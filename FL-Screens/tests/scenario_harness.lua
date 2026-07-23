-- Test harness: loads the REAL FL-Screens client code under stubbed FiveM
-- natives and drives realistic "walk in/out of range" + admin-edit scenarios
-- through it, to verify the DUI/runtime-TXD lifecycle doesn't leak or
-- needlessly re-create the (expensive) embedded browser on every show/hide.
--
-- Run with: lua5.3 tests/scenario_harness.lua   (from the FL-Screens/ dir)

local RES = (os.getenv('FLS_RES') or './')

-- ---- minimal json ----
local function jencode(v)
  local t = type(v)
  if t == 'nil' then return 'null'
  elseif t == 'boolean' then return tostring(v)
  elseif t == 'number' then return tostring(v)
  elseif t == 'string' then return '"' .. v:gsub('"', '\\"') .. '"'
  elseif t == 'table' then
    local isArr = (#v > 0)
    local parts = {}
    if isArr then
      for _, x in ipairs(v) do parts[#parts + 1] = jencode(x) end
      return '[' .. table.concat(parts, ',') .. ']'
    else
      for k, x in pairs(v) do parts[#parts + 1] = '"' .. tostring(k) .. '":' .. jencode(x) end
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

-- ---- cooperative coroutine scheduler (mimics FXServer's Citizen.Wait) ----
local threads = {}
Citizen = {}
function Citizen.CreateThread(fn)
  threads[#threads + 1] = coroutine.create(fn)
end
function Citizen.Wait(ms) coroutine.yield(ms) end

-- Resume every still-alive thread exactly once (i.e. run it until its next
-- Wait(), simulating one native tick across all resource threads).
local function stepAllThreads()
  for i = #threads, 1, -1 do
    local co = threads[i]
    if coroutine.status(co) == 'dead' then
      table.remove(threads, i)
    else
      local ok, err = coroutine.resume(co)
      if not ok then error('thread error: ' .. tostring(err)) end
    end
  end
end

-- Run the scheduler for N "ticks", advancing the clock by dtMs each tick.
local function tick(n, dtMs)
  for _ = 1, (n or 1) do
    stepAllThreads()
    advance(dtMs or 0)
  end
end

-- ---- player / world state ----
local playerCoords
-- Support the `#(a - b)` vector-length idiom used by the real client code.
local vecMeta = {}
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vecMeta) end
vecMeta.__sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
vecMeta.__len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
playerCoords = vector3(0.0, 0.0, 0.0)

function PlayerPedId() return 1 end
function GetEntityCoords(_) return playerCoords end

function GetHashKey(s) return 'HASH_' .. tostring(s) end
function GetCurrentResourceName() return 'FL-Screens' end
function GetResourceState(_) return 'started' end

-- No streamed props in this harness: screens resolve purely via Config.Coords.
function GetClosestObjectOfType() return 0 end
function DoesEntityExist(e) return e ~= 0 and e ~= nil end

-- ---- DUI / texture natives, instrumented with call counters ----
local Counters = {
  CreateDui = 0,
  DestroyDui = 0,
  CreateRuntimeTxd = 0,
  CreateRuntimeTextureFromDuiHandle = 0,
  SetDuiUrl = 0,
  AddReplaceTexture = 0,
  RemoveReplaceTexture = 0,
  SendDuiMessage = 0,
}
local duiUrls = {} -- duiObj -> current url (for assertions)
local duiCreateUrls = {} -- duiObj -> url it was CreateDui()'d with (catches the blank-then-navigate race)
local nextHandle = 1

function CreateRuntimeTxd(_)
  Counters.CreateRuntimeTxd = Counters.CreateRuntimeTxd + 1
  nextHandle = nextHandle + 1
  return nextHandle
end

function CreateDui(url, _, _)
  Counters.CreateDui = Counters.CreateDui + 1
  nextHandle = nextHandle + 1
  local handle = nextHandle
  duiUrls[handle] = url
  duiCreateUrls[handle] = url
  return handle
end

function GetDuiHandle(duiObj) return duiObj end

function CreateRuntimeTextureFromDuiHandle(_, _, _)
  Counters.CreateRuntimeTextureFromDuiHandle = Counters.CreateRuntimeTextureFromDuiHandle + 1
  nextHandle = nextHandle + 1
  return nextHandle
end

function SetDuiUrl(duiObj, url)
  Counters.SetDuiUrl = Counters.SetDuiUrl + 1
  duiUrls[duiObj] = url
end

function DestroyDui(duiObj)
  Counters.DestroyDui = Counters.DestroyDui + 1
  duiUrls[duiObj] = nil
end

function IsDuiAvailable(duiObj) return duiUrls[duiObj] ~= nil end
local lastDuiMessage = nil
function SendDuiMessage(duiObj, msg)
  Counters.SendDuiMessage = Counters.SendDuiMessage + 1
  lastDuiMessage = msg
end

function AddReplaceTexture(_, _, _, _) Counters.AddReplaceTexture = Counters.AddReplaceTexture + 1 end
function RemoveReplaceTexture(_, _) Counters.RemoveReplaceTexture = Counters.RemoveReplaceTexture + 1 end

function SetNuiFocus(_, _) end
function SendNUIMessage(_) end

-- ---- events / commands ----
local handlers = {}
function AddEventHandler(name, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
local commands = {}
function RegisterCommand(name, fn) commands[name] = fn end
local nuiCallbacks = {}
function RegisterNUICallback(name, fn) nuiCallbacks[name] = fn end
function TriggerServerEvent(_, ...) end

local function trigger(name, ...)
  if handlers[name] then for _, fn in ipairs(handlers[name]) do fn(...) end end
end

-- ---- ox_lib stub ----
lib = {
  callback = { await = function() return true end },
  notify = function() end,
}

print('\n=== FL-Screens DUI lifecycle scenario tests ===\n')

-- ---- load config + real client code ----
local function loadRes(path)
  local f = assert(io.open(RES .. path, 'r')); local src = f:read('*a'); f:close()
  local chunk = assert(load(src, '@' .. path))
  chunk()
end
loadRes('Config.lua')
loadRes('Files/Client.lua')

-- Mark screens-data ready & drain the startup threads (permission request,
-- 5s-safety-thread, initial scan-loop bootstrap wait).
trigger('FL-Screens:syncAllScreensData', {})
tick(60, 200) -- drain the "wait up to 8s for ScreensData" + Wait(500) startup

-- ---- test helpers ----
local pass, fail = 0, 0
local function check(cond, msg)
  if cond then
    pass = pass + 1; print('  PASS: ' .. msg)
  else
    fail = fail + 1; print('  FAIL: ' .. msg)
  end
end

-- The lobby screen model in Config.lua has 5 targets and Coords at (3080.36, -873.73, 1924.56), Range 50.
local LOBBY_COORDS = vector3(3080.3606, -873.729858, 1924.5627)
local FAR_COORDS = vector3(0.0, 0.0, 0.0)

local function setPlayerAt(coords) playerCoords = coords end

print('[1] Player walks into screen range -> DUIs created exactly once per target')
setPlayerAt(LOBBY_COORDS)
tick(20, 100) -- run scan loop + let the 1200ms/100ms delayed "send initial state" threads complete
check(Counters.CreateDui == 5, 'CreateDui called exactly once per of the 5 targets (got ' .. Counters.CreateDui .. ')')
check(Counters.CreateRuntimeTxd == 5, 'CreateRuntimeTxd called exactly once per target (got ' .. Counters.CreateRuntimeTxd .. ')')
check(Counters.AddReplaceTexture == 5, 'AddReplaceTexture applied for all 5 targets')
check(Counters.SetDuiUrl == 0, 'no extra SetDuiUrl navigation on first creation (created directly with final URL, no blank-then-navigate race)')
local anyCreatedBlank = false
for _, u in pairs(duiCreateUrls) do
  if u == 'about:blank' then anyCreatedBlank = true end
end
check(not anyCreatedBlank, 'new DUIs were created directly with their real content URL, never with about:blank')
check(Counters.SendDuiMessage >= 5, 'initial playlist/mute/volume state WAS pushed to all 5 newly-created screens (got ' .. Counters.SendDuiMessage .. ')')
local createDuiAfterFirstShow = Counters.CreateDui
local createTxdAfterFirstShow = Counters.CreateRuntimeTxd

print('\n[2] Player walks away -> screens hidden, but NO destroy (no leak), DUI blanked')
setPlayerAt(FAR_COORDS)
tick(2, 3000)
check(Counters.DestroyDui == 0, 'DestroyDui NOT called on hide (browser/TXD kept alive, no leak)')
check(Counters.RemoveReplaceTexture == 5, 'RemoveReplaceTexture called for all 5 targets on hide')
check(Counters.SetDuiUrl >= 5, 'DUIs navigated to about:blank while hidden (SetDuiUrl called)')

print('\n[3] Player walks back into range repeatedly (5x) -> resources REUSED, not recreated')
local sendMessageBeforeReentry = Counters.SendDuiMessage
for i = 1, 5 do
  setPlayerAt(LOBBY_COORDS)
  tick(20, 100)
  setPlayerAt(FAR_COORDS)
  tick(2, 3000)
end
check(Counters.CreateDui == createDuiAfterFirstShow,
  'CreateDui count unchanged after 5 more in/out cycles (still ' .. Counters.CreateDui .. ') -- NO re-creation')
check(Counters.CreateRuntimeTxd == createTxdAfterFirstShow,
  'CreateRuntimeTxd count unchanged after 5 more in/out cycles (still ' .. Counters.CreateRuntimeTxd .. ') -- NO leak')
check(Counters.DestroyDui == 0, 'DestroyDui still never called across repeated show/hide cycles')
check(Counters.SendDuiMessage >= sendMessageBeforeReentry + 5 * 5,
  'screens keep receiving fresh playlist/state pushes on every re-entry, not just the first time (got ' ..
  (Counters.SendDuiMessage - sendMessageBeforeReentry) .. ' new messages across 5 re-entries x 5 targets)')

print('\n[4] Admin changes a shown screen\'s URL -> navigated in place, no CreateDui')
setPlayerAt(LOBBY_COORDS)
tick(2, 3000)
local createDuiBeforeEdit = Counters.CreateDui
local ok, err = pcall(function()
  nuiCallbacks['set-screen-url']({
    key = 'HASH_oaj_trg_pvp_lobby_big_screen_1',
    data = { urls = { { url = 'https://example.com/new-stream' } }, interval = 5000 },
  }, function() end)
end)
check(ok, 'set-screen-url NUI callback executed without error' .. (ok and '' or (': ' .. tostring(err))))
check(Counters.CreateDui == createDuiBeforeEdit, 'Changing a live screen URL did not call CreateDui again (reused existing DUI)')

print('\n[5] A transient error in the scan loop does not permanently freeze all screens')
setPlayerAt(FAR_COORDS)
tick(2, 3000) -- hide everything first
local destroyCountBeforeError = Counters.DestroyDui
local realPlayerPedId = PlayerPedId
PlayerPedId = function() error('simulated native failure') end
setPlayerAt(LOBBY_COORDS)
local ok = pcall(function() tick(2, 3000) end)
check(ok, 'the error inside the scan loop did not propagate out and crash the test/resource')
check(Counters.CreateDui == createDuiAfterFirstShow, 'no screens were (incorrectly) shown while the native call was failing')
PlayerPedId = realPlayerPedId
tick(20, 100) -- next tick: the native works again, scan loop should recover on its own
check(Counters.SendDuiMessage > sendMessageBeforeReentry + 5 * 6,
  'scan loop RECOVERED on the next tick and correctly showed screens again after the transient error')

print('\n[6] Resource stop -> full teardown, all DUIs destroyed exactly once')
trigger('onResourceStop', 'FL-Screens')
check(Counters.DestroyDui == destroyCountBeforeError + 5, 'DestroyDui called exactly once per target on resource stop (got ' .. (Counters.DestroyDui - destroyCountBeforeError) .. ')')

print(('\n=== RESULT: %d passed, %d failed ===\n'):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
