--[[
    ╔══════════════════════════════════════════════════╗
    ║        qxell ANTICHEAT - SHARED/UTILS.LUA        ║
    ║   Funcții utilitare disponibile pe server        ║
    ║   și client (shared_scripts în fxmanifest)       ║
    ╚══════════════════════════════════════════════════╝
--]]

KiroUtils = {}

-- ─────────────────────────────────────────────
-- MATH / GEOMETRY
-- ─────────────────────────────────────────────

-- Distanța 3D între două coordonate (vector3 sau {x,y,z})
function KiroUtils.Distance3D(a, b)
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- Distanța 2D (ignoră Z) — util pentru teleport check pe același plan
function KiroUtils.Distance2D(a, b)
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    return math.sqrt(dx*dx + dy*dy)
end

-- Clampează o valoare între min și max
function KiroUtils.Clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

-- Returnează true dacă valoarea e în intervalul [min, max]
function KiroUtils.InRange(value, min, max)
    return value >= min and value <= max
end

-- ─────────────────────────────────────────────
-- STRING UTILITIES
-- ─────────────────────────────────────────────

-- Trunchiază un string la maxLen caractere + '...'
function KiroUtils.Truncate(str, maxLen)
    str = tostring(str or '')
    if #str <= maxLen then return str end
    return str:sub(1, maxLen) .. '...'
end

-- Sanitizează un string pentru folosire în log-uri / webhook
-- (elimină caractere care pot sparge JSON sau Markdown)
function KiroUtils.Sanitize(str)
    str = tostring(str or '')
    str = str:gsub('[`"\\]', '')  -- elimină backtick, ghilimele, backslash
    str = str:gsub('[\r\n]', ' ') -- înlocuiește newlines cu spațiu
    return str
end

-- Verifică dacă un string e un număr valid
function KiroUtils.IsNumeric(str)
    return tonumber(str) ~= nil
end

-- Formatează un număr cu separator de mii (ex: 1000000 → "1,000,000")
function KiroUtils.FormatNumber(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local result = ''
    local count  = 0
    for i = #s, 1, -1 do
        if count > 0 and count % 3 == 0 then
            result = ',' .. result
        end
        result = s:sub(i, i) .. result
        count  = count + 1
    end
    return result
end

-- ─────────────────────────────────────────────
-- TABLE UTILITIES
-- ─────────────────────────────────────────────

-- Verifică dacă un element există într-un array
function KiroUtils.TableContains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then return true end
    end
    return false
end

-- Numărul de keys dintr-un dictionar (#{} nu funcționează pentru dict)
function KiroUtils.TableCount(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

-- Deep copy al unui tabel
function KiroUtils.DeepCopy(orig)
    local copy
    local origType = type(orig)
    if origType == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            copy[KiroUtils.DeepCopy(k)] = KiroUtils.DeepCopy(v)
        end
        setmetatable(copy, KiroUtils.DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- Golește un tabel fără a crea unul nou (păstrează referința)
function KiroUtils.ClearTable(tbl)
    for k in pairs(tbl) do
        tbl[k] = nil
    end
end

-- ─────────────────────────────────────────────
-- TIME UTILITIES
-- ─────────────────────────────────────────────

-- Returnează timestamp curent în ms (folosind GetGameTimer pe client,
-- os.time()*1000 pe server)
function KiroUtils.Now()
    if IsDuplicityVersion and IsDuplicityVersion() then
        return os.time() * 1000
    end
    return GetGameTimer()
end

-- Verifică dacă a trecut cel puțin `ms` milisecunde față de `lastTime`
function KiroUtils.Cooldown(lastTime, ms)
    return (KiroUtils.Now() - lastTime) >= ms
end

-- Formatează secunde în string lizibil: "2h 30m 15s"
function KiroUtils.FormatDuration(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds <= 0 then return '0s' end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    local parts = {}
    if h > 0 then parts[#parts+1] = h .. 'h' end
    if m > 0 then parts[#parts+1] = m .. 'm' end
    if s > 0 then parts[#parts+1] = s .. 's' end
    return table.concat(parts, ' ')
end

-- ─────────────────────────────────────────────
-- IDENTIFIER UTILITIES (server-only)
-- ─────────────────────────────────────────────

-- Returnează un identifier specific al unui jucător după prefix
function KiroUtils.GetIdentifier(playerId, prefix)
    for i = 0, GetNumPlayerIdentifiers(playerId) - 1 do
        local id = GetPlayerIdentifier(playerId, i)
        if id and id:sub(1, #prefix) == prefix then
            return id
        end
    end
    return nil
end

-- Returnează licența principală a unui jucător
function KiroUtils.GetLicense(playerId)
    return KiroUtils.GetIdentifier(playerId, 'license:')
        or KiroUtils.GetIdentifier(playerId, 'license2:')
end

-- Returnează Discord ID-ul unui jucător (fără prefixul "discord:")
function KiroUtils.GetDiscordId(playerId)
    local id = KiroUtils.GetIdentifier(playerId, 'discord:')
    if id then return id:sub(9) end
    return nil
end

-- Returnează IP-ul unui jucător (fără prefixul "ip:")
function KiroUtils.GetIP(playerId)
    local id = KiroUtils.GetIdentifier(playerId, 'ip:')
    if id then return id:sub(4) end
    return nil
end

-- ─────────────────────────────────────────────
-- VECTOR UTILITIES
-- ─────────────────────────────────────────────

-- Normalizează un vector3
function KiroUtils.NormalizeVector(v)
    local len = math.sqrt(v.x^2 + v.y^2 + v.z^2)
    if len == 0 then return vector3(0, 0, 0) end
    return vector3(v.x / len, v.y / len, v.z / len)
end

-- Produsul scalar (dot product) a două vector3
function KiroUtils.DotProduct(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

-- Unghiul (în grade) dintre două vector3
function KiroUtils.AngleBetween(a, b)
    local dot = KiroUtils.DotProduct(
        KiroUtils.NormalizeVector(a),
        KiroUtils.NormalizeVector(b)
    )
    dot = KiroUtils.Clamp(dot, -1.0, 1.0)
    return math.deg(math.acos(dot))
end

-- ─────────────────────────────────────────────
-- LOGGING UTILS
-- ─────────────────────────────────────────────

-- Prefix colorat pentru consolă server
local LOG_COLORS = {
    info  = '^5',  -- Albastru deschis
    warn  = '^3',  -- Galben
    error = '^1',  -- Roșu
    ok    = '^2',  -- Verde
}

function KiroUtils.Log(level, msg)
    local color  = LOG_COLORS[level] or '^7'
    local prefix = ('[KiroAC/%s]'):format(level:upper())
    print(('%s%s^7 %s'):format(color, prefix, tostring(msg)))
end

function KiroUtils.LogInfo(msg)  KiroUtils.Log('info',  msg) end
function KiroUtils.LogWarn(msg)  KiroUtils.Log('warn',  msg) end
function KiroUtils.LogError(msg) KiroUtils.Log('error', msg) end
function KiroUtils.LogOk(msg)    KiroUtils.Log('ok',    msg) end

-- ─────────────────────────────────────────────
-- VALIDATION UTILS
-- ─────────────────────────────────────────────

-- Verifică dacă un playerId e valid și conectat
function KiroUtils.IsValidPlayer(playerId)
    if not playerId or type(playerId) ~= 'number' then return false end
    if playerId <= 0 then return false end
    return GetPlayerName(playerId) ~= nil
end

-- Verifică dacă o sumă de bani e validă conform config
function KiroUtils.IsValidAmount(amount)
    amount = tonumber(amount)
    if not amount then return false end
    if not Config.Economy.AllowNegativeValues and amount < 0 then return false end
    if not Config.Economy.AllowZeroValues    and amount == 0 then return false end
    if amount > Config.Economy.MaxSingleTransaction then return false end
    return true
end

-- ─────────────────────────────────────────────
-- HASH UTILITIES
-- ─────────────────────────────────────────────

-- Returnează hash-ul unui model ca număr (compatibil cu GetHashKey)
function KiroUtils.GetModelHash(model)
    if type(model) == 'number' then return model end
    if type(model) == 'string' then return GetHashKey(model) end
    return 0
end

-- ─────────────────────────────────────────────
-- RATE LIMITER simplu (pentru folosire în orice script)
-- ─────────────────────────────────────────────
-- Exemplu: local limiter = KiroUtils.CreateRateLimiter(5, 1000)
--          if limiter:Check() then ... end

function KiroUtils.CreateRateLimiter(maxCalls, intervalMs)
    local calls     = 0
    local lastReset = KiroUtils.Now()

    return {
        Check = function(self)
            local now = KiroUtils.Now()
            if (now - lastReset) >= intervalMs then
                calls     = 0
                lastReset = now
            end
            calls = calls + 1
            return calls <= maxCalls
        end,
        Reset = function(self)
            calls     = 0
            lastReset = KiroUtils.Now()
        end,
        GetCount = function(self)
            return calls
        end,
    }
end

KiroUtils.LogOk('Utils.lua incarcat.')
