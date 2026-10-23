--[[
    ╔══════════════════════════════════════════════════╗
    ║       qxell ANTICHEAT - SERVER/DETECTIONS.LUA    ║
    ║   Weapon, vehicle, entity, money checks          ║
    ╚══════════════════════════════════════════════════╝
--]]

-- ─────────────────────────────────────────────
-- STATE TABLES
-- ─────────────────────────────────────────────

-- Inventar de arme autorizat: [playerId] = { [weaponHash] = ammo }
local AuthorizedWeapons = {}

-- Vehicule spawnable per player: [playerId] = { [netId] = timestamp }
local PlayerVehicles    = {}

-- Obiecte spawnable per player: [playerId] = { [netId] = timestamp }
local PlayerObjects     = {}

-- Cooldown tranzacții: [playerId] = timestamp ultimei tranzacții
local TransactionCooldown = {}

-- ─────────────────────────────────────────────
-- HELPER: hash string → number (pentru weapon hash compare)
-- ─────────────────────────────────────────────
local function IsWeaponBlacklisted(weaponHash)
    for _, bHash in ipairs(Config.Weapons.BlacklistedWeapons) do
        if bHash == weaponHash then return true end
    end
    return false
end

local function IsVehicleBlacklisted(modelHash)
    for _, bHash in ipairs(Config.Vehicles.BlacklistedModels) do
        if bHash == modelHash then return true end
    end
    return false
end

local function DebugLog(msg)
    if Config.Debug then
        print('^3[qxellAC Detections]^7 ' .. tostring(msg))
    end
end

-- ─────────────────────────────────────────────
-- WEAPON CHECKS
-- ─────────────────────────────────────────────

-- Clientul raportează lista curentă de arme din mâna lui
RegisterNetEvent('KiroAC:Server:SyncWeapons', function(weaponList)
    local src = source
    if not src or type(weaponList) ~= 'table' then return end

    local ok, reason = exports['kiro_anticheat']:CheckRateLimit(src)
    if not ok then
        TriggerEvent('KiroAC:Server:KickPlayer', src, reason)
        return
    end

    for _, weapon in ipairs(weaponList) do
        local wHash = weapon.hash
        local ammo  = tonumber(weapon.ammo) or 0

        -- 1. Armă pe blacklist
        if IsWeaponBlacklisted(wHash) then
            DebugLog(('Armă blacklistată la %s: hash=%s'):format(
                GetPlayerName(src), tostring(wHash)))
            -- Forțează ștergerea armei la client
            TriggerClientEvent('KiroAC:Client:RemoveWeapon', src, wHash)
            exports['kiro_anticheat']:AddStrike(src,
                ('BLACKLISTED_WEAPON (%s)'):format(tostring(wHash)), 3)
            return
        end

        -- 2. Armă ce nu e în inventarul autorizat
        if AuthorizedWeapons[src] then
            if not AuthorizedWeapons[src][wHash] then
                DebugLog(('Armă neautorizată la %s: hash=%s'):format(
                    GetPlayerName(src), tostring(wHash)))
                TriggerClientEvent('KiroAC:Client:RemoveWeapon', src, wHash)
                exports['kiro_anticheat']:AddStrike(src,
                    ('UNAUTHORIZED_WEAPON (%s)'):format(tostring(wHash)), 2)
                return
            end

            -- 3. Anti-Infinite Ammo: ammo mai mare decât cea autorizată + buffer
            if Config.Weapons.InfiniteAmmoEnabled then
                local authAmmo = AuthorizedWeapons[src][wHash] or 0
                local maxAmmo  = authAmmo + 50  -- buffer de toleranță
                if ammo > maxAmmo and ammo > 9999 then
                    DebugLog(('InfiniteAmmo la %s: hash=%s ammo=%d'):format(
                        GetPlayerName(src), tostring(wHash), ammo))
                    TriggerClientEvent('KiroAC:Client:SetAmmo', src, wHash, authAmmo)
                    exports['kiro_anticheat']:AddStrike(src,
                        ('INFINITE_AMMO (%s, %d rounds)'):format(
                            tostring(wHash), ammo), 2)
                end
            end
        end
    end
end)

-- Server autorizează o armă pentru un jucător (apelat de frameworkul tău la give weapon)
RegisterNetEvent('KiroAC:Server:AuthorizeWeapon', function(targetId, weaponHash, ammo)
    local src = source
    -- Doar serverul sau adminii pot autoriza arme
    if src ~= 0 and not IsPlayerAceAllowed(src, Config.AdminPermission) then return end
    if not AuthorizedWeapons[targetId] then
        AuthorizedWeapons[targetId] = {}
    end
    AuthorizedWeapons[targetId][weaponHash] = tonumber(ammo) or 0
    DebugLog(('Armă autorizată pentru %s: hash=%s ammo=%d'):format(
        tostring(targetId), tostring(weaponHash), ammo or 0))
end)

-- Server revocă o armă din inventarul autorizat (la remove weapon)
RegisterNetEvent('KiroAC:Server:RevokeWeapon', function(targetId, weaponHash)
    local src = source
    if src ~= 0 and not IsPlayerAceAllowed(src, Config.AdminPermission) then return end
    if AuthorizedWeapons[targetId] then
        AuthorizedWeapons[targetId][weaponHash] = nil
    end
end)

-- ─────────────────────────────────────────────
-- VEHICLE CHECKS
-- ─────────────────────────────────────────────

-- Clientul raportează că a spawnat un vehicul
RegisterNetEvent('KiroAC:Server:ReportVehicleSpawn', function(netId, modelHash)
    local src = source
    if not src then return end

    local ok, reason = exports['kiro_anticheat']:CheckRateLimit(src)
    if not ok then
        TriggerEvent('KiroAC:Server:KickPlayer', src, reason)
        return
    end

    -- 1. Vehicul pe blacklist
    if Config.Vehicles.AntiSpawn and IsVehicleBlacklisted(modelHash) then
        DebugLog(('Vehicul blacklistat spawnat de %s: model=%s'):format(
            GetPlayerName(src), tostring(modelHash)))
        -- Șterge entitatea din lume
        local entity = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
        exports['kiro_anticheat']:AddStrike(src,
            ('BLACKLISTED_VEHICLE (%s)'):format(tostring(modelHash)), 3)
        return
    end

    -- 2. Limită de vehicule per jucător
    if not PlayerVehicles[src] then
        PlayerVehicles[src] = {}
    end

    -- Curăță vehiculele dispărute
    for vNetId, _ in pairs(PlayerVehicles[src]) do
        local ent = NetworkGetEntityFromNetworkId(vNetId)
        if not DoesEntityExist(ent) then
            PlayerVehicles[src][vNetId] = nil
        end
    end

    local vehicleCount = 0
    for _ in pairs(PlayerVehicles[src]) do vehicleCount = vehicleCount + 1 end

    if vehicleCount >= Config.Vehicles.MaxVehiclesPerPlayer then
        DebugLog(('VehicleSpam: %s are deja %d vehicule'):format(
            GetPlayerName(src), vehicleCount))
        local entity = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(entity) then DeleteEntity(entity) end
        exports['kiro_anticheat']:AddStrike(src,
            ('VEHICLE_SPAM (%d vehicule)'):format(vehicleCount + 1), 1)
        return
    end

    PlayerVehicles[src][netId] = os.time()
    DebugLog(('Vehicul înregistrat pentru %s: netId=%d model=%s'):format(
        GetPlayerName(src), netId, tostring(modelHash)))
end)

-- ─────────────────────────────────────────────
-- OBJECT / PED SPAWN CHECKS
-- ─────────────────────────────────────────────

RegisterNetEvent('KiroAC:Server:ReportObjectSpawn', function(netId, modelHash)
    local src = source
    if not src then return end

    local ok, reason = exports['kiro_anticheat']:CheckRateLimit(src)
    if not ok then
        TriggerEvent('KiroAC:Server:KickPlayer', src, reason)
        return
    end

    -- Blacklist check
    for _, bHash in ipairs(Config.Objects.BlacklistedObjects) do
        if bHash == modelHash then
            local entity = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(entity) then DeleteEntity(entity) end
            exports['kiro_anticheat']:AddStrike(src,
                ('BLACKLISTED_OBJECT (%s)'):format(tostring(modelHash)), 2)
            return
        end
    end

    if not PlayerObjects[src] then PlayerObjects[src] = {} end

    -- Curăță obiecte dispărute
    for oNetId, _ in pairs(PlayerObjects[src]) do
        local ent = NetworkGetEntityFromNetworkId(oNetId)
        if not DoesEntityExist(ent) then
            PlayerObjects[src][oNetId] = nil
        end
    end

    local objCount = 0
    for _ in pairs(PlayerObjects[src]) do objCount = objCount + 1 end

    if objCount >= Config.Objects.MaxObjectsPerPlayer then
        local entity = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(entity) then DeleteEntity(entity) end
        exports['kiro_anticheat']:AddStrike(src,
            ('OBJECT_SPAM (%d obiecte)'):format(objCount + 1), 1)
        return
    end

    PlayerObjects[src][netId] = os.time()
end)

-- ─────────────────────────────────────────────
-- ECONOMY / MONEY CHECKS
-- ─────────────────────────────────────────────

-- Frameworkul tău trebuie să apeleze acest event înainte de a da bani/items
-- Ex: TriggerEvent('KiroAC:Server:ValidateTransaction', src, amount, 'cash', callback)
AddEventHandler('KiroAC:Server:ValidateTransaction', function(playerId, amount, itemType, cb)
    -- Valori negative
    if not Config.Economy.AllowNegativeValues and (tonumber(amount) or 0) < 0 then
        DebugLog(('Transaction negativă blocată: %s amount=%s'):format(
            GetPlayerName(playerId), tostring(amount)))
        exports['kiro_anticheat']:AddStrike(playerId,
            ('NEGATIVE_TRANSACTION (%s=%s)'):format(itemType, tostring(amount)), 3)
        if cb then cb(false) end
        return
    end

    -- Valori zero
    if not Config.Economy.AllowZeroValues and (tonumber(amount) or 0) == 0 then
        DebugLog(('Transaction zero blocată: %s'):format(GetPlayerName(playerId)))
        if cb then cb(false) end
        return
    end

    -- Tranzacție prea mare
    if (tonumber(amount) or 0) > Config.Economy.MaxSingleTransaction then
        DebugLog(('Transaction suspectă: %s amount=%s'):format(
            GetPlayerName(playerId), tostring(amount)))
        exports['kiro_anticheat']:AddStrike(playerId,
            ('SUSPICIOUS_TRANSACTION (%s=%s)'):format(itemType, tostring(amount)), 2)
        if cb then cb(false) end
        return
    end

    if cb then cb(true) end
end)

-- ─────────────────────────────────────────────
-- PERIODIC SCAN: Entități orfane (spawned de nimeni)
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(Config.Vehicles.CheckInterval)

        -- Curăță vehiculele jucătorilor deconectați
        for playerId, vehicles in pairs(PlayerVehicles) do
            if not GetPlayerName(playerId) then
                -- Jucătorul s-a deconectat, șterge vehiculele lui
                for vNetId, _ in pairs(vehicles) do
                    local ent = NetworkGetEntityFromNetworkId(vNetId)
                    if DoesEntityExist(ent) then
                        DeleteEntity(ent)
                    end
                end
                PlayerVehicles[playerId] = nil
            end
        end

        -- Curăță obiectele jucătorilor deconectați
        for playerId, objects in pairs(PlayerObjects) do
            if not GetPlayerName(playerId) then
                for oNetId, _ in pairs(objects) do
                    local ent = NetworkGetEntityFromNetworkId(oNetId)
                    if DoesEntityExist(ent) then
                        DeleteEntity(ent)
                    end
                end
                PlayerObjects[playerId] = nil
            end
        end
    end
end)

-- ─────────────────────────────────────────────
-- CLEANUP la disconnect
-- ─────────────────────────────────────────────
AddEventHandler('playerDropped', function()
    local src = source
    AuthorizedWeapons[src]    = nil
    PlayerVehicles[src]       = nil
    PlayerObjects[src]        = nil
    TransactionCooldown[src]  = nil
end)

-- ─────────────────────────────────────────────
-- EXPORT: Autorizează armă din exterior
-- (apelat de framework la give weapon)
-- ─────────────────────────────────────────────
exports('AuthorizeWeapon', function(targetId, weaponHash, ammo)
    if not AuthorizedWeapons[targetId] then
        AuthorizedWeapons[targetId] = {}
    end
    AuthorizedWeapons[targetId][weaponHash] = tonumber(ammo) or 0
end)

exports('RevokeWeapon', function(targetId, weaponHash)
    if AuthorizedWeapons[targetId] then
        AuthorizedWeapons[targetId][weaponHash] = nil
    end
end)

exports('GetAuthorizedWeapons', function(targetId)
    return AuthorizedWeapons[targetId] or {}
end)

print('^2[qxellAC]^7 Server Detections.lua incarcat cu succes.')
