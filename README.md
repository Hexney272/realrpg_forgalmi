# realrpg_forgalmi

ESX Legacy + ox_inventory + ox_target + oxmysql jármű forgalmi engedély rendszer.

## Mit tud?

- `forgalmi_engedely` ox_inventory item.
- Szerviz NPC, ahol műszaki vizsga kérhető NUI ablakban.
- A műszaki vizsga alapára 150 000 Ft.
- Opcionális 5L üzemanyag sor, a képen látható szerviz NUI alapján.
- Okmányiroda NPC, ahol a sikeres műszaki után kiállítható a forgalmi.
- A forgalmi NUI megjelenése a feltöltött képekhez igazított zöld papír, barna címkék, jobb oldali kék csík, SEE logó, piros ÉRVÉNYTELEN pecsét.
- Ha a jármű tuningja / színe / optikája / neonja / felnie / futóműve változik a kiállítás után, a forgalmi automatikusan érvénytelen lesz.
- Más tuning scriptből is érvényteleníthető exporttal.

## Telepítés

1. Másold a mappát ide:

```txt
resources/[realrpg]/realrpg_forgalmi
```

2. Add hozzá a `server.cfg` fájlhoz:

```cfg
ensure oxmysql
ensure es_extended
ensure ox_inventory
ensure ox_target
ensure realrpg_forgalmi
```

3. Másold be az itemet az `ox_inventory/data/items.lua` fájlba az `ITEM_OX_INVENTORY.lua` tartalmából.

4. Másold az `ox_inventory_images/forgalmi_engedely.png` fájlt az inventory képek közé:

```txt
ox_inventory/web/images/forgalmi_engedely.png
```

5. Az SQL táblát a script automatikusan létrehozza, ha `Config.AutoCreateDatabase = true`. Ha kézzel akarod futtatni, használd a `sql/install.sql` fájlt.

6. Állítsd be a koordinátákat a `shared/config.lua` fájlban:

```lua
Config.ServiceNpc.Coords = { x = -347.28, y = -133.46, z = 38.01, w = 70.0 }
Config.OfficeNpc.Coords = { x = -552.67, y = -192.62, z = 37.22, w = 210.0 }
```

## Használat

1. A játékos megveszi az autót.
2. A játékos elviszi a járművet a szerviz NPC-hez.
3. A szerviz NUI-ban kiválasztja a műszaki vizsgát.
4. Fizet 150 000 Ft-ot.
5. Ezután elmegy az Okmányiroda NPC-hez.
6. Az NPC kiállítja a `forgalmi_engedely` itemet.
7. A item használatakor megnyílik a forgalmi NUI.

## Parancs

```txt
/forgalmi_jarmu
```

Megnyitja a közelben lévő jármű forgalmiját rendszám alapján, ha van hozzá adatbázis bejegyzés.

## Tuning script integráció

Ha van külön tuning scripted, tuning mentés után hívd meg ezt szerver oldalon:

```lua
exports['realrpg_forgalmi']:InvalidateVehicleDocument(plate, 'A jármű módosítva lett')
```

A rendszer ettől függetlenül automatikusan is ellenőrzi a jármű állapotát, amikor a játékos vezet.

## Fontos megjegyzés

A FiveM native-okból nem minden egyedi tuning adat olvasható ki minden tuning rendszerből. Amit a GTA/FiveM natívan visszaad, azt a script valós időben olvassa. Ha például a saját tuning rendszered külön kezeli a hasmagasságot, backfire-t vagy egyedi dudát, a `Config.ExternalTuningDataExport` beállítással átadhatod ezeket a forgalminak.
