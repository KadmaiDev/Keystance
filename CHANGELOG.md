## Keystance 1.0.0

New on the Keyboard tab, Update saves your gear, and a full review of everything that changes your bars, keys and gear.

- **Heat map:** the Keyboard tab's Heat map button colours every key by how easy it is to reach while your hand rests on your movement keys (read from your keybinds: WASD, ESDF...), with a legend, and each key's reach in its tooltip.
- **Move your hand:** with the heat map on, "Hand right" moves your movement keys one key right (W A S D to E S D F) and every keybind on the left of your keyboard with them, in every Shift, Ctrl and Alt layer, so each spell stays under the same finger. The column pushed off the edge wraps round, your profiles' keys move too, it asks first, and Undo puts it all back. "Hand left" goes the other way.
- **Update saves your gear too** when a profile uses Keystance's own gear: the slots it has gear for get what you're wearing now. If your gear is still being changed, or the game hasn't loaded it, the old gear is kept and Keystance says so.
- **Your keybinds shared between characters are never changed.** Restore original setup and Undo now give the character its own keybinds first, as applying a profile already did, so your other characters keep theirs. The Restore question says so.
- **Damaged saved data is refused, not half-applied:** a profile, the original setup or an undo record that's damaged in the saved file changes nothing and is kept as it is. Settings of the wrong kind go back to their defaults at login, so a damaged file can't break the windows.
- **Nothing changes until your original setup is saved:** right after login, before the game has loaded your bars and keys, Keystance waits rather than risk saving an already-changed setup as your original.
- **Undo puts back more:** which profile a key belongs to, a ring or trinket moved from one slot to the other, and nothing at all when it can't run (before, Move your hand's profile keys could go back on their own). It also stops a gear swap still under way, which could carry on after the Undo, and waits while your gear is still moving.
- **Two macros with the same name** (one for your account, one for the character): Keystance can't tell which one is on a button, so it leaves that button alone and says so, instead of guessing.
- Gear the game won't reveal at that moment is never saved as an empty slot.

## Keystance 0.1.0

The first release: keybinds, action bars and gear for each role, switched by hand, by key or automatically.

- **Profiles:** save your action bars and the keys of their buttons as a profile for each role, and apply it with one click. Every change can be undone, and a profile can be updated with how your bars are now. Each profile can have its own icon.
- **Switching:** click a profile, press its own key, step through them with a "next profile" key, or use the profile switcher, a small bar you can place anywhere on screen. A switch asked for in combat waits until combat ends.
- **Rules:** switch profile automatically when you equip a shield, a two-hander, a particular item or a gear set (the game's own equipment sets or ItemRack's), or ask first.
- **Gear:** a profile can put on an ItemRack set, or Keystance's own set, before its bars.
  - Pick each slot's item from what you have that fits, including your bank while it's open.
  - Items left in the bank are marked "In your bank", and a soft sound plays if something can't go on.
  - Undo puts gear back where it came from.
- **Bank panel:** a Keystance button on the bank window (Blizzard's, EllesmereUI's or ElvUI's) fetches a profile's gear from the bank, or stores it there. Items another profile uses stay in your bags.
- **Keyboard view:** see which key does what on an on-screen keyboard (US or UK, with or without the numpad) with its Shift, Ctrl and Alt layers, or on a controller.
- **Bars view:** your action bars and their keys. Show or hide bars, and set keys by hovering a button and pressing a key.
- **Actions panel:** spells (and those still to learn), macros, raid markers, profiles and commands, to drag onto your bars or straight onto a key.
- **New spell ranks** replace the old ones on your bars. Ranks you placed on purpose are left alone, and you can turn it off.
- **Safe to try:** before changing anything, Keystance saves your bars and every keybind, and **Restore original setup** puts them all back. Nothing changes in combat, and if your keybinds are shared between characters it asks before changing them.
- **Getting started:** a short guide walks you through your first profiles.
- Looks at home with the default UI, EllesmereUI or ElvUI. The minimap button works with EllesmereUI's tray and MinimapButtonButton.
