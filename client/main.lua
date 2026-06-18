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

    -- Fontos: sok mapon a megadott Z koordináta padlószint vagy túl magas/alacsony.
    -- Ezért először a közelbe spawnoljuk, betöltjük a collisiont, majd földre illesztjük.
    RequestCollisionAtCoord(c.x, c.y, c.z)
    local timeout = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(PlayerPedId()) and GetGameTimer() < timeout do
        Wait(25)
    end

    local ped = CreatePed(4, model, c.x, c.y, c.z - 1.0, c.w or 0.0, false, true)
    if not DoesEntityExist(ped) then
        print('[realrpg_forgalmi] NPC létrehozás sikertelen: ' .. tostring(data.Model))
        return nil
    end

    SetEntityAsMissionEntity(ped, true, true)
    SetEntityHeading(ped, c.w or 0.0)
    SetEntityCoordsNoOffset(ped, c.x, c.y, c.z - 1.0, false, false, false)
    PlaceEntityOnGroundProperly(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetPedCanRagdoll(ped, false)
    SetModelAsNoLongerNeeded(model)

    if Config.Debug then
        print(('[realrpg_forgalmi] NPC spawnolva: %s %.2f %.2f %.2f'):format(tostring(data.Model), c.x, c.y, c.z))
    end

    return ped
end

local function createBlip(coords, data)
    if not data or not data.enabled then return end
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, data.sprite or 1)
    SetBlipColour(blip, data.color or 0)
    SetBlipScale(blip, data.scale or 0.75)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(data.label or 'RealRPG')
    EndTextCommandSetBlipName(blip)
end

local function drawLocationMarker(coords)
    local m = Config.Interaction or {}
    local size = m.MarkerSize or { x = 1.1, y = 1.1, z = 0.25 }
    local color = m.MarkerColor or { r = 255, g = 204, b = 45, a = 170 }
    DrawMarker(
        m.MarkerType or 1,
        coords.x, coords.y, coords.z - 1.0,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        size.x or 1.1, size.y or 1.1, size.z or 0.25,
        color.r or 255, color.g or 204, color.b or 45, color.a or 170,
        false, true, 2, false, nil, nil, false
    )
end

local function showHelpText(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

local function oxTargetStarted()
    return GetResourceState('ox_target') == 'started'
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
        vehicleClass = GetVehicleClass(vehicle),
        health = {
            engine = GetVehicleEngineHealth(vehicle),
            body = GetVehicleBodyHealth(vehicle),
            tank = GetVehiclePetrolTankHealth(vehicle)
        },
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

local function openServiceMenu()
    local vehicle = getTargetVehicle()
    if vehicle == 0 then
        notify('Nincs jármű a közeledben.', 'error')
        return
    end

    local data = collectVehicleData(vehicle)
    if not data then
        notify('Nem sikerült beolvasni a jármű adatait.', 'error')
        return
    end

    nuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openService',
        payload = {
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
    })
end

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

    if Config.Extras and Config.Extras.OfficeQueue and Config.Extras.OfficeQueue.Enabled then
        local num = math.random(1, 999)
        notify(('Sorszám: %s-%03d | Ügyintézés folyamatban...'):format(Config.Extras.OfficeQueue.Prefix or 'A', num), 'info')
        Wait(Config.Extras.OfficeQueue.DurationMs or 15000)
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
    Wait(1000)

    servicePed = createNpc(Config.ServiceNpc)
    officePed = createNpc(Config.OfficeNpc)

    if Config.Blips then
        if Config.ServiceNpc and Config.ServiceNpc.Coords then
            createBlip(Config.ServiceNpc.Coords, Config.Blips.Service)
        end
        if Config.OfficeNpc and Config.OfficeNpc.Coords then
            createBlip(Config.OfficeNpc.Coords, Config.Blips.Office)
        end
    end

    local useTarget = Config.Interaction and Config.Interaction.UseOxTarget and oxTargetStarted()

    if useTarget and servicePed then
        exports.ox_target:addLocalEntity(servicePed, {
            {
                name = 'realrpg_forgalmi_service',
                label = Config.ServiceNpc.Label,
                icon = Config.ServiceNpc.Icon,
                distance = Config.Interaction.InteractDistance or 2.2,
                onSelect = function()
                    openServiceMenu()
                end
            }
        })
    end

    if useTarget and officePed then
        exports.ox_target:addLocalEntity(officePed, {
            {
                name = 'realrpg_forgalmi_office',
                label = Config.OfficeNpc.Label,
                icon = Config.OfficeNpc.Icon,
                distance = Config.Interaction.InteractDistance or 2.2,
                onSelect = function()
                    issueDocumentAtOffice()
                end
            }
        })
    end

    if Config.Debug then
        print('[realrpg_forgalmi] ox_target aktív: ' .. tostring(useTarget))
    end
end)

CreateThread(function()
    Wait(1500)
    if not Config.Interaction or not Config.Interaction.DrawMarkers then return end

    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local pcoords = GetEntityCoords(ped)
        local markerDistance = Config.Interaction.MarkerDistance or 25.0
        local interactDistance = Config.Interaction.InteractDistance or 2.2
        local key = Config.Interaction.Key or 38

        if Config.ServiceNpc and Config.ServiceNpc.Enabled and Config.ServiceNpc.Coords then
            local c = Config.ServiceNpc.Coords
            local dist = #(pcoords - vector3(c.x, c.y, c.z))
            if dist <= markerDistance then
                sleep = 0
                drawLocationMarker(c)
                if dist <= interactDistance then
                    showHelpText(Config.Interaction.HelpTextService or '~INPUT_CONTEXT~ Műszaki vizsga')
                    if IsControlJustReleased(0, key) then
                        openServiceMenu()
                    end
                end
            end
        end

        if Config.OfficeNpc and Config.OfficeNpc.Enabled and Config.OfficeNpc.Coords then
            local c = Config.OfficeNpc.Coords
            local dist = #(pcoords - vector3(c.x, c.y, c.z))
            if dist <= markerDistance then
                sleep = 0
                drawLocationMarker(c)
                if dist <= interactDistance then
                    showHelpText(Config.Interaction.HelpTextOffice or '~INPUT_CONTEXT~ Forgalmi engedély')
                    if IsControlJustReleased(0, key) then
                        issueDocumentAtOffice()
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

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

-- EXTRA RP FUNKCIÓK: biztosítás, adó, pótlás, rendszámcsere, hamis forgalmi
local illegalPed

local function keyboardInput(title, defaultText, maxLength)
    AddTextEntry('REALRPG_FORGALMI_INPUT', title or 'Adat megadása')
    DisplayOnscreenKeyboard(1, 'REALRPG_FORGALMI_INPUT', '', defaultText or '', '', '', '', maxLength or 32)
    while UpdateOnscreenKeyboard() == 0 do
        Wait(0)
    end
    if UpdateOnscreenKeyboard() == 1 then
        return GetOnscreenKeyboardResult()
    end
    return nil
end

local function sendVehicleAction(eventName, extra)
    local vehicle = getTargetVehicle()
    if vehicle == 0 then
        notify('Nincs jármű a közeledben.', 'error')
        return
    end
    local data = collectVehicleData(vehicle)
    if not data then
        notify('Nem sikerült beolvasni a jármű adatait.', 'error')
        return
    end
    if extra ~= nil then
        TriggerServerEvent(eventName, data, extra)
    else
        TriggerServerEvent(eventName, data)
    end
end

RegisterCommand('biztositas', function()
    sendVehicleAction('realrpg_forgalmi:server:buyInsurance')
end, false)

RegisterCommand('jarmuado', function()
    sendVehicleAction('realrpg_forgalmi:server:payVehicleTax')
end, false)

RegisterCommand('forgalmi_potlas', function()
    sendVehicleAction('realrpg_forgalmi:server:replaceDocument')
end, false)

RegisterCommand('rendszamcsere', function()
    local newPlate = keyboardInput('Új rendszám', '', 8)
    if not newPlate or newPlate == '' then return end
    sendVehicleAction('realrpg_forgalmi:server:changePlate', newPlate)
end, false)

RegisterCommand('hamisforgalmi', function(_, args)
    local quality = args and args[1] or 'medium'
    sendVehicleAction('realrpg_forgalmi:server:createFakeDocument', quality)
end, false)

RegisterNetEvent('realrpg_forgalmi:client:setVehiclePlate', function(oldPlate, newPlate)
    oldPlate = trimPlate(oldPlate)
    newPlate = trimPlate(newPlate)
    local vehicle = getTargetVehicle()
    if vehicle ~= 0 and trimPlate(GetVehicleNumberPlateText(vehicle)) == oldPlate then
        SetVehicleNumberPlateText(vehicle, newPlate)
    end
end)

CreateThread(function()
    Wait(3500)
    local useTarget = Config.Interaction and Config.Interaction.UseOxTarget and oxTargetStarted()

    if useTarget and officePed then
        exports.ox_target:addLocalEntity(officePed, {
            {
                name = 'realrpg_forgalmi_insurance',
                label = 'Kötelező biztosítás megkötése',
                icon = 'fa-solid fa-shield-halved',
                distance = Config.Interaction.InteractDistance or 2.2,
                onSelect = function() sendVehicleAction('realrpg_forgalmi:server:buyInsurance') end
            },
            {
                name = 'realrpg_forgalmi_tax',
                label = 'Járműadó befizetése',
                icon = 'fa-solid fa-file-invoice-dollar',
                distance = Config.Interaction.InteractDistance or 2.2,
                onSelect = function() sendVehicleAction('realrpg_forgalmi:server:payVehicleTax') end
            },
            {
                name = 'realrpg_forgalmi_replace',
                label = 'Forgalmi pótlása',
                icon = 'fa-solid fa-copy',
                distance = Config.Interaction.InteractDistance or 2.2,
                onSelect = function() sendVehicleAction('realrpg_forgalmi:server:replaceDocument') end
            },
            {
                name = 'realrpg_forgalmi_platechange',
                label = 'Rendszámcsere / egyedi rendszám',
                icon = 'fa-solid fa-rectangle-list',
                distance = Config.Interaction.InteractDistance or 2.2,
                onSelect = function()
                    local newPlate = keyboardInput('Új rendszám', '', 8)
                    if newPlate and newPlate ~= '' then
                        sendVehicleAction('realrpg_forgalmi:server:changePlate', newPlate)
                    end
                end
            }
        })
    end

    if Config.IllegalNpc and Config.IllegalNpc.Enabled then
        illegalPed = createNpc(Config.IllegalNpc)
        if useTarget and illegalPed then
            exports.ox_target:addLocalEntity(illegalPed, {
                {
                    name = 'realrpg_forgalmi_fake_weak',
                    label = 'Hamis forgalmi - gyenge minőség',
                    icon = Config.IllegalNpc.Icon or 'fa-solid fa-mask',
                    distance = Config.Interaction.InteractDistance or 2.2,
                    onSelect = function() sendVehicleAction('realrpg_forgalmi:server:createFakeDocument', 'weak') end
                },
                {
                    name = 'realrpg_forgalmi_fake_medium',
                    label = 'Hamis forgalmi - közepes minőség',
                    icon = Config.IllegalNpc.Icon or 'fa-solid fa-mask',
                    distance = Config.Interaction.InteractDistance or 2.2,
                    onSelect = function() sendVehicleAction('realrpg_forgalmi:server:createFakeDocument', 'medium') end
                },
                {
                    name = 'realrpg_forgalmi_fake_pro',
                    label = 'Hamis forgalmi - profi minőség',
                    icon = Config.IllegalNpc.Icon or 'fa-solid fa-mask',
                    distance = Config.Interaction.InteractDistance or 2.2,
                    onSelect = function() sendVehicleAction('realrpg_forgalmi:server:createFakeDocument', 'professional') end
                }
            })
        end
    end
end)

CreateThread(function()
    Wait(1500)
    if not Config.IllegalNpc or not Config.IllegalNpc.Enabled or not Config.Interaction or not Config.Interaction.DrawMarkers then return end
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local pcoords = GetEntityCoords(ped)
        local c = Config.IllegalNpc.Coords
        local dist = #(pcoords - vector3(c.x, c.y, c.z))
        if dist <= (Config.Interaction.MarkerDistance or 25.0) then
            sleep = 0
            drawLocationMarker(c)
            if dist <= (Config.Interaction.InteractDistance or 2.2) then
                showHelpText('~INPUT_CONTEXT~ Hamis forgalmi készítése')
                if IsControlJustReleased(0, Config.Interaction.Key or 38) then
                    sendVehicleAction('realrpg_forgalmi:server:createFakeDocument', 'medium')
                end
            end
        end
        Wait(sleep)
    end
end)

RegisterNetEvent('realrpg_forgalmi:client:useFakeDocumentItem', function(item)
    TriggerServerEvent('realrpg_forgalmi:server:openFakeDocument', item)
end)
