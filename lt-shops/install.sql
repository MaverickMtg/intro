-- ═══════════════ LT-SHOPS ═══════════════

CREATE TABLE IF NOT EXISTS `lt_shops` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `type` ENUM('grocery','weapon') NOT NULL DEFAULT 'grocery',
    `label` VARCHAR(100) NOT NULL DEFAULT 'Shop',
    `blip_name` VARCHAR(100) NOT NULL DEFAULT 'Shop',
    `owner_cid` VARCHAR(50) DEFAULT NULL,
    `owner_name` VARCHAR(100) DEFAULT NULL,
    `is_open` TINYINT(1) NOT NULL DEFAULT 1,
    `safe_money` INT NOT NULL DEFAULT 0,
    `coords` LONGTEXT NOT NULL,          -- JSON: { seller, buyer, stash, crafting }
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `lt_shop_employees` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `shop_id` INT NOT NULL,
    `citizenid` VARCHAR(50) NOT NULL,
    `name` VARCHAR(100) NOT NULL DEFAULT 'Unknown',
    `grade` ENUM('manager','employee') NOT NULL DEFAULT 'employee',
    UNIQUE KEY `uq_shop_cid` (`shop_id`, `citizenid`),
    INDEX `idx_shop` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `lt_shop_items` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `shop_id` INT NOT NULL,
    `item_name` VARCHAR(100) NOT NULL,
    `item_label` VARCHAR(100) NOT NULL,
    `item_image` VARCHAR(255) DEFAULT NULL,
    `quantity` INT NOT NULL DEFAULT 1,
    `price` INT NOT NULL DEFAULT 0,
    `added_by` VARCHAR(100) DEFAULT NULL,
    INDEX `idx_shop` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `lt_shop_storage` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `shop_id` INT NOT NULL,
    `item_name` VARCHAR(100) NOT NULL,
    `item_label` VARCHAR(100) NOT NULL,
    `amount` INT NOT NULL DEFAULT 0,
    UNIQUE KEY `uq_shop_item` (`shop_id`, `item_name`),
    INDEX `idx_shop` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `lt_shop_admins`;
CREATE TABLE `lt_shop_admins` (
    `identifier` VARCHAR(120) PRIMARY KEY,   -- discord:xxxx  or  license:xxxx
    `name` VARCHAR(100) DEFAULT 'Unknown'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ═══════════════ SEED: FIRST TWO SHOPS ═══════════════

INSERT INTO `lt_shops` (`type`, `label`, `blip_name`, `is_open`, `coords`) VALUES
('grocery', 'Grocery Store #1', 'Grocery Store', 1,
 '{"seller":{"x":301.6923,"y":-1256.6641,"z":29.4124,"w":97.0730},"buyer":{"x":291.6446,"y":-1260.1903,"z":29.4124,"w":183.2853},"stash":{"x":300.1418,"y":-1256.2546,"z":29.4124,"w":5.5353}}'),
('weapon', 'Weapon Store #1', 'Weapon Store', 0,
 '{"seller":{"x":846.5821,"y":-1035.1619,"z":28.3203,"w":98.9572},"buyer":{"x":841.9431,"y":-1035.3116,"z":28.1948,"w":335.8827},"stash":{"x":839.6329,"y":-1032.1010,"z":28.1948,"w":92.1131},"crafting":{"x":846.2060,"y":-1028.6281,"z":28.1949,"w":89.6522}}');
