<$ROOT/mkconfig

all:V:
	cp module/* $ROOT/module/
	cp libinterp/* $ROOT/libinterp
	cp emu/Linux/emu $ROOT/emu/Linux/emu
	cp sqlite/sqlite3.c $ROOT/libinterp
	cp sqlite/sqlite3.h $ROOT/include
