-- ==========================================================================
--  Discord webhook dispatcher
--  Simple FIFO queue so a burst of detections does not hit Discord's rate
--  limit or block the main thread. Exposes AC.SendWebhook(category, embed).
-- ==========================================================================

AC = AC or {}

local queue = {}

local function resolveUrl(category)
    local url = Config.Webhooks[category]
    if not url or url == '' then
        url = Config.Webhooks.default
    end
    if not url or url == '' then
        return nil
    end
    return url
end

--- Queue a rich embed for Discord.
-- @param category string  key in Config.Webhooks
-- @param title    string
-- @param description string
-- @param fields   table   list of { name=, value=, inline= }
-- @param severity string  'info' | 'warn' | 'ban'
function AC.SendWebhook(category, title, description, fields, severity)
    local url = resolveUrl(category)
    if not url then return end

    local color = Config.WebhookColors[severity or 'info'] or Config.WebhookColors.info

    local embed = {
        {
            title = title,
            description = description or '',
            color = color,
            fields = fields or {},
            footer = {
                text = ('%s Anti-Cheat • %s'):format(Config.ServerName, os.date('%Y-%m-%d %H:%M:%S'))
            }
        }
    }

    queue[#queue + 1] = { url = url, embed = embed }
end

-- Drain the queue with a small delay between sends.
CreateThread(function()
    while true do
        if #queue > 0 then
            local item = table.remove(queue, 1)
            PerformHttpRequest(item.url, function(err)
                if Config.Debug and err ~= 200 and err ~= 204 then
                    print(('[qb-anticheat] webhook http status: %s'):format(tostring(err)))
                end
            end, 'POST', json.encode({
                username    = Config.WebhookBotName,
                avatar_url  = (Config.WebhookAvatar ~= '' and Config.WebhookAvatar) or nil,
                embeds      = item.embed
            }), { ['Content-Type'] = 'application/json' })
            Wait(600)
        else
            Wait(500)
        end
    end
end)
