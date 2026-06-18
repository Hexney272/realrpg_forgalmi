local ESX = exports['es_extended']:getSharedObject()
local registeredItem = false
local lastModCheck = {}
local rejectBadVehicleCondition, getDocumentUid, webhookLog, createWorkOrder

local function dprint(...)
    if Config.Debug then
        print('[realrpg_forgalmi]', ...)
    end
end

local function trimPlate(plate)
    if not plate then return nil end
    plate = tostring(plate):gsub('^%s+', ''):gsub('%s+$', '')
    return plate:upper()
end

local function normalizePlateForSql(plate)
    plate = trimPlate(plate)
    if not plate then return nil end
    return plate:gsub('%s+', '')
end

local function notify(src, msg, nType)
    Config.Notify(src, msg, nType or 'info')
end

local function sqlDateAfterDays(days)
    return os.date('%Y-%m-%d %H:%M:%S', os.time() + ((days or 365) * 86400))
end

local function sqlNow()
    return os.date('%Y-%m-%d %H:%M:%S')
end

local function humanDate(sqlDate)
    if not sqlDate then return 'nincs' end
    local y, m, d, h, mi = tostring(sqlDate):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)%s+(%d%d):(%d%d)')
    if not y then
        y, m, d, h, mi = tostring(sqlDate):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d)')
    end
    if not y then return tostring(sqlDate) end
    return ('%s. %s. %s. %s:%s'):format(y, m, d, h, mi)
end

local function randomSerial()
    math.randomseed(os.time() + math.random(1, 999999))
    return (Config.Document.SerialPrefix or 'NJ') .. tostring(math.random(1000000, 9999999))
end

local function vinFromPlate(plate)
    local clean = normalizePlateForSql(plate) or 'UNKNOWN'
    local hash = 0
    for i = 1, #clean do
        hash = (hash * 33 + clean:byte(i)) % 99999999
    end
    return ('CHREAL%sN%s'):format(clean:sub(1, 5), tostring(hash):sub(1, 6))
end

local function engineCodeFromPlate(plate)
    local clean = normalizePlateForSql(plate) or 'UNKNOWN'
    local hash = 0
    for i = 1, #clean do
        hash = (hash * 31 + clean:byte(i)) % 16777215
    end
    return ('B%06XU'):format(hash)
end

local function safeDecode(value)
    if not value or value == '' then return {} end
    local ok, decoded = pcall(json.decode, value)
    if ok and type(decoded) == 'table' then return decoded end
    return {}
end

local function safeEncode(tbl)
    local ok, encoded = pcall(json.encode, tbl or {})
    if ok then return encoded end
    return '{}'
end

local function createDatabase()
    if not Config.AutoCreateDatabase then return end

    MySQL.query.await([[
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
    ]])
end

local function getOwnedVehicle(plate)
    local normalized = normalizePlateForSql(plate)
    if not normalized then return nil end

    local query = ([[
        SELECT `%s` AS owner, `%s` AS plate, `%s` AS vehicle
        FROM `%s`
        WHERE REPLACE(UPPER(`%s`), ' ', '') = ?
        LIMIT 1
    ]]):format(
        Config.VehicleOwnerColumn,
        Config.VehiclePlateColumn,
        Config.VehicleDataColumn,
        Config.VehicleTable,
        Config.VehiclePlateColumn
    )

    return MySQL.single.await(query, { normalized })
end

local function getOwnerName(identifier)
    if not identifier then return 'Ismeretlen tulajdonos' end

    -- Először próbáljuk firstname + lastname, ha nincs, akkor name
    local row = MySQL.single.await(([[
        SELECT `%s` AS firstname, `%s` AS lastname
        FROM `%s`
        WHERE `%s` = ?
        LIMIT 1
    ]]):format(
        Config.UsersFirstnameColumn,
        Config.UsersLastnameColumn,
        Config.UsersTable,
        Config.UsersIdentifierColumn
    ), { identifier })

    if row then
        local first = row.firstname and tostring(row.firstname) or ''
        local last = row.lastname and tostring(row.lastname) or ''
        local full = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+$', '')
        if full ~= '' then return full end
    end

    -- Fallback: próbáljuk a name oszlopot (ha létezik)
    local ok, nameRow = pcall(function()
        return MySQL.single.await(([[
            SELECT `%s` AS name FROM `%s` WHERE `%s` = ? LIMIT 1
        ]]):format(Config.UsersNameColumn, Config.UsersTable, Config.UsersIdentifierColumn), { identifier })
    end)
    if ok and nameRow and nameRow.name and tostring(nameRow.name) ~= '' then
        return tostring(nameRow.name)
    end

    return tostring(identifier)
end

local function getDocumentByPlate(plate)
    plate = trimPlate(plate)
    if not plate then return nil end

    local row = MySQL.single.await([[ 
        SELECT *, IF(`inspection_valid_until` IS NOT NULL AND `inspection_valid_until` < NOW(), 1, 0) AS expired
        FROM `vehicle_documents`
        WHERE `plate` = ?
        LIMIT 1
    ]], { plate })

    if row and tonumber(row.expired) == 1 and row.status == 'valid' then
        MySQL.update.await('UPDATE `vehicle_documents` SET `status` = ?, `invalid_reason` = ? WHERE `plate` = ?', {
            'invalid', 'Lejárt műszaki vizsga', plate
        })
        row.status = 'invalid'
        row.invalid_reason = 'Lejárt műszaki vizsga'
    end

    return row
end

local function ensureVehicleData(data)
    if type(data) ~= 'table' then return nil, 'Hibás jármű adat.' end
    local plate = trimPlate(data.plate)
    if not plate or #plate < 2 or #plate > 16 then return nil, 'Nem található rendszám.' end

    data.plate = plate
    data.modelName = tostring(data.modelName or 'unknown')
    data.modelLabel = tostring(data.modelLabel or data.modelName or 'Ismeretlen')
    data.makeName = tostring(data.makeName or '')
    data.modHash = tostring(data.modHash or '')
    data.display = type(data.display) == 'table' and data.display or {}
    data.properties = type(data.properties) == 'table' and data.properties or {}

    if data.modHash == '' then return nil, 'Nem sikerült beolvasni a jármű tuning adatait.' end
    return data, nil
end

local function validateOwner(src, plate)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return nil, nil, 'Nem található játékos.' end

    local owned = getOwnedVehicle(plate)
    if not owned then
        return nil, xPlayer, 'Ez a jármű nincs regisztrálva az owned_vehicles táblában.'
    end

    if Config.OnlyOwnerCanUse and owned.owner ~= xPlayer.identifier then
        return nil, xPlayer, 'Ezt csak a jármű tulajdonosa intézheti.'
    end

    return owned, xPlayer, nil
end

local function removePlayerMoney(xPlayer, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then return true end

    if Config.MoneyAccount == 'bank' then
        local account = xPlayer.getAccount('bank')
        if not account or tonumber(account.money) < amount then return false end
        xPlayer.removeAccountMoney('bank', amount)
        return true
    end

    if tonumber(xPlayer.getMoney()) < amount then return false end
    xPlayer.removeMoney(amount)
    return true
end

local function makeDisplayData(data, ownerName, vin, engineCode, validUntil, issueDate)
    local display = data.display or {}

    display.cityName = Config.Document.CityName
    display.logo = Config.Document.Logo
    display.title = Config.Document.Title
    display.type = display.type or data.modelLabel or 'Ismeretlen'
    display.owner = ownerName or display.owner or 'Ismeretlen tulajdonos'
    display.vin = vin
    display.engineCode = engineCode
    display.plate = data.plate
    display.identifier = display.identifier or '10'
    display.fuel = Config.VehicleFuelText[data.modelName] or display.fuel or Config.Document.DefaultFuelText
    display.tier = display.tier or Config.Document.DefaultTier
    display.inspectionValidUntil = humanDate(validUntil)
    display.issueDate = humanDate(issueDate or sqlNow())

    display.paintJob = display.paintJob or 'nincs'
    display.roofPaint = display.roofPaint or 'nincs'
    display.primaryColor = display.primaryColor or 'gyári'
    display.secondaryColor = display.secondaryColor or 'gyári'
    display.interiorColor = display.interiorColor or 'nincs'
    display.dashboardColor = display.dashboardColor or 'nincs'
    display.rim = display.rim or 'gyári'
    display.rimPaint = display.rimPaint or 'gyári'
    display.rimSticker = display.rimSticker or 'nincs'
    display.engine = display.engine or 'gyári'
    display.turbo = display.turbo or 'gyári'
    display.transmission = display.transmission or 'gyári'
    display.ecu = display.ecu or 'gyári'
    display.suspension = display.suspension or 'gyári'
    display.tires = display.tires or 'gyári'
    display.brakes = display.brakes or 'gyári'
    display.weightReduction = display.weightReduction or 'gyári'
    display.frontCamber = display.frontCamber or 'gyári'
    display.rearCamber = display.rearCamber or 'gyári'
    display.frontTrack = display.frontTrack or 'gyári'
    display.rearTrack = display.rearTrack or 'gyári'
    display.steeringAngle = display.steeringAngle or 'gyári'
    display.windowTint = display.windowTint or 'nincs'
    display.lightType = display.lightType or 'gyári'
    display.lightColor = display.lightColor or 'nincs'
    display.uniqueSound = display.uniqueSound or 'nincs'
    display.backfire = display.backfire or 'nincs'
    display.opticalTuning = display.opticalTuning or 'nincs'
    display.neonLayout = display.neonLayout or 'nincs'
    display.neonType = display.neonType or 'nincs'
    display.neonColor = display.neonColor or 'nincs'

    return display
end

local function upsertInspection(src, data, selectedFuel)
    if rejectBadVehicleCondition and rejectBadVehicleCondition(src, data) then return end
    local owned, xPlayer, ownerErr = validateOwner(src, data.plate)
    if ownerErr then
        notify(src, ownerErr, 'error')
        return
    end

    local total = Config.Inspection.Price
    if selectedFuel and Config.Fuel.Enabled then
        total = total + Config.Fuel.Price
    end

    if not removePlayerMoney(xPlayer, total) then
        notify(src, ('Nincs elég pénzed. Szükséges összeg: %s %s'):format(total, Config.Currency), 'error')
        return
    end

    local ownerName = getOwnerName(owned.owner)
    local validUntil = sqlDateAfterDays(Config.Inspection.ValidityDays)
    local now = sqlNow()
    local vin = vinFromPlate(data.plate)
    local engineCode = engineCodeFromPlate(data.plate)
    local display = makeDisplayData(data, ownerName, vin, engineCode, validUntil, now)
    local existing = getDocumentByPlate(data.plate)
    local serial = existing and existing.serial or randomSerial()

    MySQL.update.await([[
        INSERT INTO `vehicle_documents`
        (`plate`, `owner_identifier`, `owner_name`, `model_name`, `model_label`, `vin`, `engine_code`, `fuel_text`, `tier`,
         `inspection_done_at`, `inspection_valid_until`, `status`, `invalid_reason`, `serial`, `display_data`, `properties`, `last_seen_hash`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            `owner_identifier` = VALUES(`owner_identifier`),
            `owner_name` = VALUES(`owner_name`),
            `model_name` = VALUES(`model_name`),
            `model_label` = VALUES(`model_label`),
            `vin` = VALUES(`vin`),
            `engine_code` = VALUES(`engine_code`),
            `fuel_text` = VALUES(`fuel_text`),
            `tier` = VALUES(`tier`),
            `inspection_done_at` = VALUES(`inspection_done_at`),
            `inspection_valid_until` = VALUES(`inspection_valid_until`),
            `status` = 'inspected',
            `invalid_reason` = NULL,
            `serial` = COALESCE(`serial`, VALUES(`serial`)),
            `display_data` = VALUES(`display_data`),
            `properties` = VALUES(`properties`),
            `last_seen_hash` = VALUES(`last_seen_hash`)
    ]], {
        data.plate,
        owned.owner,
        ownerName,
        data.modelName,
        data.modelLabel,
        vin,
        engineCode,
        display.fuel,
        tonumber(display.tier) or Config.Document.DefaultTier,
        now,
        validUntil,
        'inspected',
        serial,
        safeEncode(display),
        safeEncode(data.properties),
        data.modHash
    })

    if selectedFuel and Config.Fuel.Enabled then
        TriggerClientEvent('realrpg_forgalmi:client:addFuel', src, Config.Fuel.Liters)
    end

    if createWorkOrder then createWorkOrder(src, data, 'Műszaki vizsga', total, 'Műszaki vizsga elvégezve') end
    if webhookLog then webhookLog('Műszaki vizsga', { ['Rendszám'] = data.plate, ['Ár'] = (tostring(total) .. ' ' .. Config.Currency) }) end
    notify(src, ('Sikeres műszaki vizsga. Fizetve: %s %s. Most menj az Okmányirodához a forgalmi kiállításához.'):format(total, Config.Currency), 'success')
end

local function giveOrUpdateDocumentItem(src, plate)
    local metadata = {
        plate = plate,
        description = ('Rendszám: %s'):format(plate),
        label = ('Forgalmi engedély - %s'):format(plate)
    }

    local slots = exports.ox_inventory:Search(src, 'slots', Config.ItemName) or {}
    for _, item in pairs(slots) do
        if item and item.metadata and trimPlate(item.metadata.plate) == trimPlate(plate) then
            exports.ox_inventory:SetMetadata(src, item.slot, metadata)
            return true
        end
    end

    return exports.ox_inventory:AddItem(src, Config.ItemName, 1, metadata)
end

local function issueDocument(src, data)
    local owned, xPlayer, ownerErr = validateOwner(src, data.plate)
    if ownerErr then
        notify(src, ownerErr, 'error')
        return
    end

    local doc = getDocumentByPlate(data.plate)
    if not doc then
        notify(src, 'Először műszaki vizsgát kell csináltatnod a szervizben.', 'error')
        return
    end

    local validRow = MySQL.single.await([[ 
        SELECT IF(`inspection_valid_until` IS NOT NULL AND `inspection_valid_until` >= NOW(), 1, 0) AS ok
        FROM `vehicle_documents`
        WHERE `plate` = ?
        LIMIT 1
    ]], { data.plate })

    if not validRow or tonumber(validRow.ok) ~= 1 then
        notify(src, 'A műszaki vizsga lejárt vagy nincs elvégezve.', 'error')
        return
    end

    local now = sqlNow()
    local ownerName = getOwnerName(owned.owner)
    local validUntil = doc.inspection_valid_until
    local vin = doc.vin and doc.vin ~= '' and doc.vin or vinFromPlate(data.plate)
    local engineCode = doc.engine_code and doc.engine_code ~= '' and doc.engine_code or engineCodeFromPlate(data.plate)
    local display = makeDisplayData(data, ownerName, vin, engineCode, validUntil, now)
    local serial = doc.serial and doc.serial ~= '' and doc.serial or randomSerial()

    MySQL.update.await([[
        UPDATE `vehicle_documents`
        SET `owner_identifier` = ?,
            `owner_name` = ?,
            `model_name` = ?,
            `model_label` = ?,
            `vin` = ?,
            `engine_code` = ?,
            `fuel_text` = ?,
            `tier` = ?,
            `issued_at` = ?,
            `status` = 'valid',
            `invalid_reason` = NULL,
            `serial` = ?,
            `display_data` = ?,
            `properties` = ?,
            `mod_hash` = ?,
            `last_seen_hash` = ?
        WHERE `plate` = ?
    ]], {
        owned.owner,
        ownerName,
        data.modelName,
        data.modelLabel,
        vin,
        engineCode,
        display.fuel,
        tonumber(display.tier) or Config.Document.DefaultTier,
        now,
        serial,
        safeEncode(display),
        safeEncode(data.properties),
        data.modHash,
        data.modHash,
        data.plate
    })

    local ok = giveOrUpdateDocumentItem(src, data.plate)
    if not ok then
        notify(src, 'A forgalmi elkészült, de nincs hely az inventorydban.', 'error')
        return
    end

    MySQL.update.await('UPDATE `vehicle_documents` SET `doc_uid` = COALESCE(`doc_uid`, ?) WHERE `plate` = ?', { getDocumentUid and getDocumentUid({}) or serial, data.plate })
    if webhookLog then webhookLog('Forgalmi kiállítva', { ["Rendszám"] = data.plate, ["Tulajdonos"] = ownerName, ["Okmányszám"] = serial }) end
    notify(src, 'A forgalmi engedély sikeresen kiállítva.', 'success')
end

local function buildDocumentPayload(doc)
    local display = safeDecode(doc.display_data)
    display.cityName = Config.Document.CityName
    display.logo = Config.Document.Logo
    display.title = Config.Document.Title
    display.owner = doc.owner_name or display.owner or 'Ismeretlen tulajdonos'
    display.plate = doc.plate or display.plate or 'nincs'
    display.vin = doc.vin or display.vin or 'nincs'
    display.engineCode = doc.engine_code or display.engineCode or 'nincs'
    display.fuel = doc.fuel_text or display.fuel or Config.Document.DefaultFuelText
    display.tier = doc.tier or display.tier or Config.Document.DefaultTier
    display.inspectionValidUntil = humanDate(doc.inspection_valid_until)
    display.issueDate = humanDate(doc.issued_at or doc.inspection_done_at)
    display.docUid = doc.doc_uid or doc.serial
    display.insurance = doc.insurance_valid_until and humanDate(doc.insurance_valid_until) or 'nincs'
    display.tax = doc.tax_paid_until and humanDate(doc.tax_paid_until) or 'nincs'
    display.wanted = tonumber(doc.wanted) == 1 and 'KÖRÖZÖTT' or 'nem'

    return {
        serial = doc.serial or randomSerial(),
        status = doc.status,
        invalid = doc.status ~= 'valid',
        invalidText = Config.Document.InvalidStamp,
        invalidReason = doc.invalid_reason or (doc.status == 'inspected' and 'Forgalmi még nincs kiállítva' or 'Érvénytelen forgalmi'),
        fields = display
    }
end

RegisterNetEvent('realrpg_forgalmi:server:issueDocumentWalk', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return notify(src, 'Nem található játékos.', 'error') end

    -- Megkeressük a játékos legutolsó érvényes vizsgával rendelkező járművét
    local row = MySQL.single.await([[
        SELECT `plate`, `model_name`, `model_label`, `display_data`, `properties`, `mod_hash`
        FROM `vehicle_documents`
        WHERE `owner_identifier` = ? AND `status` = 'inspected'
          AND `inspection_valid_until` IS NOT NULL AND `inspection_valid_until` >= NOW()
        ORDER BY `inspection_done_at` DESC
        LIMIT 1
    ]], { xPlayer.identifier })

    if not row then
        notify(src, 'Nincs érvényes műszaki vizsgával rendelkező járműved. Először vizsgáztasd le a szervizben.', 'error')
        return
    end

    -- Összerakjuk a data objektumot a meglévő issueDocument függvényhez
    local data = {
        plate = row.plate,
        modelName = row.model_name or 'unknown',
        modelLabel = row.model_label or 'Ismeretlen',
        makeName = '',
        modHash = row.mod_hash or '',
        display = safeDecode(row.display_data),
        properties = safeDecode(row.properties)
    }

    issueDocument(src, data)
end)

RegisterNetEvent('realrpg_forgalmi:server:getOfficeVehicles', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local identifier = xPlayer.identifier
    local rows = MySQL.query.await([[
        SELECT `plate`, `model_label`, `status`, `inspection_valid_until`, `insurance_valid_until`, `tax_paid_until`
        FROM `vehicle_documents`
        WHERE `owner_identifier` = ?
          AND (
            (`status` = 'inspected' AND `inspection_valid_until` IS NOT NULL AND `inspection_valid_until` >= NOW())
            OR `status` = 'valid'
          )
        ORDER BY `updated_at` DESC
    ]], { identifier })

    local vehicles = {}
    if rows then
        for _, row in ipairs(rows) do
            vehicles[#vehicles + 1] = {
                plate = row.plate,
                model_label = row.model_label or 'Ismeretlen',
                status = row.status,
                inspection_valid_until = row.inspection_valid_until,
                insurance_valid_until = row.insurance_valid_until,
                tax_paid_until = row.tax_paid_until
            }
        end
    end

    TriggerClientEvent('realrpg_forgalmi:client:openOffice', src, {
        vehicles = vehicles,
        currency = Config.Currency,
        extras = Config.Extras
    })
end)

RegisterNetEvent('realrpg_forgalmi:server:runInspection', function(vehicleData, selections)
    local src = source
    local data, err = ensureVehicleData(vehicleData)
    if not data then
        notify(src, err or 'Hibás jármű adat.', 'error')
        return
    end

    local selectedFuel = selections and selections.fuel == true
    upsertInspection(src, data, selectedFuel)
end)

RegisterNetEvent('realrpg_forgalmi:server:issueDocument', function(vehicleData)
    local src = source
    local data, err = ensureVehicleData(vehicleData)
    if not data then
        notify(src, err or 'Hibás jármű adat.', 'error')
        return
    end

    issueDocument(src, data)
end)

RegisterNetEvent('realrpg_forgalmi:server:modificationCheck', function(vehicleData)
    if not Config.InvalidateOnModification then return end
    local src = source
    local data, err = ensureVehicleData(vehicleData)
    if not data then return end

    local key = src .. ':' .. data.plate
    local now = GetGameTimer()
    if lastModCheck[key] and now - lastModCheck[key] < (Config.ModificationCheckIntervalMs - 1000) then return end
    lastModCheck[key] = now

    local doc = getDocumentByPlate(data.plate)
    if not doc or doc.status ~= 'valid' then return end
    if not doc.mod_hash or doc.mod_hash == '' then return end

    if tostring(doc.mod_hash) ~= tostring(data.modHash) then
        MySQL.update.await([[
            UPDATE `vehicle_documents`
            SET `status` = 'invalid',
                `invalid_reason` = 'A jármű módosítva lett a forgalmi kiállítása után',
                `last_seen_hash` = ?,
                `display_data` = ?,
                `properties` = ?
            WHERE `plate` = ? AND `status` = 'valid'
        ]], {
            data.modHash,
            safeEncode(data.display or {}),
            safeEncode(data.properties or {}),
            data.plate
        })

        notify(src, ('A(z) %s rendszámú jármű forgalmija ÉRVÉNYTELEN lett, mert a jármű módosítva lett.'):format(data.plate), 'error')
    end
end)

RegisterNetEvent('realrpg_forgalmi:server:openByPlate', function(plate)
    local src = source
    plate = trimPlate(plate)
    if not plate then return end

    local doc = getDocumentByPlate(plate)
    if not doc then
        notify(src, 'Ehhez a járműhöz nincs forgalmi engedély.', 'error')
        return
    end

    TriggerClientEvent('realrpg_forgalmi:client:openDocument', src, buildDocumentPayload(doc))
end)

CreateThread(function()
    Wait(500)
    createDatabase()

    -- Fallback ESX usable item. Ox_inventory esetén a mellékelt items.lua snippet client eventet használ,
    -- de így akkor is működik, ha a szervereden az ESX usable item bridge aktív.
    if not registeredItem and ESX.RegisterUsableItem then
        ESX.RegisterUsableItem(Config.ItemName, function(source, item)
            local plate = item and item.metadata and item.metadata.plate
            plate = trimPlate(plate)
            if not plate then
                notify(source, 'Ez a forgalmi nem tartalmaz rendszám adatot. Használd az ox_inventory item eventes beállítást az ITEM_OX_INVENTORY.lua fájlból.', 'error')
                return
            end

            local doc = getDocumentByPlate(plate)
            if not doc then
                notify(source, 'A forgalmi adatai nem találhatók az adatbázisban.', 'error')
                return
            end

            TriggerClientEvent('realrpg_forgalmi:client:openDocument', source, buildDocumentPayload(doc))
        end)
        registeredItem = true
    end

    -- Biztosítás item használat
    if ESX.RegisterUsableItem and Config.Extras and Config.Extras.Insurance and Config.Extras.Insurance.ItemName then
        ESX.RegisterUsableItem(Config.Extras.Insurance.ItemName, function(source, item)
            local plate = item and item.metadata and item.metadata.plate
            plate = trimPlate(plate)
            if not plate then
                notify(source, 'Ez a biztosítás nem tartalmaz rendszám adatot.', 'error')
                return
            end
            local doc = getDocumentByPlate(plate)
            if not doc then
                notify(source, 'A jármű adatai nem találhatók.', 'error')
                return
            end
            local ownerName = getOwnerName(doc.owner_identifier)
            local payload = {
                plate = plate,
                owner = ownerName,
                modelLabel = doc.model_label or 'Ismeretlen',
                validUntil = humanDate(doc.insurance_valid_until),
                issuedAt = humanDate(doc.updated_at or doc.created_at),
                serial = 'BIZ-' .. tostring(math.random(100000, 999999)),
                price = Config.Extras.Insurance.Price or 75000,
                currency = Config.Currency
            }
            TriggerClientEvent('realrpg_forgalmi:client:openInsurance', source, payload)
        end)
    end

    -- Adásvételi szerződés item használat
    if ESX.RegisterUsableItem and Config.Extras and Config.Extras.SaleContract and Config.Extras.SaleContract.ItemName then
        ESX.RegisterUsableItem(Config.Extras.SaleContract.ItemName, function(source)
            TriggerClientEvent('realrpg_forgalmi:client:startSale', source)
        end)
    end

    print('^2[realrpg_forgalmi]^7 elindult. Item: ' .. Config.ItemName)
end)

-- Más scriptekből hívható export: tuning után érvénytelenítés rendszám alapján.
exports('InvalidateVehicleDocument', function(plate, reason)
    plate = trimPlate(plate)
    if not plate then return false end

    local changed = MySQL.update.await([[
        UPDATE `vehicle_documents`
        SET `status` = 'invalid', `invalid_reason` = ?
        WHERE `plate` = ? AND `status` = 'valid'
    ]], { reason or 'A jármű módosítva lett', plate })

    return changed and changed > 0
end)

--[[
    REALRPG FORGALMI EXTRA RP CSOMAG
    Biztosítás, adó, pótlás, adásvétel, rendszámcsere, munkalap, hamis forgalmi,
    körözési státusz, garázs exportok, Discord log.
]]

local pendingTransfers = {}

local function tableHasGroup(group)
    if not Config.Extras or not Config.Extras.Wanted or not Config.Extras.Wanted.AdminGroups then return false end
    return Config.Extras.Wanted.AdminGroups[group] == true
end

local function isAdmin(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false end
    local group = xPlayer.getGroup and xPlayer.getGroup() or 'user'
    return tableHasGroup(group)
end

local function fmtMoney(amount)
    return tostring(tonumber(amount) or 0) .. ' ' .. (Config.Currency or 'Ft')
end

webhookLog = function(title, fields)
    if not Config.Discord or not Config.Discord.Enabled or not Config.Discord.Webhook or Config.Discord.Webhook == '' then return end
    local embedFields = {}
    for k, v in pairs(fields or {}) do
        embedFields[#embedFields + 1] = { name = tostring(k), value = tostring(v), inline = true }
    end
    local payload = {
        username = Config.Discord.Name or 'RealRPG Forgalmi Log',
        embeds = {{
            title = title,
            color = Config.Discord.Color or 16762624,
            fields = embedFields,
            footer = { text = os.date('%Y.%m.%d %H:%M:%S') }
        }}
    }
    PerformHttpRequest(Config.Discord.Webhook, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

local function addDaysFromNow(days)
    return os.date('%Y-%m-%d %H:%M:%S', os.time() + ((tonumber(days) or 30) * 86400))
end

local function dateIsValid(sqlDate)
    if not sqlDate then return false end
    local y, m, d, h, mi, se = tostring(sqlDate):match('^(%d+)%-(%d+)%-(%d+)%s+(%d+):(%d+):?(%d*)')
    if not y then return false end
    return os.time({year=tonumber(y), month=tonumber(m), day=tonumber(d), hour=tonumber(h), min=tonumber(mi), sec=tonumber(se) or 0}) >= os.time()
end

local function ensureExtraColumns()
    local alters = {
        "ALTER TABLE `vehicle_documents` ADD COLUMN IF NOT EXISTS `insurance_valid_until` DATETIME DEFAULT NULL",
        "ALTER TABLE `vehicle_documents` ADD COLUMN IF NOT EXISTS `tax_paid_until` DATETIME DEFAULT NULL",
        "ALTER TABLE `vehicle_documents` ADD COLUMN IF NOT EXISTS `wanted` TINYINT(1) NOT NULL DEFAULT 0",
        "ALTER TABLE `vehicle_documents` ADD COLUMN IF NOT EXISTS `wanted_reason` VARCHAR(255) DEFAULT NULL",
        "ALTER TABLE `vehicle_documents` ADD COLUMN IF NOT EXISTS `wanted_by` VARCHAR(128) DEFAULT NULL",
        "ALTER TABLE `vehicle_documents` ADD COLUMN IF NOT EXISTS `doc_uid` VARCHAR(64) DEFAULT NULL",
        "ALTER TABLE `vehicle_documents` ADD COLUMN IF NOT EXISTS `fake_quality` VARCHAR(32) DEFAULT NULL"
    }
    for _, q in ipairs(alters) do pcall(function() MySQL.query.await(q) end) end
    pcall(function() MySQL.query.await("CREATE INDEX IF NOT EXISTS `idx_vehicle_documents_doc_uid` ON `vehicle_documents` (`doc_uid`)") end)
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `vehicle_document_workorders` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `plate` VARCHAR(16) NOT NULL,
            `owner_identifier` VARCHAR(80) DEFAULT NULL,
            `mechanic_identifier` VARCHAR(80) DEFAULT NULL,
            `type` VARCHAR(64) NOT NULL,
            `price` INT NOT NULL DEFAULT 0,
            `notes` TEXT DEFAULT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`), KEY `idx_vdw_plate` (`plate`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `vehicle_document_transfers` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `plate` VARCHAR(16) NOT NULL,
            `seller_identifier` VARCHAR(80) NOT NULL,
            `buyer_identifier` VARCHAR(80) NOT NULL,
            `price` INT NOT NULL DEFAULT 0,
            `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `accepted_at` DATETIME DEFAULT NULL,
            PRIMARY KEY (`id`), KEY `idx_vdt_plate` (`plate`), KEY `idx_vdt_buyer` (`buyer_identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

CreateThread(function()
    Wait(1500)
    ensureExtraColumns()
    print('^2[realrpg_forgalmi]^7 extra RP modulok betöltve.')
end)

getDocumentUid = function(doc)
    if doc and doc.doc_uid and doc.doc_uid ~= '' then return doc.doc_uid end
    return 'REAL-VEH-' .. tostring(math.random(100000, 999999))
end

createWorkOrder = function(src, data, wtype, price, notes)
    if not Config.Extras or not Config.Extras.WorkOrder or not Config.Extras.WorkOrder.Enabled then return end
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not data or not data.plate then return end
    MySQL.insert.await('INSERT INTO `vehicle_document_workorders` (`plate`, `owner_identifier`, `mechanic_identifier`, `type`, `price`, `notes`) VALUES (?, ?, ?, ?, ?, ?)', {
        data.plate, xPlayer.identifier, xPlayer.identifier, wtype or 'művelet', tonumber(price) or 0, notes or ''
    })
    local metadata = {
        plate = data.plate,
        description = ('Rendszám: %s | %s | %s'):format(data.plate, wtype or 'Munkalap', fmtMoney(price or 0)),
        label = ('Szerviz munkalap - %s'):format(data.plate)
    }
    exports.ox_inventory:AddItem(src, Config.Extras.WorkOrder.ItemName or 'szerviz_munkalap', 1, metadata)
end

rejectBadVehicleCondition = function(src, data)
    local h = Config.Extras and Config.Extras.InspectionHealth
    if not h or not h.Enabled then return false end
    local health = data.health or {}
    local engine = tonumber(health.engine) or 1000.0
    local body = tonumber(health.body) or 1000.0
    local tank = tonumber(health.tank) or 1000.0
    if engine < (h.MinEngine or 850.0) then
        notify(src, ('A jármű nem felelt meg a műszakin. Motor állapota: %.0f/1000'):format(engine), 'error')
        return true
    end
    if body < (h.MinBody or 850.0) then
        notify(src, ('A jármű nem felelt meg a műszakin. Karosszéria állapota: %.0f/1000'):format(body), 'error')
        return true
    end
    if tank < (h.MinTank or 900.0) then
        notify(src, ('A jármű nem felelt meg a műszakin. Tank állapota: %.0f/1000'):format(tank), 'error')
        return true
    end
    return false
end

AddEventHandler('realrpg_forgalmi:server:inspectionPassedExtra', function(src, data, total)
    createWorkOrder(src, data, 'Műszaki vizsga', total or Config.Inspection.Price, 'Műszaki vizsga elvégezve')
end)

RegisterNetEvent('realrpg_forgalmi:server:buyInsurance', function(vehicleData)
    local src = source
    if not Config.Extras or not Config.Extras.Insurance or not Config.Extras.Insurance.Enabled then return end
    local data, err = ensureVehicleData(vehicleData)
    if not data then notify(src, err or 'Hibás jármű adat.', 'error') return end
    local owned, xPlayer, ownerErr = validateOwner(src, data.plate)
    if ownerErr then notify(src, ownerErr, 'error') return end
    local price = Config.Extras.Insurance.Price or 75000
    if not removePlayerMoney(xPlayer, price) then notify(src, 'Nincs elég pénzed biztosításra: ' .. fmtMoney(price), 'error') return end
    local untilDate = addDaysFromNow(Config.Extras.Insurance.ValidityDays or 30)
    MySQL.update.await('UPDATE `vehicle_documents` SET `insurance_valid_until` = ?, `doc_uid` = COALESCE(`doc_uid`, ?) WHERE `plate` = ?', { untilDate, getDocumentUid({}), data.plate })
    createWorkOrder(src, data, 'Kötelező biztosítás', price, 'Biztosítás megkötve eddig: ' .. humanDate(untilDate))
    webhookLog('Biztosítás kötve', { ["Játékos"] = xPlayer.identifier, ["Rendszám"] = data.plate, ["Ár"] = fmtMoney(price), ["Lejárat"] = humanDate(untilDate) })
    notify(src, 'Kötelező biztosítás megkötve. Lejárat: ' .. humanDate(untilDate), 'success')
end)

RegisterNetEvent('realrpg_forgalmi:server:payVehicleTax', function(vehicleData)
    local src = source
    if not Config.Extras or not Config.Extras.Tax or not Config.Extras.Tax.Enabled then return end
    local data, err = ensureVehicleData(vehicleData)
    if not data then notify(src, err or 'Hibás jármű adat.', 'error') return end
    local owned, xPlayer, ownerErr = validateOwner(src, data.plate)
    if ownerErr then notify(src, ownerErr, 'error') return end
    local class = tonumber(data.vehicleClass) or 0
    local price = (Config.Extras.Tax.PricesByClass and Config.Extras.Tax.PricesByClass[class]) or Config.Extras.Tax.BasePrice or 25000
    if not removePlayerMoney(xPlayer, price) then notify(src, 'Nincs elég pénzed járműadóra: ' .. fmtMoney(price), 'error') return end
    local untilDate = addDaysFromNow(Config.Extras.Tax.ValidityDays or 30)
    MySQL.update.await('UPDATE `vehicle_documents` SET `tax_paid_until` = ?, `doc_uid` = COALESCE(`doc_uid`, ?) WHERE `plate` = ?', { untilDate, getDocumentUid({}), data.plate })
    createWorkOrder(src, data, 'Járműadó', price, 'Adó befizetve eddig: ' .. humanDate(untilDate))
    webhookLog('Járműadó befizetve', { ["Játékos"] = xPlayer.identifier, ["Rendszám"] = data.plate, ["Ár"] = fmtMoney(price), ["Lejárat"] = humanDate(untilDate) })
    notify(src, 'Járműadó befizetve. Érvényes eddig: ' .. humanDate(untilDate), 'success')
end)

RegisterNetEvent('realrpg_forgalmi:server:replaceDocument', function(vehicleData)
    local src = source
    if not Config.Extras or not Config.Extras.Replacement or not Config.Extras.Replacement.Enabled then return end
    local data, err = ensureVehicleData(vehicleData)
    if not data then notify(src, err or 'Hibás jármű adat.', 'error') return end
    local owned, xPlayer, ownerErr = validateOwner(src, data.plate)
    if ownerErr then notify(src, ownerErr, 'error') return end
    local doc = getDocumentByPlate(data.plate)
    if not doc or doc.status ~= 'valid' then notify(src, 'Csak érvényes, már kiállított forgalmit lehet pótolni.', 'error') return end
    local price = Config.Extras.Replacement.Price or 50000
    if not removePlayerMoney(xPlayer, price) then notify(src, 'Nincs elég pénzed pótlásra: ' .. fmtMoney(price), 'error') return end
    giveOrUpdateDocumentItem(src, data.plate)
    createWorkOrder(src, data, 'Forgalmi pótlás', price, 'Elveszett/megsemmisült forgalmi pótlása')
    webhookLog('Forgalmi pótolva', { ["Játékos"] = xPlayer.identifier, ["Rendszám"] = data.plate, ["Ár"] = fmtMoney(price) })
    notify(src, 'Forgalmi engedély pótolva.', 'success')
end)

local function plateAvailable(newPlate)
    local row = getOwnedVehicle(newPlate)
    return row == nil
end

RegisterNetEvent('realrpg_forgalmi:server:changePlate', function(vehicleData, newPlate)
    local src = source
    if not Config.Extras or not Config.Extras.PlateChange or not Config.Extras.PlateChange.Enabled then return end
    local data, err = ensureVehicleData(vehicleData)
    if not data then notify(src, err or 'Hibás jármű adat.', 'error') return end
    newPlate = trimPlate(newPlate)
    local pcfg = Config.Extras.PlateChange
    if not newPlate or #newPlate < (pcfg.MinLength or 2) or #newPlate > (pcfg.MaxLength or 8) or newPlate:find('[^A-Z0-9%-]') then
        notify(src, 'Hibás rendszám. Csak A-Z, 0-9 és kötőjel használható.', 'error') return
    end
    if not plateAvailable(newPlate) then notify(src, 'Ez a rendszám már foglalt.', 'error') return end
    local owned, xPlayer, ownerErr = validateOwner(src, data.plate)
    if ownerErr then notify(src, ownerErr, 'error') return end
    local price = (#newPlate <= 6 and pcfg.NormalPrice or pcfg.CustomPrice) or pcfg.CustomPrice or 500000
    if not removePlayerMoney(xPlayer, price) then notify(src, 'Nincs elég pénzed rendszámcserére: ' .. fmtMoney(price), 'error') return end
    local veh = safeDecode(owned.vehicle)
    veh.plate = newPlate
    MySQL.update.await(([[UPDATE `%s` SET `%s` = ?, `%s` = ? WHERE REPLACE(UPPER(`%s`), ' ', '') = ? LIMIT 1]]):format(Config.VehicleTable, Config.VehiclePlateColumn, Config.VehicleDataColumn, Config.VehiclePlateColumn), {
        newPlate, safeEncode(veh), normalizePlateForSql(data.plate)
    })
    MySQL.update.await('UPDATE `vehicle_documents` SET `plate` = ?, `status` = ?, `invalid_reason` = ?, `doc_uid` = ? WHERE `plate` = ?', {
        newPlate, 'invalid', 'Rendszámcsere után új forgalmit kell kiállítani', getDocumentUid({}), data.plate
    })
    createWorkOrder(src, { plate = newPlate }, 'Rendszámcsere', price, 'Régi rendszám: ' .. data.plate)
    webhookLog('Rendszámcsere', { ["Játékos"] = xPlayer.identifier, ["Régi"] = data.plate, ["Új"] = newPlate, ["Ár"] = fmtMoney(price) })
    TriggerClientEvent('realrpg_forgalmi:client:setVehiclePlate', src, data.plate, newPlate)
    notify(src, 'Rendszámcsere sikeres. Az új rendszám: ' .. newPlate .. '. Új forgalmi szükséges.', 'success')
end)

-- Adásvételi szerződés NUI rendszer
local activeContracts = {}

RegisterNetEvent('realrpg_forgalmi:server:startSaleContract', function(plate, buyerId, price)
    local src = source
    plate = trimPlate(plate)
    if not plate then return end
    local buyerSrc = tonumber(buyerId)
    price = tonumber(price) or 0

    local xSeller = ESX.GetPlayerFromId(src)
    local xBuyer = ESX.GetPlayerFromId(buyerSrc)
    if not xSeller or not xBuyer then
        notify(src, 'A vevő nincs a közeledben vagy nem elérhető.', 'error')
        return
    end

    local owned, _, ownerErr = validateOwner(src, plate)
    if ownerErr then notify(src, ownerErr, 'error') return end

    local doc = getDocumentByPlate(plate)
    local modelLabel = (doc and doc.model_label) or 'Ismeretlen'
    local sellerName = getOwnerName(xSeller.identifier)
    local buyerName = getOwnerName(xBuyer.identifier)
    local key = normalizePlateForSql(plate)

    activeContracts[key] = {
        plate = plate,
        seller = src,
        buyer = buyerSrc,
        sellerIdentifier = xSeller.identifier,
        buyerIdentifier = xBuyer.identifier,
        sellerName = sellerName,
        buyerName = buyerName,
        modelLabel = modelLabel,
        price = price,
        sellerSigned = false,
        buyerSigned = false,
        expires = os.time() + 300
    }

    local basePayload = {
        plate = plate,
        sellerName = sellerName,
        buyerName = buyerName,
        modelLabel = modelLabel,
        price = price,
        currency = Config.Currency,
        date = humanDate(sqlNow()),
        sellerSigned = false,
        buyerSigned = false
    }

    local sellerPayload = {}
    for k, v in pairs(basePayload) do sellerPayload[k] = v end
    sellerPayload.role = 'seller'

    TriggerClientEvent('realrpg_forgalmi:client:openContract', src, sellerPayload)
end)

RegisterNetEvent('realrpg_forgalmi:server:contractSign', function(plate, role)
    local src = source
    plate = trimPlate(plate)
    if not plate then return end
    local key = normalizePlateForSql(plate)
    local contract = activeContracts[key]
    if not contract or contract.expires < os.time() then
        notify(src, 'A szerződés lejárt vagy nem létezik.', 'error')
        return
    end

    if role == 'seller' and src == contract.seller then
        contract.sellerSigned = true
        notify(src, 'Aláírtad a szerződést. Várakozás a vevő aláírására...', 'success')

        local buyerPayload = {
            plate = contract.plate,
            sellerName = contract.sellerName,
            buyerName = contract.buyerName,
            modelLabel = contract.modelLabel,
            price = contract.price,
            currency = Config.Currency,
            date = humanDate(sqlNow()),
            sellerSigned = true,
            buyerSigned = false,
            role = 'buyer'
        }
        TriggerClientEvent('realrpg_forgalmi:client:openContract', contract.buyer, buyerPayload)

    elseif role == 'buyer' and src == contract.buyer then
        contract.buyerSigned = true

        if contract.sellerSigned and contract.buyerSigned then
            local xBuyer = ESX.GetPlayerFromId(contract.buyer)
            local xSeller = ESX.GetPlayerFromId(contract.seller)
            if not xBuyer then
                notify(src, 'Hiba a vásárlás során.', 'error')
                activeContracts[key] = nil
                return
            end

            if contract.price > 0 then
                if not removePlayerMoney(xBuyer, contract.price) then
                    notify(contract.buyer, 'Nincs elég pénzed a vásárláshoz.', 'error')
                    activeContracts[key] = nil
                    return
                end
                if xSeller then xSeller.addMoney(contract.price) end
            end

            MySQL.update.await(([[UPDATE `%s` SET `%s` = ? WHERE REPLACE(UPPER(`%s`), ' ', '') = ? LIMIT 1]]):format(
                Config.VehicleTable, Config.VehicleOwnerColumn, Config.VehiclePlateColumn
            ), { xBuyer.identifier, key })

            MySQL.update.await([[
                UPDATE `vehicle_documents` SET `owner_identifier` = ?, `owner_name` = ?, `status` = 'invalid', `invalid_reason` = 'Tulajdonosváltás - új forgalmi szükséges'
                WHERE `plate` = ?
            ]], { xBuyer.identifier, contract.buyerName, contract.plate })

            local itemName = Config.Extras.SaleContract.ItemName or 'adasveteli_szerzodes'
            exports.ox_inventory:AddItem(contract.buyer, itemName, 1, {
                plate = contract.plate,
                description = ('Rendszám: %s | Ár: %s'):format(contract.plate, fmtMoney(contract.price)),
                label = 'Adásvételi szerződés - ' .. contract.plate
            })

            notify(contract.buyer, 'Sikeres adásvétel! A jármű a nevedre került. Okmányirodában új forgalmit kell kiállítanod.', 'success')
            if xSeller then notify(contract.seller, 'Az adásvétel lezárult. Pénz jóváírva: ' .. fmtMoney(contract.price), 'success') end

            webhookLog('Adásvétel (NUI)', { ["Rendszám"] = contract.plate, ["Eladó"] = contract.sellerIdentifier, ["Vevő"] = xBuyer.identifier, ["Ár"] = fmtMoney(contract.price) })
            activeContracts[key] = nil
        end
    else
        notify(src, 'Nincs jogosultságod aláírni.', 'error')
    end
end)

RegisterCommand('adasvetel', function(src, args)
    if src == 0 then return end
    local target = tonumber(args[1])
    local price = tonumber(args[2]) or 0
    local plate = trimPlate(args[3])
    if not target or not GetPlayerName(target) or not plate then
        notify(src, 'Használat: /adasvetel [játékos ID] [ár] [rendszám]', 'error') return
    end
    local xSeller = ESX.GetPlayerFromId(src)
    local xBuyer = ESX.GetPlayerFromId(target)
    if not xSeller or not xBuyer then return end
    local owned, _, ownerErr = validateOwner(src, plate)
    if ownerErr then notify(src, ownerErr, 'error') return end
    local key = normalizePlateForSql(plate)
    pendingTransfers[key] = { seller = src, buyer = target, sellerIdentifier = xSeller.identifier, buyerIdentifier = xBuyer.identifier, price = price, plate = plate, expires = os.time() + ((Config.Extras.SaleContract.PendingMinutes or 10) * 60) }
    MySQL.insert.await('INSERT INTO `vehicle_document_transfers` (`plate`, `seller_identifier`, `buyer_identifier`, `price`) VALUES (?, ?, ?, ?)', { plate, xSeller.identifier, xBuyer.identifier, price })
    notify(src, 'Adásvételi ajánlat elküldve. Rendszám: ' .. plate, 'success')
    notify(target, ('Adásvételi ajánlat érkezett. Rendszám: %s | Ár: %s. Elfogadás: /adasvetel_elfogad %s'):format(plate, fmtMoney(price), plate), 'info')
end, false)

RegisterCommand('adasvetel_elfogad', function(src, args)
    if src == 0 then return end
    local plate = trimPlate(args[1])
    if not plate then notify(src, 'Használat: /adasvetel_elfogad [rendszám]', 'error') return end
    local key = normalizePlateForSql(plate)
    local t = pendingTransfers[key]
    if not t or t.buyer ~= src or t.expires < os.time() then notify(src, 'Nincs aktív adásvételi ajánlat erre a rendszámra.', 'error') return end
    local xBuyer = ESX.GetPlayerFromId(src)
    local xSeller = ESX.GetPlayerFromId(t.seller)
    if not xBuyer then return end
    if t.price > 0 and not removePlayerMoney(xBuyer, t.price) then notify(src, 'Nincs elég pénzed az autó megvásárlásához.', 'error') return end
    if xSeller and t.price > 0 then xSeller.addMoney(t.price) end
    MySQL.update.await(([[UPDATE `%s` SET `%s` = ? WHERE REPLACE(UPPER(`%s`), ' ', '') = ? LIMIT 1]]):format(Config.VehicleTable, Config.VehicleOwnerColumn, Config.VehiclePlateColumn), { xBuyer.identifier, key })
    MySQL.update.await('UPDATE `vehicle_documents` SET `owner_identifier` = ?, `owner_name` = ?, `status` = ?, `invalid_reason` = ? WHERE `plate` = ?', { xBuyer.identifier, getOwnerName(xBuyer.identifier), 'invalid', 'Tulajdonosváltás után új forgalmit kell kiállítani', plate })
    MySQL.update.await('UPDATE `vehicle_document_transfers` SET `status` = ?, `accepted_at` = ? WHERE `plate` = ? AND `buyer_identifier` = ? AND `status` = ? ORDER BY `id` DESC LIMIT 1', { 'accepted', sqlNow(), plate, xBuyer.identifier, 'pending' })
    exports.ox_inventory:AddItem(src, Config.Extras.SaleContract.ItemName or 'adasveteli_szerzodes', 1, { plate = plate, description = ('Rendszám: %s | Ár: %s'):format(plate, fmtMoney(t.price)), label = 'Adásvételi szerződés - ' .. plate })
    pendingTransfers[key] = nil
    webhookLog('Adásvétel elfogadva', { ["Rendszám"] = plate, ["Vevő"] = xBuyer.identifier, ["Eladó"] = t.sellerIdentifier, ["Ár"] = fmtMoney(t.price) })
    notify(src, 'Sikeres adásvétel. Az okmányirodában új forgalmit kell kiállítanod.', 'success')
    if xSeller then notify(t.seller, 'A vevő elfogadta az adásvételt. Pénz jóváírva.', 'success') end
end, false)

RegisterCommand('jarmu_korozes', function(src, args)
    if src == 0 then return end
    if not isAdmin(src) then notify(src, 'Nincs jogosultságod.', 'error') return end
    local plate = trimPlate(args[1])
    local state = tostring(args[2] or '1')
    local reason = table.concat(args, ' ', 3)
    if not plate then notify(src, 'Használat: /jarmu_korozes [rendszám] [1/0] [indok]', 'error') return end
    local wanted = state ~= '0'
    local xPlayer = ESX.GetPlayerFromId(src)
    MySQL.update.await('UPDATE `vehicle_documents` SET `wanted` = ?, `wanted_reason` = ?, `wanted_by` = ? WHERE `plate` = ?', { wanted and 1 or 0, wanted and (reason ~= '' and reason or 'Nincs indok') or nil, wanted and getOwnerName(xPlayer.identifier) or nil, plate })
    webhookLog(wanted and 'Jármű körözés alá helyezve' or 'Jármű körözés levéve', { ["Rendszám"] = plate, Indok = reason ~= '' and reason or '-', Admin = xPlayer.identifier })
    notify(src, wanted and 'Jármű körözés alá helyezve.' or 'Jármű körözés levéve.', 'success')
end, false)

RegisterNetEvent('realrpg_forgalmi:server:createFakeDocument', function(vehicleData, quality)
    local src = source
    if not Config.Extras or not Config.Extras.FakeDocument or not Config.Extras.FakeDocument.Enabled then return end
    local data, err = ensureVehicleData(vehicleData)
    if not data then notify(src, err or 'Hibás jármű adat.', 'error') return end
    quality = tostring(quality or 'medium')
    local price = Config.Extras.FakeDocument.Prices[quality] or Config.Extras.FakeDocument.Prices.medium or 500000
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    if not removePlayerMoney(xPlayer, price) then notify(src, 'Nincs elég pénzed hamis forgalmira: ' .. fmtMoney(price), 'error') return end
    local fakeDisplay = data.display or {}
    fakeDisplay.cityName = Config.Document.CityName
    fakeDisplay.logo = Config.Document.Logo
    fakeDisplay.title = Config.Document.Title
    fakeDisplay.plate = data.plate
    fakeDisplay.owner = getOwnerName(xPlayer.identifier)
    fakeDisplay.vin = vinFromPlate(data.plate)
    fakeDisplay.engineCode = engineCodeFromPlate(data.plate)
    fakeDisplay.inspectionValidUntil = humanDate(addDaysFromNow(365))
    fakeDisplay.issueDate = humanDate(sqlNow())
    exports.ox_inventory:AddItem(src, Config.Extras.FakeDocument.ItemName or 'hamis_forgalmi', 1, {
        plate = data.plate,
        fake = true,
        quality = quality,
        serial = 'REAL-FAKE-' .. tostring(math.random(100000, 999999)),
        display_data = safeEncode(fakeDisplay),
        description = ('Hamis forgalmi | Rendszám: %s | Minőség: %s'):format(data.plate, quality),
        label = 'Hamis forgalmi - ' .. data.plate
    })
    webhookLog('Hamis forgalmi készült', { ["Játékos"] = xPlayer.identifier, ["Rendszám"] = data.plate, ["Minőség"] = quality, ["Ár"] = fmtMoney(price) })
    notify(src, 'Hamis forgalmi elkészült. Minőség: ' .. quality, 'success')
end)

RegisterNetEvent('realrpg_forgalmi:server:openFakeDocument', function(item)
    local src = source
    local md = item and item.metadata or {}
    local display = safeDecode(md.display_data)
    if not display or not display.plate then notify(src, 'Hibás hamis forgalmi.', 'error') return end
    TriggerClientEvent('realrpg_forgalmi:client:openDocument', src, {
        serial = md.serial or 'REAL-FAKE',
        status = 'valid',
        invalid = false,
        invalidText = Config.Document.InvalidStamp,
        invalidReason = nil,
        fake = true,
        quality = md.quality or 'medium',
        fields = display
    })
end)

exports('GetVehicleDocumentStatus', function(plate)
    local doc = getDocumentByPlate(plate)
    if not doc then return { exists = false } end
    return {
        exists = true,
        plate = doc.plate,
        status = doc.status,
        inspectionValid = dateIsValid(doc.inspection_valid_until),
        insuranceValid = dateIsValid(doc.insurance_valid_until),
        taxValid = dateIsValid(doc.tax_paid_until),
        wanted = tonumber(doc.wanted) == 1,
        wantedReason = doc.wanted_reason,
        uid = doc.doc_uid or doc.serial
    }
end)

exports('CanTakeVehicleFromGarage', function(plate)
    local doc = getDocumentByPlate(plate)
    if not doc then return true, 'nincs forgalmi adat' end
    local g = Config.Extras and Config.Extras.Garage or {}
    if g.BlockIfInspectionInvalid and doc.status ~= 'valid' then return false, 'érvénytelen műszaki/forgalmi' end
    if g.BlockIfInsuranceExpired and not dateIsValid(doc.insurance_valid_until) then return false, 'lejárt biztosítás' end
    if g.BlockIfTaxExpired and not dateIsValid(doc.tax_paid_until) then return false, 'lejárt járműadó' end
    return true, 'ok'
end)



-- PLATE-BASED EVENTS (office NUI)
RegisterNetEvent('realrpg_forgalmi:server:issueDocumentByPlate', function(plate)
    local src = source
    plate = trimPlate(plate)
    if not plate then return end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local doc = getDocumentByPlate(plate)
    if not doc then
        notify(src, 'Ehhez a járműhöz nincs műszaki vizsga elvégezve.', 'error')
        return
    end

    local owned = getOwnedVehicle(plate)
    if not owned then
        notify(src, 'Ez a jármű nincs a nevedre regisztrálva.', 'error')
        return
    end
    if Config.OnlyOwnerCanUse and owned.owner ~= xPlayer.identifier then
        notify(src, 'Ezt csak a jármű tulajdonosa intézheti.', 'error')
        return
    end

    local data = {
        plate = plate,
        modelName = doc.model_name or 'unknown',
        modelLabel = doc.model_label or 'Ismeretlen',
        makeName = '',
        modHash = doc.mod_hash or doc.last_seen_hash or '',
        display = safeDecode(doc.display_data),
        properties = safeDecode(doc.properties)
    }

    issueDocument(src, data)
end)

RegisterNetEvent('realrpg_forgalmi:server:buyInsuranceByPlate', function(plate)
    local src = source
    plate = trimPlate(plate)
    if not plate or not Config.Extras or not Config.Extras.Insurance or not Config.Extras.Insurance.Enabled then return end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local owned = getOwnedVehicle(plate)
    if not owned or (Config.OnlyOwnerCanUse and owned.owner ~= xPlayer.identifier) then
        notify(src, 'Ezt csak a jármű tulajdonosa intézheti.', 'error')
        return
    end

    local price = Config.Extras.Insurance.Price or 75000
    if not removePlayerMoney(xPlayer, price) then
        notify(src, ('Nincs elég pénzed. Szükséges: %s %s'):format(price, Config.Currency), 'error')
        return
    end

    local untilDate = sqlDateAfterDays(Config.Extras.Insurance.ValidityDays or 30)
    MySQL.update.await('UPDATE `vehicle_documents` SET `insurance_valid_until` = ? WHERE `plate` = ?', { untilDate, plate })

    -- Item adás
    local itemName = Config.Extras.Insurance.ItemName or 'kotelezo_biztositas'
    local ownerName = getOwnerName(owned.owner)
    local doc = getDocumentByPlate(plate)
    local modelLabel = (doc and doc.model_label) or 'Ismeretlen'

    local metadata = {
        plate = plate,
        description = ('Rendszám: %s | Érvényes: %s'):format(plate, humanDate(untilDate)),
        label = ('Biztosítás - %s'):format(plate)
    }

    -- Meglévő item frissítés vagy új adás
    local slots = exports.ox_inventory:Search(src, 'slots', itemName) or {}
    local found = false
    for _, item in pairs(slots) do
        if item and item.metadata and trimPlate(item.metadata.plate) == plate then
            exports.ox_inventory:SetMetadata(src, item.slot, metadata)
            found = true
            break
        end
    end
    if not found then
        exports.ox_inventory:AddItem(src, itemName, 1, metadata)
    end

    -- NUI megnyitás: biztosítási okmány megjelenítése
    local payload = {
        plate = plate,
        owner = ownerName,
        modelLabel = modelLabel,
        validUntil = humanDate(untilDate),
        issuedAt = humanDate(sqlNow()),
        serial = 'BIZ-' .. tostring(math.random(100000, 999999)),
        price = price,
        currency = Config.Currency
    }
    TriggerClientEvent('realrpg_forgalmi:client:openInsurance', src, payload)
    notify(src, 'Kötelező biztosítás megkötve. Lejárat: ' .. humanDate(untilDate), 'success')
end)

RegisterNetEvent('realrpg_forgalmi:server:payTaxByPlate', function(plate)
    local src = source
    plate = trimPlate(plate)
    if not plate or not Config.Extras or not Config.Extras.Tax or not Config.Extras.Tax.Enabled then return end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local owned = getOwnedVehicle(plate)
    if not owned or (Config.OnlyOwnerCanUse and owned.owner ~= xPlayer.identifier) then
        notify(src, 'Ezt csak a jármű tulajdonosa intézheti.', 'error')
        return
    end

    local price = Config.Extras.Tax.BasePrice or 25000
    if not removePlayerMoney(xPlayer, price) then
        notify(src, ('Nincs elég pénzed. Szükséges: %s %s'):format(price, Config.Currency), 'error')
        return
    end

    local untilDate = sqlDateAfterDays(Config.Extras.Tax.ValidityDays or 30)
    MySQL.update.await('UPDATE `vehicle_documents` SET `tax_paid_until` = ? WHERE `plate` = ?', { untilDate, plate })
    notify(src, 'Járműadó befizetve. Érvényes eddig: ' .. humanDate(untilDate), 'success')
end)

RegisterNetEvent('realrpg_forgalmi:server:replaceDocumentByPlate', function(plate)
    local src = source
    plate = trimPlate(plate)
    if not plate or not Config.Extras or not Config.Extras.Replacement or not Config.Extras.Replacement.Enabled then return end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local owned = getOwnedVehicle(plate)
    if not owned or (Config.OnlyOwnerCanUse and owned.owner ~= xPlayer.identifier) then
        notify(src, 'Ezt csak a jármű tulajdonosa intézheti.', 'error')
        return
    end

    local doc = getDocumentByPlate(plate)
    if not doc or doc.status ~= 'valid' then
        notify(src, 'Ehhez a járműhöz nincs érvényes forgalmi.', 'error')
        return
    end

    local price = Config.Extras.Replacement.Price or 50000
    if not removePlayerMoney(xPlayer, price) then
        notify(src, ('Nincs elég pénzed. Szükséges: %s %s'):format(price, Config.Currency), 'error')
        return
    end

    giveOrUpdateDocumentItem(src, plate)
    notify(src, 'Forgalmi engedély pótolva.', 'success')
end)
