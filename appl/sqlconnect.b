implement Sqlconnect;
include "sys.m";
include "draw.m";
include "sqlite.m";
sys: Sys;
print: import sys;
sqlite: Sqlite;
Conn, Stmt: import sqlite;

Sqlconnect:module{
	init:fn(c:ref Draw->Context, argv: list of string);
};

init(nil:ref Draw->Context, argv:list of string)
{
	rc: int;
	db: ref Conn;
	stmt: ref Stmt;

	sys = load Sys Sys->PATH;
	sqlite = load Sqlite Sqlite->PATH;

	if(sqlite == nil) {
		print("sqlite no loaded\n");
		exit;
	}

	(db, rc) = sqlite->open("test.db");
	print("open %d\n", rc);

	(stmt, rc) = sqlite->prepare(db, "select * from test1");
	print("prepare %d\n", rc);

	rc = sqlite->step(stmt);
	print("step %d\n", rc);
	
	s := sqlite->column_text(stmt, 0);
	if (s != nil)
		print("column 0 %s\n", s);
	else
		print("column 0 returns nil\n");
	print("column 1 %s\n", sqlite->column_text(stmt, 1));

	rc = sqlite->step(stmt);
	print("step %d\n", rc);

	rc = sqlite->finalize(stmt);
	print("finalize %d\n", rc);

	rc = sqlite->close(db);
	print("close %d\n", rc);
}
