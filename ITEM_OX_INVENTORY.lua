-- Ezt másold az ox_inventory/data/items.lua fájlba:

['forgalmi_engedely'] = {
    label = 'Forgalmi engedély',
    weight = 50,
    stack = false,
    close = true,
    consume = 0,
    description = 'Jármű forgalmi engedély',
    client = {
        image = 'forgalmi_engedely.png',
        event = 'realrpg_forgalmi:client:useDocumentItem'
    }
},

['szerviz_munkalap'] = {
    label = 'Szerviz munkalap',
    weight = 20,
    stack = false,
    close = true,
    consume = 0,
    description = 'Járműhöz tartozó szerviz munkalap',
    client = { image = 'szerviz_munkalap.png' }
},

['adasveteli_szerzodes'] = {
    label = 'Adásvételi szerződés',
    weight = 20,
    stack = false,
    close = true,
    consume = 0,
    description = 'Jármű adásvételi szerződés',
    client = { image = 'adasveteli_szerzodes.png' }
},

['hamis_forgalmi'] = {
    label = 'Hamis forgalmi engedély',
    weight = 50,
    stack = false,
    close = true,
    consume = 0,
    description = 'Hamisított jármű forgalmi engedély',
    client = {
        image = 'hamis_forgalmi.png',
        event = 'realrpg_forgalmi:client:useFakeDocumentItem'
    }
},
