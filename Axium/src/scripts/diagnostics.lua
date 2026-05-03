--[[
    Axium/src/scripts/diagnostics.lua
    Central diagnostics system. Supersedes the inline log in the loader
    after this module loads. All subsystems should use AxiumDiag instead
    of AxiumLog directly from this point forward.

    Features:
    - Rolling log buffer with configurable max size
    - Severity levels: info, warning, error, critical
    - Structured entries: timestamp + subsystem + module + fn + stack + message + args
    - Duplicate dedup with cooldown counter
    - Clipboard copy via setclipboard on every error/critical (filtered)
    - Optional console output hook
    - Optional overlay output hook (for future dev UI)
    - Stack trace capture on error/critical
    - Session summary report
]]

local Diag = {}

-- Config
local MAX_BUFFER      = 2000   -- max entries in rolling buffer
local DEDUP_COOLDOWN  = 8      -- seconds before identical entry logs again
local CLIP_COOLDOWN   = 15     -- seconds before same error re-copies to clipboard
local CLIP_SEVERITIES = { error = true, critical = true }

-- Internal state
local _buffer    = {}   -- rolling array of entry tables
local _dedupMap  = {}   -- [hash] -> { count, lastTime }
local _clipMap   = {}   -- [hash] -> lastClipTime
local _hooks     = { console = nil, overlay = nil }
local _counters  = { info = 0, warning = 0, error = 0, critical = 0, suppressed = 0 }
local _startTime = nil

-- Timestamp
local function now()
    if tick then return tick() end
    return os.clock()
end

-- Capture stack trace string, skipping `skip` levels above this function
local function captureStack(skip)
    if type(debug) ~= "table" or type(debug.traceback) ~= "function" then
        return nil
    end
    local ok, trace = pcall(debug.traceback, "", (skip or 2) + 1)
    if ok and type(trace) == "string" and #trace > 0 then
        -- Strip leading whitespace/newline
        return trace:match("^%s*(.-)%s*$")
    end
    return nil
end

-- Entry hash for dedup (excludes timestamp and args to catch repeats across time)
local function entryHash(severity, subsystem, module, fn, message)
    return severity .. "|" .. subsystem .. "|" .. module .. "|" .. fn .. "|" .. message
end

-- Format a structured log line (no stack trace -- kept in entry table separately)
local function formatLine(entry)
    local base = string.format(
        "[%-5s]  t=%.4f  [%s::%s::%s]  %s",
        entry.severity:upper(), entry.t,
        entry.subsystem, entry.module, entry.fn,
        entry.message
    )
    if entry.args ~= nil then
        base = base .. "  | args=" .. tostring(entry.args)
    end
    return base
end

-- Send to registered output hooks
local function dispatch(line, severity)
    if _hooks.console then
        pcall(_hooks.console, line, severity)
    elseif getgenv().AxiumDevMode then
        pcall(function()
            if rconsoleprint then rconsoleprint(line .. "\n")
            elseif print then print(line) end
        end)
    end
    if _hooks.overlay then
        pcall(_hooks.overlay, line, severity)
    end
end

-- Attempt clipboard copy with its own cooldown per hash
local function tryClipboard(hash, line)
    if type(setclipboard) ~= "function" then return end
    local t = now()
    local last = _clipMap[hash]
    if last and (t - last) < CLIP_COOLDOWN then return end
    _clipMap[hash] = t
    local report = string.format(
        "=== AXIUM DIAGNOSTIC ERROR ===\n%s\n==============================",
        line
    )
    pcall(setclipboard, report)
end

-- Core write function
local function write(severity, subsystem, module, fn, message, args, stackDepth)
    local t    = now()
    local hash = entryHash(severity, subsystem, module, fn, message)
    local rec  = _dedupMap[hash]

    if rec then
        if (t - rec.lastTime) < DEDUP_COOLDOWN then
            rec.count     = rec.count + 1
            _counters.suppressed = _counters.suppressed + 1
            return
        end
        rec.lastTime = t
        rec.count    = rec.count + 1
    else
        _dedupMap[hash] = { count = 1, firstTime = t, lastTime = t }
    end

    local stack = nil
    if severity == "error" or severity == "critical" then
        stack = captureStack((stackDepth or 2) + 1)
    end

    local entry = {
        t          = t,
        severity   = severity,
        subsystem  = subsystem,
        module     = module,
        fn         = fn,
        message    = message,
        args       = args,
        stack      = stack,
        hash       = hash,
        repeatCount = _dedupMap[hash].count,
    }

    -- Rolling buffer: drop oldest if full
    if #_buffer >= MAX_BUFFER then
        table.remove(_buffer, 1)
    end
    table.insert(_buffer, entry)

    _counters[severity] = (_counters[severity] or 0) + 1

    local line = formatLine(entry)
    dispatch(line, severity)

    -- Clipboard on error/critical
    if CLIP_SEVERITIES[severity] then
        local clipLine = line
        if stack then
            clipLine = clipLine .. "\nStack:\n" .. stack
        end
        tryClipboard(hash, clipLine)
    end
end

-- -- Public API ----------------------------------------------------------------

-- Log at info level
function Diag.info(subsystem, module, fn, message, args)
    write("info", subsystem, module, fn, message, args, 2)
end

-- Log at warning level
function Diag.warning(subsystem, module, fn, message, args)
    write("warning", subsystem, module, fn, message, args, 2)
end

-- Log at error level; copies to clipboard (with cooldown)
function Diag.error(subsystem, module, fn, message, args)
    write("error", subsystem, module, fn, message, args, 2)
end

-- Log at critical level; copies to clipboard (with cooldown)
-- Callers should handle fallback/restart behavior after calling this
function Diag.critical(subsystem, module, fn, message, args)
    write("critical", subsystem, module, fn, message, args, 2)
end

-- Register optional console output hook: fn(line: string, severity: string)
function Diag.setConsoleHook(fn)
    assert(type(fn) == "function" or fn == nil,
        "Diag.setConsoleHook: expected function or nil")
    _hooks.console = fn
end

-- Register optional overlay output hook: fn(line: string, severity: string)
function Diag.setOverlayHook(fn)
    assert(type(fn) == "function" or fn == nil,
        "Diag.setOverlayHook: expected function or nil")
    _hooks.overlay = fn
end

-- Returns a copy of the raw entry buffer (array of entry tables)
function Diag.getBuffer()
    local copy = {}
    for i, e in ipairs(_buffer) do copy[i] = e end
    return copy
end

-- Returns entries filtered by minimum severity
-- minSeverity: "info" | "warning" | "error" | "critical"
local SEVERITY_RANK = { info = 1, warning = 2, error = 3, critical = 4 }
function Diag.getBufferFiltered(minSeverity)
    local minRank = SEVERITY_RANK[minSeverity] or 1
    local out = {}
    for _, e in ipairs(_buffer) do
        if (SEVERITY_RANK[e.severity] or 0) >= minRank then
            out[#out + 1] = e
        end
    end
    return out
end

-- Returns last N entries
function Diag.tail(n)
    n = n or 50
    local out = {}
    local start = math.max(1, #_buffer - n + 1)
    for i = start, #_buffer do
        out[#out + 1] = _buffer[i]
    end
    return out
end

-- Returns counter table: { info, warning, error, critical, suppressed }
function Diag.counters()
    return {
        info      = _counters.info,
        warning   = _counters.warning,
        error     = _counters.error,
        critical  = _counters.critical,
        suppressed = _counters.suppressed,
    }
end

-- Clears the log buffer and resets dedup state
function Diag.clear()
    _buffer   = {}
    _dedupMap = {}
    _clipMap  = {}
    _counters = { info = 0, warning = 0, error = 0, critical = 0, suppressed = 0 }
end

-- Builds a full formatted report string from the current buffer
function Diag.buildReport()
    local lines = {}
    for _, e in ipairs(_buffer) do
        lines[#lines + 1] = formatLine(e)
        if e.stack then
            lines[#lines + 1] = "  Stack: " .. e.stack:gsub("\n", "\n  ")
        end
    end

    -- Dedup summary
    local dupLines = {}
    for hash, rec in pairs(_dedupMap) do
        if rec.count > 1 then
            dupLines[#dupLines + 1] = string.format(
                "  (x%d, first=%.4f last=%.4f) %s",
                rec.count, rec.firstTime, rec.lastTime,
                hash:gsub("|", " :: ")
            )
        end
    end

    local c = Diag.counters()
    local header = string.format(
        "=== AXIUM DIAGNOSTIC REPORT ===\n"..
        "Info: %d | Warn: %d | Error: %d | Critical: %d | Suppressed: %d\n"..
        "Entries in buffer: %d / %d\n"..
        "================================",
        c.info, c.warning, c.error, c.critical, c.suppressed,
        #_buffer, MAX_BUFFER
    )

    local parts = { header, table.concat(lines, "\n") }
    if #dupLines > 0 then
        table.sort(dupLines)
        parts[#parts + 1] = "\n--- Dedup Summary ---"
        parts[#parts + 1] = table.concat(dupLines, "\n")
        parts[#parts + 1] = "---------------------"
    end
    return table.concat(parts, "\n")
end

-- Copies the full report to clipboard
function Diag.copyReport()
    if type(setclipboard) ~= "function" then return false end
    pcall(setclipboard, Diag.buildReport())
    return true
end

-- Migrates existing AxiumLog entries into this buffer (called once at startup)
local function migrateLoaderLog()
    local AL = getgenv().AxiumLog
    if not AL or type(AL.getEntries) ~= "function" then return 0 end
    local entries = AL.getEntries()
    local count = 0
    for _, line in ipairs(entries) do
        -- Parse loader format: "[SEVER]  t=X.XXXX  [sub::mod::fn]  msg"
        local sev, ts, sub, mod, fn, msg = line:match(
            "%[(%w+)%s*%]%s+t=([%d%.]+)%s+%[(.-)::(.-)::(.-)%]%s+(.*)"
        )
        if sev and ts then
            local entry = {
                t         = tonumber(ts) or 0,
                severity  = sev:lower(),
                subsystem = sub or "?",
                module    = mod or "?",
                fn        = fn  or "?",
                message   = msg or line,
                args      = nil,
                stack     = nil,
                hash      = entryHash(sev:lower(), sub or "?", mod or "?", fn or "?", msg or line),
                repeatCount = 1,
                migrated  = true,
            }
            table.insert(_buffer, entry)
            count = count + 1
        end
    end
    return count
end

-- Replace AxiumLog with a thin shim that forwards to Diag
local function installShim()
    local env = getgenv()
    env.AxiumLog = {
        info     = function(s, m, f, msg, ctx) Diag.info(s, m, f, msg, ctx)     end,
        warning  = function(s, m, f, msg, ctx) Diag.warning(s, m, f, msg, ctx)  end,
        error    = function(s, m, f, msg, ctx) Diag.error(s, m, f, msg, ctx)    end,
        critical = function(s, m, f, msg, ctx) Diag.critical(s, m, f, msg, ctx) end,
        getEntries = function() return _buffer end,
        dump       = function() return Diag.buildReport() end,
        toClipboard = function() Diag.copyReport() end,
    }
end

-- -- Init sequence ------------------------------------------------------------

_startTime = now()
local migrated = migrateLoaderLog()
installShim()

Diag.info("Axium", "diagnostics", "init", string.format(
    "Diagnostics online | migrated %d loader entries | buffer=%d/%d | dedupCooldown=%ds",
    migrated, #_buffer, MAX_BUFFER, DEDUP_COOLDOWN
))

-- -- Dev tests ----------------------------------------------------------------

if getgenv().AxiumDevMode then
    local passed, failed_count = 0, 0

    local function pass(label)
        passed = passed + 1
        Diag.info("Axium", "diagnostics", "test", "PASS  " .. label)
    end

    local function fail(label, got, expected)
        failed_count = failed_count + 1
        Diag.error("Axium", "diagnostics", "test",
            string.format("FAIL  %s  | got=%s expected=%s",
                label, tostring(got), tostring(expected)))
    end

    local function eq(label, got, expected)
        if got == expected then pass(label) else fail(label, got, expected) end
    end

    local function assertTrue(label, v)
        if v then pass(label) else fail(label, tostring(v), "true") end
    end

    local function assertGte(label, got, threshold)
        if got >= threshold then pass(label)
        else fail(label, tostring(got), ">=" .. tostring(threshold)) end
    end

    -- Basic logging
    local before = #_buffer
    Diag.info("Test", "diag", "test", "info entry")
    Diag.warning("Test", "diag", "test", "warn entry")
    Diag.error("Test", "diag", "test", "error entry")
    Diag.critical("Test", "diag", "test", "critical entry")
    assertTrue("buffer grows", #_buffer > before)

    -- Counters
    local c = Diag.counters()
    assertTrue("counter info >= 1",     c.info >= 1)
    assertTrue("counter warning >= 1",  c.warning >= 1)
    assertTrue("counter error >= 1",    c.error >= 1)
    assertTrue("counter critical >= 1", c.critical >= 1)

    -- Severity filter
    local errors = Diag.getBufferFiltered("error")
    assertTrue("filter error level", #errors >= 1)
    for _, e in ipairs(errors) do
        assertTrue("filter only error+crit",
            e.severity == "error" or e.severity == "critical")
    end

    -- Dedup: same call twice rapidly -> suppressed
    local prevSuppressed = Diag.counters().suppressed
    Diag.info("Test", "diag", "dedup", "repeat me")
    Diag.info("Test", "diag", "dedup", "repeat me")  -- should suppress
    local nowSuppressed = Diag.counters().suppressed
    assertTrue("dedup suppresses repeat", nowSuppressed > prevSuppressed)

    -- tail()
    local tail10 = Diag.tail(10)
    assertTrue("tail returns entries", #tail10 >= 1)
    assertTrue("tail bounded", #tail10 <= 10)

    -- getBuffer() returns copy, not reference
    local buf1 = Diag.getBuffer()
    local buf2 = Diag.getBuffer()
    assertTrue("getBuffer copy", buf1 ~= buf2)
    assertTrue("getBuffer populated", #buf1 > 0)

    -- buildReport() produces string
    local report = Diag.buildReport()
    assertTrue("buildReport is string", type(report) == "string")
    assertTrue("buildReport non-empty", #report > 50)

    -- Console hook
    local hookFired = false
    Diag.setConsoleHook(function(line, sev)
        hookFired = true
    end)
    Diag.info("Test", "diag", "hook", "hook test message")
    assertTrue("console hook fires", hookFired)
    Diag.setConsoleHook(nil)  -- restore

    -- Overlay hook
    local overlayLine = nil
    Diag.setOverlayHook(function(line, _)
        overlayLine = line
    end)
    Diag.warning("Test", "diag", "overlay", "overlay test")
    assertTrue("overlay hook receives line", type(overlayLine) == "string")
    Diag.setOverlayHook(nil)

    -- AxiumLog shim forwards correctly
    local AL = getgenv().AxiumLog
    assertTrue("shim info fn",    type(AL.info)    == "function")
    assertTrue("shim warning fn", type(AL.warning) == "function")
    assertTrue("shim error fn",   type(AL.error)   == "function")
    assertTrue("shim dump fn",    type(AL.dump)    == "function")
    local shimBefore = #_buffer
    AL.info("Test", "shim", "test", "via shim")
    assertTrue("shim writes to buffer", #_buffer > shimBefore)

    -- Stack trace on error entries
    local errEntries = Diag.getBufferFiltered("error")
    local hasStack = false
    for _, e in ipairs(errEntries) do
        if e.stack and #e.stack > 0 then hasStack = true; break end
    end
    assertTrue("error entries have stack", hasStack)

    Diag.info("Axium", "diagnostics", "tests", string.format(
        "Suite complete -- %d passed, %d failed", passed, failed_count
    ))
    if failed_count > 0 then
        Diag.critical("Axium", "diagnostics", "tests",
            string.format("%d test(s) FAILED in diagnostics", failed_count))
    end
end

-- -- Registration -------------------------------------------------------------

local env = getgenv()
env._Axium              = env._Axium or {}
env._Axium.Diagnostics  = Diag
env.AxiumDiag           = Diag

if env.AxiumLoader then
    env.AxiumLoader.load("Axium.diagnostics", function() end)
end

return Diag
