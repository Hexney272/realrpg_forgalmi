-- Ezt másold az ox_inventory/data/items.lua (vagy az egyéni inventory items listája) fájlba.
-- FONTOS: a category = 'docs' biztosítja, hogy a dokumentumok a "Dokumentumok"
-- fülre kerüljenek (nem a Tárgyak fülre), így nem írja azt hogy "nincs hely",
-- amikor a Tárgyak fül tele van.

['forgalmi_engedely'] = {
    label = 'Forgalmi engedély',
    weight = 50,
    stack = false,
    close = true,
    consume = 0,
    category = 'docs',
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
    category = 'docs',
    description = 'Járműhöz tartozó szerviz munkalap',
    client = { image = 'szerviz_munkalap.png' }
},

['adasveteli_szerzodes'] = {
    label = 'Adásvételi szerződés',
    weight = 20,
    stack = false,
    close = true,
    consume = 0,
    category = 'docs',
    description = 'Jármű adásvételi szerződés',
    client = { image = 'adasveteli_szerzodes.png' }
},

['kotelezo_biztositas'] = {
    label = 'Kötelező biztosítás',
    weight = 20,
    stack = false,
    close = true,
    consume = 0,
    category = 'docs',
    description = 'Kötelező gépjármű-felelősségbiztosítás',
    client = { image = 'kotelezo_biztositas.png' }
},

['hamis_forgalmi'] = {
    label = 'Hamis forgalmi engedély',
    weight = 50,
    stack = false,
    close = true,
    consume = 0,
    category = 'docs',
    description = 'Hamisított jármű forgalmi engedély',
    client = {
        image = 'hamis_forgalmi.png',
        event = 'realrpg_forgalmi:client:useFakeDocumentItem'
    }
},
