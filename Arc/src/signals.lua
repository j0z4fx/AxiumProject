--[[
    Arc/src/signals.lua
    VoltSignal convenience layer: connection groups, one-shot connections,
    filtered connections, and safe signal factories.
    Wraps the VoltSignal executor built-in — does NOT reimplement it.
    No Axium dependencies beyond VoltSignal being present in the environment.
]]

local ArcSignals = {}

-- ── Safe signal factory ───────────────────────────────────────────────────────

--[[
    Creates a new VoltSignal with a protected wrapper.
    Returns the signal, or throws with a clear message if VoltSignal unavailable.
]]
function ArcSignals.new()
    assert(VoltSignal, "Arc.signals: VoltSignal is not available in this environment")
    return VoltSignal.new()
end

-- ── ConnectionGroup ───────────────────────────────────────────────────────────
--[[
    Tracks a set of VoltConnections and disconnects all at once.
    Use for UI nodes, controls, or any scope that has a defined lifetime.
]]

local ConnectionGroup = {}
ConnectionGroup.__index = ConnectionGroup

function ArcSignals.newGroup()
    return setmetatable({ _connections = {}, _disconnected = false }, ConnectionGroup)
end

--[[
    Connects handler to signal and tracks the connection.
    Returns the VoltConnection.
]]
function ConnectionGroup:connect(signal, handler)
    assert(not self._disconnected, "Arc.signals: ConnectionGroup already disconnected")
    assert(signal and signal.Connect, "Arc.signals: invalid signal passed to ConnectionGroup:connect")
    local conn = signal:Connect(handler)
    table.insert(self._connections, conn)
    return conn
end

-- Disconnects all tracked connections. Safe to call multiple times.
function ConnectionGroup:disconnectAll()
    for _, conn in ipairs(self._connections) do
        pcall(function() conn:Disconnect() end)
    end
    self._connections = {}
    self._disconnected = true
end

-- Returns the number of active connections in this group
function ConnectionGroup:count()
    return #self._connections
end

-- ── One-shot connection ───────────────────────────────────────────────────────

--[[
    Connects handler to signal; automatically disconnects after the first fire.
    Returns the VoltConnection.
]]
function ArcSignals.once(signal, handler)
    assert(signal and signal.Connect, "Arc.signals.once: invalid signal")
    local conn
    conn = signal:Connect(function(...)
        pcall(function() conn:Disconnect() end)
        handler(...)
    end)
    return conn
end

-- ── Filtered connection ───────────────────────────────────────────────────────

--[[
    Connects handler to signal; handler only fires when predicate(...) returns true.
    Returns the VoltConnection.
]]
function ArcSignals.filtered(signal, predicate, handler)
    assert(signal and signal.Connect, "Arc.signals.filtered: invalid signal")
    assert(type(predicate) == "function", "Arc.signals.filtered: predicate must be function")
    return signal:Connect(function(...)
        if predicate(...) then
            handler(...)
        end
    end)
end

-- ── Mapped connection ─────────────────────────────────────────────────────────

--[[
    Connects to signal; fires handler with mapFn(...) applied to the arguments.
    Useful for projecting signal payloads before handling.
]]
function ArcSignals.mapped(signal, mapFn, handler)
    assert(signal and signal.Connect, "Arc.signals.mapped: invalid signal")
    assert(type(mapFn) == "function", "Arc.signals.mapped: mapFn must be function")
    return signal:Connect(function(...)
        handler(mapFn(...))
    end)
end

-- ── Debounced connection ──────────────────────────────────────────────────────

--[[
    Connects to signal; handler fires only after the signal has been quiet for
    `delay` seconds. Requires a scheduler (schedFn(delay, callback)).
    Returns the VoltConnection.
]]
function ArcSignals.debounced(signal, delay, schedFn, handler)
    assert(signal and signal.Connect, "Arc.signals.debounced: invalid signal")
    local pending = false
    return signal:Connect(function(...)
        local args = {...}
        if not pending then
            pending = true
            schedFn(delay, function()
                pending = false
                handler(table.unpack(args))
            end)
        end
    end)
end

-- ── Signal bridge ─────────────────────────────────────────────────────────────

--[[
    Forwards all fires from `source` signal to `target` signal.
    Returns the VoltConnection (disconnect to stop forwarding).
]]
function ArcSignals.bridge(source, target)
    assert(source and source.Connect, "Arc.signals.bridge: invalid source signal")
    assert(target and target.Fire,    "Arc.signals.bridge: invalid target signal")
    return source:Connect(function(...)
        target:Fire(...)
    end)
end

-- ── Await helper ─────────────────────────────────────────────────────────────

--[[
    Yields the current coroutine until signal fires, then returns the payload.
    Thin wrapper over VoltSignal:Wait() with a nil-guard.
]]
function ArcSignals.await(signal)
    assert(signal and signal.Wait, "Arc.signals.await: invalid signal")
    return signal:Wait()
end

-- ── Dev tests ─────────────────────────────────────────────────────────────────

if getgenv().AxiumDevMode then
    local AL = getgenv().AxiumLog
    local passed, failed_count = 0, 0

    local function pass(label)
        passed = passed + 1
        AL.info("Arc", "signals", "test", "PASS  " .. label)
    end

    local function fail(label, got, expected)
        failed_count = failed_count + 1
        AL.error("Arc", "signals", "test",
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

    -- Only run signal tests if VoltSignal is available
    if not VoltSignal then
        AL.warning("Arc", "signals", "test",
            "VoltSignal not available — skipping signal tests (expected outside executor)")
    else
        -- new()
        local sig = ArcSignals.new()
        assertTrue("new() returns signal", sig ~= nil)
        assertTrue("new() has Connect",    type(sig.Connect) == "function")
        assertTrue("new() has Fire",       type(sig.Fire)    == "function")

        -- Basic fire/connect
        local received = nil
        local conn = sig:Connect(function(v) received = v end)
        sig:Fire(42)
        eq("basic fire/connect", received, 42)
        conn:Disconnect()
        sig:Fire(99)
        eq("disconnect stops handler", received, 42)  -- still 42

        -- ConnectionGroup
        local sig2 = ArcSignals.new()
        local grp  = ArcSignals.newGroup()
        local hits  = 0
        grp:connect(sig2, function() hits = hits + 1 end)
        grp:connect(sig2, function() hits = hits + 1 end)
        eq("group count", grp:count(), 2)
        sig2:Fire()
        eq("group both fire", hits, 2)
        grp:disconnectAll()
        sig2:Fire()
        eq("group disconnectAll stops", hits, 2)  -- no change

        -- Safe double-disconnect
        local ok = pcall(function() grp:disconnectAll() end)
        assertTrue("group double-disconnect safe", ok)

        -- once()
        local sig3  = ArcSignals.new()
        local onceCount = 0
        ArcSignals.once(sig3, function() onceCount = onceCount + 1 end)
        sig3:Fire()
        sig3:Fire()
        sig3:Fire()
        eq("once fires exactly once", onceCount, 1)

        -- filtered()
        local sig4   = ArcSignals.new()
        local evenSum = 0
        ArcSignals.filtered(sig4, function(v) return v % 2 == 0 end,
            function(v) evenSum = evenSum + v end)
        sig4:Fire(1)
        sig4:Fire(2)
        sig4:Fire(3)
        sig4:Fire(4)
        eq("filtered even sum", evenSum, 6)  -- 2 + 4

        -- mapped()
        local sig5  = ArcSignals.new()
        local mapped_val = nil
        ArcSignals.mapped(sig5, function(v) return v * 10 end,
            function(v) mapped_val = v end)
        sig5:Fire(7)
        eq("mapped", mapped_val, 70)

        -- bridge()
        local sigA = ArcSignals.new()
        local sigB = ArcSignals.new()
        local bridgeVal = nil
        sigB:Connect(function(v) bridgeVal = v end)
        local bridgeConn = ArcSignals.bridge(sigA, sigB)
        sigA:Fire("hello")
        eq("bridge forwards", bridgeVal, "hello")
        bridgeConn:Disconnect()
        sigA:Fire("world")
        eq("bridge disconnect stops", bridgeVal, "hello")
    end

    AL.info("Arc", "signals", "tests", string.format(
        "Suite complete — %d passed, %d failed", passed, failed_count
    ))
    if failed_count > 0 then
        AL.critical("Arc", "signals", "tests", string.format(
            "%d test(s) FAILED in Arc.signals", failed_count
        ))
    end
end

-- ── Registration ──────────────────────────────────────────────────────────────

local env = getgenv()
env._Axium             = env._Axium or {}
env._Axium.Arc         = env._Axium.Arc or {}
env._Axium.Arc.signals = ArcSignals

if env.AxiumLoader then
    env.AxiumLoader.load("Arc.signals", function() end)
end

return ArcSignals
