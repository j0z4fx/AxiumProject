# Axium — Completed Tasks

Tasks are moved here from `TASKS.md` only after explicit user confirmation of completion.

---

## Phase 3 — Veil

- [x] **T-012** `Veil/src/init.lua` — Assembles Veil; ServiceIsolation/cloneref, Protection/protectgui, Hooks/newcclosure, Env/isolated loadstring, Scanner/getgc; _hardenMeta on all class metatables; mutation lock; publishes env.Veil. 14/14 tests.
- [x] **T-011** `Veil/src/api_wrap.lua` — API wrapper: baked-tier gatekeeper check, Validator arg schemas, raw-render EXTERNAL block, anti-tamper fn-ref check, newcclosure hardening, wrapTable helper. 9/9 tests.
- [x] **T-010** `Veil/src/gatekeeper.lua` — Three-tier permission system (INTERNAL/DEV_TOOLS/EXTERNAL), action registry with built-in Axium registrations, denied-action audit log. 11/11 tests.
- [x] **T-009** `Veil/src/signal_filter.lua` — VoltSignal payload validation, origin whitelisting, blocked-signal audit log, hitCount tracking. 7/7 tests.
- [x] **T-008** `Veil/src/validator.lua` — Schema-driven type/range/pattern/fields/elements/custom validation, sanitize (clamp/trim), origin check via debug stack. 26/26 tests.

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
