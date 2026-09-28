<p align="center"><img src="media/logo.png" alt="Keystance logo" width="200"></p>

# Keystance

*Working name.*

A keybind and action bar manager for **World of Warcraft: Forever**, by **Kadmai**.

- See at a glance which key does what, on an on-screen keyboard.
- Keep separate bar and keybind profiles per role (for example a paladin's Retribution, Protection and Holy setups), and switch between them by hand or automatically when you equip certain gear, such as a shield.
- New spell ranks replace the old ones on your bars, and newly learned spells get a suggested key.
- Finger-friendly suggestions: common abilities go on keys close to your movement keys, so you're not stretching for them.
- Looks at home with the default UI, EllesmereUI or ElvUI.

Status: early development, not released yet. So far: your keybinds on an on-screen keyboard (with Shift, Ctrl and Alt layers), your action bars with their keys, profiles you can save, apply, undo and restore from, new spell ranks replacing old ones on your bars, and a spell panel: every class spell (and the ones still to learn), your macros and the raid markers in one searchable list, to drag onto your bars or straight onto a key on the keyboard. Rules switch profiles automatically when you equip a shield, a two-hander, a particular item or an equipment set. All in a window that takes the look of your UI addon. Finger-friendly key suggestions arrive next.

## Your setup is safe

- Shortly after your first login with Keystance, before it has changed anything, it saves a copy of your bars and every keybind. **Restore original setup** (Profiles tab, Settings, or `/kst restore`) puts them all back.
- **Before uninstalling Keystance, click Restore original setup.** Changes to bars and keys are kept by the game itself, so they stay after an addon is removed.
- Every change can be undone with one click, nothing changes in combat (changes wait until combat ends), and anything that can't be set is reported and left as it was.
- A profile holds your bars and the keys of your bar buttons only; movement and every other key are left alone.
- If your keybinds are shared by all your characters, Keystance asks before a profile changes them, and offers to give the character its own keybinds (nothing changes on screen, and your other characters keep theirs).

## Commands

`/kst` (or `/keystance`) opens Keystance. Profiles: `/kst save Name`, `/kst apply Name` (works in macros), `/kst undo`, `/kst restore`, `/kst profiles`, `/kst ownkeys`. `/kst spells` opens the spell panel, `/kst ranks` turns rank upgrades on or off, `/kst auto on|off` turns automatic switching on or off. Also: `/kst options` opens its page in the game's Options > AddOns, `/kst minimap` shows or hides the minimap button, `/kst skin auto | classic | ellesmere | elvui` picks the look, `/kst mem` shows memory use, `/kst help` lists everything.

## Performance

Keystance does nothing while you play: no code runs every frame, the window is only built the first time you open it, and while it's closed the game's events cost one check and create no garbage. It uses about 220 KB of memory (measured outside the game; `/kst mem` shows the real figure).

## Development

`luajit tests/run.lua` runs the tests against a fake game API; `luajit tests/perf.lua` measures memory and garbage. `python tools/install_dev.py "<WoW>\_classic_beta_"` installs a "Keystance (dev)" copy; `python tools/release.py` builds the release zip.

## Licence

MIT, see `LICENSE`.
