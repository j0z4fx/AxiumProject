--[[
    Veil/src/signal_filter.lua
    VoltSignal payload validation, origin whitelisting, blocked-signal audit log.
    Depends on: Veil.Validator (getgenv()._Axium.Veil.Validator)
]]

local SignalFilter = {}

-- Registry: [signalName] = { schema, origins, hitCount } or false (explicit block)
local _registry = {}
local _auditLog = {}
local MAX_AUDIT = 500

local function now()
    if tick then return tick() end
    return os.clock()
end

local function _logBlocked(signal, origin, reason)
    local AL = getgenv().AxiumLog
    AL.warning("Veil", "signal_filter", "blocked",
        string.format("Signal '%s' blocked | origin='%s' | %s",
            signal, tostring(origin), reason))
    if #_auditLog < MAX_AUDIT then
        table.insert(_auditLog, {
            t      = now(),
            signal = signal,
            origin = tostring(origin),
            reason = reason,
        })
    end
end

-- Register allowed config for a signal.
-- opts.schema  : { fieldName = validatorSchema } for payload validation (optional)
-- opts.origins : array of Lua pattern strings; origin must match one (optional)
function SignalFilter.allow(signalName, opts)
    opts = opts or {}
    _registry[signalName] = {
        schema   = opts.schema,
        origins  = opts.origins,
        hitCount = 0,
    }
end

-- Explicitly block a signal name; all future checks return false.
function SignalFilter.block(signalName)
    _registry[signalName] = false
end

-- Check whether signalName may fire with the given payload from origin.
-- Returns true or false, errMsg.
function SignalFilter.check(signalName, payload, origin)
    local entry = _registry[signalName]

    if entry == false then
        _logBlocked(signalName, origin, "signal explicitly blocked")
        return false, "signal blocked"
    end

    if entry == nil then
        return true  -- unknown signals pass by default (open policy)
    end

    -- Origin whitelist
    if entry.origins and origin ~= nil then
        local allowed = false
        for _, pat in ipairs(entry.origins) do
            if tostring(origin):match(pat) then
                allowed = true
                break
            end
        end
        if not allowed then
            _logBlocked(signalName, origin, "origin not whitelisted")
            return false, "origin not whitelisted"
        end
    end

    -- Payload schema validation
    if entry.schema and payload ~= nil then
        local veil = getgenv()._Axium and getgenv()._Axium.Veil
        local V    = veil and veil.Validator
        if V then
            local p  = (type(payload) == "table") and payload or { value = payload }
            local ok, err = V.checkPayload(p, entry.schema)
            if not ok then
                local reason = "payload invalid: " .. (err or "unknown")
                _logBlocked(signalName, origin, reason)
                return false, reason
            end
        end
    end

    entry.hitCount = entry.hitCount + 1
    return true
end

-- Returns copy of the audit log.
function SignalFilter.getAuditLog()
    local out = {}
    for i, e in ipairs(_auditLog) do out[i] = e end
    return out
end

function SignalFilter.clearAuditLog()
    _auditLog = {}
end

function SignalFilter.getRegistry()
    return _registry
end

-- -- Dev tests -----------------------------------------------------------------

if getgenv().AxiumDevMode then
    local AL = getgenv().AxiumLog
    local passed, failed_count = 0, 0
    local function pass(lbl)
        passed = passed + 1
        AL.info("Veil", "signal_filter", "test", "PASS  " .. lbl)
    end
    local function fail(lbl, got, expected)
        failed_count = failed_count + 1
        AL.error("Veil", "signal_filter", "test",
            string.format("FAIL  %s  |  got=%s  expected=%s", lbl, tostring(got), tostring(expected)))
    end

    -- unknown signal passes (open policy)
    local ok = SignalFilter.check("Unknown", {}, "test")
    if ok then pass("unknown signal passes") else fail("unknown signal passes", ok, true) end

    -- allowed with no constraints
    SignalFilter.allow("TestOpen")
    ok = SignalFilter.check("TestOpen", {}, "anyone")
    if ok then pass("allowed no-constraint ok") else fail("allowed no-constraint ok", ok, true) end

    -- explicit block
    SignalFilter.block("BlockedSignal")
    ok = SignalFilter.check("BlockedSignal", {}, "anyone")
    if not ok then pass("blocked signal fails") else fail("blocked signal fails", ok, false) end

    -- origin whitelist pass
    SignalFilter.allow("OriginSig", { origins = { "Axium", "Veil" } })
    ok = SignalFilter.check("OriginSig", {}, "Axium::core")
    if ok then pass("whitelisted origin ok") else fail("whitelisted origin ok", ok, true) end

    -- origin whitelist fail
    ok = SignalFilter.check("OriginSig", {}, "External::plugin")
    if not ok then pass("non-whitelisted origin fails") else fail("non-whitelisted origin fails", ok, false) end

    -- audit log populated
    local log = SignalFilter.getAuditLog()
    if #log >= 2 then pass("audit log populated") else fail("audit log count", #log, ">=2") end

    -- hit count increments on success
    SignalFilter.allow("CountSig")
    SignalFilter.check("CountSig", nil, nil)
    SignalFilter.check("CountSig", nil, nil)
    local reg = SignalFilter.getRegistry()
    if reg["CountSig"] and reg["CountSig"].hitCount == 2 then
        pass("hitCount increments")
    else
        fail("hitCount increments", reg["CountSig"] and reg["CountSig"].hitCount, 2)
    end

    AL.info("Veil", "signal_filter", "tests",
        string.format("Suite complete -- %d passed, %d failed", passed, failed_count))
    if failed_count > 0 then
        AL.critical("Veil", "signal_filter", "tests",
            string.format("%d test(s) FAILED in Veil.SignalFilter", failed_count))
    end
end

-- -- Registration -------------------------------------------------------------

local env = getgenv()
env._Axium                   = env._Axium or {}
env._Axium.Veil              = env._Axium.Veil or {}
env._Axium.Veil.SignalFilter = SignalFilter

if env.AxiumLoader then
    env.AxiumLoader.load("Veil.signal_filter", function() end)
end

return SignalFilter