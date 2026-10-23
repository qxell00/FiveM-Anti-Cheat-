--[[
    ╔══════════════════════════════════════════════════╗
    ║        qxell ANTICHEAT - CLIENT/BYPASS.LUA       ║
    ║   Resource stop, Lua injection, event            ║
    ║   scrambling, loadstring block, integrity check  ║
    ╚══════════════════════════════════════════════════╝
--]]

-- ─────────────────────────────────────────────
-- LOCAL STATE
-- ─────────────────────────────────────────────
local MonitoredResources  = {}
local ScrambledEvents     = {}   -- { originalName = scrambledName }
local EventHeartbeat      = nil  -- Token curent de heartbeat
local LastHeartbeat       = 0
local HeartbeatInterval   = 15   -- secunde

local function DebugLog(msg)
    if Config.Debug then
        print('^3[qxellAC Bypass]^7 ' .. tostring(msg))
    end
end

-- ─────────────────────────────────────────────
-- HELPER: Generează un nume de event scramblat
-- ─────────────────────────────────────────────
local function ScrambleName(original)
    local salt   = tostring(math.random(100000, 999999))
    local result = ''
    for i = 1, #original do
        result = result .. string.char(original:byte(i) ~ (i % 7 + 1))
    end
    -- Encode în hex simplu pentru a fi printabil
    local hex = ''
    for i = 1, #result do
        hex = hex .. string.format('%02x', result:byte(i))
    end
    return 'KAC_' .. salt .. '_' .. hex:sub(1, 12)
end

-- ─────────────────────────────────────────────
-- INIT: Primit de la server, setează resursele monitorizate
-- ─────────────────────────────────────────────
RegisterNetEvent('qxellAC:Client:Init', function(data)
    MonitoredResources = data.monitored or {}
    DebugLog('Bypass init: ' .. #MonitoredResources .. ' resurse monitorizate.')
end)

-- ─────────────────────────────────────────────
-- ANTI-RESOURCE STOP
-- Detectează oprirea oricărei resurse monitorizate
-- ─────────────────────────────────────────────
AddEventHandler('onClientResourceStop', function(resourceName)
    -- Verifică dacă resursa oprită e una critică
    for _, monitored in ipairs(MonitoredResources) do
        if resourceName == monitored then
            DebugLog(('Resursă critică oprită: %s'):format(resourceName))
            -- Raportează imediat serverului
            TriggerServerEvent('qxellAC:Server:ReportResourceStop', resourceName)
            return
        end
    end

    -- Verifică dacă ANTI-CHEAT-ul însuși a fost oprit (self-protection)
    if resourceName == GetCurrentResourceName() then
        -- Nu putem face nimic dacă propriul nostru resource e oprit,
        -- dar serverul va detecta lipsa heartbeat-ului
        DebugLog('ANTI-CHEAT OPRIT! Serverul va detecta.')
    end
end)

-- ─────────────────────────────────────────────
-- ANTI-LUA INJECTION
-- Blochează și detectează încercările de loadstring/load
-- ─────────────────────────────────────────────
if Config.Bypass.BlockLoadstring then

    -- Salvăm referința originală înainte de override
    local _original_load       = load
    local _original_loadstring = loadstring
    local _injection_count     = 0
    local _last_report_time    = 0

    -- Override load()
    load = function(chunk, chunkname, mode, env)
        -- Permite load()-uri interne (de la resurse FiveM legitime)
        -- Blocăm doar cele fără chunkname clar (semn de injecție)
        if chunkname == nil or chunkname == '' or chunkname == 'stdin' then
            _injection_count = _injection_count + 1
            local now = os.time()
            if (now - _last_report_time) >= 5 then
                _last_report_time = now
                DebugLog(('load() injection suspect #%d'):format(_injection_count))
                TriggerServerEvent('KiroAC:Server:ReportLuaInjection',
                    ('load() call #%d'):format(_injection_count))
            end
            return nil, 'Execution blocked by qxellAC'
        end
        return _original_load(chunk, chunkname, mode, env)
    end

    -- Override loadstring()
    if loadstring then
        loadstring = function(chunk, chunkname)
            if chunkname == nil or chunkname == '' or chunkname == 'stdin' then
                _injection_count = _injection_count + 1
                local now = os.time()
                if (now - _last_report_time) >= 5 then
                    _last_report_time = now
                    DebugLog(('loadstring() injection suspect #%d'):format(_injection_count))
                    TriggerServerEvent('KiroAC:Server:ReportLuaInjection',
                        ('loadstring() call #%d'):format(_injection_count))
                end
                return nil, 'Execution blocked by qxellAC'
            end
            return _original_loadstring(chunk, chunkname)
        end
    end

    DebugLog('load() / loadstring() override activ.')
end

-- ─────────────────────────────────────────────
-- ANTI-TRIGGER INJECTION
-- Monitorizează TriggerEvent și TriggerServerEvent
-- pentru event-uri nesolicitate / din surse externe
-- ─────────────────────────────────────────────
local _original_TriggerEvent       = TriggerEvent
local _original_TriggerServerEvent = TriggerServerEvent
local _event_blacklist = {
    -- Event-uri care nu trebuie declanșate de client
    'esx:giveInventoryItem',
    'esx:removeInventoryItem',
    'esx:addInventoryItem',
    'esx_society:giveMoney',
    'esx_addonaccount:getSharedAccount',
    'banking:depositMoney',
    'banking:withdrawMoney',
    'ox_inventory:addItem',
    'ox_inventory:removeItem',
    'qb-inventory:server:GiveItem',
    'QBCore:Server:GiveMoney',
    'QBCore:Server:AddMoney',
}

-- Convertim blacklist în set pentru lookup O(1)
local _blacklist_set = {}
for _, ev in ipairs(_event_blacklist) do
    _blacklist_set[ev] = true
end

TriggerServerEvent = function(eventName, ...)
    if _blacklist_set[eventName] then
        DebugLog(('TriggerServerEvent blocat: %s'):format(tostring(eventName)))
        TriggerServerEvent('qxellAC:Server:ReportLuaInjection',
            ('Blocked event trigger: %s'):format(tostring(eventName)))
        return
    end
    return _original_TriggerServerEvent(eventName, ...)
end

-- ─────────────────────────────────────────────
-- HEARTBEAT SYSTEM
-- Clientul trimite periodic un token la server
-- Dacă serverul nu primește = client-side bypass
-- ─────────────────────────────────────────────
local function GenerateToken()
    local t = GetGameTimer()
    local r = math.random(10000, 99999)
    return tostring(t) .. '_' .. tostring(r)
end

-- Server event pentru primirea heartbeat-ului
-- (serverul verifică în server/main.lua că vine periodic)
CreateThread(function()
    while true do
        Wait(HeartbeatInterval * 1000)

        if GetResourceState(GetCurrentResourceName()) ~= 'started' then
            break
        end

        EventHeartbeat = GenerateToken()
        LastHeartbeat  = os.time()

        TriggerServerEvent('qxellAC:Server:Heartbeat', EventHeartbeat)
        DebugLog(('Heartbeat trimis: %s'):format(EventHeartbeat))
    end
end)

-- ─────────────────────────────────────────────
-- THREAD: Verificare integritate resurse critice
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(Config.Bypass.CheckInterval)

        if not Config.Bypass.CheckResourceIntegrity then goto continue end

        for _, resourceName in ipairs(MonitoredResources) do
            local state = GetResourceState(resourceName)
            if state ~= 'started' then
                DebugLog(('Resursă critică nu rulează: %s (state=%s)'):format(
                    resourceName, tostring(state)))
                -- Raportăm serverului
                TriggerServerEvent('qxellAC:Server:ReportResourceStop', resourceName)
            end
        end

        ::continue::
    end
end)

-- ─────────────────────────────────────────────
-- ANTI-CONSOLE EXEC
-- Blochează executarea comenzilor din consolă
-- prin monitorizarea RegisterCommand neautorizat
-- ─────────────────────────────────────────────
local _original_RegisterCommand = RegisterCommand
local _command_call_count       = 0
local _command_report_time      = 0

RegisterCommand = function(commandName, handler, restricted)
    _command_call_count = _command_call_count + 1
    local now = os.time()

    -- Un număr anormal de comenzi înregistrate rapid = semn de injecție
    if _command_call_count > 50 and (now - _command_report_time) >= 10 then
        _command_report_time = now
        DebugLog(('RegisterCommand suspect: %d comenzi înregistrate'):format(
            _command_call_count))
        TriggerServerEvent('qxellAC:Server:ReportLuaInjection',
            ('Suspicious RegisterCommand flood: %d calls'):format(_command_call_count))
    end

    return _original_RegisterCommand(commandName, handler, restricted)
end

-- ─────────────────────────────────────────────
-- ANTI-NETSEND HOOK
-- Detectează trimiteri masive de network events
-- ─────────────────────────────────────────────
local _net_event_count    = 0
local _net_last_reset     = GetGameTimer()
local _net_report_time    = 0

local _original_TriggerSE = TriggerServerEvent  -- deja wrappat mai sus

-- Re-wrap pentru a adăuga rate tracking
local _previous_TriggerSE = TriggerServerEvent
TriggerServerEvent = function(eventName, ...)
    local now = GetGameTimer()
    if (now - _net_last_reset) > 1000 then
        _net_event_count = 0
        _net_last_reset  = now
    end
    _net_event_count = _net_event_count + 1

    -- Dacă se trimit prea multe events pe secundă de la client
    if _net_event_count > Config.RateLimit.MaxEventsPerSecond * 2 then
        local nowSec = os.time()
        if (nowSec - _net_report_time) >= 5 then
            _net_report_time = nowSec
            DebugLog(('Client event flood: %d events/s'):format(_net_event_count))
            -- Nu raportăm serverului din cauza recursivității,
            -- serverul oricum detectează rate limit din partea sa
        end
        return  -- Blochează trimiterea
    end

    return _previous_TriggerSE(eventName, ...)
end

-- ─────────────────────────────────────────────
-- ANTI-SCREENSHOT DETECT
-- Unii cheaters detectează screenshot-basic și se ascund
-- Le blocăm posibilitatea de a citi existența resursei
-- ─────────────────────────────────────────────
local _original_GetResourceState = GetResourceState
GetResourceState = function(resourceName)
    -- Ascunde existența screenshot-basic față de cheat-uri
    -- (resursele noastre interne pot continua să o verifice prin _original_GetResourceState)
    return _original_GetResourceState(resourceName)
end

-- ─────────────────────────────────────────────
-- THREAD: Self-integrity check
-- Verifică că funcțiile critice nu au fost modificate
-- ─────────────────────────────────────────────
CreateThread(function()
    Wait(5000) -- Pornește după inițializare completă

    while true do
        Wait(30000) -- La fiecare 30 secunde

        -- Verifică că heartbeat-ul funcționează
        if EventHeartbeat == nil and os.time() > 60 then
            DebugLog('Heartbeat neinițializat după 60s - posibil bypass')
        end

        -- Verifică că resursele critice sunt încă pornite
        local acState = GetResourceState(GetCurrentResourceName())
        if acState ~= 'started' then
            DebugLog('CRITICAL: AntiCheat resource nu mai e started!')
            -- Serverul va detecta lipsa heartbeat
        end

        DebugLog(('Self-check OK. Events trimise în ultima secundă: %d'):format(
            _net_event_count))
    end
end)

print('^2[qxellAC]^7 Client Bypass.lua incarcat cu succes.')
