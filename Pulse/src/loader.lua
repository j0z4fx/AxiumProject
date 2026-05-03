--[[
    Pulse/src/loader.lua
    Entry point for Axium. Run ONLY this file in your executor.
    It reads and loadstrings every module in dependency order.

    DEV MODE: Set AxiumDevMode = true below to enable test suites,
    verbose logging, and developer tooling across all modules.
    Set to false for production — dev globals and harness will not exist.

    Source is fetched via HTTP GET from raw GitHub on every boot.
    No local file reads. No require. No bundled source.
]]

-- ============================================================
-- [[ DEV MODE TOGGLE — flip this before running ]]
getgenv().AxiumDevMode = true

-- [[ RAW SOURCE BASE — trailing slash required ]]
local RAW_BASE = "https://raw.githubusercontent.com/j0z4fx/AxiumProject/master/"
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

-- Ordered list of modules to load. Path is relative to BASE_PATH.
-- Add new entries here as modules are completed, in dependency order.
local MODULE_LIST = {
    -- Phase 1: Arc utilities
    { name = "Arc.math",       path = "Arc/src/math.lua"       },
    { name = "Arc.utils",      path = "Arc/src/utils.lua"      },
    { name = "Arc.cache",      path = "Arc/src/cache.lua"      },
    { name = "Arc.transforms", path = "Arc/src/transforms.lua" },
    { name = "Arc.signals",    path = "Arc/src/signals.lua"    },
    { name = "Arc.init",       path = "Arc/src/init.lua"       },
    -- Phase 2: Diagnostics          (added when T-007 complete)
    -- Phase 3: Veil                 (added when T-008..T-012 complete)
    -- Phase 4: Axium Core           (added when T-013..T-017 complete)
    -- ... remainder added as tasks complete
}

-- HTTP GET: tries executor request APIs in order of commonality
local function httpGet(url)
    -- Synapse X / KRNL / Fluxus / most modern executors
    if request then
        local res = request({ Url = url, Method = "GET" })
        if res and res.Body then return res.Body end
    end
    -- Alternate namespace (some executors)
    if http and http.request then
        local res = http.request({ Url = url, Method = "GET" })
        if res and res.Body then return res.Body end
    end
    -- Roblox game object (works inside Roblox client with HttpService enabled)
    if game and game.HttpGet then
        return game:HttpGet(url)
    end
    error("No HTTP API found in this executor")
end

local function execModule(name, relativePath)
    local AL  = getgenv().AxiumLog
    local url = RAW_BASE .. relativePath
    AL.info("Pulse", "Loader", "exec", "Fetching: " .. name, url)

    local source, compileErr, runOk, runErr

    -- Fetch source over HTTP
    local fetchOk
    fetchOk, source = pcall(httpGet, url)
    if not fetchOk or not source or #source == 0 then
        table.insert(_failed, name)
        AL.error("Pulse", "Loader", "exec", "Fetch FAILED: " .. name, source)
        return
    end

    -- Compile via loadstring
    local chunk
    chunk, compileErr = loadstring(source, "@" .. relativePath)
    if not chunk then
        table.insert(_failed, name)
        AL.error("Pulse", "Loader", "exec", "Compile FAILED: " .. name, compileErr)
        return
    end

    -- Execute
    runOk, runErr = pcall(chunk)
    if not runOk then
        table.insert(_failed, name)
        AL.error("Pulse", "Loader", "exec", "Runtime FAILED: " .. name, runErr)
        return
    end

    table.insert(_loaded, name)
    AL.info("Pulse", "Loader", "exec", "OK: " .. name)
end

getgenv().AxiumLoader = {

    --[[
        Used by individual module files to self-register with the loader.
        The loader calls this after loadstring executes the file, but modules
        can also call it directly if loaded out of order during development.
        name   : human-readable module identifier e.g. "Arc.math"
        initFn : optional zero-argument function for any post-load init work
    ]]
    load = function(name, initFn)
        local AL = getgenv().AxiumLog
        if initFn then
            local ok, err = pcall(initFn)
            if not ok then
                AL.error("Pulse", "Loader", "load", "initFn FAILED: " .. name, tostring(err))
                return
            end
        end
        AL.info("Pulse", "Loader", "load", "Registered: " .. name)
    end,

    --[[
        Runs the full boot sequence: reads and loadstrings every module in
        MODULE_LIST order, then finalizes with a clipboard report.
    ]]
    boot = function()
        local AL = getgenv().AxiumLog
        AL.info("Pulse", "Loader", "boot", string.format(
            "Starting boot — %d modules queued", #MODULE_LIST
        ))
        for _, entry in ipairs(MODULE_LIST) do
            execModule(entry.name, entry.path)
        end
        getgenv().AxiumLoader.finalize()
    end,

    --[[
        Finalizes the session: logs summary and copies full report to clipboard.
        Called automatically by boot(), or manually after custom load sequences.
    ]]
    finalize = function()
        local AL = getgenv().AxiumLog
        AL.info("Pulse", "Loader", "finalize", string.format(
            "Boot complete — loaded: %d | failed: %d", #_loaded, #_failed
        ))
        if #_failed > 0 then
            AL.warning("Pulse", "Loader", "finalize",
                "Failed modules: " .. table.concat(_failed, ", ")
            )
        end
        AL.toClipboard()
    end,

    -- Returns the list of successfully loaded module names
    getLoaded = function() return _loaded end,

    -- Returns the list of failed module names
    getFailed = function() return _failed end,
}

-- ── Boot ──────────────────────────────────────────────────────────────────────

getgenv().AxiumLog.info("Pulse", "Loader", "init", string.format(
    "Axium loader initialised | DevMode=%s | Source=%s",
    tostring(getgenv().AxiumDevMode), RAW_BASE
))

-- Begin loading all modules immediately
getgenv().AxiumLoader.boot()
