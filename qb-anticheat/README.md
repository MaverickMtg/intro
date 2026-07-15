# qb-anticheat

A server-authoritative anti-cheat resource for **QBCore** FiveM servers, built to
counter the exact techniques used by client "menu" cheats (the *Macho / Kso7*
style menus): revive-spam crashes, explosion/VDM trolls, bot & vehicle flooding,
weapon-damage exploits, teleport/god/noclip, and attempts to stop the anti-cheat.

Every punishment decision is made **on the server**. Detections are written to a
flat-file audit log **and** pushed to Discord via webhooks.

> ⚠️ No anti-cheat is a silver bullet. The strongest protection comes from
> server-authoritative validation of your own resources (never trust client
> `TriggerServerEvent`). This resource focuses on that layer plus a best-effort
> client layer, and detects when the client layer is tampered with.

## Installation

1. Copy the `qb-anticheat` folder into your `resources` directory.
2. Add `ensure qb-anticheat` to your `server.cfg` **after** `qb-core`. For best
   results, start it as early as possible so its event handlers are attached
   before players connect.
3. Open `config.lua` and paste your Discord webhook URL(s) into `Config.Webhooks`.
   At minimum set `Config.Webhooks.default`.
4. Tune the thresholds to your server (see below) and restart.

## What it protects against

| Cheat behaviour (from the menu) | Protection | Layer |
| --- | --- | --- |
| `hospital:server:RevivePlayer` spam → **crash/DoS** | `Config.EventFlood` per-event rate guard | Server |
| Cuff-all / Kidnap / Rob / Search / OpenInventory / Paymentcheck spam | `Config.EventFlood` | Server |
| Boom-vehicle / crush / mass explosions / VDM detonations | `explosionEvent` blacklist + rate limit (cancels the explosion) | Server |
| "Crasher" ped/bot flooding, black-hole/attach, bus spam, mass vehicle spawn | `entityCreating` / `entityCreated` rate limit + burst deletion | Server |
| Spawning blacklisted models (bus, etc.) | `Config.EntitySpawn.blacklistedModels` (cancels creation) | Server |
| Super-punch / weapon damage modifier / illegal weapons | `weaponDamageEvent` validation (cancels the hit) | Server |
| Teleport / goto / crasher teleport | Position/speed sampling | Server |
| God mode | `GetPlayerInvincible` report | Client → server |
| Noclip | `GetEntityCollisionDisabled` report | Client → server |
| Invisibility | alpha/visibility report | Client → server |
| `MachoResourceStop` / killing the anti-cheat / frozen client script | Heartbeat timeout | Server |

## How punishment works

`Config.Actions` maps each detection category to `log`, `kick`, or `ban`.

- **log** – recorded to `detections.log` + Discord only.
- **kick** – recorded + player dropped.
- **ban** – recorded + permanent ban written to `bans.json` (keyed by every
  identifier: license, discord, ip, steam, …). Enforced at connect time.

Kicks escalate to a ban after `Config.MaxFlagsBeforeBan[category]` repeat offences,
which protects against one-off false positives.

**Admins never get punished.** Anyone matching `Config.AdminPermissions`
(QBCore permission) or holding the `Config.AdminAce` ACE is bypassed; their
detections are still logged so you can spot a compromised admin account.

## Logs & webhooks

- **File:** `detections.log` (one JSON object per line) in the resource folder —
  a permanent, greppable audit trail.
- **Discord:** separate channels per category (`explosions`, `entities`,
  `weapons`, `events`, `movement`, `tamper`, `bans`). Any blank webhook falls
  back to `Config.Webhooks.default`.

## Console commands (server console only)

- `acbans` – list all ban records.
- `acunban <banId>` – remove a ban (the ban ID is shown in the ban webhook/log).

## Tuning notes / avoiding false positives

- **`teleport`** defaults to `log` because legitimate teleports (admin menus,
  interiors, respawns) trip the speed check. Watch the logs first, then raise
  `Config.Movement.maxSpeed` or switch to `kick`/`ban` once tuned.
- **`eventFlood`** thresholds must be higher than your busiest legitimate usage
  (e.g. an EMS main reviving many players). Start permissive, tighten from logs.
- **`entitySpam`** — if you have scripts that legitimately spawn many entities
  fast (e.g. a car-meet spawner), raise the limits or whitelist those models.
- **`invisible`** is `log` by default because some cutscene/stealth scripts hide
  the ped locally.

## Limitations (be honest with yourself)

- Client checks (`godMode`, `noclip`, `invisible`) can be bypassed by an injector
  that also patches the getters. The heartbeat catches a *disabled* client
  script, but not a perfectly spoofed one. Treat these as an early-warning layer.
- Event-flood guards run **alongside** the owning resource's handler; they can't
  stop the first few triggers, only detect the flood and punish quickly. The real
  fix for event abuse is server-side validation inside each of your resources
  (ownership checks, cooldowns, permission checks).
- `explosionEvent`, `weaponDamageEvent`, `entityCreating` cancellation is fully
  authoritative and does block the action.
