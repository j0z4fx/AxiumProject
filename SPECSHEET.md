# Axium Spec Sheet

All modules operate under Axium.Veil enforcement at all times. Veil is mandatory for every internal call, rendering operation, signal flow, and external exposure. No functionality is accessible unless routed through Veil.

All eventing uses VoltSignal exclusively. All rendering uses the Volt Drawing Library exclusively.

---

## System Overview

Axium is a modular runtime framework consisting of UI construction, interaction logic, rendering output, and system orchestration. All subsystems are coordinated through Axium.Veil and initialized via Axium.Pulse.

---

## Error Handling & Diagnostics

- Add very detailed error handling across all modules and subsystems.
- Wrap sensitive execution paths with protected calls and structured failure capture.
- Every error log must include: timestamp, subsystem, module, function, stack trace, message, and safe argument context when available.
- Maintain an internal rolling log buffer for diagnostics.
- Automatically copy formatted error reports to clipboard using `setclipboard(text: string)` whenever an error occurs.
- Duplicate filtering: constantly repeating identical errors are only copied once during a cooldown period.
- Repeated identical errors increment a counter instead of creating new clipboard entries.
- Severity levels: `info`, `warning`, `error`, `critical`.
- Critical failures may trigger fallback mode, subsystem restart, or safe shutdown behavior.
- Support optional developer console output and debug overlay output.

### Mini Docs: Clipboard

| Field    | Value |
|----------|-------|
| Function | `setclipboard(text: string) -> void` |
| Purpose  | Copies text to the system clipboard. |
| Aliases  | `toclipboard`, `setrbxclipboard` |
| Example  | `setclipboard("[Axium Error] nil reference in Canvas.Window")` |

---

## File Structure

```
/AxiumProject/
│
├── /Axium/
│   └── /src/
│       ├── init.lua
│       ├── bootstrap.lua
│       ├── registry.lua
│       ├── lifecycle.lua
│       ├── runtime.lua
│       └── scripts/
│
├── /Canvas/
│   ├── /Lattice/
│   │   ├── Init.lua
│   │   ├── src.lua
│   │   ├── drag.lua
│   │   ├── tween.lua
│   │   ├── spring.lua
│   │   ├── bind.lua
│   │   ├── input.lua
│   │   └── animation.lua
│   │
│   └── /Controls/
│       ├── Window.lua
│       ├── Modal.lua
│       ├── TabSidebar.lua
│       ├── TabButton.lua
│       ├── Notification.lua
│       ├── Toast.lua
│       ├── Columns.lua
│       ├── Button.lua
│       ├── Dropdown.lua
│       ├── ToggleSwitch.lua
│       ├── Checkbox.lua
│       ├── TextInput.lua
│       ├── Slider.lua
│       ├── Label.lua
│       ├── Keypicker.lua
│       ├── Colorpicker.lua
│       ├── Radio_Horizontal.lua
│       ├── Radio_Vertical.lua
│       ├── Modular.lua
│       ├── ProgressBar.lua
│       ├── Tooltip.lua
│       ├── Divider.lua
│       ├── Header.lua
│       ├── Paragraph.lua
│       └── Codeblock.lua
│
├── /Veil/
│   └── /src/
│       ├── init.lua
│       ├── gatekeeper.lua
│       ├── validator.lua
│       ├── api_wrap.lua
│       └── signal_filter.lua
│
├── /Pulse/
│   └── /src/
│       ├── init.lua
│       ├── loader.lua
│       ├── dependency_graph.lua
│       ├── module_loader.lua
│       └── startup_sequence.lua
│
└── /Arc/
    └── /src/
        ├── init.lua
        ├── math.lua
        ├── signals.lua
        ├── transforms.lua
        ├── utils.lua
        └── cache.lua
```

---

## Core Module

### Axium (Main)

- **Type:** Runtime Orchestrator
- **Responsibility:**
  - Manages global system state
  - Coordinates all module lifecycle events
  - Routes communication between subsystems
  - Enforces Veil-controlled execution flow
  - Maintains registry of all loaded modules

---

## UI Layer

### Axium.Canvas

- **Type:** UI Framework Layer
- **Responsibility:**
  - Defines UI structure (windows, tabs, containers, elements)
  - Manages UI hierarchy and state
  - Does not render directly
  - Outputs structured UI data to Lattice and rendering pipeline

### Axium.Canvas.Lattice

- **Type:** UI Behavior & Interaction Engine
- **Responsibility:**
  - Handles UI animations and transitions
  - Provides drag, snap, hover, and input binding systems
  - Converts user input into reactive UI state changes
  - Uses VoltSignal for all event-driven behavior
  - Bridges UI logic to rendering updates

---

## Security Layer

### Axium.Veil

- **Type:** Security / Execution Control / Cloaking Layer
- **Responsibility:**
  - Validates all function calls and module interactions
  - Controls access to rendering and internal APIs
  - Enforces system-wide execution rules
  - Acts as sole gateway to drawing and sensitive operations
  - Required for all VoltSignal usage validation
  - Mediates all cross-module communication

---

## Initialization Layer

### Axium.Pulse

- **Type:** Bootstrap / Loader
- **Responsibility:**
  - Initializes system in staged order
  - Ensures Veil is active before subsystem startup
  - Loads and links all modules (Canvas, Lattice, Arc, Drawing layer)
  - Establishes runtime dependencies and signal wiring

---

## Utility Layer

### Axium.Arc

- **Type:** Core Utility / Computation Layer
- **Responsibility:**
  - Provides math utilities and helper functions
  - Supplies signal and transformation utilities
  - Prepares computed values for UI and rendering systems
  - Serves as internal abstraction layer for shared logic

---

## Rendering Layer

### Volt Drawing Library

- **Type:** Low-Level Rendering System
- **Responsibility:**
  - Directly renders visuals to viewport
  - Manages drawable objects independent of UI hierarchy
  - Provides primitive drawing API

### Core Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `Drawing.new` | `Drawing.new(type) -> obj` | Creates render object |
| `setrenderproperty` | `setrenderproperty(obj, property, value)` | Updates visual properties |
| `getrenderproperty` | `getrenderproperty(obj, property) -> value` | Retrieves property values |
| `cleardrawcache` | `cleardrawcache()` | Removes all render objects |
| `isrenderobj` | `isrenderobj(value) -> bool` | Validates render objects |

---

## Event System

### VoltSignal

- **Type:** Event / Signal System
- **Responsibility:**
  - Handles internal communication between modules
  - Enables reactive UI and system behavior

### API

| Method | Signature | Description |
|--------|-----------|-------------|
| `VoltSignal.new` | `VoltSignal.new() -> signal` | Creates signal instance |
| `VoltSignal:Connect` | `:Connect(f) -> VoltConnection` | Registers handler |
| `VoltSignal:Fire` | `:Fire(...) -> void` | Triggers signal with arguments |
| `VoltSignal:Wait` | `:Wait() -> ...` | Yields until signal fires |
| `VoltConnection:Disconnect` | `:Disconnect() -> void` | Removes handler |

---

## Runtime Lifecycle

- Lifecycle states: `boot → preload → init → ready → running → suspended → reloading → shutting_down → destroyed`
- Every module must expose `init` / `start` / `stop` / `destroy` hooks when applicable.
- Pulse coordinates ordered transitions and dependency-safe startup.
- Veil remains active during all lifecycle transitions.

---

## Runtime Update Loop

Deterministic frame pipeline. Order per tick:

1. Input collection
2. Signal queue flush
3. State updates
4. Animation / tween / spring updates
5. Layout recalculation
6. Render object sync
7. Cleanup / garbage collection tasks

Support throttled background tasks on lower priority intervals.

---

## State & Binding Model

- Controls may use local state, shared runtime state, or reactive bound state.
- Support one-way and two-way bindings.
- Signal-driven updates mutate only subscribed nodes.
- Prefer immutable snapshots for complex shared state transitions.
- Prevent stale references on destroyed controls.

---

## Layout Rules

- Support: padding, margin, spacing, docking, stacking, rows, columns, absolute positioning.
- Support auto-size based on content.
- Support min/max size constraints.
- Support clipping and overflow handling.
- Support z-index / draw order priority.
- Support responsive scaling for viewport changes.

---

## Performance Policy

- Reuse drawing objects whenever possible.
- Avoid destroying and recreating render objects during normal updates.
- Dirty-state redraws: only changed objects update.
- Batch property writes when possible.
- Debounce spam signals and expensive recalculations.
- Pool temporary objects and caches.
- Lightweight profiler timers for frame cost analysis.

---

## Security Rules

- Only approved APIs may be called through Veil.
- Direct raw rendering access outside Veil is blocked.
- Validate signal payload types and origins.
- Sanitize external inputs before execution.
- Maintain audit logs for denied actions.
- Permission tiers: internal modules / developer tools / external harness access.
- Optional anti-tamper integrity checks.

---

## Developer Loader

- Dedicated Dev Loader separate from production loader behavior.
- Dev Loader may enable: debugging systems, verbose logs, hot reload, harness API, inspectors.
- Production loader disables all developer-only globals and harness exposure.
- Dev Loader self-identifies current mode: `development` or `production`.

---

## Harness API (Developer Mode Only)

- External control harness for MCP / automation workflows.
- Exists only when launched through Dev Loader.
- Global namespace: `_G.AxiumHarness`
- External scripts may issue API-formatted commands to the active runtime.
- Communication model: request / response.

### Supported Commands

`inspect` · `call` · `getState` · `setState` · `emitSignal` · `listModules` · `reloadModule` · `createUI` · `destroyUI`

### Harness Security

- All harness commands pass through Veil validation.
- Rate limiting enforced.
- Optional authentication token.
- Full audit logging for all harness calls.
- If Dev Loader not active: harness API must not exist.

---

## Plugin & Extension Model

- Module manifests: `name`, `version`, `dependencies`, `permissions`.
- Allow dynamic registration of controls, services, and utilities.
- Prevent duplicate registrations.
- Dependency conflicts fail safely with logs.

---

## Persistence Layer

- Support save/load of: configs, window positions, preferences, runtime state.
- Schema versioning required.
- Migration handlers for older saved data.
- Fallback safely to defaults on corruption.

---

## Developer Tooling

| Tool | Description |
|------|-------------|
| Debug Console | Live command input and output |
| UI Tree Inspector | Visual hierarchy browser |
| Signal/Event Monitor | Real-time signal activity viewer |
| Frame Profiler | Per-frame cost breakdown |
| Module Registry Viewer | Loaded module list and metadata |
| Live Log Viewer | Filterable, real-time log stream |

---

## AI Generation Standards

- Generate complete, production-ready implementations.
- No placeholder functions.
- No pseudocode.
- No TODO stubs unless explicitly requested.
- Defensive programming throughout.
- Clean, readable, maintainable modules.
- One responsibility per file.
- Public APIs documented with concise comments.
- Optimize for reliability and performance.

---

## Data Flow Summary

```
UI defined in        →  Axium.Canvas
Interaction logic    →  Axium.Canvas.Lattice
Events propagate via →  VoltSignal
Validation by        →  Axium.Veil
Rendering via        →  Volt Drawing Library
Initialized by       →  Axium.Pulse
Utilities from       →  Axium.Arc
```
