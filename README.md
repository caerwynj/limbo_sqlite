# limbo_sqlite

This is a language binding of SQLite to Limbo programming language.

Download the sqlite3 source.
Extract the source and name the folder ./sqlite/

Apply the sqlite_os_unix.patch
```
patch ./sqlite/src/os_unix.c sqlite_os_unix.patch
```

Build the amalgamation files for sqlite3.c and sqlite3.h by following the instructions from the Sqlite website.

Run `mk` to copy all the files to the inferno64 root folder. 
Make sure $ROOT is set to the root of inferno64.

This will copy sqlite3.c to /libinterp and sqlite3.h to the /include folder of the inferno distribution.

Then build the Inferno64 emu.

## NOTE
The sqlite3 turns relative paths into absolute paths for the host system.
But the patched os_unix.c opens files relative to the Inferno OS namespace.
So always give the sqlite->open() function absolute paths from within the Inferno OS namespace.

