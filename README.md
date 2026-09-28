<p align="center"><img src="media/logo.png" alt="Keystance logo" width="200"></p>

# Keystance

*Working name.*

A keybind and action bar manager for **World of Warcraft: Forever**, by **Kadmai**.

- See at a glance which key does what, on an on-screen keyboard.
- Keep separate bar and keybind profiles per role (for example a paladin's Retribution, Protection and Holy setups), and switch between them by hand or automatically when you equip certain gear, such as a shield.
- New spell ranks replace the old ones on your bars, and newly learned spells get a suggested key.
- Finger-friendly suggestions: common abilities go on keys close to your movement keys, so you're not stretching for them.
- Looks at home with the default UI, EllesmereUI or ElvUI.

Status: early development, not released yet. So far you can see your keybinds on an on-screen keyboard (with Shift, Ctrl and Alt layers) and your action bars with their keys, in a window that takes the look of your UI addon; the rest arrives in stages.

Your setup is safe: Keystance only reads your bars and keys for now. Shortly after your first login with it, it saves a copy of your bars and keybinds as they were, so that once it can change them you can always put everything back.

## Commands

`/kst` (or `/keystance`) opens Keystance. Also: `/kst options` opens its page in the game's Options > AddOns, `/kst minimap` shows or hides the minimap button, `/kst skin auto | classic | ellesmere | elvui` picks the look, `/kst mem` shows memory use, `/kst help` lists everything.

## Performance

Keystance does nothing while you play: no code runs every frame, the window is only built the first time you open it, and while it's closed the game's events cost one check and create no garbage. It uses about 120 KB of memory (measured outside the game; `/kst mem` shows the real figure).

## Development

`luajit tests/run.lua` runs the tests against a fake game API; `luajit tests/perf.lua` measures memory and garbage. `python tools/install_dev.py "<WoW>\_classic_beta_"` installs a "Keystance (dev)" copy; `python tools/release.py` builds the release zip.

## Licence

MIT, see `LICENSE`.
