# Prompt: Burgstadt komplett neu planen

> Diesen ganzen Text in eine neue Sitzung kopieren. Die Teile in [eckigen Klammern] vorher anpassen oder löschen.

---

Hallo! Ich möchte auf meinem Minecraft-Server eine mittelalterliche Burgstadt bauen und brauche dafür einen kompletten, neuen Bauplan. Ich habe das schon einmal mit dir geplant und dabei viel gelernt. Hier ist alles, was du wissen musst. Bitte lies es ganz, stell mir dann deine Fragen und fang erst danach an.

## 1. Über mich und wie du mit mir reden sollst

- Sprich Deutsch mit mir, einfach und ohne Fachchinesisch. Ich bin kein Programmierer.
- Kurze Antworten, Schritt für Schritt, mit klaren Klick-Anleitungen.
- Ich spiele auf **Windows** mit der **Modrinth-App** (Instanz „Fabric 26.3“).
- Mein Server läuft bei **G-Portal** mit **Fabric**, Dateien lade ich mit **FileZilla** hoch.
- Ich spiele überwiegend allein im **Survival**.
- Wenn du etwas Wichtiges entscheiden musst (Größe, Lage, was weg kommt), frag mich mit 2 bis 4 Auswahlmöglichkeiten und sag, was du empfiehlst.

## 2. Spiel und Technik

- **Minecraft Java 26.3**, Fabric. Meeresspiegel: oberste Wasserschicht auf **Y 62**, normaler Boden auf **Y 63**.
- Mods bei mir (Client): Fabric API, **Litematica** (+ MaLiLib), Karten-Mod auf Taste M. Litematica ist nur bei mir, nicht auf dem Server.
- Mods, die Client **und** Server brauchen (z. B. Traveler's Backpack), müssen auf beiden in genau derselben Version sein.
- Keine Original-Texturen von Mojang ins Repository hochladen. Texturen nachbauen oder aus meiner eigenen Minecraft-.jar im Browser laden lassen.

## 3. Meine Insel (echte Daten, nicht raten!)

- Die Insel liegt in meiner Welt ungefähr bei **X −2826 bis −2524, Z −2054 bis −1745**.
- Dazu gehören die Region-Dateien **r.-6.-5.mca, r.-5.-5.mca, r.-6.-4.mca, r.-5.-4.mca** aus `world/region`. [Ich lade sie dir hoch.]
- **Lies Form, Höhen, Wasser, Sand und Wald direkt aus diesen Dateien aus**, bevor du irgendetwas planst. Beim letzten Mal war die Insel erst nach Karte und Screenshots geschätzt und lag dadurch daneben. Erst die echten Weltdaten (26.3-Chunk-Format, Paletten als Strings oder Dicts mit `id`/`properties`) haben gepasst.
- Was ich schon weiß:
  - Im Norden eine Bucht, die sich als Hafen eignet.
  - Im Westen ein natürlicher Hügel (gut für die Burg), dahinter Wiese und eine Sandzunge nach Südwesten.
  - Im Südosten eine bewaldete Halbinsel. **Dieser Wald soll stehen bleiben.**
  - Im Osten ein Fluss, dahinter Land, das **so bleibt, wie es ist**.

## 4. Was ich haben will

- Mittelalterliche Burgstadt im Fachwerk-Stil:
  - **Burg auf dem Hügel:** Hauptburg mit Bergfried, Palas und Kapelle, Vorburg mit Stall und Wirtschaftshaus, Graben, Torhaus mit Zugbrücke.
  - **Stadtmauer** mit runden Ecktürmen, Haupttor mit Steinbrücke, Hafentor, Pforte.
  - **Marktplatz** mit Brunnen und Ständen, **Hafen** mit Stegen, Booten und Leuchtturm.
  - **Wohnhäuser** entlang krummer Gassen, Laternen, Torbögen, Gemüsegärten.
  - **Vor der Stadt:** Kloster, Obsthof, Windmühle.
- **Jedes besondere Gebäude hat eine nützliche Farm**, möglichst halbautomatisch:
  - Eisengolem-Farm unter der Schmiede, Mob-Farm und Kerker unter dem Bergfried.
  - Eier, Bienen und Honig, Fische, Seetang, Zuckerrohr, Melonen und Kürbisse, Weizen, Gemüse, Leder.
- Alle Farmen sind per **unterirdischer Lorenbahn** mit einem **Lagerhaus mit Sortieranlage** verbunden.
- [Größe: Das letzte Mal waren es rund 69.000 Blöcke Bauwerke plus 54.000 Blöcke Erde, das sind etwa 130 bis 200 Stunden. Diesmal möchte ich höchstens ___ Stunden einplanen. Bitte richte die Größe danach.]

## 5. Was ich beim letzten Mal gelernt habe (bitte von Anfang an so machen)

1. **Vom echten Gelände ausgehen, nicht erst alles platt machen.** Beim letzten Plan sollte die ganze Insel auf Y 63 eingeebnet und danach der Burghügel wieder aufgeschüttet werden. Allein am Burghügel wären das rund 40.000 Blöcke Erde für nichts gewesen. Natürliche Hügel bleiben, wo der Plan Höhe braucht. Abgetragen und aufgeschüttet wird nur die Differenz.
2. **Früh festlegen, was natürlich bleibt** (Wald im Südosten, Land jenseits des Flusses). Diese Flächen weder einebnen noch bebauen, aber im 3D-Plan mit ihren Bäumen zeigen.
3. **Aufgeschüttete Hügel innen hohl lassen**: nur eine 2 Blöcke dicke Außenhaut, im Hohlraum Laternen gegen Monster.
4. **In Bauabschnitten bauen, nicht in Gewerken.** Nicht „erst alle Mauern, dann alle Häuser“, sondern Gebiet für Gebiet komplett fertig: Gelände, Mauer, Wege, Gebäude, Farmen, Lorenbahn-Stück, Bäume. Zuletzt waren es 5 Abschnitte:
   1. Burg
   2. Stadt Mitte und Markt
   3. Stadt Süd mit dem Lagerhaus (früh, weil dort alle Bahnen ankommen)
   4. Stadt Nord und Hafen
   5. Westen mit Kloster, Obsthof und Windmühle

   Große Bauwerke wie Mauer, Straßen, Lorenbahn und Bäume werden dafür pro Abschnitt geteilt.
5. **Gebäude nicht in Wald oder Wasser quetschen.** Vor dem Platzieren prüfen, ob genug Platz ist. Wege bekommen Abstand zu Gebäuden und führen nicht durch sie hindurch.
6. **Aufwand ehrlich ausrechnen** und mir vor dem Ausarbeiten zeigen: Blöcke pro Abschnitt, Erde abtragen und aufschütten, die wichtigsten Materialien in Stacks, geschätzte Stunden.

## 6. Was du liefern sollst

### A) Interaktiver 3D-Bauplan als eine einzige HTML-Datei

- three.js, im Browser ohne Installation, auch als Artifact veröffentlichbar.
- Die Insel in echter Form und Höhe, alle Gebäude Block für Block in Minecraft-Optik, Tag- und Abendstimmung.
- **Echte Minecraft-Koordinaten** überall: beim Gebäude, beim Mauszeiger über dem Gelände, in jedem Schichtplan.
- Klick auf ein Gebäude öffnet:
  - Beschreibung
  - Materialliste mit Stacks
  - Bauanleitung in Schritten
  - **Schichtplan** (Ebene für Ebene, mit Y-Wert)
  - Farm mit Funktionsweise und Röntgenansicht für Keller
- Ansicht „Geländearbeiten“: farbig, wo aufgeschüttet, abgetragen oder Wasser zugeschüttet wird. Gelände in Stücke von etwa einem Chunk (16 × 16) geteilt, jedes mit eigenem Schichtplan.
- Ansicht „Bauetappen“, nach Bauabschnitten gruppiert. In 3D steht nur, was in früheren Etappen schon gebaut ist.
- Gesamt-Materialliste.

### B) Litematica-Dateien (.litematic) für mich

- **Jede Datei hat ihre echte Position als Ursprung** (Nordwestecke unten, also kleinstes X, Y und Z). Ich trage den Ursprung in Litematica unter *Schematic Placements → Configure → Placement origin* ein. Kein gemeinsamer Ankerpunkt, kein „Move to player“.
- Dateien:
  - ganze Stadt
  - ganzes Gelände
  - jede Etappe, sortiert in **Unterordnern pro Bauabschnitt**
  - jedes Gebäude
  - jedes Geländestück
- Technisch:
  - gzip-NBT, MinecraftDataVersion für 26.3, Version 7.
  - Paletten-Index = (y·sz + z)·sx + x, Bits über Long-Grenzen gepackt, mindestens 2 Bits.
  - Breite Dateien in Chunk-große Regionen teilen.
- Blockzustände korrekt:
  - Treppenform (Ecken)
  - Verbindungen von Zäunen, Glasscheiben und Mauern
  - Redstone- und Schienenverlauf
  - Richtungen von Türen, Falltüren, Leitern und Knöpfen
  - Wachstumsstufen
  - Laub `persistent`
- Prüfe jede erzeugte Datei mit einem eigenen Lese-Skript (Blockanzahl stimmt, ein Gebäude Block für Block gegen den Plan).
- Alles als **ZIP** (Artifacts erlauben keinen Download von `.litematic`). Dazu:
  - **LIESMICH.txt** mit Anleitung und Koordinatentabelle
  - **Excel-Tabelle** mit X, Y, Z, Blockanzahl und einer Spalte zum Abhaken pro Datei

### C) Kurze Anleitung für Litematica, auf meine Fragen zugeschnitten

- Immer nur eine Datei gleichzeitig laden, alte Placements entfernen.
- Weniger grell:
  - *Visuals*: Ghost-Blöcke durchsichtig (`renderBlocksAsTranslucent`, Alpha 0,3)
  - Placement-Kästen und Seitenflächen aus
- Einzelne Schichten: *Render Layers → Single Layer, Achse Y*, mit Bild auf/ab weiterschalten.

## 7. Arbeitsweise

1. Zuerst: Weltdaten auslesen, mir eine Karte der Insel zeigen und bestätigen lassen, dass Form und Lage stimmen.
2. Dann: mir 2 bis 3 Grob-Entwürfe (Lage von Burg, Stadt, Hafen, Höfen) als Draufsicht zeigen, mit Aufwand in Stunden.
3. Erst nach meiner Wahl ausarbeiten.
4. Nach jeder größeren Änderung:
   - im Browser testen (keine Fehler, alle Gebäude platziert, nichts im Wasser oder Wald)
   - Screenshot ansehen
   - committen und pushen
   - das Artifact aktualisieren
5. Litematica-Dateien neu erzeugen, wenn sich Positionen ändern, und mir sagen, welche Werte sich geändert haben.

## 8. Tipps fürs Bauen, die du einplanen kannst

- **Stein:** Steingenerator (Lava fließt **von oben** auf Wasser, dann entsteht Stein statt Bruchstein). Mit Behutsamkeits-Spitzhacke, Effizienz V und **Eile II** vom Leuchtfeuer baut man Stein ohne Verzögerung ab. Im **Steinschneider** wird 1 Stein zu 1 Steinziegel, ohne Ofen. Ein Ofen ist nur für rissige Steinziegel nötig.
- Gut wäre ein **Steinbruch mit Leuchtfeuer** als allererstes Bauwerk im Plan.
- Brennstoff: getrocknete Seetangblöcke aus der Seetangfarm.
- Litematica „Easy Place“ spart viel Zeit bei Treppen und Stufen.

## 9. Referenz: der alte Plan

[Falls die Sitzung Zugriff auf mein Repository hat:]

Der alte Stand liegt im Repository `jktzhitrl/server`, Branch `claude/cool-johnson-y8oo0b`:
- `minecraft-stadt.html` (3D-Plan mit Litematica-Export)
- `farmen.html` und `eisenfarm.html`

Nutze ihn als Ideensammlung und für den Code (Blockdefinitionen, Litematica-Writer, Blockzustände). Der neue Plan soll aber sauber neu aufgebaut werden, mit den Lehren aus Abschnitt 5.

Bitte fang mit deinen Fragen an.
