--[[
    ╔══════════════════════════════════════════════════╗
    ║         qxell ANTICHEAT - CLIENT/MAIN.LUA        ║
    ║   Movement, godmode, noclip, teleport,           ║
    ║   health, spectate, freecam, screenshot          ║
    ╚══════════════════════════════════════════════════╝
--]]

-- ─────────────────────────────────────────────
-- LOCAL STATE
-- ─────────────────────────────────────────────
local Initialized       = false
local MonitoredResources = {}
local LastPosition      = nil
local LastPositionTime  = 0
local JumpBaseZ         = nil
local IsJumping         = false
local AirTimeCounter    = 0.0
local LastHealth        = 200.0
local LastArmour        = 0.0
local ScreenshotReason  = ''

local function DebugLog(msg)
    if Config.Debug then
        print('^3[qxellAC Client]^7 ' .. tostring(msg))
    end
end

-- ─────────────────────────────────────────────
-- INIT: Primit de la server după spawn
-- ─────────────────────────────────────────────
RegisterNetEvent('qxellAC:Client:Init', function(data)
    if Initialized then return end
    Initialized = true
    MonitoredResources = data.monitored or {}
    DebugLog('Client inițializat. Resurse monitorizate: ' .. #MonitoredResources)
end)

-- ─────────────────────────────────────────────
-- HELPER: Distanța față de sol (ground check)
-- ─────────────────────────────────────────────
local function GetHeightAboveGround(coords)
    local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z, false)
    if found then
        return coords.z - groundZ
    end
    return 0.0
end

-- ─────────────────────────────────────────────
-- HELPER: Jucătorul e într-un vehicul, parașută sau ragdoll
-- ─────────────────────────────────────────────
local function IsPlayerInSpecialState(ped)
    return IsPedInAnyVehicle(ped, false)
        or IsPedFalling(ped)
        or IsPedRagdoll(ped)
        or IsPedInParachuteFreeFall(ped)
        or GetPedParachuteState(ped) ~= -1
end

-- ─────────────────────────────────────────────
-- THREAD: SYNC POZIȚIE cu serverul
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(Config.Teleport.CheckInterval)
        if not Initialized then goto continue end

        local ped    = PlayerPedId()
        if not DoesEntityExist(ped) or IsEntityDead(ped) then goto continue end

        local coords    = GetEntityCoords(ped)
        local vel       = GetEntityVelocity(ped)
        local speed     = math.sqrt(vel.x^2 + vel.y^2 + vel.z^2)
        local inVehicle = IsPedInAnyVehicle(ped, false)
        local inParachute = GetPedParachuteState(ped) ~= -1

        -- Viteză vehicul (din native mai precis)
        if inVehicle then
            local veh = GetVehiclePedIsIn(ped, false)
            speed = GetEntitySpeed(veh)
        end

        local heightAboveGround = GetHeightAboveGround(coords)

        TriggerServerEvent('qxellAC:Server:SyncPosition', {
            x              = coords.x,
            y              = coords.y,
            z              = coords.z,
            speed          = speed,
            inVehicle      = inVehicle,
            inParachute    = inParachute,
            zAboveGround   = heightAboveGround,
        })

        ::continue::
    end
end)

-- ─────────────────────────────────────────────
-- THREAD: SYNC HEALTH cu serverul
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(Config.Godmode.CheckInterval)
        if not Initialized then goto continue end

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) or IsEntityDead(ped) then goto continue end

        local health = GetEntityHealth(ped)
        local armour = GetPedArmour(ped)

        -- Forțează invincibilitate OFF dacă cumva e activată
        if Config.Godmode.Enabled then
            if IsEntityInvincible(ped) then
                SetEntityInvincible(ped, false)
                DebugLog('Godmode dezactivat forțat (invincible flag)')
            end
        end

        -- Dacă HP crește brusc fără să existe motive legitime
        if Config.Godmode.Enabled then
            if health > LastHealth + 50.0 and health > Config.Godmode.MaxHealth then
                DebugLog(('HP sus suspect: %.0f -> %.0f'):format(LastHealth, health))
                TriggerServerEvent('qxellAC:Server:SyncHealth', {
                    health = health,
                    armour = armour,
                })
            end
            if armour > LastArmour + 50.0 and armour > Config.Godmode.MaxArmour then
                DebugLog(('Armour sus suspect: %.0f -> %.0f'):format(LastArmour, armour))
                TriggerServerEvent('qxellAC:Server:SyncHealth', {
                    health = health,
                    armour = armour,
                })
            end
        end

        -- Sync normal
        TriggerServerEvent('qxellAC:Server:SyncHealth', {
            health = health,
            armour = armour,
        })

        LastHealth = health
        LastArmour = armour

        ::continue::
    end
end)

-- ─────────────────────────────────────────────
-- THREAD: ANTI-SUPER JUMP
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(100)
        if not Initialized then goto continue end

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) then goto continue end

        local coords = GetEntityCoords(ped)

        -- Detectează momentul în care jucătorul sare
        if not IsJumping and IsPedJumping(ped) then
            IsJumping  = true
            JumpBaseZ  = coords.z
        end

        -- Dacă sare și a ajuns la înălțime maximă
        if IsJumping and Config.SuperJump.Enabled then
            local jumpHeight = coords.z - (JumpBaseZ or coords.z)
            if jumpHeight > Config.SuperJump.MaxJumpHeight then
                DebugLog(('SuperJump detectat: %.1fm'):format(jumpHeight))
                TriggerServerEvent('qxellAC:Server:ReportSuperJump', jumpHeight)
                IsJumping = false
                JumpBaseZ = nil
            end
        end

        -- Reset când aterizează
        if IsJumping and IsEntityOnGround(ped) and not IsPedJumping(ped) then
            IsJumping = false
            JumpBaseZ = nil
        end

        ::continue::
    end
end)

-- ─────────────────────────────────────────────
-- THREAD: ANTI-INVISIBLE / ALPHA
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(3000)
        if not Initialized then goto continue end
        if not Config.Invisible.Enabled then goto continue end

        local ped   = PlayerPedId()
        if not DoesEntityExist(ped) then goto continue end

        local alpha = GetEntityAlpha(ped)

        if alpha < Config.Invisible.MinAlpha then
            DebugLog(('Alpha suspect: %d'):format(alpha))
            -- Resetează alpha la normal
            ResetEntityAlpha(ped)
            TriggerServerEvent('qxellAC:Server:ReportInvisible', alpha)
        end

        ::continue::
    end
end)

-- ─────────────────────────────────────────────
-- THREAD: ANTI-SPECTATE
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(5000)
        if not Initialized then goto continue end
        if not Config.Spectate.Enabled then goto continue end

        -- Verifică dacă jucătorul e în spectate mode
        -- (camera este atașată la un alt jucător)
        local ped    = PlayerPedId()
        local camEnt = GetCamEffectiveFov(GetRenderingCam())

        if NetworkIsInSpectatorMode() then
            DebugLog('Spectate neautorizat detectat')
            TriggerServerEvent('qxellAC:Server:ReportSpectate')
            -- Ieși din spectate
            NetworkSetInSpectatorMode(false, ped)
        end

        ::continue::
    end
end)

-- ─────────────────────────────────────────────
-- THREAD: ANTI-FREECAM
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(2000)
        if not Initialized then goto continue end
        if not Config.FreeCam.Enabled then goto continue end

        local ped    = PlayerPedId()
        if not DoesEntityExist(ped) then goto continue end

        local pedPos = GetEntityCoords(ped)
        local cam    = GetRenderingCam()

        if DoesCamExist(cam) then
            local camPos = GetCamCoord(cam)
            local dist   = #(vector3(camPos.x, camPos.y, camPos.z) -
                             vector3(pedPos.x, pedPos.y, pedPos.z))

            if dist > Config.FreeCam.MaxCamDistance then
                DebugLog(('FreeCam detectat: dist=%.1f'):format(dist))
                TriggerServerEvent('qxellAC:Server:ReportFreecam', dist)
                -- Distruge camera custom
                DestroyCam(cam, false)
                RenderScriptCams(false, false, 0, true, true)
            end
        end

        ::continue::
    end
end)

-- ─────────────────────────────────────────────
-- THREAD: SYNC ARME cu serverul
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(5000)
        if not Initialized then goto continue end

        local ped        = PlayerPedId()
        if not DoesEntityExist(ped) then goto continue end

        local weaponList = {}

        -- Iterează toate armele posibile și verifică ce are jucătorul
        -- Folosim o listă hardcodată a hash-urilor comune GTA V
        local commonWeapons = {
            `weapon_pistol`, `weapon_pistol_mk2`, `weapon_combatpistol`,
            `weapon_appistol`, `weapon_stungun`, `weapon_flaregun`,
            `weapon_marksman_pistol`, `weapon_revolver`, `weapon_revolver_mk2`,
            `weapon_doubleaction`, `weapon_ceramicpistol`, `weapon_navyrevolver`,
            `weapon_microsmg`, `weapon_smg`, `weapon_smg_mk2`, `weapon_assaultsmg`,
            `weapon_combatpdw`, `weapon_machinepistol`, `weapon_minismg`,
            `weapon_pumpshotgun`, `weapon_pumpshotgun_mk2`, `weapon_sawnoffshotgun`,
            `weapon_assaultshotgun`, `weapon_bullpupshotgun`, `weapon_musket`,
            `weapon_heavyshotgun`, `weapon_dbshotgun`, `weapon_autoshotgun`,
            `weapon_assaultrifle`, `weapon_assaultrifle_mk2`, `weapon_carbinerifle`,
            `weapon_carbinerifle_mk2`, `weapon_advancedrifle`, `weapon_specialcarbine`,
            `weapon_specialcarbine_mk2`, `weapon_bullpuprifle`, `weapon_bullpuprifle_mk2`,
            `weapon_compactrifle`, `weapon_mg`, `weapon_combatmg`, `weapon_combatmg_mk2`,
            `weapon_gusenberg`, `weapon_sniperrifle`, `weapon_heavysniper`,
            `weapon_heavysniper_mk2`, `weapon_marksmanrifle`, `weapon_marksmanrifle_mk2`,
            `weapon_rpg`, `weapon_grenadelauncher`, `weapon_grenadelauncher_smoke`,
            `weapon_minigun`, `weapon_firework`, `weapon_railgun`, `weapon_hominglauncher`,
            `weapon_compactlauncher`, `weapon_emplauncher`,
            `weapon_grenade`, `weapon_bzgas`, `weapon_smokegrenade`,
            `weapon_flare`, `weapon_molotov`, `weapon_stickybomb`,
            `weapon_proxmine`, `weapon_snowball`, `weapon_pipebomb`, `weapon_ball`,
            `weapon_knife`, `weapon_nightstick`, `weapon_hammer`, `weapon_bat`,
            `weapon_golfclub`, `weapon_crowbar`, `weapon_bottle`, `weapon_dagger`,
            `weapon_hatchet`, `weapon_machete`, `weapon_flashlight`, `weapon_switchblade`,
            `weapon_battleaxe`, `weapon_poolcue`, `weapon_wrench`,
            `weapon_unarmed`,
        }

        for _, wHash in ipairs(commonWeapons) do
            if HasPedGotWeapon(ped, wHash, false) then
                local _, ammo = GetAmmoInPed(ped, wHash)
                weaponList[#weaponList + 1] = {
                    hash = wHash,
                    ammo = ammo,
                }
            end
        end

        if #weaponList > 0 then
            TriggerServerEvent('qxellAC:Server:SyncWeapons', weaponList)
        end

        ::continue::
    end
end)

-- ─────────────────────────────────────────────
-- EVENT: Server cere să ștergem o armă
-- ─────────────────────────────────────────────
RegisterNetEvent('qxellAC:Client:RemoveWeapon', function(weaponHash)
    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        RemoveWeaponFromPed(ped, weaponHash)
        DebugLog(('Armă ștearsă: %s'):format(tostring(weaponHash)))
    end
end)

-- ─────────────────────────────────────────────
-- EVENT: Server setează ammo la valoarea autorizată
-- ─────────────────────────────────────────────
RegisterNetEvent('qxellAC:Client:SetAmmo', function(weaponHash, ammo)
    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        SetPedAmmo(ped, weaponHash, ammo)
    end
end)

-- ─────────────────────────────────────────────
-- EVENT: Screenshot solicitat de server
-- Necesită resursa `screenshot-basic`
-- ─────────────────────────────────────────────
RegisterNetEvent('qxellAC:Client:TakeScreenshot', function(isManual)
    ScreenshotReason = isManual and 'Verificare manuală admin' or 'Detecție auto AntiCheat'

    -- Verifică dacă screenshot-basic e disponibil
    if GetResourceState('screenshot-basic') ~= 'started' then
        DebugLog('screenshot-basic nu este pornit, skip screenshot.')
        return
    end

    exports['screenshot-basic']:requestScreenshotUpload(
        Config.Webhooks.Screenshot,
        'files[]',
        {
            encoding   = 'png',
            quality    = 0.85,
        },
        function(data)
            -- data conține URL-ul imaginii uploadate
            local body = json.decode(data)
            if body and body.attachments and body.attachments[1] then
                local imgUrl = body.attachments[1].url
                TriggerServerEvent('qxellAC:Server:ReceiveScreenshot',
                    imgUrl,
                    GetPlayerName(PlayerId()),
                    ScreenshotReason)
                DebugLog('Screenshot trimis: ' .. imgUrl)
            end
        end
    )
end)

-- ─────────────────────────────────────────────
-- THREAD: Raportează spawn vehicul
-- ─────────────────────────────────────────────
local TrackedVehicles = {}

CreateThread(function()
    while true do
        Wait(3000)
        if not Initialized then goto continue end

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) then goto continue end

        -- Scanează entitățile din raza jucătorului
        local coords = GetEntityCoords(ped)

        local vehicles = GetGamePool('CVehicle')
        for _, veh in ipairs(vehicles) do
            if DoesEntityExist(veh) and not IsEntityDead(veh) then
                local owner = NetworkGetEntityOwner(veh)
                if owner == PlayerId() then
                    local netId = VehToNet(veh)
                    if netId and netId ~= 0 and not TrackedVehicles[netId] then
                        TrackedVehicles[netId] = true
                        local model = GetEntityModel(veh)
                        TriggerServerEvent('qxellAC:Server:ReportVehicleSpawn', netId, model)
                    end
                end
            end
        end

        -- Curăță tracked vehicles dispărute
        for netId, _ in pairs(TrackedVehicles) do
            local ent = NetToVeh(netId)
            if not DoesEntityExist(ent) then
                TrackedVehicles[netId] = nil
            end
        end

        ::continue::
    end
end)

-- ─────────────────────────────────────────────
-- THREAD: Raportează spawn obiecte
-- ─────────────────────────────────────────────
local TrackedObjects = {}

CreateThread(function()
    while true do
        Wait(5000)
        if not Initialized then goto continue end

        local objects = GetGamePool('CObject')
        for _, obj in ipairs(objects) do
            if DoesEntityExist(obj) then
                local owner = NetworkGetEntityOwner(obj)
                if owner == PlayerId() then
                    local netId = ObjToNet(obj)
                    if netId and netId ~= 0 and not TrackedObjects[netId] then
                        TrackedObjects[netId] = true
                        local model = GetEntityModel(obj)
                        TriggerServerEvent('qxellAC:Server:ReportObjectSpawn', netId, model)
                    end
                end
            end
        end

        for netId, _ in pairs(TrackedObjects) do
            local ent = NetToObj(netId)
            if not DoesEntityExist(ent) then
                TrackedObjects[netId] = nil
            end
        end

        ::continue::
    end
end)

-- ─────────────────────────────────────────────
-- THREAD: Verifică periodic integritatea ped-ului
-- (godmode flags, task-uri interzise)
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(1000)
        if not Initialized then goto continue end

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) or IsEntityDead(ped) then goto continue end

        -- Resetează invincibilitate dacă e setată
        if Config.Godmode.Enabled and IsEntityInvincible(ped) then
            SetEntityInvincible(ped, false)
            DebugLog('Godmode flag resetat pe client.')
            TriggerServerEvent('qxellAC:Server:SyncHealth', {
                health = GetEntityHealth(ped),
                armour = GetPedArmour(ped),
            })
        end

        -- Resetează super-speed flag
        if Config.SpeedHack.Enabled then
            SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
            SetSwimMultiplierForPlayer(PlayerId(), 1.0)
        end

        ::continue::
    end
end)

print('^2[qxellAC]^7 Client Main.lua incarcat cu succes.')
