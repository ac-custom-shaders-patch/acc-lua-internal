--[[
  A thing using SQLite (https://github.com/kkharji/sqlite.lua) for a couple of classes for storing data.
  One is a key-value storage (values can be anything that can be supported by `stringify.binary()`, including
  tables and vectors) with an optional age limit (for caching), another is a list with optional entries limit
  (if exceeded during initialization, old ones would be removed) and optional wrapper and unwrapper function.
  If `key` is set to `true`, it’s expected that `.encode` function will return a key as a second value. Older
  entry in the list with the same ID will be removed.

  To use, include with `local dbStorage = require('shared/utils/dbstorage'). Not available to scripts without
  I/O support. Make sure to call `dbStorage.configure(…)` before creating any collections. Use `:memory:` as
  a file name if you don’t want for it to create any files.

  Example:
  ```
  local dbStorage = require('shared/utils/dbstorage')
  dbStorage.configure(':memory:')

  ---@type DbDictionaryStorage<{a: integer, b: string}>
  local dbList = dbStorage.Dictionary('TABLE')
  dbList:set('TestEntry1', {a = 1, b = 'HELLO WORLD'})
  ac.log(dbList:get('TestEntry1'))
  ac.log(dbList:get('TestEntry2'))
  ```
]]

local sqlite, tbl = (function ()
  ffi.cdef [[
    typedef struct sqlite3 sqlite3;      
    typedef __int64 sqlite_int64;
    typedef unsigned __int64 sqlite_uint64;      
    typedef sqlite_int64 sqlite3_int64;
    typedef sqlite_uint64 sqlite3_uint64;      
    typedef struct sqlite3_stmt sqlite3_stmt;      
    int sqlite3_close(sqlite3*);
    int sqlite3_exec(sqlite3*, const char *sql, int (*callback)(void*,int,char**,char**), void *, char **errmsg);      
    sqlite3_int64 sqlite3_last_insert_rowid(sqlite3*);
    int sqlite3_open(const char *filename, sqlite3 **ppDb);
    int sqlite3_errcode(sqlite3 *db);
    const char *sqlite3_errmsg(sqlite3*);
    int sqlite3_prepare_v2(sqlite3 *db, const char *zSql, int nByte, sqlite3_stmt **ppStmt, const char **pzTail);
    char *sqlite3_expanded_sql(sqlite3_stmt *pStmt);
    int sqlite3_bind_blob64(sqlite3_stmt*, int, const void*, sqlite3_uint64, void(*)(void*));
    int sqlite3_bind_double(sqlite3_stmt*, int, double);
    int sqlite3_bind_null(sqlite3_stmt*, int);
    int sqlite3_bind_text(sqlite3_stmt*,int,const char*,int,void(*)(void*));
    int sqlite3_bind_zeroblob(sqlite3_stmt*, int, int n);
    int sqlite3_bind_zeroblob64(sqlite3_stmt*, int, sqlite3_uint64);      
    int sqlite3_bind_parameter_count(sqlite3_stmt*);
    const char *sqlite3_bind_parameter_name(sqlite3_stmt*, int);
    int sqlite3_clear_bindings(sqlite3_stmt*);
    int sqlite3_column_count(sqlite3_stmt *pStmt);
    const char *sqlite3_column_name(sqlite3_stmt*, int N);   
    int sqlite3_step(sqlite3_stmt*);
    const void *sqlite3_column_blob(sqlite3_stmt*, int iCol);
    double sqlite3_column_double(sqlite3_stmt*, int iCol);
    int sqlite3_column_int(sqlite3_stmt*, int iCol);
    const unsigned char *sqlite3_column_text(sqlite3_stmt*, int iCol);
    int sqlite3_column_bytes(sqlite3_stmt*, int iCol);
    int sqlite3_column_type(sqlite3_stmt*, int iCol);      
    int sqlite3_finalize(sqlite3_stmt *pStmt);
    int sqlite3_reset(sqlite3_stmt *pStmt);      
  ]]

  local clib = {
    flags = {ok = 0, error = 1, row = 100, done = 101},
    to_str = function(ptr, len) return ptr ~= nil and ffi.string(ptr, len) or nil end,
    get_new_db_ptr = function() return ffi.new 'sqlite3*[1]' end,
    get_new_stmt_ptr = function() return ffi.new 'sqlite3_stmt*[1]' end,
    last_errcode = function(conn) return ffi.C.sqlite3_errcode(conn) end,
  }

  do
    local curConn
    clib.wrapStmts = function(conn, fn)
      if not curConn then
        ffi.C.sqlite3_exec(conn, 'BEGIN', nil, nil, nil)
        curConn = conn
        setTimeout(function ()
          ffi.C.sqlite3_exec(curConn, 'COMMIT', nil, nil, nil)
          curConn = nil
        end)
      elseif curConn ~= conn then
        error('Two different connections are not supported')
      end
      return fn()
    end
    
    __util.pushEnsureToCall(function ()
      if curConn then
        ffi.C.sqlite3_exec(curConn, 'COMMIT', nil, nil, nil)
        curConn = nil
      end
    end)
    
    ac.onRelease(function ()
      if curConn then
        ffi.C.sqlite3_exec(curConn, 'COMMIT', nil, nil, nil)
        curConn = nil
      end
    end)
  end
  
  clib.last_errmsg = function(conn) return clib.to_str(ffi.C.sqlite3_errmsg(conn)) end
  
  clib.connect = function(uri, opts)
    opts = opts or {}
    local conn = clib.get_new_db_ptr()
    local code = ffi.C.sqlite3_open(uri, conn)      
    if code ~= clib.flags.ok then
      error('sqlite: couldn’t connect to sql database, error code: %s' % code)
    end      
    for k, v in pairs(opts) do
      if type(k) == 'boolean' then k = 'ON' end
      ffi.C.sqlite3_exec(conn[0], ('pragma %s = %s'):format(k, v), nil, nil, nil)
    end      
    return conn[0]
  end
  
  local sqlite = {db = {}}
  sqlite.db.__index = sqlite.db

  -- utils
  local u = {}
  u.if_nil = function(a, b) return a == nil and b or a end    
  u.is_nested = function(t) return t and type(t[1]) == 'table' or false end
  
  u.okeys = function(t)
    local r = {}
    for k in u.opairs(t) do r[#r + 1] = k end
    return r
  end
  
  u.opairs = (function()
    local __gen_order_index = function(t)
      local orderedIndex = {}
      for key in pairs(t) do
        table.insert(orderedIndex, key)
      end
      table.sort(orderedIndex)
      return orderedIndex
    end  
    local __nextpair = function(t, state)
      local key
      if state == nil then
        t.__orderedIndex = __gen_order_index(t)
        key = t.__orderedIndex[1]
      else
        for i = 1, #t.__orderedIndex do
          if t.__orderedIndex[i] == state then
            key = t.__orderedIndex[i + 1]
          end
        end
      end
      if key then
        return key, t[key]
      end
      t.__orderedIndex = nil
    end
    return function(t) return __nextpair, t, nil end
  end)()
  
  u.keys = function(t)
    local r = {}
    for k in pairs(t) do r[#r + 1] = k end
    return r
  end
  
  u.values = function(t)
    local r = {}
    for _, v in pairs(t) do r[#r + 1] = v end
    return r
  end
  
  u.map = function(t, f)
    local _t = {}
    for i, value in pairs(t) do
      local k, kv, v = i, f(value, i)
      _t[v and kv or k] = v or kv
    end
    return _t
  end
  
  u.join = function(l, s)
    return table.concat(u.map(l, tostring), s, 1)
  end
  
  u.flatten = function(tbl)
    local result = {}
    local function flatten(arr)
      local n = #arr
      for i = 1, n do
        local v = arr[i]
        if type(v) == 'table' then
          flatten(v)
        elseif v then
          table.insert(result, v)
        end
      end
    end
    flatten(tbl)
    return result
  end

  -- stmt
  local s = (function ()
    local sqlstmt = {}
    sqlstmt.__index = sqlstmt
    
    function sqlstmt:parse(conn, str)
      local o = setmetatable({str = str, conn = conn, finalized = false}, sqlstmt)    
      local pstmt = clib.get_new_stmt_ptr()
      if ffi.C.sqlite3_prepare_v2(o.conn, o.str, #o.str, pstmt, nil) ~= clib.flags.ok then
        error('sqlite: sql statement parse, stmt: “%s”, err: “%s”' % {o.str, clib.last_errmsg(o.conn)})
      end
      o.pstmt = pstmt[0]
      return o
    end
    
    function sqlstmt:reset()
      return ffi.C.sqlite3_reset(self.pstmt)
    end
    
    function sqlstmt:finalize()
      self.errcode = ffi.C.sqlite3_finalize(self.pstmt)
      self.finalized = self.errcode == clib.flags.ok
      return self.finalized
    end
    
    function sqlstmt:step()
      return ffi.C.sqlite3_step(self.pstmt)
    end
    
    function sqlstmt:nkeys()
      return ffi.C.sqlite3_column_count(self.pstmt)
    end

    function sqlstmt:nrows()
      local count = 0
      self:each(function()
        count = count + 1
      end)
      return count
    end
    
    function sqlstmt:key(idx)
      return clib.to_str(ffi.C.sqlite3_column_name(self.pstmt, idx))
    end
    
    function sqlstmt:keys()
      local keys = {}
      for i = 0, self:nkeys() - 1 do
        keys[i + 1] = self:key(i)
      end
      return keys
    end
    
    function sqlstmt:val(idx)
      local ktype = ffi.C.sqlite3_column_type(self.pstmt, idx)
      if ktype == 5 then
        return
      elseif ktype == 4 then
        local ptr = ffi.C.sqlite3_column_blob(self.pstmt, idx)
        if ptr == nil then return nil end
        return stringify.binary.parse(ptr)
      elseif ktype == 3 then
        local ptr = ffi.C.sqlite3_column_text(self.pstmt, idx)
        if ptr == nil then return nil end
        local size = ffi.C.sqlite3_column_bytes(self.pstmt, idx)
        return ffi.string(ptr, size)
      elseif ktype == 1 then
        return ffi.C.sqlite3_column_int(self.pstmt, idx)
      elseif ktype == 2 then
        return ffi.C.sqlite3_column_double(self.pstmt, idx)
      end
      return nil
    end
    
    function sqlstmt:vals()
      local vals = {}
      for i = 0, self:nkeys() - 1 do
        table.insert(vals, i + 1, self:val(i))
      end
      return vals
    end
    
    function sqlstmt:kv()
      local ret = {}
      for i = 0, self:nkeys() - 1 do
        ret[self:key(i)] = self:val(i)
      end
      return ret
    end
    
    function sqlstmt:next()
      local code = self:step()
      if code == clib.flags.row then
        return self
      elseif code == clib.flags.done then
        self:reset()
      else
        return nil, code
      end
    end
    
    function sqlstmt:iter()
      return self:next(), self.pstmt
    end
    
    function sqlstmt:each(callback)
      while self:step() == clib.flags.row do
        callback(self)
      end
    end
    
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
    
    function sqlstmt:bind(...)
      local args = { ... }
      if type(args[1]) == 'table' then
        local names = args[1]
        local parameter_index_cache = {}
        local anon_indices = {}
        for i = 1, self:nparam() do
          local name = self:param(i)
          if name == '?' then
            table.insert(anon_indices, i)
          else
            parameter_index_cache[name:sub(2, -1)] = i
          end
        end
        for k, v in pairs(names) do
          local index = parameter_index_cache[k] or table.remove(anon_indices, 1)
          if index and (((type(v) == 'string' and v:match '^[%S]+%(.*%)$') and clib.flags.ok or self:bind(index, v)) ~= clib.flags.ok) then
            error('sqlite error at sqlstmt:bind(), failed to bind a given value “%s”' % v)
          end
        end
        return clib.flags.ok
      end
    
      if type(args[1]) == 'number' and args[2] then
        local idx, value = args[1], args[2]
    
        if type(value) == 'table' then
          local i = stringify.binary(value)
          return ffi.C.sqlite3_bind_blob64(self.pstmt, idx, i, #i, nil)
        elseif type(value) == 'string' then
          return ffi.C.sqlite3_bind_text(self.pstmt, idx, value, #value, nil)
        elseif type(value) == 'number' then
          return ffi.C.sqlite3_bind_double(self.pstmt, idx, value)
        else
          if value ~= nil then error('Not supported: '..type(value)) end
          return ffi.C.sqlite3_bind_null(self.pstmt, idx, value)
        end
      end
    end
    
    function sqlstmt:bind_blob(idx, pointer, size)
      return ffi.C.sqlite3_bind_blob64(self.pstmt, idx, pointer, size, nil)
    end
    
    function sqlstmt:bind_zeroblob(idx, size)
      return ffi.C.sqlite3_bind_zeroblob64(self.pstmt, idx, size)
    end
    
    function sqlstmt:nparam()
      if not self.parm_count then
        self.parm_count = ffi.C.sqlite3_bind_parameter_count(self.pstmt)
      end
      return self.parm_count
    end
    
    function sqlstmt:param(idx)
      return clib.to_str(ffi.C.sqlite3_bind_parameter_name(self.pstmt, idx)) or '?'
    end
    
    function sqlstmt:params()
      local res = {}
      for i = 1, self:nparam() do
        table.insert(res, self:param(i))
      end
      return res
    end
    
    function sqlstmt:bind_clear()
      self.current_bind_index = nil
      return ffi.C.sqlite3_clear_bindings(self.pstmt)
    end
    
    function sqlstmt:bind_next(value)
      if not self.current_bind_index then
        self.current_bind_index = 1
      end    
      if self.current_bind_index <= self:nparam() then
        local ret = self:bind(self.current_bind_index, value)
        self.current_bind_index = self.current_bind_index + 1
        return ret
      end
      return clib.flags.error
    end
    
    function sqlstmt:expand()
      return clib.to_str(ffi.C.sqlite3_expanded_sql(self.pstmt))
    end
    
    return sqlstmt
  end)()

  local p = (function ()
    local tinsert = table.insert
    local tconcat = table.concat
    local M = {}
    
    local specifier = function(v, nonbind)
      local type = type(v)
      if type == 'number' then
        local _, b = math.modf(v)
        return b == 0 and '%d' or '%f'
      elseif type == 'string' and not nonbind then
        return v:find '\'' and '"%s"' or '\'%s\''
      elseif nonbind then
        return v
      else
        return ''
      end
    end
    
    local bind = function(o)
      o = o or {}
      o.s = o.s or ', '
      if not o.kv then
        o.v = o.v ~= nil and o.v or '?'
        return ('%s = '..specifier(o.v)):format(o.k, o.v)
      else
        local res = {}
        for k, v in u.opairs(o.kv) do
          k = o.k ~= nil and o.k or k
          v = o.nonbind and ':'..k or v
          tinsert(res, ('%s'..(o.nonbind and nil or ' = ')..specifier(v, o.nonbind)):format(k, v))
        end
        return tconcat(res, o.s)
      end
    end
    
    local pcontains = function(defs)
      if not defs then return {} end
      local items = {}
      for k, v in u.opairs(defs) do
        local head = '%s glob '..specifier(k)
        tinsert(items, type(v) == 'table' and tconcat(u.map(v, function(value) return head:format(k, value) end), ' or ') or head:format(k, v))
      end    
      return tconcat(items, ' ')
    end
    
    local pkeys = function(defs, kv)
      kv = kv == nil and true or kv    
      if not defs or not kv then return {} end
      local keys = {}
      for k, _ in u.opairs(u.is_nested(defs) and defs[1] or defs) do
        tinsert(keys, k)
      end
      return ('(%s)'):format(tconcat(keys, ', '))
    end
    
    local pvalues = function(defs, kv)
      kv = kv == nil and true or kv
      if not defs or not kv then return {} end
      local keys = {}
      for k, v in u.opairs(u.is_nested(defs) and defs[1] or defs) do
        tinsert(keys, type(v) == 'string' and v:match '^[%S]+%(.*%)$' and v or ':'..k)
      end
      return ('values(%s)'):format(tconcat(keys, ', '))
    end
    
    local pwhere = function(defs, name, join, contains)
      if not defs and not contains then return {} end    
      local where = {}
      if defs then
        for k, v in u.opairs(defs) do
          k = join and name..'.'..k or k    
          if type(v) ~= 'table' then
            if type(v) == 'string' and (v:sub(1, 1) == '<' or v:sub(1, 1) == '>') then
              tinsert(where, k..' '..v)
            else
              tinsert(where, bind { v = v, k = k, s = ' and ' })
            end
          else
            if type(k) == 'number' then
              tinsert(where, table.concat(v, ' '))
            else
              tinsert(where, '('..bind { kv = v, k = k, s = ' or ' }..')')
            end
          end
        end
      end    
      if contains then
        tinsert(where, pcontains(contains))
      end
      return ('where %s'):format(tconcat(where, ' and '))
    end
    
    local plimit = function(defs)
      if not defs then return {} end    
      local type = type(defs)
      local istbl = (type == 'table' and defs[2])
      local offset = 'limit %s offset %s'
      local limit = 'limit %s'    
      return istbl and offset:format(defs[1], defs[2]) or limit:format(type == 'number' and defs or defs[1])
    end
    
    local pset = function(defs)
      if not defs then return {} end    
      return 'set '..bind { kv = defs, nonbind = true }
    end
    
    local pjoin = function(defs, name)
      if not defs or not name then return {} end
      local target    
      local on = (function()
        for k, v in pairs(defs) do
          if k ~= name then
            target = k
            return ('%s.%s ='):format(k, v)
          end
        end
      end)()    
      local select = (function()
        for k, v in pairs(defs) do
          if k == name then
            return ('%s.%s'):format(k, v)
          end
        end
      end)()    
      return ('inner join %s on %s %s'):format(target, on, select)
    end
    
    local porder_by = function(defs)
      if not defs then return {} end    
      local fmt = '%s %s'
      local items = {}    
      for v, k in u.opairs(defs) do
        if type(k) == 'table' then
          for _, _k in u.opairs(k) do
            tinsert(items, fmt:format(_k, v))
          end
        else
          tinsert(items, fmt:format(k, v))
        end
      end    
      return ('order by %s'):format(tconcat(items, ', '))
    end
    
    local partial = function(method, tbl, opts, modifier)
      opts = opts or {}
      return tconcat(u.flatten {
        method,
        pkeys(opts.values),
        pvalues(opts.values, opts.named),
        pset(opts.set),
        pwhere(opts.where, tbl, opts.join, opts.contains),
        porder_by(opts.order_by),
        plimit(opts.limit),
        modifier,
      }, ' ')
    end
    
    local pselect = function(select)
      local t = type(select)    
      if t == 'table' and next(select) ~= nil then
        local items = {}
        for k, v in pairs(select) do
          tinsert(items, type(k) == 'number' and v or ('%s as %s'):format(v, k))
        end    
        return tconcat(items, ', ')
      end    
      return t == 'string' and select or '*'
    end
    
    M.select = function(tbl, opts)
      opts = opts or {}
      local cmd = opts.unique and 'select distinct %s' or 'select %s'
      local select = pselect(opts.select)
      local stmt = (cmd..' from %s'):format(select, tbl)
      local method = opts.join and stmt..' '..pjoin(opts.join, tbl) or stmt
      return partial(method, tbl, opts)
    end
    
    M.update = function(tbl, opts)
      local method = ('update %s'):format(tbl)
      return partial(method, tbl, opts)
    end
    
    M.insert = function(tbl, opts, modifier)
      local method = ('insert into %s'):format(tbl)
      return partial(method, tbl, opts, modifier)
    end
    
    M.delete = function(tbl, opts)
      opts = opts or {}
      local method = ('delete from %s'):format(tbl)
      local where = pwhere(opts.where)
      return type(where) == 'string' and method..' '..where or method
    end
    
    local format_action = function(value, update)
      local stmt = update and 'on update' or 'on delete'
      local preappend = (value:match 'default' or value:match 'null') and ' set ' or ' '    
      return stmt..preappend..value
    end
    
    local opts_to_str = function(tbl)
      local f = {
        pk = function() return 'primary key' end,
        type = function(v) return v end,
        unique = function() return 'unique' end,
        required = function(v)
          if v then return 'not null' end
        end,
        default = function(v)
          v = (type(v) == 'string' and v:match '^[%S]+%(.*%)$') and '('..tostring(v)..')' or v
          return tbl['required'] and 'on conflict replace default '..v or 'default '..v
        end,
        reference = function(v) return ('references %s'):format(v:gsub('%.', '(')..')') end,
        on_update = function(v) return format_action(v, true) end,
        on_delete = function(v) return format_action(v) end,
      }
    
      f.primary = f.pk
    
      local res = {}    
      if type(tbl[1]) == 'string' then
        res[1] = tbl[1]
      end
    
      local check = function(type)
        local v = tbl[type]
        if v then
          res[#res + 1] = f[type](v)
        end
      end
    
      check 'type'
      check 'unique'
      check 'required'
      check 'pk'
      check 'primary'
      check 'default'
      check 'reference'
      check 'on_update'
      check 'on_delete'
      return tconcat(res, ' ')
    end
    
    M.create = function(tbl, defs, ignore_ensure)
      if not defs then return end
      local items = {}
      tbl = (defs.ensure and not ignore_ensure) and 'if not exists '..tbl or tbl    
      for k, v in u.opairs(defs) do
        if k ~= 'ensure' then
          local t = type(v)
          tinsert(items, t == 'boolean' and k..' integer not null primary key'
            or t ~= 'table' and string.format('%s %s', k, v)
            or table.isArray(v) and ('%s %s'):format(k, tconcat(v, ' '))
            or ('%s %s'):format(k, opts_to_str(v)))
        end
      end
      return ('CREATE TABLE %s(%s)'):format(tbl, tconcat(items, ', '))
    end
    
    M.drop = function(tbl)
      return 'drop table '..tbl
    end
          
    M.table_alter_key_defs = function(tname, new, old, dry)
      local tmpname = tname..'_new'
      local create = M.create(tmpname, new, true)
      local drop = M.drop(tname)
      local move = 'INSERT INTO %s(%s) SELECT %s FROM %s'
      local rename = ('ALTER TABLE %s RENAME TO %s'):format(tmpname, tname)
      local with_foregin_key = false    
      for _, def in pairs(new) do
        if type(def) == 'table' and def.reference then
          with_foregin_key = true
        end
      end    
      local stmt = 'PRAGMA foreign_keys=off; BEGIN TRANSACTION; %s; COMMIT;'
      if not with_foregin_key then
        stmt = stmt..' PRAGMA foreign_keys=on'
      end    
      local keys = { new = u.okeys(new), old = u.okeys(old) }
      local idx = { new = {}, old = {} }    
      for _, varient in ipairs { 'new', 'old' } do
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
      local update_null_stmt = 'UPDATE %s SET %s=%s where %s IS NULL'
      for key, def in pairs(new) do
        if type(def) == 'table' and def.default and not def.required then
          tinsert(update_null_vals, update_null_stmt:format(tmpname, key, def.default, key))
        end
      end
      update_null_vals = #update_null_vals == 0 and '' or tconcat(update_null_vals, '; ')    
      local new_keys, old_keys = tconcat(keys.new, ', '), tconcat(keys.old, ', ')
      local insert = move:format(tmpname, new_keys, old_keys, tname)
      stmt = stmt:format(tconcat({create, insert, update_null_vals, drop, rename}, '; '))    
      return not dry and stmt or insert
    end
    
    M.pre_insert = function(rows, schema)
      rows = u.is_nested(rows) and rows or { rows }
      return rows
    end

    return M
  end)()

  -- helpers
  local h = {}
  function h.get_schema(tbl_name, db)
    local schema = db.tbl_schemas[tbl_name]
    if schema then return schema end
    db.tbl_schemas[tbl_name] = db:schema(tbl_name)
    return db.tbl_schemas[tbl_name]
  end  
  function h.check_for_auto_alter(o, valid_schema)
    if not valid_schema then return end

    local with_foregin_key = false
    for _, def in pairs(o.tbl_schema) do
      if type(def) == 'table' and def.reference then
        with_foregin_key = true
        break
      end
    end
  
    local get = string.format('select * from sqlite_master where name = \'%s\'', o.name)    
    local stmt = o.tbl_exists and o.db:eval(get) or nil
    if type(stmt) ~= 'table' then return end
  
    local origin, parsed = stmt[1].sql, p.create(o.name, o.tbl_schema, true)
    if origin == parsed then return end
  
    local ok, cmd = pcall(p.table_alter_key_defs, o.name, o.tbl_schema, o.db:schema(o.name))
    if not ok then return end
  
    o.db:execute(cmd)
    o.db_schema = o.db:schema(o.name)    
    if with_foregin_key then
      o.db:execute 'PRAGMA foreign_keys = ON;'
      o.db.opts.foreign_keys = true
    end
  end  
  function h.run(func, o)
    local exec = function()
      if not o.db_schema then
        local valid_schema = o.tbl_schema and next(o.tbl_schema) ~= nil
        if o.tbl_exists == nil then
          o.tbl_exists = o.db:exists(o.name)
          h.check_for_auto_alter(o, valid_schema)
        end
        if o.tbl_exists == false and valid_schema then
          o.tbl_schema.ensure = u.if_nil(o.tbl_schema.ensure, true)
          o.db:create(o.name, o.tbl_schema)
          o.db_schema = o.db:schema(o.name)
        end
        if not o.db_schema then
          o.db_schema = o.db:schema(o.name)
        end
      end
      return func()
    end    
    if o.db.closed then
      return o.db:with_open(exec)
    end
    return exec()
  end

  local tbl = (function ()
    local sqlite = {tbl = {}}
    sqlite.tbl.__index = sqlite.tbl
    
    function sqlite.tbl.new(name, schema, db)
      schema = schema or {}    
      local t = setmetatable({db = db, name = name, tbl_schema = u.if_nil(schema.schema, schema)}, sqlite.tbl)    
      if db then
        h.run(function() end, t)
      end    
      return setmetatable({}, {
        __index = function(_, key)
          if type(key) == 'string' then
            key = key:sub(1, 2) == '__' and key:sub(3, -1) or key
            if t[key] then
              return t[key]
            end
          end
        end,
      })
    end
    
    function sqlite.tbl:schema(schema)
      return h.run(function()
        local exists = self.db:exists(self.name)
        if not schema then
          return exists and self.db:schema(self.name) or {}
        end
        if not exists or schema.ensure then
          self.tbl_exists = self.db:create(self.name, schema)
          return self.tbl_exists
        end
        if not schema.ensure then
          local res = exists and self.db:drop(self.name) or true
          res = res and self.db:create(self.name, schema) or false
          self.tbl_schema = schema
          return res
        end
      end, self)
    end
    
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
    
    function sqlite.tbl:empty()
      return h.run(function()
        if self.db:exists(self.name) then
          return self.db:eval('select count(*) from '..self.name)[1]['count(*)'] == 0
        end
      end, self)
    end
    
    function sqlite.tbl:exists()
      return h.run(function()
        return self.db:exists(self.name)
      end, self)
    end

    function sqlite.tbl:count(filter)
      return h.run(function()
        if not self.db:exists(self.name) then
          return 0
        end
        local res = self.db:eval('select count(*) from '..self.name)
        return res[1]['count(*)']
      end, self)
    end
    
    function sqlite.tbl:get(query)
      return h.run(function() return self.db:select(self.name, query, self.db_schema) end, self)
    end
    
    function sqlite.tbl:insert(rows, modifier)
      return h.run(function()
        local succ, last_rowid = self.db:insert(self.name, rows, self.db_schema, modifier)
        return succ and last_rowid
      end, self)
    end
    
    function sqlite.tbl:remove(where)
      return h.run(function() return self.db:delete(self.name, where) end, self)
    end
    
    function sqlite.tbl:update(specs)
      return h.run(function() return self.db:update(self.name, specs, self.db_schema) end, self)
    end
    
    function sqlite.tbl:set_db(db)
      self.db = db
    end
    
    sqlite.tbl = setmetatable(sqlite.tbl, {__call = function(_, ...) return sqlite.tbl.new(...) end})    
    return sqlite.tbl      
  end)()

  function sqlite.db.new(uri, opts)
    opts = opts or {}
    local keep_open = opts.keep_open
    opts.keep_open = nil
    uri = uri or ':memory:'
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

  function sqlite.db:extend(conf)
    conf.opts = conf.opts or {}
    local lazy = conf.opts.lazy
    conf.opts.lazy = nil
    local db = self.new(conf.uri, conf.opts)
    local cls = setmetatable({ db = db }, {
      __index = function(_, key)
        if type(key) == 'string' then
          key = key:sub(1, 2) == '__' and key:sub(3, -1) or key
          if db[key] then
            return db[key]
          end
        end
      end,
    })
    for tbl_name, schema in pairs(conf) do
      if tbl_name ~= 'uri' and tbl_name ~= 'opts' and tbl_name ~= 'lazy' and type(schema) == 'table' then
        local name = schema._name and schema._name or tbl_name
        cls[tbl_name] = schema.set_db and schema or require('sqlite.tbl').new(name, schema, not lazy and db or nil)
        if not cls[tbl_name].db then (cls[tbl_name]):set_db(db) end
      end
    end
    return cls
  end

  function sqlite.db:open(uri, opts, noconn)
    local d = self
    if not d.uri then
      d = sqlite.db.new(uri, opts)
    end
    if d.closed or d.closed == nil then
      d.conn = clib.connect(d.uri, d.opts)
      d.created = os.date '%Y-%m-%d %H:%M:%S'
      d.closed = false
    end
    return d
  end

  function sqlite.db:close()
    self.closed = self.closed or ffi.C.sqlite3_close(self.conn) == 0
    return self.closed
  end

  function sqlite.db:with_open(...)
    local args = {...}
    if type(self) == 'string' or not self then self = sqlite.db:open(self) end
    local func = type(args[1]) == 'function' and args[1] or args[2]
    if self:isclose() then self:open() end
    local res = func(self)
    self:close()
    return res
  end

  function sqlite.db:isopen()
    return not self.closed
  end

  function sqlite.db:isclose()
    return self.closed
  end

  function sqlite.db:status()
    return {msg = clib.last_errmsg(self.conn), code = clib.last_errcode(self.conn)}
  end

  function sqlite.db:eval(statement, params)
    local res = {}
    local stmt = s:parse(self.conn, statement)
    if not params then
      stmt:each(function() table.insert(res, stmt:kv()) end)
      stmt:reset()
    elseif type(params) ~= 'table' and statement:match '%?' then
      local value = params
      stmt:bind { value }
      stmt:each(function(stm)
        table.insert(res, stm:kv())
      end)
      stmt:reset()
      stmt:bind_clear()
    elseif params and type(params) == 'table' then
      params = type(params[1]) == 'table' and params or { params }
      for _, v in ipairs(params) do
        stmt:bind(v)
        stmt:each(function(stm)
          table.insert(res, stm:kv())
        end)
        stmt:reset()
        stmt:bind_clear()
      end
    end
    stmt:finalize()
    res = rawequal(next(res), nil) and clib.last_errcode(self.conn) == clib.flags.ok or res
    if type(res) == 'table' and res[2] == nil and u.is_nested(res[1]) then res = res[1] end
    self.modified = true
    return res
  end

  function sqlite.db:execute(statement)
    return ffi.C.sqlite3_exec(self.conn, statement, nil, nil, nil) == 0 or error(clib.last_errmsg(self.conn))
  end

  function sqlite.db:exists(tbl_name)
    local q = self:eval('select name from sqlite_master where name= ?', tbl_name)
    return type(q) == 'table' and true or false
  end

  function sqlite.db:create(tbl_name, schema)
    local req = p.create(tbl_name, schema)
    if req:match 'reference' then
      self:execute 'pragma foreign_keys = ON'
      self.opts.foreign_keys = true
    end
    return self:eval(req)
  end

  function sqlite.db:drop(tbl_name)
    self.tbl_schemas[tbl_name] = nil
    return self:eval(p.drop(tbl_name))
  end

  function sqlite.db:schema(tbl_name)
    local sch = self:eval(('pragma table_info(%s)'):format(tbl_name))
    local schema = {}
    for _, v in ipairs(type(sch) == 'boolean' and {} or sch) do
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

  function sqlite.db:insert(tbl_name, rows, schema, modifier)
    local ret_vals = {}
    schema = schema and schema or h.get_schema(tbl_name, self)
    local items = p.pre_insert(rows, schema)
    local last_rowid
    clib.wrapStmts(self.conn, function()
      for _, v in ipairs(items) do
        local stmt = s:parse(self.conn, p.insert(tbl_name, { values = v }, modifier))
        stmt:bind(v)
        stmt:step()
        stmt:bind_clear()
        table.insert(ret_vals, stmt:finalize())
      end
      last_rowid = tonumber(ffi.C.sqlite3_last_insert_rowid(self.conn))
    end)
    local succ = table.every(ret_vals, function(v) return v end)
    if succ then
      self.modified = true
    end
    return succ, last_rowid
  end

  function sqlite.db:update(tbl_name, specs, schema)
    if not specs then return false end
    return clib.wrapStmts(self.conn, function()
      specs = u.is_nested(specs) and specs or { specs }
      schema = schema and schema or h.get_schema(tbl_name, self)
      local ret_val = nil
      for _, v in ipairs(specs) do
        v.set = v.set and v.set or v.values
        local stmt = s:parse(self.conn, p.update(tbl_name, { set = v.set, where = v.where }))
        stmt:bind(p.pre_insert(v.set, schema)[1])
        stmt:step()
        stmt:reset()
        stmt:bind_clear()
        stmt:finalize()
        ret_val = true
      end
      self.modified = true
      return ret_val
    end)
  end

  function sqlite.db:delete(tbl_name, where)
    if not where then return self:execute(p.delete(tbl_name)) end
    where = u.is_nested(where) and where or { where }
    clib.wrapStmts(self.conn, function()
      for _, spec in ipairs(where) do
        local _where = spec.where and spec.where or spec
        local stmt = s:parse(self.conn, p.delete(tbl_name, { where = _where }))
        stmt:step()
        stmt:reset()
        stmt:finalize()
      end
    end)
    self.modified = true
    return true
  end

  function sqlite.db:select(tbl_name, spec, schema)
    return clib.wrapStmts(self.conn, function()
      local ret = {}
      schema = schema and schema or h.get_schema(tbl_name, self)
      spec = spec or {}
      spec.select = spec.keys and spec.keys or spec.select
      local stmt = s:parse(self.conn, p.select(tbl_name, spec))
      s.each(stmt, function() table.insert(ret, s.kv(stmt)) end)
      s.reset(stmt)
      if s.finalize(stmt) then self.modified = false end
      return ret
    end)
  end

  function sqlite.db:transaction(fn)
    return clib.wrapStmts(self.conn, fn)
  end

  function sqlite.db:tbl(tbl_name, schema)
    if type(self) == 'string' then
      schema = tbl_name
      return tbl.new(self, schema)
    end
    return tbl.new(tbl_name, schema, self)
  end

  sqlite.db = setmetatable(sqlite.db, {
    __call = sqlite.db.extend,
  })

  return sqlite.db, tbl
end)()

local db

---@class DbDictionaryStorage<T>: {get: (fun(self: DbDictionaryStorage, key: string): T?), set: (fun(self: DbDictionaryStorage, key: string, value: T)), remove: (fun(self: DbDictionaryStorage, key: string)), clear: (fun(self: DbDictionaryStorage): self), removeAged: (fun(self: DbDictionaryStorage, time: integer, removeNewer: boolean?): self)}

local dictStorage = class('DbDictionaryStorage')

function dictStorage:initialize(tableKey, params)
  tableKey = 'dbstorage_list__%s' % ac.checksumSHA256(tostring(tableKey))
  params = type(params) == 'table' and params or {}
  if not db then
    error('Call DbBackedStorage.configure first')
  end
  self.entries = tbl(tableKey, {key = {'text', required = true, primary = true}, data = {'blob', required = true}, time = params.maxAge and {'integer', required = true}})
  self.entries:set_db(db)
  self.cache = setmetatable({}, {__mode = 'kv'})
  if params.maxAge then
    self.timeLimited = true
    self.entries:remove({ where = { time = '<%d' % (os.time() - params.maxAge) }})
  end
end

function dictStorage:removeAged(threshold, removeNewer)
  self.cache = setmetatable({}, {__mode = 'kv'})
  self.entries:remove({ where = { time = string.format(removeNewer and '>%d' or '<%d', threshold) }})
end

function dictStorage:get(key)
  local c = self.cache[key]
  if c then return c end
  local r = self.entries:get({where = {key = key}}, {'data'})
  c = r and r[1] and r[1].data
  self.cache[key] = c
  if self.timeLimited then
    self.entries:update({where = {key = key}, set = {time = os.time()}})
  end
  return c
end

function dictStorage:set(key, value)
  if type(value) ~= 'table' and self.cache[key] == value then
    return
  end
  if self.timeLimited then
    self.entries:insert({key = key, data = value, time = os.time()}, ' ON CONFLICT(key) DO UPDATE SET data=excluded.data, time=excluded.time')
  else
    self.entries:insert({key = key, data = value}, ' ON CONFLICT(key) DO UPDATE SET data=excluded.data')
  end
  self.cache[key] = value
end

function dictStorage:remove(key)
  self.entries:remove({key = key})
  self.cache[key] = nil
end

function dictStorage:clear()
  self.entries:remove()
  self.cache = setmetatable({}, {__mode = 'kv'})
end

---@class DbListStorage<T>: {at: (fun(self: DbListStorage, i: integer): T), loaded: (fun(self: DbListStorage): T[], integer), list: (fun(self: DbListStorage): T[], integer), alive: (fun(self: DbListStorage): integer), purge: (fun(self: DbListStorage): self), add: (fun(self: DbListStorage, item: T): self), update: (fun(self: DbListStorage, item: T): self), remove: (fun(self: DbListStorage, item: T): self), restore: (fun(self: DbListStorage, item: T): self), swap: (fun(self: DbListStorage, item1: T, item2: T): self), clear: (fun(self: DbListStorage): self)}

local listStorage = class('DbListStorage')

local function decode(item, _, self)
  if self.purged[item.id] then
    return self.purged[item.id]
  end
  if self.wrapper then
    item.data = self.wrapper.decode(item.data, item.key)
  end
  item.data['\1'] = item.id
  return item.data
end

function listStorage:initialize(tableKey, params)
  tableKey = 'dbstorage_list__%s' % ac.checksumSHA256(tostring(tableKey))
  params = type(params) == 'table' and params or {}
  if not db then
    error('Call DbBackedStorage.configure first')
  end
  self.entries = tbl(tableKey, {id = true, data = {'blob', required = true}, key = params.wrapper and params.wrapper.key and {'text', unique = true, required = true, primary = false} or nil})
  self.entries:set_db(db)
  self.wrapper = params.wrapper
  self.rows = params.wrapper and params.wrapper.key and {'id', 'data', 'key'} or {'id', 'data'}
  self.count = self.entries:count()
  if params.limit and self.count > params.limit then
    db:execute(string.format('delete from %s where id in (select id from %s order by id asc limit %d)', tableKey, tableKey, self.count - params.limit))
    self.count = params.limit
  end
  self.live = {}
  self.liveN = 0
  self.purged = {}
  if params.wrapper and params.wrapper.key then
    db:execute(string.format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%s ON %s (key)', tableKey, tableKey))
  end
end

function listStorage:at(i)
  if not i or i < 1 or i > self.count then return nil end 
  local missing = self.count - self.liveN
  if i > missing then return self.live[i - missing] end
  local itemsToGet = 1 + missing - i
  local got = self.entries:get({limit = {itemsToGet, self.count - self.liveN - itemsToGet}, order_by = {asc = 'id'}}, self.rows)
  if #got == 1 then
    table.insert(self.live, 1, decode(got[1], nil, self))
  else
    self.live = table.chain(table.map(got, decode, self), self.live)
  end
  self.liveN = self.liveN + #got
  return self.live[i - (self.count - self.liveN)]
end

local function listIterator(s, i)
  i = i + 1
  if i <= s.count then return i, s:at(i) end
end

function listStorage:__ipairs()
  return listIterator, self, 0
end

function listStorage:loaded()
  return self.live, self.liveN
end

function listStorage:list()
  self:at(1)
  return self.live, self.liveN
end

function listStorage:__len()
  return self.count
end

function listStorage:alive()
  return self.liveN
end

function listStorage:purge()
  if self.liveN > 0 then
    self.purged = {}
    for i = 1, self.liveN do
      self.purged[self.live[i]['\1']] = self.live[i]
    end
    table.clear(self.live)
    self.count, self.liveN = self.entries:count(), 0
  end
  return self
end

local function encode(value, wrapper, id)
  local key
  if wrapper then
    value, key = wrapper.encode(value)
  end
  return {data = value, id = id, key = key}
end

local function findRestorePosition(item, _, callbackData)
  return item['\1'] > callbackData
end

local function hasItemByID(self, id)
  return self.liveN == self.count or self.live[1] and self.live[1]['\1'] < id
end

function listStorage:add(value)
  local w
  if self.wrapper and self.wrapper.key then
    local v, k = self.wrapper.encode(value)
    local x = self.entries:get({where = {key = k}})
    if #x > 0 then
      self.entries:remove({where = {key = k}})
      if hasItemByID(self, x[1].id) then
        self:purge()
      else
        self.count = self.count - 1
      end
    end
    local s = self.entries:insert({data = v, key = k})
    self.live[self.liveN + 1], self.liveN = value, self.liveN + 1
    self.count = self.count + 1
    if s then value['\1'] = s end
  else
    local s = self.entries:insert(encode(value, self.wrapper))
    self.live[self.liveN + 1], self.liveN = value, self.liveN + 1
    self.count = self.count + 1
    if s then value['\1'] = s end
  end
  return self
end

function listStorage:update(value)
  if value and value['\1'] then 
    self.entries:update({where = {id = value['\1']}, set = encode(value, self.wrapper)})
  else
    self:add(value)
  end
  return self
end

function listStorage:remove(value)
  if not value or not value['\1'] then return end
  self.entries:remove({where = {id = value['\1']}})
  if table.removeItem(self.live, value) then
    self.liveN, self.count = self.liveN - 1, self.count - 1
  else
    ac.warn('Failed to change data inline')
    self:purge()
  end
  return self
end

function listStorage:restore(value)
  if not value or not value['\1'] then return end
  self.entries:insert(encode(value, self.wrapper, value['\1']))
  if hasItemByID(self, value['\1']) then
    local pos = table.findLeftOfIndex(self.live, findRestorePosition, value['\1'])
    table.insert(self.live, pos and pos + 1 or #self.live + 1, value)
    self.liveN, self.count = self.liveN + 1, self.count + 1
  else
    ac.warn('Failed to restore data inline')
  end
  return self
end

function listStorage:swap(value1, value2)
  if not value1 or not value1['\1'] or not value2 or not value2['\1'] then return end
  db:transaction(function ()
    value1['\1'], value2['\1'] = value2['\1'], value1['\1']
    self.entries:update({where = {id = value1['\1']}, set = encode(value1, self.wrapper)})
    self.entries:update({where = {id = value2['\1']}, set = encode(value2, self.wrapper)})
    local i1, i2 = table.indexOf(self.live, value1), table.indexOf(self.live, value2)
    if i1 and i2 then
      self.live[i1], self.live[i2] = self.live[i2], self.live[i1]
    else
      ac.warn('Failed to swap data inline')
      self:purge()
    end
  end)
  return self
end

function listStorage:clear()
  self.entries:remove()
  table.clear(self.live)
  self.count, self.liveN = 0, 0
  return self
end

---@type fun(tableKey: string, params: {maxAgeSeconds: integer?}?): DbDictionaryStorage
local dictConstructor = dictStorage.initialize

---@type fun(tableKey: string, params: {limit: integer?, wrapper: {encode: function, decode: function, key: boolean?}?}?): DbListStorage
local listConstructor = listStorage.initialize

return {
  Dictionary = class.emmy(dictStorage, dictConstructor),
  List = class.emmy(listStorage, listConstructor),

  ---@param filename string? @Database filename.
  ---@param params {useWAL: boolean?}? @Parameters. `useWAL` improves performance if you need a lot of frequent writes, enabled by default.
  configure = function(filename, params)
    params = type(params) == 'table' and params or {}
    db = sqlite{uri = filename, opts = {keep_open = true, journal_mode = params.useWAL ~= false and 'WAL' or nil}}
    ac.onRelease(function ()
      db:close()
    end)
  end,
}

-- todo: update time when reading cache
-- todo: option for filtering key for the list (so that old history entries could be removed)