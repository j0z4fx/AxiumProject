--[[
    Veil/src/api_wrap.lua
    Wraps exposed APIs with Veil enforcement:
      - Gatekeeper permission check (tier baked in at wrap time)
      - Argument validation via Validator
      - Raw-render access blocking for EXTERNAL callers
      - Optional anti-tamper: original function reference stored and verified
    Depends on: Veil.Validator, Veil.Gatekeeper (via getgenv()._Axium.Veil)

    Wrap options:
      action        : string  -- gatekeeper action name to check (required)
      tier          : number  -- caller tier this wrapper operates at (default: EXTERNAL=3)
      argSchemas    : table   -- array of Validator schemas for positional args
      blockRawRender: bool    -- EXTERNAL callers rejected; requires DEV_TOOLS+ (tier <= 2)
      tamperCheck   : bool    -- verify original fn ref unchanged on every call
      label         : string  -- friendly name for log messages
]]

local ApiWrap = {}

local _registry = {}  -- { label, action, tier } for each wrapped function

local function _getValidator()
    local v = getgenv()._Axium
    return v and v.Veil and v.Veil.Validator
end

local function _getGatekeeper()
    local v = getgenv()._Axium
    return v and v.Veil and v.Veil.Gatekeeper
end

-- Wraps fn with Veil enforcement. Returns wrapped function or nil, errMsg.
function ApiWrap.wrap(fn, opts)
    if type(fn) ~= "function" then
        return nil, "Veil.ApiWrap: fn must be a function"
    end
    opts = opts or {}

    local action         = opts.action or "axium.unknown"
    local tier           = opts.tier or 3  -- default EXTERNAL; baked in at wrap time
    local argSchemas     = opts.argSchemas
    local blockRawRender = opts.blockRawRender
    local tamperCheck    = opts.tamperCheck
    local label          = opts.label or action
    local _origRef       = fn  -- stored for tamper detection

    local function wrapped(...)
        -- Anti-tamper: verify fn reference unchanged
        if tamperCheck and fn ~= _origRef then
            getgenv().AxiumLog.critical("Veil", "api_wrap", "tamper",
                "Tamper detected on '" .. label .. "': function reference changed")
            return nil, "tamper detected"
        end

        -- Raw-render restriction: EXTERNAL callers cannot invoke render-adjacent APIs
        if blockRawRender and tier > 2 then
            getgenv().AxiumLog.warning("Veil", "api_wrap", "blocked",
                string.format("Render-restricted API '%s' blocked for tier %d", label, tier))
            return nil, string.format("Veil.ApiWrap: '%s' is render-restricted", label)
        end

        -- Gatekeeper permission check
        local GK = _getGatekeeper()
        if GK then
            local ok, err = GK.check(action, tier)
            if not ok then return nil, err end
        end

        -- Argument validation
        if argSchemas then
            local V = _getValidator()
            if V then
                local args = { ... }
                local ok, err = V.checkArgs(args, argSchemas)
                if not ok then return nil, err end
            end
        end

        return fn(...)
    end

    -- newcclosure: prevents upvalue inspection via getupvalues
    local finalFn = wrapped
    if type(newcclosure) == "function" then
        local ok, cc = pcall(newcclosure, wrapped)
        if ok and cc then finalFn = cc end
    end

    table.insert(_registry, { label = label, action = action, tier = tier })
    return finalFn
end

-- Wraps all function values in table t in-place.
-- opts      : base options applied to all functions
-- fnOpts    : { [key] = opts overrides } for per-function customisation
-- opts.actionPrefix : prepended to key name to form action (e.g. "axium" -> "axium.get")
function ApiWrap.wrapTable(t, opts, fnOpts)
    opts    = opts    or {}
    fnOpts  = fnOpts  or {}
    for k, v in pairs(t) do
        if type(v) == "function" then
            local merged = {}
            for ok2, ov in pairs(opts)            do merged[ok2] = ov end
            for ok2, ov in pairs(fnOpts[k] or {}) do merged[ok2] = ov end
            if not merged.label then
                merged.label = tostring(k)
            end
            if not merged.action then
                local prefix = opts.actionPrefix
                merged.action = prefix and (prefix .. "." .. k) or tostring(k)
            end
            local wfn, _ = ApiWrap.wrap(v, merged)
            if wfn then t[k] = wfn end
        end
    end
    return t
end

-- Returns list of { label, action, tier } for all registered wrappers.
function ApiWrap.getRegistry()
    local out = {}
    for i, e in ipairs(_registry) do
        out[i] = { label = e.label, action = e.action, tier = e.tier }
    end
    return out
end

-- -- Dev tests -----------------------------------------------------------------

if getgenv().AxiumDevMode then
    local AL = getgenv().AxiumLog
    local passed, failed_count = 0, 0
    local function pass(lbl)
        passed = passed + 1
        AL.info("Veil", "api_wrap", "test", "PASS  " .. lbl)
    end
    local function fail(lbl, got, expected)
        failed_count = failed_count + 1
        AL.error("Veil", "api_wrap", "test",
            string.format("FAIL  %s  |  got=%s  expected=%s", lbl, tostring(got), tostring(expected)))
    end

    -- Basic wrap: INTERNAL tier on a registered action passes
    local hits = 0
    local wrapped = ApiWrap.wrap(function(x) hits = hits + 1; return x * 2 end, {
        action = "axium.listModules",  -- EXTERNAL-allowed action
        tier   = 3,
    })

    local result = wrapped(5)
    if hits == 1 and result == 10 then pass("wrap basic call ok") else fail("wrap basic call", hits, 1) end

    -- INTERNAL tier on INTERNAL-only action passes
    local wrappedInternal = ApiWrap.wrap(function() return "ok" end, {
        action = "axium.boot",
        tier   = 1,  -- INTERNAL
    })
    local r2 = wrappedInternal()
    if r2 == "ok" then pass("internal tier on internal action ok") else fail("internal tier ok", r2, "ok") end

    -- EXTERNAL tier on INTERNAL-only action blocked
    local wrappedBlocked = ApiWrap.wrap(function() return "ok" end, {
        action = "axium.boot",
        tier   = 3,  -- EXTERNAL
    })
    local r3, err3 = wrappedBlocked()
    if r3 == nil and err3 then pass("external blocked on internal action") else fail("external blocked", r3, nil) end

    -- blockRawRender: tier 3 (EXTERNAL) blocked
    local wrappedRender = ApiWrap.wrap(function() return "drawn" end, {
        action         = "axium.listModules",
        tier           = 3,
        blockRawRender = true,
    })
    local r4, err4 = wrappedRender()
    if r4 == nil and err4 then pass("raw render blocked for external") else fail("raw render blocked", r4, nil) end

    -- blockRawRender: tier 2 (DEV_TOOLS) allowed
    local wrappedRender2 = ApiWrap.wrap(function() return "drawn" end, {
        action         = "axium.createUI",
        tier           = 2,
        blockRawRender = true,
    })
    local r5 = wrappedRender2()
    if r5 == "drawn" then pass("raw render allowed for dev_tools") else fail("raw render dev ok", r5, "drawn") end

    -- arg schema validation
    local wrappedSchema = ApiWrap.wrap(function(x) return x end, {
        action     = "axium.listModules",
        tier       = 3,
        argSchemas = { { type = "number" } },
    })
    local r6 = wrappedSchema(42)
    if r6 == 42 then pass("argSchema pass") else fail("argSchema pass", r6, 42) end

    local r7, err7 = wrappedSchema("not_a_number")
    if r7 == nil and err7 then pass("argSchema fail") else fail("argSchema fail", r7, nil) end

    -- getRegistry has entries
    local reg = ApiWrap.getRegistry()
    if #reg >= 5 then pass("registry populated") else fail("registry populated", #reg, ">=5") end

    -- invalid fn rejected
    local nfn, nerr = ApiWrap.wrap("notafunc", {})
    if nfn == nil and nerr then pass("invalid fn rejected") else fail("invalid fn rejected", nfn, nil) end

    AL.info("Veil", "api_wrap", "tests",
        string.format("Suite complete -- %d passed, %d failed", passed, failed_count))
    if failed_count > 0 then
        AL.critical("Veil", "api_wrap", "tests",
            string.format("%d test(s) FAILED in Veil.ApiWrap", failed_count))
    end
end

-- -- Registration -------------------------------------------------------------

local env = getgenv()
env._Axium               = env._Axium or {}
env._Axium.Veil          = env._Axium.Veil or {}
env._Axium.Veil.ApiWrap  = ApiWrap

if env.AxiumLoader then
    env.AxiumLoader.load("Veil.api_wrap", function() end)
end

return ApiWrap