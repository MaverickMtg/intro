-- ==========================================================================
--  qb-anticheat :: client core
--  Sends the heartbeat used by the server tamper-detection and exposes a
--  throttled reporter for the best-effort client detections.
--
--  NOTE: client-side checks are a *secondary* layer. A sophisticated injector
--  can patch these out, which is exactly why the server also watches for a
--  missing heartbeat (see Config.Heartbeat) and relies on server-authoritative
--  checks (explosions, entities, weapon damage, event flood, teleport).
-- ==========================================================================

local lastReport = {}

--- Throttled report to the server (max 1 per category per `cooldown` ms).
function ReportDetection(category, detail, cooldown)
    cooldown = cooldown or 5000
    local now = GetGameTimer()
    if lastReport[category] and (now - lastReport[category]) < cooldown then
        return
    end
    lastReport[category] = now
    TriggerServerEvent('qb-anticheat:server:report', category, detail)
end

-- Heartbeat: keep proving the client script is alive.
CreateThread(function()
    -- Wait until fully connected/spawned.
    while not NetworkIsSessionStarted() do Wait(500) end
    Wait(2000)
    while true do
        TriggerServerEvent('qb-anticheat:server:heartbeat')
        Wait(Config.Heartbeat.clientInterval)
    end
end)
