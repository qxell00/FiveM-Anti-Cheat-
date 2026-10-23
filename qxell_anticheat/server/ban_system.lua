--[[
    ╔══════════════════════════════════════════════════╗
    ║       qxell  ANTICHEAT - SERVER/BAN_SYSTEM.LUA   ║
    ║   HWID + Multi-Identifier ban, DB storage        ║
    ╚══════════════════════════════════════════════════╝
--]]

-- ─────────────────────────────────────────────
-- CACHE: [identifier] = banRecord
-- Ținut în memorie pentru verificări rapide la join
-- ─────────────────────────────────────────────
local BanCache = {}

local function DebugLog(msg)
    if Config.Debug then
        print('^3[qxellAC BanSystem]^7 ' .. tostring(msg))
    end
end

-- ─────────────────────────────────────────────
-- HELPER: Generează un Ban ID unic
-- ─────────────────────────────────────────────
local function GenerateBanId()
    local chars  = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local result = 'QAC-'
    for i = 1, 8 do
        local idx = math.random(1, #chars)
        result = result .. chars:sub(idx, idx)
    end
    return result
end

-- ─────────────────────────────────────────────
-- HELPER: Colectează toți identificatorii unui player
-- ─────────────────────────────────────────────
local function GetAllIdentifiers(playerId)
    local ids = {
        license   = nil,
        license2  = nil,
        steam     = nil,
        discord   = nil,
        live      = nil,
        xbl       = nil,
        ip        = nil,
        tokens    = {},
    }

    for i = 0, GetNumPlayerIdentifiers(playerId) - 1 do
        local id = GetPlayerIdentifier(playerId, i)
        if id then
            if     id:sub(1, 8)  == 'license:' then ids.license  = id
            elseif id:sub(1, 9)  == 'license2:' then ids.license2 = id
            elseif id:sub(1, 6)  == 'steam:'   then ids.steam    = id
            elseif id:sub(1, 8)  == 'discord:' then ids.discord  = id
            elseif id:sub(1, 5)  == 'live:'    then ids.live     = id
            elseif id:sub(1, 4)  == 'xbl:'     then ids.xbl      = id
            elseif id:sub(1, 3)  == 'ip:'      then ids.ip       = id
            end
        end
    end

    -- Tokens (HWID-like) — pot fi mai mulți
    for i = 0, GetNumPlayerTokens(playerId) - 1 do
        local token = GetPlayerToken(playerId, i)
        if token then
            ids.tokens[#ids.tokens + 1] = token
        end
    end

    return ids
end

-- ─────────────────────────────────────────────
-- HELPER: Construiește un string JSON din identifiers
-- ─────────────────────────────────────────────
local function IdentifiersToJson(ids)
    local t = {}
    if ids.license  then t[#t+1] = '"license":"'  .. ids.license  .. '"' end
    if ids.license2 then t[#t+1] = '"license2":"' .. ids.license2 .. '"' end
    if ids.steam    then t[#t+1] = '"steam":"'    .. ids.steam    .. '"' end
    if ids.discord  then t[#t+1] = '"discord":"'  .. ids.discord  .. '"' end
    if ids.live     then t[#t+1] = '"live":"'     .. ids.live     .. '"' end
    if ids.xbl      then t[#t+1] = '"xbl":"'      .. ids.xbl      .. '"' end
    if ids.ip       then t[#t+1] = '"ip":"'       .. ids.ip       .. '"' end
    if #ids.tokens > 0 then
        t[#t+1] = '"tokens":["' .. table.concat(ids.tokens, '","') .. '"]'
    end
    return '{' .. table.concat(t, ',') .. '}'
end

-- ─────────────────────────────────────────────
-- DB: Creează tabelele dacă nu există
-- ─────────────────────────────────────────────
if Config.Database.Enabled then
    CreateThread(function()
        Wait(1000) -- Așteaptă MySQL să se inițializeze

        MySQL.query([[
            CREATE TABLE IF NOT EXISTS `kiro_bans` (
                `id`            INT AUTO_INCREMENT PRIMARY KEY,
                `ban_id`        VARCHAR(20) NOT NULL UNIQUE,
                `player_name`   VARCHAR(100) NOT NULL,
                `reason`        VARCHAR(500) NOT NULL,
                `banned_by`     VARCHAR(100) NOT NULL DEFAULT 'KiroAC',
                `identifiers`   LONGTEXT NOT NULL,
                `license`       VARCHAR(100) DEFAULT NULL,
                `license2`      VARCHAR(100) DEFAULT NULL,
                `steam`         VARCHAR(100) DEFAULT NULL,
                `discord`       VARCHAR(100) DEFAULT NULL,
                `ip`            VARCHAR(50)  DEFAULT NULL,
                `token1`        VARCHAR(200) DEFAULT NULL,
                `token2`        VARCHAR(200) DEFAULT NULL,
                `token3`        VARCHAR(200) DEFAULT NULL,
                `ban_date`      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `expire_date`   DATETIME DEFAULT NULL,
                `active`        TINYINT(1) NOT NULL DEFAULT 1
            )
        ]])

        MySQL.query([[
            CREATE TABLE IF NOT EXISTS `kiro_logs` (
                `id`            INT AUTO_INCREMENT PRIMARY KEY,
                `player_name`   VARCHAR(100) NOT NULL,
                `identifiers`   LONGTEXT NOT NULL,
                `action`        VARCHAR(50)  NOT NULL,
                `reason`        VARCHAR(500) NOT NULL,
                `coords`        VARCHAR(100) DEFAULT NULL,
                `log_date`      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ]])

        print('^2[qxellAC]^7 Tabele baze de date verificate/create.')

        -- Încarcă ban cache-ul la startup
        MySQL.query('SELECT * FROM kiro_bans WHERE active = 1', {}, function(results)
            if results then
                for _, row in ipairs(results) do
                    -- Indexăm după fiecare identifier pentru lookup rapid
                    if row.license  and row.license  ~= '' then BanCache[row.license]  = row end
                    if row.license2 and row.license2 ~= '' then BanCache[row.license2] = row end
                    if row.steam    and row.steam    ~= '' then BanCache[row.steam]    = row end
                    if row.discord  and row.discord  ~= '' then BanCache[row.discord]  = row end
                    if row.ip       and row.ip       ~= '' then BanCache[row.ip]       = row end
                    if row.token1   and row.token1   ~= '' then BanCache[row.token1]   = row end
                    if row.token2   and row.token2   ~= '' then BanCache[row.token2]   = row end
                    if row.token3   and row.token3   ~= '' then BanCache[row.token3]   = row end
                end
                print('^2[KiroAC]^7 Ban cache încarcat: ' .. #results .. ' ban-uri active.')
            end
        end)
    end)
end

-- ─────────────────────────────────────────────
-- CORE: Banează un jucător
-- ─────────────────────────────────────────────
AddEventHandler('KiroAC:Server:BanPlayer', function(playerId, reason, bannedBy, expireSeconds)
    if not GetPlayerName(playerId) then return end

    local playerName = GetPlayerName(playerId)
    local ids        = GetAllIdentifiers(playerId)
    local banId      = GenerateBanId()
    local idsJson    = IdentifiersToJson(ids)
    local bannedByStr = bannedBy or 'KiroAC_AUTO'

    -- Expire date
    local expireDate = nil
    if expireSeconds and expireSeconds > 0 then
        expireDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + expireSeconds)
    end

    DebugLog(('BAN: %s | Motiv: %s | ID: %s'):format(playerName, reason, banId))

    -- Adaugă în cache imediat
    local banRecord = {
        ban_id      = banId,
        player_name = playerName,
        reason      = reason,
        banned_by   = bannedByStr,
        identifiers = idsJson,
        license     = ids.license,
        license2    = ids.license2,
        steam       = ids.steam,
        discord     = ids.discord,
        ip          = ids.ip,
        token1      = ids.tokens[1],
        token2      = ids.tokens[2],
        token3      = ids.tokens[3],
        active      = 1,
    }

    if ids.license  then BanCache[ids.license]  = banRecord end
    if ids.license2 then BanCache[ids.license2] = banRecord end
    if ids.steam    then BanCache[ids.steam]    = banRecord end
    if ids.discord  then BanCache[ids.discord]  = banRecord end
    if ids.ip       then BanCache[ids.ip]       = banRecord end
    if ids.tokens[1] then BanCache[ids.tokens[1]] = banRecord end
    if ids.tokens[2] then BanCache[ids.tokens[2]] = banRecord end
    if ids.tokens[3] then BanCache[ids.tokens[3]] = banRecord end

    -- Screenshot înainte de ban
    if Config.ScreenshotOnBan then
        TriggerClientEvent('KiroAC:Client:TakeScreenshot', playerId, false)
        Wait(3000) -- Mică pauză pentru screenshot
    end

    -- Kick cu mesaj de ban
    local banMsg = Config.Messages.BanMessage:format(reason, banId)
    DropPlayer(playerId, banMsg)

    -- Salvează în DB (async)
    if Config.Database.Enabled then
        MySQL.insert(
            [[INSERT INTO kiro_bans
                (ban_id, player_name, reason, banned_by, identifiers,
                 license, license2, steam, discord, ip, token1, token2, token3, expire_date)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]],
            {
                banId, playerName, reason, bannedByStr, idsJson,
                ids.license, ids.license2, ids.steam, ids.discord, ids.ip,
                ids.tokens[1], ids.tokens[2], ids.tokens[3],
                expireDate
            }
        )

        -- Log în kiro_logs
        MySQL.insert(
            'INSERT INTO kiro_logs (player_name, identifiers, action, reason) VALUES (?, ?, ?, ?)',
            { playerName, idsJson, 'BAN', reason }
        )
    end

    -- Trimite webhook Discord
    TriggerEvent('KiroAC:Webhook:SendBan', {
        playerName  = playerName,
        reason      = reason,
        banId       = banId,
        bannedBy    = bannedByStr,
        ids         = ids,
        expireDate  = expireDate,
    })
end)

-- ─────────────────────────────────────────────
-- CORE: Log kick în DB
-- ─────────────────────────────────────────────
AddEventHandler('KiroAC:Server:LogKick', function(playerId, reason)
    if not Config.Database.Enabled then return end
    local playerName = GetPlayerName(playerId) or 'Unknown'
    local ids        = GetAllIdentifiers(playerId)
    local idsJson    = IdentifiersToJson(ids)

    MySQL.insert(
        'INSERT INTO kiro_logs (player_name, identifiers, action, reason) VALUES (?, ?, ?, ?)',
        { playerName, idsJson, 'KICK', reason }
    )

    TriggerEvent('KiroAC:Webhook:SendKick', {
        playerName = playerName,
        reason     = reason,
        ids        = ids,
    })
end)

-- ─────────────────────────────────────────────
-- CORE: Log detecție în DB
-- ─────────────────────────────────────────────
AddEventHandler('KiroAC:Server:LogDetection', function(playerId, reason, strikeCount)
    if not Config.Database.Enabled then return end
    local playerName = GetPlayerName(playerId) or 'Unknown'
    local ids        = GetAllIdentifiers(playerId)
    local idsJson    = IdentifiersToJson(ids)

    MySQL.insert(
        'INSERT INTO kiro_logs (player_name, identifiers, action, reason) VALUES (?, ?, ?, ?)',
        { playerName, idsJson, 'DETECTION', reason .. ' (Strike ' .. tostring(strikeCount) .. ')' }
    )

    TriggerEvent('KiroAC:Webhook:SendDetection', {
        playerName  = playerName,
        reason      = reason,
        strikeCount = strikeCount,
        ids         = ids,
    })
end)

-- ─────────────────────────────────────────────
-- UNBAN
-- ─────────────────────────────────────────────
AddEventHandler('KiroAC:BanSystem:Unban', function(banId, adminId)
    if not Config.Database.Enabled then
        print('[qxellAC] Unban: DB dezactivat. Curăță manual.')
        return
    end

    MySQL.query(
        'SELECT * FROM kiro_bans WHERE ban_id = ? AND active = 1',
        { banId },
        function(results)
            if not results or #results == 0 then
                print('[qxellAC] Ban ID ' .. tostring(banId) .. ' nu a fost găsit sau deja inactiv.')
                return
            end

            local row = results[1]
            MySQL.update(
                'UPDATE kiro_bans SET active = 0 WHERE ban_id = ?',
                { banId }
            )

            -- Curăță cache-ul
            if row.license  then BanCache[row.license]  = nil end
            if row.license2 then BanCache[row.license2] = nil end
            if row.steam    then BanCache[row.steam]    = nil end
            if row.discord  then BanCache[row.discord]  = nil end
            if row.ip       then BanCache[row.ip]       = nil end
            if row.token1   then BanCache[row.token1]   = nil end
            if row.token2   then BanCache[row.token2]   = nil end
            if row.token3   then BanCache[row.token3]   = nil end

            print(('[qxellAC] Unban executat: %s (de admin ID %s)'):format(banId, tostring(adminId)))

            TriggerEvent('KiroAC:Webhook:SendInfo',
                ('✅ Unban executat: **%s** | Jucător: %s | Admin: %s'):format(
                    banId, row.player_name, tostring(adminId)))
        end
    )
end)

-- ─────────────────────────────────────────────
-- VERIFICARE BAN LA CONECTARE
-- ─────────────────────────────────────────────
AddEventHandler('playerConnecting', function(playerName, setKickReason, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)
    deferrals.update('Se verifică ban-ul...')

    -- Colectează identificatorii
    local identifiers = {}
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id then identifiers[#identifiers + 1] = id end
    end
    local tokens = {}
    for i = 0, GetNumPlayerTokens(src) - 1 do
        local t = GetPlayerToken(src, i)
        if t then tokens[#tokens + 1] = t end
    end

    -- Verifică cache mai întâi (rapid)
    local function CheckCache()
        for _, id in ipairs(identifiers) do
            if BanCache[id] then return BanCache[id] end
        end
        for _, t in ipairs(tokens) do
            if BanCache[t] then return BanCache[t] end
        end
        return nil
    end

    local cachedBan = CheckCache()
    if cachedBan then
        local banMsg = Config.Messages.BanMessage:format(
            cachedBan.reason, cachedBan.ban_id)
        deferrals.done(banMsg)
        DebugLog(('Conectare blocată (cache): %s - BanID: %s'):format(
            playerName, cachedBan.ban_id))
        return
    end

    -- Verifică DB (dacă cache-ul e gol la startup)
    if Config.Database.Enabled then
        local searchIds = {}
        for _, id in ipairs(identifiers) do searchIds[#searchIds + 1] = id end
        for _, t in ipairs(tokens)      do searchIds[#searchIds + 1] = t end

        if #searchIds == 0 then
            deferrals.done()
            return
        end

        -- Construiește placeholders
        local placeholders = {}
        for _ in ipairs(searchIds) do placeholders[#placeholders + 1] = '?' end
        local ph = table.concat(placeholders, ',')

        local query = ([[
            SELECT * FROM kiro_bans
            WHERE active = 1
            AND (
                license  IN (%s) OR license2 IN (%s) OR steam IN (%s) OR
                discord  IN (%s) OR ip IN (%s) OR
                token1   IN (%s) OR token2 IN (%s) OR token3 IN (%s)
            )
            LIMIT 1
        ]]):format(ph, ph, ph, ph, ph, ph, ph, ph)

        -- Repetăm parametrii de 8 ori (câte unul per coloană)
        local params = {}
        for _ = 1, 8 do
            for _, id in ipairs(searchIds) do
                params[#params + 1] = id
            end
        end

        MySQL.query(query, params, function(results)
            if results and #results > 0 then
                local row    = results[1]
                -- Adaugă în cache
                if row.license  then BanCache[row.license]  = row end
                if row.license2 then BanCache[row.license2] = row end
                if row.steam    then BanCache[row.steam]    = row end
                if row.discord  then BanCache[row.discord]  = row end
                if row.ip       then BanCache[row.ip]       = row end
                if row.token1   then BanCache[row.token1]   = row end
                if row.token2   then BanCache[row.token2]   = row end
                if row.token3   then BanCache[row.token3]   = row end

                local banMsg = Config.Messages.BanMessage:format(row.reason, row.ban_id)
                deferrals.done(banMsg)
                DebugLog(('Conectare blocată (DB): %s - BanID: %s'):format(
                    playerName, row.ban_id))
            else
                deferrals.done()
            end
        end)
    else
        -- Fără DB, doar cache
        deferrals.done()
    end
end)

-- ─────────────────────────────────────────────
-- VERIFICARE BAN-URI EXPIRATE (la fiecare oră)
-- ─────────────────────────────────────────────
if Config.Database.Enabled then
    CreateThread(function()
        while true do
            Wait(3600000) -- 1 oră
            MySQL.query(
                'SELECT ban_id, license, license2, steam, discord, ip, token1, token2, token3 FROM kiro_bans WHERE active = 1 AND expire_date IS NOT NULL AND expire_date <= NOW()',
                {},
                function(results)
                    if not results or #results == 0 then return end
                    for _, row in ipairs(results) do
                        MySQL.update('UPDATE kiro_bans SET active = 0 WHERE ban_id = ?', { row.ban_id })
                        if row.license  then BanCache[row.license]  = nil end
                        if row.license2 then BanCache[row.license2] = nil end
                        if row.steam    then BanCache[row.steam]    = nil end
                        if row.discord  then BanCache[row.discord]  = nil end
                        if row.ip       then BanCache[row.ip]       = nil end
                        if row.token1   then BanCache[row.token1]   = nil end
                        if row.token2   then BanCache[row.token2]   = nil end
                        if row.token3   then BanCache[row.token3]   = nil end
                    end
                    print(('[qxellAC] %d ban-uri expirate dezactivate.'):format(#results))
                end
            )
        end
    end)
end

print('^2[qxellAC]^7 Server BanSystem.lua incarcat cu succes.')
