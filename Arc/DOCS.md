# Arc — Documentation

Arc is the pure utility layer for Axium. No Axium runtime dependencies.
All submodules are accessible via the unified `Arc` global after `Arc/src/init.lua` loads.

Load order: `math` → `utils` → `cache` → `transforms` → `signals` → `init`

---

## Arc.math

Scalar helpers, easing curves, and Vector2 operations.

### Scalar

| Function | Signature | Description |
|----------|-----------|-------------|
| `lerp` | `lerp(a, b, t) -> number` | Linear interpolation |
| `clamp` | `clamp(n, min, max) -> number` | Clamp to range |
| `round` | `round(n, decimals?) -> number` | Round to decimal places (default 0) |
| `map` | `map(v, inMin, inMax, outMin, outMax) -> number` | Remap value between ranges |
| `sign` | `sign(n) -> -1|0|1` | Sign of n |
| `wrap` | `wrap(n, min, max) -> number` | Modular wrap within [min, max) |
| `approximately` | `approximately(a, b, epsilon?) -> bool` | Float equality within epsilon (default 1e-6) |
| `snapToGrid` | `snapToGrid(v, gridSize) -> number` | Snap to nearest grid multiple |

### Easing

All functions accept `t ∈ [0,1]` and return a value in `[0,1]` (back/elastic may overshoot).

`Arc.ease.linear` · `inQuad` · `outQuad` · `inOutQuad` · `inCubic` · `outCubic` · `inOutCubic` · `inQuart` · `outQuart` · `inOutQuart` · `inQuint` · `outQuint` · `inOutQuint` · `inSine` · `outSine` · `inOutSine` · `inExpo` · `outExpo` · `inOutExpo` · `inCirc` · `outCirc` · `inOutCirc` · `inBack` · `outBack` · `inOutBack` · `inElastic` · `outElastic` · `inOutElastic` · `inBounce` · `outBounce` · `inOutBounce`

### Vector2 (`Arc.math.v2`)

Vector tables are plain `{ x, y }` — no metatables.

| Function | Description |
|----------|-------------|
| `v2.new(x, y)` | Create vector |
| `v2.add(a, b)` | Component-wise add |
| `v2.sub(a, b)` | Component-wise subtract |
| `v2.scale(a, s)` | Multiply by scalar |
| `v2.dot(a, b)` | Dot product |
| `v2.magnitude(a)` | Length |
| `v2.normalize(a)` | Unit vector (zero-safe) |
| `v2.distance(a, b)` | Euclidean distance |
| `v2.lerp(a, b, t)` | Component-wise lerp |
| `v2.equals(a, b, eps?)` | Approximate equality |
| `v2.negate(a)` | Negate both components |
| `v2.perpendicular(a)` | 90° CCW rotation |

---

## Arc.utils

Type checking, table operations, string helpers, UUID, functional utilities.

### Type checking

| Function | Returns |
|----------|---------|
| `isString(v)` | bool |
| `isNumber(v)` | bool |
| `isBoolean(v)` | bool |
| `isTable(v)` | bool |
| `isFunction(v)` | bool |
| `isNil(v)` | bool |
| `isNonEmptyString(v)` | bool |
| `isFiniteNumber(v)` | bool — false for NaN and ±inf |
| `isInteger(v)` | bool |
| `isArray(t)` | bool — true only if sequential integer keys from 1 |
| `assertType(v, expected, argName?)` | throws on mismatch |

### Table operations

| Function | Description |
|----------|-------------|
| `shallowCopy(t)` | Top-level key copy |
| `deepCopy(t)` | Recursive copy, handles circular refs |
| `merge(dst, src)` | Merge src into dst in-place (src wins) |
| `assign(a, b)` | New table: a merged with b (b wins) |
| `keys(t)` | Array of all keys |
| `values(t)` | Array of all values |
| `contains(t, v)` | True if value present |
| `indexOf(t, v)` | First index of v or nil |
| `count(t)` | Entry count (works on non-sequential tables) |
| `isEmpty(t)` | True if no entries |
| `removeValue(t, v)` | Remove first occurrence, return index or nil |
| `filter(t, pred)` | New array of elements where pred(v) is true |
| `map(t, fn)` | New array with fn(v, i) applied |
| `reduce(t, fn, init)` | Fold to single value |
| `concat(...)` | Flatten multiple arrays into one |

### String helpers

| Function | Description |
|----------|-------------|
| `trim(s)` | Strip leading/trailing whitespace |
| `split(s, sep)` | Split on separator (default whitespace) |
| `startsWith(s, prefix)` | Prefix check |
| `endsWith(s, suffix)` | Suffix check |
| `padLeft(s, n, char?)` | Left-pad to width n (default `" "`) |
| `padRight(s, n, char?)` | Right-pad to width n |
| `rep(s, n)` | Repeat string n times |
| `stringify(v, depth?)` | Compact human-readable string (max depth 3) |

### UUID & functional

| Function | Description |
|----------|-------------|
| `uuid()` | Pseudo-random UUID v4 string |
| `once(fn)` | Wraps fn; only executes on first call, caches result |
| `memoize(fn)` | Caches result by first argument |
| `debounce(fn, delay, schedFn)` | Fires fn after `delay` seconds of silence |

---

## Arc.cache

### KeyedCache

```lua
local kc = Arc.cache.newKeyedCache(defaultTTL?)
```

| Method | Description |
|--------|-------------|
| `kc:set(key, value, ttl?)` | Store value; ttl overrides default |
| `kc:get(key)` | Retrieve or nil if expired/missing |
| `kc:has(key)` | Existence check |
| `kc:delete(key)` | Remove entry |
| `kc:purgeExpired()` | Remove all expired entries, returns count |
| `kc:clear()` | Remove all entries |
| `kc:stats()` | `{ size, hits, misses, hitRate }` |

### LRUCache

```lua
local lru = Arc.cache.newLRUCache(capacity)
```

O(1) get/set via doubly-linked list + hashmap. Evicts least-recently-used on overflow.

| Method | Description |
|--------|-------------|
| `lru:get(key)` | Retrieve and promote to MRU, or nil |
| `lru:set(key, value)` | Store and promote; evicts LRU if full |
| `lru:has(key)` | Existence check (no promotion) |
| `lru:delete(key)` | Remove entry |
| `lru:clear()` | Remove all entries |
| `lru:keys()` | Ordered array MRU→LRU |
| `lru:stats()` | `{ size, capacity, hits, misses, evictions, hitRate }` |

### ObjectPool

```lua
local pool = Arc.cache.newObjectPool(createFn, resetFn, maxSize?)
```

| Method | Description |
|--------|-------------|
| `pool:acquire()` | Get object (reuses pooled or calls createFn) |
| `pool:release(obj)` | Return object (discards if at maxSize) |
| `pool:clear()` | Discard all idle objects |
| `pool:available()` | Count of idle objects in pool |
| `pool:stats()` | `{ available, acquired, released, created, maxSize }` |

---

## Arc.transforms

UI layout math. All positions/sizes are plain `{ x, y }` tables. Rects are `{ x, y, w, h }`.

### Rect

| Function | Description |
|----------|-------------|
| `rect(x, y, w, h)` | Create rect |
| `rectRight(r)` | x + w |
| `rectBottom(r)` | y + h |
| `rectCenter(r)` | `{ x, y }` center point |
| `rectContainsPoint(r, px, py)` | Point-in-rect test |
| `rectIntersects(a, b)` | Overlap test |
| `rectIntersection(a, b)` | Intersection rect or nil |
| `rectUnion(a, b)` | Bounding rect of both |
| `rectInset(r, amount)` | Expand (positive) or shrink (negative) on all sides |
| `rectOffset(r, dx, dy)` | Translate rect |
| `rectClampInside(r, bounds)` | Clamp position within bounds, preserve size |

### Anchor

| Function | Description |
|----------|-------------|
| `resolveAnchor(anchorPos, size, anchor)` | Anchor pos + size + anchor → top-left `{x,y}` |
| `anchorPoint(pos, size, anchor)` | Top-left pos → anchor point `{x,y}` |

**Presets** (`Arc.Anchor.*`): `TopLeft` · `TopCenter` · `TopRight` · `MiddleLeft` · `Center` · `MiddleRight` · `BottomLeft` · `BottomCenter` · `BottomRight`

### Viewport scaling

| Function | Description |
|----------|-------------|
| `viewportScale(designSize, viewportSize, mode?)` | Scale factor; mode: `"fit"` (default) · `"fill"` · `"width"` · `"height"` |
| `viewportOffset(designSize, viewportSize, scale)` | Centering offset `{x,y}` |
| `designToViewport(point, scale, offset)` | Design space → screen space |
| `viewportToDesign(point, scale, offset)` | Screen space → design space |

### Padding

```lua
local pad = Arc.transforms.padding(top, right?, bottom?, left?)
```

CSS box-model shorthand: single value fills all sides, two values = top/right mirror to bottom/left.

| Function | Description |
|----------|-------------|
| `applyPadding(r, pad)` | Outer rect → content rect |
| `removePadding(r, pad)` | Content rect → outer rect |

### Lerp

| Function | Description |
|----------|-------------|
| `lerpRect(a, b, t)` | Component-wise rect lerp |
| `lerpPoint(a, b, t)` | `{x,y}` lerp |

---

## Arc.signals

VoltSignal convenience wrappers. VoltSignal is a Volt executor built-in.

| Function | Description |
|----------|-------------|
| `Arc.signals.new()` | Safe VoltSignal factory (guards against missing VoltSignal) |
| `Arc.signals.once(signal, handler)` | Auto-disconnect after first fire |
| `Arc.signals.filtered(signal, predicate, handler)` | Only fires when predicate returns true |
| `Arc.signals.mapped(signal, mapFn, handler)` | Transform payload before handler |
| `Arc.signals.debounced(signal, delay, schedFn, handler)` | Fires after signal quiet for `delay` seconds |
| `Arc.signals.bridge(source, target)` | Forward source fires to target signal |
| `Arc.signals.await(signal)` | Yield until signal fires, return payload |

### ConnectionGroup

```lua
local grp = Arc.signals.newGroup()   -- or Arc.newGroup()
```

| Method | Description |
|--------|-------------|
| `grp:connect(signal, handler)` | Connect and track; returns VoltConnection |
| `grp:disconnectAll()` | Disconnect all tracked connections |
| `grp:count()` | Number of active connections |

---

## Top-level aliases on `Arc`

These are available directly on the `Arc` global for convenience:

```
Arc.lerp        → Arc.math.lerp
Arc.clamp       → Arc.math.clamp
Arc.round       → Arc.math.round
Arc.map         → Arc.math.map
Arc.ease        → Arc.math.ease
Arc.v2          → Arc.math.v2
Arc.deepCopy    → Arc.utils.deepCopy
Arc.shallowCopy → Arc.utils.shallowCopy
Arc.uuid        → Arc.utils.uuid
Arc.stringify   → Arc.utils.stringify
Arc.rect        → Arc.transforms.rect
Arc.Anchor      → Arc.transforms.Anchor
Arc.newGroup    → Arc.signals.newGroup
Arc.once        → Arc.signals.once
```
