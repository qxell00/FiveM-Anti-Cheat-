--[[
    ╔══════════════════════════════════════════════════╗
    ║        qxell ANTICHEAT - CLIENT/MENU.LUA          ║
    ║   Deschide/închide NUI, verificare acces,        ║
    ║   gestionare cursor, NUI callbacks               ║
    ╚══════════════════════════════════════════════════╝
--]]

-- ─────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────
local MenuOpen      = false
local HasAccess     = false
local AccessChecked = false

local function DebugLog(msg)
    if Config.Debug then
        print('^3[qxellAC Menu]^7 ' .. tostring(msg))
    end
end

-- ─────────────────────────────────────────────
-- OPEN / CLOSE (fără recursivitate)
-- ─────────────────────────────────────────────
local function OpenMenu()
    if MenuOpen then return end
    if not HasAccess then
        DebugLog('Fără acces la meniu.')
        return
    end

    MenuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openMenu' })
    DebugLog('Meniu deschis.')
end

-- IMPORTANT: această funcție este apelată DOAR din Lua (tasta INSERT sau /kac_closemenu)
-- JS-ul nu apelează niciun NUI callback pentru închidere — trimite doar un postMessage
local function CloseMenu()
    if not MenuOpen then return end
    MenuOpen = false
    SetNuiFocus(false, false)       -- Eliberează cursorul
    SendNUIMessage({ action = 'closeMenu' })
    DebugLog('Meniu închis.')
end

-- ─────────────────────────────────────────────
-- NUI CALLBACK: Închidere din JS (X button, ESC, click afară)
-- Acesta NU apelează CloseMenu() — face direct SetNuiFocus
-- pentru a evita recursivitatea și cursorul blocat
-- ─────────────────────────────────────────────
RegisterNUICallback('qxellAC:NUI:Close', function(data, cb)
    MenuOpen = false
    SetNuiFocus(false, false)   -- Eliberează cursorul imediat
    DebugLog('Meniu închis din NUI.')
    cb({ success = true })
end)

-- ─────────────────────────────────────────────
-- VERIFICARE ACCES (server validează licența)
-- ─────────────────────────────────────────────
local function RequestAccessCheck()
    TriggerServerEvent('qxellAC:Menu:CheckAccess')
end

RegisterNetEvent('qxellAC:Menu:AccessResult', function(hasAccess)
    HasAccess     = hasAccess
    AccessChecked = true
    DebugLog(('Acces meniu: %s'):format(tostring(hasAccess)))

    if hasAccess then
        SendNUIMessage({
            action = 'setServerName',
            data   = {
                name = Config.AdminMenu.ServerName,
                logo = Config.AdminMenu.ServerLogo or '',
            }
        })
    end
end)

-- ─────────────────────────────────────────────
-- TASTA INSERT — toggle meniu
-- ─────────────────────────────────────────────
CreateThread(function()
    Wait(3000)
    RequestAccessCheck()

    while true do
        Wait(0)

        if IsControlJustPressed(0, Config.AdminMenu.OpenKey) then
            if not AccessChecked then
                RequestAccessCheck()
                Wait(500)
            end

            if HasAccess then
                if MenuOpen then
                    CloseMenu()
                else
                    OpenMenu()
                end
            else
                DebugLog('Acces refuzat la meniu.')
            end
        end

        -- Blochează input-urile de joc când meniul e deschis
        if MenuOpen then
            DisableAllControlActions(0)
            EnableControlAction(0, 1,   true) -- Mouse X
            EnableControlAction(0, 2,   true) -- Mouse Y
            EnableControlAction(0, 142, true) -- Scroll up
            EnableControlAction(0, 143, true) -- Scroll down
            EnableControlAction(0, 18,  true) -- Enter
        end
    end
end)

-- ─────────────────────────────────────────────
-- NUI CALLBACKS — Date (fiecare UNIC, fără duplicate)
-- ─────────────────────────────────────────────

-- Funcție helper pentru request async server → client → NUI
local function FetchFromServer(serverEvent, clientResponseEvent, cb)
    local result  = nil
    local done    = false

    TriggerServerEvent(serverEvent)

    local handler
    handler = AddEventHandler(clientResponseEvent, function(data)
        result = data
        done   = true
        RemoveEventHandler(handler)
    end)

    -- Timeout 5 secunde
    local timeout = 0
    while not done and timeout < 5000 do
        Wait(50)
        timeout = timeout + 50
    end

    cb(result or {})
end

-- ─── PLAYERS ───
RegisterNUICallback('qxellAC:NUI:GetPlayers', function(data, cb)
    if not HasAccess then cb({}) return end
    FetchFromServer(
        'qxellAC:Menu:Server:GetPlayers',
        'qxellAC:Menu:Client:PlayersData',
        cb
    )
end)

-- ─── GET BANS ───
RegisterNUICallback('qxellAC:NUI:GetBans', function(data, cb)
    if not HasAccess then cb({}) return end
    FetchFromServer(
        'qxellAC:Menu:Server:GetBans',
        'qxellAC:Menu:Client:BansData',
        cb
    )
end)

-- ─── GET LOGS ───
RegisterNUICallback('qxellAC:NUI:GetLogs', function(data, cb)
    if not HasAccess then cb({}) return end
    FetchFromServer(
        'qxellAC:Menu:Server:GetLogs',
        'qxellAC:Menu:Client:LogsData',
        cb
    )
end)

-- ─── GET STRIKES ───
RegisterNUICallback('qxellAC:NUI:GetStrikes', function(data, cb)
    if not HasAccess then cb({}) return end
    FetchFromServer(
        'qxellAC:Menu:Server:GetStrikes',
        'qxellAC:Menu:Client:StrikesData',
        cb
    )
end)

-- ─── GET STATS ───
RegisterNUICallback('qxellAC:NUI:GetStats', function(data, cb)
    if not HasAccess then cb({}) return end
    FetchFromServer(
        'qxellAC:Menu:Server:GetStats',
        'qxellAC:Menu:Client:StatsData',
        cb
    )
end)

-- ─── BAN PLAYER ───
RegisterNUICallback('qxellAC:NUI:BanPlayer', function(data, cb)
    if not HasAccess then cb({ success = false, error = 'Acces refuzat' }) return end
    if not data or not data.id or not data.reason then
        cb({ success = false, error = 'Date incomplete' })
        return
    end
    local targetId = tonumber(data.id)
    local reason   = tostring(data.reason)
    local duration = tonumber(data.duration) or 0
    -- Trimitem la server — serverul verifică dacă jucătorul există
    TriggerServerEvent('qxellAC:Menu:Server:BanPlayer', targetId, reason, duration)
    cb({ success = true })
end)

-- ─── KICK PLAYER ───
RegisterNUICallback('qxellAC:NUI:KickPlayer', function(data, cb)
    if not HasAccess then cb({ success = false, error = 'Acces refuzat' }) return end
    if not data or not data.id or not data.reason then
        cb({ success = false, error = 'Date incomplete' })
        return
    end
    TriggerServerEvent('qxellAC:Menu:Server:KickPlayer', tonumber(data.id), tostring(data.reason))
    cb({ success = true })
end)

-- ─── UNBAN ───
RegisterNUICallback('qxellAC:NUI:Unban', function(data, cb)
    if not HasAccess then cb({ success = false, error = 'Acces refuzat' }) return end
    if not data or not data.banId then
        cb({ success = false, error = 'Ban ID lipsă' })
        return
    end
    TriggerServerEvent('qxellAC:Menu:Server:Unban', tostring(data.banId))
    cb({ success = true })
end)

-- ─── SCREENSHOT ───
RegisterNUICallback('qxellAC:NUI:Screenshot', function(data, cb)
    if not HasAccess then cb({ success = false, error = 'Acces refuzat' }) return end
    TriggerServerEvent('qxellAC:Menu:Server:Screenshot', tonumber(data.id))
    cb({ success = true })
end)

-- ─── SERVER NAME (pentru titlul meniului) ───
RegisterNUICallback('qxellAC:NUI:GetServerName', function(data, cb)
    cb({
        name = Config.AdminMenu.ServerName or 'qxellAC',
        logo = Config.AdminMenu.ServerLogo or '',
    })
end)

-- ─────────────────────────────────────────────
-- SERVER → CLIENT: Toast notifications
-- ─────────────────────────────────────────────
RegisterNetEvent('qxellC:Menu:Client:Toast', function(message, toastType)
    SendNUIMessage({
        action = 'toast',
        data   = { message = message, type = toastType or 'info' }
    })
end)

-- ─────────────────────────────────────────────
-- COMENZI UTILITARE
-- ─────────────────────────────────────────────

-- Închide forțat meniul dacă tasta nu funcționează
RegisterCommand('qac_closemenu', function()
    CloseMenu()
end, false)

-- Afișează propria licență în consolă + chat
RegisterCommand('qac_myid', function()
    TriggerServerEvent('qxellAC:Menu:Server:GetMyId')
end, false)

RegisterNetEvent('qxellAC:Menu:Client:MyId', function(license)
    print('^2[qxellAC]^7 Licența ta: ^3' .. tostring(license))
    TriggerEvent('chat:addMessage', {
        color = {100, 200, 100},
        args  = { '[qxellAC]', 'Licenta ta: ' .. tostring(license) }
    })
end)

print('^2[qxellAC]^7 Client Menu.lua incarcat cu succes.')
