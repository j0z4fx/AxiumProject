--[[
    Arc/src/transforms.lua
    Transform utilities for UI layout: position, size, anchor resolution,
    viewport scaling, rect operations, and coordinate space conversions.
    Depends on Arc.math (accessed via getgenv()._Axium.Arc.math).
]]

local Math = getgenv()._Axium and getgenv()._Axium.Arc and getgenv()._Axium.Arc.math
assert(Math, "Arc.transforms requires Arc.math to be loaded first")

local ArcTransforms = {}

-- -- Rect ----------------------------------------------------------------------
-- Rect: { x, y, w, h }  -- top-left origin, width/height extents

-- Creates a new rect
function ArcTransforms.rect(x, y, w, h)
    return { x = x or 0, y = y or 0, w = w or 0, h = h or 0 }
end

-- Returns rect right edge (x + w)
function ArcTransforms.rectRight(r)  return r.x + r.w end

-- Returns rect bottom edge (y + h)
function ArcTransforms.rectBottom(r) return r.y + r.h end

-- Returns center point { x, y } of rect
function ArcTransforms.rectCenter(r)
    return { x = r.x + r.w * 0.5, y = r.y + r.h * 0.5 }
end

-- Returns true if point {x,y} is inside rect (inclusive edges)
function ArcTransforms.rectContainsPoint(r, px, py)
    return px >= r.x and px <= r.x + r.w
       and py >= r.y and py <= r.y + r.h
end

-- Returns true if two rects overlap (inclusive edges)
function ArcTransforms.rectIntersects(a, b)
    return a.x <= b.x + b.w and a.x + a.w >= b.x
       and a.y <= b.y + b.h and a.y + a.h >= b.y
end

-- Returns the intersection rect, or nil if no overlap
function ArcTransforms.rectIntersection(a, b)
    local x1 = math.max(a.x, b.x)
    local y1 = math.max(a.y, b.y)
    local x2 = math.min(a.x + a.w, b.x + b.w)
    local y2 = math.min(a.y + a.h, b.y + b.h)
    if x2 < x1 or y2 < y1 then return nil end
    return ArcTransforms.rect(x1, y1, x2 - x1, y2 - y1)
end

-- Returns the bounding rect that contains both a and b
function ArcTransforms.rectUnion(a, b)
    local x1 = math.min(a.x, b.x)
    local y1 = math.min(a.y, b.y)
    local x2 = math.max(a.x + a.w, b.x + b.w)
    local y2 = math.max(a.y + a.h, b.y + b.h)
    return ArcTransforms.rect(x1, y1, x2 - x1, y2 - y1)
end

-- Expands rect by amount on all sides (negative shrinks)
function ArcTransforms.rectInset(r, amount)
    return ArcTransforms.rect(
        r.x + amount,  r.y + amount,
        r.w - amount * 2, r.h - amount * 2
    )
end

-- Returns a rect offset by dx, dy
function ArcTransforms.rectOffset(r, dx, dy)
    return ArcTransforms.rect(r.x + dx, r.y + dy, r.w, r.h)
end

-- Clamps rect so it stays within bounds rect; preserves size
function ArcTransforms.rectClampInside(r, bounds)
    local x = Math.clamp(r.x, bounds.x, bounds.x + bounds.w - r.w)
    local y = Math.clamp(r.y, bounds.y, bounds.y + bounds.h - r.h)
    return ArcTransforms.rect(x, y, r.w, r.h)
end

-- -- Anchor --------------------------------------------------------------------
-- Anchor: { x, y } in [0,1] space -- (0,0)=top-left, (0.5,0.5)=center, (1,1)=bottom-right

-- Resolves an anchored position to an absolute top-left {x, y}
-- anchorPos : { x, y } -- where the anchor point sits in parent space (absolute pixels)
-- size      : { x, y } -- width/height of the element
-- anchor    : { x, y } -- normalised anchor point within the element
function ArcTransforms.resolveAnchor(anchorPos, size, anchor)
    return {
        x = anchorPos.x - size.x * anchor.x,
        y = anchorPos.y - size.y * anchor.y,
    }
end

-- Resolves the anchor point position (in absolute pixels) from a top-left position
function ArcTransforms.anchorPoint(pos, size, anchor)
    return {
        x = pos.x + size.x * anchor.x,
        y = pos.y + size.y * anchor.y,
    }
end

-- Common anchor presets
ArcTransforms.Anchor = {
    TopLeft      = { x = 0,   y = 0   },
    TopCenter    = { x = 0.5, y = 0   },
    TopRight     = { x = 1,   y = 0   },
    MiddleLeft   = { x = 0,   y = 0.5 },
    Center       = { x = 0.5, y = 0.5 },
    MiddleRight  = { x = 1,   y = 0.5 },
    BottomLeft   = { x = 0,   y = 1   },
    BottomCenter = { x = 0.5, y = 1   },
    BottomRight  = { x = 1,   y = 1   },
}

-- -- Viewport scaling ----------------------------------------------------------

--[[
    Computes a uniform scale factor to fit designSize inside viewportSize.
    mode:
      "fit"    -- scale down to fit entirely (letterbox); default
      "fill"   -- scale up to fill entirely (may crop)
      "width"  -- match width only
      "height" -- match height only
    Returns a single scale number.
]]
function ArcTransforms.viewportScale(designSize, viewportSize, mode)
    local sx = viewportSize.x / designSize.x
    local sy = viewportSize.y / designSize.y
    mode = mode or "fit"
    if mode == "fit"    then return math.min(sx, sy) end
    if mode == "fill"   then return math.max(sx, sy) end
    if mode == "width"  then return sx end
    if mode == "height" then return sy end
    error("Arc.transforms.viewportScale: unknown mode '" .. tostring(mode) .. "'")
end

--[[
    Returns the offset {x,y} needed to centre designSize (after scaling)
    within viewportSize.
]]
function ArcTransforms.viewportOffset(designSize, viewportSize, scale)
    return {
        x = (viewportSize.x - designSize.x * scale) * 0.5,
        y = (viewportSize.y - designSize.y * scale) * 0.5,
    }
end

-- Converts a point from design space to viewport space given scale and offset
function ArcTransforms.designToViewport(point, scale, offset)
    return {
        x = point.x * scale + offset.x,
        y = point.y * scale + offset.y,
    }
end

-- Converts a point from viewport space back to design space
function ArcTransforms.viewportToDesign(point, scale, offset)
    return {
        x = (point.x - offset.x) / scale,
        y = (point.y - offset.y) / scale,
    }
end

-- -- Padding / margin ----------------------------------------------------------
-- Padding/margin: { top, right, bottom, left }  (CSS box-model order)

function ArcTransforms.padding(top, right, bottom, left)
    return { top = top or 0, right = right or top or 0,
             bottom = bottom or top or 0, left = left or right or top or 0 }
end

-- Returns content rect after applying padding to outer rect
function ArcTransforms.applyPadding(r, pad)
    return ArcTransforms.rect(
        r.x + pad.left,
        r.y + pad.top,
        r.w - pad.left - pad.right,
        r.h - pad.top  - pad.bottom
    )
end

-- Returns outer rect that contains content rect with padding applied
function ArcTransforms.removePadding(r, pad)
    return ArcTransforms.rect(
        r.x - pad.left,
        r.y - pad.top,
        r.w + pad.left + pad.right,
        r.h + pad.top  + pad.bottom
    )
end

-- -- Lerp helpers --------------------------------------------------------------

-- Lerps two rects component-wise
function ArcTransforms.lerpRect(a, b, t)
    return ArcTransforms.rect(
        Math.lerp(a.x, b.x, t), Math.lerp(a.y, b.y, t),
        Math.lerp(a.w, b.w, t), Math.lerp(a.h, b.h, t)
    )
end

-- Lerps two {x,y} points
function ArcTransforms.lerpPoint(a, b, t)
    return { x = Math.lerp(a.x, b.x, t), y = Math.lerp(a.y, b.y, t) }
end

-- -- Dev tests -----------------------------------------------------------------

if getgenv().AxiumDevMode then
    local AL = getgenv().AxiumLog
    local passed, failed_count = 0, 0
    local AT = ArcTransforms

    local function pass(label)
        passed = passed + 1
        AL.info("Arc", "transforms", "test", "PASS  " .. label)
    end

    local function fail(label, got, expected)
        failed_count = failed_count + 1
        AL.error("Arc", "transforms", "test",
            string.format("FAIL  %s  |  got=%s  expected=%s",
                label, tostring(got), tostring(expected))
        )
    end

    local function near(label, got, expected, eps)
        eps = eps or 1e-5
        if math.abs(got - expected) <= eps then
            pass(label)
        else
            fail(label, string.format("%.6f", got), string.format("%.6f", expected))
        end
    end

    local function assertTrue(label, v)
        if v then pass(label) else fail(label, tostring(v), "true") end
    end

    local function assertFalse(label, v)
        if not v then pass(label) else fail(label, tostring(v), "false") end
    end

    local function assertNil(label, v)
        if v == nil then pass(label) else fail(label, tostring(v), "nil") end
    end

    -- Rect basics
    local r = AT.rect(10, 20, 100, 50)
    near("rectRight",  AT.rectRight(r),  110)
    near("rectBottom", AT.rectBottom(r), 70)
    local c = AT.rectCenter(r)
    near("rectCenter x", c.x, 60)
    near("rectCenter y", c.y, 45)

    assertTrue("rectContainsPoint inside",  AT.rectContainsPoint(r, 50, 40))
    assertTrue("rectContainsPoint edge",    AT.rectContainsPoint(r, 10, 20))
    assertFalse("rectContainsPoint outside",AT.rectContainsPoint(r, 0, 0))

    local r2 = AT.rect(50, 40, 100, 50)
    assertTrue("rectIntersects overlap",    AT.rectIntersects(r, r2))
    local r3 = AT.rect(200, 200, 10, 10)
    assertFalse("rectIntersects no overlap",AT.rectIntersects(r, r3))

    local ix = AT.rectIntersection(r, r2)
    assertTrue("rectIntersection not nil", ix ~= nil)
    near("rectIntersection x", ix.x, 50)
    near("rectIntersection y", ix.y, 40)
    near("rectIntersection w", ix.w, 60)
    near("rectIntersection h", ix.h, 30)

    assertNil("rectIntersection nil on no overlap", AT.rectIntersection(r, r3))

    local u = AT.rectUnion(r, r2)
    near("rectUnion x", u.x, 10)
    near("rectUnion y", u.y, 20)
    near("rectUnion w", u.w, 140)
    near("rectUnion h", u.h, 70)

    local ins = AT.rectInset(r, 5)
    near("rectInset x", ins.x, 15)
    near("rectInset y", ins.y, 25)
    near("rectInset w", ins.w, 90)
    near("rectInset h", ins.h, 40)

    local off = AT.rectOffset(r, 10, -5)
    near("rectOffset x", off.x, 20)
    near("rectOffset y", off.y, 15)

    local bounds = AT.rect(0, 0, 200, 200)
    local big    = AT.rect(150, 150, 100, 100)
    local clamped = AT.rectClampInside(big, bounds)
    near("rectClampInside x", clamped.x, 100)
    near("rectClampInside y", clamped.y, 100)

    -- Anchor
    local pos  = { x = 100, y = 100 }
    local size = { x = 80, y = 40 }
    local anc  = AT.Anchor.Center
    local tl   = AT.resolveAnchor(pos, size, anc)
    near("resolveAnchor center x", tl.x, 60)
    near("resolveAnchor center y", tl.y, 80)

    local ap = AT.anchorPoint({x=60,y=80}, size, anc)
    near("anchorPoint x", ap.x, 100)
    near("anchorPoint y", ap.y, 100)

    local tlAnchor = AT.resolveAnchor(pos, size, AT.Anchor.TopLeft)
    near("resolveAnchor TopLeft x", tlAnchor.x, 100)
    near("resolveAnchor TopLeft y", tlAnchor.y, 100)

    -- Viewport scaling
    local design   = { x = 1280, y = 720 }
    local viewport = { x = 1920, y = 1080 }
    local scaleFit = AT.viewportScale(design, viewport, "fit")
    near("viewportScale fit", scaleFit, 1.5)

    local viewport2 = { x = 1920, y = 800 }
    local scaleFit2 = AT.viewportScale(design, viewport2, "fit")
    near("viewportScale fit narrow", scaleFit2, 800/720, 1e-5)

    local scaleFill = AT.viewportScale(design, viewport2, "fill")
    near("viewportScale fill", scaleFill, 1920/1280, 1e-5)

    local ofs = AT.viewportOffset(design, viewport, scaleFit)
    near("viewportOffset x", ofs.x, 0)
    near("viewportOffset y", ofs.y, 0)

    local p = AT.designToViewport({x=640, y=360}, scaleFit, {x=0,y=0})
    near("designToViewport x", p.x, 960)
    near("designToViewport y", p.y, 540)

    local back = AT.viewportToDesign(p, scaleFit, {x=0,y=0})
    near("viewportToDesign x", back.x, 640)
    near("viewportToDesign y", back.y, 360)

    -- Padding
    local pad = AT.padding(10, 20, 10, 20)
    local content = AT.applyPadding(AT.rect(0,0,200,100), pad)
    near("applyPadding x", content.x, 20)
    near("applyPadding y", content.y, 10)
    near("applyPadding w", content.w, 160)
    near("applyPadding h", content.h, 80)

    local outer = AT.removePadding(content, pad)
    near("removePadding x", outer.x, 0)
    near("removePadding y", outer.y, 0)
    near("removePadding w", outer.w, 200)
    near("removePadding h", outer.h, 100)

    -- Uniform padding shorthand
    local padUniform = AT.padding(5)
    near("padding uniform top",   padUniform.top,    5)
    near("padding uniform right", padUniform.right,  5)
    near("padding uniform left",  padUniform.left,   5)

    -- Lerp
    local ra = AT.rect(0,0,100,50)
    local rb = AT.rect(100,100,200,100)
    local rl = AT.lerpRect(ra, rb, 0.5)
    near("lerpRect x", rl.x, 50)
    near("lerpRect y", rl.y, 50)
    near("lerpRect w", rl.w, 150)
    near("lerpRect h", rl.h, 75)

    local pa = {x=0, y=0}
    local pb = {x=10, y=20}
    local pl = AT.lerpPoint(pa, pb, 0.5)
    near("lerpPoint x", pl.x, 5)
    near("lerpPoint y", pl.y, 10)

    -- Summary
    AL.info("Arc", "transforms", "tests", string.format(
        "Suite complete -- %d passed, %d failed", passed, failed_count
    ))
    if failed_count > 0 then
        AL.critical("Arc", "transforms", "tests", string.format(
            "%d test(s) FAILED in Arc.transforms", failed_count
        ))
    end
end

-- -- Registration --------------------------------------------------------------

local env = getgenv()
env._Axium                = env._Axium or {}
env._Axium.Arc            = env._Axium.Arc or {}
env._Axium.Arc.transforms = ArcTransforms

if env.AxiumLoader then
    env.AxiumLoader.load("Arc.transforms", function() end)
end

return ArcTransforms
