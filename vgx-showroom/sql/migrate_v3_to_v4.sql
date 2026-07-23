-- ============================================================
--  VGX Showroom — v3 ➜ v4 migration
--  Run setup.sql FIRST (creates the new tables), then this.
--  It moves your old single "Legacy Motors" showroom into the
--  new multi-showroom structure as showroom #1.
-- ============================================================

-- 1) create showroom #1 from the old hard-coded config
INSERT INTO `showrooms` (`id`, `name`, `owner_cid`, `owner_name`, `points`) VALUES
(1, 'Legacy Motors', '1042', NULL,
 '{"entrance":{"x":-678.8994,"y":-697.8365,"z":31.4302},"dropoff":{"x":-662.9369,"y":-712.5365,"z":27.2319},"tdspawn":{"x":-821.3094,"y":-3211.1558,"z":13.9445,"w":62.2549},"tdreturn":{"x":-655.8608,"y":-676.9009,"z":31.5857}}')
ON DUPLICATE KEY UPDATE `name` = `name`;

-- 2) recreate the old 11 world slots for showroom #1
INSERT INTO `showroom_slots` (`showroom_id`, `slot_no`, `x`, `y`, `z`, `heading`) VALUES
(1, 1,  -658.8121, -686.1156, 30.4302, 64.7392),
(1, 2,  -659.0894, -691.2142, 30.4302, 59.4805),
(1, 3,  -659.2953, -695.9128, 30.4302, 61.3799),
(1, 4,  -659.6335, -700.5573, 30.4302, 57.5968),
(1, 5,  -658.7743, -705.5087, 30.4302, 59.8855),
(1, 6,  -662.8002, -679.9732, 30.4302, 204.8383),
(1, 7,  -667.4368, -679.9520, 30.4302, 203.5834),
(1, 8,  -671.9984, -679.7267, 31.4302, 199.3744),
(1, 9,  -676.9315, -679.8806, 31.4302, 205.7924),
(1, 10, -665.5253, -689.1135, 30.5299, 179.8767),
(1, 11, -666.4783, -697.8410, 30.5299, 1.1622)
ON DUPLICATE KEY UPDATE `x` = VALUES(`x`);

-- 3) attach existing listings / staff / sales to showroom #1
ALTER TABLE `showroom_listings` ADD COLUMN IF NOT EXISTS `showroom_id` INT NOT NULL DEFAULT 1;
ALTER TABLE `showroom_staff`    ADD COLUMN IF NOT EXISTS `showroom_id` INT NOT NULL DEFAULT 1;
ALTER TABLE `showroom_sales`    ADD COLUMN IF NOT EXISTS `showroom_id` INT NOT NULL DEFAULT 1;

UPDATE `showroom_listings` SET `showroom_id` = 1 WHERE `showroom_id` = 0;
UPDATE `showroom_staff`    SET `showroom_id` = 1 WHERE `showroom_id` = 0;
UPDATE `showroom_sales`    SET `showroom_id` = 1 WHERE `showroom_id` = 0;

-- 4) staff uniqueness is now per-showroom
ALTER TABLE `showroom_staff` DROP INDEX `citizenid`;
ALTER TABLE `showroom_staff` ADD UNIQUE KEY `uq_showroom_cid` (`showroom_id`, `citizenid`);

-- 5) move the old treasury balance into the new per-showroom treasury
INSERT INTO `society` (`name`, `money`)
SELECT 'showroom_1', `money` FROM `society` WHERE `name` = 'showroom_legacy'
ON DUPLICATE KEY UPDATE `money` = `money`;

UPDATE `showroom_treasury_log` SET `treasury` = 'showroom_1' WHERE `treasury` = 'showroom_legacy';
