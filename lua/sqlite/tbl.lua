---@brief [[
---Abstraction to produce more readable code.
---<pre>
--- ```lua
--- local tbl = require'sqlite.tbl'
--- ```
---</pre>
---@brief ]]
---@tag sqlite.tbl.lua

local u = require "sqlite.utils"
local h = require "sqlite.helpers"

local indexer = require "sqlite.tbl.indexer"
local sqlite = {}

---@class sqlite_tbl @Main sql table class
---@field db sqlite_db: sqlite.lua database object.
---@field name string: table name.
---@field mtime number: db last modified time.
sqlite.tbl = {}
sqlite.tbl.__index = sqlite.tbl

-- TODO: Add examples to index access in sqlite.tbl.new

---Create new |sqlite_tbl| object. This object encouraged to be extend and
---modified by the user. overwritten method can be still accessed via
---pre-appending `__`  e.g. redefining |sqlite_tbl:get|, result in
---`sqlite_tbl:__get` available as a backup. This object can be instantiated
---without a {db}, in which case, it requires 'sqlite.tbl:set_db' is called.
---
---Common use case might be to define tables in separate files and then require them in
---file that export db object (TODO: support tbl reuse in different dbs).
---
---<pre>
---```lua
--- local t = tbl("todos", { --- or tbl.new
---   id = true, -- same as { "integer", required = true, primary = true }
---   title = "text",
---   since = { "date", default = sqlite.lib.strftime("%s", "now") },
---   category = {
---     type = "text",
---     reference = "category.id",
---     on_update = "cascade", -- means when category get updated update
---     on_delete = "null", -- means when category get deleted, set to null
---   },
--- }, db)
--- --- overwrite
--- t.get = function() return t:__get({ where = {...}, select = {...} })[1] end
---```
---</pre>
---@param name string: table name
---@param schema sqlite_schema_dict
---@param db sqlite_db|nil : if nil, then for it to work, it needs setting with sqlite.tbl:set_db().
---@return sqlite_tbl
function sqlite.tbl.new(name, schema, db)
  schema = schema or {}
  schema = u.if_nil(schema.schema, schema)
  ---@type sqlite_tbl
  local tbl = setmetatable({
    db = db,
    name = name,
    tbl_schema = schema,
  }, sqlite.tbl)

  if db then
    h.run(nil, tbl)
  end

  return indexer(tbl)
end

---Create or change table schema. If no {schema} is given,
---then it return current the used schema if it exists or empty table otherwise.
---On change schema it returns boolean indecting success.
---
---<pre>
---```lua
--- local projects = sqlite.tbl:new("", {...})
--- --- get project table schema.
--- projects:schema()
--- --- mutate project table schema with droping content if not schema.ensure
--- projects:schema {...}
---```
---</pre>
---@param schema sqlite_schema_dict
---@return sqlite_schema_dict | boolean
function sqlite.tbl:schema(schema)
  return h.run(function()
    local exists = self.db:exists(self.name)
    if not schema then -- TODO: or table is empty
      return exists and self.db:schema(self.name) or {}
    end
    if not exists or schema.ensure then
      self.tbl_exists = self.db:create(self.name, schema)
      return self.tbl_exists
    end
    if not schema.ensure then -- TODO: use alter
      local res = exists and self.db:drop(self.name) or true
      res = res and self.db:create(self.name, schema) or false
      self.tbl_schema = schema
      return res
    end
  end, self)
end

---Remove table from database, if the table is already drooped then it returns false.
---
---<pre>
---```lua
--- --- drop todos table content.
--- todos:drop()
---```
---</pre>
---@see sqlite.db:drop
---@return boolean
function sqlite.tbl:drop()
  return h.run(function()
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
---
---<pre>
---```lua
--- if todos:empty() then
---   print "no more todos, we are free :D"
--- end
---```
---</pre>
---@return boolean
function sqlite.tbl:empty()
  return h.run(function()
    if self.db:exists(self.name) then
      return self.db:eval("select count(*) from " .. self.name)[1]["count(*)"] == 0
    end
  end, self)
end

---Predicate that returns true if the table exists.
---
---<pre>
---```lua
--- if goals:exists() then
---   error("I'm disappointed in you :D")
--- end
---```
---</pre>
---@return boolean
function sqlite.tbl:exists()
  return h.run(function()
    return self.db:exists(self.name)
  end, self)
end

---Get the current number of rows in the table
---
---<pre>
---```lua
--- if notes:count() == 0 then
---   print("no more notes")
--- end
---```
---@return number
function sqlite.tbl:count()
  return h.run(function()
    if not self.db:exists(self.name) then
      return 0
    end
    local res = self.db:eval("select count(*) from " .. self.name)
    return res[1]["count(*)"]
  end, self)
end

---Query the table and return results.
---
---<pre>
---```lua
--- --- get everything
--- todos:get()
--- --- get row with id of 1
--- todos:get { where = { id = 1 } }
--- --- select a set of keys with computed one
--- timestamps:get {
---   select = {
---     age = (strftime("%s", "now") - strftime("%s", "timestamp")) * 24 * 60,
---     "id",
---     "timestamp",
---     "entry",
---     },
---   }
---```
---</pre>
---@param query sqlite_query_select
---@return table
---@see sqlite.db:select
function sqlite.tbl:get(query)
  -- query = query or { query = { all = 1 } }

  return h.run(function()
    local res = self.db:select(self.name, query or { query = { all = 1 } }, self.db_schema)
    return res
  end, self)
end

---Get first match.
---
---<pre>
---```lua
--- --- get single entry. notice that we don't pass where key.
--- tbl:where{ id = 1 }
--- --- get row with id of 1 or 'todos.where { id = 1 }'
---```
---</pre>
---@param where table: where key values
---@return nil or row
---@usage ``
---@see sqlite.db:select
function sqlite.tbl:where(where)
  return where and self:get({ where = where })[1] or nil
end

---Iterate over table rows and execute {func}.
---Returns false if no row is returned.
---
---<pre>
---```lua
--- --- Execute a function on each returned row
--- todos:each(function(row)
---   print(row.title)
--- end, {
---   where = { status = "pending" },
---   contains = { title = "fix*" }
--- })
---
--- todos:each({ where = { ... }}, function(row)
---   print(row.title)
--- end)
---```
---</pre>
---@param func function: func(row)
---@param query sqlite_query_select|nil
---@return boolean
function sqlite.tbl:each(func, query)
  if type(func) == "table" then
    func, query = query, func
  end

  return h.run(function()
    local rows = self.db:select(self.name, query or {}, self.db_schema)
    if not rows then
      return false
    end

    for _, row in ipairs(rows) do
      func(row)
    end

    return rows ~= {} or type(rows) ~= "boolean"
  end, self)
end

---Create a new table from iterating over a tbl rows with {func}.
---
---<pre>
---```lua
--- --- transform rows.
--- local rows = todos:map(function(row)
---   row.somekey = ""
---   row.f = callfunction(row)
---   return row
--- end, {
---   where = { status = "pending" },
---   contains = { title = "fix*" }
--- })
--- --- This works too.
--- local titles = todos:map({ where = { ... }}, function(row)
---   return row.title
--- end)
--- --- no query, no problem :D
--- local all = todos:map(function(row) return row.title end)
---```
---</pre>
---@param func function: func(row)
---@param query sqlite_query_select
---@return table[]
function sqlite.tbl:map(func, query)
  if type(func) == "table" then
    func, query = query, func
  end

  return h.run(function()
    local res = {}
    local rows = self.db:select(self.name, query or {}, self.db_schema)
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
---
---<pre>
---```lua
--- --- return rows sort by id.
--- local res = t1:sort({ where = {id = {32,12,35}}})
--- --- return rows sort by age
--- local res = t1:sort({ where = {id = {32,12,35}}}, "age")`
--- --- return with custom sort function (recommended)
--- local res = t1:sort({where = { ... }}, "age", function(a, b) return a > b end)`
---```
---</pre>
---@param query sqlite_query_select|nil
---@param transform function: a `transform` function to sort elements. Defaults to @{identity}
---@param comp function: a comparison function, defaults to the `<` operator
---@return table[]
function sqlite.tbl:sort(query, transform, comp)
  return h.run(function()
    local res = self.db:select(self.name, query or { query = { all = 1 } }, self.db_schema)
    local f = transform or function(r)
      return r[u.keys(query.where)[1]]
    end
    if type(transform) == "string" then
      f = function(r)
        return r[transform]
      end
    end
    comp = comp or function(a_, b_)
      return a_ < b_
    end
    table.sort(res, function(a_, b_)
      return comp(f(a_), f(b_))
    end)
    return res
  end, self)
end

---Insert rows into a table.
---
---<pre>
---```lua
--- --- single item.
--- todos:insert { title = "new todo" }
--- --- insert multiple items, using todos table as first param
--- tbl.insert(todos, "items", {  { name = "a"}, { name = "b" }, { name = "c" } })
---```
---</pre>
---@param rows table: a row or a group of rows
---@see sqlite.db:insert
---@usage `todos:insert { title = "stop writing examples :D" }` insert single item.
---@usage `todos:insert { { ... }, { ... } }` insert multiple items
---@return integer: last inserted id
function sqlite.tbl:insert(rows)
  return h.run(function()
    local succ, last_rowid = self.db:insert(self.name, rows, self.db_schema)
    if succ then
      self.has_content = self:count() ~= 0 or false
    end
    return last_rowid
  end, self)
end

---Delete a rows/row or table content based on {where} closure. If {where == nil}
---then clear table content.
---
---<pre>
---```lua
--- --- delete todos table content
--- todos:remove()
--- --- delete row that has id as 1
--- todos:remove { id = 1 }
--- --- delete all rows that has value of id 1 or 2 or 3
--- todos:remove { id = {1,2,3} }
--- --- matching ids or greater than 5
--- todos:remove { id = {"<", 5} } -- or {id = "<5"}
---```
---</pre>
---@param where sqlite_query_delete
---@see sqlite.db:delete
---@return boolean
function sqlite.tbl:remove(where)
  return h.run(function()
    return self.db:delete(self.name, where)
  end, self)
end

---Update table row with where closure and list of values
---returns true incase the table was updated successfully.
---
---<pre>
---```lua
--- --- update todos status linked to project "lua-hello-world" or "rewrite-neoivm-in-rust"
--- todos:update {
---   where = { project = {"lua-hello-world", "rewrite-neoivm-in-rust"} },
---   set = { status = "later" }
--- }
--- --- pass custom statement and boolean
--- ts:update {
---   where = { id = "<" .. 4 }, -- mimcs WHERE id < 4
---   set = { seen = true } -- will be converted to 0.
--- }
---```
---</pre>
---@param specs sqlite_query_update
---@see sqlite.db:update
---@see sqlite_query_update
---@return boolean
function sqlite.tbl:update(specs)
  return h.run(function()
    local succ = self.db:update(self.name, specs, self.db_schema)
    return succ
  end, self)
end

---Replaces table content with a given set of {rows}.
---
---<pre>
---```lua
--- --- replace project table content with a single call
--- todos:replace { { ... }, { ... }, { ... },  }
---
--- --- replace everything with a single row
--- ts:replace { key = "val" }
---```
---</pre>
---@param rows table[]|table
---@see sqlite.db:delete
---@see sqlite.db:insert
---@return boolean
function sqlite.tbl:replace(rows)
  return h.run(function()
    self.db:delete(self.name)
    local succ = self.db:insert(self.name, rows, self.db_schema)
    return succ
  end, self)
end

---Changes the db object to which the sqlite_tbl correspond to. If the object is
---going to be passed to |sqlite.new|, then it will be set automatically at
---definition.
---@param db sqlite_db
function sqlite.tbl:set_db(db)
  self.db = db
end

function sqlite.tbl:last_id()
  h.run(function()
    rawset(self, "last_id", self.db:last_insert_rowid())
  end, self)
end

sqlite.tbl = setmetatable(sqlite.tbl, {
  __call = function(_, ...)
    return sqlite.tbl.new(...)
  end,
})

return sqlite.tbl
