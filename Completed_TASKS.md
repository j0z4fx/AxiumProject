# Axium — Completed Tasks

Tasks are moved here from `TASKS.md` only after explicit user confirmation of completion.

---

## Phase 1 — Arc

- [x] **T-007** `Axium/src/scripts/diagnostics.lua` -- Rolling buffer (2000), severity levels, structured entries w/ stack trace, dedup cooldown, clipboard on error/critical, console+overlay hooks, loader log migration, AxiumLog shim. All tests passed.
- [x] **T-006.5** `Arc/DOCS.md` — Full API reference for all 5 Arc submodules + top-level aliases.
- [x] **T-006** `Arc/src/init.lua` — Unified Arc namespace, submodule validation, top-level aliases, env.Arc global.
- [x] **T-005** `Arc/src/signals.lua` — VoltSignal wrappers: new, once, filtered, mapped, debounced, bridge, await, ConnectionGroup.
- [x] **T-004** `Arc/src/transforms.lua` — Rect ops, anchor resolution, viewport scaling (fit/fill/width/height), padding box-model, lerpRect/lerpPoint. All tests passed.
- [x] **T-003** `Arc/src/cache.lua` — KeyedCache (TTL), LRUCache (O(1) DLL+hashmap), ObjectPool. All tests passed.
- [x] **T-002** `Arc/src/utils.lua` — Type checking, table ops, string helpers, deepCopy (circular-safe), UUID v4, once/memoize/debounce. All tests passed.
- [x] **T-001** `Arc/src/math.lua` — lerp, clamp, round, map, sign, wrap, approximately, snapToGrid; 20 easing curves (quad/cubic/quart/quint/sine/expo/circ/back/elastic/bounce in/out/inOut); Vector2 ops (new/add/sub/scale/dot/magnitude/normalize/distance/lerp/equals/negate/perpendicular). 148/148 tests passed.
