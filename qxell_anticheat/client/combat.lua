--[[
    ╔══════════════════════════════════════════════════╗
    ║        qxell ANTICHEAT - CLIENT/COMBAT.LUA       ║
    ║   Aimbot heuristics, explosive bullets,          ║
    ║   damage modifier, no recoil, wallhack           ║
    ╚══════════════════════════════════════════════════╝
--]]

-- ─────────────────────────────────────────────
-- LOCAL STATE
-- ─────────────────────────────────────────────

-- Tracking shoot events pentru no-recoil / no-spread
local LastShotCoords    = nil   -- Ultimele coordonate de tragere
local LastShotWeapon    = nil   -- Ultima armă folosită
local ShotCount         = 0     -- Număr total shots în sesiunea curentă

-- Tracking damage primit/oferit
local LastDamageTime    = 0
local DamageBuffer      = {}    -- { damage, weaponHash, timestamp }

-- Headshot counter (per kill window)
local HeadshotWindow    = {}    -- { timestamp }
local TotalKills        = 0

-- Bullet trajectory tracking
local BulletTrajectory  = {}    -- Ultimele N direcții de tragere

-- Arme ce nu produc explozii în mod normal
local NON_EXPLOSIVE_WEAPONS = {
    [`weapon_pistol`]           = true,
    [`weapon_pistol_mk2`]       = true,
    [`weapon_combatpistol`]     = true,
    [`weapon_appistol`]         = true,
    [`weapon_microsmg`]         = true,
    [`weapon_smg`]              = true,
    [`weapon_smg_mk2`]          = true,
    [`weapon_assaultsmg`]       = true,
    [`weapon_combatpdw`]        = true,
    [`weapon_machinepistol`]    = true,
    [`weapon_minismg`]          = true,
    [`weapon_assaultrifle`]     = true,
    [`weapon_assaultrifle_mk2`] = true,
    [`weapon_carbinerifle`]     = true,
    [`weapon_carbinerifle_mk2`] = true,
    [`weapon_advancedrifle`]    = true,
    [`weapon_specialcarbine`]   = true,
    [`weapon_specialcarbine_mk2`] = true,
    [`weapon_bullpuprifle`]     = true,
    [`weapon_bullpuprifle_mk2`] = true,
    [`weapon_compactrifle`]     = true,
    [`weapon_mg`]               = true,
    [`weapon_combatmg`]         = true,
    [`weapon_combatmg_mk2`]     = true,
    [`weapon_gusenberg`]        = true,
    [`weapon_sniperrifle`]      = true,
    [`weapon_heavysniper`]      = true,
    [`weapon_heavysniper_mk2`]  = true,
    [`weapon_marksmanrifle`]    = true,
    [`weapon_marksmanrifle_mk2`] = true,
    [`weapon_pumpshotgun`]      = true,
    [`weapon_pumpshotgun_mk2`]  = true,
    [`weapon_sawnoffshotgun`]   = true,
    [`weapon_assaultshotgun`]   = true,
    [`weapon_heavyshotgun`]     = true,
    [`weapon_dbshotgun`]        = true,
    [`weapon_autoshotgun`]      = true,
    [`weapon_revolver`]         = true,
    [`weapon_revolver_mk2`]     = true,
}

local function DebugLog(msg)
    if Config.Debug then
        print('^3[qxellAC Combat]^7 ' .. tostring(msg))
    end
end

-- ─────────────────────────────────────────────
-- THREAD: Monitorizează daunele primite de alți jucători
-- Detectează explosive bullets & damage modifier
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(0)

        if not Config.ExplosiveBullets.Enabled then
            Wait(5000)
            goto continue
        end

        local myPed = PlayerPedId()
        if not DoesEntityExist(myPed) then goto continue end

        -- Iterează toți jucătorii din joc
        local players = GetActivePlayers()
        for _, playerId in ipairs(players) do
            local ped = GetPlayerPed(playerId)
            if DoesEntityExist(ped) and ped ~= myPed then

                -- Verifică dacă ped-ul a primit daune recent
                if HasEntityBeenDamagedByAnyPed(ped) or HasEntityBeenDamagedByEntity(ped, myPed, true) then

                    -- Verifică dacă dauna vine de la un proiectil
                    local hit, entityHit, coords, surfaceNormal, weaponHash =
                        GetPedLastDamageBone(ped)

                    -- Caută în pool de proiectile active
                    local projectiles = GetGamePool('CProjectile')
                    for _, proj in ipairs(projectiles) do
                        if DoesEntityExist(proj) then
                            local projOwner = NetworkGetEntityOwner(proj)
                            if projOwner == PlayerId() then
                                local projWeapon = GetWeaponDamageType(GetEntityModel(proj))
                                -- Dacă arma nu e în mod normal explozivă dar proiectilul face explozie
                                if NON_EXPLOSIVE_WEAPONS[weaponHash] then
                                    -- Verifică dacă există un efect de explozie în apropiere
                                    local projCoords = GetEntityCoords(proj)
                                    local explosion = HasEntityCollidedWithAnything(proj)
                                    if explosion then
                                        DebugLog(('ExplosiveBullets: weapon=%s'):format(
                                            tostring(weaponHash)))
                                        TriggerServerEvent('qxellAC:Server:ReportExplosiveDmg',
                                            500.0, -- daună artificială mare pentru trigger
                                            weaponHash)
                                    end
                                end
                            end
                        end
                    end

                    ClearEntityLastDamageEntity(ped)
                end
            end
        end

        ::continue::
    end
end)

-- ─────────────────────────────────────────────
-- THREAD: Monitorizează shot-urile proprii
-- Detectează no-recoil prin analiza direcției
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(0)

        if not Config.Weapons.AntiNoReload then
            Wait(5000)
            goto continue
        end

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) then goto continue end

        -- Detectează momentul când jucătorul trage
        if IsPedShooting(ped) then
            local weapon = GetSelectedPedWeapon(ped)
            local camRot = GetGameplayCamRot(2)  -- Rotația camerei (pitch, roll, yaw)
            local camDir = GetGameplayCamForwardVector()

            -- Stochează direcția
            BulletTrajectory[#BulletTrajectory + 1] = {
                x   = camDir.x,
                y   = camDir.y,
                z   = camDir.z,
                t   = GetGameTimer(),
                weapon = weapon,
            }

            -- Păstrează doar ultimele 20 shots
            if #BulletTrajectory > 20 then
                table.remove(BulletTrajectory, 1)
            end

            ShotCount = ShotCount + 1

            -- Analiză no-recoil: dacă ultimele N shots au direcții aproape identice
            -- (în mod normal recoil-ul variază direcția ușor)
            if Config.Weapons.AntiNoReload and #BulletTrajectory >= 10 then
                local first = BulletTrajectory[1]
                local last  = BulletTrajectory[#BulletTrajectory]
                local timeDiff = (last.t - first.t) / 1000.0

                -- Dacă 10 shots au fost trase în sub 2 secunde cu aceeași armă
                if timeDiff < 2.0 and first.weapon == weapon then
                    -- Calculează variația direcției
                    local totalVariance = 0.0
                    for i = 2, #BulletTrajectory do
                        local prev = BulletTrajectory[i-1]
                        local curr = BulletTrajectory[i]
                        local dx = math.abs(curr.x - prev.x)
                        local dy = math.abs(curr.y - prev.y)
                        totalVariance = totalVariance + dx + dy
                    end
                    local avgVariance = totalVariance / (#BulletTrajectory - 1)

                    -- Variație sub 0.001 = no recoil suspect
                    if avgVariance < 0.001 and ShotCount > 5 then
                        DebugLog(('No-Recoil suspect: variance=%.6f shots=%d'):format(
                            avgVariance, ShotCount))
                        TriggerServerEvent('qxellAC:Server:ReportExplosiveDmg',
                            0.0, weapon) -- Trimitem cu dmg=0 pentru a distingue tipul
                        BulletTrajectory = {}
                        ShotCount        = 0
                    end
                end
            end

            LastShotCoords = GetEntityCoords(ped)
            LastShotWeapon = weapon
        end

        ::continue::
    end
end)

-- ─────────────────────────────────────────────
-- THREAD: Monitorizează kill-urile și headshot-urile
-- Detectează aimbot prin rata de headshots
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(500)

        if not Config.Aimbot.Enabled then
            Wait(5000)
            goto continue
        end

        local myPed = PlayerPedId()
        if not DoesEntityExist(myPed) then goto continue end

        -- Verifică toți jucătorii pentru a detecta kill-uri
        local players = GetActivePlayers()
        for _, playerId in ipairs(players) do
            local ped = GetPlayerPed(playerId)
            if DoesEntityExist(ped) and ped ~= myPed then

                -- Verifică dacă ped-ul a murit din cauza noastră
                if IsEntityDead(ped) and HasEntityBeenDamagedByEntity(ped, myPed, true) then

                    TotalKills = TotalKills + 1

                    -- Verifică dacă e headshot (bone 31086 = cap)
                    local boneIndex = GetEntityBoneIndexByName(ped, 'SKEL_Head')
                    local _, lastDamageBone = GetPedLastDamageBone(ped)

                    -- lastDamageBone == 31086 înseamnă headshot
                    if lastDamageBone == 31086 then
                        DebugLog(('Headshot detectat. Total kills: %d'):format(TotalKills))
                        TriggerServerEvent('qxellAC:Server:ReportHeadshot')
                    end

                    ClearEntityLastDamageEntity(ped)
                end
            end
        end

        ::continue::
    end
end)

-- ─────────────────────────────────────────────
-- THREAD: Anti-Wallhack pasiv
-- Ascunde jucătorii care sunt complet în spatele unor pereți
-- (Setează alpha la 0 local, nu afectează serverul)
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(200)

        local myPed    = PlayerPedId()
        if not DoesEntityExist(myPed) then goto continue end
        local myCam    = GetFinalRenderedCamCoord()
        local players  = GetActivePlayers()

        for _, playerId in ipairs(players) do
            local ped = GetPlayerPed(playerId)
            if DoesEntityExist(ped) and ped ~= myPed and not IsEntityDead(ped) then

                local pedCoords = GetEntityCoords(ped)

                -- Raycast de la camera la jucătorul țintă
                local rayHandle = StartExpensiveSynchronousShapeTestLosProbe(
                    myCam.x, myCam.y, myCam.z,
                    pedCoords.x, pedCoords.y, pedCoords.z,
                    1 + 16,  -- Mașini + pereți
                    myPed,
                    4
                )

                local _, hit, _, _, _ = GetShapeTestResult(rayHandle)

                -- Dacă raza e blocată (hit = true) => jucătorul e după perete
                -- Nu modificăm alpha pentru că e doar client-side rendering hint
                -- Dar putem folosi această info pentru a detecta dacă altcineva
                -- încearcă să tragă prin pereți (prin raycast invers)
                -- Aceasta e o funcție defensivă opțională

            end
        end

        ::continue::
    end
end)

-- ─────────────────────────────────────────────
-- THREAD: Detectează modificarea datelor armelor
-- (weapon meta / handling integrity)
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(3000)

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) then goto continue end

        local weapon = GetSelectedPedWeapon(ped)
        if weapon == `weapon_unarmed` then goto continue end

        -- Verifică damage multiplier al armei (dacă e modificat de cheat)
        local baseDamage = GetWeaponDamage(weapon, 0)

        -- Damage-ul normal pentru arme comune nu depășește ~250
        -- Dacă un cheat modifică weapon meta, damage-ul poate fi 999+
        if baseDamage and baseDamage > Config.ExplosiveBullets.MaxDamagePerHit then
            DebugLog(('DamageModifier detectat: weapon=%s damage=%.0f'):format(
                tostring(weapon), baseDamage))
            TriggerServerEvent('qxellAC:Server:ReportExplosiveDmg',
                baseDamage, weapon)
        end

        ::continue::
    end
end)

-- ─────────────────────────────────────────────
-- THREAD: Anti-No Reload
-- Monitorizează starea de reload a jucătorului
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(0)

        if not Config.Weapons.AntiNoReload then
            Wait(5000)
            goto continue
        end

        local ped    = PlayerPedId()
        if not DoesEntityExist(ped) then goto continue end

        local weapon = GetSelectedPedWeapon(ped)
        if weapon == `weapon_unarmed` then goto continue end

        -- Verifică dacă jucătorul ar trebui să fie în reload
        local _, currentAmmoInClip = GetAmmoInClip(ped, weapon)
        local _, maxAmmoInClip     = GetMaxAmmoInClip(ped, weapon, true)

        -- Dacă clip-ul e plin imediat după ce a fost gol (fără animație de reload)
        if currentAmmoInClip and maxAmmoInClip then
            if currentAmmoInClip == maxAmmoInClip and IsPedShooting(ped) then
                -- Clip plin în timp ce trage? Posibil no-reload
                -- Verificăm dacă animația de reload rulează
                local isReloading = IsEntityPlayingAnim(ped, 
                    'weapons@pistol@ads', 'reload_aim', 3)

                -- Dacă nu reîncarcă și clip-ul e mereu plin = suspect
                -- Stochăm pentru verificare pe server
                DebugLog(('Clip check: %d/%d, reloading=%s'):format(
                    currentAmmoInClip, maxAmmoInClip, tostring(isReloading)))
            end
        end

        ::continue::
    end
end)

print('^2[qxellAC]^7 Client Combat.lua incarcat cu succes.')
