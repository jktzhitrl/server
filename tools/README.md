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
* Nach jeder Änderung das Ergebnis ansehen, bevor committet wird: Signale und
  Weichen liegen dicht beieinander, Überlappungen fallen nur im Bild auf.

`waldenberg.py` enthält mit `gleissperre()` auch ein Symbol, das der aktuelle Plan
nicht verwendet. Es ist gegen die Ril geprüft und bleibt als Baustein erhalten.
