local ESX = exports['es_extended']:getSharedObject()
local registeredItem = false
local lastModCheck = {}

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
    return ('%s. %s. %s.  %s:%s'):format(y, m, d, h, mi)
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
    return ('CHSEE%sN%s'):format(clean:sub(1, 5), tostring(hash):sub(1, 6))
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

local userColumnsCache = nil
local function getUserColumns()
    if userColumnsCache then return userColumnsCache end
    userColumnsCache = {}

    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT `COLUMN_NAME` AS col
            FROM `INFORMATION_SCHEMA`.`COLUMNS`
            WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = ?
        ]], { Config.UsersTable })
    end)

    if ok and type(rows) == 'table' then
        for _, r in ipairs(rows) do
            if r and r.col then
                userColumnsCache[tostring(r.col):lower()] = true
            end
        end
    end

    return userColumnsCache
end

local function getOwnerName(identifier)
    if not identifier then return 'Ismeretlen tulajdonos' end

    local cols = getUserColumns()
    local selectParts = {}

    local firstCol = Config.UsersFirstnameColumn
    local lastCol = Config.UsersLastnameColumn
    local nameCol = Config.UsersNameColumn

    -- Ha nem sikerült beolvasni az oszloplistát, próbáljuk a configban megadottakat.
    local schemaKnown = next(cols) ~= nil
    local hasFirst = firstCol and (not schemaKnown or cols[firstCol:lower()])
    local hasLast = lastCol and (not schemaKnown or cols[lastCol:lower()])
    local hasName = nameCol and schemaKnown and cols[nameCol:lower()]

    if hasFirst then selectParts[#selectParts + 1] = ('`%s` AS firstname'):format(firstCol) end
    if hasLast then selectParts[#selectParts + 1] = ('`%s` AS lastname'):format(lastCol) end
    if hasName then selectParts[#selectParts + 1] = ('`%s` AS name'):format(nameCol) end

    if #selectParts == 0 then return tostring(identifier) end

    local query = ('SELECT %s FROM `%s` WHERE `%s` = ? LIMIT 1'):format(
        table.concat(selectParts, ', '),
        Config.UsersTable,
        Config.UsersIdentifierColumn
    )

    local row = MySQL.single.await(query, { identifier })
    if row then
        local first = row.firstname and tostring(row.firstname) or ''
        local last = row.lastname and tostring(row.lastname) or ''
        local full = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+$', '')
        if full ~= '' then return full end
        if row.name and tostring(row.name) ~= '' then return tostring(row.name) end
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

    return {
        serial = doc.serial or randomSerial(),
        status = doc.status,
        invalid = doc.status ~= 'valid',
        invalidText = Config.Document.InvalidStamp,
        invalidReason = doc.invalid_reason or (doc.status == 'inspected' and 'Forgalmi még nincs kiállítva' or 'Érvénytelen forgalmi'),
        fields = display
    }
end

RegisterNetEvent('realrpg_forgalmi:server:requestService', function(plate)
    local src = source
    plate = trimPlate(plate)
    if not plate then
        notify(src, 'Nem található rendszám.', 'error')
        return
    end

    local owned, xPlayer, ownerErr = validateOwner(src, plate)
    if ownerErr then
        notify(src, ownerErr, 'error')
        return
    end

    -- A jármű a sajátod -> jelezzük a kliensnek, hogy nyithatja a NUI-t.
    TriggerClientEvent('realrpg_forgalmi:client:serviceApproved', src, plate)
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
