# Generator für den Lageplan Waldenberg

Der Lageplan und das Zeichnungsblatt für Waldenberg werden erzeugt, nicht von Hand
gepflegt. Beide Blätter stammen aus derselben Geometrie, damit sie nicht
auseinanderlaufen.

## Dateien

| Datei | Zweck |
|---|---|
| `waldenberg.py` | Gleisgeometrie und Symbole nach Ril 819.9002. `build()` liefert den Plan einmal mit `currentColor` (Lageplan, Dark Mode) und einmal in Schwarz (Zeichnungsblatt). |
| `build_waldenberg.py` | Schreibt `lageplan-waldenberg.html` und `zeichnung-waldenberg.html` – Seitenrahmen, Tabellen, Begleittexte. |
| `render_export.py` | Rendert `export/lageplan-waldenberg.jpg` aus dem fertigen Lageplan (Playwright). |
| `obersosa.py` | Gleisgeometrie des Knotens Obersosa. Die Weichennummern werden aus den Weichenmitten automatisch vergeben, damit sie nach Ril 819.9001 mit der Kilometrierung steigen. |
| `build_obersosa.py` | Schreibt `lageplan-obersosa.html` und `zeichnung-obersosa.html`. |
| `gleisband.py` | Schreibt `gleisband-los5.html`: das Übersichtsblatt aller drei Strecken und darunter zwei Folienblätter mit je zwei Abschnitten (`db-1`, `db-2`) sowie vier Einzelblätter (`eb-s1-west`, `eb-s1-ost`, `eb-s2`, `eb-s3`). Das Übersichtsblatt ist fürs Zeichnungsblatt gedacht, die Einzelblätter für die Projektion – dort entscheidet die Schriftgröße im Verhältnis zur Bildbreite über die Lesbarkeit. |
| `seite.py` | Gemeinsames Stylesheet der Blätter. `build_waldenberg.py` führt noch eine eigene Kopie und sollte darauf umgestellt werden. |

## Ablauf

```sh
python3 tools/build_waldenberg.py    # beide HTML-Dateien neu schreiben
python3 tools/render_export.py       # JPG-Export neu rendern
```

`render_export.py` sucht Chromium unter `/opt/pw-browsers/chromium`; ein anderer
Pfad lässt sich über die Umgebungsvariable `CHROMIUM_PATH` setzen.

## Was beim Ändern zu beachten ist

* **Weichennummern** steigen nach Ril 819.9001 Abschnitt 3(1) mit der
  Kilometrierung. Wer eine Weiche verschiebt oder ergänzt, muss die Nummerierung
  und alle Verweise in den Tabellen und Texten von `build_waldenberg.py`
  mitziehen.
* **Regel- und Gegengleis** beschreiben nur die freie Strecke. Im Bahnhof gibt es
  Bahnhofsgleise und Fahrstraßen – die Begriffe gehören dort nicht hin.
* **Zs 3 und Gegengleisanzeiger hängen am Fahrweg, nicht am Signalnamen.** Ein Zs 3
  steht nur dort, wo die Fahrstraße abzweigend über eine Weiche führen kann; ein
  Gegengleisanzeiger nur dort, wo die Ausfahrt auf dem Streckengleis der
  Gegenrichtung weitergehen kann. Wer Gleisnummern tauscht oder Weichenzungen
  umdreht, muss beides neu aus der Geometrie herleiten.
* **Die Fahrleitung selbst wird im sicherungstechnischen Lageplan nicht gezeichnet.**
  Schaltabschnittsgrenzen sind nach Ril 819.9002 ausdrücklich ohne Darstellung.
  Gekennzeichnet wird nur, welches Gleis *nicht* elektrifiziert ist – Raute auf der
  Gleislinie, Strich auf der nicht elektrifizierten Seite (`ohne_fahrleitung()`).
  Die Streckendaten inklusive Elektrifizierung stehen in den Streckenangaben an den
  Blatträndern.
* Nach jeder Änderung das Ergebnis ansehen, bevor committet wird: Signale und
  Weichen liegen dicht beieinander, Überlappungen fallen nur im Bild auf.

`waldenberg.py` enthält mit `gleissperre()` auch ein Symbol, das der aktuelle Plan
nicht verwendet. Es ist gegen die Ril geprüft und bleibt als Baustein erhalten.
