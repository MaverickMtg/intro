# vgx-showroom v4 — Player Showrooms, created entirely IN-GAME

QBCore. Works exactly like the lt-shops system: admins create everything from an
in-game panel — no config coords, no restarts, no file edits.

## What changed vs v3
- **Multiple showrooms**: create as many as you want, anywhere on the map.
- **Everything in-game** via `/showrooms`:
  - Create a showroom: stand at each spot and press **Capture** (entrance,
    vehicle drop-off, optional test-drive spawn/return).
  - **Vehicle parking slots** are captured in-game too: park a car exactly how
    display vehicles should face and press *Capture slot at my position* (uses
    the vehicle's position + heading). Capture as many slots as you want.
  - Assign / remove the **owner** by online player ID.
  - Add / remove parking slots on existing showrooms at any time.
  - Rename, edit points, delete showrooms (listed cars are returned to their
    owners' garages automatically).
- **Per-showroom everything**: staff, listings, sales log, treasury
  (`society` row `showroom_<id>`), blip with the showroom's name.
- **Identifier-based admins** (like lt-shops): `Config.SuperAdmins`
  (Discord ID / license) + extra admins added from the panel — no QBCore
  god/admin groups needed.

## Install
1. Drop `vgx-showroom` into resources, `ensure vgx-showroom` after `qb-core`
   and `oxmysql`.
2. Run `sql/setup.sql`.
   - Upgrading from v3? Run `sql/migrate_v3_to_v4.sql` afterwards — it converts
     your old Legacy Motors config into showroom #1 with its 11 slots.
3. Open `config.lua` → `Config.SuperAdmins` and add YOUR identifiers:
   ```lua
   Config.SuperAdmins = {
       'discord:123456789012345678',   -- your Discord user ID
       -- 'license:1a2b3c....',        -- or your FiveM license
   }
   ```
4. In-game: `/showrooms` → **Create Showroom** tab → capture the points and
   parking slots → Create. Then assign an owner from the **Showrooms** tab.

## Day-to-day usage (unchanged from v3)
- **Entrance marker** → browse UI (buy, inspect, staff/treasury tabs for staff).
- **Drop-off marker** → staff drive a car in and press E to list it
  (auto-picks the first free slot; set the price from the UI).
- Walk up to any display car → **E** inspect, **G** test drive (if enabled).
- Owner manages staff (manager/employee) and withdraws the treasury from the UI.

## Notes
- Treasury balances live in the `society` table as `showroom_<id>` so they show
  up in qb-bossmenu too. The old `showroom_legacy` row is migrated to
  `showroom_1` by the migration script.
- All permission checks are server-side and per-showroom.
