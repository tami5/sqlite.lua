local ffi = require "ffi"
local bit = require "bit"
local luv = require "luv"
local M = {}

--- Load clib
local clib = (function()
  local path, _

  if vim then
    if vim.g.sql_clib_path then
      error [[ sqlite.lua: vim.g.sql_clib_path is deprecated. Use vim.g.sqlite_clib_path instead. ]]
    end
    path = vim.g.sqlite_clib_path
  end

  if not path then
    path, _ = luv.os_getenv "LIBSQLITE"
  end

  local clib_path = path
    or (function() --- try to find libsqlite.Linux and Macos support only.
      local os = luv.os_uname()

      local file_exists = function(file_path)
        local f = io.open(file_path, "r")
        if f ~= nil then
          io.close(f)
          return true
        else
          return false
        end
      end

      if os.sysname == "Linux" then
        local linux_paths = {
          "/usr/lib/x86_64-linux-gnu/libsqlite3.so",
          "/usr/lib/x86_64-linux-gnu/libsqlite3.so.0",
          "/usr/lib64/libsqlite3.so",
          "/usr/lib64/libsqlite3.so.0",
          "/usr/lib/libsqlite3.so",
        }
        for _, v in pairs(linux_paths) do
          if file_exists(v) then
            return v
          end
        end
      end

      if os.sysname == "Darwin" then
        return os.machine == "arm64" and "/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib"
          or "/usr/local/opt/sqlite3/lib/libsqlite3.dylib"
      end
    end)()

  return ffi.load(clib_path or "libsqlite3")
end)()

---@type sqlite_flags
M.flags = {
  -- Result codes
  ["ok"] = 0,
  ["error"] = 1,
  ["internal"] = 2,
  ["perm"] = 3,
  ["abort"] = 4,
  ["busy"] = 5,
  ["locked"] = 6,
  ["nomem"] = 7,
  ["readonly"] = 8,
  ["interrupt"] = 9,
  ["ioerr"] = 10,
  ["corrupt"] = 11,
  ["notfound"] = 12,
  ["full"] = 13,
  ["cantopen"] = 14,
  ["protocol"] = 15,
  ["empty"] = 16,
  ["schema"] = 17,
  ["toobig"] = 18,
  ["constraint"] = 19,
  ["mismatch"] = 20,
  ["misuse"] = 21,
  ["nolfs"] = 22,
  ["auth"] = 23,
  ["format"] = 24,
  ["range"] = 25,
  ["notadb"] = 26,
  ["notice"] = 27,
  ["warning"] = 28,
  ["row"] = 100,
  ["done"] = 101,
}

---@type sqlite_db.opts
M.valid_pargma = {
  ["analysis_limit"] = true,
  ["application_id"] = true,
  ["auto_vacuum"] = true,
  ["automatic_index"] = true,
  ["busy_timeout"] = true,

  ["cache_size"] = true,
  ["cache_spill"] = true,
  ["case_sensitive_like"] = true,
  ["cell_size_check"] = true,
  ["checkpoint_fullfsync"] = true,

  ["collation_list"] = true,
  ["compile_options"] = true,
  ["data_version"] = true,
  ["database_list"] = true,
  ["encoding"] = true,
  ["foreign_key_check"] = true,

  ["foreign_key_list"] = true,
  ["foreign_keys"] = true,
  ["freelist_count"] = true,
  ["fullfsync"] = true,
  ["function_list"] = true,

  ["hard_heap_limit"] = true,
  ["ignore_check_constraints"] = true,
  ["incremental_vacuum"] = true,
  ["index_info"] = true,
  ["index_list"] = true,

  ["index_xinfo"] = true,
  ["integrity_check"] = true,
  ["journal_mode"] = true,
  ["journal_size_limit"] = true,
  ["legacy_alter_table"] = true,

  ["legacy_file_format"] = true,
  ["locking_mode"] = true,
  ["max_page_count"] = true,
  ["mmap_size"] = true,
  ["module_list"] = true,
  ["optimize"] = true,

  ["page_count"] = true,
  ["page_size"] = true,
  ["parser_trace"] = true,
  ["pragma_list"] = true,
  ["query_only"] = true,
  ["quick_check"] = true,

  ["read_uncommitted"] = true,
  ["recursive_triggers"] = true,
  ["reverse_unordered_selects"] = true,
  ["schema_version"] = true,
  ["secure_delete"] = true,

  ["shrink_memory"] = true,
  ["soft_heap_limit"] = true,
  ["stats"] = true,
  ["synchronous"] = true,
  ["table_info"] = true,
  ["table_xinfo"] = true,
  ["temp_store"] = true,

  ["vdbe_trace"] = true,
  ["wal_autocheckpoint"] = true,
  ["wal_checkpoint"] = true,
  ["writable_schema"] = true,

  ["threads"] = true,
  ["trusted_schema"] = true,
  ["user_version"] = true,
  ["vdbe_addoptrace"] = true,
  ["vdbe_debug"] = true,
  ["vdbe_listing"] = true,
}

-- Extended Result Codes
M.flags["error_missing_collseq"] = bit.bor(M.flags.error, bit.lshift(1, 8))
M.flags["error_retry"] = bit.bor(M.flags.error, bit.lshift(2, 8))
M.flags["error_snapshot"] = bit.bor(M.flags.error, bit.lshift(3, 8))
M.flags["ioerr_read"] = bit.bor(M.flags.ioerr, bit.lshift(1, 8))
M.flags["ioerr_short_read"] = bit.bor(M.flags.ioerr, bit.lshift(2, 8))
M.flags["ioerr_write"] = bit.bor(M.flags.ioerr, bit.lshift(3, 8))
M.flags["ioerr_fsync"] = bit.bor(M.flags.ioerr, bit.lshift(4, 8))
M.flags["ioerr_dir_fsync"] = bit.bor(M.flags.ioerr, bit.lshift(5, 8))
M.flags["ioerr_truncate"] = bit.bor(M.flags.ioerr, bit.lshift(6, 8))
M.flags["ioerr_fstat"] = bit.bor(M.flags.ioerr, bit.lshift(7, 8))
M.flags["ioerr_unlock"] = bit.bor(M.flags.ioerr, bit.lshift(8, 8))
M.flags["ioerr_rdlock"] = bit.bor(M.flags.ioerr, bit.lshift(9, 8))
M.flags["ioerr_delete"] = bit.bor(M.flags.ioerr, bit.lshift(10, 8))
M.flags["ioerr_blocked"] = bit.bor(M.flags.ioerr, bit.lshift(11, 8))
M.flags["ioerr_nomem"] = bit.bor(M.flags.ioerr, bit.lshift(12, 8))
M.flags["ioerr_access"] = bit.bor(M.flags.ioerr, bit.lshift(13, 8))
M.flags["ioerr_checkreservedlock"] = bit.bor(M.flags.ioerr, bit.lshift(14, 8))
M.flags["ioerr_lock"] = bit.bor(M.flags.ioerr, bit.lshift(15, 8))
M.flags["ioerr_close"] = bit.bor(M.flags.ioerr, bit.lshift(16, 8))
M.flags["ioerr_dir_close"] = bit.bor(M.flags.ioerr, bit.lshift(17, 8))
M.flags["ioerr_shmopen"] = bit.bor(M.flags.ioerr, bit.lshift(18, 8))
M.flags["ioerr_shmsize"] = bit.bor(M.flags.ioerr, bit.lshift(19, 8))
M.flags["ioerr_shmlock"] = bit.bor(M.flags.ioerr, bit.lshift(20, 8))
M.flags["ioerr_shmmap"] = bit.bor(M.flags.ioerr, bit.lshift(21, 8))
M.flags["ioerr_seek"] = bit.bor(M.flags.ioerr, bit.lshift(22, 8))
M.flags["ioerr_delete_noent"] = bit.bor(M.flags.ioerr, bit.lshift(23, 8))
M.flags["ioerr_mmap"] = bit.bor(M.flags.ioerr, bit.lshift(24, 8))
M.flags["ioerr_gettemppath"] = bit.bor(M.flags.ioerr, bit.lshift(25, 8))
M.flags["ioerr_convpath"] = bit.bor(M.flags.ioerr, bit.lshift(26, 8))
M.flags["ioerr_vnode"] = bit.bor(M.flags.ioerr, bit.lshift(27, 8))
M.flags["ioerr_auth"] = bit.bor(M.flags.ioerr, bit.lshift(28, 8))
M.flags["ioerr_begin_atomic"] = bit.bor(M.flags.ioerr, bit.lshift(29, 8))
M.flags["ioerr_commit_atomic"] = bit.bor(M.flags.ioerr, bit.lshift(30, 8))
M.flags["ioerr_rollback_atomic"] = bit.bor(M.flags.ioerr, bit.lshift(31, 8))
M.flags["ioerr_data"] = bit.bor(M.flags.ioerr, bit.lshift(32, 8))
M.flags["ioerr_corruptfs"] = bit.bor(M.flags.ioerr, bit.lshift(33, 8))
M.flags["locked_sharedcache"] = bit.bor(M.flags.locked, bit.lshift(1, 8))
M.flags["locked_vtab"] = bit.bor(M.flags.locked, bit.lshift(2, 8))
M.flags["busy_recovery"] = bit.bor(M.flags.busy, bit.lshift(1, 8))
M.flags["busy_snapshot"] = bit.bor(M.flags.busy, bit.lshift(2, 8))
M.flags["busy_timeout"] = bit.bor(M.flags.busy, bit.lshift(3, 8))
M.flags["cantopen_notempdir"] = bit.bor(M.flags.cantopen, bit.lshift(1, 8))
M.flags["cantopen_isdir"] = bit.bor(M.flags.cantopen, bit.lshift(2, 8))
M.flags["cantopen_fullpath"] = bit.bor(M.flags.cantopen, bit.lshift(3, 8))
M.flags["cantopen_convpath"] = bit.bor(M.flags.cantopen, bit.lshift(4, 8))
M.flags["cantopen_dirtywal"] = bit.bor(M.flags.cantopen, bit.lshift(5, 8))
M.flags["cantopen_symlink"] = bit.bor(M.flags.cantopen, bit.lshift(6, 8))
M.flags["corrupt_vtab"] = bit.bor(M.flags.corrupt, bit.lshift(1, 8))
M.flags["corrupt_sequence"] = bit.bor(M.flags.corrupt, bit.lshift(2, 8))
M.flags["corrupt_index"] = bit.bor(M.flags.corrupt, bit.lshift(3, 8))
M.flags["readonly_recovery"] = bit.bor(M.flags.readonly, bit.lshift(1, 8))
M.flags["readonly_cantlock"] = bit.bor(M.flags.readonly, bit.lshift(2, 8))
M.flags["readonly_rollback"] = bit.bor(M.flags.readonly, bit.lshift(3, 8))
M.flags["readonly_dbmoved"] = bit.bor(M.flags.readonly, bit.lshift(4, 8))
M.flags["readonly_cantinit"] = bit.bor(M.flags.readonly, bit.lshift(5, 8))
M.flags["readonly_directory"] = bit.bor(M.flags.readonly, bit.lshift(6, 8))
M.flags["abort_rollback"] = bit.bor(M.flags.abort, bit.lshift(2, 8))
M.flags["constraint_check"] = bit.bor(M.flags.constraint, bit.lshift(1, 8))
M.flags["constraint_commithook"] = bit.bor(M.flags.constraint, bit.lshift(2, 8))
M.flags["constraint_foreignkey"] = bit.bor(M.flags.constraint, bit.lshift(3, 8))
M.flags["constraint_function"] = bit.bor(M.flags.constraint, bit.lshift(4, 8))
M.flags["constraint_notnull"] = bit.bor(M.flags.constraint, bit.lshift(5, 8))
M.flags["constraint_primarykey"] = bit.bor(M.flags.constraint, bit.lshift(6, 8))
M.flags["constraint_trigger"] = bit.bor(M.flags.constraint, bit.lshift(7, 8))
M.flags["constraint_unique"] = bit.bor(M.flags.constraint, bit.lshift(8, 8))
M.flags["constraint_vtab"] = bit.bor(M.flags.constraint, bit.lshift(9, 8))
M.flags["constraint_rowid"] = bit.bor(M.flags.constraint, bit.lshift(10, 8))
M.flags["constraint_pinned"] = bit.bor(M.flags.constraint, bit.lshift(11, 8))
M.flags["notice_recover_wal"] = bit.bor(M.flags.notice, bit.lshift(1, 8))
M.flags["notice_recover_rollback"] = bit.bor(M.flags.notice, bit.lshift(2, 8))
M.flags["warning_autoindex"] = bit.bor(M.flags.warning, bit.lshift(1, 8))
M.flags["auth_user"] = bit.bor(M.flags.auth, bit.lshift(1, 8))
M.flags["ok_load_permanently"] = bit.bor(M.flags.ok, bit.lshift(1, 8))
M.flags["ok_symlink"] = bit.bor(M.flags.ok, bit.lshift(2, 8))

-- Flags for file open operations.
M.flags["open_readonly"] = 0x00000001
M.flags["open_readwrite"] = 0x00000002
M.flags["open_create"] = 0x00000004
M.flags["open_deleteonclose"] = 0x00000008
M.flags["open_exclusive"] = 0x00000010
M.flags["open_autoproxy"] = 0x00000020
M.flags["open_uri"] = 0x00000040
M.flags["open_memory"] = 0x00000080
M.flags["open_main_db"] = 0x00000100
M.flags["open_temp_db"] = 0x00000200
M.flags["open_transient_db"] = 0x00000400
M.flags["open_main_journal"] = 0x00000800
M.flags["open_temp_journal"] = 0x00001000
M.flags["open_subjournal"] = 0x00002000
M.flags["open_super_journal"] = 0x00004000
M.flags["open_nomutex"] = 0x00008000
M.flags["open_fullmutex"] = 0x00010000
M.flags["open_sharedcache"] = 0x00020000
M.flags["open_privatecache"] = 0x00040000
M.flags["open_wal"] = 0x00080000
M.flags["open_nofollow"] = 0x01000000

-- Fundamental Datatypes
M.flags["integer"] = 1
M.flags["float"] = 2
M.flags["text"] = 3
M.flags["blob"] = 4
M.flags["null"] = 5

-- Types
ffi.cdef [[
  typedef struct sqlite3 sqlite3;

  typedef __int64 sqlite_int64;
  typedef unsigned __int64 sqlite_uint64;

  typedef sqlite_int64 sqlite3_int64;
  typedef sqlite_uint64 sqlite3_uint64;

  typedef struct sqlite3_file sqlite3_file;
  typedef struct sqlite3_stmt sqlite3_stmt;

  typedef struct sqlite3_value sqlite3_value;
  typedef struct sqlite3_context sqlite3_context;

  typedef struct sqlite3_vtab sqlite3_vtab;
  typedef struct sqlite3_vtab_cursor sqlite3_vtab_cursor;

  typedef struct sqlite3_blob sqlite3_blob;

  typedef struct sqlite3_str sqlite3_str;
  typedef struct sqlite3_backup sqlite3_backup;
]]

-- Functions
ffi.cdef [[
  const char *sqlite3_libversion(void);
  const char *sqlite3_sourceid(void);
  int sqlite3_libversion_number(void);

  int sqlite3_threadsafe(void);

  int sqlite3_close(sqlite3*);
  int sqlite3_close_v2(sqlite3*);

  int sqlite3_exec(sqlite3*, const char *sql, int (*callback)(void*,int,char**,char**), void *, char **errmsg);

  int sqlite3_initialize(void);
  int sqlite3_shutdown(void);
  int sqlite3_os_init(void);
  int sqlite3_os_end(void);

  int sqlite3_config(int, ...);
  int sqlite3_db_config(sqlite3*, int op, ...);

  int sqlite3_extended_result_codes(sqlite3*, int onoff);

  sqlite3_int64 sqlite3_last_insert_rowid(sqlite3*);
  void sqlite3_set_last_insert_rowid(sqlite3*,sqlite3_int64);

  int sqlite3_changes(sqlite3*);
  int sqlite3_total_changes(sqlite3*);

  void sqlite3_interrupt(sqlite3*);

  int sqlite3_complete(const char *sql);
  int sqlite3_complete16(const void *sql);

  int sqlite3_busy_handler(sqlite3*,int(*)(void*,int),void*);
  int sqlite3_busy_timeout(sqlite3*, int ms);

  int sqlite3_get_table(sqlite3 *db, const char *zSql, char ***pazResult, int *pnRow, int *pnColumn, char **pzErrmsg);
  void sqlite3_free_table(char **result);

  sqlite3_int64 sqlite3_memory_used(void);
  sqlite3_int64 sqlite3_memory_highwater(int resetFlag);

  void sqlite3_randomness(int N, void *P);

  int sqlite3_set_authorizer(sqlite3*, int (*xAuth)(void*,int,const char*,const char*,const char*,const char*),
                  void *pUserData);

  int sqlite3_trace_v2(sqlite3*, unsigned uMask, int(*xCallback)(unsigned,void*,void*,void*), void *pCtx);

  void sqlite3_progress_handler(sqlite3*, int, int(*)(void*), void*);

  int sqlite3_open(const char *filename, sqlite3 **ppDb);
  int sqlite3_open16(const void *filename, sqlite3 **ppDb);
  int sqlite3_open_v2(const char *filename, sqlite3 **ppDb, int flags, const char *zVfs);

  const char *sqlite3_uri_parameter(const char *zFilename, const char *zParam);
  int sqlite3_uri_boolean(const char *zFile, const char *zParam, int bDefault);
  sqlite3_int64 sqlite3_uri_int64(const char*, const char*, sqlite3_int64);
  const char *sqlite3_uri_key(const char *zFilename, int N);

  const char *sqlite3_filename_database(const char*);
  const char *sqlite3_filename_journal(const char*);
  const char *sqlite3_filename_wal(const char*);

  sqlite3_file *sqlite3_database_file_object(const char*);

  char *sqlite3_create_filename(const char *zDatabase, const char *zJournal, const char *zWal, int nParam,
                  const char **azParam);
  void sqlite3_free_filename(char*);

  int sqlite3_errcode(sqlite3 *db);
  int sqlite3_extended_errcode(sqlite3 *db);
  const char *sqlite3_errmsg(sqlite3*);
  const void *sqlite3_errmsg16(sqlite3*);
  const char *sqlite3_errstr(int);

  int sqlite3_limit(sqlite3*, int id, int newVal);

  int sqlite3_prepare(sqlite3 *db, const char *zSql, int nByte, sqlite3_stmt **ppStmt, const char **pzTail);
  int sqlite3_prepare_v2(sqlite3 *db, const char *zSql, int nByte, sqlite3_stmt **ppStmt, const char **pzTail);
  int sqlite3_prepare_v3(sqlite3 *db, const char *zSql, int nByte, unsigned int prepFlags, sqlite3_stmt **ppStmt,
                  const char **pzTail);
  int sqlite3_prepare16(sqlite3 *db, const void *zSql, int nByte, sqlite3_stmt **ppStmt, const void **pzTail);
  int sqlite3_prepare16_v2(sqlite3 *db, const void *zSql, int nByte, sqlite3_stmt **ppStmt, const void **pzTail);
  int sqlite3_prepare16_v3(sqlite3 *db, const void *zSql, int nByte, unsigned int prepFlags, sqlite3_stmt **ppStmt,
                  const void **pzTail);

  const char *sqlite3_sql(sqlite3_stmt *pStmt);
  char *sqlite3_expanded_sql(sqlite3_stmt *pStmt);
  const char *sqlite3_normalized_sql(sqlite3_stmt *pStmt);

  int sqlite3_stmt_readonly(sqlite3_stmt *pStmt);
  int sqlite3_stmt_isexplain(sqlite3_stmt *pStmt);
  int sqlite3_stmt_busy(sqlite3_stmt*);

  int sqlite3_bind_blob(sqlite3_stmt*, int, const void*, int n, void(*)(void*));
  int sqlite3_bind_blob64(sqlite3_stmt*, int, const void*, sqlite3_uint64,
                  void(*)(void*));
  int sqlite3_bind_double(sqlite3_stmt*, int, double);
  int sqlite3_bind_int(sqlite3_stmt*, int, int);
  int sqlite3_bind_int64(sqlite3_stmt*, int, sqlite3_int64);
  int sqlite3_bind_null(sqlite3_stmt*, int);
  int sqlite3_bind_text(sqlite3_stmt*,int,const char*,int,void(*)(void*));
  int sqlite3_bind_text16(sqlite3_stmt*, int, const void*, int, void(*)(void*));
  int sqlite3_bind_text64(sqlite3_stmt*, int, const char*, sqlite3_uint64,
                  void(*)(void*), unsigned char encoding);
  int sqlite3_bind_value(sqlite3_stmt*, int, const sqlite3_value*);
  int sqlite3_bind_pointer(sqlite3_stmt*, int, void*, const char*,void(*)(void*));
  int sqlite3_bind_zeroblob(sqlite3_stmt*, int, int n);
  int sqlite3_bind_zeroblob64(sqlite3_stmt*, int, sqlite3_uint64);

  int sqlite3_bind_parameter_count(sqlite3_stmt*);
  const char *sqlite3_bind_parameter_name(sqlite3_stmt*, int);
  int sqlite3_bind_parameter_index(sqlite3_stmt*, const char *zName);
  int sqlite3_clear_bindings(sqlite3_stmt*);
  int sqlite3_column_count(sqlite3_stmt *pStmt);
  const char *sqlite3_column_name(sqlite3_stmt*, int N);
  const void *sqlite3_column_name16(sqlite3_stmt*, int N);

  const char *sqlite3_column_database_name(sqlite3_stmt*,int);
  const void *sqlite3_column_database_name16(sqlite3_stmt*,int);
  const char *sqlite3_column_table_name(sqlite3_stmt*,int);
  const void *sqlite3_column_table_name16(sqlite3_stmt*,int);
  const char *sqlite3_column_origin_name(sqlite3_stmt*,int);
  const void *sqlite3_column_origin_name16(sqlite3_stmt*,int);

  const char *sqlite3_column_decltype(sqlite3_stmt*,int);
  const void *sqlite3_column_decltype16(sqlite3_stmt*,int);

  int sqlite3_step(sqlite3_stmt*);
  int sqlite3_data_count(sqlite3_stmt *pStmt);

  const void *sqlite3_column_blob(sqlite3_stmt*, int iCol);
  double sqlite3_column_double(sqlite3_stmt*, int iCol);
  int sqlite3_column_int(sqlite3_stmt*, int iCol);
  sqlite3_int64 sqlite3_column_int64(sqlite3_stmt*, int iCol);
  const unsigned char *sqlite3_column_text(sqlite3_stmt*, int iCol);
  const void *sqlite3_column_text16(sqlite3_stmt*, int iCol);
  sqlite3_value *sqlite3_column_value(sqlite3_stmt*, int iCol);
  int sqlite3_column_bytes(sqlite3_stmt*, int iCol);
  int sqlite3_column_bytes16(sqlite3_stmt*, int iCol);
  int sqlite3_column_type(sqlite3_stmt*, int iCol);

  int sqlite3_finalize(sqlite3_stmt *pStmt);
  int sqlite3_reset(sqlite3_stmt *pStmt);

  const void *sqlite3_value_blob(sqlite3_value*);
  double sqlite3_value_double(sqlite3_value*);
  int sqlite3_value_int(sqlite3_value*);
  sqlite3_int64 sqlite3_value_int64(sqlite3_value*);
  void *sqlite3_value_pointer(sqlite3_value*, const char*);
  const unsigned char *sqlite3_value_text(sqlite3_value*);
  const void *sqlite3_value_text16(sqlite3_value*);
  const void *sqlite3_value_text16le(sqlite3_value*);
  const void *sqlite3_value_text16be(sqlite3_value*);
  int sqlite3_value_bytes(sqlite3_value*);
  int sqlite3_value_bytes16(sqlite3_value*);
  int sqlite3_value_type(sqlite3_value*);
  int sqlite3_value_numeric_type(sqlite3_value*);
  int sqlite3_value_nochange(sqlite3_value*);
  int sqlite3_value_frombind(sqlite3_value*);

  unsigned int sqlite3_value_subtype(sqlite3_value*);

  sqlite3_value *sqlite3_value_dup(const sqlite3_value*);
  void sqlite3_value_free(sqlite3_value*);

  void *sqlite3_aggregate_context(sqlite3_context*, int nBytes);

  void *sqlite3_user_data(sqlite3_context*);

  sqlite3 *sqlite3_context_db_handle(sqlite3_context*);

  void *sqlite3_get_auxdata(sqlite3_context*, int N);
  void sqlite3_set_auxdata(sqlite3_context*, int N, void*, void (*)(void*));

  void sqlite3_result_blob(sqlite3_context*, const void*, int, void(*)(void*));
  void sqlite3_result_blob64(sqlite3_context*,const void*,
                  sqlite3_uint64,void(*)(void*));
  void sqlite3_result_double(sqlite3_context*, double);
  void sqlite3_result_error(sqlite3_context*, const char*, int);
  void sqlite3_result_error16(sqlite3_context*, const void*, int);
  void sqlite3_result_error_toobig(sqlite3_context*);
  void sqlite3_result_error_nomem(sqlite3_context*);
  void sqlite3_result_error_code(sqlite3_context*, int);
  void sqlite3_result_int(sqlite3_context*, int);
  void sqlite3_result_int64(sqlite3_context*, sqlite3_int64);
  void sqlite3_result_null(sqlite3_context*);
  void sqlite3_result_text(sqlite3_context*, const char*, int, void(*)(void*));
  void sqlite3_result_text64(sqlite3_context*, const char*,sqlite3_uint64,
                  void(*)(void*), unsigned char encoding);
  void sqlite3_result_text16(sqlite3_context*, const void*, int, void(*)(void*));
  void sqlite3_result_text16le(sqlite3_context*, const void*, int,void(*)(void*));
  void sqlite3_result_text16be(sqlite3_context*, const void*, int,void(*)(void*));
  void sqlite3_result_value(sqlite3_context*, sqlite3_value*);
  void sqlite3_result_pointer(sqlite3_context*, void*,const char*,void(*)(void*));
  void sqlite3_result_zeroblob(sqlite3_context*, int n);
  int sqlite3_result_zeroblob64(sqlite3_context*, sqlite3_uint64 n);

  void sqlite3_result_subtype(sqlite3_context*,unsigned int);

  int sqlite3_sleep(int);

  int sqlite3_get_autocommit(sqlite3*);
  sqlite3 *sqlite3_db_handle(sqlite3_stmt*);
  const char *sqlite3_db_filename(sqlite3 *db, const char *zDbName);
  int sqlite3_db_readonly(sqlite3 *db, const char *zDbName);
  int sqlite3_txn_state(sqlite3*,const char *zSchema);

  sqlite3_stmt *sqlite3_next_stmt(sqlite3 *pDb, sqlite3_stmt *pStmt);

  void *sqlite3_commit_hook(sqlite3*, int(*)(void*), void*);
  void *sqlite3_rollback_hook(sqlite3*, void(*)(void *), void*);

  void *sqlite3_update_hook(sqlite3*, void(*)(void *,int ,char const *,char const *,sqlite3_int64), void*);

  int sqlite3_enable_shared_cache(int);
  int sqlite3_release_memory(int);
  int sqlite3_db_release_memory(sqlite3*);

  sqlite3_int64 sqlite3_soft_heap_limit64(sqlite3_int64 N);
  sqlite3_int64 sqlite3_hard_heap_limit64(sqlite3_int64 N);

  int sqlite3_table_column_metadata(sqlite3 *db, const char *zDbName, const char *zTableName, const char *zColumnName,
                  char const **pzDataType, char const **pzCollSeq, int *pNotNull, int *pPrimaryKey, int *pAutoinc);

  int sqlite3_load_extension(sqlite3 *db, const char *zFile, const char *zProc, char **pzErrMsg);

  int sqlite3_enable_load_extension(sqlite3 *db, int onoff);
  int sqlite3_auto_extension(void(*xEntryPoint)(void));
  int sqlite3_cancel_auto_extension(void(*xEntryPoint)(void));
  void sqlite3_reset_auto_extension(void);

  int sqlite3_declare_vtab(sqlite3*, const char *zSQL);
  int sqlite3_overload_function(sqlite3*, const char *zFuncName, int nArg);

  int sqlite3_blob_open(sqlite3*, const char *zDb, const char *zTable, const char *zColumn, sqlite3_int64 iRow,
                  int flags, sqlite3_blob **ppBlob);
  int sqlite3_blob_reopen(sqlite3_blob *, sqlite3_int64);
  int sqlite3_blob_close(sqlite3_blob *);
  int sqlite3_blob_bytes(sqlite3_blob *);
  int sqlite3_blob_read(sqlite3_blob *, void *Z, int N, int iOffset);
  int sqlite3_blob_write(sqlite3_blob *, const void *z, int n, int iOffset);

  int sqlite3_file_control(sqlite3*, const char *zDbName, int op, void*);
  int sqlite3_test_control(int op, ...);

  int sqlite3_keyword_count(void);
  int sqlite3_keyword_name(int,const char**,int*);
  int sqlite3_keyword_check(const char*,int);

  sqlite3_str *sqlite3_str_new(sqlite3*);
  char *sqlite3_str_finish(sqlite3_str*);

  void sqlite3_str_appendf(sqlite3_str*, const char *zFormat, ...);
  void sqlite3_str_vappendf(sqlite3_str*, const char *zFormat, va_list);
  void sqlite3_str_append(sqlite3_str*, const char *zIn, int N);
  void sqlite3_str_appendall(sqlite3_str*, const char *zIn);
  void sqlite3_str_appendchar(sqlite3_str*, int N, char C);
  void sqlite3_str_reset(sqlite3_str*);

  int sqlite3_str_errcode(sqlite3_str*);
  int sqlite3_str_length(sqlite3_str*);
  char *sqlite3_str_value(sqlite3_str*);

  int sqlite3_status(int op, int *pCurrent, int *pHighwater, int resetFlag);
  int sqlite3_status64(int op, sqlite3_int64 *pCurrent, sqlite3_int64 *pHighwater, int resetFlag);

  int sqlite3_db_status(sqlite3*, int op, int *pCur, int *pHiwtr, int resetFlg);
  int sqlite3_stmt_status(sqlite3_stmt*, int op,int resetFlg);

  sqlite3_backup *sqlite3_backup_init(sqlite3 *pDest, const char *zDestName, sqlite3 *pSource, const char *zSourceName);
  int sqlite3_backup_step(sqlite3_backup *p, int nPage);
  int sqlite3_backup_finish(sqlite3_backup *p);
  int sqlite3_backup_remaining(sqlite3_backup *p);
  int sqlite3_backup_pagecount(sqlite3_backup *p);

  int sqlite3_unlock_notify(sqlite3 *pBlocked, void (*xNotify)(void **apArg, int nArg), void *pNotifyArg);

  int sqlite3_stricmp(const char *, const char *);
  int sqlite3_strnicmp(const char *, const char *, int);

  int sqlite3_strglob(const char *zGlob, const char *zStr);

  int sqlite3_strlike(const char *zGlob, const char *zStr, unsigned int cEsc);

  void sqlite3_log(int iErrCode, const char *zFormat, ...);

  void *sqlite3_wal_hook(sqlite3*, int(*)(void *,sqlite3*,const char*,int), void*);

  int sqlite3_wal_autocheckpoint(sqlite3 *db, int N);
  int sqlite3_wal_checkpoint(sqlite3 *db, const char *zDb);

  int sqlite3_wal_checkpoint_v2(sqlite3 *db, const char *zDb, int eMode, int *pnLog, int *pnCkpt);

  int sqlite3_vtab_config(sqlite3*, int op, ...);

  int sqlite3_vtab_on_conflict(sqlite3 *);
  int sqlite3_vtab_nochange(sqlite3_context*);

  int sqlite3_stmt_scanstatus(sqlite3_stmt *pStmt, int idx, int iScanStatusOp, void *pOut);

  void sqlite3_stmt_scanstatus_reset(sqlite3_stmt*);
  int sqlite3_db_cacheflush(sqlite3*);
  int sqlite3_system_errno(sqlite3*);

  unsigned char *sqlite3_serialize(sqlite3 *db, const char *zSchema, sqlite3_int64 *piSize, unsigned int mFlags);
  int sqlite3_deserialize(sqlite3 *db, const char *zSchema, unsigned char *pData, sqlite3_int64 szDb,
                  sqlite3_int64 szBuf, unsigned mFlags);
]]

---@class sqlite3 @sqlite3 db object
---@class sqlite_blob* @sqlite3 blob object

M.to_str = function(ptr, len)
  if ptr == nil then
    return
  end
  return ffi.string(ptr, len)
end

M.type_of = function(ptr)
  if ptr == nil then
    return
  end
  return ffi.typeof(ptr)
end

M.get_new_db_ptr = function()
  return ffi.new "sqlite3*[1]"
end

M.get_new_stmt_ptr = function()
  return ffi.new "sqlite3_stmt*[1]"
end

M.get_new_blob_ptr = function()
  return ffi.new "sqlite3_blob*[1]"
end

M.type_of_db_ptr = ffi.typeof "sqlite3*"
M.type_of_stmt_ptr = ffi.typeof "sqlite3_stmt*"
M.type_of_exec_ptr = ffi.typeof "int (*)(void*,int,char**,char**)"
M.type_of_blob_ptr = ffi.typeof "sqlite3_blob*"

--- Wrapper around clib.exec for convenience.
---@param conn_ptr sqlite connction ptr
---@param statement string: statement to be executed.
---@return table: stmt object
M.exec_stmt = function(conn_ptr, statement)
  return clib.sqlite3_exec(conn_ptr, statement, nil, nil, nil)
end

--- Execute a manipulation sql statement within begin and commit block
---@param conn_ptr sqlite connction ptr
---@param fn func()
M.wrap_stmts = function(conn_ptr, fn)
  M.exec_stmt(conn_ptr, "BEGIN")
  local res = fn()
  M.exec_stmt(conn_ptr, "COMMIT")
  return res
end

---Get last error msg
---@param conn_ptr sqlite connction ptr
---@return string: sqlite error msg
M.last_errmsg = function(conn_ptr)
  return M.to_str(clib.sqlite3_errmsg(conn_ptr))
end

---Get last error code
---@param conn_ptr sqlite connction ptr
---@return number: sqlite error number
M.last_errcode = function(conn_ptr)
  return clib.sqlite3_errcode(conn_ptr)
end

-- Open Modes
M.open_modes = {
  ["ro"] = bit.bor(M.flags.open_readonly, M.flags.open_uri),
  ["rw"] = bit.bor(M.flags.open_readwrite, M.flags.open_uri),
  ["rwc"] = bit.bor(M.flags.open_readwrite, M.flags.open_create, M.flags.open_uri),
}

---Create new connection and modify `sqlite_db` object
---@param uri string
---@param opts sqlite_db.opts
---@return sqlite_blob*
M.connect = function(uri, opts)
  opts = opts or {}
  local conn = M.get_new_db_ptr()
  local open_mode = opts.open_mode
  opts.open_mode = nil
  if type(open_mode) == "table" then
    open_mode = bit.bor(unpack(open_mode))
  else
    open_mode = M.open_modes[open_mode or "rwc"]
  end

  local code = clib.sqlite3_open_v2(uri, conn, open_mode, nil)

  if code ~= M.flags.ok then
    error(("sqlite.lua: couldn't connect to sql database, ERR: %s"):format(M.last_errmsg(conn[0])))
  end

  for k, v in pairs(opts) do
    if not M.valid_pargma[k] then
      error("sqlite.lua: " .. k .. " is not a valid pragma")
    end
    if type(k) == "boolean" then
      k = "ON"
    end
    M.exec_stmt(conn[0], ("pragma %s = %s"):format(k, v))
  end

  return conn[0]
end

M = setmetatable(M, {
  __index = function(_, k)
    return clib["sqlite3_" .. k]
  end,
})

return M
