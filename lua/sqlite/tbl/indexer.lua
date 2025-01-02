local a = require "sqlite.assert"
local u = require "sqlite.utils"
---Get primary key from sqlite_tbl schema
---@param tbl sqlite_schema_dict
local get_primary_key = function(tbl)
  local pk
  for k, v in pairs(tbl or {}) do
    if type(v) == "table" and v.primary then
      pk = v
      if not pk.type then
        pk.type = pk[1]
      end
      pk.name = k
      break
    elseif type(v) == "boolean" and k ~= "ensure" then
      pk = {
        name = k,
        type = "integer",
        primary = true,
      }
      break
    end
  end

  return pk
end

---TODO: remove after using value should rawset and rawget in helpers.run, sqlite.tbl
local is_part_of_tbl_object = function(key)
  return key == "db"
    or key == "tbl_exists"
    or key == "db_schema"
    or key == "tbl_name"
    or key == "tbl_schema"
    or key == "mtime"
    or key == "has_content"
    or key == "_name"
end

local resolve_meta_key = function(kt, key)
  return kt == "string" and (key:sub(1, 2) == "__" and key:sub(3, -1) or key) or key
end

---Used to extend a table row to be able to manipulate the row values
---@param tbl sqlite_tbl
---@param pk sqlite_schema_key
---@return function(row, altkey):table
local tbl_row_extender = function(tbl, pk)
  return function(row, reqkey)
    row = row or {}
    local mt = {
      __newindex = function(_, key, val)
        tbl:update { -- TODO: maybe return inserted row??
          where = { [pk.name] = (row[pk.name] or reqkey) },
          set = { [key] = val },
        }
        row = {}
      end,
      __index = function(_, key)
        if key == "values" then
          return row
        end
        if not row[key] then
          local res = tbl:where { [pk.name] = row[pk.name] } or {}
          row = res
          return res[key]
        else
          return row[key]
        end
      end,
    }

    return setmetatable({}, mt)
  end
end

local sep_query_and_where = function(q, keys)
  local kv = { where = {} }
  for k, v in pairs(q) do
    if u.contains(keys, k) then
      kv.where[k] = v
    else
      kv[k] = v
    end
  end

  if next(kv.where) == nil then
    kv.where = nil
  end
  return kv
end

---Print errors to the user
---@param func function
-- local sc = function(func)
--   local ok, val = xpcall(func, function(msg)
--     print(msg)
--   end)
--   return ok and val
-- end

return function(tbl)
  local pk = get_primary_key(tbl.tbl_schema)
  local extend = tbl_row_extender(tbl, pk)
  local tbl_keys = u.keys(tbl.tbl_schema)
  local mt = {}

  mt.__index = function(_, arg)
    if is_part_of_tbl_object(arg) then
      return tbl[arg]
    end

    local kt = type(arg)
    local skey = resolve_meta_key(kt, arg)

    if not pk or (kt == "string" and tbl[skey]) then
      return tbl[skey]
    end

    if kt == "string" or kt == "number" and pk then
      a.should_match_pk_type(tbl.name, kt, pk, arg)
      return extend(
        tbl:where {
          [pk.name] = arg,
        },
        arg
      )
    end

    return kt == "table" and tbl:get(sep_query_and_where(arg, tbl_keys))
  end

  mt.__newindex = function(o, arg, val)
    if is_part_of_tbl_object(arg) then
      tbl[arg] = val
      return
    end

    local kt, vt = type(arg), type(val)

    if not pk or (vt == "function" and kt == "string") then
      rawset(o, arg, val)
      return
    end

    if vt == "nil" and kt == "string" or kt == "number" then
      tbl:remove { [pk.name] = arg }
    end

    if vt == "table" and kt == "table" then
      local q = sep_query_and_where(arg, tbl_keys)
      q.set = val
      tbl:update(q)
      return
    end

    if vt == "table" and pk then
      a.should_match_pk_type(tbl.name, kt, pk, arg)
      if arg == 0 or arg == true or arg == "" then
        return tbl:insert(val)
      else
        return tbl:update { where = { [pk.name] = arg }, set = val }
      end
    end
  end

  return setmetatable({ _config = {}, _state = {} }, mt)
end
