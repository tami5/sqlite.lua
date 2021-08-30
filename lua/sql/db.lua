---@brief [[
---Main sql.nvim object and methods.
---@brief ]]
---@tag sqldb.overview

---@type sqldb
local sqldb = {}
sqldb.__index = sqldb

local clib = require "sql.defs"
local stmt = require "sql.stmt"
local u = require "sql.utils"
local a = require "sql.assert"
local t = require "sql.table"
local P = require "sql.parser"
local flags = clib.flags

---Get a table schema, or execute a given function to get it
---@param tbl_name string
---@param self sqldb
local get_schema = function(tbl_name, self)
  local schema = self.tbl_schemas[tbl_name]
  if schema then
    return schema
  end
  self.tbl_schemas[tbl_name] = self:schema(tbl_name)
  return self.tbl_schemas[tbl_name]
end

---Creates a new sql.nvim object, without creating a connection to uri.
---|sqldb.new| is identical to |sqldb:open| but it without opening sqlite db
---connection. Thus its most suited for cases where the database might be
---acccess from multiple places. For neovim use cases, this mean from different
---neovim instances.
---
---<pre>
---```lua
--- local db = sqldb.new("path/to/db" or "$env_var", { ... } or nil)
---```
---</pre>
---@param uri string: uri to db file.
---@param opts sqlopts: (optional) see |sqlopts|
---@return sqldb
function sqldb.new(uri, opts)
  return sqldb:open(uri, opts, true)
end

---Creates and connect to new sqlite db object, either in memory or via a {uri}.
---If it is called on pre-made |sqldb| object, than it should open it. otherwise ignore.
---
---<pre>
---```lua
--- -- Open db file at path or environment variable, otherwise open in memory.
--- local db = sqldb:open("./pathto/dbfile" or "$ENV_VARABLE" or nil, {...})
--- -- reopen connection if closed.
--- db:open()
---```
---</pre>
---@param uri string: (optional) {uri} == {nil} then in-memory db.
---@param opts sqlopts: (optional) see |sqlopts|
---@return sqldb
function sqldb:open(uri, opts, noconn)
  if not self.uri then
    uri = type(uri) == "string" and u.expand(uri) or ":memory:"
    return setmetatable({
      uri = uri,
      conn = not noconn and clib.connect(uri, opts) or nil,
      closed = noconn and true or false,
      opts = opts or {},
      modified = false,
      created = not noconn and os.date "%Y-%m-%d %H:%M:%S" or nil,
      tbl_schemas = {},
    }, self)
  else
    if self.closed or self.closed == nil then
      self.conn = clib.connect(self.uri, self.opts)
      self.created = os.date "%Y-%m-%d %H:%M:%S"
      self.closed = false
    end
    return self
  end
end

---Extend |sqldb| object with extra sugar syntax and api. This is recommended
---for all sqlite use case as it provide convenience. This method is super lazy.
---it try its best to doing any ffi calls until the first operation done on a table.
---
---In the case you want to keep db connection open and not on invocation bases.
---Run |sqldb:open()| right after creating the object or when you
---intend,
---
---<pre>
---```lua
--- local db = sqldb { -- or sqldb:extend
---   uri = "path/to/db", -- path to db file
---   entries = entries,  -- pre-made |sqltblext| with |sqltbl:extend()| without db
---   category = { title = { "text", unique = true, primary = true}  },
---   opts = {} or nil -- custom sqlite3 options, see |sqlopts|
--- }
--- -- unlike |sqltbl|, |sqltblext| is accessed by dot notation.
--- db.entries.insert { {..}, {..} }
---```
---</pre>
---@param opts table: see 'Fields'
---@field uri string: path to db file.
---@field opts sqlopts: (optional) see |sqlopts|
---@field tname1 string: pointing to |sqltblext| or |sqlschema|
---@field tnameN string: pointing to |sqltblext| or |sqlschema|
---@see sqltbl:extend
---@return sqldb
function sqldb:extend(opts)
  local db = self.new(opts.uri, opts.opts)
  local cls = setmetatable({ db = db }, { __index = db })
  for tbl_name, schema in pairs(opts) do
    if tbl_name ~= "uri" and tbl_name ~= "opts" and u.is_tbl(schema) then
      local name = schema._name and schema._name or tbl_name
      cls[tbl_name] = schema.set_db and schema or t:extend(name, schema)
      if not cls[tbl_name].db then
        cls[tbl_name].set_db(cls.db)
      end
    end
  end
  return cls
end

---Close sqlite db connection. returns true if closed, error otherwise.
---
---<pre>
---```lua
--- local db = sqldb:open()
--- db:close() -- close connection
---```
---</pre>
---@return boolean
function sqldb:close()
  self.closed = self.closed or clib.close(self.conn) == 0
  a.should_close(self.conn, self.closed)
  return self.closed
end

---Same as |sqldb:open| but execute {func} then closes db connection.
---If the function is called as a method to db object e.g. 'db:with_open', then
---{args[1]} must be a function. Else {args[1]} need to be the uri and {args[2]} the function.
---
---<pre>
---```lua
--- -- as a function
--- local entries = sqldb.with_open("path/to/db", function(db)
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
---@see sqldb:open
---@return any
function sqldb:with_open(...)
  local args = { ... }
  if type(self) == "string" or not self then
    self = sqldb:open(self)
  end

  local func = type(args[1]) == "function" and args[1] or args[2]

  if self:isclose() then
    self:open()
  end

  local res = func(self)
  self:close()
  return res
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
function sqldb:isopen()
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
function sqldb:isclose()
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
---@return sqldb_status
function sqldb:status()
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
function sqldb:eval(statement, params)
  local res = {}
  local s = stmt:parse(self.conn, statement)

  -- when the user provide simple sql statements
  if not params then
    s:each(function()
      table.insert(res, s:kv())
    end)
    s:reset()

    -- when the user run eval("select * from ?", "tbl_name")
  elseif type(params) ~= "table" and statement:match "%?" then
    local value = P.sqlvalue(params)
    s:bind { value }
    s:each(function(stm)
      table.insert(res, stm:kv())
    end)
    s:reset()
    s:bind_clear()

    -- when the user provided named keys
  elseif params and type(params) == "table" then
    params = type(params[1]) == "table" and params or { params }
    for _, v in ipairs(params) do
      s:bind(v)
      s:each(function(stm)
        table.insert(res, stm:kv())
      end)
      s:reset()
      s:bind_clear()
    end
  end
  -- clear out the parsed statement.
  s:finalize()

  -- if no rows is returned, then check return the result of errcode == flags.ok
  res = rawequal(next(res), nil) and clib.last_errcode(self.conn) == flags.ok or res

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
function sqldb:execute(statement)
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
function sqldb:exists(tbl_name)
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
---@param schema sqlschema
---@return boolean
function sqldb:create(tbl_name, schema)
  local req = P.create(tbl_name, schema)
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
function sqldb:drop(tbl_name)
  self.tbl_schemas[tbl_name] = nil
  return self:eval(P.drop(tbl_name))
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
---@return sqlschema
function sqldb:schema(tbl_name)
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
function sqldb:insert(tbl_name, rows, schema)
  a.is_sqltbl(self, tbl_name, "insert")
  local ret_vals = {}
  schema = schema and schema or get_schema(tbl_name, self)
  local items = P.pre_insert(rows, schema)
  local last_rowid
  clib.wrap_stmts(self.conn, function()
    for _, v in ipairs(items) do
      local s = stmt:parse(self.conn, P.insert(tbl_name, { values = v }))
      s:bind(v)
      s:step()
      s:bind_clear()
      table.insert(ret_vals, s:finalize())
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
---@param specs sqlquery_update | sqlquery_update[]
---@return boolean
function sqldb:update(tbl_name, specs, schema)
  a.is_sqltbl(self, tbl_name, "update")
  if not specs then
    return false
  end

  return clib.wrap_stmts(self.conn, function()
    specs = u.is_nested(specs) and specs or { specs }
    schema = schema and schema or get_schema(tbl_name, self)

    local ret_val = nil
    for _, v in ipairs(specs) do
      v.set = v.set and v.set or v.values
      if self:select(tbl_name, { where = v.where })[1] then
        local s = stmt:parse(self.conn, P.update(tbl_name, { set = v.set, where = v.where }))
        s:bind(P.pre_insert(v.set, schema)[1])
        s:step()
        s:reset()
        s:bind_clear()
        s:finalize()
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
---@param where sqlquery_delete: key value pair to where delete operation should effect.
---@todo support querys with `and`
---@return boolean: true if operation is successfully, false otherwise.
function sqldb:delete(tbl_name, where)
  a.is_sqltbl(self, tbl_name, "delete")

  if not where then
    return self:execute(P.delete(tbl_name))
  end

  where = u.is_nested(where) and where or { where }
  clib.wrap_stmts(self.conn, function()
    for _, spec in ipairs(where) do
      local _where = spec.where and spec.where or spec
      local s = stmt:parse(self.conn, P.delete(tbl_name, { where = _where }))
      s:step()
      s:reset()
      s:finalize()
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
---@param spec sqlquery_select
---@return table[]
function sqldb:select(tbl_name, spec, schema)
  a.is_sqltbl(self, tbl_name, "select")
  return clib.wrap_stmts(self.conn, function()
    local ret = {}
    schema = schema and schema or get_schema(tbl_name, self)

    spec = spec or {}
    spec.select = spec.keys and spec.keys or spec.select

    local s = stmt:parse(self.conn, P.select(tbl_name, spec))
    stmt.each(s, function()
      table.insert(ret, stmt.kv(s))
    end)
    stmt.reset(s)
    if stmt.finalize(s) then
      self.modified = false
    end
    return P.post_select(ret, schema)
  end)
end

---Create new sql-table object.
---If {opts}.ensure = false, on each run it will drop the table and recreate it.
---
---<pre>
---```lua
--- local tbl = db:table("todos", {
---   id = true, -- { type = "integer", required = true, primary = true }
---   title = "text",
---   since = { "date", default = strftime("%s", "now") },
---   count = { "number", default = 0 },
---   type = { "text", required = true },
---   category = {
---     type = "text",
---     reference = "category.id",
---     on_update = "cascade", -- means when category get updated update
---     on_delete = "null", -- means when category get deleted, set to null
---   },
--- })
---```
---</pre>
---@param tbl_name string: the name of the table. can be new or existing one.
---@param opts table: {schema, ensure (defalut true)}
---@return sqltbl
function sqldb:table(tbl_name, opts)
  return t:new(self, tbl_name, opts)
end

---Sqlite functions sugar wrappers. See `sql/strfun`
sqldb.lib = require "sql.strfun"

sqldb = setmetatable(sqldb, { __call = sqldb.extend })

return sqldb
