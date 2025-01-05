local M = {}
local u = require "sqlite.utils"

local customstr
customstr = function(str)
  local mt = getmetatable(str)

  local wrap = function(a_, b_, sign)
    local _str = ("%s %s %s"):format(a_, sign, b_)
    if u.is_str(b_) and b_:match "^%a+%(.+%)$" then
      _str = "(" .. _str .. ")"
    end
    return _str
  end

  mt._a_dd = function(a_, b_)
    return wrap(a_, b_, "+")
  end
  mt.__sub = function(a_, b_)
    return wrap(a_, b_, "-")
  end
  mt.__mul = function(a_, b_)
    return wrap(a_, b_, "*")
  end
  mt.__div = function(a_, b_)
    return wrap(a_, b_, "/")
  end
  mt.__pow = function(a_, b_)
    return wrap(a_, b_, "^")
  end
  mt.__mod = function(a_, b_)
    return wrap(a_, b_, "%")
  end

  return str
end

local ts = function(ts)
  local str
  if ts ~= "now" and (type(ts) == "string" and not ts:match "%d") then
    str = "%s"
  else
    str = "'%s'"
  end
  return str:format(ts or "now")
end

---Format date according {format}
---@param format string the format
---     %d 	day of month: 00
---     %f 	fractional seconds: SS.SSS
---     %H 	hour: 00-24
---     %j 	day of year: 001-366
---     %J 	Julian day number
---     %m 	month: 01-12
---     %M 	minute: 00-59
---     %s 	seconds since 1970-01-01
---     %S 	seconds: 00-59
---     %w 	day of week 0-6 with Sunday==0
---     %W 	week of year: 00-53
---     %Y 	year: 0000-9999
---     %% 	%
---@param timestring string timestamp to format 'deafult now'
---@return string: string representation or TEXT when evaluated.
---@usage `sqlstrftime('%Y %m %d','now')` -> 2021 8 11
---@usage `sqlstrftime('%H %M %S %s','now')` -> 12 40 18 1414759218
---@usage `sqlstrftime('%s','now') - strftime('%s','2014-10-07 02:34:56')` -> 2110042
M.strftime = function(format, timestring)
  local str = [[strftime('%s', %s)]]
  return M.fn(str:format(format, ts(timestring)))
end

---Return the number of days since noon in Greenwich on November 24, 4714 B.C.
---@param timestring string timestamp to format 'deafult now'
---@return string: string representation or REAL when evaluated.
---@usage `sqljulianday('now')` -> ...
---@usage `sqljulianday('now') - julianday('1947-08-15')` -> 24549.5019360879
M.julianday = function(timestring)
  local str = "julianday(%s)"
  return customstr(str:format(ts(timestring)))
end

---Returns date as "YYYY-MM-DD HH:MM:SS"
---@param timestring string timestamp to format 'deafult now'
---@return string: string representation or  "YYYY-MM-DD HH:MM:SS"
---@usage `sqldatetime('now')` -> 2021-8-11 11:31:52
M.datetime = function(timestring)
  local str = [[datetime('%s')]]
  return customstr(str:format(timestring or "now"))
end

---Returns time as HH:MM:SS.
---@param timestring string timestamp to format 'deafult now'
---@param modifier string: e.g. +60 seconds, +15 minutes
---@return string: string representation or "HH:MM:SS"
---@usage `sqltime()` -> "12:50:01"
---@usage `sqltime('2014-10-07 15:45:57.005678')` -> 15:45:57
---@usage `sqltime('now','+60 seconds')` 15:45:57 + 60 seconds
M.time = function(timestring, modifier)
  local str = [[time('%s')]]
  if modifier then
    str = [[time('%s', '%s')]]
    return customstr(str:format(timestring or "now", modifier))
  end

  return customstr(str:format(timestring or "now"))
end

---Returns date as YYYY-MM-DD
---@param timestring string timestamp to format 'deafult now'
---@param modifier string: e.g. +2 month, +1 year
---@return string: string representation or "HH:MM:SS"
---@usage `sqldate()` -> 2021-08-31
---@usage `sqldate('2021-08-07')` -> 2021-08-07
---@usage `sqldate('now','+2 month')` -> 2021-10-07
M.date = function(timestring, modifier)
  local str = [[date('%s')]]
  if modifier then
    str = [[date('%s', '%s')]]
    return customstr(str:format(timestring or "now", modifier))
  end

  return customstr(str:format(timestring or "now"))
end

---Cast a value as something
---@param source string: the value.
---@param as string: the type.
---@usage `cast((julianday() - julianday "timestamp") * 24 * 60, "integer")`
---@return string
M.cast = function(source, as)
  return string.format("cast(%s as %s)", source, as)
end

M.fn = function(s)
  return function()
    return s
  end
end

return M
