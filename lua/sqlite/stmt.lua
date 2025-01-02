---@brief [[
--- sqlstmt is a collection of methods to deal with sqlite statements.
---@brief ]]
---@tag sqlstmt
local clib = require "sqlite.defs"
local flags = clib.flags

---@class sqlstmt @Object to deal with sqlite statements
---@field pstmt sqlite_blob sqlite_pstmt
---@field conn sqlite_blob sqlite3 object
---@field str string original statement
local sqlstmt = {}
sqlstmt.__index = sqlstmt

--- TODO: refactor and make parser.lua required here only.

---Parse a statement
---@param conn sqlite3: the database connection.
---@param str string: the sqlite statement to be parsed.
---@return sqlstmt: collection of methods, applicable to the parsed statement.
---@see sqlstmt:__parse
---@usage local sqlstmt = sqlstmt:parse(db, "insert into todos (title,desc) values(:title, :desc)")
function sqlstmt:parse(conn, str)
  assert(clib.type_of(conn) == clib.type_of_db_ptr, "Invalid connection passed to sqlstmt:parse")
  assert(type(str) == "string", "Invalid second argument passed to sqlstmt:parse")
  local o = setmetatable({
    str = str,
    conn = conn,
    finalized = false,
  }, sqlstmt)

  local pstmt = clib.get_new_stmt_ptr()
  local code = clib.prepare_v2(o.conn, o.str, #o.str, pstmt, nil)

  assert(
    code == flags.ok,
    string.format(
      "sqlite.lua\n(parse error): `%s` code == %d\nstatement == '%s'",
      clib.to_str(clib.errmsg(self.conn)),
      code,
      self.str
    )
  )

  o.pstmt = pstmt[0]
  return o

end

---Resets the parsed statement. required for parsed statements to be re-executed.
---NOTE: Any statement variables that had values bound to them using the
---sqlstmt:bind functions retain their values.
---@return number: falgs.ok or errcode
---@TODO should we error out when errcode?
function sqlstmt:reset()
  return clib.reset(self.pstmt)
end

---Frees the prepared statement
---@return boolean: if no error true.
function sqlstmt:finalize()
  self.errcode = clib.finalize(self.pstmt)
  self.finalized = self.errcode == flags.ok
  assert(
    self.finalized,
    string.format(
      "sqlite.lua: couldn't finalize statement, ERRMSG: %s stmt = (%s)",
      clib.to_str(clib.errmsg(self.conn)),
      self.str
    )
  )
  return self.finalized
end

---Called before evaluating the (next iteration) of the prepared statement.
---@return sqlite_flags: Possible Flags: { flags.busy, flags.done, flags.row, flags.error, flags.misuse }
function sqlstmt:step()
  local step_code = clib.step(self.pstmt)
  assert(
    step_code ~= flags.error or step_code ~= flags.misuse,
    string.format("sqlite.lua: error in step(), ERRMSG: %s. Please report issue.", clib.to_str(clib.errmsg(self.conn)))
  )
  return step_code
end

---Number of keys/columns in results
---@return number: column count in the results.
function sqlstmt:nkeys()
  return clib.column_count(self.pstmt)
end

---Number of rows/items in results.
---@return number: rows count in the results.
function sqlstmt:nrows()
  local count = 0
  self:each(function()
    count = count + 1
  end)
  return count
end

---key-name/column-name at {idx} in results.
---@param idx number: (0-index)
---@return string: keyname/column name at {idx}
---@TODO should accept 1-index
function sqlstmt:key(idx)
  return clib.to_str(clib.column_name(self.pstmt, idx))
end

---key-names/column-names in results.
---@return table: key-names/column-names.
---@see sqlstmt:nkeys
---@see sqlstmt:key
function sqlstmt:keys()
  local keys = {}
  for i = 0, self:nkeys() - 1 do
    table.insert(keys, i + 1, self:key(i))
  end
  return keys
end

local sqlite_datatypes = {
  [1] = "int", -- bind_double
  [2] = "double", -- bind_text
  [3] = "text", -- bind_null
  [4] = "blob", -- bind_null
  [5] = "null", -- bind_null
}

---Key/Column lua datatype at {idx}
---@param idx number: (0-index)
---@return string: key/column type at {idx}
---@TODO should accept 1-index
function sqlstmt:convert_type(idx)
  local convert_dt = {
    ["INTEGER"] = "number",
    ["FLOAT"] = "number",
    ["DOUBLE"] = "number",
    ["TEXT"] = "string",
    ["BLOB"] = "binary",
    ["NULL"] = nil,
  }
  return convert_dt[clib.to_str(clib.column_decltype(self.pstmt, idx))]
end

---Keys/Columns types visible in current result.
---@return table: list of types, ordered by key location.
---@see sqlstmt:type
---@see sqlstmt:nkeys
function sqlstmt:types()
  local types = {}
  for i = 0, self:nkeys() - 1 do
    table.insert(types, i + 1, self:convert_type(i))
  end
  return types
end

---Value at {idx}
---@param idx number: (0-index)
---@return string: value at {idx}
---@TODO should accept 1-index
function sqlstmt:val(idx)
  local ktype = clib.column_type(self.pstmt, idx)
  if ktype == 5 then
    return
  end
  local val = clib["column_" .. sqlite_datatypes[ktype]](self.pstmt, idx)
  return ktype == 3 and clib.to_str(val) or val
end

---Ordered list of current result values.
---@return table: list of values, ordered by key location.
---@see sqlstmt:val
---@see sqlstmt:nkeys
function sqlstmt:vals()
  local vals = {}
  for i = 0, self:nkeys() - 1 do
    table.insert(vals, i + 1, self:val(i))
  end
  return vals
end

---Key/value pair in current result.
---@return table: key/value pair of a row.
---@see sqlstmt:key
---@see sqlstmt:val
---@see sqlstmt:nkeys
function sqlstmt:kv()
  local ret = {}
  for i = 0, self:nkeys() - 1 do
    ret[self:key(i)] = self:val(i)
  end
  return ret
end

---Key/type pair in current result.
---@return table: key/type pair of a row.
---@see sqlstmt:key
---@see sqlstmt:val
---@see sqlstmt:nkeys
function sqlstmt:kt()
  local ret = {}
  for i = 0, self:nkeys() - 1 do
    ret[self:key(i)] = self:convert_type(i)
  end
  return ret
end

---sqlstmt:next:
---If code == flags.row it returns
---If code == flags.done it reset the parsed statement
function sqlstmt:next()
  local code = self:step()
  if code == flags.row then
    return self
  elseif code == flags.done then
    self:reset()
  else
    return nil, code
  end
end

---sqlstmt:iter
---@see sqlstmt:next
function sqlstmt:iter()
  return self:next(), self.pstmt
end

---Loops through results with {callback} until there is no row left.
---@param callback function: a function to be called on each number of row.
---@usage sqlstmt:each(function(s)  print(s:val(1))  end)
---@see sqlstmt:step
function sqlstmt:each(callback)
  assert(type(callback) == "function", "sqlstmt:each expected a function, got something else.")
  while self:step() == flags.row do
    callback(self)
  end
end

---Loops through the results and if {callback} pass to it row, else return nested kv pairs.
---@param callback function: a function to be called with each row.
---@return table: if no callback then nested key-value pairs
---@see sqlstmt:kv
---@see sqlstmt:each
function sqlstmt:kvrows(callback)
  local kv = {}
  self:each(function()
    local row = self:kv()
    if callback then
      return callback(row)
    else
      table.insert(kv, row)
    end
  end)
  if not callback then
    return kv
  end
end

---Like sqlstmt:kvrows but passed list of values instead of kv pairs.
---@param callback function: a function to be called with each row.
---@return table: if no callback then nested lists of values in each row.
---@see sqlstmt:vals
---@see sqlstmt:each
function sqlstmt:vrows(callback)
  local vals = {}
  self:each(function(s)
    local row = s:vals()
    if callback then
      return callback(row)
    else
      table.insert(vals, row)
    end
  end)
  if not callback then
    return vals
  end
end

local bind_type_to_func = {
  ["number"] = "double", -- bind_double
  ["string"] = "text", -- bind_text
  ["nil"] = "null", -- bind_null
}

---Bind {args[2]} at {args[1]} or kv pairs {args[1]}.
---If {args[1]} is a number and {args[2]} is a value then it binds by index.
---Else first argument is a table, then it binds the table to indicies, and it
---works with named and unnamed.
---@varargs if {args[1]} number and {args[2]} or {args[1]} table
---@see sqlstmt:nparam
---@see sqlstmt:param
---@see sqlstmt:bind
function sqlstmt:bind(...)
  local args = { ... }
  -- bind by table
  if type(args[1]) == "table" then
    local names = args[1]
    local parameter_index_cache = {}
    local anon_indices = {}
    for i = 1, self:nparam() do
      local name = self:param(i)
      if name == "?" then
        table.insert(anon_indices, i)
      else
        parameter_index_cache[name:sub(2, -1)] = i
      end
    end

    for k, v in pairs(names) do
      local index = parameter_index_cache[k] or table.remove(anon_indices, 1)
      if ((type(v) == "string" and v:match "^[%S]+%(.*%)$") and flags.ok or self:bind(index, v)) ~= flags.ok then
        error("sqlite.lua error at stmt:bind(), failed to bind a given value '%s'. Please report issue."):format(v)
      end
    end
    return flags.ok
  end

  -- bind by index
  if type(args[1]) == "number" and args[2] then
    local idx, value = args[1], args[2]
    local func = bind_type_to_func[type(value)]
    local len = func == "text" and #value or nil

    if not func then
      return error [[
        sqlite.lua error at stmt:bind(): Unrecognized or unsupported type.
        Please report issue.
      ]]
    end

    if len then
      return clib["bind_" .. func](self.pstmt, idx, value, len, nil)
    else
      if value then
        return clib["bind_" .. func](self.pstmt, idx, value)
      else
        return clib["bind_" .. func](self.pstmt, idx)
      end
    end
  end
end

---Binds a blob at {idx} with {size}
---@param idx number: index starting at 1
---@param pointer sqlite_blob: blob to bind
---@param size number: pointer size
---@return sqlite_flags
function sqlstmt:bind_blob(idx, pointer, size)
  return clib.bind_blob64(self.pstmt, idx, pointer, size, nil) -- Always 64? or two functions
end

---Binds zeroblob at {idx} with {size}
---@param idx number: index starting at 1
---@param size number: zeroblob size
---@return sqlite_flags
function sqlstmt:bind_zeroblob(idx, size)
  return clib.bind_zeroblob64(self.pstmt, idx, size)
end

---The number of parameter to bind.
---@return number: number of params in {sqlstmt.pstmt}
function sqlstmt:nparam()
  if not self.parm_count then
    self.parm_count = clib.bind_parameter_count(self.pstmt)
  end

  return self.parm_count
end

---The parameter key/name at {idx}
---@param idx number: index starting at 1
---@return string: param key ":key" at {idx}
function sqlstmt:param(idx)
  return clib.to_str(clib.bind_parameter_name(self.pstmt, idx)) or "?"
end

---Parameters keys/names
---@return table: paramters key/names in {sqlstmt.pstmt}
---@see sqlstmt:nparam
---@see sqlstmt:param
function sqlstmt:params()
  local res = {}
  for i = 1, self:nparam() do
    table.insert(res, self:param(i))
  end
  return res
end

---Clear the current bindings.
---@return sqlite_flags
function sqlstmt:bind_clear()
  self.current_bind_index = nil
  return clib.clear_bindings(self.pstmt)
end

---Bind the value at the next index until all values are bound
---@param value any: value to bind
---@return sqlite_flags
---@TODO does it return sqlite_flag in all cases? @conni
function sqlstmt:bind_next(value)
  if not self.current_bind_index then
    self.current_bind_index = 1
  end

  if self.current_bind_index <= self:nparam() then
    local ret = self:bind(self.current_bind_index, value)
    self.current_bind_index = self.current_bind_index + 1
    return ret
  end
  return flags.error -- TODO(conni): should error out?
end

---Expand the resulting statement after binding, used for debugging purpose.
---@return string: the resulting statement that can be finalized.
function sqlstmt:expand()
  return clib.to_str(clib.expanded_sql(self.pstmt))
end

return sqlstmt
