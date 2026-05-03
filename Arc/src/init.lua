--[[
    Arc/src/init.lua
    Assembles the Arc module from all submodules and exposes a single
    unified Arc namespace at getgenv().Arc.

    Must be loaded AFTER: math, utils, cache, transforms, signals.
    Validates all submodules are present before finalising.
]]

local REQUIRED = { "math", "utils", "cache", "transforms", "signals" }

local env    = getgenv()
local arcSrc = env._Axium and env._Axium.Arc

-- Validate all submodules loaded
local missing = {}
for _, name in ipairs(REQUIRED) do
    if not (arcSrc and arcSrc[name]) then
        table.insert(missing, "Arc." .. name)
    end
end

if #missing > 0 then
    local msg = "Arc.init: missing submodules: " .. table.concat(missing, ", ")
    if env.AxiumLog then
        env.AxiumLog.critical("Arc", "init", "assemble", msg)
    end
    error(msg)
end

-- ── Build unified Arc namespace ───────────────────────────────────────────────

local Arc = {
    math       = arcSrc.math,
    utils      = arcSrc.utils,
    cache      = arcSrc.cache,
    transforms = arcSrc.transforms,
    signals    = arcSrc.signals,

    -- Version metadata
    _version   = "0.1.0",
    _modules   = REQUIRED,
}

-- Convenience aliases at the top level
Arc.lerp         = Arc.math.lerp
Arc.clamp        = Arc.math.clamp
Arc.round        = Arc.math.round
Arc.map          = Arc.math.map
Arc.ease         = Arc.math.ease
Arc.v2           = Arc.math.v2

Arc.deepCopy     = Arc.utils.deepCopy
Arc.shallowCopy  = Arc.utils.shallowCopy
Arc.uuid         = Arc.utils.uuid
Arc.stringify    = Arc.utils.stringify

Arc.rect         = Arc.transforms.rect
Arc.Anchor       = Arc.transforms.Anchor

Arc.newGroup     = Arc.signals.newGroup
Arc.once         = Arc.signals.once

-- Publish to global environment
env.Arc = Arc

if env.AxiumLog then
    env.AxiumLog.info("Arc", "init", "assemble", string.format(
        "Arc v%s assembled — modules: %s", Arc._version, table.concat(REQUIRED, ", ")
    ))
end

-- ── Dev tests ─────────────────────────────────────────────────────────────────

if env.AxiumDevMode then
    local AL = env.AxiumLog
    local passed, failed_count = 0, 0

    local function pass(label)
        passed = passed + 1
        AL.info("Arc", "init", "test", "PASS  " .. label)
    end

    local function fail(label, got, expected)
        failed_count = failed_count + 1
        AL.error("Arc", "init", "test",
            string.format("FAIL  %s  |  got=%s  expected=%s",
                label, tostring(got), tostring(expected))
        )
    end

    local function assertTrue(label, v)
        if v then pass(label) else fail(label, tostring(v), "true") end
    end

    -- Submodule presence
    for _, name in ipairs(REQUIRED) do
        assertTrue("Arc." .. name .. " present", Arc[name] ~= nil)
    end

    -- Aliases resolve correctly
    assertTrue("Arc.lerp alias",    Arc.lerp == Arc.math.lerp)
    assertTrue("Arc.clamp alias",   Arc.clamp == Arc.math.clamp)
    assertTrue("Arc.ease alias",    Arc.ease == Arc.math.ease)
    assertTrue("Arc.v2 alias",      Arc.v2 == Arc.math.v2)
    assertTrue("Arc.deepCopy alias",Arc.deepCopy == Arc.utils.deepCopy)
    assertTrue("Arc.uuid alias",    Arc.uuid == Arc.utils.uuid)
    assertTrue("Arc.rect alias",    Arc.rect == Arc.transforms.rect)
    assertTrue("Arc.Anchor alias",  Arc.Anchor == Arc.transforms.Anchor)
    assertTrue("Arc.once alias",    Arc.once == Arc.signals.once)

    -- Sanity: aliases actually work
    assertTrue("Arc.lerp works",   Arc.lerp(0, 10, 0.5) == 5)
    assertTrue("Arc.clamp works",  Arc.clamp(15, 0, 10) == 10)
    local r = Arc.rect(0, 0, 100, 50)
    assertTrue("Arc.rect works",   r.w == 100)
    assertTrue("Arc.uuid works",   #Arc.uuid() == 36)

    -- Global env.Arc published
    assertTrue("env.Arc published", env.Arc == Arc)
    assertTrue("env.Arc.math",      env.Arc.math ~= nil)

    AL.info("Arc", "init", "tests", string.format(
        "Suite complete — %d passed, %d failed", passed, failed_count
    ))
    if failed_count > 0 then
        AL.critical("Arc", "init", "tests",
            string.format("%d test(s) FAILED in Arc.init", failed_count))
    end
end

-- ── Registration ──────────────────────────────────────────────────────────────

env._Axium          = env._Axium or {}
env._Axium.Arc      = env._Axium.Arc or {}
env._Axium.Arc.init = Arc

if env.AxiumLoader then
    env.AxiumLoader.load("Arc.init", function() end)
end

return Arc
