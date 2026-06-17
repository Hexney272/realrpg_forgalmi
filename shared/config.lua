Config = {}

-- ALAP BEÁLLÍTÁSOK
Config.Debug = false
Config.ItemName = 'forgalmi_engedely'
Config.MoneyAccount = 'money' -- money = készpénz, bank = bankszámla
Config.Currency = 'Ft'
Config.AutoCreateDatabase = true

-- ADATBÁZIS BEÁLLÍTÁSOK
Config.VehicleTable = 'owned_vehicles'
Config.VehicleOwnerColumn = 'owner'
Config.VehiclePlateColumn = 'plate'
Config.VehicleDataColumn = 'vehicle'
Config.UsersTable = 'users'
Config.UsersIdentifierColumn = 'identifier'
Config.UsersFirstnameColumn = 'firstname'
Config.UsersLastnameColumn = 'lastname'
Config.UsersNameColumn = 'name'

-- Csak a saját járművére lehessen műszakit / forgalmit intézni.
Config.OnlyOwnerCanUse = true

-- MŰSZAKI VIZSGA
Config.Inspection = {
    Price = 150000,
    ValidityDays = 365,
    CompanyName = 'VAPID OF LOS SANTOS',
    RepairDurationMinutes = 0,
    ClubSpeedupMinutes = 0,
    ExpectedDurationMinutes = 0
}

-- A második képen látható 5L üzemanyag sor. Kikapcsolható, de alapból benne van.
Config.Fuel = {
    Enabled = true,
    Label = '5L üzemanyag',
    Liters = 5,
    Price = 25000
}

-- Automatikusan érvényteleníti a forgalmit, ha a jármű tuning / festés / optika változik.
Config.InvalidateOnModification = true
Config.ModificationCheckIntervalMs = 12000
Config.VehicleSearchRadius = 8.0

-- MŰSZAKI VIZSGA HELYSZÍN: real_markers marker (a szerviz NPC helyett).
-- A marker felett ÁLLVA, a SAJÁT járművedben (vezetőülésben) ülve nyílik meg a NUI.
Config.ServiceMarker = {
    Enabled = true,                 -- true: a real_markers markert használja az NPC helyett
    Resource = 'real_markers',      -- a marker resource neve
    Id = 'realrpg_inspection',      -- egyedi marker azonosító
    Style = 'real_inspection',      -- real_markers style (MŰSZAKI VIZSGA)
    Coords = vec3(-347.28, -133.46, 38.01),
    Title = 'MŰSZAKI VIZSGA',
    Subtitle = 'Ülj a járművedbe és nyomd meg az E-t',
    HelpText = '~INPUT_CONTEXT~ Műszaki vizsga (ülj a saját járművedben)',
    DrawDistance = 30.0,
    InteractDistance = 3.5,
    RequireOwnVehicle = true,       -- csak a saját (owned_vehicles) járművedre nyíljon meg
    RequireDriverSeat = true        -- a vezetőülésben kell ülnöd
}

-- NPC-k / helyszínek. Írd át a saját pályádhoz.
-- A szerviz (műszaki) NPC alapból KI van kapcsolva, mert a Config.ServiceMarker
-- markert használjuk helyette. Ha mégis NPC-t szeretnél, állítsd ServiceMarker.Enabled = false-ra
-- és ServiceNpc.Enabled = true-ra.
Config.ServiceNpc = {
    Enabled = false,
    Model = 's_m_m_autoshop_01',
    Coords = { x = -347.28, y = -133.46, z = 38.01, w = 70.0 },
    Label = 'Műszaki vizsga',
    Icon = 'fa-solid fa-screwdriver-wrench'
}

Config.OfficeNpc = {
    Enabled = true,
    Model = 'a_f_y_business_01',
    Coords = { x = -552.67, y = -192.62, z = 37.22, w = 210.0 },
    Label = 'Forgalmi engedély kiállítása',
    Icon = 'fa-solid fa-id-card'
}

-- FORGALMI ENGEDÉLY KINÉZET
Config.Document = {
    CityName = 'Real City',
    Title = 'Forgalmi engedély',
    Logo = 'REAL',
    SerialPrefix = 'NJ',
    InvalidStamp = 'ÉRVÉNYTELEN',
    IssuerLabel = 'KIÁLLÍTÁS IDŐPONTJA',
    DefaultFuelText = 'Dízel (40 L)',
    DefaultTier = 1
}

-- Jármű üzemanyag típus felülírás modellekhez. Példa: ['sultan'] = 'Benzin (50 L)'
Config.VehicleFuelText = {}

-- Átírás, ha egy kiegészítő tuning scriptedből exporttal akarod adni az értékeket.
-- Ha üres, a GTA/FiveM native értékekből számolja ki.
Config.ExternalTuningDataExport = nil -- pl. 'my_tuning_resource:getVehicleDocData'

-- Értesítés
Config.Notify = function(source, message, nType)
    TriggerClientEvent('esx:showNotification', source, message)
end

Config.ClientNotify = function(message, nType)
    ESX.ShowNotification(message)
end

-- Színnevek. A FiveM/GTA szín indexeket ezekre fordítja a forgalmi.
Config.ColorNames = {
    [0] = 'Fekete', [1] = 'Grafit', [2] = 'Fekete metál', [3] = 'Ezüst', [4] = 'Kék ezüst',
    [5] = 'Acél szürke', [6] = 'Árnyék ezüst', [7] = 'Kő ezüst', [8] = 'Éj ezüst', [9] = 'Öntött ezüst',
    [10] = 'Piros', [11] = 'Torino piros', [12] = 'Formula piros', [13] = 'Láva piros', [14] = 'Grace piros',
    [15] = 'Garnet piros', [16] = 'Cabernet piros', [17] = 'Bor vörös', [18] = 'Candy piros', [19] = 'Hot pink',
    [20] = 'Pfsiter pink', [21] = 'Lazac pink', [22] = 'Nap narancs', [23] = 'Narancs', [24] = 'Bronz',
    [25] = 'Sárga', [26] = 'Verseny sárga', [27] = 'Harmat zöld', [28] = 'Oliva zöld', [29] = 'Sötét zöld',
    [30] = 'Benzin zöld', [31] = 'Lime zöld', [32] = 'Éjkék', [33] = 'Galaxy kék', [34] = 'Sötét kék',
    [35] = 'Szász kék', [36] = 'Kék', [37] = 'Mariner kék', [38] = 'Harbor kék', [39] = 'Diamond kék',
    [40] = 'Surf kék', [41] = 'Nautical kék', [42] = 'Racing kék', [43] = 'Ultra kék', [44] = 'Világos kék',
    [45] = 'Csokoládé barna', [46] = 'Bison barna', [47] = 'Creeen barna', [48] = 'Feltzer barna', [49] = 'Maple barna',
    [50] = 'Bükk barna', [51] = 'Sienna barna', [52] = 'Saddle barna', [53] = 'Moss barna', [54] = 'Wood barna',
    [55] = 'Straw barna', [56] = 'Sandy barna', [57] = 'Bleached barna', [58] = 'Schafter lila', [59] = 'Spinnaker lila',
    [60] = 'Midnight lila', [61] = 'Bright lila', [62] = 'Cream', [63] = 'Jég fehér', [64] = 'Fagy fehér',
    [111] = 'Fehér', [112] = 'Fagy fehér', [120] = 'Króm', [131] = 'Fehér', [134] = 'Tiszta fehér'
}

Config.WindowTintNames = {
    [-1] = 'nincs', [0] = 'nincs', [1] = 'Pure black', [2] = 'Dark smoke', [3] = 'Light smoke', [4] = 'Stock', [5] = 'Limo', [6] = 'Green'
}

Config.XenonColorNames = {
    [-1] = 'gyári', [0] = 'Fehér', [1] = 'Kék', [2] = 'Elektromos kék', [3] = 'Mentazöld', [4] = 'Lime',
    [5] = 'Sárga', [6] = 'Arany', [7] = 'Narancs', [8] = 'Piros', [9] = 'Pony pink', [10] = 'Hot pink',
    [11] = 'Lila', [12] = 'Blacklight'
}
