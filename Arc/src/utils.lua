--[[
    Arc/src/utils.lua
    General-purpose utilities: type checking, table ops, string helpers,
    shallow/deep copy, UUID generation.
    No Axium dependencies — safe to load standalone.
]]

local ArcUtils = {}

-- ── Type checking ─────────────────────────────────────────────────────────────

function ArcUtils.isString(v)   return type(v) == "string"   end
function ArcUtils.isNumber(v)   return type(v) == "number"   end
function ArcUtils.isBoolean(v)  return type(v) == "boolean"  end
function ArcUtils.isTable(v)    return type(v) == "table"    end
function ArcUtils.isFunction(v) return type(v) == "function" end
function ArcUtils.isNil(v)      return v == nil               end

-- Returns true if v is a non-empty string
function ArcUtils.isNonEmptyString(v)
    return type(v) == "string" and #v > 0
end

-- Returns true if v is a finite real number (not NaN, not inf)
function ArcUtils.isFiniteNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Returns true if v is an integer value (no fractional part)
function ArcUtils.isInteger(v)
    return type(v) == "number" and math.floor(v) == v
end

-- Returns true if t is a table with only sequential integer keys starting at 1
function ArcUtils.isArray(t)
    if type(t) ~= "table" then return false end
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count == #t
end

-- Asserts v matches expected type string; throws formatted error on mismatch
function ArcUtils.assertType(v, expected, argName)
    local got = type(v)
    if got ~= expected then
        error(string.format(
            "Arc.utils.assertType: %s expected %s, got %s",
            argName or "arg", expected, got
        ), 2)
    end
end

-- ── Table ops ─────────────────────────────────────────────────────────────────

-- Shallow copy: copies top-level keys only
function ArcUtils.shallowCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

-- Deep copy: recursively copies all nested tables
function ArcUtils.deepCopy(t, _seen)
    if type(t) ~= "table" then return t end
    _seen = _seen or {}
    if _seen[t] then return _seen[t] end  -- handle circular refs
    local out = {}
    _seen[t] = out
    for k, v in pairs(t) do
        out[ArcUtils.deepCopy(k, _seen)] = ArcUtils.deepCopy(v, _seen)
    end
    return setmetatable(out, getmetatable(t))
end

-- Merge src into dst in-place; src keys overwrite dst keys (shallow)
function ArcUtils.merge(dst, src)
    for k, v in pairs(src) do dst[k] = v end
    return dst
end

-- Returns a new table with all keys from both a and b; b overwrites a on conflict
function ArcUtils.assign(a, b)
    local out = ArcUtils.shallowCopy(a)
    for k, v in pairs(b) do out[k] = v end
    return out
end

-- Returns array of all keys in t
function ArcUtils.keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    return out
end

-- Returns array of all values in t
function ArcUtils.values(t)
    local out = {}
    for _, v in pairs(t) do out[#out + 1] = v end
    return out
end

-- Returns true if t contains value v (shallow equality)
function ArcUtils.contains(t, v)
    for _, val in pairs(t) do
        if val == v then return true end
    end
    return false
end

-- Returns first index of v in array t, or nil
function ArcUtils.indexOf(t, v)
    for i, val in ipairs(t) do
        if val == v then return i end
    end
    return nil
end

-- Returns number of entries in t (works for non-sequential tables)
function ArcUtils.count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- Returns true if t has no entries
function ArcUtils.isEmpty(t)
    return next(t) == nil
end

-- Removes first occurrence of value v from array t in-place; returns removed index or nil
function ArcUtils.removeValue(t, v)
    for i, val in ipairs(t) do
        if val == v then
            table.remove(t, i)
            return i
        end
    end
    return nil
end

-- Returns new array containing only elements where predicate(v) is true
function ArcUtils.filter(t, predicate)
    local out = {}
    for _, v in ipairs(t) do
        if predicate(v) then out[#out + 1] = v end
    end
    return out
end

-- Returns new array with fn applied to each element
function ArcUtils.map(t, fn)
    local out = {}
    for i, v in ipairs(t) do out[i] = fn(v, i) end
    return out
end

-- Reduces array t to a single value; init is the starting accumulator
function ArcUtils.reduce(t, fn, init)
    local acc = init
    for _, v in ipairs(t) do acc = fn(acc, v) end
    return acc
end

-- Returns a flat array combining all provided arrays
function ArcUtils.concat(...)
    local out = {}
    for _, t in ipairs({...}) do
        for _, v in ipairs(t) do out[#out + 1] = v end
    end
    return out
end

-- ── String helpers ────────────────────────────────────────────────────────────

-- Trims leading and trailing whitespace
function ArcUtils.trim(s)
    return s:match("^%s*(.-)%s*$")
end

-- Splits s on separator sep; returns array of substrings
function ArcUtils.split(s, sep)
    sep = sep or "%s"
    local out = {}
    for part in s:gmatch("([^" .. sep .. "]+)") do
        out[#out + 1] = part
    end
    return out
end

-- Returns true if s starts with prefix
function ArcUtils.startsWith(s, prefix)
    return s:sub(1, #prefix) == prefix
end

-- Returns true if s ends with suffix
function ArcUtils.endsWith(s, suffix)
    return suffix == "" or s:sub(-#suffix) == suffix
end

-- Pads s on the left to at least length n using char (default " ")
function ArcUtils.padLeft(s, n, char)
    char = char or " "
    while #s < n do s = char .. s end
    return s
end

-- Pads s on the right to at least length n using char (default " ")
function ArcUtils.padRight(s, n, char)
    char = char or " "
    while #s < n do s = s .. char end
    return s
end

-- Repeats string s n times
function ArcUtils.rep(s, n)
    return string.rep(s, n)
end

-- Converts value to a compact string for logging/display
function ArcUtils.stringify(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "string"   then return string.format("%q", v) end
    if t ~= "table"    then return tostring(v) end
    if depth > 3       then return "{...}" end
    local parts = {}
    for k, val in pairs(v) do
        local key = type(k) == "string" and k or ("[" .. tostring(k) .. "]")
        parts[#parts + 1] = key .. "=" .. ArcUtils.stringify(val, depth + 1)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- ── UUID ──────────────────────────────────────────────────────────────────────

-- Generates a pseudo-random UUID v4 string (xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx)
-- Uses math.random; seed externally for better entropy if needed
function ArcUtils.uuid()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return template:gsub("[xy]", function(c)
        local v = c == "x" and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end)
end

-- ── Functional helpers ────────────────────────────────────────────────────────

-- Returns a function that calls fn at most once; subsequent calls return cached result
function ArcUtils.once(fn)
    local called, result = false, nil
    return function(...)
        if not called then
            called = true
            result = fn(...)
        end
        return result
    end
end

-- Returns a memoized version of fn keyed on the first argument (string/number)
function ArcUtils.memoize(fn)
    local cache = {}
    return function(key, ...)
        if cache[key] == nil then
            cache[key] = fn(key, ...)
        end
        return cache[key]
    end
end

-- Returns a debounced wrapper: fn fires only after delay seconds of no calls
-- Requires a scheduler callback (schedFn) that calls its argument after delay seconds
-- For executor use: pass a coroutine-based or tick-based scheduler
function ArcUtils.debounce(fn, delay, schedFn)
    local pending = false
    return function(...)
        local args = {...}
        if not pending then
            pending = true
            schedFn(delay, function()
                pending = false
                fn(table.unpack(args))
            end)
        end
    end
end

-- ── Dev tests ─────────────────────────────────────────────────────────────────

if getgenv().AxiumDevMode then
    local AL = getgenv().AxiumLog
    local passed, failed_count = 0, 0

    local function pass(label)
        passed = passed + 1
        AL.info("Arc", "utils", "test", "PASS  " .. label)
    end

    local function fail(label, got, expected)
        failed_count = failed_count + 1
        AL.error("Arc", "utils", "test",
            string.format("FAIL  %s  |  got=%s  expected=%s",
                label, tostring(got), tostring(expected))
        )
    end

    local function eq(label, got, expected)
        if got == expected then pass(label) else fail(label, got, expected) end
    end

    local function assertTrue(label, v)
        if v then pass(label) else fail(label, tostring(v), "true") end
    end

    local function assertFalse(label, v)
        if not v then pass(label) else fail(label, tostring(v), "false") end
    end

    -- Type checking
    assertTrue("isString('hi')",        ArcUtils.isString("hi"))
    assertFalse("isString(1)",           ArcUtils.isString(1))
    assertTrue("isNumber(3.14)",         ArcUtils.isNumber(3.14))
    assertTrue("isBoolean(false)",       ArcUtils.isBoolean(false))
    assertTrue("isTable({})",            ArcUtils.isTable({}))
    assertTrue("isFunction(print)",      ArcUtils.isFunction(print))
    assertTrue("isNil(nil)",             ArcUtils.isNil(nil))
    assertFalse("isNil(false)",          ArcUtils.isNil(false))
    assertTrue("isNonEmptyString('a')",  ArcUtils.isNonEmptyString("a"))
    assertFalse("isNonEmptyString('')",  ArcUtils.isNonEmptyString(""))
    assertTrue("isFiniteNumber(1)",      ArcUtils.isFiniteNumber(1))
    assertFalse("isFiniteNumber(1/0)",   ArcUtils.isFiniteNumber(1/0))
    assertFalse("isFiniteNumber(0/0)",   ArcUtils.isFiniteNumber(0/0))
    assertTrue("isInteger(4)",           ArcUtils.isInteger(4))
    assertFalse("isInteger(4.5)",        ArcUtils.isInteger(4.5))
    assertTrue("isArray({1,2,3})",       ArcUtils.isArray({1,2,3}))
    assertFalse("isArray({a=1})",        ArcUtils.isArray({a=1}))

    -- Table ops
    local orig = {a=1, b={c=2}}
    local sc = ArcUtils.shallowCopy(orig)
    assertTrue("shallowCopy top key",  sc.a == 1)
    assertTrue("shallowCopy same ref", sc.b == orig.b)  -- shallow: same inner table

    local dc = ArcUtils.deepCopy(orig)
    assertTrue("deepCopy top key",       dc.a == 1)
    assertTrue("deepCopy nested value",  dc.b.c == 2)
    assertFalse("deepCopy diff ref",     dc.b == orig.b)  -- deep: different table

    -- Circular ref deep copy
    local circ = {}; circ.self = circ
    local dc2 = ArcUtils.deepCopy(circ)
    assertTrue("deepCopy circular", dc2.self == dc2)

    local dst = {x=1}
    ArcUtils.merge(dst, {y=2, x=99})
    eq("merge overwrites", dst.x, 99)
    eq("merge adds",       dst.y, 2)

    local ab = ArcUtils.assign({a=1}, {b=2, a=9})
    eq("assign a overwritten", ab.a, 9)
    eq("assign b added",       ab.b, 2)

    local ks = ArcUtils.keys({a=1,b=2})
    eq("keys count", #ks, 2)

    local vs = ArcUtils.values({a=1,b=2})
    eq("values count", #vs, 2)

    assertTrue("contains found",    ArcUtils.contains({10,20,30}, 20))
    assertFalse("contains missing", ArcUtils.contains({10,20,30}, 99))

    eq("indexOf found",   ArcUtils.indexOf({5,6,7}, 6), 2)
    eq("indexOf missing", ArcUtils.indexOf({5,6,7}, 9), nil)

    eq("count",   ArcUtils.count({a=1,b=2,c=3}), 3)
    assertTrue("isEmpty {}",       ArcUtils.isEmpty({}))
    assertFalse("isEmpty {1}",     ArcUtils.isEmpty({1}))

    local arr = {1,2,3,2}
    ArcUtils.removeValue(arr, 2)
    eq("removeValue first", arr[2], 3)  -- first 2 removed, 3 shifts

    local filtered = ArcUtils.filter({1,2,3,4,5}, function(v) return v % 2 == 0 end)
    eq("filter count", #filtered, 2)
    eq("filter[1]",    filtered[1], 2)

    local mapped = ArcUtils.map({1,2,3}, function(v) return v * 10 end)
    eq("map[1]", mapped[1], 10)
    eq("map[3]", mapped[3], 30)

    local sum = ArcUtils.reduce({1,2,3,4}, function(acc,v) return acc+v end, 0)
    eq("reduce sum", sum, 10)

    local cat = ArcUtils.concat({1,2},{3,4},{5})
    eq("concat count", #cat, 5)
    eq("concat[3]",    cat[3], 3)

    -- String helpers
    eq("trim",            ArcUtils.trim("  hello  "), "hello")
    eq("trim no spaces",  ArcUtils.trim("hi"),         "hi")

    local parts = ArcUtils.split("a,b,c", ",")
    eq("split count", #parts, 3)
    eq("split[2]",    parts[2], "b")

    assertTrue("startsWith",          ArcUtils.startsWith("hello", "hel"))
    assertFalse("startsWith false",   ArcUtils.startsWith("hello", "llo"))
    assertTrue("endsWith",            ArcUtils.endsWith("hello", "llo"))
    assertFalse("endsWith false",     ArcUtils.endsWith("hello", "hel"))

    eq("padLeft",  ArcUtils.padLeft("5",  3, "0"), "005")
    eq("padRight", ArcUtils.padRight("5", 3, "0"), "500")
    eq("rep",      ArcUtils.rep("-", 3),            "---")

    local str = ArcUtils.stringify({x=1, y="hi"})
    assertTrue("stringify table", type(str) == "string" and #str > 0)
    eq("stringify string", ArcUtils.stringify("hello"), '"hello"')
    eq("stringify number", ArcUtils.stringify(42), "42")

    -- UUID
    local id1 = ArcUtils.uuid()
    local id2 = ArcUtils.uuid()
    eq("uuid length",    #id1, 36)
    assertTrue("uuid v4 marker",  id1:sub(15,15) == "4")
    assertFalse("uuid unique",    id1 == id2)

    -- Functional helpers
    local callCount = 0
    local onceFn = ArcUtils.once(function() callCount = callCount + 1; return 99 end)
    local r1 = onceFn()
    local r2 = onceFn()
    eq("once result",  r1, 99)
    eq("once cached",  r2, 99)
    eq("once calls",   callCount, 1)

    local memoHits = 0
    local memoFn = ArcUtils.memoize(function(k) memoHits = memoHits + 1; return k * 2 end)
    eq("memoize first",  memoFn(5), 10)
    eq("memoize cached", memoFn(5), 10)
    eq("memoize hits",   memoHits, 1)

    -- Summary
    AL.info("Arc", "utils", "tests", string.format(
        "Suite complete — %d passed, %d failed", passed, failed_count
    ))
    if failed_count > 0 then
        AL.critical("Arc", "utils", "tests", string.format(
            "%d test(s) FAILED in Arc.utils", failed_count
        ))
    end
end

-- ── Registration ──────────────────────────────────────────────────────────────

local env = getgenv()
env._Axium           = env._Axium or {}
env._Axium.Arc       = env._Axium.Arc or {}
env._Axium.Arc.utils = ArcUtils

if env.AxiumLoader then
    env.AxiumLoader.load("Arc.utils", function() end)
end

return ArcUtils
