# qb-multicharacter (VGX Edition)

Multicharacter for QBCore with a rebuilt sharp-cornered cyber UI and a fixed character preview system.

## What is different from stock qb-multicharacter

### Duplicate ped fix

The stock resource could leave a clone of your preview ped behind, so after spawning you would see "another ped like yours" standing in the world. This version:

- Tracks every preview ped it creates in a list and deletes all of them (not just the last handle) whenever the preview changes or you spawn in.
- Uses a request generation counter so that if you click between characters quickly, ped creations that are still loading a model get cancelled instead of spawning an orphan ped.
- Sweeps the preview area for any leftover non-player peds as a safety net (covers resource restarts and lost handles).
- Deletes preview peds again after the spawn fade-out, catching peds that finished spawning during the transition.
- Cleans up peds on resource stop.

### New UI

- Sharp corners everywhere: zero border radius, angled clip-path cuts instead.
- Slot panel on the left, live character intel panel on the right (job, grade, cash, bank, nationality, birthdate, gender, phone, account number).
- Animated glitch title, scanning beam, drifting holo-grid, neon cyan/red theme.
- New fonts: Orbitron for display text, Chakra Petch for body text.
- Rewritten in vanilla JS — Vue, Vuetify and SweetAlert were removed, so the NUI is much lighter.
- Custom nationality autocomplete, gender toggle buttons, inline toast validation errors.
- All existing locales keep working (translations are passed from Lua exactly like before).

## Install

1. Drop the `qb-multicharacter` folder into your `resources/[qb]` directory (replace the old one).
2. `ensure qb-multicharacter` after `qb-core` (already the case if you replaced the stock resource).
3. No database or config changes are required; the stock `config.lua` options still apply.

## Dependencies

- qb-core
- qb-spawn
- qb-apartments (config is read at startup, same as stock)
- oxmysql
