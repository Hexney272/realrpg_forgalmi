# RealRPG Forgalmi rendszer V3 - Extra RP csomag

ESX Legacy + ox_inventory + ox_target + oxmysql alapú jármű forgalmi / okmányiroda / műszaki rendszer.

## Alap funkciók
- `forgalmi_engedely` item használatakor megnyíló Real City forgalmi NUI.
- Szerviz NPC műszaki vizsgával.
- Okmányiroda NPC forgalmi kiállítással.
- Automatikus érvénytelenítés tuning / festés / optika módosítás után.
- Marker + blip + ox_target + E gomb fallback.

## V3 extra funkciók
Az 1. rendőrségi rendszámlekérdezés direkt NINCS benne, mert azt nem kérted.

Benne van viszont:
- Kötelező biztosítás rendszer.
- Járműadó / súlyadó rendszer járműosztály alapján.
- Forgalmi pótlás.
- Automatikus műszaki lejárat.
- Jármű állapot alapú műszaki vizsga: motor, kasztni, tank állapot minimum.
- Szerviz munkalap item.
- Okmányiroda sorszámos várakozási idő.
- Adásvételi rendszer.
- Hamis forgalmi rendszer illegális NPC-vel / paranccsal.
- Rendszámcsere / egyedi rendszám.
- Egyedi okmányazonosító mező adatbázisban.
- Admin körözési státusz járművekre.
- Discord webhook log.
- Garázs integrációs exportok.

## Telepítés
1. Másold a `realrpg_forgalmi` mappát a resources mappába.
2. `server.cfg`:

```cfg
ensure oxmysql
ensure es_extended
ensure ox_inventory
ensure ox_target
ensure realrpg_forgalmi
```

3. Másold az `ITEM_OX_INVENTORY.lua` tartalmát az `ox_inventory/data/items.lua` fájlba.
4. Másold az `ox_inventory_images` képeit az `ox_inventory/web/images/` mappába.
5. A koordinátákat a `shared/config.lua` fájlban állítsd át.

## Fontos config részek
`shared/config.lua`:

```lua
Config.Extras.Insurance.Price = 75000
Config.Extras.Tax.BasePrice = 25000
Config.Extras.Replacement.Price = 50000
Config.Extras.PlateChange.NormalPrice = 100000
Config.Extras.PlateChange.CustomPrice = 500000
Config.Extras.InspectionHealth.MinEngine = 850.0
Config.Extras.InspectionHealth.MinBody = 850.0
Config.Extras.InspectionHealth.MinTank = 900.0
```

Illegális hamis forgalmi NPC alapból ki van kapcsolva:

```lua
Config.IllegalNpc.Enabled = false
```

Ha kell, állítsd `true`-ra és írd át a koordinátát.

## Hasznos parancsok
- `/biztositas` - biztosítás megkötése a közelben lévő járműre.
- `/jarmuado` - járműadó befizetése.
- `/forgalmi_potlas` - forgalmi pótlása.
- `/rendszamcsere` - új rendszám megadása képernyő billentyűzettel.
- `/adasvetel [játékosID] [ár] [rendszám]` - adásvételi ajánlat.
- `/adasvetel_elfogad [rendszám]` - adásvételi ajánlat elfogadása.
- `/hamisforgalmi weak|medium|professional` - hamis forgalmi készítése, ha engedélyezve van.
- `/jarmu_korozes [rendszám] [1/0] [indok]` - admin jármű körözési státusz.

## Exportok garázshoz
```lua
local status = exports.realrpg_forgalmi:GetVehicleDocumentStatus(plate)
local canTake, reason = exports.realrpg_forgalmi:CanTakeVehicleFromGarage(plate)
```

Példa garázs blokkolás:

```lua
local canTake, reason = exports.realrpg_forgalmi:CanTakeVehicleFromGarage(plate)
if not canTake then
    ESX.ShowNotification('Nem veheted ki a járművet: ' .. reason)
    return
end
```

## Discord log
Alapból kikapcsolva:

```lua
Config.Discord.Enabled = false
Config.Discord.Webhook = ''
```

Ha bekapcsolod, logolja a műszakit, biztosítást, adót, pótlást, rendszámcserét, adásvételt, hamis forgalmit és körözést.
