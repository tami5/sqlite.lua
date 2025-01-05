local p = require "sqlite.parser"
local fn = require("sqlite.strfun").fn
local eq = assert.are.same

describe("parse", function()
  local tbl = "todo"
  describe("[insert]", function()
    it("post function without key in values", function()
      eq(
        "insert into todo (date, id) values(date('now'), :id)",
        p.insert(tbl, { values = {
          date = fn "date('now')",
          id = 1,
        } })
      )
    end)
  end)

  describe("[all]", function()
    it("select all", function()
      local sqlstmt = p.select(tbl)
      eq("select * from todo", sqlstmt, "It should be identical")
    end)
    it("delete all", function()
      local sqlstmt = p.delete(tbl)
      eq("delete from todo", sqlstmt, "It should be identical")
    end)
  end)

  describe("[where]", function()
    it("single key = value", function()
      local where = { id = 1 }
      local pselect = p.select(tbl, { where = where })
      local eselect = "select * from todo where id = 1"
      eq(eselect, pselect, "It should be identical")
    end)
    it("multi key", function()
      local where = { id = 1, act = "done" }
      local pselect = p.select(tbl, { where = where })
      local eselect = "select * from todo where act = 'done' and id = 1"
      eq(eselect, pselect, "It should be identical")
    end)
    it("with [or] for single keys", function()
      local where = { act = { "done", "overdue" } }
      local pselect = p.select(tbl, { where = where })
      local eselect = "select * from todo where (act = 'done' or act = 'overdue')"
      eq(eselect, pselect, "It should be identical")
    end)
    it("with [or] for multi keys", function()
      local where = {
        act = { "done", "overdue" },
        name = "conni",
        date = 2021,
      }
      local pselect = p.select(tbl, { where = where })
      local eselect = "select * from todo where (act = 'done' or act = 'overdue') and date = 2021 and name = 'conni'"
      eq(eselect, pselect, "It should be identical")
    end)
    it("with multi [or] and multi keys", function()
      local where = {
        n = { 1, 2, 3 },
        act = { "a", "b" },
        date = 2021,
      }
      local pselect = p.select(tbl, { where = where })
      local eselect = "select * from todo where (act = 'a' or act = 'b') and date = 2021 and (n = 1 or n = 2 or n = 3)"
      eq(eselect, pselect, "It should be identical")
    end)
    it("interop boolean", function()
      local where = {
        act = false,
        n = true,
        date = 2021,
      }
      local eselect = "select * from todo where act = 0 and date = 2021 and n = 1"
      local pselect = p.select(tbl, { where = where })
      eq(eselect, pselect, "It should be identical")
    end)
    it("handles quotes", function()
      local where = { a = "I'm", c = "it's" }
      local eselect = [[select * from todo where a = "I'm" and c = "it's"]]
      local pselect = p.select(tbl, { where = where })
      eq(eselect, pselect, "It should be identical")
    end)
    it("concat list and pass it as query", function()
      local where = { { "date", "<", 2021 } }
      local where = { date = "< 2021" }
      local eselect = [[select * from todo where date < 2021]]
      local pselect = p.select(tbl, { where = where })
      eq(eselect, pselect)
    end)
  end)

  describe("[set]", function()
    it("single value and [where]", function()
      local set = { date = 2021 }
      local where = { id = 1 }
      local pupdate = p.update(tbl, { where = where, set = set })
      local eupdate = "update todo set date = :date where id = 1"
      eq(eupdate, pupdate, "should be identical")
    end)
    it("multiple value and where", function()
      local set = { date = 2021, a = "b", c = "d" }
      local where = { id = 1 }
      local pupdate = p.update(tbl, { where = where, set = set })
      local eupdate = "update todo set a = :a, c = :c, date = :date where id = 1"
      eq(eupdate, pupdate, "should be identical")
    end)
  end)

  describe("[create]", function()
    it("table", function()
      local defs = {
        id = { "integer", "primary", "key" },
        title = "text",
        desc = "text",
        created = "int",
        done = { "int", "not", "null", "default", 0 },
      }
      local expected =
        "CREATE TABLE todos(created int, desc text, done int not null default 0, id integer primary key, title text)"
      local passed = p.create("todos", defs)
      eq(expected, passed, "should be identical")
    end)

    it("ensure that the table is created", function()
      local defs = {
        id = { "integer", "primary", "key" },
        name = "text",
        age = "int",
        ensure = true,
      }
      local expected = "CREATE TABLE if not exists people(age int, id integer primary key, name text)"
      local passed = p.create("people", defs)
      eq(expected, passed, "should be identical")
    end)

    it("ensure that the table is created with a key being true", function()
      local defs = {
        id = true,
        name = "text",
        age = "int",
        ensure = true,
      }
      local expected = "CREATE TABLE if not exists people(age int, id integer not null primary key, name text)"
      local passed = p.create("people", defs)
      eq(expected, passed, "should be identical")
    end)

    it("key-pair: nullable & unique", function()
      local defs = {
        id = true,
        name = { "text", required = true, unique = true },
      }
      local passed = p.create("people", defs)
      local expected = "CREATE TABLE people(id integer not null primary key, name text unique not null)"
      eq(expected, passed, "should be identical")
    end)
    it("key-pair: default value", function()
      local defs = {
        id = true,
        name = { "text", default = "unknown" },
      }
      local passed = p.create("people", defs)
      local expected = "CREATE TABLE people(id integer not null primary key, name text default unknown)"
      eq(expected, passed, "should be identical")
    end)

    it("key-pair: type", function()
      local defs = {
        id = true,
        name = { type = "text" },
      }
      local passed = p.create("people", defs)
      local expected = "CREATE TABLE people(id integer not null primary key, name text)"
      eq(expected, passed, "should be identical")
    end)

    it("primary key", function()
      local defs = {
        id = { type = "integer", pk = true },
        name = { type = "text", default = "noname" },
      }
      local passed = p.create("people", defs)
      local expected = {
        "CREATE TABLE people(",
        "id integer primary key, ",
        "name text default noname",
        ")",
      }

      eq(table.concat(expected, ""), passed, "should be identical")
    end)
    it("foreign key", function()
      local defs = {
        id = true,
        name = { "text", default = "unknown" },
        job_id = {
          type = "integer",
          reference = "jobs.id",
        },
      }
      local passed = p.create("people", defs)
      local expected = {
        "CREATE TABLE people(",
        "id integer not null primary key, ",
        "job_id integer references jobs(id), ",
        "name text default unknown",
        ")",
      }

      eq(table.concat(expected, ""), passed, "should be identical")
    end)

    it("foreign key + single action", function()
      local defs = {
        id = true,
        name = { "text", default = "unknown" },
        job_id = {
          type = "integer",
          reference = "jobs.id",
          on_update = "cascade",
        },
      }
      local passed = p.create("people", defs)
      local expected = {
        "CREATE TABLE people(",
        "id integer not null primary key, ",
        "job_id integer references jobs(id) on update cascade, ",
        "name text default unknown",
        ")",
      }

      eq(table.concat(expected, ""), passed, "should be identical")
    end)

    it("foreign key + multi action", function()
      local defs = {
        id = true,
        name = { "text", default = "unknown" },
        job_id = {
          type = "integer",
          reference = "jobs.id",
          on_update = "cascade",
          on_delete = "null",
        },
      }
      local passed = p.create("people", defs)
      local expected = {
        "CREATE TABLE people(",
        "id integer not null primary key, ",
        "job_id integer references jobs(id) on update cascade on delete set null, ",
        "name text default unknown",
        ")",
      }

      eq(table.concat(expected, ""), passed, "should be identical")
    end)
  end)

  describe("[select]", function()
    it('works with [select] = "a single string"', function()
      local defs = {
        select = {
          "id",
          z = fn "date('now')",
        },
      }
      local expected = "select id, date('now') as z from people"
      local passed = p.select("people", defs)
      eq(expected, passed, "should be identical")
    end)
  end)

  describe("[order by]", function()
    it("works with signle table name", function()
      local defs = {
        select = { "id", "name" },
        order_by = {
          desc = "name",
          asc = "id",
        },
      }
      local expected = "select id, name from people order by id asc, name desc"
      local passed = p.select("people", defs)
      eq(expected, passed, "should be identical")
    end)
    it("works with multiple table name", function()
      local defs = {
        select = { "id", "name" },
        order_by = {
          asc = { "name", "age" },
        },
      }
      local expected = "select id, name from people order by name asc, age asc"
      local passed = p.select("people", defs)
      eq(expected, passed, "should be identical")
    end)
    it('works with [select] = "a single string"', function()
      local defs = {
        select = "id",
        order_by = {
          asc = { "name", "age" },
        },
      }
      local expected = "select id from people order by name asc, age asc"
      local passed = p.select("people", defs)
      eq(expected, passed, "should be identical")
    end)
  end)

  describe("[distinct]", function()
    -- remove duplicate from result set
    it("with single key", function()
      local defs = { -- TODO: works for a single key
        select = { "id", "name" },
        unique = true,
      }
      local expected = "select distinct id, name from people"
      local passed = p.select("people", defs)
      eq(expected, passed, "should be identical")
    end)
  end)

  describe("[limit]", function()
    it("with limit as number", function()
      local defs = {
        select = { "id", "name" },
        limit = 10,
      }
      local expected = "select id, name from people limit 10"
      local passed = p.select("people", defs)
      eq(expected, passed, "should be identical")
    end)
    it("with limit as number inside list", function()
      local defs = {
        select = { "id", "name" },
        limit = { 10 },
      }
      local expected = "select id, name from people limit 10"
      local passed = p.select("people", defs)
      eq(expected, passed, "should be identical")
    end)
    it("with limit and offset", function()
      local defs = {
        select = { "id", "name" },
        limit = { 10, 10 },
      }
      local expected = "select id, name from people limit 10 offset 10"
      local passed = p.select("people", defs)
      eq(expected, passed, "should be identical")
    end)
  end)

  describe("[glob]/contains", function()
    it("with single key", function()
      local defs = {
        select = { "id", "name" },
        contains = { name = "%j" },
      }
      local expected = "select id, name from people where name glob '%j'"
      local passed = p.select("people", defs)
      eq(expected, passed, "should be identical")
    end)
    it("with single key and an list of patterns", function()
      local defs = {
        select = { "id", "name" },
        contains = { name = { "%j", "%a", "%b%" } },
      }
      local expected = "select id, name from people where name glob '%j' or name glob '%a' or name glob '%b%'"
      local passed = p.select("people", defs)
      eq(expected, passed, "should be identical")
    end)
    it("with multi key and an list of patterns", function()
      local defs = {
        select = { "id", "name" },
        contains = {
          name = { "%j", "%a", "%b%" },
          last = "%f",
        },
      }
      local expected =
        "select id, name from people where last glob '%f' name glob '%j' or name glob '%a' or name glob '%b%'"
      local passed = p.select("people", defs)
      eq(expected, passed, "should be identical")
    end)
  end)
end)
