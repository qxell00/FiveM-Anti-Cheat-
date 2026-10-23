--[[
    ╔══════════════════════════════════════════════════╗
    ║           qxell ANTICHEAT - CONFIG.LUA           ║
    ╚══════════════════════════════════════════════════╝
    Editează toate setările din acest fișier.
    NU modifica fișierele server/ sau client/ dacă nu știi ce faci.
--]]

Config = {}

-- ─────────────────────────────────────────────
-- GENERAL
-- ─────────────────────────────────────────────
Config.Debug            = false          -- Afișează mesaje debug în consolă
Config.Language         = 'EN'           -- Limba mesajelor (RO / EN)
Config.AdminPermission  = 'anticheat.admin'  -- Ace permission pentru admini
Config.ScreenshotOnBan  = true           -- Face screenshot la ban (necesită screenshot-basic)
Config.ResourceName     = GetCurrentResourceName()

-- ─────────────────────────────────────────────
-- DISCORD WEBHOOKS
-- ─────────────────────────────────────────────
Config.Webhooks = {
    Ban         = 'https://discord.com/api/webhooks/WEBHOOK_BAN_HERE',
    Kick        = 'https://discord.com/api/webhooks/WEBHOOK_KICK_HERE',
    Detection   = 'https://discord.com/api/webhooks/WEBHOOK_DETECTION_HERE',
    Screenshot  = 'https://discord.com/api/webhooks/WEBHOOK_SCREENSHOT_HERE',
    Info        = 'https://discord.com/api/webhooks/WEBHOOK_INFO_HERE',
}

Config.WebhookBotName   = 'qxell AntiCheat'
Config.WebhookAvatarUrl = 'https://i.postimg.cc/05TSW6bb/imagine-2026-08-26-175854399.png'  -- Avatar bot Discord

-- ─────────────────────────────────────────────
-- SISTEM STRIKES / AVERTISMENTE
-- ─────────────────────────────────────────────
Config.Strikes = {
    Enabled         = true,
    MaxStrikes      = 3,        -- Număr de strikes înainte de BAN
    ResetAfter      = 300,      -- Secunde după care se resetează strikes (0 = niciodată)
    StrikeAction    = 'ban',    -- 'ban' | 'kick' | 'warn'
}

-- ─────────────────────────────────────────────
-- RATE LIMITING (Anti-Event Spam)
-- ─────────────────────────────────────────────
Config.RateLimit = {
    MaxEventsPerSecond  = 15,   -- Maxim events pe secundă per jucător
    MaxEventsPerMinute  = 300,  -- Maxim events pe minut per jucător
    ActionOnExceed      = 'kick',  -- 'ban' | 'kick'
}

-- ─────────────────────────────────────────────
-- ANTI-TELEPORT
-- ─────────────────────────────────────────────
Config.Teleport = {
    Enabled         = true,
    MaxDistance     = 250.0,    -- Distanța maximă permisă per secundă (pe jos)
    MaxVehicleDist  = 700.0,    -- Distanța maximă în vehicul (avioane/heli sunt mai rapide)
    CheckInterval   = 1000,     -- Interval verificare în ms
    Strikes         = 2,        -- Strikes adăugate la detectare
}

-- ─────────────────────────────────────────────
-- ANTI-SPEEDHACK
-- ─────────────────────────────────────────────
Config.SpeedHack = {
    Enabled             = true,
    MaxOnFootSpeed      = 15.0,     -- m/s maxim pe jos (sprint ~8 m/s, supersprint ~12 m/s)
    MaxVehicleSpeed     = 120.0,    -- m/s maxim în vehicul (~432 km/h, acoperă Hydra/Lazer)
    CheckInterval       = 500,
    Strikes             = 2,
}

-- ─────────────────────────────────────────────
-- ANTI-NOCLIP / ANTI-FLY
-- ─────────────────────────────────────────────
Config.NoClip = {
    Enabled             = true,
    MaxAirTime          = 5.0,      -- Secunde maxime în aer fără vehicul/parasuta
    MinAltitudeCheck    = 1.5,      -- Înălțimea minimă față de sol pentru a considera "în aer"
    CheckInterval       = 1000,
    Strikes             = 3,
}

-- ─────────────────────────────────────────────
-- ANTI-GODMODE / HEALTH HACK
-- ─────────────────────────────────────────────
Config.Godmode = {
    Enabled             = true,
    MaxHealth           = 200.0,    -- HP maxim autorizat (default GTA = 200)
    MaxArmour           = 100.0,    -- Armura maximă autorizată
    CheckInterval       = 2000,
    Strikes             = 3,
}

-- ─────────────────────────────────────────────
-- ANTI-SUPER JUMP
-- ─────────────────────────────────────────────
Config.SuperJump = {
    Enabled         = true,
    MaxJumpHeight   = 5.0,      -- Înălțimea maximă per salt (metri)
    Strikes         = 2,
}

-- ─────────────────────────────────────────────
-- ANTI-INVISIBLE / ALPHA
-- ─────────────────────────────────────────────
Config.Invisible = {
    Enabled     = true,
    MinAlpha    = 200,          -- Alpha minim permis (255 = complet vizibil)
    Strikes     = 3,
}

-- ─────────────────────────────────────────────
-- ANTI-FREECAM
-- ─────────────────────────────────────────────
Config.FreeCam = {
    Enabled         = true,
    MaxCamDistance  = 50.0,     -- Distanța maximă a camerei față de ped
    Strikes         = 2,
}

-- ─────────────────────────────────────────────
-- ANTI-SPECTATE
-- ─────────────────────────────────────────────
Config.Spectate = {
    Enabled     = true,
    Strikes     = 3,
}

-- ─────────────────────────────────────────────
-- ANTI-AIMBOT (Heuristics)
-- ─────────────────────────────────────────────
Config.Aimbot = {
    Enabled                 = true,
    HeadshotWindowSeconds   = 10,       -- Fereastra de timp pentru headshot-uri consecutive
    MaxHeadshotsInWindow    = 8,        -- Maxim headshot-uri în fereastra de timp
    MinKillsForCheck        = 3,        -- Minimum kill-uri înainte de a activa detectarea
    Strikes                 = 3,
}

-- ─────────────────────────────────────────────
-- ANTI-EXPLOSIVE BULLETS / DAMAGE MODIFIER
-- ─────────────────────────────────────────────
Config.ExplosiveBullets = {
    Enabled         = true,
    MaxDamagePerHit = 250.0,    -- Dauna maximă per hit de pistol/rifle
    Strikes         = 3,
}

-- ─────────────────────────────────────────────
-- ARME (blacklist & ammo checks)
-- ─────────────────────────────────────────────
Config.Weapons = {
    InfiniteAmmoEnabled = true,     -- Verifică infinite ammo
    AntiNoReload        = true,     -- Verifică no reload
    -- Arme care nu trebuie să existe NICIODATĂ pe jucători fără aprobare
    BlacklistedWeapons = {
        `weapon_railgun`,
        `weapon_minigun`,
        `weapon_rpg`,
        `weapon_grenadelauncher`,
        `weapon_hominglauncher`,
        `weapon_firework`,
        `weapon_compactlauncher`,
        `weapon_emplauncher`,
    },
}

-- ─────────────────────────────────────────────
-- VEHICULE (blacklist & spawn protection)
-- ─────────────────────────────────────────────
Config.Vehicles = {
    AntiSpawn           = true,
    MaxVehiclesPerPlayer = 2,       -- Maxim vehicule spawnable per jucător odată
    CheckInterval       = 5000,
    -- Vehicule interzise pentru spawn de jucători normali
    BlacklistedModels = {
        `rhino`,
        `hydra`,
        `lazer`,
        `hunter`,
        `barrage`,
        `khanjali`,
        `thruster`,
        `atomizer`,  -- nu vehicul, dar model ped
        `insurgent`,
        `technical`,
        `halftrack`,
        `apc`,
        `chernobog`,
    },
}

-- ─────────────────────────────────────────────
-- OBIECTE / PED (blacklist spawn)
-- ─────────────────────────────────────────────
Config.Objects = {
    MaxObjectsPerPlayer = 5,
    CheckInterval       = 5000,
    BlacklistedObjects  = {
        -- Adaugă hash-uri de obiecte periculoase
        -- Ex: `prop_bomb_01`
    },
}

-- ─────────────────────────────────────────────
-- BANI / ITEMS (tranzacții)
-- ─────────────────────────────────────────────
Config.Economy = {
    MaxSingleTransaction    = 1000000,  -- Suma maximă acceptată per tranzacție
    AllowNegativeValues     = false,
    AllowZeroValues         = false,
}

-- ─────────────────────────────────────────────
-- BYPASS / INJECTION PREVENTION
-- ─────────────────────────────────────────────
Config.Bypass = {
    CheckResourceIntegrity  = true,     -- Verifică dacă resursele critice sunt pornite
    MonitoredResources      = {         -- Resurse a căror oprire = ban imediat
        'qxell_anticheat',
        'es_extended',
        'ox_inventory',
        'oxmysql',
    },
    BlockLoadstring         = true,     -- Blochează loadstring pe client
    EventScrambling         = true,     -- Scramblează numele event-urilor la restart
    CheckInterval           = 10000,
}

-- ─────────────────────────────────────────────
-- BAZE DE DATE
-- ─────────────────────────────────────────────
Config.Database = {
    Enabled     = true,         -- false dacă nu folosești oxmysql/mysql-async
    BanTable    = 'kiro_bans',
    LogTable    = 'kiro_logs',
}

-- ─────────────────────────────────────────────
-- MESAJE (RO)
-- ─────────────────────────────────────────────
Config.Messages = {
    BanMessage  = '[qxell AntiCheat] Ai fost banat.\nMotiv: %s\nID Ban: %s\nContact: discord.gg/server',
    KickMessage = '[qxell AntiCheat] Ai fost dat afară.\nMotiv: %s',
    WarnMessage = '[qxell AntiCheat] Avertisment %d/%d: %s',
}

-- ─────────────────────────────────────────────
-- MENIU ADMIN NUI
-- ─────────────────────────────────────────────
Config.AdminMenu = {
    -- Tasta pentru deschidere/închidere meniu (INSERT = 121)
    -- Lista taste: https://docs.fivem.net/docs/game-references/controls/
    OpenKey         = 121,          -- INSERT
    OpenKeyLabel    = 'INSERT',     -- Afișat în UI

    -- Licențele care au acces la meniu
    -- Găsești licența ta în consola serverului la conectare
    -- sau cu comanda /qac_myid în joc
    AllowedLicenses = {
        'license:282f345b22948209f4dca2b90205db0debd6388b',
        -- 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
        -- Adaugă mai multe după nevoie
    },

    -- Opțional: permite și prin Ace Permission (dacă ai anticheat.admin setat)
    AllowByAce      = true,

    -- Server title afișat în meniu
    ServerName      = 'qxell AntiCheat',
    ServerLogo      = 'https://i.postimg.cc/05TSW6bb/imagine-2026-08-26-175854399.png',           -- URL logo (opțional, lasă gol dacă nu ai)
}

