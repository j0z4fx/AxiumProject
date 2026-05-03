--[[
    Veil/src/init.lua
    Assembles Veil from its four submodules:
      Validator, SignalFilter, Gatekeeper, ApiWrap
    Adds STRATA-derived runtime infrastructure:
      ServiceIsolation (cloneref), Protection (protectgui), Hooks (newcclosure/hookfunction),
      Env (isolated loadstring execution), Scanner (getgc/getscripts anti-cheat scan)
    Security hardening (from STRATA _hardenMeta pattern):
      - All class metatables: Lua fns wrapped as C closures, setreadonly applied
      - Veil table mutation-locked via __newindex after init
    Publishes getgenv().Veil and getgenv()._Axium.Veil (merged namespace).
    Once active, Veil cannot be replaced or mutated externally.
]]

-- -- Dependency resolution ----------------------------------------------------

local env   = getgenv()
local _axv  = env._Axium and env._Axium.Veil
assert(_axv and _axv.Validator,   "[Veil] Veil.Validator not loaded")
assert(_axv and _axv.SignalFilter, "[Veil] Veil.SignalFilter not loaded")
assert(_axv and _axv.Gatekeeper,  "[Veil] Veil.Gatekeeper not loaded")
assert(_axv and _axv.ApiWrap,     "[Veil] Veil.ApiWrap not loaded")

local Validator   = _axv.Validator
local SignalFilter = _axv.SignalFilter
local Gatekeeper  = _axv.Gatekeeper
local ApiWrap     = _axv.ApiWrap

-- -- ServiceIsolation ----------------------------------------------------------
-- Wraps each game service in cloneref to prevent reference-equality anti-cheat
-- detection. Falls back to raw instance when cloneref unavailable.

local ServiceIsolation = {}
ServiceIsolation.__index = ServiceIsolation

local function _safeClone(instance)
    local cloneRef = cloneref or clonereference
    if type(cloneRef) ~= "function" then return instance end
    local ok, cloned = pcall(cloneRef, instance)
    return (ok and cloned ~= nil) and cloned or instance
end

function ServiceIsolation.new()
    return setmetatable({ _cache = {} }, ServiceIsolation)
end

function ServiceIsolation:Get(name)
    if self._cache[name] then return self._cache[name] end
    local ok, svc = pcall(function() return game:GetService(name) end)
    if not ok or not svc then return nil end
    local isolated = _safeClone(svc)
    self._cache[name] = isolated
    return isolated
end

function ServiceIsolation:Require(name)
    local svc = self:Get(name)
    assert(svc, "[Veil.Services] Missing service '" .. tostring(name) .. "'")
    return svc
end

-- -- Protection ----------------------------------------------------------------
-- Resolves and applies protectgui (or syn.protect_gui) to hide ScreenGuis
-- from the game's LocalScript environment and anti-cheat enumeration.

local Protection = {}
Protection.__index = Protection

local function _resolveProtectGui()
    if type(protectgui)     == "function" then return protectgui     end
    if type(protect_gui)    == "function" then return protect_gui    end
    if type(syn)            == "table"
    and type(syn.protect_gui) == "function" then return syn.protect_gui end
    return nil
end

function Protection.new()
    return setmetatable({}, Protection)
end

function Protection:GetHandler()
    return _resolveProtectGui()
end

function Protection:Apply(instance)
    local handler = self:GetHandler()
    if not handler or not instance then return false end
    return pcall(handler, instance)
end

-- -- Hooks ---------------------------------------------------------------------
-- newcclosure-wrapped hookfunction / hookmetamethod.
-- Replacements become C closures so getupvalues cannot inspect internals.

local Hooks = {}
Hooks.__index = Hooks

local function _wrapCClosure(fn)
    if type(newcclosure) ~= "function" then return fn end
    local ok, wrapped = pcall(newcclosure, fn)
    return (ok and wrapped) or fn
end

function Hooks.new()
    return setmetatable({ _entries = {} }, Hooks)
end

function Hooks:HookFunction(target, replacement)
    if type(hookfunction) ~= "function" then return nil, "hookfunction unavailable" end
    local ok, original = pcall(hookfunction, target, _wrapCClosure(replacement))
    if not ok then return nil, original end
    table.insert(self._entries, { kind = "function", target = target, original = original })
    return original
end

function Hooks:HookMetamethod(object, method, callback)
    if type(hookmetamethod) ~= "function" then return nil, "hookmetamethod unavailable" end
    local ok, original = pcall(hookmetamethod, object, method, _wrapCClosure(callback))
    if not ok then return nil, original end
    table.insert(self._entries, { kind = "metamethod", target = object, method = method, original = original })
    return original
end

-- -- Env -----------------------------------------------------------------------
-- Isolated execution environment. Execute() compiles + runs a source string
-- in an isolated global environment so loaded scripts cannot pollute shared env.

local Env = {}
Env.__index = Env

local function _getGlobalEnv()
    if type(getgenv) == "function" then
        local ok, g = pcall(getgenv)
        if ok and type(g) == "table" then return g end
    end
    if type(getfenv) == "function" then
        local ok, g = pcall(getfenv, 0)
        if ok and type(g) == "table" then return g end
    end
    return _G
end

function Env.new()
    return setmetatable({ _globals = {} }, Env)
end

function Env:SetGlobal(key, value)
    self._globals[key] = value
    return value
end

function Env:BuildEnvironment(extra)
    local isolated  = {}
    local injected  = {}
    local parent    = _getGlobalEnv()
    for k, v in pairs(self._globals)  do injected[k] = v end
    for k, v in pairs(extra or {})    do injected[k] = v end
    return setmetatable(isolated, {
        __index    = function(_, k) return injected[k] ~= nil and injected[k] or parent[k] end,
        __newindex = function(_, k, v) rawset(isolated, k, v) end,
    })
end

function Env:Wrap(fn, extra)
    if type(fn) ~= "function" then return nil, "Expected function" end
    local environment = self:BuildEnvironment(extra)
    if type(setfenv) == "function" then pcall(setfenv, fn, environment) end
    return fn, environment
end

function Env:Execute(source, extra)
    if type(source) ~= "string" then return nil, "Expected string source" end
    if type(loadstring) ~= "function" then return nil, "loadstring unavailable" end
    local compiled, compileErr = loadstring(source)
    if type(compiled) ~= "function" then return nil, compileErr end
    local wrapped, environment = self:Wrap(compiled, extra)
    if not wrapped then return nil, environment end
    local ok, result = pcall(wrapped)
    if not ok then return nil, result end
    return result, environment
end

-- -- Scanner -------------------------------------------------------------------
-- GC-based security scanner. Inspects live Lua closures and game Scripts for
-- patterns indicating anti-cheat or monitoring code.

local Scanner = {}
Scanner.__index = Scanner

local _SUSPECT_PATTERNS = {
    "anticheat", "anti.?cheat", "hyperion", "byfron",
    "getexecutorname", "is_exploit", "exploit.?detect",
    "script.?monitor", "script.?watcher",
    "kick%.player", "banplayer", "punish",
}

local function _matchSuspect(str)
    if type(str) ~= "string" then return nil end
    local lower = str:lower()
    for _, pat in ipairs(_SUSPECT_PATTERNS) do
        if lower:match(pat) then return pat end
    end
    return nil
end

local function _safeGCFunctions()
    if type(getgc) ~= "function" then return {} end
    local ok, gc = pcall(getgc, false)
    return (ok and type(gc) == "table") and gc or {}
end

local function _safeConstants(fn)
    if type(getconstants) ~= "function" then return {} end
    local ok, c = pcall(getconstants, fn)
    return (ok and type(c) == "table") and c or {}
end

local function _safeUpvalueNames(fn)
    if type(getupvalues) ~= "function" then return {} end
    local ok, u = pcall(getupvalues, fn)
    if not ok or type(u) ~= "table" then return {} end
    local names = {}
    for k in pairs(u) do
        if type(k) == "string" then table.insert(names, k) end
    end
    return names
end

local function _safeScripts()
    if type(getscripts) ~= "function" then return {} end
    local ok, s = pcall(getscripts)
    return (ok and type(s) == "table") and s or {}
end

function Scanner.new()
    return setmetatable({}, Scanner)
end

function Scanner:Run()
    if type(getgc) ~= "function" and type(getscripts) ~= "function" then
        return nil, "No scan APIs available (getgc/getscripts required)"
    end
    local results = {}
    local seen    = {}

    if type(islclosure) == "function" then
        for _, obj in ipairs(_safeGCFunctions()) do
            if type(obj) == "function" and not seen[obj] then
                local isLua = pcall(islclosure, obj) and islclosure(obj)
                if isLua then
                    seen[obj] = true
                    for _, c in pairs(_safeConstants(obj)) do
                        local match = _matchSuspect(c)
                        if match then
                            local src = "unknown"
                            if type(debug) == "table" and type(debug.info) == "function" then
                                local ok2, s = pcall(debug.info, obj, "s")
                                if ok2 and s then src = s end
                            end
                            table.insert(results, {
                                Name      = src:match("[^/\\]+$") or src,
                                Path      = src,
                                Reason    = 'Constant: "' .. tostring(c):sub(1, 36) .. '"',
                                ScriptRef = nil,
                            })
                            break
                        end
                    end
                    if not seen[obj] then
                        for _, uname in ipairs(_safeUpvalueNames(obj)) do
                            if _matchSuspect(uname) then
                                table.insert(results, {
                                    Name      = "closure",
                                    Path      = "gc:upvalue",
                                    Reason    = 'Upvalue: "' .. uname .. '"',
                                    ScriptRef = nil,
                                })
                                seen[obj] = true
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    for _, script in ipairs(_safeScripts()) do
        if typeof(script) == "Instance" and not seen[script] then
            local ok, fullName = pcall(function() return script:GetFullName() end)
            local path = ok and fullName or tostring(script)
            local name = script.Name or "Script"
            if _matchSuspect(name) or _matchSuspect(path) then
                seen[script] = true
                table.insert(results, {
                    Name      = name,
                    Path      = path,
                    Reason    = "Suspicious name",
                    ScriptRef = script,
                })
            end
        end
    end

    return results
end

function Scanner:CopyPath(path)
    local str = tostring(path)
    if type(setclipboard) == "function" then pcall(setclipboard, str); return true end
    if type(toclipboard)  == "function" then pcall(toclipboard,  str); return true end
    return false
end

function Scanner:Kill(scriptRef)
    if typeof(scriptRef) ~= "Instance" then return false end
    pcall(function() scriptRef.Disabled = true end)
    pcall(function() scriptRef.Parent   = nil  end)
    return true
end

-- -- Security hardening --------------------------------------------------------
-- Wraps Lua fns as C closures and freezes metatables.
-- Mirrors STRATA _hardenMeta pattern.

local function _wrapIfLua(fn)
    if type(newcclosure) ~= "function" then return fn end
    local ok, wrapped = pcall(newcclosure, fn)
    return (ok and wrapped) or fn
end

local function _hardenMeta(meta)
    for k, v in pairs(meta) do
        if type(v) == "function" then rawset(meta, k, _wrapIfLua(v)) end
    end
    if rawget(meta, "__metatable") == nil then
        rawset(meta, "__metatable", "locked")
    end
    if type(setreadonly) == "function" then
        pcall(setreadonly, meta, true)
    end
end

-- -- Assembly ------------------------------------------------------------------

local Veil = {
    -- Core submodules
    Validator   = Validator,
    SignalFilter = SignalFilter,
    Gatekeeper  = Gatekeeper,
    ApiWrap     = ApiWrap,
    -- Runtime infrastructure
    Services    = ServiceIsolation.new(),
    Protection  = Protection.new(),
    Hooks       = Hooks.new(),
    Env         = Env.new(),
    Scanner     = Scanner.new(),
}

-- Convenience alias
function Veil.Protect(instance)
    return Veil.Protection:Apply(instance)
end

-- Harden all class metatables
_hardenMeta(ServiceIsolation)
_hardenMeta(Protection)
_hardenMeta(Hooks)
_hardenMeta(Env)
_hardenMeta(Scanner)

-- Wrap standalone module-level fns as C closures
Veil.Protect = _wrapIfLua(Veil.Protect)

-- Mutation lock: external writes to the Veil table throw an error
setmetatable(Veil, {
    __newindex = function(_, k, _v)
        error("[Veil] Cannot mutate Veil externally: " .. tostring(k), 2)
    end,
    __metatable = "locked",
})

-- -- Dev tests -----------------------------------------------------------------

if getgenv().AxiumDevMode then
    local AL = getgenv().AxiumLog
    local passed, failed_count = 0, 0
    local function pass(lbl)
        passed = passed + 1
        AL.info("Veil", "init", "test", "PASS  " .. lbl)
    end
    local function fail(lbl, got, expected)
        failed_count = failed_count + 1
        AL.error("Veil", "init", "test",
            string.format("FAIL  %s  |  got=%s  expected=%s", lbl, tostring(got), tostring(expected)))
    end

    -- Submodules present
    if type(Veil.Validator)    == "table" then pass("Validator present")    else fail("Validator",    type(Veil.Validator),    "table") end
    if type(Veil.SignalFilter) == "table" then pass("SignalFilter present") else fail("SignalFilter", type(Veil.SignalFilter), "table") end
    if type(Veil.Gatekeeper)  == "table" then pass("Gatekeeper present")   else fail("Gatekeeper",  type(Veil.Gatekeeper),   "table") end
    if type(Veil.ApiWrap)     == "table" then pass("ApiWrap present")      else fail("ApiWrap",     type(Veil.ApiWrap),      "table") end

    -- Runtime infra present
    if type(Veil.Services)   == "table" then pass("Services present")   else fail("Services",   type(Veil.Services),   "table") end
    if type(Veil.Protection) == "table" then pass("Protection present") else fail("Protection", type(Veil.Protection), "table") end
    if type(Veil.Hooks)      == "table" then pass("Hooks present")      else fail("Hooks",      type(Veil.Hooks),      "table") end
    if type(Veil.Env)        == "table" then pass("Env present")        else fail("Env",        type(Veil.Env),        "table") end
    if type(Veil.Scanner)    == "table" then pass("Scanner present")    else fail("Scanner",    type(Veil.Scanner),    "table") end

    -- Mutation lock
    local ok, err = pcall(function() Veil.foo = "bar" end)
    if not ok then pass("mutation lock throws") else fail("mutation lock", ok, false) end

    -- Protect fn is callable (handler may be nil in test env, just must not throw)
    local pOk, pErr = pcall(Veil.Protect, nil)
    if pOk then pass("Protect(nil) no throw") else fail("Protect(nil) no throw", pErr, "no error") end

    -- Env.Execute isolated
    local result, _ = Veil.Env:Execute("return 1 + 1")
    if result == 2 then pass("Env.Execute 1+1=2") else fail("Env.Execute", result, 2) end

    -- Scanner.Run returns table or nil+msg (depends on executor)
    local scanResult, scanErr = Veil.Scanner:Run()
    if type(scanResult) == "table" or (scanResult == nil and type(scanErr) == "string") then
        pass("Scanner.Run returns valid result")
    else
        fail("Scanner.Run", type(scanResult), "table or nil+msg")
    end

    -- ServiceIsolation returns nil for nonexistent service
    local svc = Veil.Services:Get("NonExistentService12345")
    if svc == nil then pass("Services.Get nonexistent = nil") else fail("Services.Get nonexistent", svc, nil) end

    AL.info("Veil", "init", "tests",
        string.format("Suite complete -- %d passed, %d failed", passed, failed_count))
    if failed_count > 0 then
        AL.critical("Veil", "init", "tests",
            string.format("%d test(s) FAILED in Veil.init", failed_count))
    end
end

-- -- Registration -------------------------------------------------------------

env._Axium          = env._Axium or {}
env._Axium.Veil     = Veil  -- replace partial namespace with full assembled Veil
env.Veil            = Veil  -- top-level convenience global

if env.AxiumLoader then
    env.AxiumLoader.load("Veil.init", function() end)
end

return Veil