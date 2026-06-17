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
