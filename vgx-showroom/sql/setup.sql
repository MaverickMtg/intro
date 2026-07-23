-- ============================================================
--  VGX Showroom v4 — everything is created IN-GAME
--  Run this whole file once. If you are upgrading from v3,
--  ALSO run sql/migrate_v3_to_v4.sql afterwards.
-- ============================================================

-- Showrooms themselves (created from the /showrooms admin panel)
CREATE TABLE IF NOT EXISTS `showrooms` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `name`         VARCHAR(100) NOT NULL DEFAULT 'Showroom',
    `owner_cid`    VARCHAR(64) DEFAULT NULL,
    `owner_name`   VARCHAR(128) DEFAULT NULL,
    -- JSON points captured in-game:
    --   entrance  = {x,y,z}        browse marker
    --   dropoff   = {x,y,z}        drive-in listing marker
    --   tdspawn   = {x,y,z,w}      test-drive spawn (optional)
    --   tdreturn  = {x,y,z}        test-drive return (optional)
    `points`       LONGTEXT NOT NULL,
    `created_at`   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Vehicle display slots (parking spots), captured in-game per showroom
CREATE TABLE IF NOT EXISTS `showroom_slots` (
    `id`          INT AUTO_INCREMENT PRIMARY KEY,
    `showroom_id` INT NOT NULL,
    `slot_no`     INT NOT NULL,
    `x`           DOUBLE NOT NULL,
    `y`           DOUBLE NOT NULL,
    `z`           DOUBLE NOT NULL,
    `heading`     DOUBLE NOT NULL DEFAULT 0,
    UNIQUE KEY `uq_showroom_slot` (`showroom_id`, `slot_no`),
    INDEX `idx_showroom` (`showroom_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `showroom_listings` (
    `id`          INT AUTO_INCREMENT PRIMARY KEY,
    `showroom_id` INT NOT NULL,
    `slot_id`     INT NOT NULL,          -- slot_no within the showroom
    `owner_cid`   VARCHAR(64) NOT NULL,
    `model`       VARCHAR(64) NOT NULL,
    `label`       VARCHAR(128) NOT NULL,
    `price`       INT NOT NULL DEFAULT 0,
    `plate`       VARCHAR(16) NOT NULL,
    `mods`        LONGTEXT DEFAULT NULL,
    `added_by`    VARCHAR(64) NOT NULL,
    `created_at`  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_showroom` (`showroom_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `showroom_staff` (
    `id`          INT AUTO_INCREMENT PRIMARY KEY,
    `showroom_id` INT NOT NULL,
    `citizenid`   VARCHAR(64) NOT NULL,
    `name`        VARCHAR(128) NOT NULL,
    `role`        VARCHAR(32) NOT NULL DEFAULT 'employee',
    `hired_by`    VARCHAR(64) NOT NULL,
    `hired_at`    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_showroom_cid` (`showroom_id`, `citizenid`),
    INDEX `idx_showroom` (`showroom_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `showroom_sales` (
    `id`          INT AUTO_INCREMENT PRIMARY KEY,
    `showroom_id` INT NOT NULL,
    `buyer_cid`   VARCHAR(64) NOT NULL,
    `buyer_name`  VARCHAR(128) NOT NULL,
    `seller_cid`  VARCHAR(64) NOT NULL,
    `model`       VARCHAR(64) NOT NULL,
    `label`       VARCHAR(128) NOT NULL,
    `price`       INT NOT NULL,
    `tax`         INT NOT NULL,
    `plate`       VARCHAR(16) NOT NULL,
    `sold_at`     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_showroom` (`showroom_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Treasury transaction log (per-showroom treasury 'showroom_<id>')
CREATE TABLE IF NOT EXISTS `showroom_treasury_log` (
    `id`         INT AUTO_INCREMENT PRIMARY KEY,
    `treasury`   VARCHAR(64) NOT NULL,
    `type`       VARCHAR(16) NOT NULL,   -- 'deposit' | 'withdraw' | 'sale'
    `amount`     INT NOT NULL,
    `cid`        VARCHAR(64) NOT NULL,
    `name`       VARCHAR(128) NOT NULL,
    `note`       VARCHAR(255) DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Extra showroom-admins added from the /showrooms panel
-- (identifier = discord:xxxx or license:xxxx)
CREATE TABLE IF NOT EXISTS `showroom_admins` (
    `identifier` VARCHAR(120) PRIMARY KEY,
    `name`       VARCHAR(100) DEFAULT 'Unknown'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- NOTE: each showroom's treasury BALANCE lives in the standard `society`
-- table as 'showroom_<id>' — rows are created automatically in-game.
