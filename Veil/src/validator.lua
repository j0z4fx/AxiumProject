--[[
    Veil/src/validator.lua
    Input/payload type validation, argument sanitization, origin checks,
    schema enforcement.
    No external Axium dependencies -- safe to load after Arc.

    Schema fields (all optional unless noted):
      type      : string  -- "string/number/boolean/table/function/any"
      required  : bool    -- nil/missing = error when true (default: true)
      nullable  : bool    -- nil accepted even when required (default: false)
      min       : number  -- numbers: min value; strings: min byte length
      max       : number  -- numbers: max value; strings: max byte length
      pattern   : string  -- Lua pattern applied to strings only
      elements  : schema  -- applied to every ipairs element of a table
      fields    : table   -- { key = schema } checked against table keys
      custom    : fn(v) -> bool, string?  -- returns true or false + errMsg
      label     : string  -- human-readable name used in error messages
]]

local Validator = {}

local PRIMITIVE_TYPES = {
    string   = true,
    number   = true,
    boolean  = true,
    table    = true,
    ["function"] = true,
    userdata = true,
    thread   = true,
    any      = true,
}

-- -- Internal ------------------------------------------------------------------

local function _fieldPath(label, key)
    if key then return (label or "value") .. "." .. tostring(key) end
    return label or "value"
end

local function _check(v, schema, label)
    label = label or schema.label or "value"

    if v == nil then
        local required = (schema.required ~= false)
        if not required or schema.nullable then return true end
        return false, string.format("Veil.Validator: '%s' is required", label)
    end

    if schema.type and schema.type ~= "any" then
        if not PRIMITIVE_TYPES[schema.type] then
            return false, string.format(
                "Veil.Validator: unknown schema type '%s' for '%s'",
                schema.type, label
            )
        end
        local got = type(v)
        if got ~= schema.type then
            return false, string.format(
                "Veil.Validator: '%s' expected %s, got %s",
                label, schema.type, got
            )
        end
    end

    if type(v) == "number" then
        if schema.min ~= nil and v < schema.min then
            return false, string.format(
                "Veil.Validator: '%s' value %g is below minimum %g",
                label, v, schema.min
            )
        end
        if schema.max ~= nil and v > schema.max then
            return false, string.format(
                "Veil.Validator: '%s' value %g exceeds maximum %g",
                label, v, schema.max
            )
        end
    end

    if type(v) == "string" then
        if schema.min ~= nil and #v < schema.min then
            return false, string.format(
                "Veil.Validator: '%s' length %d is below minimum %d",
                label, #v, schema.min
            )
        end
        if schema.max ~= nil and #v > schema.max then
            return false, string.format(
                "Veil.Validator: '%s' length %d exceeds maximum %d",
                label, #v, schema.max
            )
        end
        if schema.pattern and not v:match(schema.pattern) then
            return false, string.format(
                "Veil.Validator: '%s' does not match required pattern", label
            )
        end
    end

    if type(v) == "table" then
        if schema.elements then
            for i, elem in ipairs(v) do
                local ok, err = _check(elem, schema.elements, _fieldPath(label, i))
                if not ok then return false, err end
            end
        end
        if schema.fields then
            for k, fieldSchema in pairs(schema.fields) do
                local ok, err = _check(v[k], fieldSchema, _fieldPath(label, k))
                if not ok then return false, err end
            end
        end
    end

    if schema.custom then
        local ok2, result, detail = pcall(schema.custom, v)
        if not ok2 then
            return false, string.format(
                "Veil.Validator: '%s' custom validator threw: %s",
                label, tostring(result)
            )
        end
        if not result then
            return false, detail or string.format(
                "Veil.Validator: '%s' failed custom validation", label
            )
        end
    end

    return true
end

-- -- Public API ---------------------------------------------------------------

-- Validates v against schema. Returns true or false, errMsg.
function Validator.check(v, schema)
    if type(schema) ~= "table" then
        return false, "Veil.Validator: schema must be a table"
    end
    return _check(v, schema, schema.label)
end

-- Validates positional args table against array of schemas.
-- Stops at first failure. Returns true or false, errMsg.
function Validator.checkArgs(args, schemas)
    for i, schema in ipairs(schemas) do
        local ok, err = _check(args[i], schema, schema.label or ("arg[" .. i .. "]"))
        if not ok then return false, err end
    end
    return true
end

-- Validates a named-key payload table against a fields-schema table.
function Validator.checkPayload(payload, fields)
    if type(payload) ~= "table" then
        return false, "Veil.Validator: payload must be a table"
    end
    if type(fields) ~= "table" then
        return false, "Veil.Validator: fields schema must be a table"
    end
    return _check(payload, { type = "table", fields = fields }, "payload")
end

-- Sanitizes v per schema. Numbers clamped, strings trimmed + truncated.
function Validator.sanitize(v, schema)
    if type(schema) ~= "table" or v == nil then return v end
    if type(v) == "number" then
        if schema.min ~= nil and v < schema.min then v = schema.min end
        if schema.max ~= nil and v > schema.max then v = schema.max end
        return v
    end
    if type(v) == "string" then
        v = v:match("^%s*(.-)%s*$")
        if schema.max ~= nil and #v > schema.max then v = v:sub(1, schema.max) end
        return v
    end
    return v
end

-- Origin check: returns true if the call stack contains a frame whose source
-- matches any pattern in allowedPatterns. Fail-open when debug unavailable.
function Validator.checkOrigin(allowedPatterns, depth)
    if type(debug) ~= "table" then return true end
    local getinfo = debug.getinfo
    if type(getinfo) ~= "function" then return true end
    depth = depth or 8
    for level = 2, depth do
        local info = getinfo(level, "S")
        if not info then break end
        local src = info.source or info.short_src or ""
        for _, pat in ipairs(allowedPatterns) do
            if src:match(pat) then return true end
        end
    end
    return false
end

-- Returns "source:line" for the caller `level` levels up the stack.
function Validator.callerSource(level)
    if type(debug) ~= "table" then return "unknown" end
    local getinfo = debug.getinfo
    if type(getinfo) ~= "function" then return "unknown" end
    local info = getinfo((level or 1) + 2, "Sl")
    if not info then return "unknown" end
    return (info.source or info.short_src or "unknown") .. ":" .. (info.currentline or 0)
end

-- -- Dev tests -----------------------------------------------------------------

if getgenv().AxiumDevMode then
    local AL = getgenv().AxiumLog
    local passed, failed_count = 0, 0
    local function pass(lbl)
        passed = passed + 1
        AL.info("Veil", "validator", "test", "PASS  " .. lbl)
    end
    local function fail(lbl, got, expected)
        failed_count = failed_count + 1
        AL.error("Veil", "validator", "test",
            string.format("FAIL  %s  |  got=%s  expected=%s", lbl, tostring(got), tostring(expected)))
    end

    local ok
    ok = Validator.check("hello", { type = "string" })
    if ok then pass("string ok") else fail("string ok", ok, true) end

    ok = Validator.check(42, { type = "string" })
    if not ok then pass("number/string fail") else fail("number/string fail", ok, false) end

    ok = Validator.check(nil, { type = "string", required = false })
    if ok then pass("optional nil ok") else fail("optional nil ok", ok, true) end

    ok = Validator.check(nil, { type = "string" })
    if not ok then pass("required nil fail") else fail("required nil fail", ok, false) end

    ok = Validator.check(nil, { type = "string", nullable = true })
    if ok then pass("nullable nil ok") else fail("nullable nil ok", ok, true) end

    ok = Validator.check(5, { type = "number", min = 1, max = 10 })
    if ok then pass("number in range") else fail("number in range", ok, true) end

    ok = Validator.check(0, { type = "number", min = 1 })
    if not ok then pass("number below min") else fail("number below min", ok, false) end

    ok = Validator.check(11, { type = "number", max = 10 })
    if not ok then pass("number above max") else fail("number above max", ok, false) end

    ok = Validator.check("hi", { type = "string", min = 1, max = 5 })
    if ok then pass("string length ok") else fail("string length ok", ok, true) end

    ok = Validator.check("toolong", { type = "string", max = 4 })
    if not ok then pass("string too long") else fail("string too long", ok, false) end

    ok = Validator.check("abc123", { type = "string", pattern = "^%a+%d+$" })
    if ok then pass("pattern match ok") else fail("pattern match ok", ok, true) end

    ok = Validator.check("abc", { type = "string", pattern = "^%d+$" })
    if not ok then pass("pattern match fail") else fail("pattern match fail", ok, false) end

    ok = Validator.checkPayload(
        { name = "foo", count = 3 },
        { name = { type = "string" }, count = { type = "number", min = 0 } }
    )
    if ok then pass("payload ok") else fail("payload ok", ok, true) end

    ok = Validator.checkPayload({ name = 99 }, { name = { type = "string" } })
    if not ok then pass("payload type fail") else fail("payload type fail", ok, false) end

    ok = Validator.check(4, { type = "number",
        custom = function(v) return v % 2 == 0, "must be even" end })
    if ok then pass("custom ok even") else fail("custom ok even", ok, true) end

    ok = Validator.check(3, { type = "number",
        custom = function(v) return v % 2 == 0, "must be even" end })
    if not ok then pass("custom fail odd") else fail("custom fail odd", ok, false) end

    local s = Validator.sanitize("  hello  ", { type = "string" })
    if s == "hello" then pass("sanitize trim") else fail("sanitize trim", s, "hello") end

    local n = Validator.sanitize(200, { type = "number", max = 100 })
    if n == 100 then pass("sanitize clamp max") else fail("sanitize clamp max", n, 100) end

    local n2 = Validator.sanitize(-5, { type = "number", min = 0 })
    if n2 == 0 then pass("sanitize clamp min") else fail("sanitize clamp min", n2, 0) end

    ok = Validator.checkArgs({ "hi", 42 }, { { type = "string" }, { type = "number" } })
    if ok then pass("checkArgs ok") else fail("checkArgs ok", ok, true) end

    ok = Validator.checkArgs({ "hi", "bad" }, { { type = "string" }, { type = "number" } })
    if not ok then pass("checkArgs fail") else fail("checkArgs fail", ok, false) end

    ok = Validator.check({ 1, 2, 3 }, { type = "table", elements = { type = "number" } })
    if ok then pass("elements ok") else fail("elements ok", ok, true) end

    ok = Validator.check({ 1, "x" }, { type = "table", elements = { type = "number" } })
    if not ok then pass("elements fail") else fail("elements fail", ok, false) end

    AL.info("Veil", "validator", "tests",
        string.format("Suite complete -- %d passed, %d failed", passed, failed_count))
    if failed_count > 0 then
        AL.critical("Veil", "validator", "tests",
            string.format("%d test(s) FAILED in Veil.Validator", failed_count))
    end
end

-- -- Registration -------------------------------------------------------------

local env = getgenv()
env._Axium                = env._Axium or {}
env._Axium.Veil           = env._Axium.Veil or {}
env._Axium.Veil.Validator = Validator

if env.AxiumLoader then
    env.AxiumLoader.load("Veil.validator", function() end)
end

return Validator