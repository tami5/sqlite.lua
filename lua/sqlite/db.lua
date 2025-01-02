---@brief [[
---Main sqlite.lua object and methods.
---@brief ]]
---@tag sqlite.db.lua

local u = require "sqlite.utils"
local require = u.require_on_index

local sqlite = {}

---@class sqlite_db @Main sqlite.lua object.
---@field uri string: database uri. it can be an environment variable or an absolute path. default ":memory:"
---@field opts sqlite_opts: see https://www.sqlite.org/pragma.html |sqlite_opts|
---@field conn sqlite_blob: sqlite connection c object.
---@field db sqlite_db: reference to fallback to when overwriting |sqlite_db| methods (extended only).
sqlite.db = {}
sqlite.db.__index = sqlite.db
sqlite.db.__version = "v1.2.2"

local clib = require "sqlite.defs"
local s = require "sqlite.stmt"
local h = require "sqlite.helpers"
local a = require "sqlite.assert"
local p = require "sqlite.parser"
local tbl = require "sqlite.tbl"

---Creates a new sqlite.lua object, without creating a connection to uri.
---|sqlite.new| is identical to |sqlite.db:open| but it without opening sqlite db
---connection (unless opts.keep_open). Its most suited for cases where the
---database might be -acccess from multiple places. For neovim use cases, this
---mean from different -neovim instances.
---
---<pre>
---```lua
--- local db = sqlite.new("path/to/db" or "$env_var", { ... } or nil)
--- -- configure open mode through opts.open_mode = "ro", "rw", "rwc", default "rwc"
--- -- for more customize behaviour, set opts.open_mode to a list of db.flags
--- -- see https://sqlite.org/c3ref/open.html#urifilenamesinsqlite3open
---```
---</pre>
---@param uri string: uri to db file.
---@param opts sqlite_opts: (optional) see |sqlite_opts|
---@return sqlite_db
function sqlite.db.new(uri, opts)
  opts = opts or {}
  local keep_open = opts.keep_open
  opts.keep_open = nil
  uri = type(uri) == "string" and u.expand(uri) or ":memory:"

  local o = setmetatable({
    uri = uri,
    conn = nil,
    closed = true,
    opts = opts,
    modified = false,
    created = nil,
    tbl_schemas = {},
  }, sqlite.db)

  if keep_open then
    o:open()
  end

  return o
end

---Extend |sqlite_db| object with extra sugar syntax and api. This is recommended
---for all sqlite use case as it provide convenience. This method is super lazy.
---it try its best to doing any ffi calls until the first operation done on a table.
---
---In the case you want to keep db connection open and not on invocation bases.
---Run |sqlite.db:open()| right after creating the object or when you
---intend to use it.
---
---Like |sqlite_tbl| original methods can be access through pre-appending "__"
---when user overwrites it.
---
---if { conf.opts.lazy } then only return a logical object with self-dependent
--tables, e.g. a table exists and other not because the one that
---exists, it's method was called. (default false).
---if { conf.opts.keep_open } then the sqlite extend db object will be returned
---with an open connection (default false)

---<pre>
---```lua
--- local db = sqlite { -- or sqlite_db:extend
---   uri = "path/to/db", -- path to db file
---   entries = require'entries',  -- a pre-made |sqlite_tbl| object.
---   category = { title = { "text", unique = true, primary = true}  },
---   opts = {} or nil -- custom sqlite3 options, see |sqlite_opts|
---   --- if opts.keep_open, make connection and keep it open.
---   --- if opts.lazy, then just provide logical object
---   --- configure open mode through opts.open_mode = "ro", "rw", "rwc", default "rwc"
---   --- for more customize behaviour, set opts.open_mode to a list of db.flags
---   --- see https://sqlite.org/c3ref/open.html#urifilenamesinsqlite3open
--- }
--- --- Overwrite method and access it using through pre-appending "__"
--- db.select = function(...) db:__select(...) end
---```
---</pre>
---@param conf table: see 'Fields'
---@field uri string: path to db file.
---@field opts sqlite_opts: (optional) see |sqlite_opts| + lazy (default false), open (default false)
---@field tname1 string: pointing to |sqlite_etbl| or |sqlite_schema_dict|
---@field tnameN string: pointing to |sqlite_etbl| or |sqlite_schema_dict|
---@see sqlite_tbl:extend
---@return sqlite_db
function sqlite.db:extend(conf)
  conf.opts = conf.opts or {}
  local lazy = conf.opts.lazy
  conf.opts.lazy = nil

  local db = self.new(conf.uri, conf.opts)
  local cls = setmetatable({ db = db }, {
    __index = function(_, key, ...)
      if type(key) == "string" then
        key = key:sub(1, 2) == "__" and key:sub(3, -1) or key
        if db[key] then
          return db[key]
        end
      end
    end,
  })

  for tbl_name, schema in pairs(conf) do
    if tbl_name ~= "uri" and tbl_name ~= "opts" and tbl_name ~= "lazy" and u.is_tbl(schema) then
      local name = schema._name and schema._name or tbl_name
      cls[tbl_name] = schema.set_db and schema or require("sqlite.tbl").new(name, schema, not lazy and db or nil)
      if not cls[tbl_name].db then
        (cls[tbl_name]):set_db(db)
      end
    end
  end

  return cls
end

---Creates and connect to new sqlite db object, either in memory or via a {uri}.
---If it is called on pre-made |sqlite_db| object, than it should open it. otherwise ignore.
---
---<pre>
---```lua
--- -- Open db file at path or environment variable, otherwise open in memory.
--- local db = sqlite.db:open("./pathto/dbfile" or "$ENV_VARABLE" or nil, {...})
--- -- reopen connection if closed.
--- db:open()
--- -- configure open mode through opts.open_mode = "ro", "rw", "rwc", default "rwc"
--- -- for more customize behaviour, set opts.open_mode to a list of db.flags
--- -- see https://sqlite.org/c3ref/open.html#urifilenamesinsqlite3open
---```
---</pre>
---@param uri string: (optional) {uri} == {nil} then in-memory db.
---@param opts sqlite_opts|nil:  see |sqlite_opts|
---@return sqlite_db
function sqlite.db:open(uri, opts, noconn)
  local d = self
  if not d.uri then
    d = sqlite.db.new(uri, opts)
  end

  if d.closed or d.closed == nil then
    d.conn = clib.connect(d.uri, d.opts)
    d.created = os.date "%Y-%m-%d %H:%M:%S"
    d.closed = false
  end

  return d
end

---Close sqlite db connection. returns true if closed, error otherwise.
---
---<pre>
---```lua
--- local db = sqlite.db:open()
--- db:close() -- close connection
---```
---</pre>
---@return boolean
function sqlite.db:close()
  self.closed = self.closed or clib.close(self.conn) == 0
  a.should_close(self.conn, self.closed)
  return self.closed
end

---Same as |sqlite.db:open| but execute {func} then closes db connection.
---If the function is called as a method to db object e.g. 'db:with_open', then
---{args[1]} must be a function. Else {args[1]} need to be the uri and {args[2]} the function.
---
---<pre>
---```lua
--- -- as a function
--- local entries = sqlite.with_open("path/to/db", function(db)
---    return db:select("todos", { where = { status = "done" } })
--- end)
--- -- as a method
--- local exists = db:with_open(function()
---   return db:exists("projects")
---  end)
---```
---</pre>
---
---@varargs If used as db method, then the {args[1]} should be a function, else
---{args[1]} is uri and {args[2]} is function.
---@see sqlite.db:open
---@return any
function sqlite.db:with_open(...)
  local args = { ... }
  if type(self) == "string" or not self then
    self = sqlite.db:open(self)
  end

  local func = type(args[1]) == "function" and args[1] or args[2]

  if self:isclose() then
    self:open()
  end

  local success, result = pcall(function()
    return func(self)
  end)
  self:close()
  if not success then
    error(result)
  end
  return result
end

---Predict returning true if db connection is active.
---
---<pre>
---```lua
--- if db:isopen() then
---   db:close()
--- end
---```
---</pre>
---@return boolean
function sqlite.db:isopen()
  return not self.closed
end

---Predict returning true if db connection is indeed closed.
---
---<pre>
---```lua
--- if db:isclose() then
---   error("db is closed")
--- end
---```
---</pre>
---@return boolean
function sqlite.db:isclose()
  return self.closed
end

---Returns current connection status
---Get last error code
---
---<pre>
---```lua
--- print(db:status().msg) -- get last error msg
--- print(db:status().code) -- get last error code.
---```
---</pre>
---@return sqlite_db_status
function sqlite.db:status()
  return {
    msg = clib.last_errmsg(self.conn),
    code = clib.last_errcode(self.conn),
  }
end

---Evaluates a sql {statement} and if there are results from evaluation it
---returns list of rows. Otherwise it returns a boolean indecating
---whether the evaluation was successful.
---
---<pre>
---```lua
--- -- evaluate without any extra arguments.
--- db:eval("drop table if exists todos")
--- --  evaluate with unamed value.
--- db:eval("select * from todos where id = ?", 1)
--- -- evaluate with named arguments.
--- db:eval("insert into t(a, b) values(:a, :b)", {a = "1", b = 3})
---```
---</pre>
---@param statement string: SQL statement.
---@param params table|nil: params to be bind to {statement}
---@return boolean|table
function sqlite.db:eval(statement, params)
  local res = {}
  local stmt = s:parse(self.conn, statement)

  -- when the user provide simple sql statements
  if not params then
    stmt:each(function()
      table.insert(res, stmt:kv())
    end)
    stmt:reset()

    -- when the user run eval("select * from ?", "tbl_name")
  elseif type(params) ~= "table" and statement:match "%?" then
    local value = p.sqlvalue(params)
    stmt:bind { value }
    stmt:each(function(stm)
      table.insert(res, stm:kv())
    end)
    stmt:reset()
    stmt:bind_clear()

    -- when the user provided named keys
  elseif params and type(params) == "table" then
    params = type(params[1]) == "table" and params or { params }
    for _, v in ipairs(params) do
      stmt:bind(v)
      stmt:each(function(stm)
        table.insert(res, stm:kv())
      end)
      stmt:reset()
      stmt:bind_clear()
    end
  end
  -- clear out the parsed statement.
  stmt:finalize()

  -- if no rows is returned, then check return the result of errcode == flags.ok
  res = rawequal(next(res), nil) and clib.last_errcode(self.conn) == clib.flags.ok or res

  -- fix res of its table, so that select all doesn't return { [1] = {[1] = { row }} }
  if type(res) == "table" and res[2] == nil and u.is_nested(res[1]) then
    res = res[1]
  end

  a.should_eval(self.conn)

  self.modified = true

  return res
end

---Execute statement without any return
---
---<pre>
---```lua
--- db:execute("drop table if exists todos")
--- db:execute("pragma foreign_keys=on")
---```
---</pre>
---@param statement string: statement to be executed
---@return boolean: true if successful, error out if not.
function sqlite.db:execute(statement)
  local succ = clib.exec_stmt(self.conn, statement) == 0
  return succ and succ or error(clib.last_errmsg(self.conn))
end

---Check if a table with {tbl_name} exists in sqlite db
---<pre>
---```lua
--- if not db:exists("todo_tbl") then
---   error("Table doesn't exists!!!")
--- end
---```
---</pre>
---@param tbl_name string: the table name.
---@return boolean
function sqlite.db:exists(tbl_name)
  local q = self:eval("select name from sqlite_master where name= ?", tbl_name)
  return type(q) == "table" and true or false
end

---Create a new sqlite db table with {name} based on {schema}. if {schema.ensure} then
---create only when it does not exists. similar to 'create if not exists'.
---
---<pre>
---```lua
--- db:create("todos", {
---   id = {"int", "primary", "key"},
---   title = "text",
---   name = { type = "string", reference = "sometbl.id" },
---   ensure = true -- create table if it doesn't already exists (THIS IS DEFUAULT)
--- })
---```
---</pre>
---@param tbl_name string: table name
---@param schema sqlite_schema_dict
---@return boolean
function sqlite.db:create(tbl_name, schema)
  local req = p.create(tbl_name, schema)
  if req:match "reference" then
    self:execute "pragma foreign_keys = ON"
    self.opts.foreign_keys = true
  end
  return self:eval(req)
end

---Remove {tbl_name} from database
---
---<pre>
---```lua
--- if db:exists("todos") then
---   db:drop("todos")
--- end
---```
---</pre>
---@param tbl_name string: table name
---@return boolean
function sqlite.db:drop(tbl_name)
  self.tbl_schemas[tbl_name] = nil
  return self:eval(p.drop(tbl_name))
end

---Get {name} table schema, if table does not exist then return an empty table.
---
---<pre>
---```lua
--- if db:exists("todos") then
---   inspect(db:schema("todos").project)
--- else
---   print("create me")
--- end
---```
---</pre>
---@param tbl_name string: the table name.
---@return sqlite_schema_dict
function sqlite.db:schema(tbl_name)
  local sch = self:eval(("pragma table_info(%s)"):format(tbl_name))
  local schema = {}
  for _, v in ipairs(type(sch) == "boolean" and {} or sch) do
    schema[v.name] = {
      cid = v.cid,
      required = v.notnull == 1,
      primary = v.pk == 1,
      type = v.type,
      default = v.dflt_value,
    }
  end
  return schema
end

---Insert lua table into sqlite database table.
---
---<pre>
---```lua
--- --- single item.
--- db:insert("todos", { title = "new todo" })
--- --- insert multiple items.
--- db:insert("items", {  { name = "a"}, { name = "b" }, { name = "c" } })
---```
---</pre>
---@param tbl_name string: the table name
---@param rows table: rows to insert to the table.
---@return boolean|integer: boolean (true == success), and the last inserted row id.
function sqlite.db:insert(tbl_name, rows, schema)
  a.is_sqltbl(self, tbl_name, "insert")
  local ret_vals = {}
  schema = schema and schema or h.get_schema(tbl_name, self)
  local items = p.pre_insert(rows, schema)
  local last_rowid
  clib.wrap_stmts(self.conn, function()
    for _, v in ipairs(items) do
      local stmt = s:parse(self.conn, p.insert(tbl_name, { values = v }))
      stmt:bind(v)
      stmt:step()
      stmt:bind_clear()
      table.insert(ret_vals, stmt:finalize())
    end
    last_rowid = tonumber(clib.last_insert_rowid(self.conn))
  end)

  local succ = u.all(ret_vals, function(_, v)
    return v
  end)
  if succ then
    self.modified = true
  end
  return succ, last_rowid
end

---Update table row with where closure and list of values
---returns true incase the table was updated successfully.
---
---<pre>
---```lua
--- --- update todos status linked to project "lua-hello-world" or "rewrite-neoivm-in-rust"
--- db:update("todos", {
---   where = { project = {"lua-hello-world", "rewrite-neoivm-in-rust"} },
---   set = { status = "later" }
--- })
---
--- --- pass custom statement and boolean
--- db:update("timestamps", {
---   where = { id = "<" .. 4 }, -- mimcs WHERE id < 4
---   set = { seen = true } -- will be converted to 0.
--- })
---```
---</pre>
---@param tbl_name string: sqlite table name.
---@param specs sqlite_query_update | sqlite_query_update[]
---@return boolean
function sqlite.db:update(tbl_name, specs, schema)
  a.is_sqltbl(self, tbl_name, "update")
  if not specs then
    return false
  end

  return clib.wrap_stmts(self.conn, function()
    specs = u.is_nested(specs) and specs or { specs }
    schema = schema and schema or h.get_schema(tbl_name, self)

    local ret_val = nil
    for _, v in ipairs(specs) do
      v.set = v.set and v.set or v.values
      if self:select(tbl_name, { where = v.where })[1] then
        local stmt = s:parse(self.conn, p.update(tbl_name, { set = v.set, where = v.where }))
        stmt:bind(p.pre_insert(v.set, schema)[1])
        stmt:step()
        stmt:reset()
        stmt:bind_clear()
        stmt:finalize()
        a.should_modify(self:status())
        ret_val = true
      else
        ret_val = self:insert(tbl_name, u.tbl_extend("keep", v.set, v.where))
        a.should_modify(self:status())
      end
    end
    self.modified = true
    return ret_val
  end)
end

---Delete a {tbl_name} row/rows based on the {where} closure. If {where == nil}
---then all the {tbl_name} content will be deleted.
---
---<pre>
---```lua
--- --- delete todos table content
--- db:delete("todos")
--- --- delete row that has id as 1
--- db:delete("todos", { id = 1 })
--- --- delete all rows that has value of id 1 or 2 or 3
--- db:delete("todos", { id = {1,2,3} })
--- --- matching ids or greater than 5
--- db:delete("todos", { id = {"<", 5} }) -- or {id = "<5"}
---```
---</pre>
---@param tbl_name string: sqlite table name
---@param where sqlite_query_delete: key value pair to where delete operation should effect.
---@todo support querys with `and`
---@return boolean: true if operation is successfully, false otherwise.
function sqlite.db:delete(tbl_name, where)
  a.is_sqltbl(self, tbl_name, "delete")

  if not where then
    return self:execute(p.delete(tbl_name))
  end

  where = u.is_nested(where) and where or { where }
  clib.wrap_stmts(self.conn, function()
    for _, spec in ipairs(where) do
      local _where = spec.where and spec.where or spec
      local stmt = s:parse(self.conn, p.delete(tbl_name, { where = _where }))
      stmt:step()
      stmt:reset()
      stmt:finalize()
      a.should_modify(self:status())
    end
  end)

  self.modified = true

  return true
end

---Query from a table with where and join options
---
---<pre>
---```lua
--- db:select("todos") get everything
--- --- get row with id of 1
--- db:select("todos", { where = { id = 1 })
--- ---  get row with status value of later or paused
--- db:select("todos", { where = { status = {"later", "paused"} })
--- --- get 5 items from todos table
--- db:select("todos", { limit = 5 })
--- --- select a set of keys with computed one
--- db:select("timestamps", {
---   select = {
---     age = (strftime("%s", "now") - strftime("%s", "timestamp")) * 24 * 60,
---     "id",
---     "timestamp",
---     "entry",
---     },
---   })
---```
---</pre>
---@param tbl_name string: the name of the db table to select on
---@param spec sqlite_query_select
---@return table[]
function sqlite.db:select(tbl_name, spec, schema)
  a.is_sqltbl(self, tbl_name, "select")
  return clib.wrap_stmts(self.conn, function()
    local ret = {}
    schema = schema and schema or h.get_schema(tbl_name, self)

    spec = spec or {}
    spec.select = spec.keys and spec.keys or spec.select
    local select = p.select(tbl_name, spec)
    local st = ""

    local stmt = s:parse(self.conn, select, tbl_name)
    stmt:each(function()
      table.insert(ret, stmt:kv())
    end)
    if tbl_name == "todos_indexer" then
      st = stmt:expand()
    end

    stmt:reset()
    if stmt:finalize() then
      self.modified = false
    end
    if tbl_name == "todos_indexer" and spec.id == 3 then
      error(st)
    end

    return p.post_select(ret, schema)
  end)
end

---Create new sqlite_tbl object.
---If {opts}.ensure = false, then on each run it will drop the table and recreate it.
---NOTE: this might change someday to alter the table instead. For now
---alteration is auto and limited to field schema edits and renames
---
---<pre>
---```lua
--- local tbl = db:tbl("todos", {
---   id = true, -- same as { type = "integer", required = true, primary = true }
---   title = "text",
---   category = {
---     type = "text",
---     reference = "category.id",
---     on_update = "cascade", -- means when category get updated update
---     on_delete = "null", -- means when category get deleted, set to null
---   },
--- })
--- --- or without db injected and use as wrapper for |sqlite.tbl.new|
--- local tbl = db.tbl("name", ...)
---```
---</pre>
---@param tbl_name string: the name of the table. can be new or existing one.
---@param schema sqlite_schema_dict: {schema, ensure (defalut true)}
---@see |sqlite.tbl.new|
---@return sqlite_tbl
function sqlite.db:tbl(tbl_name, schema)
  if type(self) == "string" then
    schema = tbl_name
    return tbl.new(self, schema)
  end
  return tbl.new(tbl_name, schema, self)
end

---DEPRECATED
function sqlite.db:table(tbl_name, opts)
  print "sqlite.lua sqlite:table is deprecated use sqlite:tbl instead"
  return self:tbl(tbl_name, opts)
end

function sqlite.db:last_insert_rowid()
  return tonumber(clib.last_insert_rowid(self.conn))
end

---Sqlite functions sugar wrappers. See `sql/strfun`
sqlite.db.lib = require "sqlite.strfun"

sqlite.db = setmetatable(sqlite.db, {
  __call = sqlite.db.extend,
})

sqlite.db.flags = clib.flags

return sqlite.db
