# Takt-Helfer – Script-Mod für Transport Fever 3

Verteilt die Fahrzeuge einer Linie gleichmäßig. Kein Pulk mehr aus drei Zügen,
nach dem 20 Minuten gar nichts kommt.

## So funktioniert's

Pro Linie wählst du einen **Taktknoten**, also einen Halt der Linie. Dort hält der Mod
jedes Fahrzeug fest, bis seit der letzten Abfahrt ein voller Takt vergangen ist.
An allen anderen Halten fahren die Fahrzeuge ganz normal.

| Einstellung | Bedeutung |
|---|---|
| **An** | Takt-Helfer für diese Linie ein-/ausschalten |
| **Takt** `Auto` | Takt = Umlaufzeit ÷ Anzahl Fahrzeuge. Die Umlaufzeit lernt der Mod selbst (nach einer Runde). Fahrzeuge dazukaufen/verkaufen passt den Takt automatisch an. |
| **Takt** `x min` | Fester Takt, z. B. alle 10 Minuten (Spielzeit, 1 min = 60 s) |
| **Taktknoten** `< >` | An welchem Halt getaktet wird, am besten eine Endstation |
| **Uhr** | Abfahrten nur zu vollen Taktzeiten (bei 10 min: :00, :10, :20 …). So passen Anschlüsse zwischen Linien mit gleichem Takt. |
| **Status** | Fahrzeuge im Einsatz · aktueller Takt · letzter gemessener Abstand |

Sicherungen:
- Jedes Fahrzeug steht mindestens 20 s am Knoten (Ein-/Aussteigen).
- Kein Fahrzeug wird länger als 1,5 Takte festgehalten, damit nichts dauerhaft blockiert.

## Installation

1. Den Ordner `takt_helfer_1` in den lokalen Mod-Ordner kopieren:
   - Steam: `C:\Program Files (x86)\Steam\userdata\<deine ID>\3493540\local\mods\`
   - GOG/Epic: Transport-Fever-3-Ordner unter `%AppData%`, darin `mods`

   Wichtig: `mod.lua` muss direkt in `mods\takt_helfer_1\` liegen, nicht noch einen Ordner tiefer.
2. Im Spiel unter *Freies Spiel* (bzw. beim Laden eines Spielstands) den Mod **Takt-Helfer** anhaken.
3. Im Spiel erscheint unten in der Leiste der Button **Takt**, der das Fenster öffnet.

## Wichtig: Erstversion, im Spiel noch ungetestet

Transport Fever 3 ist seit dem 29.09.2026 draußen, und die Script-API ist noch nicht
öffentlich dokumentiert. Der Mod ist nach der **TPF2-Script-API** gebaut (manuelle Abfahrt
per `setVehicleManualDeparture` / `setVehicleShouldDepart`, wie im bekannten Timetables-Mod).
Hat TPF3 dort etwas umbenannt, muss nur **eine** Datei angepasst werden:

`takt_helfer_1/res/scripts/takt_helfer/spiel.lua`

Wenn etwas nicht geht: Fehlermeldung bzw. `stdout.txt` aus dem Spielordner mitschicken,
dann wird das dort angepasst.

## Aufbau

```
takt_helfer_1/
  mod.lua                                  Mod-Infos
  res/config/game_script/takt_helfer.lua   Game-Script (wird vom Spiel automatisch geladen)
  res/scripts/takt_helfer/logik.lua        Taktlogik (ohne Spiel-API, testbar)
  res/scripts/takt_helfer/spiel.lua        alle Zugriffe auf die Spiel-API
  res/scripts/takt_helfer/fenster.lua      Fenster im Spiel
tests/
  test_logik.lua        Simulation: 4 Züge als Pulk -> gleichmäßige Abstände
  test_spiel_mock.lua   Script mit nachgebauter API: Fenster, Klicks, Zugsteuerung
```

Tests ausführen (im Ordner `tpf3-mods`, mit LuaJIT wie im Spiel):

```
luajit tests/test_logik.lua
luajit tests/test_spiel_mock.lua
```
