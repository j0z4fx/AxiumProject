--[[
    Arc/src/math.lua
    Pure math utilities: scalar helpers, easing curves, Vector2 ops.
    No Axium dependencies — safe to load standalone.

    Checks getgenv().AxiumDevMode at load time.
    If true, runs a full test suite and logs results via AxiumLog.
]]

local ArcMath = {}

-- ── Scalar ────────────────────────────────────────────────────────────────────

-- Linear interpolation between a and b at position t [0,1]
function ArcMath.lerp(a, b, t)
    return a + (b - a) * t
end

-- Clamp n to the range [min, max]
function ArcMath.clamp(n, min, max)
    if n < min then return min end
    if n > max then return max end
    return n
end

-- Round n to `decimals` decimal places (default 0)
function ArcMath.round(n, decimals)
    local factor = 10 ^ (decimals or 0)
    return math.floor(n * factor + 0.5) / factor
end

-- Re-map value v from [inMin,inMax] to [outMin,outMax]
function ArcMath.map(v, inMin, inMax, outMin, outMax)
    return outMin + (v - inMin) / (inMax - inMin) * (outMax - outMin)
end

-- Returns -1, 0, or 1 depending on the sign of n
function ArcMath.sign(n)
    if n > 0 then return 1 elseif n < 0 then return -1 else return 0 end
end

-- Wraps n within [min, max) (modular arithmetic)
function ArcMath.wrap(n, min, max)
    local range = max - min
    return min + ((n - min) % range)
end

-- Returns true if |a - b| <= epsilon (default 1e-6)
function ArcMath.approximately(a, b, epsilon)
    return math.abs(a - b) <= (epsilon or 1e-6)
end

-- Snap v to the nearest multiple of gridSize
function ArcMath.snapToGrid(v, gridSize)
    if gridSize == 0 then return v end
    return math.floor(v / gridSize + 0.5) * gridSize
end

-- ── Easing ────────────────────────────────────────────────────────────────────
-- All functions: t in [0,1], returns value in [0,1].
-- f(0) == 0, f(1) == 1 (within floating-point tolerance).

ArcMath.ease = {}
local ease = ArcMath.ease

local PI   = math.pi
local sin  = math.sin
local cos  = math.cos
local sqrt = math.sqrt

function ease.linear(t)      return t                                          end

function ease.inQuad(t)      return t * t                                      end
function ease.outQuad(t)     return t * (2 - t)                                end
function ease.inOutQuad(t)
    return t < 0.5 and 2 * t * t or -1 + (4 - 2 * t) * t
end

function ease.inCubic(t)     return t * t * t                                  end
function ease.outCubic(t)    local u = t - 1; return u * u * u + 1             end
function ease.inOutCubic(t)
    return t < 0.5 and 4 * t * t * t or (t - 1) * (2 * t - 2) * (2 * t - 2) + 1
end

function ease.inQuart(t)     return t * t * t * t                              end
function ease.outQuart(t)    local u = t - 1; return 1 - u * u * u * u        end
function ease.inOutQuart(t)
    return t < 0.5 and 8 * t * t * t * t
        or 1 - 8 * (t-1) * (t-1) * (t-1) * (t-1)
end

function ease.inQuint(t)     return t * t * t * t * t                          end
function ease.outQuint(t)    local u = t - 1; return u * u * u * u * u + 1    end
function ease.inOutQuint(t)
    return t < 0.5 and 16 * t * t * t * t * t
        or 1 + 16 * (t-1) * (t-1) * (t-1) * (t-1) * (t-1)
end

function ease.inSine(t)      return 1 - cos(t * PI / 2)                       end
function ease.outSine(t)     return sin(t * PI / 2)                            end
function ease.inOutSine(t)   return -(cos(PI * t) - 1) / 2                    end

function ease.inExpo(t)
    return t == 0 and 0 or 2 ^ (10 * t - 10)
end
function ease.outExpo(t)
    return t == 1 and 1 or 1 - 2 ^ (-10 * t)
end
function ease.inOutExpo(t)
    if t == 0 then return 0 end
    if t == 1 then return 1 end
    if t < 0.5 then return 2 ^ (20 * t - 10) / 2
    else            return (2 - 2 ^ (-20 * t + 10)) / 2 end
end

function ease.inCirc(t)   return 1 - sqrt(1 - t * t)                          end
function ease.outCirc(t)  local u = t - 1; return sqrt(1 - u * u)             end
function ease.inOutCirc(t)
    if t < 0.5 then return (1 - sqrt(1 - 4 * t * t)) / 2
    else            return (sqrt(-(2 * t - 3) * (2 * t - 1)) + 1) / 2 end
end

local BACK_C1 = 1.70158
local BACK_C2 = BACK_C1 * 1.525
local BACK_C3 = BACK_C1 + 1
function ease.inBack(t)
    return BACK_C3 * t * t * t - BACK_C1 * t * t
end
function ease.outBack(t)
    local u = t - 1
    return 1 + BACK_C3 * u * u * u + BACK_C1 * u * u
end
function ease.inOutBack(t)
    if t < 0.5 then
        return ((2 * t) ^ 2 * ((BACK_C2 + 1) * 2 * t - BACK_C2)) / 2
    else
        local u = 2 * t - 2
        return (u ^ 2 * ((BACK_C2 + 1) * u + BACK_C2) + 2) / 2
    end
end

local ELASTIC_C4 = (2 * PI) / 3
local ELASTIC_C5 = (2 * PI) / 4.5
function ease.inElastic(t)
    if t == 0 then return 0 end
    if t == 1 then return 1 end
    return -(2 ^ (10 * t - 10)) * sin((t * 10 - 10.75) * ELASTIC_C4)
end
function ease.outElastic(t)
    if t == 0 then return 0 end
    if t == 1 then return 1 end
    return 2 ^ (-10 * t) * sin((t * 10 - 0.75) * ELASTIC_C4) + 1
end
function ease.inOutElastic(t)
    if t == 0 then return 0 end
    if t == 1 then return 1 end
    if t < 0.5 then
        return -(2 ^ (20 * t - 10) * sin((20 * t - 11.125) * ELASTIC_C5)) / 2
    else
        return  (2 ^ (-20 * t + 10) * sin((20 * t - 11.125) * ELASTIC_C5)) / 2 + 1
    end
end

local function bounceOut(t)
    local n1, d1 = 7.5625, 2.75
    if t < 1 / d1 then
        return n1 * t * t
    elseif t < 2 / d1 then
        t = t - 1.5 / d1;   return n1 * t * t + 0.75
    elseif t < 2.5 / d1 then
        t = t - 2.25 / d1;  return n1 * t * t + 0.9375
    else
        t = t - 2.625 / d1; return n1 * t * t + 0.984375
    end
end
function ease.inBounce(t)    return 1 - bounceOut(1 - t)                      end
function ease.outBounce(t)   return bounceOut(t)                               end
function ease.inOutBounce(t)
    return t < 0.5 and (1 - bounceOut(1 - 2 * t)) / 2
        or (1 + bounceOut(2 * t - 1)) / 2
end

-- ── Vector2 ───────────────────────────────────────────────────────────────────

ArcMath.v2 = {}
local v2 = ArcMath.v2

function v2.new(x, y)     return { x = x or 0, y = y or 0 }                   end
function v2.add(a, b)     return { x = a.x + b.x, y = a.y + b.y }            end
function v2.sub(a, b)     return { x = a.x - b.x, y = a.y - b.y }            end
function v2.scale(a, s)   return { x = a.x * s,   y = a.y * s   }            end
function v2.dot(a, b)     return a.x * b.x + a.y * b.y                        end
function v2.magnitude(a)  return sqrt(a.x * a.x + a.y * a.y)                  end
function v2.distance(a,b) return v2.magnitude(v2.sub(b, a))                   end

function v2.normalize(a)
    local m = v2.magnitude(a)
    if m == 0 then return { x = 0, y = 0 } end
    return { x = a.x / m, y = a.y / m }
end

function v2.lerp(a, b, t)
    return { x = ArcMath.lerp(a.x, b.x, t), y = ArcMath.lerp(a.y, b.y, t) }
end

-- True if both components are within eps of each other (default 1e-6)
function v2.equals(a, b, eps)
    return ArcMath.approximately(a.x, b.x, eps)
       and ArcMath.approximately(a.y, b.y, eps)
end

function v2.negate(a)    return { x = -a.x, y = -a.y }                        end
function v2.perpendicular(a) return { x = -a.y, y = a.x }                     end

-- ── Dev tests ─────────────────────────────────────────────────────────────────

if getgenv().AxiumDevMode then
    local AL = getgenv().AxiumLog
    local passed, failed_count = 0, 0

    local function pass(label)
        passed = passed + 1
        AL.info("Arc", "math", "test", "PASS  " .. label)
    end

    local function fail(label, got, expected)
        failed_count = failed_count + 1
        AL.error("Arc", "math", "test",
            string.format("FAIL  %s  |  got=%s  expected=%s",
                label, tostring(got), tostring(expected))
        )
    end

    -- eq: exact equality
    local function eq(label, got, expected)
        if got == expected then pass(label) else fail(label, got, expected) end
    end

    -- near: float comparison with tolerance
    local function near(label, got, expected, eps)
        eps = eps or 1e-5
        if math.abs(got - expected) <= eps then
            pass(label)
        else
            fail(label, string.format("%.8f", got), string.format("%.8f", expected))
        end
    end

    local function assertTrue(label, cond)
        if cond then pass(label) else fail(label, "false", "true") end
    end

    local function assertFalse(label, cond)
        if not cond then pass(label) else fail(label, "true", "false") end
    end

    -- Scalar tests
    near("lerp(0,10,0.5)=5",        ArcMath.lerp(0, 10, 0.5), 5)
    near("lerp(0,10,0)=0",          ArcMath.lerp(0, 10, 0), 0)
    near("lerp(0,10,1)=10",         ArcMath.lerp(0, 10, 1), 10)
    near("lerp extrapolate t=2",    ArcMath.lerp(0, 10, 2), 20)

    eq("clamp(5,0,10)=5",           ArcMath.clamp(5, 0, 10), 5)
    eq("clamp(-1,0,10)=0",          ArcMath.clamp(-1, 0, 10), 0)
    eq("clamp(11,0,10)=10",         ArcMath.clamp(11, 0, 10), 10)
    eq("clamp at min boundary",     ArcMath.clamp(0, 0, 10), 0)
    eq("clamp at max boundary",     ArcMath.clamp(10, 0, 10), 10)

    near("round(3.456,2)=3.46",     ArcMath.round(3.456, 2), 3.46)
    near("round(3.5,0)=4",          ArcMath.round(3.5, 0), 4)
    near("round(3.4,0)=3",          ArcMath.round(3.4, 0), 3)
    near("round(0.0049,3)=0.005",   ArcMath.round(0.0049, 3), 0.005)

    near("map(5,0,10,0,100)=50",    ArcMath.map(5, 0, 10, 0, 100), 50)
    near("map(0,0,10,0,100)=0",     ArcMath.map(0, 0, 10, 0, 100), 0)
    near("map(10,0,10,0,100)=100",  ArcMath.map(10, 0, 10, 0, 100), 100)
    near("map negative range",      ArcMath.map(5, 0, 10, 100, 0), 50)

    eq("sign(5)=1",   ArcMath.sign(5), 1)
    eq("sign(-3)=-1", ArcMath.sign(-3), -1)
    eq("sign(0)=0",   ArcMath.sign(0), 0)

    near("wrap(11,0,10)=1",         ArcMath.wrap(11, 0, 10), 1)
    near("wrap(0,0,10)=0",          ArcMath.wrap(0, 0, 10), 0)
    near("wrap(10,0,10)=0",         ArcMath.wrap(10, 0, 10), 0)
    near("wrap(-1,0,10)=9",         ArcMath.wrap(-1, 0, 10), 9)

    assertTrue("approximately(1+1e-7, 1)",          ArcMath.approximately(1 + 1e-7, 1))
    assertFalse("not approximately(1, 2)",          ArcMath.approximately(1, 2))
    assertTrue("approximately custom eps",          ArcMath.approximately(1.4, 1, 0.5))

    near("snapToGrid(7,5)=5",   ArcMath.snapToGrid(7, 5), 5)
    near("snapToGrid(8,5)=10",  ArcMath.snapToGrid(8, 5), 10)
    near("snapToGrid(5,5)=5",   ArcMath.snapToGrid(5, 5), 5)
    near("snapToGrid(0,5)=0",   ArcMath.snapToGrid(0, 5), 0)
    near("snapToGrid(v,0)=v",   ArcMath.snapToGrid(7, 0), 7)

    -- Easing boundary tests: f(0)=0, f(1)=1 for all standard easings
    local easingNames = {
        "linear",
        "inQuad",   "outQuad",   "inOutQuad",
        "inCubic",  "outCubic",  "inOutCubic",
        "inQuart",  "outQuart",  "inOutQuart",
        "inQuint",  "outQuint",  "inOutQuint",
        "inSine",   "outSine",   "inOutSine",
        "inExpo",   "outExpo",   "inOutExpo",
        "inCirc",   "outCirc",
        "inBack",   "outBack",
        "inElastic","outElastic",
        "inBounce", "outBounce", "inOutBounce",
    }
    for _, name in ipairs(easingNames) do
        near("ease." .. name .. "(0)=0", ease[name](0), 0, 1e-5)
        near("ease." .. name .. "(1)=1", ease[name](1), 1, 1e-5)
        -- Midpoint must be in [0,1] range (sanity check)
        local mid = ease[name](0.5)
        assertTrue("ease." .. name .. "(0.5) in range",
            mid >= -0.5 and mid <= 1.5  -- back/elastic may overshoot slightly
        )
    end

    -- inOutCirc only defined for t<0.5 on left branch — test both halves
    near("ease.inOutCirc(0)=0",   ease.inOutCirc(0), 0, 1e-5)
    near("ease.inOutCirc(1)=1",   ease.inOutCirc(1), 1, 1e-5)
    near("ease.inOutCirc(0.5)=0.5", ease.inOutCirc(0.5), 0.5, 1e-3)

    -- inOutBack, inOutElastic boundary
    near("ease.inOutBack(0)=0",     ease.inOutBack(0), 0, 1e-5)
    near("ease.inOutBack(1)=1",     ease.inOutBack(1), 1, 1e-5)
    near("ease.inOutElastic(0)=0",  ease.inOutElastic(0), 0, 1e-5)
    near("ease.inOutElastic(1)=1",  ease.inOutElastic(1), 1, 1e-5)
    near("ease.inOutBounce(0)=0",   ease.inOutBounce(0), 0, 1e-5)
    near("ease.inOutBounce(1)=1",   ease.inOutBounce(1), 1, 1e-5)

    -- Vector2 tests
    local va = v2.new(3, 4)
    local vb = v2.new(1, 2)
    local zo = v2.new(0, 0)

    near("v2.magnitude({3,4})=5",       v2.magnitude(va), 5)
    near("v2.distance({3,4},{0,0})=5",  v2.distance(va, zo), 5)

    local norm = v2.normalize(va)
    near("v2.normalize x=0.6",  norm.x, 0.6, 1e-6)
    near("v2.normalize y=0.8",  norm.y, 0.8, 1e-6)

    local normZero = v2.normalize(zo)
    near("v2.normalize zero x=0", normZero.x, 0)
    near("v2.normalize zero y=0", normZero.y, 0)

    local added = v2.add(va, vb)
    near("v2.add x=4", added.x, 4)
    near("v2.add y=6", added.y, 6)

    local subbed = v2.sub(va, vb)
    near("v2.sub x=2", subbed.x, 2)
    near("v2.sub y=2", subbed.y, 2)

    local scaled = v2.scale(va, 2)
    near("v2.scale x=6", scaled.x, 6)
    near("v2.scale y=8", scaled.y, 8)

    near("v2.dot perpendicular=0",  v2.dot(v2.new(1,0), v2.new(0,1)), 0)
    near("v2.dot parallel={1,0}",   v2.dot(v2.new(1,0), v2.new(1,0)), 1)
    near("v2.dot({3,4},{3,4})=25",  v2.dot(va, va), 25)

    local lerped = v2.lerp(zo, v2.new(10, 20), 0.5)
    near("v2.lerp x=5",  lerped.x, 5)
    near("v2.lerp y=10", lerped.y, 10)

    assertTrue("v2.equals same",         v2.equals(va, v2.new(3, 4)))
    assertFalse("v2.equals different",   v2.equals(va, vb))

    local neg = v2.negate(va)
    near("v2.negate x=-3", neg.x, -3)
    near("v2.negate y=-4", neg.y, -4)

    local perp = v2.perpendicular(v2.new(1, 0))
    near("v2.perpendicular x=0",  perp.x, 0)
    near("v2.perpendicular y=1",  perp.y, 1)

    -- Summary
    AL.info("Arc", "math", "tests", string.format(
        "Suite complete — %d passed, %d failed", passed, failed_count
    ))
    if failed_count > 0 then
        AL.critical("Arc", "math", "tests", string.format(
            "%d test(s) FAILED in Arc.math", failed_count
        ))
    end
end

-- ── Registration ──────────────────────────────────────────────────────────────

local env = getgenv()
env._Axium      = env._Axium or {}
env._Axium.Arc  = env._Axium.Arc or {}
env._Axium.Arc.math = ArcMath

if env.AxiumLoader then
    env.AxiumLoader.load("Arc.math", function()
        -- Module already registered above; this call is for loader tracking only.
    end)
end

return ArcMath
