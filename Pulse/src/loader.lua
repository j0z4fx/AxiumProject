--[[
    Pulse/src/loader.lua
    Entry point for Axium. Run this file first before any other module.

    DEV MODE: Set AxiumDevMode = true below to enable test suites,
    verbose logging, and developer tooling across all modules.
    Set to false for production — dev globals and harness will not exist.
]]

-- ============================================================
-- [[ DEV MODE TOGGLE — flip this before running ]]
getgenv().AxiumDevMode = true
-- ============================================================

-- Internal log state (private to this file)
local _entries  = {}    -- ordered list of formatted log lines
local _errorMap = {}    -- [hash] -> { count, firstTime, lastTime }
local _loaded   = {}    -- names of successfully loaded modules
local _failed   = {}    -- names of failed modules

local LOG_COOLDOWN = 10    -- seconds: suppress identical entries within this window
local MAX_ENTRIES  = 1000  -- hard cap on log buffer size

-- Timestamp: prefer tick() (Roblox executor), fall back to os.clock()
local function now()
    if tick then return tick() end
    return os.clock()
end

local function makeHash(subsystem, module, fn, message)
    return subsystem .. "\0" .. module .. "\0" .. fn .. "\0" .. message
end

local LABELS = {
    info     = "[INFO ]",
    warning  = "[WARN ]",
    error    = "[ERROR]",
    critical = "[CRIT ]",
}

local function writeEntry(severity, subsystem, module, fn, message, argCtx)
    local h   = makeHash(subsystem, module, fn, message)
    local t   = now()
    local rec = _errorMap[h]

    if rec then
        if (t - rec.lastTime) < LOG_COOLDOWN then
            rec.count = rec.count + 1
            return  -- suppress: within cooldown window
        end
        rec.lastTime = t
        rec.count    = rec.count + 1
    else
        _errorMap[h] = { count = 1, firstTime = t, lastTime = t }
    end

    local line
    if argCtx ~= nil then
        line = string.format(
            "%s  t=%.4f  [%s::%s::%s]  %s  | ctx=%s",
            LABELS[severity] or "[LOG  ]", t,
            subsystem, module, fn,
            tostring(message), tostring(argCtx)
        )
    else
        line = string.format(
            "%s  t=%.4f  [%s::%s::%s]  %s",
            LABELS[severity] or "[LOG  ]", t,
            subsystem, module, fn,
            tostring(message)
        )
    end

    if #_entries < MAX_ENTRIES then
        table.insert(_entries, line)
    elseif #_entries == MAX_ENTRIES then
        table.insert(_entries,
            "[WARN ]  t=" .. string.format("%.4f", t) ..
            "  Log buffer reached MAX_ENTRIES (" .. MAX_ENTRIES .. ") — further entries dropped"
        )
    end

    -- Live console output in dev mode
    if getgenv().AxiumDevMode then
        pcall(function()
            if rconsoleprint then
                rconsoleprint(line .. "\n")
            elseif print then
                print(line)
            end
        end)
    end
end

-- Builds the dedup summary block appended to the final report
local function buildDupSummary()
    local lines = {}
    for h, rec in pairs(_errorMap) do
        if rec.count > 1 then
            local display = h:gsub("\0", " :: ")
            table.insert(lines, string.format(
                "  (x%d hits, first=%.4f last=%.4f)  %s",
                rec.count, rec.firstTime, rec.lastTime, display
            ))
        end
    end
    if #lines == 0 then return nil end
    table.sort(lines)
    return table.concat(lines, "\n")
end

-- ── Public log API ────────────────────────────────────────────────────────────

getgenv().AxiumLog = {
    -- Log at info severity
    info = function(sub, mod, fn, msg, ctx)
        writeEntry("info", sub, mod, fn, msg, ctx)
    end,

    -- Log at warning severity
    warning = function(sub, mod, fn, msg, ctx)
        writeEntry("warning", sub, mod, fn, msg, ctx)
    end,

    -- Log at error severity
    error = function(sub, mod, fn, msg, ctx)
        writeEntry("error", sub, mod, fn, msg, ctx)
    end,

    -- Log at critical severity
    critical = function(sub, mod, fn, msg, ctx)
        writeEntry("critical", sub, mod, fn, msg, ctx)
    end,

    -- Returns raw entry array (read-only intent)
    getEntries = function()
        return _entries
    end,

    -- Builds and returns the full formatted report string
    dump = function()
        local parts = { table.concat(_entries, "\n") }
        local dups  = buildDupSummary()
        if dups then
            table.insert(parts, "\n\226\148\128\226\148\128\226\148\128 Suppressed Duplicate Summary \226\148\128\226\148\128\226\148\128")
            table.insert(parts, dups)
            table.insert(parts, string.rep("\226\148\128", 20))
        end
        return table.concat(parts, "\n")
    end,

    -- Compiles the full report and copies it to the system clipboard
    toClipboard = function()
        local AL   = getgenv().AxiumLog
        local mode = getgenv().AxiumDevMode and "DEVELOPMENT" or "PRODUCTION"

        local header = string.format(
            "Mode     : %s\n" ..
            "Entries  : %d\n" ..
            "Loaded   : %d\n" ..
            "Failed   : %d\n",
            mode, #_entries, #_loaded, #_failed
        )

        local loadedList = #_loaded > 0
            and ("Loaded:\n  " .. table.concat(_loaded, "\n  "))
            or  "No modules loaded."

        local failedList = #_failed > 0
            and ("Failed:\n  " .. table.concat(_failed, "\n  "))
            or  nil

        local sections = {
            "=== AXIUM LOG REPORT ===",
            header,
            loadedList,
        }
        if failedList then
            table.insert(sections, failedList)
        end
        table.insert(sections, "--- Log ---")
        table.insert(sections, AL.dump())

        setclipboard(table.concat(sections, "\n"))
    end,
}

-- ── Module loader ─────────────────────────────────────────────────────────────

getgenv().AxiumLoader = {

    --[[
        Register a module load attempt.
        name   : human-readable module identifier e.g. "Arc.math"
        initFn : zero-argument function containing the module's init logic
        If initFn throws, the error is captured and logged at error severity.
    ]]
    load = function(name, initFn)
        local AL = getgenv().AxiumLog
        local ok, err = pcall(initFn)
        if ok then
            table.insert(_loaded, name)
            AL.info("Pulse", "Loader", "load", "Module loaded: " .. name)
        else
            table.insert(_failed, name)
            AL.error("Pulse", "Loader", "load", "Module FAILED: " .. name, tostring(err))
        end
    end,

    --[[
        Call after all modules have been loaded.
        Logs a boot summary and copies the full report to clipboard.
    ]]
    finalize = function()
        local AL = getgenv().AxiumLog
        AL.info("Pulse", "Loader", "finalize", string.format(
            "Boot complete — loaded: %d | failed: %d", #_loaded, #_failed
        ))
        if #_failed > 0 then
            AL.warning("Pulse", "Loader", "finalize",
                "Failed: " .. table.concat(_failed, ", ")
            )
        end
        AL.toClipboard()
    end,

    -- Returns the list of successfully loaded module names
    getLoaded = function() return _loaded end,

    -- Returns the list of failed module names
    getFailed = function() return _failed end,
}

-- ── Boot log ──────────────────────────────────────────────────────────────────

getgenv().AxiumLog.info("Pulse", "Loader", "init", string.format(
    "Axium loader initialised | DevMode=%s", tostring(getgenv().AxiumDevMode)
))
