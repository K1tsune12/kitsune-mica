# Kitsune Mica 🦊

A [Millennium](https://github.com/SteamClientHomebrew/Millennium) plugin that gives the Steam client a translucent **Mica / acrylic backdrop**.

Fork of [dwmx](https://github.com/shdwmtr/dwmx), with the main Steam window now included and a few stability fixes.

## Requirements

- Windows 11
- Transparency effects turned **on** (Settings → Personalization → Colors)
- A theme with transparent backgrounds - e.g. [Kitsune Theme](https://github.com/K1tsune12/steam-kitsune-theme) or [SpaceTheme](https://github.com/SpaceTheme/Steam)

## Install

1. Install **Millennium** (v3.0+).
2. Place this plugin in `...\Steam\millennium\plugins\kitsune-mica\`.
3. Turn on transparency effects in Windows.
4. Restart Steam and enable **Kitsune Mica** in *Millennium → Plugins*.

## Build

```bash
pnpm install
pnpm build
```

## Changelog

- **v1.0.3** - Fixed an occasional crash when launching Steam. Minor cleanup.
- **v1.0.2** - Fixed a Steam client crash.
- **v1.0.1** - Stability fix for newer Windows.
- **v1.0.0** - First release: Mica/acrylic backdrop, with the main window included.

## Credits

Based on [dwmx](https://github.com/shdwmtr/dwmx) by shdwmtr. MIT licensed - see [LICENSE](./LICENSE).
