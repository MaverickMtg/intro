-- ==========================================================================
--  qb-anticheat :: client best-effort detections
--  Reports god-mode, noclip and invisibility to the server. These catch the
--  common menu exploits (god mode, noclip, invisible) from cheats like the one
--  this resource defends against. All punishment decisions are made server-side.
-- ==========================================================================

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    Wait(5000) -- let the character finish loading before sampling

    local playerId = PlayerId()

    while true do
        Wait(2500)
        local ped = PlayerPedId()
        if ped and ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then

            -- God mode: player invincibility flag set outside of normal gameplay.
            if Config.Actions.godMode and GetPlayerInvincible(playerId) then
                ReportDetection('godMode', 'GetPlayerInvincible = true', 8000)
            end

            -- Noclip: collisions disabled while on foot.
            if Config.Actions.noclip and GetVehiclePedIsIn(ped, false) == 0 then
                if GetEntityCollisionDisabled(ped) then
                    ReportDetection('noclip', 'entity collision disabled on foot', 8000)
                end
            end

            -- Invisibility: alpha lowered / not visible while alive (log-only by default).
            if Config.Actions.invisible then
                if not IsEntityVisible(ped) or GetEntityAlpha(ped) < 200 then
                    ReportDetection('invisible', ('alpha=%d visible=%s'):format(GetEntityAlpha(ped), tostring(IsEntityVisible(ped))), 10000)
                end
            end
        end
    end
end)
