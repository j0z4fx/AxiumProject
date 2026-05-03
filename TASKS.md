# Axium — Task Queue

## ⚠️ Workflow Rules (Mandatory)

- **NEVER start the next task before the current one is explicitly marked complete by the user.**
- **NEVER assume a task is complete.** Only the user can confirm completion.
- When a task is confirmed complete: remove it from this file and add it to `Completed_TASKS.md`.
- Tasks must be executed in order. No skipping, no parallelizing without explicit approval.
- Each task maps to one file or one coherent system feature. Scope does not expand without user approval.

---

## Build Order Rationale

Dependency chain drives order:
> Arc (pure utils) → Diagnostics Core → Veil (security, needed by everything) → Axium Core (runtime, registry) → Pulse (loader, wires all modules) → Lattice (UI behavior) → Controls (primitive → composite → container) → System Features → Dev Tooling & Harness

---

## Phase 1 — Arc: Pure Utility Layer
> No Axium dependencies. Safe to build in isolation. All other modules consume Arc.

---

## Phase 2 — Diagnostics Core
> Cross-cutting. Built early so every subsequent module integrates it from the start.

---

## Phase 3 — Veil: Security & Execution Control
> Must be fully operational before any other module is initialized. All API calls route through Veil.

- [ ] **T-008** `Veil/src/validator.lua` — Input/payload type validation, argument sanitization, origin checks, schema enforcement
- [ ] **T-009** `Veil/src/signal_filter.lua` — VoltSignal payload validation, origin whitelisting, blocked-signal audit log
- [ ] **T-010** `Veil/src/gatekeeper.lua` — Permission tier enforcement (internal / dev tools / external harness), access control registry, denied-action audit log
- [ ] **T-011** `Veil/src/api_wrap.lua` — Wraps every exposed API with Veil enforcement, enforces blocked raw rendering access, optional anti-tamper integrity checks
- [ ] **T-012** `Veil/src/init.lua` — Assembles Veil, exposes the single Veil public interface, ensures Veil is irremovable once active

---

## Phase 4 — Axium Core: Runtime Orchestrator
> Manages global state, module registry, lifecycle machine, and the deterministic frame loop.

- [ ] **T-013** `Axium/src/registry.lua` — Module registration, lookup, duplicate prevention, dependency conflict detection, plugin manifest support (`name/version/dependencies/permissions`)
- [ ] **T-014** `Axium/src/lifecycle.lua` — Lifecycle state machine: `boot → preload → init → ready → running → suspended → reloading → shutting_down → destroyed`; exposes `init/start/stop/destroy` hooks per module
- [ ] **T-015** `Axium/src/runtime.lua` — Deterministic frame pipeline (input → signal flush → state → animation → layout → render sync → GC), throttled background task scheduler, frame profiler timers
- [ ] **T-016** `Axium/src/bootstrap.lua` — Early-stage boot sequence: activates Veil first, initializes Arc and Diagnostics, prepares runtime for Pulse handoff
- [ ] **T-017** `Axium/src/init.lua` — Assembles Axium, exposes global Axium namespace, coordinates all core subsystems

---

## Phase 5 — Pulse: Bootstrap & Loader
> Staged initialization. Ensures correct load order, resolves dependencies, wires signals.

- [ ] **T-018** `Pulse/src/dependency_graph.lua` — Builds and resolves module dependency graph, detects cycles, determines safe load order
- [ ] **T-019** `Pulse/src/module_loader.lua` — Loads individual modules via resolved graph order, handles init/start hooks, captures load errors
- [ ] **T-020** `Pulse/src/loader.lua` — Top-level loader entry: dev vs production mode detection, selectively enables/disables dev globals and harness exposure
- [ ] **T-021** `Pulse/src/startup_sequence.lua` — Staged startup: enforces Veil-first rule, sequences Arc → Diagnostics → Veil → Core → Canvas → Lattice → Controls, emits lifecycle signals at each stage
- [ ] **T-022** `Pulse/src/init.lua` — Assembles Pulse, exposes loader API, self-identifies mode (`development` / `production`)

---

## Phase 6 — Canvas/Lattice: UI Behavior & Interaction Engine
> Handles all UI animation, input, drag, binding. Consumes Arc, VoltSignal, Veil. Does not render directly.

- [ ] **T-023** `Canvas/Lattice/src.lua` — Lattice core: internal state store for all active UI nodes, dirty-flag tracking, layout invalidation queue
- [ ] **T-024** `Canvas/Lattice/bind.lua` — One-way and two-way state bindings, reactive subscriptions, stale-ref prevention on destroy
- [ ] **T-025** `Canvas/Lattice/input.lua` — Input collection layer: mouse, keyboard, scroll; normalizes raw input into Lattice events; feeds signal queue
- [ ] **T-026** `Canvas/Lattice/drag.lua` — Drag system: hit-test, drag start/move/end, snap-to-grid, boundary clamping, VoltSignal drag events
- [ ] **T-027** `Canvas/Lattice/tween.lua` — Tween engine: linear + easing curves, chained tweens, cancel/pause/resume, Arc.math integration
- [ ] **T-028** `Canvas/Lattice/spring.lua` — Spring physics: stiffness/damping/mass params, velocity accumulation, settling detection
- [ ] **T-029** `Canvas/Lattice/animation.lua` — Animation orchestrator: sequences tween and spring systems, handles per-node animation state, integrates with frame pipeline step 4
- [ ] **T-030** `Canvas/Lattice/Init.lua` — Assembles Lattice, exposes public Lattice API, registers with Axium via Veil

---

## Phase 7 — Canvas/Controls: UI Controls
> Built primitive-first. Each control depends on Lattice, Veil, VoltSignal. Complex controls depend on simpler ones.

### 7a — Display / Primitive
- [ ] **T-031** `Canvas/Controls/Label.lua` — Static/dynamic text display, font/size/color props, auto-size
- [ ] **T-032** `Canvas/Controls/Divider.lua` — Horizontal/vertical separator, thickness/color/margin props
- [ ] **T-033** `Canvas/Controls/Header.lua` — Section header with title text, optional subtitle, visual hierarchy styling
- [ ] **T-034** `Canvas/Controls/Paragraph.lua` — Multi-line text block, word wrap, selectable text option
- [ ] **T-035** `Canvas/Controls/Codeblock.lua` — Monospace code display, syntax highlight hint, scrollable, copyable

### 7b — Interactive / Simple
- [ ] **T-036** `Canvas/Controls/Button.lua` — Click action, hover/press/disabled states, label + icon support, VoltSignal `OnClick`
- [ ] **T-037** `Canvas/Controls/Checkbox.lua` — Boolean toggle, checked/unchecked/indeterminate states, label, VoltSignal `OnChanged`
- [ ] **T-038** `Canvas/Controls/ToggleSwitch.lua` — Animated boolean switch, spring animation on toggle, VoltSignal `OnChanged`
- [ ] **T-039** `Canvas/Controls/Slider.lua` — Range input, min/max/step, draggable thumb, value binding, VoltSignal `OnChanged`
- [ ] **T-040** `Canvas/Controls/TextInput.lua` — Single-line text input, placeholder, validation callback, character limit, VoltSignal `OnChanged` / `OnSubmit`

### 7c — Interactive / Complex
- [ ] **T-041** `Canvas/Controls/Radio_Horizontal.lua` — Horizontal radio group, mutual exclusion, VoltSignal `OnSelected`
- [ ] **T-042** `Canvas/Controls/Radio_Vertical.lua` — Vertical radio group, mutual exclusion, VoltSignal `OnSelected`
- [ ] **T-043** `Canvas/Controls/Dropdown.lua` — Select menu, searchable option list, multi-select option, animated open/close, VoltSignal `OnSelected`
- [ ] **T-044** `Canvas/Controls/Keypicker.lua` — Keybind capture, conflict detection, clear/reset, VoltSignal `OnBound`
- [ ] **T-045** `Canvas/Controls/Colorpicker.lua` — HSV/RGB/Hex input, color preview, alpha channel, VoltSignal `OnChanged`

### 7d — Feedback / Overlay
- [ ] **T-046** `Canvas/Controls/ProgressBar.lua` — Value/max props, animated fill, label overlay, indeterminate mode
- [ ] **T-047** `Canvas/Controls/Tooltip.lua` — Hover-triggered overlay, auto-position to avoid viewport clip, delay/fade
- [ ] **T-048** `Canvas/Controls/Toast.lua` — Timed notification popup, severity icon, auto-dismiss with tween, queue support
- [ ] **T-049** `Canvas/Controls/Notification.lua` — Persistent alert panel, dismiss button, severity levels, stacking

### 7e — Layout / Containers
- [ ] **T-050** `Canvas/Controls/Columns.lua` — Multi-column layout container, configurable column count/spacing, auto-distribute children
- [ ] **T-051** `Canvas/Controls/TabButton.lua` — Individual tab trigger, active/inactive state, VoltSignal `OnActivated`
- [ ] **T-052** `Canvas/Controls/TabSidebar.lua` — Vertical tab navigation, manages TabButton group, content panel switching
- [ ] **T-053** `Canvas/Controls/Modal.lua` — Blocking overlay dialog, backdrop, close-on-backdrop-click option, animated entry/exit
- [ ] **T-054** `Canvas/Controls/Window.lua` — Top-level UI container, drag via Lattice, resize handles, min/max size, z-index, close/minimize/collapse, clipping

### 7f — Special
- [ ] **T-055** `Canvas/Controls/Modular.lua` — Dynamic control composition: accepts a schema/config and assembles arbitrary control layouts at runtime

---

## Phase 8 — System Features

- [ ] **T-056** **Plugin & Extension Model** — Module manifest schema (`name/version/dependencies/permissions`), dynamic registration API, duplicate guard, dependency conflict handler with structured error log
- [ ] **T-057** **Persistence Layer** — Save/load for configs, window positions, preferences, runtime state; schema versioning; migration handler for outdated saves; corruption fallback to defaults
- [ ] **T-058** **Dev Loader** — Separate dev-mode loader path in `Pulse/src/loader.lua`: enables verbose logs, hot reload stubs, harness API, inspector hooks; production path strips all dev globals

---

## Phase 9 — Developer Tooling & Harness API

- [ ] **T-059** **Debug Console** — Live command input/output panel, command history, piped to diagnostics log
- [ ] **T-060** **UI Tree Inspector** — Real-time Canvas node hierarchy browser, property viewer per node, highlight-on-hover
- [ ] **T-061** **Signal/Event Monitor** — Live stream of all VoltSignal fires: name, payload, origin, timestamp; filterable
- [ ] **T-062** **Frame Profiler** — Per-frame cost breakdown tied to runtime pipeline steps, rolling average, spike detection
- [ ] **T-063** **Module Registry Viewer** — Lists all registered modules: name, version, state, dependencies, permissions
- [ ] **T-064** **Live Log Viewer** — Filterable, real-time stream from diagnostics rolling buffer; filter by severity/subsystem/module
- [ ] **T-065** **Harness API** (`_G.AxiumHarness`) — Dev-mode-only external control harness: request/response messaging, commands (`inspect/call/getState/setState/emitSignal/listModules/reloadModule/createUI/destroyUI`), Veil-validated, rate-limited, optional auth token, full audit log; destroyed if not in dev mode

---

*Total tasks: 65*
