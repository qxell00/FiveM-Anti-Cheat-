-- ══════════════════════════════════════════════════
--  qxell ANTICHEAT - Schema SQL
--  Rulează acest fișier O SINGURĂ DATĂ în baza ta de date.
--  Tabelele se pot crea și automat la primul start al resursei
--  (dacă Config.Database.Enabled = true și oxmysql e pornit).
-- ══════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS `qxell_bans` (
    `id`            INT AUTO_INCREMENT PRIMARY KEY,
    `ban_id`        VARCHAR(20)  NOT NULL UNIQUE COMMENT 'ID unic generat (ex: QAC-AB12CD34)',
    `player_name`   VARCHAR(100) NOT NULL,
    `reason`        VARCHAR(500) NOT NULL,
    `banned_by`     VARCHAR(100) NOT NULL DEFAULT 'qxellAC',
    `identifiers`   LONGTEXT     NOT NULL COMMENT 'JSON cu toți identificatorii',
    `license`       VARCHAR(100) DEFAULT NULL,
    `license2`      VARCHAR(100) DEFAULT NULL,
    `steam`         VARCHAR(100) DEFAULT NULL,
    `discord`       VARCHAR(100) DEFAULT NULL,
    `ip`            VARCHAR(50)  DEFAULT NULL,
    `token1`        VARCHAR(200) DEFAULT NULL,
    `token2`        VARCHAR(200) DEFAULT NULL,
    `token3`        VARCHAR(200) DEFAULT NULL,
    `ban_date`      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `expire_date`   DATETIME     DEFAULT NULL COMMENT 'NULL = permanent',
    `active`        TINYINT(1)   NOT NULL DEFAULT 1,
    INDEX idx_license  (`license`),
    INDEX idx_license2 (`license2`),
    INDEX idx_steam    (`steam`),
    INDEX idx_discord  (`discord`),
    INDEX idx_ip       (`ip`),
    INDEX idx_token1   (`token1`(100)),
    INDEX idx_active   (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `qxell_logs` (
    `id`            INT AUTO_INCREMENT PRIMARY KEY,
    `player_name`   VARCHAR(100) NOT NULL,
    `identifiers`   LONGTEXT     NOT NULL,
    `action`        VARCHAR(50)  NOT NULL COMMENT 'BAN / KICK / DETECTION',
    `reason`        VARCHAR(500) NOT NULL,
    `coords`        VARCHAR(100) DEFAULT NULL,
    `log_date`      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_action   (`action`),
    INDEX idx_log_date (`log_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
