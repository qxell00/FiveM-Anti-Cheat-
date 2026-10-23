--[[
    ╔══════════════════════════════════════════════════╗
    ║        qxell ANTICHEAT - SERVER/MENU.LUA         ║
    ║   Callbacks pentru meniu: players, bans,         ║
    ║   logs, strikes, actions                         ║
    ╚══════════════════════════════════════════════════╝
--]]

-- ─────────────────────────────────────────────
-- HELPER: Verificare acces pe server
-- ─────────────────────────────────────────────
local function DebugLog(msg)
    if Config.Debug then
        print('^3[qxellAC Menu-Server]^7 ' .. tostring(msg))
    end
end

local function HasMenuAccess(playerId)
    -- 1. Verifică Ace Permission (dacă e activat)
    if Config.AdminMenu.AllowByAce then
        if IsPlayerAceAllowed(playerId, Config.AdminPermission) then
            return true
        end
    end

    -- 2. Verifică licența în lista AllowedLicenses
    local playerLicense  = nil
    local playerLicense2 = nil

    for i = 0, GetNumPlayerIdentifiers(playerId) - 1 do
        local id = GetPlayerIdentifier(playerId, i)
        if id then
            if id:sub(1, 8) == 'license:' then
                playerLicense = id
            elseif id:sub(1, 9) == 'license2:' then
                playerLicense2 = id
            end
        end
    end

    for _, allowed in ipairs(Config.AdminMenu.AllowedLicenses) do
        if playerLicense  == allowed then return true end
        if playerLicense2 == allowed then return true end
    end

    return false
end

-- ─────────────────────────────────────────────
-- EVENT: Verificare acces (la apăsarea tastei)
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Menu:CheckAccess', function()
    local src    = source
    local access = HasMenuAccess(src)
    DebugLog(('CheckAccess: %s → %s'):format(GetPlayerName(src), tostring(access)))
    TriggerClientEvent('KiroAC:Menu:AccessResult', src, access)
end)

-- ─────────────────────────────────────────────
-- EVENT: Obține lista jucătorilor online
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Menu:Server:GetPlayers', function()
    local src = source
    if not HasMenuAccess(src) then
        TriggerClientEvent('KiroAC:Menu:Client:PlayersData', src, {})
        return
    end

    local players = {}
    for _, playerId in ipairs(GetPlayers()) do
        local pid = tonumber(playerId)

        -- Colectează identificatori
        local license, discord, steam, ip = nil, nil, nil, nil
        for i = 0, GetNumPlayerIdentifiers(pid) - 1 do
            local id = GetPlayerIdentifier(pid, i)
            if id then
                if     id:sub(1, 8)  == 'license:' then license = id
                elseif id:sub(1, 8)  == 'discord:' then discord = id
                elseif id:sub(1, 6)  == 'steam:'   then steam   = id
                elseif id:sub(1, 3)  == 'ip:'      then ip      = id
                end
            end
        end

        players[#players + 1] = {
            id      = pid,
            name    = GetPlayerName(pid) or 'Unknown',
            ping    = GetPlayerPing(pid),
            license = license,
            discord = discord,
            steam   = steam,
            ip      = ip,
        }
    end

    TriggerClientEvent('KiroAC:Menu:Client:PlayersData', src, players)
    DebugLog(('GetPlayers: trimis %d jucători la %s'):format(#players, GetPlayerName(src)))
end)

-- ─────────────────────────────────────────────
-- EVENT: Ban player din meniu
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Menu:Server:BanPlayer', function(targetId, reason, durationHours)
    local src = source
    if not HasMenuAccess(src) then
        TriggerClientEvent('KiroAC:Menu:Client:Toast', src, 'Acces refuzat.', 'error')
        return
    end
    if not GetPlayerName(targetId) then
        TriggerClientEvent('KiroAC:Menu:Client:Toast', src,
            'Jucătorul nu mai e conectat.', 'warning')
        return
    end

    local expireSeconds = (durationHours and durationHours > 0)
        and (durationHours * 3600) or nil
    local adminName     = GetPlayerName(src) or 'Admin'

    DebugLog(('%s a banat pe %s | Motiv: %s | Durată: %sh'):format(
        adminName, GetPlayerName(targetId), reason, tostring(durationHours)))

    TriggerEvent('KiroAC:Server:BanPlayer', targetId, reason,
        ('Admin: %s'):format(adminName), expireSeconds)

    TriggerClientEvent('KiroAC:Menu:Client:Toast', src,
        ('Jucătorul %s a fost banat.'):format(GetPlayerName(targetId) or targetId),
        'success')
end)

-- ─────────────────────────────────────────────
-- EVENT: Kick player din meniu
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Menu:Server:KickPlayer', function(targetId, reason)
    local src = source
    if not HasMenuAccess(src) then
        TriggerClientEvent('KiroAC:Menu:Client:Toast', src, 'Acces refuzat.', 'error')
        return
    end
    if not GetPlayerName(targetId) then
        TriggerClientEvent('KiroAC:Menu:Client:Toast', src,
            'Jucătorul nu mai e conectat.', 'warning')
        return
    end

    local adminName = GetPlayerName(src) or 'Admin'
    DebugLog(('%s a dat kick la %s | Motiv: %s'):format(
        adminName, GetPlayerName(targetId), reason))

    local fullReason = ('[Admin: %s] %s'):format(adminName, reason)
    TriggerEvent('KiroAC:Server:KickPlayer', targetId, fullReason)

    TriggerClientEvent('KiroAC:Menu:Client:Toast', src,
        ('Jucătorul %s a fost dat afară.'):format(GetPlayerName(targetId) or targetId),
        'success')
end)

-- ─────────────────────────────────────────────
-- EVENT: Unban din meniu
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Menu:Server:Unban', function(banId)
    local src = source
    if not HasMenuAccess(src) then
        TriggerClientEvent('KiroAC:Menu:Client:Toast', src, 'Acces refuzat.', 'error')
        return
    end

    DebugLog(('%s a deblocat ban-ul %s'):format(GetPlayerName(src), banId))
    TriggerEvent('KiroAC:BanSystem:Unban', banId, GetPlayerName(src))

    TriggerClientEvent('KiroAC:Menu:Client:Toast', src,
        ('Unban executat: %s'):format(banId), 'success')
end)

-- ─────────────────────────────────────────────
-- EVENT: Screenshot din meniu
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Menu:Server:Screenshot', function(targetId)
    local src = source
    if not HasMenuAccess(src) then
        TriggerClientEvent('KiroAC:Menu:Client:Toast', src, 'Acces refuzat.', 'error')
        return
    end
    if not GetPlayerName(targetId) then
        TriggerClientEvent('KiroAC:Menu:Client:Toast', src,
            'Jucătorul nu mai e conectat.', 'warning')
        return
    end

    DebugLog(('%s a solicitat screenshot pentru %s'):format(
        GetPlayerName(src), GetPlayerName(targetId)))
    TriggerClientEvent('KiroAC:Client:TakeScreenshot', targetId, true)

    TriggerClientEvent('KiroAC:Menu:Client:Toast', src,
        ('Screenshot solicitat pentru %s'):format(GetPlayerName(targetId)), 'info')
end)

-- ─────────────────────────────────────────────
-- EVENT: Obține ban-uri active din DB
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Menu:Server:GetBans', function()
    local src = source
    if not HasMenuAccess(src) then
        TriggerClientEvent('KiroAC:Menu:Client:BansData', src, {})
        return
    end

    if not Config.Database.Enabled then
        TriggerClientEvent('KiroAC:Menu:Client:BansData', src, {})
        return
    end

    MySQL.query(
        'SELECT ban_id, player_name, reason, banned_by, ban_date, expire_date FROM kiro_bans WHERE active = 1 ORDER BY ban_date DESC LIMIT 100',
        {},
        function(results)
            TriggerClientEvent('KiroAC:Menu:Client:BansData', src, results or {})
            DebugLog(('GetBans: trimis %d ban-uri la %s'):format(
                #(results or {}), GetPlayerName(src)))
        end
    )
end)

-- ─────────────────────────────────────────────
-- EVENT: Obține loguri recente din DB
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Menu:Server:GetLogs', function()
    local src = source
    if not HasMenuAccess(src) then
        TriggerClientEvent('KiroAC:Menu:Client:LogsData', src, {})
        return
    end

    if not Config.Database.Enabled then
        TriggerClientEvent('KiroAC:Menu:Client:LogsData', src, {})
        return
    end

    MySQL.query(
        'SELECT player_name, action, reason, log_date FROM kiro_logs ORDER BY log_date DESC LIMIT 200',
        {},
        function(results)
            TriggerClientEvent('KiroAC:Menu:Client:LogsData', src, results or {})
            DebugLog(('GetLogs: trimis %d loguri la %s'):format(
                #(results or {}), GetPlayerName(src)))
        end
    )
end)

-- ─────────────────────────────────────────────
-- EVENT: Obține strike-urile active (din memorie)
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Menu:Server:GetStrikes', function()
    local src = source
    if not HasMenuAccess(src) then
        TriggerClientEvent('KiroAC:Menu:Client:StrikesData', src, {})
        return
    end

    -- Accesează strike-urile din server/main.lua prin export
    -- Deoarece PlayerStrikes e local în main.lua, folosim un event dedicat
    TriggerEvent('KiroAC:Internal:GetStrikes', function(strikesData)
        TriggerClientEvent('KiroAC:Menu:Client:StrikesData', src, strikesData or {})
    end)
end)

-- ─────────────────────────────────────────────
-- EVENT: Statistici generale
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Menu:Server:GetStats', function()
    local src = source
    if not HasMenuAccess(src) then
        TriggerClientEvent('KiroAC:Menu:Client:StatsData', src, {})
        return
    end

    local playerCount = #GetPlayers()
    local stats = {
        players    = playerCount,
        bans       = 0,
        detections = 0,
    }

    if Config.Database.Enabled then
        MySQL.query('SELECT COUNT(*) as cnt FROM kiro_bans WHERE active = 1', {},
            function(r)
                if r and r[1] then stats.bans = r[1].cnt end
                MySQL.query("SELECT COUNT(*) as cnt FROM kiro_logs WHERE action = 'DETECTION'", {},
                    function(r2)
                        if r2 and r2[1] then stats.detections = r2[1].cnt end
                        TriggerClientEvent('KiroAC:Menu:Client:StatsData', src, stats)
                    end
                )
            end
        )
    else
        TriggerClientEvent('KiroAC:Menu:Client:StatsData', src, stats)
    end
end)

-- ─────────────────────────────────────────────
-- EVENT: Obține propria licență (pentru setup)
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Menu:Server:GetMyId', function()
    local src     = source
    local license = nil

    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id and id:sub(1, 8) == 'license:' then
            license = id
            break
        end
    end

    TriggerClientEvent('KiroAC:Menu:Client:MyId', src, license or 'Licență negăsită')
    DebugLog(('%s și-a cerut licența: %s'):format(GetPlayerName(src), tostring(license)))
end)

-- ─────────────────────────────────────────────
-- INTERNAL: Expune strike-urile pentru meniu
-- (main.lua trebuie să asculte acest event și să răspundă)
-- ─────────────────────────────────────────────
-- Adaugă în server/main.lua:
--
-- AddEventHandler('KiroAC:Internal:GetStrikes', function(cb)
--     local result = {}
--     for playerId, data in pairs(PlayerStrikes) do
--         if GetPlayerName(playerId) then
--             result[#result + 1] = {
--                 id         = playerId,
--                 name       = GetPlayerName(playerId),
--                 count      = data.count,
--                 lastReason = data.lastReason or 'N/A',
--             }
--         end
--     end
--     cb(result)
-- end)
--
-- Și în AddStrike(), adaugă: data.lastReason = reason

print('^2[qxellAC]^7 Server Menu.lua incarcat cu succes.')
