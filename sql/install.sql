CREATE TABLE IF NOT EXISTS `vehicle_documents` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `plate` VARCHAR(16) NOT NULL,
    `owner_identifier` VARCHAR(80) DEFAULT NULL,
    `owner_name` VARCHAR(128) DEFAULT NULL,
    `model_name` VARCHAR(80) DEFAULT NULL,
    `model_label` VARCHAR(128) DEFAULT NULL,
    `vin` VARCHAR(40) DEFAULT NULL,
    `engine_code` VARCHAR(40) DEFAULT NULL,
    `fuel_text` VARCHAR(80) DEFAULT NULL,
    `tier` INT NOT NULL DEFAULT 1,
    `inspection_done_at` DATETIME DEFAULT NULL,
    `inspection_valid_until` DATETIME DEFAULT NULL,
    `issued_at` DATETIME DEFAULT NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'inspected',
    `invalid_reason` VARCHAR(255) DEFAULT NULL,
    `serial` VARCHAR(40) DEFAULT NULL,
    `display_data` LONGTEXT DEFAULT NULL,
    `properties` LONGTEXT DEFAULT NULL,
    `mod_hash` VARCHAR(80) DEFAULT NULL,
    `last_seen_hash` VARCHAR(80) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_vehicle_documents_plate` (`plate`),
    KEY `idx_vehicle_documents_owner` (`owner_identifier`),
    KEY `idx_vehicle_documents_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- V3 EXTRA RP MODULOK
ALTER TABLE `vehicle_documents` ADD COLUMN IF NOT EXISTS `insurance_valid_until` DATETIME DEFAULT NULL;
ALTER TABLE `vehicle_documents` ADD COLUMN IF NOT EXISTS `tax_paid_until` DATETIME DEFAULT NULL;
ALTER TABLE `vehicle_documents` ADD COLUMN IF NOT EXISTS `wanted` TINYINT(1) NOT NULL DEFAULT 0;
ALTER TABLE `vehicle_documents` ADD COLUMN IF NOT EXISTS `wanted_reason` VARCHAR(255) DEFAULT NULL;
ALTER TABLE `vehicle_documents` ADD COLUMN IF NOT EXISTS `wanted_by` VARCHAR(128) DEFAULT NULL;
ALTER TABLE `vehicle_documents` ADD COLUMN IF NOT EXISTS `doc_uid` VARCHAR(64) DEFAULT NULL;
ALTER TABLE `vehicle_documents` ADD COLUMN IF NOT EXISTS `fake_quality` VARCHAR(32) DEFAULT NULL;

CREATE TABLE IF NOT EXISTS `vehicle_document_workorders` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `plate` VARCHAR(16) NOT NULL,
    `owner_identifier` VARCHAR(80) DEFAULT NULL,
    `mechanic_identifier` VARCHAR(80) DEFAULT NULL,
    `type` VARCHAR(64) NOT NULL,
    `price` INT NOT NULL DEFAULT 0,
    `notes` TEXT DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_vdw_plate` (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vehicle_document_transfers` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `plate` VARCHAR(16) NOT NULL,
    `seller_identifier` VARCHAR(80) NOT NULL,
    `buyer_identifier` VARCHAR(80) NOT NULL,
    `price` INT NOT NULL DEFAULT 0,
    `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `accepted_at` DATETIME DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_vdt_plate` (`plate`),
    KEY `idx_vdt_buyer` (`buyer_identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
