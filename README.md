# Kitsune Mica

Fork of [shdwmtr/dwmx](https://github.com/shdwmtr/dwmx) (the "Extended Desktop Window Manager" Millennium plugin for Steam) that fixes a critical bug preventing the main Steam window from being patched.

> [!WARNING]
> This plugin extends Windows 11 native compositor, allowing it to work with the Steam Client.
> You MUST have transparency effects enabled on your system, otherwise it will not work.

## What this plugin does

Patches `steamwebhelper.exe` windows with:
- Custom border radius (rounded corners)
- Acrylic window backdrop (blur-behind, enabling Mica-like transparency)

Supported themes must implement the CSS-side (transparent backgrounds) for the effect to be visible — e.g. [SpaceTheme](https://github.com/SpaceTheme/Steam) or [Kitsune Theme](https://github.com/K1tsune12/steam-kitsune-theme).

## Why this fork exists

Upstream dwmx had two bugs that prevented it from patching the **main Steam window** (only secondary popups got blurred):

### Bug 1 — `ULONG_PTR` declared as 4 bytes on x64

In `backend/main.lua`, the FFI cdef declared:

```c
typedef unsigned long ULONG_PTR;  // wrong: `unsigned long` is 4 bytes on Windows (LLP64)
```

But `ULONG_PTR` is pointer-sized — 8 bytes on x64. This made `PROCESSENTRY32W` 12 bytes too small. When `Process32FirstW` was called with this misaligned struct, Windows silently rejected it (returned 0). Result: `find_pids_by_name("steamwebhelper.exe")` always returned empty, so `PatchAllWindows()` never had any window to patch.

**Fix**: use `uintptr_t` / `intptr_t` instead — these are platform-aware in LuaJIT FFI.

### Bug 2 — `PatchAllWindows()` not called on plugin load

Upstream only calls `PatchAllWindows()` inside the `window.open` JavaScript hook. The main Steam window is created natively by CEF **before** the plugin's frontend hook installs, so it never passes through `window.open` and never gets patched.

**Fix**:
- `frontend/index.tsx` — call `PatchAllWindows()` once inside `PluginMain` so existing windows (including the main one) get patched on plugin load.
- `backend/main.lua` — `on_frontend_loaded` was calling a placeholder `"classname.method"` that errored. Replaced with a real `PatchAllWindows()` call as additional safety.

## CPU usage

This fork does **not** reintroduce the heavy CPU usage of the old Python-based dwmx (which used `SetWinEventHook(EVENT_MIN..EVENT_MAX)` and ran a continuous event listener). The patching strategy stays event-driven:

- 1 call on plugin/frontend load (now actually works)
- 1 call per `window.open` (when Steam opens popups/modals)

No polling, no continuous hook.

## Installation

1. Make sure you have **Millennium v3.0+** installed.
2. Place the plugin folder at `C:\Program Files (x86)\Steam\millennium\plugins\kitsune-mica\`.
3. Enable transparency effects in Windows 11 (*Settings → Personalization → Colors → Transparency effects*).
4. Restart Steam.
5. Enable **Kitsune Mica** in *Millennium → Plugins*.

Your theme must support transparent backgrounds for the effect to be visible.

## Build from source

Requires Node.js + pnpm.

```bash
pnpm install
pnpm build
```

Then copy `plugin.json`, `backend/`, and `.millennium/Dist/` to the Millennium plugins folder.

## License

MIT — see [LICENSE](./LICENSE). Credit to original author [shdwmtr](https://github.com/shdwmtr) for the dwmx project.
