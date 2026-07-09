# lt-shops — Player Owned Shops (Grocery + Weapon Stores)
Legends RP | QBCore

## What it does
- **Admin-assigned shops**: admins create shops and assign an owner. Every shop has its own coords, own owner, own staff, own safe.
- **Two types**:
  - **Grocery** — always open. Seller ped (staff management + add items), buyer ped (customers), stash, safe, custom blip name.
  - **Weapon store** — same as grocery **plus**: crafting table (materials pulled from shop stash), open/close toggle, and buyers **must carry a signed weapon license** to buy.
- **3-tier staff**: Owner / Manager / Employee (full permission matrix in `config.lua`).
  - Employees can deposit crafting materials into the stash (deposit-only) and restock listings.
  - Managers can do most things but can't withdraw the safe, rename the blip, or sign licenses.
- **Safe**: all sales revenue goes into the shop safe. Owner withdraws it. Anyone with a **lockpick** can rob it — but ONLY if no shop staff is in the premises (radius configurable). Police get alerted + flashing blip. Robbers get markedbills.
- **Weapon license**: owner signs an A4-paper license item (`weaponlicense`) with his name + signature + date, delivered straight to the player's inventory. No signed license = no buying.
- **Custom blips**: each owner names his own store on the map. Weapon stores show (مفتوح/مغلق) and change blip color.

## Install
1. Drop `lt-shops` into resources, add `ensure lt-shops` **after** qb-core, oxmysql, qb-target.
2. Run `install.sql` — it creates the tables **and seeds your 2 shops** at the coords you gave (Grocery near Innocence Blvd + Weapon store near Ammu-Nation).
3. Add the license item to `qb-core/shared/items.lua`:

```lua
weaponlicense = { name = 'weaponlicense', label = 'رخصة سلاح', weight = 50, type = 'item', image = 'weaponlicense.png', unique = true, useable = true, shouldClose = true, description = 'ورقة A4 - رخصة سلاح موقعة' },
```

4. Add a `weaponlicense.png` image to qb-inventory images (any A4 paper icon works).
5. Make sure `lockpick` and `markedbills` items exist (they do in default QBCore). If your markedbills item has a different name, change it in `server/main.lua` (search `markedbills`).

## Usage
- `/shops` — opens the admin panel (QBCore `god`/`admin` groups, plus anyone you add in the Admins tab). Create shops in-game: stand at each spot and press **📍 موقعي** to capture coords. Assign/remove owners by server ID. Delete shops.
- `/shopsgive [id]` / `/shopsremove [id]` — (god only) grant/revoke in-game shop-admin.
- **Seller ped** → full management NUI (listings, staff, safe/revenue, settings, open/close, sign licenses).
- **Buyer ped** → customer shop UI.
- **Stash point** → shop storage (deposit/withdraw) + the safe lockpick option for robbers.
- **Crafting point** (weapon shops) → craft menu; materials consumed from shop storage.

## Crafting recipes
Edit `Config.Crafting` in `config.lua` — send me your weapon list and I'll wire the exact recipes.

## Notes
- Everything is server-authoritative: permission, distance, price, stock, craft timing, and rob timing are all validated server-side. Client can't fake any of it.
- Sales tax option in config (`Config.SalesTax`) if you want the city to take a cut.

## Admin Permissions (identifier-based, no QBCore groups)
1. Open `config.lua` → `Config.SuperAdmins` and add YOUR identifiers (server owner):
   ```lua
   Config.SuperAdmins = {
       'discord:123456789012345678',   -- your Discord user ID
       -- 'license:1a2b3c....',        -- or your FiveM license
   }
   ```
   Find your license in the server console when you connect, or in the `players` table.
2. In-game type `/shops` → full panel: create shops, set owners, sign weapon licenses, and (super admins only) add more shop admins by online player ID, Discord ID, or license string.
3. If you already imported an older install.sql: re-run just the `lt_shop_admins` part (it drops & recreates that table only).
