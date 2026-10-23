--[[
    ╔══════════════════════════════════════════════════╗
    ║        qxell ANTICHEAT - SERVER/WEBHOOK.LUA      ║
    ║   Discord logging, embeds, screenshot capture    ║
    ╚══════════════════════════════════════════════════╝
--]]

-- ─────────────────────────────────────────────
-- HELPER: Trimite un request HTTP la Discord
-- ─────────────────────────────────────────────
local function SendWebhook(webhookUrl, payload)
    if not webhookUrl or webhookUrl == '' or webhookUrl:find('WEBHOOK_') then
        if Config.Debug then
            print('^3[qxellAC Webhook]^7 Webhook URL neconfigurat, skip.')
        end
        return
    end

    PerformHttpRequest(webhookUrl, function(statusCode, text, headers)
        if Config.Debug then
            print(('[qxellAC Webhook] Status: %d'):format(statusCode or 0))
        end
    end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json'
    })
end

-- ─────────────────────────────────────────────
-- HELPER: Timestamp curent formatat
-- ─────────────────────────────────────────────
local function GetTimestamp()
    return os.date('%Y-%m-%dT%H:%M:%SZ')
end

-- ─────────────────────────────────────────────
-- HELPER: Formatează identificatorii pentru embed
-- ─────────────────────────────────────────────
local function FormatIdentifiers(ids)
    local lines = {}
    if ids.license  then lines[#lines+1] = '🔑 `' .. ids.license  .. '`' end
    if ids.license2 then lines[#lines+1] = '🔑 `' .. ids.license2 .. '`' end
    if ids.steam    then lines[#lines+1] = '🎮 `' .. ids.steam    .. '`' end
    if ids.discord  then lines[#lines+1] = '💬 `' .. ids.discord  .. '`' end
    if ids.live     then lines[#lines+1] = '🎯 `' .. ids.live     .. '`' end
    if ids.xbl      then lines[#lines+1] = '🎯 `' .. ids.xbl      .. '`' end
    if ids.ip       then lines[#lines+1] = '🌐 `' .. ids.ip       .. '`' end
    if ids.tokens and #ids.tokens > 0 then
        for i, t in ipairs(ids.tokens) do
            lines[#lines+1] = ('🔐 Token%d: `%s`'):format(i, t:sub(1, 30) .. '...')
        end
    end
    return #lines > 0 and table.concat(lines, '\n') or 'N/A'
end

-- ─────────────────────────────────────────────
-- EMBED: BAN
-- ─────────────────────────────────────────────
AddEventHandler('KiroAC:Webhook:SendBan', function(data)
    local payload = {
        username   = Config.WebhookBotName,
        avatar_url = Config.WebhookAvatarUrl,
        embeds     = {{
            title       = '🔨 Jucător BANAT',
            color       = 16711680, -- Roșu
            timestamp   = GetTimestamp(),
            thumbnail   = { url = Config.WebhookAvatarUrl },
            fields      = {
                {
                    name   = '👤 Jucător',
                    value  = '`' .. tostring(data.playerName) .. '`',
                    inline = true
                },
                {
                    name   = '🆔 Ban ID',
                    value  = '`' .. tostring(data.banId) .. '`',
                    inline = true
                },
                {
                    name   = '⚖️ Banat de',
                    value  = '`' .. tostring(data.bannedBy) .. '`',
                    inline = true
                },
                {
                    name   = '📋 Motiv',
                    value  = '```' .. tostring(data.reason) .. '```',
                    inline = false
                },
                {
                    name   = '🗓️ Expiră',
                    value  = data.expireDate and ('`' .. data.expireDate .. '`') or '`Permanent`',
                    inline = true
                },
                {
                    name   = '🔍 Identificatori',
                    value  = FormatIdentifiers(data.ids or {}),
                    inline = false
                },
            },
            footer = {
                text     = 'qxell AntiCheat • ' .. os.date('%d/%m/%Y %H:%M:%S'),
                icon_url = Config.WebhookAvatarUrl
            }
        }}
    }
    SendWebhook(Config.Webhooks.Ban, payload)
end)

-- ─────────────────────────────────────────────
-- EMBED: KICK
-- ─────────────────────────────────────────────
AddEventHandler('KiroAC:Webhook:SendKick', function(data)
    local payload = {
        username   = Config.WebhookBotName,
        avatar_url = Config.WebhookAvatarUrl,
        embeds     = {{
            title     = '👢 Jucător Dat Afară (Kick)',
            color     = 16753920, -- Portocaliu
            timestamp = GetTimestamp(),
            fields    = {
                {
                    name   = '👤 Jucător',
                    value  = '`' .. tostring(data.playerName) .. '`',
                    inline = true
                },
                {
                    name   = '📋 Motiv',
                    value  = '```' .. tostring(data.reason) .. '```',
                    inline = false
                },
                {
                    name   = '🔍 Identificatori',
                    value  = FormatIdentifiers(data.ids or {}),
                    inline = false
                },
            },
            footer = {
                text     = 'qxell AntiCheat • ' .. os.date('%d/%m/%Y %H:%M:%S'),
                icon_url = Config.WebhookAvatarUrl
            }
        }}
    }
    SendWebhook(Config.Webhooks.Kick, payload)
end)

-- ─────────────────────────────────────────────
-- EMBED: DETECȚIE / STRIKE
-- ─────────────────────────────────────────────
AddEventHandler('KiroAC:Webhook:SendDetection', function(data)
    -- Culoare bazată pe numărul de strike-uri
    local color = 16776960 -- Galben (strike 1)
    if (data.strikeCount or 1) >= Config.Strikes.MaxStrikes then
        color = 16711680   -- Roșu (strike final = ban)
    elseif (data.strikeCount or 1) >= 2 then
        color = 16753920   -- Portocaliu (strike 2)
    end

    local payload = {
        username   = Config.WebhookBotName,
        avatar_url = Config.WebhookAvatarUrl,
        embeds     = {{
            title     = '⚠️ Detecție AntiCheat',
            color     = color,
            timestamp = GetTimestamp(),
            fields    = {
                {
                    name   = '👤 Jucător',
                    value  = '`' .. tostring(data.playerName) .. '`',
                    inline = true
                },
                {
                    name   = '📊 Strike-uri',
                    value  = ('`%d / %d`'):format(
                        data.strikeCount or 1, Config.Strikes.MaxStrikes),
                    inline = true
                },
                {
                    name   = '🔎 Detecție',
                    value  = '```' .. tostring(data.reason) .. '```',
                    inline = false
                },
                {
                    name   = '🔍 Identificatori',
                    value  = FormatIdentifiers(data.ids or {}),
                    inline = false
                },
            },
            footer = {
                text     = 'qxell AntiCheat • ' .. os.date('%d/%m/%Y %H:%M:%S'),
                icon_url = Config.WebhookAvatarUrl
            }
        }}
    }
    SendWebhook(Config.Webhooks.Detection, payload)
end)

-- ─────────────────────────────────────────────
-- EMBED: SCREENSHOT primit de la client
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Server:ReceiveScreenshot', function(screenshotUrl, playerName, reason)
    local src = source

    local payload = {
        username   = Config.WebhookBotName,
        avatar_url = Config.WebhookAvatarUrl,
        embeds     = {{
            title     = '📸 Screenshot Jucător Suspect',
            color     = 3447003, -- Albastru
            timestamp = GetTimestamp(),
            image     = { url = screenshotUrl },
            fields    = {
                {
                    name   = '👤 Jucător',
                    value  = '`' .. tostring(playerName or GetPlayerName(src)) .. '`',
                    inline = true
                },
                {
                    name   = '🔎 Motiv Captură',
                    value  = '`' .. tostring(reason or 'Verificare manuală') .. '`',
                    inline = true
                },
                {
                    name   = '🆔 Server ID',
                    value  = '`' .. tostring(src) .. '`',
                    inline = true
                },
            },
            footer = {
                text     = 'qxell AntiCheat • ' .. os.date('%d/%m/%Y %H:%M:%S'),
                icon_url = Config.WebhookAvatarUrl
            }
        }}
    }
    SendWebhook(Config.Webhooks.Screenshot, payload)
end)

-- ─────────────────────────────────────────────
-- EMBED: INFO (mesaje generale)
-- ─────────────────────────────────────────────
AddEventHandler('KiroAC:Webhook:SendInfo', function(message)
    local payload = {
        username   = Config.WebhookBotName,
        avatar_url = Config.WebhookAvatarUrl,
        embeds     = {{
            title       = 'ℹ️ qxellAC Info',
            description = tostring(message),
            color       = 3066993, -- Verde
            timestamp   = GetTimestamp(),
            footer      = {
                text     = 'qxell AntiCheat • ' .. os.date('%d/%m/%Y %H:%M:%S'),
                icon_url = Config.WebhookAvatarUrl
            }
        }}
    }
    SendWebhook(Config.Webhooks.Info, payload)
end)

-- ─────────────────────────────────────────────
-- EMBED: SERVER START
-- ─────────────────────────────────────────────
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= Config.ResourceName then return end
    Wait(2000)
    TriggerEvent('KiroAC:Webhook:SendInfo',
        ('🟢 **qxell AntiCheat** a pornit pe server.\n⏰ Data: `%s`\n📦 Versiune: `6.8.3`'):format(
            os.date('%d/%m/%Y %H:%M:%S')))
end)

-- ─────────────────────────────────────────────
-- CLIENT EVENT: Cerere screenshot de la server
-- Clientul folosește `screenshot-basic` și returnează URL-ul
-- ─────────────────────────────────────────────
-- Clientul apelează KiroAC:Client:TakeScreenshot
-- iar după captură trimite înapoi KiroAC:Server:ReceiveScreenshot
-- (logica completă în client/main.lua)

print('^2[qxellAC]^7 Server Webhook.lua incarcat cu succes.')
