Config = {}

-- ALAP BEÁLLÍTÁSOK
Config.Debug = true
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
    CompanyName = 'REAL OF LOS SANTOS',
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

-- NPC-k / helyszínek. Írd át a saját pályádhoz.
Config.ServiceNpc = {
    Enabled = true,
    Model = 's_m_m_autoshop_01',
    Coords = { x = -347.28, y = -133.46, z = 38.01, w = 70.0 },
    Label = 'Műszaki vizsga',
    Icon = 'fa-solid fa-screwdriver-wrench',
    Name = 'Szabó Márk'  -- Ez jelenik meg az NPC feje felett
}

Config.OfficeNpc = {
    Enabled = true,
    Model = 'a_f_y_business_01',
    Coords = { x = -542.14, y = -208.54, z = 37.64, w = 210.0 },
    Label = 'Forgalmi engedély kiállítása',
    Icon = 'fa-solid fa-id-card',
    Name = 'Kovács Anna',
    Title = 'OkmányIroda'
}

-- Okmányiroda marker (real_markers): az NPC előtt, szöveg/badge nélkül.
Config.OfficeMarker = {
    Enabled = false,
    Resource = 'real_markers',
    Id = 'realrpg_office',
    Style = 'document',
    Coords = vec3(-542.14, -208.54, 37.64),
    DrawDistance = 25.0,
    InteractDistance = 2.5,
    HelpText = '~INPUT_CONTEXT~ Forgalmi engedély kiállítása',
    ShowBadge = false    -- NEM jelenik meg NUI badge/szöveg, csak a marker
}



-- LÁTHATÓ NPC / MARKER BEÁLLÍTÁSOK
-- Ha nem használod az ox_targetet vagy bármiért nem indulna el, a marker akkor is működik.
Config.Interaction = {
    UseOxTarget = true,
    DrawMarkers = true,
    MarkerDistance = 25.0,
    InteractDistance = 2.2,
    Key = 38, -- E
    MarkerType = 1,
    MarkerSize = { x = 1.1, y = 1.1, z = 0.25 },
    MarkerColor = { r = 255, g = 204, b = 45, a = 170 },
    HelpTextService = '~INPUT_CONTEXT~ Műszaki vizsga megnyitása',
    HelpTextOffice = '~INPUT_CONTEXT~ Forgalmi engedély kiállítása'
}

Config.Blips = {
    Service = { enabled = true, sprite = 446, color = 5, scale = 0.75, label = 'RealRPG Műszaki vizsga' },
    Office = { enabled = true, sprite = 498, color = 5, scale = 0.75, label = 'RealRPG Okmányiroda' }
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

-- EXTRA RP RENDSZEREK
Config.Extras = {
    Insurance = {
        Enabled = true,
        Price = 75000,
        ValidityDays = 30,
        Label = 'Kötelező biztosítás'
    },
    Tax = {
        Enabled = true,
        BasePrice = 25000,
        ValidityDays = 30,
        PricesByClass = {
            [0] = 25000, [1] = 25000, [2] = 35000, [3] = 35000, [4] = 45000,
            [5] = 60000, [6] = 75000, [7] = 120000, [8] = 20000, [9] = 50000,
            [10] = 90000, [11] = 80000, [12] = 65000, [13] = 10000, [14] = 70000,
            [15] = 150000, [16] = 150000, [17] = 80000, [18] = 100000, [19] = 100000,
            [20] = 150000, [21] = 150000, [22] = 250000
        },
        Label = 'Járműadó'
    },
    Replacement = {
        Enabled = true,
        Price = 50000,
        Label = 'Forgalmi pótlása'
    },
    PlateChange = {
        Enabled = true,
        NormalPrice = 100000,
        CustomPrice = 500000,
        MinLength = 2,
        MaxLength = 8,
        AllowCustom = true
    },
    OfficeQueue = {
        Enabled = true,
        DurationMs = 15000,
        Prefix = 'A'
    },
    WorkOrder = {
        Enabled = true,
        ItemName = 'szerviz_munkalap'
    },
    SaleContract = {
        Enabled = true,
        ItemName = 'adasveteli_szerzodes',
        TransferFee = 50000,
        PendingMinutes = 10
    },
    FakeDocument = {
        Enabled = true,
        ItemName = 'hamis_forgalmi',
        Prices = { weak = 250000, medium = 500000, professional = 1000000 },
        DetectionChance = { weak = 65, medium = 30, professional = 10 }
    },
    Wanted = {
        Enabled = true,
        AdminGroups = { admin = true, superadmin = true, owner = true }
    },
    InspectionHealth = {
        Enabled = true,
        MinEngine = 850.0,
        MinBody = 850.0,
        MinTank = 900.0
    },
    Garage = {
        BlockIfInspectionInvalid = false,
        BlockIfInsuranceExpired = false,
        BlockIfTaxExpired = false
    }
}

Config.IllegalNpc = {
    Enabled = false,
    Model = 'g_m_y_mexgoon_02',
    Coords = { x = 707.42, y = -966.83, z = 30.41, w = 180.0 },
    Label = 'Hamis forgalmi készítése',
    Icon = 'fa-solid fa-mask'
}

Config.Discord = {
    Enabled = false,
    Webhook = '',
    Name = 'RealRPG Forgalmi Log',
    Color = 16762624
}
