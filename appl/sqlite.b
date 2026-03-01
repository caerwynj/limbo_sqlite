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
include "names.m";
	names: Names;
include "workdir.m";
	workdir: Workdir;

Sqlcli: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

out: ref Iobuf;
in: ref Iobuf;
db: ref Conn;
stderr: ref sys->FD;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	arg = load Arg Arg->PATH;
	sql = load Sqlite Sqlite->PATH;
	names = load Names Names->PATH;
	workdir = load Workdir Workdir->PATH;	
	

	if (sql == nil) {
		# Try to give a useful error if load fails
		sys->print("sqlcli: cannot load %s: %r. Ensure sqlite.dis is available.\n", Sqlite->PATH);
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
	if(dbpath != ":memory:")
		dbpath = names->rooted(workdir->init(), dbpath);
	(db, err) = sql->open(dbpath);
	if (db == nil) {
		sys->print("sqlcli: cannot open database %s: error %d\n", dbpath, err);
		raise "fail:open";
	}
	
	stderr = sys->fildes(2);
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
			#cols = count_cols(stmt);
			cols = sql->column_count(stmt);
		}
		print_row(stmt, cols);
	}
	
	if (rc != sql->DONE) {
		 sys->fprint(stderr, "Error: step failed: %d\n", rc);
	}
	
	sql->finalize(stmt);
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
