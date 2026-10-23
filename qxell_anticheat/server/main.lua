--[[
    ╔══════════════════════════════════════════════════╗
    ║         qxell ANTICHEAT - SERVER/MAIN.LUA        ║
    ║   Core logic: rate limiting, strikes, sync       ║
    ╚══════════════════════════════════════════════════╝
--]]

-- ─────────────────────────────────────────────
-- STATE TABLES
-- ─────────────────────────────────────────────

-- Strikes per player:  [playerId] = { count, lastReset }
local PlayerStrikes    = {}

-- Rate limiting:       [playerId] = { perSec, perMin, lastSecReset, lastMinReset }
local RateLimitData    = {}

-- Position snapshots:  [playerId] = { coords, timestamp, inVehicle }
local PosSnapshot      = {}

-- Health snapshots:    [playerId] = { health, armour, timestamp }
local HealthSnapshot   = {}

-- Air-time counter:    [playerId] = seconds_in_air
local AirTime          = {}

-- Jump origin:         [playerId] = z_coordinate
local JumpOrigin       = {}

-- Headshot tracking:   [playerId] = { timestamps = {} }
local HeadshotLog      = {}

-- Damage tracking:     [playerId] = { lastDmg, timestamp }
local DamageLog        = {}

-- ─────────────────────────────────────────────
-- HELPER: Get all player identifiers
-- ─────────────────────────────────────────────
local function GetPlayerIdentifiers(playerId)
    local ids = {}
    for i = 0, GetNumPlayerIdentifiers(playerId) - 1 do
        local id = GetPlayerIdentifier(playerId, i)
        if id then
            ids[#ids + 1] = id
        end
    end
    return ids
end

-- ─────────────────────────────────────────────
-- HELPER: Debug log
-- ─────────────────────────────────────────────
local function DebugLog(msg)
    if Config.Debug then
        print('^3[qxellAC Debug]^7 ' .. tostring(msg))
    end
end

-- ─────────────────────────────────────────────
-- STRIKE SYSTEM
-- ─────────────────────────────────────────────
local function AddStrike(playerId, reason, strikeCount)
    strikeCount = strikeCount or 1
    if not PlayerStrikes[playerId] then
        PlayerStrikes[playerId] = { count = 0, lastReset = os.time() }
    end

    local data = PlayerStrikes[playerId]

    -- Reset strikes după intervalul configurat
    if Config.Strikes.ResetAfter > 0 then
        if (os.time() - data.lastReset) >= Config.Strikes.ResetAfter then
            data.count     = 0
            data.lastReset = os.time()
        end
    end

    data.count = data.count + strikeCount
    data.lastReason = reason  -- Salvat pentru meniu
    DebugLog(('Strike adăugat pentru %s (%d/%d) - %s'):format(
        GetPlayerName(playerId), data.count, Config.Strikes.MaxStrikes, reason))

    -- Trimite webhook de detecție
    TriggerEvent('KiroAC:Server:LogDetection', playerId, reason, data.count)

    -- Avertisment pe chat (opțional)
    if Config.Strikes.Enabled and data.count < Config.Strikes.MaxStrikes then
        local warnMsg = Config.Messages.WarnMessage:format(
            data.count, Config.Strikes.MaxStrikes, reason)
        TriggerClientEvent('chat:addMessage', playerId, {
            color   = {255, 165, 0},
            args    = {'[qxellAC]', warnMsg}
        })
    end

    -- Acțiune finală la atingerea limitei
    if data.count >= Config.Strikes.MaxStrikes then
        local action = Config.Strikes.StrikeAction
        if action == 'ban' then
            TriggerEvent('KiroAC:Server:BanPlayer', playerId, reason, 'STRIKE_SYSTEM')
        elseif action == 'kick' then
            TriggerEvent('KiroAC:Server:KickPlayer', playerId, reason)
        end
    end
end
exports('AddStrike', AddStrike)

-- ─────────────────────────────────────────────
-- KICK
-- ─────────────────────────────────────────────
AddEventHandler('KiroAC:Server:KickPlayer', function(playerId, reason)
    if not GetPlayerName(playerId) then return end
    local msg = Config.Messages.KickMessage:format(reason)
    DropPlayer(playerId, msg)
    TriggerEvent('KiroAC:Server:LogKick', playerId, reason)
    DebugLog(('Kick: %s - %s'):format(GetPlayerName(playerId), reason))
end)

-- ─────────────────────────────────────────────
-- RATE LIMITING
-- ─────────────────────────────────────────────
local function CheckRateLimit(playerId)
    local now = os.time()
    if not RateLimitData[playerId] then
        RateLimitData[playerId] = {
            perSec      = 0,
            perMin      = 0,
            lastSecReset = now,
            lastMinReset = now,
        }
    end
    local d = RateLimitData[playerId]

    if (now - d.lastSecReset) >= 1 then
        d.perSec      = 0
        d.lastSecReset = now
    end
    if (now - d.lastMinReset) >= 60 then
        d.perMin      = 0
        d.lastMinReset = now
    end

    d.perSec = d.perSec + 1
    d.perMin = d.perMin + 1

    if d.perSec > Config.RateLimit.MaxEventsPerSecond then
        DebugLog(('RateLimit /sec depășit: %s (%d eps)'):format(
            GetPlayerName(playerId), d.perSec))
        return false, 'EVENT_SPAM_PER_SECOND'
    end
    if d.perMin > Config.RateLimit.MaxEventsPerMinute then
        DebugLog(('RateLimit /min depășit: %s (%d epm)'):format(
            GetPlayerName(playerId), d.perMin))
        return false, 'EVENT_SPAM_PER_MINUTE'
    end
    return true, nil
end
exports('CheckRateLimit', CheckRateLimit)

-- ─────────────────────────────────────────────
-- EVENT: Client raportează date de mișcare
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Server:SyncPosition', function(data)
    local src = source
    if not src or not data then return end

    -- Rate limit
    local ok, reason = CheckRateLimit(src)
    if not ok then
        TriggerEvent('KiroAC:Server:KickPlayer', src, reason)
        return
    end

    local now = os.time()

    -- Anti-Teleport
    if Config.Teleport.Enabled and PosSnapshot[src] then
        local prev    = PosSnapshot[src]
        local elapsed = now - prev.timestamp
        if elapsed > 0 and elapsed <= 2 then
            local dist   = #(vector3(data.x, data.y, data.z) -
                             vector3(prev.x, prev.y, prev.z))
            local limit  = data.inVehicle and Config.Teleport.MaxVehicleDist
                                           or Config.Teleport.MaxDistance
            if dist > limit then
                DebugLog(('Anti-Teleport: %s dist=%.1f limit=%.1f'):format(
                    GetPlayerName(src), dist, limit))
                AddStrike(src, ('TELEPORT (%.0fm)'):format(dist),
                          Config.Teleport.Strikes)
            end
        end
    end

    -- Anti-Speedhack (pe jos)
    if Config.SpeedHack.Enabled and not data.inVehicle then
        local speed = data.speed or 0
        if speed > Config.SpeedHack.MaxOnFootSpeed then
            DebugLog(('Anti-SpeedHack (ped): %s speed=%.2f'):format(
                GetPlayerName(src), speed))
            AddStrike(src, ('SPEEDHACK_FOOT (%.1f m/s)'):format(speed),
                      Config.SpeedHack.Strikes)
        end
    end

    -- Anti-Speedhack (vehicul)
    if Config.SpeedHack.Enabled and data.inVehicle then
        local speed = data.speed or 0
        if speed > Config.SpeedHack.MaxVehicleSpeed then
            DebugLog(('Anti-SpeedHack (veh): %s speed=%.2f'):format(
                GetPlayerName(src), speed))
            AddStrike(src, ('SPEEDHACK_VEHICLE (%.1f m/s)'):format(speed),
                      Config.SpeedHack.Strikes)
        end
    end

    -- Anti-Fly / Noclip (air time tracking)
    if Config.NoClip.Enabled and not data.inVehicle and not data.inParachute then
        if data.zAboveGround and data.zAboveGround > Config.NoClip.MinAltitudeCheck then
            AirTime[src] = (AirTime[src] or 0) + elapsed
            if AirTime[src] >= Config.NoClip.MaxAirTime then
                DebugLog(('Anti-Fly: %s airtime=%.1fs'):format(
                    GetPlayerName(src), AirTime[src]))
                AddStrike(src, ('NOCLIP_FLY (%.1fs aer)'):format(AirTime[src]),
                          Config.NoClip.Strikes)
                AirTime[src] = 0  -- reset după strike
            end
        else
            AirTime[src] = 0
        end
    else
        AirTime[src] = 0
    end

    -- Salvează snapshot
    PosSnapshot[src] = {
        x         = data.x,
        y         = data.y,
        z         = data.z,
        timestamp = now,
        inVehicle = data.inVehicle,
    }
end)

-- ─────────────────────────────────────────────
-- EVENT: Client raportează date de health
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Server:SyncHealth', function(data)
    local src = source
    if not src or not data then return end

    local ok, reason = CheckRateLimit(src)
    if not ok then
        TriggerEvent('KiroAC:Server:KickPlayer', src, reason)
        return
    end

    if Config.Godmode.Enabled then
        if data.health and data.health > Config.Godmode.MaxHealth then
            DebugLog(('Godmode/HealthHack: %s hp=%.0f'):format(
                GetPlayerName(src), data.health))
            AddStrike(src, ('GODMODE_HEALTH (%.0f hp)'):format(data.health),
                      Config.Godmode.Strikes)
        end
        if data.armour and data.armour > Config.Godmode.MaxArmour then
            DebugLog(('Armour Hack: %s armour=%.0f'):format(
                GetPlayerName(src), data.armour))
            AddStrike(src, ('GODMODE_ARMOUR (%.0f armour)'):format(data.armour),
                      Config.Godmode.Strikes)
        end
    end

    HealthSnapshot[src] = {
        health    = data.health,
        armour    = data.armour,
        timestamp = os.time(),
    }
end)

-- ─────────────────────────────────────────────
-- EVENT: Client raportează super jump
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Server:ReportSuperJump', function(height)
    local src = source
    if not src then return end
    if Config.SuperJump.Enabled and height > Config.SuperJump.MaxJumpHeight then
        DebugLog(('SuperJump: %s height=%.1f'):format(GetPlayerName(src), height))
        AddStrike(src, ('SUPER_JUMP (%.1fm)'):format(height),
                  Config.SuperJump.Strikes)
    end
end)

-- ─────────────────────────────────────────────
-- EVENT: Client raportează invisible/alpha
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Server:ReportInvisible', function(alpha)
    local src = source
    if not src then return end
    if Config.Invisible.Enabled and alpha < Config.Invisible.MinAlpha then
        DebugLog(('Invisible: %s alpha=%d'):format(GetPlayerName(src), alpha))
        AddStrike(src, ('INVISIBLE_ALPHA (%d)'):format(alpha),
                  Config.Invisible.Strikes)
    end
end)

-- ─────────────────────────────────────────────
-- EVENT: Client raportează spectate neautorizat
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Server:ReportSpectate', function()
    local src = source
    if not src then return end
    if Config.Spectate.Enabled then
        -- Verifică dacă are permisiune de admin
        if not IsPlayerAceAllowed(src, Config.AdminPermission) then
            DebugLog(('Spectate neautorizat: %s'):format(GetPlayerName(src)))
            AddStrike(src, 'SPECTATE_UNAUTHORIZED', Config.Spectate.Strikes)
        end
    end
end)

-- ─────────────────────────────────────────────
-- EVENT: Client raportează freecam
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Server:ReportFreecam', function(dist)
    local src = source
    if not src then return end
    if Config.FreeCam.Enabled then
        if not IsPlayerAceAllowed(src, Config.AdminPermission) then
            DebugLog(('FreeCam: %s dist=%.1f'):format(GetPlayerName(src), dist))
            AddStrike(src, ('FREECAM (dist=%.1f)'):format(dist),
                      Config.FreeCam.Strikes)
        end
    end
end)

-- ─────────────────────────────────────────────
-- EVENT: Client raportează aimbot/headshot suspect
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Server:ReportHeadshot', function()
    local src = source
    if not src then return end
    if not Config.Aimbot.Enabled then return end

    local now = os.time()
    if not HeadshotLog[src] then
        HeadshotLog[src] = { timestamps = {}, kills = 0 }
    end
    local log = HeadshotLog[src]
    log.kills = log.kills + 1
    log.timestamps[#log.timestamps + 1] = now

    -- Curăță timestamps vechi
    local window  = Config.Aimbot.HeadshotWindowSeconds
    local cleaned = {}
    for _, t in ipairs(log.timestamps) do
        if (now - t) <= window then
            cleaned[#cleaned + 1] = t
        end
    end
    log.timestamps = cleaned

    if log.kills >= Config.Aimbot.MinKillsForCheck then
        if #log.timestamps >= Config.Aimbot.MaxHeadshotsInWindow then
            DebugLog(('Aimbot suspect: %s - %d headshots in %ds'):format(
                GetPlayerName(src), #log.timestamps, window))
            AddStrike(src,
                ('AIMBOT_HEADSHOT (%d hs/%ds)'):format(#log.timestamps, window),
                Config.Aimbot.Strikes)
            log.timestamps = {}  -- reset după strike
        end
    end
end)

-- ─────────────────────────────────────────────
-- EVENT: Client raportează daune explozive suspecte
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Server:ReportExplosiveDmg', function(damage, weaponHash)
    local src = source
    if not src then return end
    if Config.ExplosiveBullets.Enabled then
        if damage > Config.ExplosiveBullets.MaxDamagePerHit then
            DebugLog(('ExplosiveBullets: %s dmg=%.0f weapon=%s'):format(
                GetPlayerName(src), damage, tostring(weaponHash)))
            AddStrike(src,
                ('EXPLOSIVE_BULLETS (dmg=%.0f)'):format(damage),
                Config.ExplosiveBullets.Strikes)
        end
    end
end)

-- ─────────────────────────────────────────────
-- EVENT: Client raportează resource stop suspect
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Server:ReportResourceStop', function(resourceName)
    local src = source
    if not src then return end
    DebugLog(('ResourceStop suspect: %s oprit de %s'):format(
        tostring(resourceName), GetPlayerName(src)))
    TriggerEvent('KiroAC:Server:BanPlayer', src,
        ('RESOURCE_STOP (%s)'):format(tostring(resourceName)), 'AUTO_BAN')
end)

-- ─────────────────────────────────────────────
-- EVENT: Client raportează lua injection
-- ─────────────────────────────────────────────
RegisterNetEvent('KiroAC:Server:ReportLuaInjection', function(details)
    local src = source
    if not src then return end
    DebugLog(('LuaInjection: %s - %s'):format(
        GetPlayerName(src), tostring(details)))
    TriggerEvent('KiroAC:Server:BanPlayer', src,
        ('LUA_INJECTION (%s)'):format(tostring(details)), 'AUTO_BAN')
end)

-- ─────────────────────────────────────────────
-- CLEANUP la disconnect
-- ─────────────────────────────────────────────
AddEventHandler('playerDropped', function(reason)
    local src = source
    PlayerStrikes[src]  = nil
    RateLimitData[src]  = nil
    PosSnapshot[src]    = nil
    HealthSnapshot[src] = nil
    AirTime[src]        = nil
    JumpOrigin[src]     = nil
    HeadshotLog[src]    = nil
    DamageLog[src]      = nil
    DebugLog(('Cleanup date player: %s (motiv: %s)'):format(
        tostring(src), tostring(reason)))
end)

-- ─────────────────────────────────────────────
-- INIT: Trimite config relevant la client
-- ─────────────────────────────────────────────
AddEventHandler('playerSpawned', function()
    local src = source
    Wait(2000)  -- Mică întârziere ca clientul să fie gata
    TriggerClientEvent('KiroAC:Client:Init', src, {
        resourceName = Config.ResourceName,
        monitored    = Config.Bypass.MonitoredResources,
    })
end)

-- ─────────────────────────────────────────────
-- ADMIN: Comandă manuală de ban
-- ─────────────────────────────────────────────
RegisterCommand('kac_ban', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, Config.AdminPermission) then
        TriggerClientEvent('chat:addMessage', src, {
            color = {255, 0, 0}, args = {'[qxellAC]', 'Nu ai permisiune.'}
        })
        return
    end
    local targetId = tonumber(args[1])
    local reason   = table.concat(args, ' ', 2) or 'Ban manual de admin'
    if not targetId or not GetPlayerName(targetId) then
        print('[qxellAC] Jucătorul cu ID ' .. tostring(targetId) .. ' nu există.')
        return
    end
    TriggerEvent('KiroAC:Server:BanPlayer', targetId, reason, 'ADMIN_BAN')
end, false)

-- ─────────────────────────────────────────────
-- ADMIN: Comandă unban
-- ─────────────────────────────────────────────
RegisterCommand('qac_unban', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, Config.AdminPermission) then return end
    local banId = args[1]
    if not banId then
        print('[qxellAC] Folosire: /qac_unban <ban_id>')
        return
    end
    TriggerEvent('KiroAC:BanSystem:Unban', banId, src)
end, false)

-- ─────────────────────────────────────────────
-- ADMIN: Screenshot manual
-- ─────────────────────────────────────────────
RegisterCommand('qac_ss', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, Config.AdminPermission) then return end
    local targetId = tonumber(args[1])
    if not targetId or not GetPlayerName(targetId) then return end
    TriggerClientEvent('KiroAC:Client:TakeScreenshot', targetId, true)
    print(('[qxellAC] Screenshot solicitat pentru %s'):format(GetPlayerName(targetId)))
end, false)

-- ─────────────────────────────────────────────
-- INTERNAL: Expune strike-urile active pentru meniu
-- ─────────────────────────────────────────────
AddEventHandler('KiroAC:Internal:GetStrikes', function(cb)
    local result = {}
    for playerId, data in pairs(PlayerStrikes) do
        if GetPlayerName(playerId) then
            result[#result + 1] = {
                id         = playerId,
                name       = GetPlayerName(playerId),
                count      = data.count,
                lastReason = data.lastReason or 'N/A',
            }
        end
    end
    if cb then cb(result) end
end)

print('^2[qxellAC]^7 Server Main.lua incarcat cu succes.')
