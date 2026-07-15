-- Test harness: loads the REAL qb-anticheat server code under stubbed FiveM
-- natives and drives the attack scenarios from the cheat menu through it.

local RES = (os.getenv('AC_RES') or './') 

-- ---- minimal json ----
local function jencode(v)
  local t = type(v)
  if t == 'nil' then return 'null'
  elseif t == 'boolean' then return tostring(v)
  elseif t == 'number' then return tostring(v)
  elseif t == 'string' then return '"' .. v:gsub('"','\\"') .. '"'
  elseif t == 'table' then
    local isArr = (#v > 0)
    local parts = {}
    if isArr then
      for _, x in ipairs(v) do parts[#parts+1] = jencode(x) end
      return '[' .. table.concat(parts, ',') .. ']'
    else
      for k, x in pairs(v) do parts[#parts+1] = '"'..tostring(k)..'":'..jencode(x) end
      return '{' .. table.concat(parts, ',') .. '}'
    end
  end
  return 'null'
end
json = { encode = jencode, decode = function() return {} end }

-- ---- controllable clock ----
local CLOCK = 0
function GetGameTimer() return CLOCK end
local function advance(ms) CLOCK = CLOCK + ms end

-- ---- FiveM native stubs ----
function joaat(s) local h=0 for i=1,#s do h=(h+string.byte(s,i)) h=(h+(h*1024)) h=h%4294967296 h=(h~ (h//64)) end return h end
_G.CancelEvent_called = false
function CancelEvent() _G.CancelEvent_called = true end
function Wait(_) end
local threads = {}
function CreateThread(fn) threads[#threads+1] = fn end   -- stored, not auto-run
function RegisterCommand() end
local print_orig = print

local players = {}  -- src -> {name=, idents=, coords=, veh=, ace=, invincible=}
function GetPlayerName(src) local p=players[src]; return p and p.name or nil end
function GetPlayers() local t={} for s in pairs(players) do t[#t+1]=tostring(s) end return t end
function GetPlayerPed(src) return players[src] and (1000+src) or 0 end
function GetPlayerIdentifiers(src) return players[src] and players[src].idents or {} end
function GetEntityCoords(_) return {0.0,0.0,0.0} end
function GetVehiclePedIsIn(_) return 0 end
function DoesEntityExist(_) return true end
function IsPlayerAceAllowed(src, ace) local p=players[src]; return p and p.ace==ace or false end
local dropped = {}
function DropPlayer(src, reason) dropped[src]=reason; players[src]=nil end

-- entity stubs
local entModel, entType, entOwner = {}, {}, {}
function GetEntityModel(e) return entModel[e] or 0 end
function GetEntityType(e) return entType[e] or 0 end
function NetworkGetEntityOwner(e) return entOwner[e] or -1 end
local deleted = {}
function DeleteEntity(e) deleted[e]=true end

function LoadResourceFile() return '' end
local savedFiles = {}
function SaveResourceFile(_, name, data) savedFiles[name]=data return true end
function GetCurrentResourceName() return 'qb-anticheat' end
function PerformHttpRequest() end

-- exports['qb-core']:GetCoreObject()
exports = setmetatable({}, { __index = function()
  return { GetCoreObject = function()
    return { Functions = { HasPermission = function() return false end } }
  end }
end })

-- event system
local handlers = {}
function AddEventHandler(name, fn) handlers[name]=handlers[name] or {}; table.insert(handlers[name], fn) end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
source = 0
local function trigger(name, ...)
  _G.CancelEvent_called = false
  if handlers[name] then for _,fn in ipairs(handlers[name]) do fn(...) end end
end

-- ---- load config + real resource code (rewrite `hash` -> joaat('hash')) ----
local function loadRes(path)
  local f = assert(io.open(RES..path,'r')); local src=f:read('*a'); f:close()
  src = src:gsub('`([%w_]+)`', "joaat('%1')")
  local chunk = assert(load(src, '@'..path))
  chunk()
end
loadRes('config.lua')
loadRes('server/webhook.lua')
loadRes('server/bans.lua')
loadRes('server/main.lua')

-- ---- spy on AC.Flag ----
local flags = {}
local realFlag = AC.Flag
AC.Flag = function(src, cat, detail)
  flags[#flags+1] = { src=src, cat=cat, detail=detail }
  return realFlag(src, cat, detail)
end

-- ---- test helpers ----
local pass, fail = 0, 0
local function check(cond, msg)
  if cond then pass=pass+1; print_orig('  PASS: '..msg)
  else fail=fail+1; print_orig('  FAIL: '..msg) end
end
local function countFlags(cat) local n=0 for _,f in ipairs(flags) do if f.cat==cat then n=n+1 end end return n end
local function resetFlags() flags = {} end

local function addPlayer(src, name, ace)
  players[src] = { name=name, idents={'license:'..name, 'discord:'..src}, ace=ace }
end

print_orig('\n=== qb-anticheat runtime scenario tests ===\n')

-- Scenario 1: revive-spam crash (event flood) -> ban
addPlayer(1, 'cheater1')
source = 1
print_orig('[1] Revive-spam crash (hospital:server:RevivePlayer x20 in <10s)')
for i=1,20 do trigger('hospital:server:RevivePlayer') end
check(countFlags('eventFlood') >= 1, 'event flood detected for revive spam')
check(dropped[1] ~= nil, 'cheater1 was banned/dropped by revive-spam flood')

-- Scenario 2: explosion blacklist (boom vehicle = type 4) -> cancel + flag
addPlayer(2, 'cheater2')
resetFlags()
print_orig('\n[2] Boom-vehicle explosion (blacklisted type 4)')
trigger('explosionEvent', '2', { explosionType = 4 })
check(_G.CancelEvent_called == true, 'blacklisted explosion was cancelled')
check(countFlags('explosionSpam') >= 1, 'explosionSpam flagged')

-- Scenario 3: explosion rate limit (non-blacklisted type 0 spam)
addPlayer(3, 'cheater3')
resetFlags()
print_orig('\n[3] Explosion rate limit (type 0 x8, limit=4/10s)')
for i=1,8 do trigger('explosionEvent', '3', { explosionType = 0 }) end
check(countFlags('explosionSpam') >= 1, 'explosion rate limit tripped')

-- Scenario 4: entity/bot flood ("Crasher") -> kick escalates to ban
addPlayer(4, 'cheater4')
resetFlags()
print_orig('\n[4] Bot flood: 20 peds created by one owner (limit 15/10s)')
for i=1,20 do
  local e = 5000+i; entType[e]=1; entOwner[e]=4; entModel[e]=123
  trigger('entityCreated', e)
end
check(countFlags('entitySpam') >= 1, 'entity flood detected')
check(deleted[5001] == true, 'burst entities deleted on flag')

-- Scenario 5: weapon damage exploit (super punch, override 9999)
addPlayer(6, 'cheater6')
resetFlags()
print_orig('\n[5] Super-punch weapon damage override (9999 > maxDamage 250)')
trigger('weaponDamageEvent', '6', { weaponType = joaat('WEAPON_PISTOL'), overrideDefaultDamage = true, weaponDamage = 9999.0 })
check(_G.CancelEvent_called == true, 'over-damage hit cancelled')
check(countFlags('weaponExploit') >= 1, 'weaponExploit flagged')

-- Scenario 6: admin bypass (event flood by admin -> logged, NOT dropped)
addPlayer(7, 'adminGuy', 'qb-anticheat.bypass')
resetFlags()
source = 7
print_orig('\n[6] Admin bypass: admin triggers revive spam -> logged, not punished')
for i=1,20 do trigger('hospital:server:RevivePlayer') end
check(countFlags('eventFlood') >= 1, 'admin action still logged')
check(dropped[7] == nil, 'admin NOT dropped (bypass works)')

-- Scenario 7: normal player under limits -> no flags
addPlayer(8, 'legit')
resetFlags()
source = 8
print_orig('\n[7] Legit player: 2 revives, 1 explosion type0 -> no flags')
trigger('hospital:server:RevivePlayer'); trigger('hospital:server:RevivePlayer')
trigger('explosionEvent', '8', { explosionType = 0 })
check(countFlags('eventFlood') == 0 and countFlags('explosionSpam') == 0, 'no false positive for legit usage')
check(dropped[8] == nil, 'legit player not punished')

print_orig(('\n=== RESULT: %d passed, %d failed ===\n'):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
