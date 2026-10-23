# qxell AntiCheat — Ghid de Instalare

## Structura fișierelor

```
qxell_anticheat/
├── fxmanifest.lua
├── config.lua               ← EDITEAZĂ AICI
├── INSTALARE.md
├── sql/
│   └── kiro_anticheat.sql
├── shared/
│   └── utils.lua
├── server/
│   ├── main.lua
│   ├── detections.lua
│   ├── ban_system.lua
│   └── webhook.lua
└── client/
    ├── main.lua
    ├── combat.lua
    └── bypass.lua
```

---

## Dependențe obligatorii

| Resursă | Link | Motiv |
|---|---|---|
| `oxmysql` | https://github.com/overextended/oxmysql | Baza de date ban-uri |
| `screenshot-basic` | https://github.com/citizenfx/screenshot-basic | Screenshot la ban |

> Dacă nu folosești oxmysql, setează `Config.Database.Enabled = false` în config.lua.  
> Dacă nu vrei screenshot-uri, setează `Config.ScreenshotOnBan = false`.

---

## Instalare pas cu pas

### 1. Baza de date
```sql
-- Rulează fișierul sql/qxell_anticheat.sql în baza ta de date
-- SAU lasă resursa să creeze tabelele automat la primul start
```

### 2. Copiază resursa
```
resources/
└── [anticheat]/
    └── qxell_anticheat/
```

### 3. Editează config.lua
Deschide `config.lua` și completează:
- **Webhook-urile Discord** (înlocuiește `WEBHOOK_..._HERE` cu URL-urile tale)
- **Config.Bypass.MonitoredResources** — adaugă resursele tale critice
- **Config.Weapons.BlacklistedWeapons** — ajustează lista
- **Config.Vehicles.BlacklistedModels** — ajustează lista

### 4. server.cfg
```cfg
ensure oxmysql
ensure screenshot-basic
ensure qxell_anticheat

# Permisiuni admin
add_ace group.admin anticheat.admin allow
```

### 5. Integrare cu framework-ul tău

#### ESX — Give Weapon
```lua
-- Când dai o armă unui jucător, autorizează-o:
exports['qxell_anticheat']:AuthorizeWeapon(source, GetHashKey('weapon_pistol'), 250)

-- Când iei o armă:
exports['qxell_anticheat']:RevokeWeapon(source, GetHashKey('weapon_pistol'))
```

#### QBCore — Give Weapon
```lua
exports['qxell_anticheat']:AuthorizeWeapon(source, GetHashKey('weapon_pistol'), 250)
```

#### Validare tranzacții bani/items
```lua
-- Înainte de a adăuga bani unui jucător:
TriggerEvent('qxellAC:Server:ValidateTransaction', source, amount, 'cash', function(valid)
    if valid then
        -- dă banii
    end
end)
```

---

## Comenzi admin

| Comandă | Descriere |
|---|---|
| `/kac_ban <id> <motiv>` | Banează un jucător manual |
| `/kac_unban <ban_id>` | Debanează după Ban ID (ex: QAC-AB12CD34) |
| `/kac_ss <id>` | Face screenshot la un jucător |

---

## Sistem Strikes

Comportamentul implicit (modificabil în `config.lua`):

```
Strike 1 → Avertisment în chat + log Discord (galben)
Strike 2 → Avertisment în chat + log Discord (portocaliu)
Strike 3 → BAN automat + screenshot + log Discord (roșu)
```

---

## Note importante

- **Server-Authoritative**: Toate verificările finale se fac pe server. Clientul doar raportează date.
- **False Positives**: Dacă ai lag mare pe server, mărește pragurile din config (ex: `MaxDistance`, `MaxAirTime`).
- **No oxmysql**: Poți folosi `mysql-async` înlocuind `MySQL.query/insert/update` cu echivalentele din mysql-async. 
- **Heartbeat**: Dacă clientul nu trimite heartbeat în 60s, serverul îl poate kick (nu e implementat implicit — adaugă logica în server/main.lua după nevoie).
