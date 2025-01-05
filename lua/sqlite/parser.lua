local u = require "sqlite.utils"
local json = require "sqlite.json"
local tinsert = table.insert
local tconcat = table.concat
local a = require "sqlite.assert"
local M = {}

---@brief [[
---Internal functions for parsing sql statement from lua table.
---methods = { select, update, delete, insert, create, alter, drop }
---accepts tbl name and options.
---options = {join, keys, values, set, where, select}
---hopfully returning valid sql statement :D
---@brief ]]
---@tag parser.lua

---handle sqlite datatype interop
M.sqlvalue = function(v)
  return type(v) == "boolean" and (v == true and 1 or 0) or (v == nil and "null" or v)
end

M.luavalue = function(v, key_type)
  if key_type == "luatable" or key_type == "json" then
    return json.decode(v)
  elseif key_type == "boolean" then
    if v == 0 then
      return false
    else
      return true
    end
    -- return v == 0 and false or true
  end

  return v
end

---string.format specifier based on value type
---@param v any: the value
---@param nonbind boolean?: whether to return the specifier or just return the value.
---@return string
local specifier = function(v, nonbind)
  local type = type(v)
  if type == "number" then
    local _, b = math.modf(v)
    return b == 0 and "%d" or "%f"
  elseif type == "string" and not nonbind then
    return v:find "'" and [["%s"]] or "'%s'"
  elseif nonbind then
    return v
  else
    return ""
  end
end

local bind = function(o)
  o = o or {}
  o.s = o.s or ", "
  if not o.kv then
    o.v = o.v ~= nil and M.sqlvalue(o.v) or "?"
    return ("%s = " .. specifier(o.v)):format(o.k, o.v)
  else
    local res = {}
    for k, v in u.opairs(o.kv) do
      k = o.k ~= nil and o.k or k
      v = M.sqlvalue(v)
      v = o.nonbind and ":" .. k or v
      tinsert(res, ("%s" .. (o.nonbind and nil or " = ") .. specifier(v, o.nonbind)):format(k, v))
    end
    return tconcat(res, o.s)
  end
end

---format glob pattern as part of where clause
local pcontains = function(defs)
  if not defs then
    return {}
  end
  local items = {}
  for k, v in u.opairs(defs) do
    local head = "%s glob " .. specifier(k)

    if type(v) == "table" then
      local val = u.map(v, function(value)
        return head:format(k, M.sqlvalue(value))
      end)
      tinsert(items, tconcat(val, " or "))
    else
      tinsert(items, head:format(k, v))
    end
  end

  return tconcat(items, " ")
end

---Format values part of sql statement
---@params defs table: key/value pairs defining sqlite table keys.
---@params defs kv: whether to bind by named keys.
local pkeys = function(defs, kv)
  kv = kv == nil and true or kv

  if not defs or not kv then
    return {}
  end

  defs = u.is_nested(defs) and defs[1] or defs

  local keys = {}
  for k, _ in u.opairs(defs) do
    tinsert(keys, k)
  end

  return ("(%s)"):format(tconcat(keys, ", "))
end

---Format values part of sql statement, usually used with select method.
---@params defs table: key/value pairs defining sqlite table keys.
---@params defs kv: whether to bind by named keys.
local pvalues = function(defs, kv)
  kv = kv == nil and true or kv -- TODO: check if defs is key value pairs instead
  if not defs or not kv then
    return {}
  end

  defs = u.is_nested(defs) and defs[1] or defs

  local keys = {}
  for k, v in u.opairs(defs) do
    if type(v) == "function" then
      tinsert(keys, v())
    else
      tinsert(keys, ":" .. k)
    end
  end

  return ("values(%s)"):format(tconcat(keys, ", "))
end

---Format where part of a sql statement.
---@params defs table: key/value pairs defining sqlite table keys.
---@params name string: the name of the sqlite table
---@params join table: used as boolean, controling whether to use name.key or just key.
local pwhere = function(defs, name, join, contains)
  if not defs and not contains then
    return {}
  end

  local where = {}
  if defs then
    for k, v in u.opairs(defs) do
      k = join and name .. "." .. k or k

      if type(v) ~= "table" then
        if type(v) == "string" and (v:sub(1, 1) == "<" or v:sub(1, 1) == ">") then
          tinsert(where, k .. " " .. v)
        else
          tinsert(where, bind { v = v, k = k, s = " and " })
        end
      else
        if type(k) == "number" then
          tinsert(where, table.concat(v, " "))
        else
          tinsert(where, "(" .. bind { kv = v, k = k, s = " or " } .. ")")
        end
      end
    end
  end

  if contains then
    tinsert(where, pcontains(contains))
  end
  return ("where %s"):format(tconcat(where, " and "))
end

local plimit = function(defs)
  if not defs then
    return {}
  end

  local type = type(defs)
  local istbl = (type == "table" and defs[2])
  local offset = "limit %s offset %s"
  local limit = "limit %s"

  return istbl and offset:format(defs[1], defs[2]) or limit:format(type == "number" and defs or defs[1])
end

---Format set part of sql statement, usually used with update method.
---@params defs table: key/value pairs defining sqlite table keys.
local pset = function(defs)
  if not defs then
    return {}
  end

  return "set " .. bind { kv = defs, nonbind = true }
end

---Format join part of a sql statement.
---@params defs table: key/value pairs defining sqlite table keys.
---@params name string: the name of the sqlite table
local pjoin = function(defs, name)
  if not defs or not name then
    return {}
  end
  local target

  local on = (function()
    for k, v in pairs(defs) do
      if k ~= name then
        target = k
        return ("%s.%s ="):format(k, v)
      end
    end
  end)()

  local select = (function()
    for k, v in pairs(defs) do
      if k == name then
        return ("%s.%s"):format(k, v)
      end
    end
  end)()

  return ("inner join %s on %s %s"):format(target, on, select)
end

local porder_by = function(defs)
  -- TODO: what if nulls? should append "nulls last"
  if not defs then
    return {}
  end

  local fmt = "%s %s"
  local items = {}

  for v, k in u.opairs(defs) do
    if type(k) == "table" then
      for _, _k in u.opairs(k) do
        tinsert(items, fmt:format(_k, v))
      end
    else
      tinsert(items, fmt:format(k, v))
    end
  end

  return ("order by %s"):format(tconcat(items, ", "))
end

local partial = function(method, tbl, opts)
  opts = opts or {}
  return tconcat(
    u.flatten {
      method,
      pkeys(opts.values),
      pvalues(opts.values, opts.named),
      pset(opts.set),
      pwhere(opts.where, tbl, opts.join, opts.contains),
      porder_by(opts.order_by),
      plimit(opts.limit),
    },
    " "
  )
end

local pselect = function(select)
  local t = type(select)

  if t == "table" and next(select) ~= nil then
    local items = {}
    for k, v in pairs(select) do
      if type(k) == "number" then
        tinsert(items, v)
      else
        local z = type(v) == "function" and v() or v
        tinsert(items, ("%s as %s"):format(z, k))
      end
    end

    return tconcat(items, ", ")
  end

  return t == "string" and select or "*"
end

---Parse select statement to extracts data from a database
---@param tbl string: table name
---@param opts table: lists of options: valid{ select, join, order_by, limit, where }
---@return string: the select sql statement.
M.select = function(tbl, opts)
  opts = opts or {}
  local cmd = opts.unique and "select distinct %s" or "select %s"
  local select = pselect(opts.select)
  local stmt = (cmd .. " from %s"):format(select, tbl)
  local method = opts.join and stmt .. " " .. pjoin(opts.join, tbl) or stmt
  return partial(method, tbl, opts)
end

---Parse select statement to update data in the database
---@param tbl string: table name
---@param opts table: lists of options: valid{ set, where }
---@return string: the update sql statement.
M.update = function(tbl, opts)
  local method = ("update %s"):format(tbl)
  return partial(method, tbl, opts)
end

---Parse insert statement to insert data into a database
---@param tbl string: table name
---@param opts table: lists of options: valid{ where }
---@return string: the insert sql statement.
M.insert = function(tbl, opts)
  local method = ("insert into %s"):format(tbl)
  return partial(method, tbl, opts)
end

---Parse delete statement to deletes data from a database
---@param tbl string: table name
---@param opts table: lists of options: valid{ where }
---@return string: the delete sql statement.
M.delete = function(tbl, opts)
  opts = opts or {}
  local method = ("delete from %s"):format(tbl)
  local where = pwhere(opts.where)
  return type(where) == "string" and method .. " " .. where or method
end

local format_action = function(value, update)
  local stmt = update and "on update" or "on delete"
  local preappend = (value:match "default" or value:match "null") and " set " or " "

  return stmt .. preappend .. value
end

local opts_to_str = function(tbl)
  local f = {
    pk = function()
      return "primary key"
    end,
    type = function(v)
      return v
    end,
    unique = function()
      return "unique"
    end,
    required = function(v)
      if v then
        return "not null"
      end
    end,
    default = function(v)
      v = type(v) == "function" and "(" .. tostring(v()) .. ")" or v
      local str = "default "
      if tbl["required"] then
        return "on conflict replace " .. str .. v
      else
        return str .. v
      end
    end,
    reference = function(v)
      return ("references %s"):format(v:gsub("%.", "(") .. ")")
    end,
    on_update = function(v)
      return format_action(v, true)
    end,
    on_delete = function(v)
      return format_action(v)
    end,
  }

  f.primary = f.pk

  local res = {}

  if type(tbl[1]) == "string" then
    res[1] = tbl[1]
  end

  local check = function(type)
    local v = tbl[type]
    if v then
      res[#res + 1] = f[type](v)
    end
  end

  check "type"
  check "unique"
  check "required"
  check "pk"
  check "primary"
  check "default"
  check "reference"
  check "on_update"
  check "on_delete"

  return tconcat(res, " ")
end

---Parse table create statement
---@param tbl string: table name
---@param defs table: keys and type pairs
---@return string: the create sql statement.
M.create = function(tbl, defs, ignore_ensure)
  if not defs then
    return
  end
  local items = {}

  tbl = (defs.ensure and not ignore_ensure) and "if not exists " .. tbl or tbl

  for k, v in u.opairs(defs) do
    if k ~= "ensure" then
      local t = type(v)
      if t == "boolean" then
        tinsert(items, k .. " integer not null primary key")
      elseif t ~= "table" then
        tinsert(items, string.format("%s %s", k, v))
      else
        if u.is_list(v) then
          tinsert(items, ("%s %s"):format(k, tconcat(v, " ")))
        else
          tinsert(items, ("%s %s"):format(k, opts_to_str(v)))
        end
      end
    end
  end
  return ("CREATE TABLE %s(%s)"):format(tbl, tconcat(items, ", "))
end

---Parse table drop statement
---@param tbl string: table name
---@return string: the drop sql statement.
M.drop = function(tbl)
  return "drop table " .. tbl
end

-- local same_type = function(new, old)
--   if not new or not old then
--     return false
--   end

--   local tnew, told = type(new), type(old)

--   if tnew == told then
--     if tnew == "string" then
--       return new == old
--     elseif tnew == "table" then
--       if new[1] and old[1] then
--         return (new[1] == old[1])
--       elseif new.type and old.type then
--         return (new.type == old.type)
--       elseif new.type and old[1] then
--         return (new.type == old[1])
--       elseif new[1] and old.type then
--         return (new[1] == old.type)
--       end
--     end
--   else
--     if tnew == "table" and told == "string" then
--       if new.type == old then
--         return true
--       elseif new[1] == old then
--         return true
--       end
--     elseif tnew == "string" and told == "table" then
--       return old.type == new or old[1] == new
--     end
--   end
--   -- return false
-- end

---Alter a given table, only support changing key definition
---@param tname string
---@param new sqlite_schema_dict
---@param old sqlite_schema_dict
M.table_alter_key_defs = function(tname, new, old, dry)
  local tmpname = tname .. "_new"
  local create = M.create(tmpname, new, true)
  local drop = M.drop(tname)
  local move = "INSERT INTO %s(%s) SELECT %s FROM %s"
  local rename = ("ALTER TABLE %s RENAME TO %s"):format(tmpname, tname)
  local with_foregin_key = false

  for _, def in pairs(new) do
    if type(def) == "table" and def.reference then
      with_foregin_key = true
    end
  end

  local stmt = "PRAGMA foreign_keys=off; BEGIN TRANSACTION; %s; COMMIT;"
  if not with_foregin_key then
    stmt = stmt .. " PRAGMA foreign_keys=on"
  end

  local keys = { new = u.okeys(new), old = u.okeys(old) }
  local idx = { new = {}, old = {} }
  local len = { new = #keys.new, old = #keys.old }
  -- local facts = { extra_key = len.new > len.old, drop_key = len.old > len.new }

  a.auto_alter_should_have_equal_len(len.new, len.old, tname)

  for _, varient in ipairs { "new", "old" } do
    for k, v in pairs(keys[varient]) do
      idx[varient][v] = k
    end
  end

  for i, v in ipairs(keys.new) do
    if idx.old[v] and idx.old[v] ~= i then
      local tmp = keys.old[i]
      keys.old[i] = v
      keys.old[idx.old[v]] = tmp
    end
  end

  local update_null_vals = {}
  local update_null_stmt = "UPDATE %s SET %s=%s where %s IS NULL"
  for key, def in pairs(new) do
    if type(def) == "table" and def.default and not def.required then
      tinsert(update_null_vals, update_null_stmt:format(tmpname, key, def.default, key))
    end
  end
  update_null_vals = #update_null_vals == 0 and "" or tconcat(update_null_vals, "; ")

  local new_keys, old_keys = tconcat(keys.new, ", "), tconcat(keys.old, ", ")
  local insert = move:format(tmpname, new_keys, old_keys, tname)
  stmt = stmt:format(tconcat({ create, insert, update_null_vals, drop, rename }, "; "))

  return not dry and stmt or insert
end

---Pre-process data insert to sql db.
---for now it's mainly used to for parsing lua tables and boolean values.
---It throws when a schema key is required and doesn't exists.
---@param rows tinserted row.
---@param schema table tbl schema with extra info
---@return table pre processed rows
M.pre_insert = function(rows, schema)
  local res = {}
  rows = u.is_nested(rows) and rows or { rows }
  for i, row in ipairs(rows) do
    res[i] = u.map(row, function(v, k)
      local column_def = schema[k]
      a.should_have_column_def(column_def, k, schema)
      a.missing_req_key(v, column_def)
      local is_json = column_def.type == "luatable" or column_def.type == "json"
      return is_json and json.encode(v) or M.sqlvalue(v)
    end)
  end
  return res
end

---Postprocess data queried from a sql db. for now it is mainly used
---to for parsing json values to lua table.
---@param rows tinserted row.
---@param schema table tbl schema
---@return table pre processed rows
---@TODO support boolean values.
M.post_select = function(rows, schema)
  local is_nested = u.is_nested(rows)
  rows = is_nested and rows or { rows }
  for _, row in ipairs(rows) do
    for k, v in pairs(row) do
      local info = schema[k]
      if info then
        row[k] = M.luavalue(v, info.type)
      else
        row[k] = v
      end
    end
  end

  return is_nested and rows or rows[1]
end

return M
