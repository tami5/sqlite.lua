---@brief [[
---Abstraction to produce more readable code.
---@brief ]]
---@tag table.lua
local u = require "sql.utils"
local a = require "sql.assert"
local fmt = string.format
local P = require "sql.parser"
local luv = require "luv"

---@class sqltbl @Main table class
---@field db sqldb: database in which the tbl is part of.
local tbl = {}
tbl.__index = tbl

local check_for_auto_alter = function(o, valid_schema)
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
---@param o sqltbl
---@return any
local run = function(func, o)
  a.should_have_db_object(o.db, o.name)
  local exec = function()
    local valid_schema = o.tbl_schema and next(o.tbl_schema) ~= nil

    --- Run once pre-init
    if o.tbl_exists == nil then
      o.tbl_exists = o.db:exists(o.name)
      o.mtime = o.db.uri and (luv.fs_stat(o.db.uri) or { mtime = {} }).mtime.sec or nil
      o.has_content = o.tbl_exists and o.db:eval(fmt("select count(*) from %s", o.name))[1]["count(*)"] ~= 0 or 0
      check_for_auto_alter(o, valid_schema)
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

    --- Run wrapped function
    return func()
  end

  if o.db.closed then
    return o.db:with_open(exec)
  end
  return exec()
end

---Create new sql table object
---@param db sqldb
---@param name string: table name
---@param schema sqlschema
---@return sqltbl
function tbl:new(db, name, schema)
  schema = schema or {}
  local o = setmetatable({ db = db, name = name, tbl_schema = u.if_nil(schema.schema, schema) }, self)
  if db then
    run(function() end, o)
  end
  return o
end

---Extend Sqlite Table Object. if first argument is {name} then second should be {schema}.
---If no {db} is provided, the tbl object won't be initialized until tbl.set_db
---is called
---@param db sqldb
---@param name string
---@param schema sqlschema
---@return sqltbl.ext
function tbl:extend(db, name, schema)
  if not schema and type(db) == "string" then
    name, db, schema = db, nil, name
  end

  local t = self:new(db, name, { schema = schema })
  return setmetatable({
    set_db = function(o)
      t.db = o
    end,
  }, {
    __index = function(o, key, ...)
      if type(key) == "string" then
        key = key:sub(1, 1) == "_" and key:sub(2, -1) or key
        if type(t[key]) == "function" then
          return function(...)
            return t[key](t, ...)
          end
        else
          return t[key]
        end
      end
    end,
  })
end

---Create or change table schema. If no {schema} is given,
---then it return current the used schema if it exists or empty table otherwise.
---On change schema it returns boolean indecting success.
---@param schema sqlschema
---@return sqlschema | boolean
---@usage `projects:schema()` get project table schema.
---@usage `projects:schema({...})` mutate project table schema
---@todo do alter when updating the schema instead of droping it completely
function tbl:schema(schema)
  return run(function()
    local exists = self.db:exists(self.name)
    if not schema then -- TODO: or table is empty
      return exists and self.db:schema(self.name) or {}
    end
    if not exists or schema.ensure then
      self.tbl_exists = self.db:create(self.name, schema)
      return self.tbl_exists
    end
    if not schema.ensure then -- maybe better to use alter
      local res = exists and self.db:drop(self.name) or true
      res = res and self.db:create(self.name, schema) or false
      self.tbl_schema = schema
      return res
    end
  end, self)
end

---Remove table from database, if the table is already drooped then it returns false.
---@usage `todos:drop()` drop todos table content.
---@see DB:drop
---@return boolean
function tbl:drop()
  return run(function()
    if not self.db:exists(self.name) then
      return false
    end

    local res = self.db:drop(self.name)
    if res then
      self.tbl_exists = false
      self.tbl_schema = nil
    end
    return res
  end, self)
end

---Predicate that returns true if the table is empty.
---@usage `if todos:empty() then echo "no more todos, you are free :D" end`
---@return boolean
function tbl:empty()
  return self:exists() and self:count() == 0 or false
end

---Predicate that returns true if the table exists.
---@usage `if not goals:exists() then error("I'm disappointed in you ") end`
---@return boolean
function tbl:exists()
  return run(function()
    return self.db:exists(self.name)
  end, self)
end

---Get the current number of rows in the table
---@return number
function tbl:count()
  return run(function()
    if not self.db:exists(self.name) then
      return 0
    end
    local res = self.db:eval("select count(*) from " .. self.name)
    return res[1]["count(*)"]
  end, self)
end

---Query the table and return results.
---@param query sqlquery_select
---@return table
---@usage `projects:get()` get a list of all rows in project table.
---@usage `projects:get({ where = { status = "pending", client = "neovim" }})`
---@usage `projects:get({ where = { status = "done" }, limit = 5})` get the last 5 done projects
---@see DB:select
function tbl:get(query)
  -- query = query or { query = { all = 1 } }

  return run(function()
    local res = self.db:select(self.name, query or { query = { all = 1 } }, self.db_schema)
    return res
  end, self)
end

---Get first match.
---@param where table: where key values
---@return nil or row
---@usage `tbl:where{id = 1}`
---@see DB:select
function tbl:where(where)
  return where and self:get({ where = where })[1] or nil
end

---Iterate over table rows and execute {func}.
---Returns true only when rows is not emtpy.
---@param func function: func(row)
---@param query table: query.where, query.keys, query.join
---@usage `let query = { where = { status = "pending"}, contains = { title = "fix*" } }`
---@usage `todos:each(function(row) print(row.title) end, query)`
---@return boolean
function tbl:each(func, query)
  query = query or {}
  if type(func) == "table" then
    func, query = query, func
  end

  return run(function()
    local rows = self.db:select(self.name, query, self.db_schema)
    if not rows then
      return false
    end

    for _, row in ipairs(rows) do
      func(row)
    end

    return rows ~= {} or type(rows) ~= "boolean"
  end, self)
end

---Create a new table from iterating over {self.name} rows with {func}.
---@param func function: func(row)
---@param query table: query.where, query.keys, query.join
---@usage `let query = { where = { status = "pending"}, contains = { title = "fix*" } }`
---@usage `local t = todos:map(function(row) return row.title end, query)`
---@return table[]
function tbl:map(func, query)
  query = query or {}
  if type(func) == "table" then
    func, query = query, func
  end

  return run(function()
    local res = {}
    local rows = self.db:select(self.name, query, self.db_schema)
    if not rows then
      return {}
    end
    for _, row in ipairs(rows) do
      local ret = func(row)
      if ret then
        table.insert(res, func(row))
      end
    end

    return res
  end, self)
end

---Sorts a table in-place using a transform. Values are ranked in a custom order of the results of
---running `transform (v)` on all values. `transform` may also be a string name property  sort by.
---`comp` is a comparison function. Adopted from Moses.lua
---@param query table: query.where, query.keys, query.join
---@param transform function: a `transform` function to sort elements. Defaults to @{identity}
---@param comp function: a comparison function, defaults to the `<` operator
---@return table[]
---@usage `local res = t1:sort({ where = {id = {32,12,35}}})` return rows sort by id
---@usage `local res = t1:sort({ where = {id = {32,12,35}}}, "age")` return rows sort by age
---@usage `local res = t1:sort({where = { ... }}, "age", function(a, b) return a > b end)` with custom function
function tbl:sort(query, transform, comp)
  query = query or { query = { all = 1 } }
  return run(function()
    local res = self.db:select(self.name, query, self.db_schema)
    local f = transform or function(r)
      return r[u.keys(query.where)[1]]
    end
    if type(transform) == "string" then
      f = function(r)
        return r[transform]
      end
    end
    comp = comp or function(_a, _b)
      return _a < _b
    end
    table.sort(res, function(_a, _b)
      return comp(f(_a), f(_b))
    end)
    return res
  end, self)
end

---Same functionalities as |DB:insert()|
---@param rows table: a row or a group of rows
---@see DB:insert
---@usage `todos:insert { title = "stop writing examples :D" }` insert single item.
---@usage `todos:insert { { ... }, { ... } }` insert multiple items
---@return integer: last inserted id
function tbl:insert(rows)
  return run(function()
    local succ, last_rowid = self.db:insert(self.name, rows, self.db_schema)
    if succ then
      self.has_content = self:count() ~= 0 or false
    end
    return last_rowid
  end, self)
end

---Same functionalities as |DB:delete()|
---@param where table: query
---@see DB:delete
---@return boolean
---@usage `todos:remove()` remove todos table content.
---@usage `todos:remove{ project = "neovim" }` remove all todos where project == "neovim".
---@usage `todos:remove{{project = "neovim"}, {id = 1}}` remove all todos where project == "neovim" or id =1
function tbl:remove(where)
  return run(function()
    return self.db:delete(self.name, where)
  end, self)
end

---Same functionalities as |DB:update()|
---@param specs table: a table or a list of tables with where and values keys.
---@see DB:update
---@return boolean
function tbl:update(specs)
  return run(function()
    local succ = self.db:update(self.name, specs, self.db_schema)
    return succ
  end, self)
end

---replaces table content with {rows}
---@param rows table: a row or a group of rows
---@see DB:delete
---@see DB:insert
---@return boolean
function tbl:replace(rows)
  return run(function()
    self.db:delete(self.name)
    local succ = self.db:insert(self.name, rows, self.db_schema)
    return succ
  end, self)
end

tbl = setmetatable(tbl, { __call = tbl.extend })

return tbl
