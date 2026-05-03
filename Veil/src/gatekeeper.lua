--[[
    Veil/src/gatekeeper.lua
    Permission tier enforcement. Three tiers:
      INTERNAL  (1) -- Axium core; full access
      DEV_TOOLS (2) -- dev harness / inspector; restricted write access
      EXTERNAL  (3) -- plugins / third-party; read-only + gated APIs
    An action's requiredTier is the MAXIMUM caller tier allowed.
    Caller tier must be <= requiredTier to be permitted.
    Denied-action audit log.
]]

local Gatekeeper = {}

Gatekeeper.TIER = {
    INTERNAL  = 1,
    DEV_TOOLS = 2,
    EXTERNAL  = 3,
}

-- [actionName] = { requiredTier, description }
local _actions = {}
local _denied  = {}
local MAX_DENIED = 500

local function now()
    if tick then return tick() end
    return os.clock()
end

local function _logDenied(action, callerTier, requiredTier)
    local AL = getgenv().AxiumLog
    AL.warning("Veil", "gatekeeper", "denied",
        string.format(
            "Action '%s' denied: caller tier %d > required tier %d",
            action, callerTier, requiredTier
        ))
    if #_denied < MAX_DENIED then
        table.insert(_denied, {
            t            = now(),
            action       = action,
            callerTier   = callerTier,
            requiredTier = requiredTier,
        })
    end
end

-- Register an action.
-- requiredTier: max caller tier allowed (INTERNAL=1 = core only; EXTERNAL=3 = anyone).
function Gatekeeper.register(action, requiredTier, description)
    if type(action) ~= "string" then return end
    _actions[action] = {
        requiredTier = requiredTier or Gatekeeper.TIER.INTERNAL,
        description  = description or "",
    }
end

function Gatekeeper.unregister(action)
    _actions[action] = nil
end

-- Check permission. Returns true or false, errMsg.
function Gatekeeper.check(action, callerTier)
    callerTier = callerTier or Gatekeeper.TIER.EXTERNAL

    local entry = _actions[action]
    if not entry then
        _logDenied(action, callerTier, 0)
        return false, string.format(
            "Veil.Gatekeeper: action '%s' is not registered", action)
    end

    if callerTier <= entry.requiredTier then
        return true
    end

    _logDenied(action, callerTier, entry.requiredTier)
    return false, string.format(
        "Veil.Gatekeeper: action '%s' requires tier <= %d, caller is tier %d",
        action, entry.requiredTier, callerTier
    )
end

-- Resolve tier name string to constant. Unknown names map to EXTERNAL.
function Gatekeeper.resolveTier(name)
    return Gatekeeper.TIER[name] or Gatekeeper.TIER.EXTERNAL
end

function Gatekeeper.getDeniedLog()
    local out = {}
    for i, e in ipairs(_denied) do out[i] = e end
    return out
end

function Gatekeeper.clearDeniedLog()
    _denied = {}
end

function Gatekeeper.getRegistry()
    local out = {}
    for k, v in pairs(_actions) do
        out[k] = { requiredTier = v.requiredTier, description = v.description }
    end
    return out
end

-- -- Built-in action registrations --------------------------------------------

local T = Gatekeeper.TIER

Gatekeeper.register("axium.boot",           T.INTERNAL,  "Bootstrap sequence")
Gatekeeper.register("axium.shutdown",       T.INTERNAL,  "Full shutdown")
Gatekeeper.register("axium.registerModule", T.INTERNAL,  "Register module in registry")
Gatekeeper.register("axium.reloadModule",   T.DEV_TOOLS, "Hot-reload a module")
Gatekeeper.register("axium.inspect",        T.DEV_TOOLS, "Inspect module state")
Gatekeeper.register("axium.getState",       T.DEV_TOOLS, "Read runtime state")
Gatekeeper.register("axium.setState",       T.INTERNAL,  "Write runtime state")
Gatekeeper.register("axium.emitSignal",     T.DEV_TOOLS, "Emit arbitrary signal")
Gatekeeper.register("axium.listModules",    T.EXTERNAL,  "List module names (read-only)")
Gatekeeper.register("axium.createUI",       T.DEV_TOOLS, "Create UI elements")
Gatekeeper.register("axium.destroyUI",      T.DEV_TOOLS, "Destroy UI elements")
Gatekeeper.register("veil.bypass",          T.INTERNAL,  "Bypass Veil checks (never external)")
Gatekeeper.register("veil.scanResult",      T.DEV_TOOLS, "Read scanner results")
Gatekeeper.register("veil.wrapApi",         T.INTERNAL,  "Wrap API through Veil")

-- -- Dev tests -----------------------------------------------------------------

if getgenv().AxiumDevMode then
    local AL = getgenv().AxiumLog
    local passed, failed_count = 0, 0
    local TIER = Gatekeeper.TIER
    local function pass(lbl)
        passed = passed + 1
        AL.info("Veil", "gatekeeper", "test", "PASS  " .. lbl)
    end
    local function fail(lbl, got, expected)
        failed_count = failed_count + 1
        AL.error("Veil", "gatekeeper", "test",
            string.format("FAIL  %s  |  got=%s  expected=%s", lbl, tostring(got), tostring(expected)))
    end

    Gatekeeper.register("test.internal",  TIER.INTERNAL,  "test")
    Gatekeeper.register("test.dev",       TIER.DEV_TOOLS, "test")
    Gatekeeper.register("test.all",       TIER.EXTERNAL,  "test")

    local ok

    -- INTERNAL action: only tier 1 passes
    ok = Gatekeeper.check("test.internal", TIER.INTERNAL)
    if ok then pass("internal ok for internal") else fail("internal ok", ok, true) end

    ok = Gatekeeper.check("test.internal", TIER.DEV_TOOLS)
    if not ok then pass("dev blocked on internal") else fail("dev blocked", ok, false) end

    ok = Gatekeeper.check("test.internal", TIER.EXTERNAL)
    if not ok then pass("external blocked on internal") else fail("external blocked", ok, false) end

    -- DEV_TOOLS action: tiers 1 and 2 pass
    ok = Gatekeeper.check("test.dev", TIER.INTERNAL)
    if ok then pass("internal ok for dev") else fail("internal ok dev", ok, true) end

    ok = Gatekeeper.check("test.dev", TIER.DEV_TOOLS)
    if ok then pass("dev ok for dev") else fail("dev ok", ok, true) end

    ok = Gatekeeper.check("test.dev", TIER.EXTERNAL)
    if not ok then pass("external blocked on dev") else fail("external on dev", ok, false) end

    -- EXTERNAL action: all tiers pass
    ok = Gatekeeper.check("test.all", TIER.EXTERNAL)
    if ok then pass("external ok for external") else fail("external ok", ok, true) end

    -- Unregistered action: denied
    ok = Gatekeeper.check("nonexistent.xyz", TIER.INTERNAL)
    if not ok then pass("unregistered denied") else fail("unregistered denied", ok, false) end

    -- Denied log populated
    local log = Gatekeeper.getDeniedLog()
    if #log > 0 then pass("denied log has entries") else fail("denied log empty", #log, ">0") end

    -- resolveTier
    local t = Gatekeeper.resolveTier("INTERNAL")
    if t == TIER.INTERNAL then pass("resolveTier INTERNAL") else fail("resolveTier INTERNAL", t, 1) end

    t = Gatekeeper.resolveTier("BOGUS")
    if t == TIER.EXTERNAL then pass("resolveTier unknown=EXTERNAL") else fail("resolveTier bogus", t, 3) end

    AL.info("Veil", "gatekeeper", "tests",
        string.format("Suite complete -- %d passed, %d failed", passed, failed_count))
    if failed_count > 0 then
        AL.critical("Veil", "gatekeeper", "tests",
            string.format("%d test(s) FAILED in Veil.Gatekeeper", failed_count))
    end
end

-- -- Registration -------------------------------------------------------------

local env = getgenv()
env._Axium                  = env._Axium or {}
env._Axium.Veil             = env._Axium.Veil or {}
env._Axium.Veil.Gatekeeper  = Gatekeeper

if env.AxiumLoader then
    env.AxiumLoader.load("Veil.gatekeeper", function() end)
end

return Gatekeeper