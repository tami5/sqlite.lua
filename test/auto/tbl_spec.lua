local sql = require "sqlite.db"
local tbl = require "sqlite.tbl"
local luv = require "luv"
local eq = assert.are.same
local P = require "sqlite.parser"
local demo = {
  { a = 1, b = "lsf", c = "de" },
  { a = 99, b = "sdj", c = "in" },
  { a = 32, b = "sbs", c = "en" },
  { a = 12, b = "srd", c = "fn" },
  { a = 35, b = "cba", c = "qa" },
  { a = 4, b = "pef", c = "ru" },
  { a = 5, b = "sam", c = "da" },
}

local dbpath = "/tmp/tbl_methods_test.sql"
luv.fs_unlink(dbpath)
local db = sql.new(dbpath)

local seed = function()
  db:open()
  db:create("T", { a = "integer", b = "text", c = "text", ensure = true })
  db:insert("T", demo)
  return db:tbl "T", db:tbl "N"
end

local clean = function()
  db:close()
  luv.fs_unlink(dbpath)
end

clean()
describe("sqlite.tbl", function()
  local t1, t2 = seed()

  describe(":new", function()
    it("create new object with sql.table methods.", function()
      eq("table", type(t1))
    end)
    it("registers table name in self.name.", function()
      eq("T", t1.name)
    end)
    it("registers whether the table exists in self.tbl_exists.", function()
      eq(true, t1.tbl_exists)
    end)
    it("registers whether the table has content in self.has_content.", function()
      eq(true, t1.has_content, "should be false")
    end)
    it("doesn't fail if table isn't created yat.", function()
      eq("table", type(t2))
    end)

    local opts = {
      schema = {
        id = "int",
        name = "text",
      },
    }
    local detailed_schema = {
      id = {
        cid = 0,
        primary = false,
        required = false,
        type = "INT",
      },
      name = {
        cid = 1,
        primary = false,
        required = false,
        type = "TEXT",
      },
    }
    local new = db:tbl("newtbl", opts)

    it("initalizes db with schema", function()
      -- NOTE: Hack to ensure the casing of types always match!! due to github actions
      local got_schema = new:schema()
      for k, v in pairs(got_schema) do
        v.type = string.upper(v.type)
        got_schema[k] = v
      end

      eq(detailed_schema, got_schema, "should be identical")
    end)
    it("should not rewrite schema.", function()
      local new2 = db:tbl "newtbl"

      -- NOTE: Hack to ensure the casing of types always match!! due to github actions
      local got_schema = new2:schema()
      for k, v in pairs(got_schema) do
        v.type = string.upper(v.type)
        got_schema[k] = v
      end

      eq(detailed_schema, got_schema, "should be identical")
      -- eq(detailed_schema, new2.tbl_schema, "should be identical")
      -- local new3 = db:tbl("newtbl", { schema = { id = "string" } })
      -- eq(detailed_schema, new3:schema(), "should be identical")
      -- eq(detailed_schema, new3.tbl_schema, "should be identical")
    end)
  end)

  describe(":schema", function()
    it("returns schema if self.tbl exists", function()
      -- NOTE: Hack to ensure the casing of types always match!! due to github actions
      local got_schema = t1:schema()
      for k, v in pairs(got_schema) do
        v.type = string.upper(v.type)
        got_schema[k] = v
      end

      eq({
        a = {
          cid = 0,
          primary = false,
          required = false,
          type = "INTEGER",
        },
        b = {
          cid = 1,
          primary = false,
          required = false,
          type = "TEXT",
        },
        c = {
          cid = 2,
          primary = false,
          required = false,
          type = "TEXT",
        },
      }, got_schema)
    end)
    it("returns empty table if schema doesn't exists", function()
      eq({}, t2:schema())
    end)
    it("creates new table with schema", function()
      local schema = {
        a = {
          cid = 0,
          primary = false,
          required = false,
          type = "TEXT",
        },
        d = {
          cid = 1,
          primary = false,
          required = false,
          type = "TEXT",
        },
        id = {
          cid = 2,
          primary = false,
          required = false,
          type = "INT",
        },
      }
      eq(true, t2:schema(schema), "Should return true")
      eq(schema, t2:schema(), "should return the schema.")
      eq(true, t2.tbl_exists, "should alter self.exists value")
    end)
    it("should drop and recreate the table if not schema.ensure", function()
      local new = {
        a = {
          cid = 0,
          primary = false,
          required = false,
          type = "TEXT",
        },
        f = {
          cid = 1,
          primary = false,
          required = false,
          type = "TEXT",
        },
        id = {
          cid = 2,
          primary = false,
          required = false,
          type = "INT",
        },
      }
      eq(true, t2:schema(new), "Should return true")
      eq(new, t2:schema(), "should return the schema.")
      eq(true, t2.tbl_exists, "should alter self.exists value")
    end)
    it("should skip looking at the schema if schema.ensure", function()
      local old = t2:schema()
      local new = { i = "int", aaa = "text", fff = "text", ensure = true }
      eq(true, t2:schema(new), "Should return true")
      eq(old, t2:schema(), "should return the schema.")
    end)
  end)

  describe(":drop/:exists", function()
    it("should drop table", function()
      eq(true, t2:drop(), "should return true")
      eq(false, t2:exists(), "should not exists.")
    end)
    it("should return false if already dropped", function()
      eq(false, t2:drop(), "should be false")
    end)
  end)

  describe(":get", function()
    it("return everything.", function()
      local res = t1:get()
      eq(demo, res, "should be identical")
    end)

    it("runs a query and returns results (where)", function()
      local res = t1:get { where = { a = 1 } }
      eq(demo[1], res[1], "should be identical")
    end)

    it("runs a query and returns results (where & keys)", function()
      local res = t1:get { keys = { "b", "c" }, where = { a = 1 } }
      demo[1].a = nil
      eq(demo[1], res[1], "should be identical")
      demo[1].a = 1
    end)

    it("runs a query and returns results (keys & limit)", function()
      local limit = 3
      local res = t1:get { keys = { "a" }, limit = limit }
      eq(res[1].b, nil, "should not have the key")
      eq(res[1].c, nil, "should not have the key")
      eq(#res, limit, "they should be the same")
    end)

    it("run a query and returns results when connection is closed.", function()
      db:close()
      local res = t1:get { where = { a = 99 } }
      eq(demo[2], res[1], "should be identical")
    end)

    it("the db should stay closed after doing the query.", function()
      eq(true, t1.db.closed, "should update the state")
      eq(true, db.closed, "should update the state")
      db:open()
    end)
  end)

  it(":where", function()
    it("runs a query and returns results (where) with kv pairs", function()
      local res = t1:where { a = 1 }
      eq(demo[1], res, "should be identical")
    end)
  end)

  describe(":each", function()
    it("should work func", function()
      local res = {}
      eq(
        true,
        t1:each({ where = { a = { 12, 99, 32 } } }, function(row)
          table.insert(res, row.a)
        end),
        "the number of rows"
      )
      eq(res, { 99, 32, 12 }, "should be identical") -- this might fail at some point because of the ordering.
    end)
    it("supports function as first argument", function()
      local res = {}
      eq(
        true,
        t1:each(function(row)
          table.insert(res, row.a)
        end, { where = { a = { 12, 99, 32 } } }),
        "the number of rows"
      )
      eq(res, { 99, 32, 12 }, "should be identical")
    end)
    it("supports function as first argument with no query", function()
      local res = {}
      eq(
        true,
        t1:each(function(row)
          table.insert(res, row.a)
        end),
        "the number of rows"
      )
      eq(res, { 1, 99, 32, 12, 35, 4, 5 }, "should be identical")
    end)
  end)

  describe(":map", function()
    it("should work func", function()
      local res = t1:map({ where = { a = { 12, 99, 32 } } }, function(row)
        return row.a
      end)
      eq(res, { 99, 32, 12 }, "should be identical") -- this might fail at some point because of the ordering.
    end)
    it("support function as first argument", function()
      local res = t1:map(function(row)
        return row.a
      end, { where = { a = { 12, 99, 32 } } })
      eq(res, { 99, 32, 12 }, "should be identical") -- this might fail at some point because of the ordering.
    end)
    it("support function as first argument with no query", function()
      local res = t1:map(function(row)
        return row.a
      end)
      eq(res, { 1, 99, 32, 12, 35, 4, 5 }, "should be identical") -- this might fail at some point because of the ordering.
    end)
  end)

  describe(":sort", function()
    it("transform function defaults to to first where key", function()
      eq(
        {
          { a = 4, b = "pef", c = "ru" },
          { a = 5, b = "sam", c = "da" },
          { a = 35, b = "cba", c = "qa" },
        },
        t1:sort {
          where = { a = { 35, 4, 5 } },
        },
        "should be identical"
      )
    end)

    it("transform function can be a string with row key ", function()
      eq({
        { a = 12, b = "srd", c = "fn" },
        { a = 32, b = "sbs", c = "en" },
        { a = 35, b = "cba", c = "qa" },
      }, t1:sort({ where = { a = { 32, 12, 35 } } }, "a"))
      eq({
        { a = 32, b = "sbs", c = "en" },
        { a = 12, b = "srd", c = "fn" },
        { a = 35, b = "cba", c = "qa" },
      }, t1:sort({ where = { a = { 32, 12, 35 } } }, "c"))
      eq({
        { a = 35, b = "cba", c = "qa" },
        { a = 32, b = "sbs", c = "en" },
        { a = 12, b = "srd", c = "fn" },
      }, t1:sort({ where = { a = { 32, 12, 35 } } }, "b"))
    end)

    it("can use a custom comparison function", function()
      local comp = function(a, b)
        return a > b
      end
      eq({
        { a = 12, b = "srd", c = "fn" },
        { a = 32, b = "sbs", c = "en" },
        { a = 35, b = "cba", c = "qa" },
      }, t1:sort({ where = { a = { 32, 12, 35 } } }, "b", comp))
    end)
  end)

  describe(":remove", function()
    it("removes a single row", function()
      eq(true, t1:remove { where = { a = 5 } }, "should remove")
      eq(true, db:eval "select * from T where a = 5", "should return boolean, if no resluts")
    end)

    it("removes a multiple rows", function()
      eq(true, t1:remove { where = { a = { 35, 4 } } }, "should remove")
      eq(true, db:eval "select * from T where a = 35 or a = 4", "should return boolean, if no resluts")
    end)
    it("removes a multiple rows with where key only", function()
      eq(true, t1:remove { a = { 35, 4 } }, "should remove")
      eq(true, db:eval "select * from T where a = 35 or a = 4", "should return boolean, if no resluts")
    end)
  end)

  clean()
  seed()

  describe(":update", function()
    it("update a single row", function()
      eq(true, t1:update { where = { a = 4 }, values = { c = "a", b = "a" } }, "should be updated")
      demo[6] = { a = 4, c = "a", b = "a" }
      eq({ demo[6] }, db:eval "select * from T where a = 4", "should return boolean, if no resluts")
    end)

    it("update a multiple rows", function()
      eq(
        true,
        t1:update {
          {
            where = { a = 35 },
            values = { c = "a", b = "a" },
          },
          {
            where = { a = 5 },
            values = { c = "a", b = "a" },
          },
        },
        "should be updated"
      )
      demo[7] = { a = 5, c = "a", b = "a" }
      demo[5] = { a = 35, c = "a", b = "a" }
      eq({ demo[7] }, db:eval "select * from T where a = 5", "should return boolean, if no resluts")
      eq({ demo[5] }, db:eval "select * from T where a = 35", "should return boolean, if no resluts")
    end)
  end)

  clean()
  seed()

  describe(":replace", function()
    it("replcaes table content with new content", function()
      local new_rows = {
        { a = 1, b = "lsf", c = "de" },
        { a = 2, b = "sdj", c = "in" },
        { a = 3, b = "sbs", c = "en" },
      }
      eq(true, t1:replace(new_rows), "it should return true")
      eq(new_rows, t1:get(), "it should have the new rows")
    end)
  end)

  clean()
  seed()

  describe(":insert", function()
    local ex_last_rowid = #demo
    it("inserts a row", function()
      local new_row = { a = 109, b = "0", c = "0" }
      ex_last_rowid = ex_last_rowid + 1
      local last_rowid = t1:insert(new_row)
      eq(ex_last_rowid, last_rowid, "it should return row_id " .. ex_last_rowid)
      eq({ new_row }, db:eval "select * from T where a = 109", "it should have the new rows")
    end)

    it("inserts a list of rows", function()
      local new_rows = {
        { a = 11, b = "lsf", c = "de" },
        { a = 22, b = "sdj", c = "in" },
        { a = 33, b = "sbs", c = "en" },
      }
      ex_last_rowid = ex_last_rowid + #new_rows
      local last_rowid = t1:insert(new_rows)
      eq(ex_last_rowid, last_rowid, "it should return row_id " .. ex_last_rowid)
      eq(new_rows, db:eval "select * from T where a = 11 or a = 22 or a = 33", "it should have the new rows")
    end)
  end)

  clean()
  seed()

  describe(":count", function()
    it("retunrs the current number of rows in a db", function()
      eq(7, t1:count(), "the number of rows")
    end)
  end)

  clean()
  describe("foreign key: ", function()
    local db = sql:open(nil)
    local artists, tracks
    it("create demo", function()
      artists = db:tbl("artists", {
        id = { type = "integer", pk = true },
        name = "text",
      })
      tracks = db:tbl("tracks", {
        id = "integer",
        name = "text",
        artist = {
          type = "integer",
          reference = "artists.id",
        },
      })
    end)

    -- it("should fail", function()
    --   eq({}, tracks:schema())
    -- end)

    it("seed", function()
      artists:insert {
        { id = 1, name = "Dean Martin" },
        { id = 2, name = "Frank Sinatra" },
      }

      tracks:insert {
        { id = 11, name = "That's Amore", artist = 1 },
        { id = 12, name = "Christmas Blues", artist = 1 },
        { id = 13, name = "My Way", artist = 2 },
      }
    end)

    local function try(self, action, args)
      return pcall(self[action], self, args)
    end

    tracks.try = try
    artists.try = try

    it("foreign_keys enabled", function()
      eq(1, db:eval("pragma foreign_keys")[1].foreign_keys)
    end)

    it("sqlite.org foreignkeys example no.1", function()
      eq(
        false,
        tracks:try("insert", { id = 4, name = "Mr. Bojangles", artist = 3 }),
        "fails when artist with id of 3 doesn't exists"
      )
      eq(
        true,
        tracks:try("insert", { id = 4, name = "Mr. Bojangles" }),
        "passes, since artist here in null and it is nullable in schema definition."
      )
      eq(
        false,
        tracks:try("update", { values = { artist = 3 }, where = { name = "Mr. Bojangles" } }),
        "fails on update as well."
      )
      eq(
        true,
        artists:try("insert", { id = 3, name = "Sammy Davis Jr." }),
        "pases as it normall would without foregin keys"
      )
      eq(
        true,
        tracks:try("update", { values = { artist = 3 }, where = { name = "Mr. Bojangles" } }),
        "passes, now that artist of id 3 is created"
      )
      eq(
        true,
        tracks:try("insert", { id = 15, name = "Boogie Woogie", artist = 3 }),
        "passes since artist of id 3 is created"
      )
      eq(
        false,
        artists:try("remove", { where = { name = "Frank Sinatra" } }),
        "fails due to existing rows refering to it."
      )
      eq(
        true,
        tracks:try("remove", { where = { name = "My Way" } }),
        "pases, so that the artist refered by this row can be deleted."
      )
      eq(
        true,
        artists:try("remove", { where = { name = "Frank Sinatra" } }),
        "passes since nothing referencing that artist is referencing it "
      )
      eq(
        false,
        artists:try("update", { values = { id = 4 }, where = { name = "Dean Martin" } }),
        "fails since there is a record referencing it "
      )
      eq(
        true,
        tracks:try("remove", { name = { "That's Amore", "Christmas Blues" } }),
        "passes, thus enabling the artist id above to be updated"
      )
      eq(
        true,
        artists:try("update", { values = { id = 4 }, where = { name = "Dean Martin" } }),
        "fails since there is a record referencing it "
      )
    end)

    it("on_update & on_delete actions", function()
      tracks:schema {
        id = "integer",
        name = "text",
        artist = {
          type = "integer",
          reference = "artists.id",
          on_update = "cascade",
          on_delete = "cascade",
        },
      }
      tracks:insert {
        { id = 11, name = "That's Amore", artist = 3 },
        { id = 12, name = "Christmas Blues", artist = 3 },
        { id = 13, name = "My Way", artist = 4 },
        { id = 14, name = "Return to Me", artist = 4 },
      }
      eq(
        true,
        artists:try("update", { where = { name = "Dean Martin" }, set = { id = 100 } }),
        "pases without issues since we have on_update cascade."
      )
      eq(
        true,
        next(tracks:get { where = { artist = 100 } }) ~= nil,
        "changes are reflect in tracks table. This means all row referencing Dean Martin get updated"
      )
      eq(
        true,
        artists:try("remove", { where = { name = "Dean Martin" } }),
        "pases without issues since we have on_delete cascade."
      )
      eq(true, next(tracks:get { where = { artist = 100 } }) == nil, "shouldn't be any rows referencing Dean Martin")
    end)
  end)

  describe(":extend", function()
    local t
    it("missing db object", function()
      t = tbl("tbl_name", { id = true, name = "text" })
      eq(false, pcall(t.insert, t, { name = "tami" }), "should fail early.")
      t:set_db(db)
      eq(true, pcall(t.insert, t, { name = "conni" }), "should work now we have a db object to operate against.")
      eq({ { id = 1, name = "conni" } }, t:get(), "only insert conni")
    end)

    it("with db object", function()
      t = tbl("tansactions", { id = true, amount = "real" }, db)
      eq(1, t:insert { amount = 20.2 })
      eq(
        "20.2",
        t:map(function(row)
          return tostring(row.amount)
        end)[1]
      )
    end)

    it("overwrite functions and fallback to t.db", function()
      t.get = function(_)
        return math.floor(t:__get({ where = { id = 1 } })[1].amount)
      end
      eq(20, t:get())
    end)

    local some

    it("create a new table", function()
      some = tbl.new("somename", {
        name = "text",
        id = true,
        count = {
          type = "integer",
          required = true,
          default = 0,
        },
      }, db)
    end)

    it("access function", function()
      eq("function", type(some.get), "should we still have access for")
      eq("function", type(some.__get), "should be accessible.")
      eq("cdata", type(some.db.conn))
    end)

    it("custom function", function()
      function some:insert_or_update(name)
        eq("string", type(name), "name should be a string")
        local entry = self:where { name = name }
        if not entry then
          self:insert { name = name }
        else
          eq("function", type(some.update))
          self:update {
            where = { id = entry.id },
            values = { count = entry.count + 2 },
          }
        end
      end

      eq("function", type(some.insert_or_update), "should be registered as function")
      some:insert_or_update "ff"
      eq("ff", some:where({ name = "ff" }).name)
      some:insert_or_update "ff"
      eq(2, some:where({ name = "ff" }).count)
    end)
  end)

  describe(":auto_alter", function()
    local fmt = string.format
    local alter = function(case)
      local schema, data = case.schema, case.data
      local tname = case.tname and case.tname
        or "A" .. string.char(math.random(97, 122)) .. string.char(math.random(97, 122))

      local new_table_cmd = P.table_alter_key_defs(tname, schema.after, schema.before, true)

      local tbefore = db:tbl(tname, schema.before)

      eq("number", type(tbefore:insert(data.before)), "should insert without issues.")

      local ok, tafter = pcall(db.tbl, db, tname, schema.after)

      eq(true, ok, fmt('\n\n\n%s:\n\n   "%s"\n\n', tafter, new_table_cmd))

      eq(
        data.after,
        tafter:get(),
        fmt(
          '\n\n\nnot matching expected data shape\n  "%s"\n\nTable Schema:%s',
          new_table_cmd,
          vim.inspect(tafter:schema())
        )
      )

      return tafter
    end
    it("case: simple rename with idetnical number of keys", function()
      local t = alter {
        schema = {
          before = {
            id = { type = "integer" },
            name = { type = "text" },
          },
          after = {
            id = { type = "integer", required = false },
            some_name = { type = "text" },
          },
        },
        ----------------
        data = {
          before = {
            { id = 1, name = "a" },
            { id = 2, name = "b" },
            { id = 3, name = "c" },
          },
          after = {
            { id = 1, some_name = "a" },
            { id = 2, some_name = "b" },
            { id = 3, some_name = "c" },
          },
        },
      }
      eq(true, t:drop())
    end)

    it("case: simple rename with idetnical number of keys with a key turned to be required", function()
      local t = alter {
        schema = {
          before = {
            id = { type = "integer" },
            name = { type = "text" },
            age = { "integer" },
          },
          after = {
            id = { type = "integer", required = true },
            some_name = { type = "text" },
            age = {
              type = "integer",
              default = 20,
              required = true,
            },
          },
        },
        ----------------
        data = {
          before = {
            { id = 1, name = "a", age = 5 },
            { id = 2, name = "b", age = 6 },
            { id = 3, name = "c", age = 7 },
            { id = 4, name = "e" },
          },
          after = {
            { id = 1, some_name = "a", age = 5 },
            { id = 2, some_name = "b", age = 6 },
            { id = 3, some_name = "c", age = 7 },
            { id = 4, some_name = "e", age = 20 },
          },
        },
      }

      eq(true, t:drop())
    end)

    it("case: more than one rename with idetnical number of keys", function()
      local t = alter {
        schema = {
          before = { id = { type = "integer" }, name = { type = "text" }, age = { "integer" } },
          after = {
            id = { type = "integer", required = true },
            some_name = { type = "text" },
            since = {
              type = "integer",
              default = 20,
              required = true,
            },
          },
        },
        ----------------
        data = {
          before = {
            { id = 1, name = "a", age = 5 },
            { id = 2, name = "b", age = 6 },
            { id = 3, name = "c", age = 7 },
            { id = 4, name = "e" },
          },
          after = {
            { id = 1, some_name = "a", since = 5 },
            { id = 2, some_name = "b", since = 6 },
            { id = 3, some_name = "c", since = 7 },
            { id = 4, some_name = "e", since = 20 },
          },
        },
      }

      eq(true, t:drop())
    end)

    it("case: more than one rename with idetnical number of keys + default without required = true", function()
      local t = alter {
        schema = {
          before = { id = { type = "integer" }, name = { type = "text" }, age = { "integer" } },
          after = {
            id = { type = "integer", required = true },
            some_name = { type = "text" },
            since = {
              type = "integer",
              default = 20,
            },
          },
        },
        ----------------
        data = {
          before = {
            { id = 1, name = "a", age = 5 },
            { id = 2, name = "b", age = 6 },
            { id = 3, name = "c", age = 7 },
            { id = 4, name = "e" },
          },
          after = {
            { id = 1, some_name = "a", since = 5 },
            { id = 2, some_name = "b", since = 6 },
            { id = 3, some_name = "c", since = 7 },
            { id = 4, some_name = "e", since = 20 },
          },
        },
      }

      eq(true, t:drop())
    end)

    clean()
    describe("case: foreign key:", function()
      local artists = db:tbl("artists", {
        id = true,
        name = "text",
      })

      artists:insert {
        { id = 1, name = "Dean Martin" },
        { id = 2, name = "Frank Sinatra" },
        { id = 3, name = "Sammy Davis Jr." },
      }

      local tracks
      it("transforms to foregin key", function()
        tracks = alter {
          tname = "tracks",
          schema = {
            before = {
              id = "integer",
              name = "text",
              artist = "integer",
            },
            after = {
              id = "integer",
              name = "text",
              artist = {
                type = "integer",
                reference = "artists.id",
                -- on_update = "cascade",
                -- on_delete = "cascade",
              },
            },
          },
          ----------------
          data = {
            before = {
              { id = 11, name = "That's Amore", artist = 1 },
              { id = 12, name = "Christmas Blues", artist = 1 },
              { id = 13, name = "My Way", artist = 2 },
            },
            after = {
              { id = 11, name = "That's Amore", artist = 1 },
              { id = 12, name = "Christmas Blues", artist = 1 },
              { id = 13, name = "My Way", artist = 2 },
            },
          },
        }
      end)

      it("pass sqlite.org tests", function()
        local function try(self, action, args)
          return pcall(self[action], self, args)
        end

        -- db:open()

        tracks.try = try
        artists.try = try

        eq(
          false,
          tracks:try("insert", { id = 4, name = "Mr. Bojangles", artist = 5 }),
          "fails when artist with id of 5 doesn't exists"
        )
        eq(
          true,
          tracks:try("insert", { id = 4, name = "Mr. Bojangles" }),
          "passes, since artist here in null and it is nullable in schema definition."
        )
        eq(
          false,
          tracks:try("update", { values = { artist = 5 }, where = { name = "Mr. Bojangles" } }),
          "fails on update as well."
        )
        eq(true, artists:try("insert", { id = 4, name = "Sammy" }), "pases as it normall would without foregin keys")
        eq(
          true,
          tracks:try("update", { values = { artist = 3 }, where = { name = "Mr. Bojangles" } }),
          "passes, now that artist of id 3 is created"
        )
        eq(
          true,
          tracks:try("insert", { id = 15, name = "Boogie Woogie", artist = 3 }),
          "passes since artist of id 3 is created"
        )
        eq(
          false,
          artists:try("remove", { where = { name = "Frank Sinatra" } }),
          "fails due to existing rows refering to it."
        )
        eq(
          true,
          tracks:try("remove", { where = { name = "My Way" } }),
          "pases, so that the artist refered by this row can be deleted."
        )
        eq(
          true,
          artists:try("remove", { where = { name = "Frank Sinatra" } }),
          "passes since nothing referencing that artist is referencing it "
        )
        eq(
          false,
          artists:try("update", { values = { id = 4 }, where = { name = "Dean Martin" } }),
          "fails since there is a record referencing it "
        )
        eq(
          true,
          tracks:try("remove", { name = { "That's Amore", "Christmas Blues" } }),
          "passes, thus enabling the artist id above to be updated"
        )

        tracks = db:tbl("tracks", {
          id = "integer",
          name = "text",
          artist = {
            type = "integer",
            reference = "artists.id",
            on_update = "cascade",
            on_delete = "cascade",
          },
        })

        tracks.try = try
        artists.try = try

        tracks:insert {
          { id = 11, name = "That's Amore", artist = 3 },
          { id = 12, name = "Christmas Blues", artist = 1 },
          { id = 13, name = "My Way", artist = 4 },
          { id = 14, name = "Return to Me", artist = 1 },
        }

        eq(
          true,
          artists:try("update", { where = { name = "Dean Martin" }, set = { id = 100 } }),
          "pases without issues since we have on_update cascade."
        )
        eq(
          true,
          next(tracks:get { where = { artist = 100 } }) ~= nil,
          "all row referencing Dean Martin get updated .. got: "
            .. vim.inspect(tracks:get {})
            .. vim.inspect(artists:get())
        )
        eq(
          true,
          artists:try("remove", { where = { name = "Dean Martin" } }),
          "pases without issues since we have on_delete cascade."
        )
        eq(true, next(tracks:get { where = { artist = 100 } }) == nil, "shouldn't be any rows referencing Dean Martin")
      end)
    end)
  end)

  describe(":index access", function()
    local db_path = ":memory:" or "/tmp/idx_db"
    -- vim.loop.fs_unlink(db_path)
    db = sql:open(db_path)

    describe("string_index:", function()
      local kv = tbl("kvpair", {
        key = { "text", primary = true, required = true, default = "none" },
        len = "integer",
      }, db)

      it("access/insert-to table using primary key", function()
        kv.a = { len = 1 }
        eq({ key = "a", len = 1 }, kv.a)
      end)

      it("access/update a row field len", function()
        -- eq({}, kv.a)
        kv.a = { len = 1 }
        kv.a.len = 2
        eq(2, kv:where({ len = 2 }).len, "should have been set")
        eq(2, kv.a.len, "should have been set")
        kv.a.len = 3
        eq({ key = "a", len = 3 }, kv.a, "should return values")
      end)

      it("remove a row using primary key", function()
        kv.a = nil
        eq(nil, kv:where { key = "a" }, "should be empty")
        eq({}, kv.a, "should be empty")
      end)

      it("sets a row field len without creating the row first", function()
        kv["some key with spaces :D"].len = 4
        eq(kv["some key with spaces :D"], { key = "some key with spaces :D", len = 4 })
        kv["some key with spaces :D"] = nil
      end)

      it("query using index", function()
        kv.a.len, kv.b.len, kv.c.len = 1, 2, 3
        eq(
          {
            { key = "a", len = 1 },
            { key = "b", len = 2 },
          },
          kv[{
            where = { len = { 1, 2, 3 } },
            order_by = { asc = { "key", "len" } },
            limit = 2,
          }]
        )
      end)
      it("bulk update", function()
        kv[{ len = { 1, 2, 3 } }] = { len = 10 }
        eq(
          {
            { key = "a", len = 10 },
            { key = "b", len = 10 },
          },
          kv[{
            order_by = { asc = { "key" } },
            limit = 2,
          }]
        )
      end)

      it("insert with 0 or true to skip the primary key value.", function()
        kv[true] = { len = 5 }
        eq(5, kv.none.len)
        kv[""] = { len = 6 }
        eq({ key = "none", len = 6 }, kv:where { len = 6 })
      end)
    end)

    describe("number_index", function()
      local t = tbl("number_idx", { id = true, name = "integer" }, db)

      it("passes string_index tests", function()
        t[1] = { name = "sam" }
        eq({ id = 1, name = "sam" }, t[1])
        eq("sam", t:where({ id = 1 }).name, "should have been set")

        t[2].name = "John"
        eq({ id = 2, name = "John" }, t[2])
        eq("John", t:where({ id = 2 }).name, "should have been set")
        eq("John", t[2].name, "should have been set")

        t[2] = nil
        eq(nil, t:where { id = 2 }, "should be empty")
        eq({}, t[2], "should be empty")

        t[1].name, t[2].name, t[2].name = "sam", "tami", "ram"
        eq(
          {
            { id = 1, name = "sam" },
            { id = 2, name = "tami" },
          },
          t[{
            where = { name = { "sam", "tami", "ram" } },
            order_by = { asc = { "id" } },
            limit = 2,
          }]
        )
        t[{ id = { 1, 2, 3 } }] = { name = "none" }
        eq(
          {
            { id = 1, name = "none" },
            { id = 2, name = "none" },
          },
          t[{
            order_by = { asc = { "id" } },
            limit = 2,
          }]
        )
      end)
    end)

    describe("Relationships", function()
      local todos = tbl("todos_indexer", {
        id = true,
        title = "text",
        project = {
          reference = "projects.title",
          required = true,
          on_delete = "cascade",
          on_update = "cascade",
        },
      }, db)

      local projects = tbl("projects", {
        title = { type = "text", primary = true, required = true, unique = true },
        deadline = { "date", default = db.lib.date "now" },
      }, db)

      it("create new table with default values", function()
        projects.neovim = {}
        eq(true, projects.neovim.deadline == os.date "!%Y-%m-%d")
        projects["sqlite"] = {}
        --- TODO: if you have sqilte.lua todos[2] return empty table
      end)

      it("fails if foregin key doesn't exists", function()
        eq(
          false,
          pcall(function()
            todos[2].project = "ram"
          end)
        )
      end)
    end)

    -- vim.loop.fs_unlink(db_path)
  end)

  clean()
end)
