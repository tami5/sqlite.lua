local M = {}
local luv = require "luv"
local a = require "sqlite.assert"
local u = require "sqlite.utils"
local fmt = string.format
local P = require "sqlite.parser"

---Get a table schema, or execute a given function to get it
---@param tbl_name string
---@param db sqlite_db
M.get_schema = function(tbl_name, db)
  local schema = db.tbl_schemas[tbl_name]
  if schema then
    return schema
  end
  db.tbl_schemas[tbl_name] = db:schema(tbl_name)
  return db.tbl_schemas[tbl_name]
end

---Check and alter table schema, limited to simple renames and alteration of key schema
---@param o sqlite_tbl
---@param valid_schema any
M.check_for_auto_alter = function(o, valid_schema)
  local with_foregin_key = false

  if not valid_schema then
    return
  end

  for _, def in pairs(o.tbl_schema) do
    if type(def) == "table" and def.reference then
      with_foregin_key = true
      break
    end
  end

  local get = fmt("select * from sqlite_master where name = '%s'", o.name)

  local stmt = o.tbl_exists and o.db:eval(get) or nil
  if type(stmt) ~= "table" then
    return
  end

  local origin, parsed = stmt[1].sql, P.create(o.name, o.tbl_schema, true)
  if origin == parsed then
    return
  end

  local ok, cmd = pcall(P.table_alter_key_defs, o.name, o.tbl_schema, o.db:schema(o.name))
  if not ok then
    print(cmd)
    return
  end

  o.db:execute(cmd)
  o.db_schema = o.db:schema(o.name)

  if with_foregin_key then
    o.db:execute "PRAGMA foreign_keys = ON;"
    o.db.opts.foreign_keys = true
  end
end

---Run tbl functions
---@param func function: wrapped function to run
---@param o sqlite_tbl
---@return any
M.run = function(func, o)
  func = func or function() end
  a.should_have_db_object(o.db, o.name)
  local exec = function()
    local valid_schema = o.tbl_schema and next(o.tbl_schema) ~= nil

    --- Run once pre-init
    if o.tbl_exists == nil then
      o.tbl_exists = o.db:exists(o.name)
      o.mtime = o.db.uri and (luv.fs_stat(o.db.uri) or { mtime = {} }).mtime.sec or nil
      rawset(
        o,
        "has_content",
        o.tbl_exists and o.db:eval(fmt("select count(*) from %s", o.name))[1]["count(*)"] ~= 0 or 0
      )
      -- o.has_content =
      M.check_for_auto_alter(o, valid_schema)
    end

    --- Run when tbl doesn't exists anymore
    if o.tbl_exists == false and valid_schema then
      o.tbl_schema.ensure = u.if_nil(o.tbl_schema.ensure, true)
      o.db:create(o.name, o.tbl_schema)
      o.db_schema = o.db:schema(o.name)
    end

    --- Run once when we don't have schema
    if not o.db_schema then
      o.db_schema = o.db:schema(o.name)
    end

    rawset(o, "last_id", o.db:last_insert_rowid())
    --- Run wrapped function
    return func()
  end

  if o.db.closed then
    return o.db:with_open(exec)
  end
  return exec()
end

return M
