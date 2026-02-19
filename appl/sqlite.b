implement Sqlcli;

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "arg.m";
	arg: Arg;
include "sqlite.m";
	sql: Sqlite;
	Conn, Stmt: import sql;

Sqlcli: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

out: ref Iobuf;
in: ref Iobuf;
db: ref Conn;
stderr: ref sys->FD;

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	arg = load Arg Arg->PATH;
	sql = load Sqlite Sqlite->PATH;
	
	stderr = sys->fildes(2);

	if (sql == nil) {
		# Try to give a useful error if load fails
		sys->fprint(stderr, "sqlcli: cannot load %s: %r. Ensure sqlite.dis is available.\n", Sqlite->PATH);
		raise "fail:load";
	}

	arg->init(args);
	arg->setusage("sqlite [database]");
	
	dbpath := ":memory:";
	
	while((opt := arg->opt()) != 0) {
		case opt {
		* =>
			arg->usage();
		}
	}
	
	args = arg->argv();
	if (len args > 0)
		dbpath = hd args;
	
	err: int;
	(db, err) = sql->open(dbpath);
	if (db == nil) {
		sys->fprint(stderr, "sqlcli: cannot open database %s: error %d\n", dbpath, err);
		raise "fail:open";
	}
	
	out = bufio->fopen(sys->fildes(1), Bufio->OWRITE);
	in = bufio->fopen(sys->fildes(0), Bufio->OREAD);
	
	sys->print("SQLite version 3.x (Limbo wrapper)\n");
	sys->print("Enter \".help\" for usage hints.\n");
	
	repl();
	
	sql->close(db);
}

repl()
{
	prompt := "sqlite> ";
	sb := "";
	
	while (1) {
		out.puts(prompt);
		out.flush();
		
		s := in.gets('\n');
		if (s == nil)
			break;
			
		# Trim trailing newline
		if (len s > 0 && s[len s - 1] == '\n')
			s = s[0:len s - 1];
			
		is_continuation := (prompt == "   ...> ");

		# Check for dot commands if current buffer is empty (start of command)
		if (!is_continuation && len sb == 0 && len s > 0 && s[0] == '.') {
			if (do_dot_command(s))
				break;
			continue;
		}

		sb += s;
		
		if (ends_with_semicolon(sb)) {
			exec(sb);
			sb = "";
			prompt = "sqlite> ";
		} else {
			sb += " ";
			prompt = "   ...> ";
		}
	}
}

ends_with_semicolon(s: string): int
{
	for (i := len s - 1; i >= 0; i--) {
		c := s[i];
		if (c == ' ' || c == '\t' || c == '\n' || c == '\r')
			continue;
		if (c == ';')
			return 1;
		return 0;
	}
	return 0;
}

do_dot_command(cmd: string): int
{
	(nil, tokens) := sys->tokenize(cmd, " \t");
	if (tokens == nil) return 0;
	
	case hd tokens {
		".quit" or ".exit" =>
			return 1;
		".help" =>
			out.puts(".exit      Exit this program\n");
			out.puts(".help      Show this message\n");
			out.puts(".quit      Exit this program\n");
			out.puts(".tables    List names of tables\n");
			out.puts(".schema    Show the CREATE statements\n");
			out.flush();
		".tables" =>
			exec("SELECT name FROM sqlite_master WHERE type='table';");
		".schema" =>
			exec("SELECT sql FROM sqlite_master;");
		* =>
			sys->fprint(stderr, "Error: unknown command or invalid arguments:  \"%s\". Enter \".help\" for help\n", cmd);
	}
	return 0;
}

exec(query: string)
{
	(stmt, err) := sql->prepare(db, query);
	if (stmt == nil) {
		if (err != 0) 
			sys->fprint(stderr, "Error: prepare failed: %d\n", err);
		return;
	}

	cols := -1; 
	
	while ((rc := sql->step(stmt)) == sql->ROW) {
		if (cols == -1) {
			cols = count_cols(stmt);
		}
		print_row(stmt, cols);
	}
	
	if (rc != sql->DONE) {
		 sys->fprint(stderr, "Error: step failed: %d\n", rc);
	}
	
	sql->finalize(stmt);
}

count_cols(stmt: ref Stmt): int
{
	# Heuristic: Probe columns to determine count since interface is missing it
	# Most queries have few columns. Limit to 100 for sanity.
	for (i := 0; i < 100; i++) {
		# Fast path: existing column with bytes > 0
		if (sql->column_bytes(stmt, i) > 0)
			continue;
			
		# Slow path: probe specifically for existence
		# This is necessary because column_text/blob crash on OOB
		if (!probe_safe(stmt, i)) 
			return i;
	}
	return 100;
}

probe_safe(stmt: ref Stmt, col: int): int
{
	fds := array[2] of ref sys->FD;
	if (sys->pipe(fds) < 0) return 0;
	
	sync := chan of int;
	spawn prober(sync, fds[1], stmt, col);
	<-sync; # Wait for prober to start
	
	buf := array[1] of byte;
	n := sys->read(fds[0], buf, 1);
	
	# Cleanup FDs
	fds[0] = nil;
	fds[1] = nil;
	
	if (n > 0) return 1;
	return 0;
}

prober(sync: chan of int, fd: ref sys->FD, stmt: ref Stmt, col: int)
{
	# New Process Group to isolate crashes
	sys->pctl(sys->NEWPGRP|sys->FORKFD, nil);
	
	# Try to suppress stderr to hide "Broken" messages from debug output
	nullfd := sys->open("/dev/null", sys->OWRITE);
	if (nullfd != nil)
		sys->dup(nullfd.fd, 2);
	
	sync <-= 1; # Signal start
	
	# This line will crash if col is OOB
	s := sql->column_text(stmt, col);
	
	# If we survived, signal success
	sys->write(fd, array[] of {byte 1}, 1);
}

print_row(stmt: ref Stmt, cols: int)
{
	sep := "";
	for (i := 0; i < cols; i++) {
		out.puts(sep);
		val := sql->column_text(stmt, i);
		if (val != nil)
			out.puts(val);
		sep = "|";
	}
	out.puts("\n");
	out.flush();
}
