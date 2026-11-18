#ifndef CSQLITE_SHIM_H
#define CSQLITE_SHIM_H

#include <sqlite3.h>

/// `SQLITE_TRANSIENT` is a cast macro that Swift cannot import. It tells SQLite
/// to copy bound text and blobs before the bind call returns.
static inline sqlite3_destructor_type csqlite_transient(void) {
    return SQLITE_TRANSIENT;
}

#endif
