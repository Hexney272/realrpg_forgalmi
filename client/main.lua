local ESX = exports['es_extended']:getSharedObject()
local servicePed, officePed
local nuiOpen = false
local lastSent = { plate = nil, hash = nil, at = 0 }

local function dprint(...)
    if Config.Debug then
        print('[realrpg_forgalmi:client]', ...)
    end
end

local function notify(msg, nType)
    Config.ClientNotify(msg, nType or 'info')
end

local function requestModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    RequestModel(hash)
    local timeout = GetGameTimer() + 7000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(10)
    end
    return hash
end

local function createNpc(data)
    if not data or not data.Enabled then return nil end
    local model = requestModel(data.Model)
    if not HasModelLoaded(model) then
        print('[realrpg_forgalmi] NPC model nem tölthető be: ' .. tostring(data.Model))
        return nil
    end

    local c = data.Coords
    local ped = CreatePed(4, model, c.x, c.y, c.z, c.w or 0.0, false, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetPedCanRagdoll(ped, false)
    return ped
end

local function getLabelFromDisplay(display)
    if not display or display == '' then return 'Ismeretlen' end
    local label = GetLabelText(display)
    if not label or label == 'NULL' then return display end
    return label
end

local function trimPlate(plate)
    if not plate then return nil end
    plate = tostring(plate):gsub('^%s+', ''):gsub('%s+$', '')
    return plate:upper()
end

local function colorName(index)
    index = tonumber(index)
    return Config.ColorNames[index] or (index and ('szín #' .. index) or 'nincs')
end

local function tintName(index)
    index = tonumber(index)
    return Config.WindowTintNames[index] or (index and ('tint #' .. index) or 'nincs')
end

local function xenonName(index)
    index = tonumber(index)
    return Config.XenonColorNames[index] or (index and ('xenon #' .. index) or 'gyári')
end

local function rgbToName(r, g, b)
    r, g, b = tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0
    if r > 220 and g > 220 and b > 220 then return 'Fehér' end
    if r < 30 and g < 30 and b < 30 then return 'Fekete' end
    if r > g and r > b then return 'Piros' end
    if g > r and g > b then return 'Zöld' end
    if b > r and b > g then return 'Kék' end
    if r > 190 and g > 160 and b < 80 then return 'Sárga' end
    return ('RGB %d %d %d'):format(r, g, b)
end

local function modLevelLabel(vehicle, modType, prefix)
    local value = GetVehicleMod(vehicle, modType)
    if value == nil or value < 0 then return 'gyári' end
    local count = GetNumVehicleMods(vehicle, modType)
    if count and count > 0 then
        return ('%s %d/%d'):format(prefix or 'Tuning', value + 1, count)
    end
    return (prefix or 'Tuning') .. ' ' .. tostring(value + 1)
end

local function wheelLabel(vehicle)
    local mod = GetVehicleMod(vehicle, 23)
    if mod == nil or mod < 0 then return 'gyári' end
    local label = GetModTextLabel(vehicle, 23, mod)
    local text = getLabelFromDisplay(label)
    if text == label then
        return 'egyedi #' .. tostring(mod + 1)
    end
    return text
end

local function countOpticalTuning(vehicle)
    local count = 0
    local opticalMods = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 25, 27, 28, 29, 30, 31, 32, 33, 34, 35, 38, 39, 40, 41, 42, 43, 44, 45, 48}
    for _, modType in ipairs(opticalMods) do
        if GetVehicleMod(vehicle, modType) and GetVehicleMod(vehicle, modType) >= 0 then
            count = count + 1
        end
    end
    for extra = 0, 20 do
        if DoesExtraExist(vehicle, extra) and IsVehicleExtraTurnedOn(vehicle, extra) then
            count = count + 1
        end
    end
    return count > 0 and (tostring(count) .. ' db') or 'nincs'
end

local function neonLayout(vehicle)
    local labels = {}
    if IsVehicleNeonLightEnabled(vehicle, 0) then labels[#labels + 1] = 'Bal' end
    if IsVehicleNeonLightEnabled(vehicle, 1) then labels[#labels + 1] = 'Jobb' end
    if IsVehicleNeonLightEnabled(vehicle, 2) then labels[#labels + 1] = 'Elöl' end
    if IsVehicleNeonLightEnabled(vehicle, 3) then labels[#labels + 1] = 'Hátul' end
    if #labels == 0 then return 'nincs' end
    if #labels == 4 then return 'Körbe' end
    return table.concat(labels, ', ')
end

local function stableEncode(value)
    local t = type(value)
    if t == 'nil' then return 'nil' end
    if t == 'number' or t == 'boolean' then return tostring(value) end
    if t == 'string' then return ('%q'):format(value) end
    if t ~= 'table' then return tostring(value) end

    local isArray = true
    local max = 0
    local count = 0
    for k in pairs(value) do
        if type(k) ~= 'number' or k < 1 or k % 1 ~= 0 then
            isArray = false
            break
        end
        if k > max then max = k end
        count = count + 1
    end

    local parts = {}
    if isArray and max == count then
        for i = 1, max do
            parts[#parts + 1] = stableEncode(value[i])
        end
        return '[' .. table.concat(parts, ',') .. ']'
    end

    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        parts[#parts + 1] = tostring(k) .. '=' .. stableEncode(value[k])
    end
    return '{' .. table.concat(parts, ',') .. '}'
end

local function getVehicleModSnapshot(vehicle)
    local c1, c2 = GetVehicleColours(vehicle)
    local pearl, wheelColor = GetVehicleExtraColours(vehicle)
    local r, g, b = GetVehicleNeonLightsColour(vehicle)
    local smokeR, smokeG, smokeB = GetVehicleTyreSmokeColor(vehicle)
    local dash = GetVehicleDashboardColor(vehicle)
    local inter = GetVehicleInteriorColor(vehicle)

    local mods = {}
    for i = 0, 49 do
        mods[tostring(i)] = GetVehicleMod(vehicle, i)
    end

    local toggles = {
        turbo = IsToggleModOn(vehicle, 18),
        tyreSmoke = IsToggleModOn(vehicle, 20),
        xenon = IsToggleModOn(vehicle, 22)
    }

    local neon = {}
    for i = 0, 3 do neon[tostring(i)] = IsVehicleNeonLightEnabled(vehicle, i) end

    local extras = {}
    for i = 0, 20 do
        if DoesExtraExist(vehicle, i) then
            extras[tostring(i)] = IsVehicleExtraTurnedOn(vehicle, i)
        end
    end

    return {
        model = GetEntityModel(vehicle),
        plate = trimPlate(GetVehicleNumberPlateText(vehicle)),
        plateIndex = GetVehicleNumberPlateTextIndex(vehicle),
        colours = { primary = c1, secondary = c2, pearlescent = pearl, wheel = wheelColor, dashboard = dash, interior = inter },
        windowTint = GetVehicleWindowTint(vehicle),
        wheels = GetVehicleWheelType(vehicle),
        mods = mods,
        toggles = toggles,
        neon = neon,
        neonColor = { r = r, g = g, b = b },
        tyreSmoke = { r = smokeR, g = smokeG, b = smokeB },
        xenonColor = GetVehicleXenonLightsColor(vehicle),
        livery = GetVehicleLivery(vehicle),
        extras = extras
    }
end

local function getVehicleDisplayData(vehicle, modelName, modelLabel)
    local c1, c2 = GetVehicleColours(vehicle)
    local pearl, wheelColor = GetVehicleExtraColours(vehicle)
    local dash = GetVehicleDashboardColor(vehicle)
    local inter = GetVehicleInteriorColor(vehicle)
    local neonR, neonG, neonB = GetVehicleNeonLightsColour(vehicle)
    local fuelText = Config.VehicleFuelText[modelName] or Config.Document.DefaultFuelText
    local engineLevel = GetVehicleMod(vehicle, 11)
    local tier = engineLevel and engineLevel >= 0 and (engineLevel + 1) or Config.Document.DefaultTier
    local xenonOn = IsToggleModOn(vehicle, 22)
    local xenonColor = GetVehicleXenonLightsColor(vehicle)
    local neon = neonLayout(vehicle)

    return {
        type = modelLabel,
        fuel = fuelText,
        tier = tier,
        paintJob = 'nincs',
        roofPaint = 'nincs',
        primaryColor = colorName(c1),
        secondaryColor = colorName(c2),
        interiorColor = colorName(inter),
        dashboardColor = colorName(dash),
        rim = wheelLabel(vehicle),
        rimPaint = colorName(wheelColor),
        rimSticker = 'nincs',
        engine = modLevelLabel(vehicle, 11, 'Venom'),
        turbo = IsToggleModOn(vehicle, 18) and 'Venom' or 'gyári',
        transmission = modLevelLabel(vehicle, 13, 'Venom'),
        ecu = engineLevel and engineLevel >= 0 and 'Venom' or 'gyári',
        suspension = modLevelLabel(vehicle, 15, 'Venom'),
        tires = GetVehicleMod(vehicle, 23) >= 0 and 'Venom' or 'gyári',
        brakes = modLevelLabel(vehicle, 12, 'Venom'),
        weightReduction = GetVehicleMod(vehicle, 16) >= 0 and 'Venom' or 'gyári',
        frontCamber = 'gyári',
        rearCamber = 'gyári',
        frontTrack = 'gyári',
        rearTrack = 'gyári',
        steeringAngle = 'gyári',
        windowTint = tintName(GetVehicleWindowTint(vehicle)),
        lightType = xenonOn and 'Xenon' or 'gyári',
        lightColor = xenonOn and xenonName(xenonColor) or 'nincs',
        uniqueSound = 'nincs',
        backfire = 'nincs',
        opticalTuning = countOpticalTuning(vehicle),
        neonLayout = neon,
        neonType = neon ~= 'nincs' and 'Egyszínű' or 'nincs',
        neonColor = neon ~= 'nincs' and rgbToName(neonR, neonG, neonB) or 'nincs',
        identifier = '10'
    }
end

local function collectVehicleData(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end

    local plate = trimPlate(GetVehicleNumberPlateText(vehicle))
    if not plate then return nil end

    local modelHash = GetEntityModel(vehicle)
    local modelName = string.lower(GetDisplayNameFromVehicleModel(modelHash) or 'unknown')
    local modelLabel = getLabelFromDisplay(GetDisplayNameFromVehicleModel(modelHash))
    local makeName = ''

    local ok, make = pcall(function()
        return GetMakeNameFromVehicleModel(modelHash)
    end)
    if ok and make and make ~= '' then
        makeName = getLabelFromDisplay(make)
    end

    SetVehicleModKit(vehicle, 0)
    local snapshot = getVehicleModSnapshot(vehicle)
    local display = getVehicleDisplayData(vehicle, modelName, modelLabel)

    if Config.ExternalTuningDataExport then
        local resource, exportName = Config.ExternalTuningDataExport:match('([^:]+):(.+)')
        if resource and exportName and exports[resource] and exports[resource][exportName] then
            local okExternal, external = pcall(function()
                return exports[resource][exportName](vehicle)
            end)
            if okExternal and type(external) == 'table' then
                for k, v in pairs(external) do
                    display[k] = v
                end
            end
        end
    end

    local props = {}
    if ESX.Game and ESX.Game.GetVehicleProperties then
        props = ESX.Game.GetVehicleProperties(vehicle) or {}
    end

    local hash = tostring(GetHashKey(stableEncode(snapshot)))

    return {
        plate = plate,
        modelHash = modelHash,
        modelName = modelName,
        modelLabel = modelLabel,
        makeName = makeName,
        display = display,
        properties = props,
        modHash = hash
    }
end

local function getTargetVehicle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then return vehicle end

    local coords = GetEntityCoords(ped)
    local closestVehicle = GetClosestVehicle(coords.x, coords.y, coords.z, Config.VehicleSearchRadius, 0, 71)
    if closestVehicle ~= 0 then return closestVehicle end

    return 0
end

local pendingService = nil

local function buildServicePayload(data)
    return {
        company = Config.Inspection.CompanyName,
        plate = data.plate,
        vehicleName = data.modelLabel,
        currency = Config.Currency,
        inspection = {
            label = 'Műszaki vizsga',
            price = Config.Inspection.Price,
            time = '00:15'
        },
        fuel = {
            enabled = Config.Fuel.Enabled,
            label = Config.Fuel.Label,
            price = Config.Fuel.Price,
            time = '00:05'
        },
        duration = {
            repair = Config.Inspection.RepairDurationMinutes,
            club = Config.Inspection.ClubSpeedupMinutes,
            expected = Config.Inspection.ExpectedDurationMinutes
        },
        vehicleData = data
    }
end

local function openServiceNui(data)
    if not data then return end
    nuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openService',
        payload = buildServicePayload(data)
    })
end

-- Beolvassa a jármű adatait, és (ha kell) szerver oldali tulajdonos-ellenőrzést kér,
-- mielőtt megnyitná a NUI-t. Így csak a saját járműre nyílik meg.
local function requestService(vehicle)
    if vehicle == 0 then
        notify('Nincs jármű a közeledben.', 'error')
        return
    end

    local data = collectVehicleData(vehicle)
    if not data then
        notify('Nem sikerült beolvasni a jármű adatait.', 'error')
        return
    end

    if Config.ServiceMarker and Config.ServiceMarker.RequireOwnVehicle then
        pendingService = data
        TriggerServerEvent('realrpg_forgalmi:server:requestService', data.plate)
    else
        openServiceNui(data)
    end
end

-- NPC útvonal (ha valaki visszakapcsolja a ServiceNpc-t): a legközelebbi / beülős jármű.
local function openServiceMenu()
    requestService(getTargetVehicle())
end

-- A real_markers marker interakciója ide fut be (E gomb a markeren).
RegisterNetEvent('realrpg_forgalmi:client:serviceMarker', function()
    if nuiOpen then return end

    local sm = Config.ServiceMarker or {}
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then
        notify('Ülj be a járművedbe, amellyel a műszaki vizsgát szeretnéd elvégeztetni.', 'error')
        return
    end

    if sm.RequireDriverSeat and GetPedInVehicleSeat(vehicle, -1) ~= ped then
        notify('A vezetőülésben kell ülnöd a járműben a műszaki vizsgához.', 'error')
        return
    end

    requestService(vehicle)
end)

-- A szerver jóváhagyta (a jármű a sajátod) -> megnyitjuk a NUI-t.
RegisterNetEvent('realrpg_forgalmi:client:serviceApproved', function(plate)
    plate = trimPlate(plate)
    if pendingService and trimPlate(pendingService.plate) == plate then
        local data = pendingService
        pendingService = nil
        openServiceNui(data)
    end
end)

local function issueDocumentAtOffice()
    local vehicle = getTargetVehicle()
    if vehicle == 0 then
        notify('Állj azzal a járművel az Okmányiroda közelébe, amelyikhez a forgalmit kéred.', 'error')
        return
    end

    local data = collectVehicleData(vehicle)
    if not data then
        notify('Nem sikerült beolvasni a jármű adatait.', 'error')
        return
    end

    TriggerServerEvent('realrpg_forgalmi:server:issueDocument', data)
end

RegisterNUICallback('close', function(_, cb)
    nuiOpen = false
    SetNuiFocus(false, false)
    cb(true)
end)

RegisterNUICallback('serviceSubmit', function(payload, cb)
    nuiOpen = false
    SetNuiFocus(false, false)

    if not payload or type(payload.vehicleData) ~= 'table' then
        cb(false)
        return
    end

    TriggerServerEvent('realrpg_forgalmi:server:runInspection', payload.vehicleData, {
        inspection = payload.inspection == true,
        fuel = payload.fuel == true
    })
    cb(true)
end)

RegisterNetEvent('realrpg_forgalmi:client:openDocument', function(payload)
    nuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openDocument', payload = payload })
end)

RegisterNetEvent('realrpg_forgalmi:client:addFuel', function(liters)
    local vehicle = getTargetVehicle()
    if vehicle == 0 then return end
    local current = GetVehicleFuelLevel(vehicle)
    SetVehicleFuelLevel(vehicle, math.min(100.0, current + (tonumber(liters) or 0.0)))
end)

RegisterCommand('forgalmi_jarmu', function()
    local vehicle = getTargetVehicle()
    if vehicle == 0 then
        notify('Nincs jármű a közeledben.', 'error')
        return
    end
    local plate = trimPlate(GetVehicleNumberPlateText(vehicle))
    TriggerServerEvent('realrpg_forgalmi:server:openByPlate', plate)
end, false)

CreateThread(function()
    servicePed = createNpc(Config.ServiceNpc)
    officePed = createNpc(Config.OfficeNpc)

    if servicePed and exports.ox_target then
        exports.ox_target:addLocalEntity(servicePed, {
            {
                name = 'realrpg_forgalmi_service',
                label = Config.ServiceNpc.Label,
                icon = Config.ServiceNpc.Icon,
                distance = 2.0,
                onSelect = function()
                    openServiceMenu()
                end
            }
        })
    end

    if officePed and exports.ox_target then
        exports.ox_target:addLocalEntity(officePed, {
            {
                name = 'realrpg_forgalmi_office',
                label = Config.OfficeNpc.Label,
                icon = Config.OfficeNpc.Icon,
                distance = 2.0,
                onSelect = function()
                    issueDocumentAtOffice()
                end
            }
        })
    end
end)

-- A real_markers markerének regisztrálása (a szerviz NPC helyett).
local function registerServiceMarker()
    local sm = Config.ServiceMarker
    if not (sm and sm.Enabled) then return false end

    local res = sm.Resource or 'real_markers'
    if GetResourceState(res) ~= 'started' then return false end

    local ok, err = pcall(function()
        exports[res]:RegisterImageMarker(sm.Id or 'realrpg_inspection', {
            style = sm.Style or 'real_inspection',
            coords = sm.Coords,
            title = sm.Title,
            subtitle = sm.Subtitle,
            drawDistance = sm.DrawDistance or 30.0,
            interactDistance = sm.InteractDistance or 3.0,
            helpText = sm.HelpText or '~INPUT_CONTEXT~ Műszaki vizsga',
            event = 'realrpg_forgalmi:client:serviceMarker',
            serverEvent = false
        })
    end)

    if ok then
        print(('^2[realrpg_forgalmi]^7 Műszaki marker regisztrálva (id=%s) a(z) %s resource-ba: %s'):format(sm.Id or 'realrpg_inspection', res, tostring(sm.Coords)))
        return true
    end

    print('^1[realrpg_forgalmi]^7 Nem sikerült regisztrálni a műszaki markert: ' .. tostring(err))
    return false
end

CreateThread(function()
    local sm = Config.ServiceMarker
    if not (sm and sm.Enabled) then return end

    local res = sm.Resource or 'real_markers'
    local tries = 0
    while GetResourceState(res) ~= 'started' and tries < 100 do
        Wait(200)
        tries = tries + 1
    end

    if GetResourceState(res) ~= 'started' then
        print('^3[realrpg_forgalmi]^7 A(z) ' .. res .. ' resource nem fut (20s várakozás után sem), a műszaki marker nem jött létre. Indítsd el a real_markers-t (server.cfg), vagy állítsd Config.ServiceMarker.Enabled = false-ra és Config.ServiceNpc.Enabled = true-ra.')
        return
    end

    registerServiceMarker()
end)

-- Ha a real_markers (újra)indul, regisztráljuk újra a markert, különben elveszik.
AddEventHandler('onClientResourceStart', function(resourceName)
    local sm = Config.ServiceMarker
    if not (sm and sm.Enabled) then return end
    if resourceName ~= (sm.Resource or 'real_markers') then return end
    CreateThread(function()
        Wait(1500) -- megvárjuk, amíg a real_markers kliens oldala feláll
        registerServiceMarker()
    end)
end)

-- Diagnosztikai parancs: F8 konzolban kiírja az állapotot és újraregisztrál.
RegisterCommand('forgalmi_marker_debug', function()
    local sm = Config.ServiceMarker or {}
    local res = sm.Resource or 'real_markers'
    print(('^5[realrpg_forgalmi]^7 ServiceMarker.Enabled=%s | %s state=%s | Coords=%s'):format(
        tostring(sm.Enabled), res, GetResourceState(res), tostring(sm.Coords)))
    local done = registerServiceMarker()
    notify(done and 'Marker újraregisztrálva. Nézd az F8 konzolt.' or ('A(z) ' .. res .. ' nem fut vagy a marker ki van kapcsolva. Lásd F8.'), done and 'success' or 'error')
end, false)

CreateThread(function()
    if not Config.InvalidateOnModification then return end
    Wait(8000)

    while true do
        Wait(Config.ModificationCheckIntervalMs)
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
            local data = collectVehicleData(vehicle)
            if data then
                local now = GetGameTimer()
                if lastSent.plate ~= data.plate or lastSent.hash ~= data.modHash or now - lastSent.at > 60000 then
                    lastSent.plate = data.plate
                    lastSent.hash = data.modHash
                    lastSent.at = now
                    TriggerServerEvent('realrpg_forgalmi:server:modificationCheck', data)
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        if nuiOpen and IsControlJustReleased(0, 177) then
            nuiOpen = false
            SetNuiFocus(false, false)
            SendNUIMessage({ action = 'forceClose' })
        end
        Wait(0)
    end
end)

RegisterNetEvent('realrpg_forgalmi:client:useDocumentItem', function(item)
    local plate = item and item.metadata and item.metadata.plate
    plate = trimPlate(plate)
    if not plate then
        notify('Ez a forgalmi nem tartalmaz rendszám adatot.', 'error')
        return
    end
    TriggerServerEvent('realrpg_forgalmi:server:openByPlate', plate)
end)
