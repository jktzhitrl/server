# -*- coding: utf-8 -*-
"""Schreibt lageplan-obersosa.html und zeichnung-obersosa.html.

Die Geometrie kommt aus obersosa.py, das Seitenlayout aus seite.py. Die
betrieblichen Aussagen sind aus den Fahrplandaten des Projekts hergeleitet
(strecke1-fahrplan.html und strecke2-fahrplan.html), nicht geschaetzt.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import obersosa as o
from seite import CSS

REPO = str(pathlib.Path(__file__).resolve().parent.parent) + "/"

ARIA = ("Sicherungstechnischer Lageplan des Knotens Obersosa. Sieben Gleise, davon sechs "
        "Bahnsteiggleise an vier Bahnsteigen; Empfangsgebäude und Hauptzugang im Süden. "
        "Fünf Zulaufrichtungen: am Westkopf Krug und Erx, Silberberg und Bernstein sowie "
        "Windingen und Güterbahnhof, am Ostkopf Furth und Neumark. An beiden Bahnhofsköpfen "
        "eine Gleisharfe aus je sechs Weichenpaaren, die benachbarte Gleise verbindet. "
        "Zwischensignale ZU und ZR teilen die Gleise 1, 2 und 5 in die Abschnitte a und b. "
        "Einfahrsignale A, AA, B, BB und C am Westkopf, F, FF und G am Ostkopf; "
        "Ausfahrsignale P1 bis P7 nach Westen und N1 bis N7 nach Osten mit Zs 2 "
        "Richtungsanzeiger.")

WEICHEN = [
    ("1 / 3",   "Gleis 7 ↔ Gleis 6 · Westkopf"),
    ("2 / 5",   "Gleis 6 ↔ Gleis 5 · Westkopf"),
    ("4 / 7",   "Gleis 5 ↔ Gleis 4 · Westkopf"),
    ("6 / 9",   "Gleis 4 ↔ Gleis 3 · Westkopf"),
    ("8 / 11",  "Gleis 3 ↔ Gleis 2 · Westkopf"),
    ("10 / 12", "Gleis 2 ↔ Gleis 1 · Westkopf"),
    ("13 / 15", "Gleis 7 ↔ Gleis 6 · Ostkopf"),
    ("14 / 17", "Gleis 6 ↔ Gleis 5 · Ostkopf"),
    ("16 / 19", "Gleis 5 ↔ Gleis 4 · Ostkopf"),
    ("18 / 21", "Gleis 4 ↔ Gleis 3 · Ostkopf"),
    ("20 / 23", "Gleis 3 ↔ Gleis 2 · Ostkopf"),
    ("22 / 24", "Gleis 2 ↔ Gleis 1 · Ostkopf"),
]

SIGNALE = [
    ("A · AA", "Einfahrt von Waldenberg und Krug · AA für Fahrten auf dem <strong>Gegengleis</strong>"),
    ("B · BB", "Einfahrt von Hochstein und Silberberg · BB für das <strong>Gegengleis</strong>"),
    ("C",  "Einfahrt vom Güterbahnhof und aus Windingen · eingleisig"),
    ("F · FF", "Einfahrt von Lossow und Furth · FF für das <strong>Gegengleis</strong>"),
    ("G",  "Einfahrt von Kirchheim und Neumark · eingleisig"),
    ("P1 – P7", "Ausfahrt nach Westen · mit <strong>Zs 2 Richtungsanzeiger (K, S, W)</strong>, "
                "weil die Fahrt nach Krug, Silberberg oder Windingen führen kann"),
    ("N1 – N7", "Ausfahrt nach Osten · mit <strong>Zs 2 (F, N)</strong> für Furth oder Neumark"),
    ("P2 · N2", "zusätzlich <strong>Zs 6 Gleiswechselanzeiger</strong> für die Ausfahrt auf das "
                "Streckengleis der Gegenrichtung"),
    ("ZU1 · ZR1<br>ZU2 · ZR2<br>ZU5 · ZR5",
     "<strong>Zwischensignale</strong>, die die Gleise 1, 2 und 5 in die Abschnitte a und b "
     "teilen · ZR in Richtung der Kilometrierung, ZU entgegen (Ril 819.9001 Abschnitt 4 (3))"),
    ("—", "Gesonderte Vorsignale entfallen: Vorsignalisierung über den Ks-2-Begriff"),
]

PROGRAMM = [
    ("RB 62<br>Neumark", "Endet in Obersosa, steht im Abschnitt <strong>1a</strong>. "
     "Abfahrt Minute 20 und 50", "1a"),
    ("RB 63<br>Krug", "Endet in Obersosa, steht im Abschnitt <strong>1b</strong>. "
     "Abfahrt Minute 30", "1b"),
    ("RE 71 · RE 70<br>Richtung Furth", "Beide Äste des Flügelzuges stehen hintereinander: "
     "RE 71 an Minute 53 in 2a, RE 70 an Minute 57 in 2b, gemeinsame Abfahrt Minute 00", "2a / 2b"),
    ("RB 61<br>Richtung Furth", "Durchfahrt mit Halt, Abfahrt Minute 15 und 45 · dazu der "
     "Fernverkehr Richtung Furth Minute 55", "3"),
    ("RB 61<br>Ri Waldenberg und Windingen", "Abfahrt Minute 15 und 45 · dazu IC 13 Richtung "
     "Erx und Richtung Sandheide Minute 25", "4"),
    ("RE 70/71<br>Teilung des Flügelzuges", "Der Zug wird hier <strong>geteilt</strong>: "
     "RE 71 nach Bernstein ab Minute 07 aus 5a, RE 70 nach Erx ab Minute 03 aus 5b. "
     "Beide kommen an Minute 00", "5a / 5b"),
    ("RB 65", "Richtung Sandheide ab Minute 28, Richtung Furth ab Minute 32", "6"),
    ("Güterverkehr", "Überholung und Abstellung ohne Bahnsteig, Prellbock im Osten", "7"),
]
SEITE = """<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Lageplan Obersosa – Mitteltrasse Los 5</title>
<style>__CSS__</style>
</head>
<body>
<div class="wrap">
  <span class="kicker">Los 5 · Sicherungstechnischer Lageplan · Ril 819.9001 / 819.9002</span>
  <h1>Lageplan Obersosa</h1>
  <p class="sub">
    Obersosa ist der <strong>Knoten des Loses</strong> – hier treffen <strong>fünf
    Zulaufrichtungen</strong> zusammen: Krug und Erx, Silberberg und Bernstein sowie Windingen
    und Güterbahnhof am Westkopf, Furth und Neumark am Ostkopf. Sechs Bahnsteiggleise an vier
    Bahnsteigen, dazu ein Güter- und Abstellgleis. Das Empfangsgebäude liegt im Süden – von dort
    zählen die Gleisnummern nach Ril 819.9001 Abschnitt 2 (3) aufsteigend. Gleisbelegung und
    Abfahrtsminuten sind der Projektarbeit entnommen.
  </p>

  <section class="panel">
    <h2>Gleistopologie</h2>
    <p class="panel-note">
      Symbole nach Ril 819.9002: Weichenanfang und Weichenmitte je als senkrechter Strich, ab der
      Weichenmitte die Schwärzung zum Zweiggleis, dahinter das Grenzzeichen. Zusatzsignale nach
      819.9002A01, wie an einem stehenden Mast angeordnet: <strong>Zs 3</strong>
      Geschwindigkeitsanzeiger als Dreieck mit der Spitze nach oben, <strong>Zs 2</strong>
      Richtungsanzeiger als Fünfeck, <strong>Zs 6</strong> Gleiswechselanzeiger als Quadrat mit
      Diagonale. Festprellböcke an den Gleisen 5, 6 und 7.
    </p>
    <div class="diagram-scroll">
      <svg class="plan" viewBox="0 0 3100 940" role="img" aria-label="__ARIA__">
        __PLAN__
      </svg>
    </div>
    <div class="rules">
      <span>Gleis 1 und 2 sind die durchgehenden Hauptgleise der Strecke 1; Gleis 4 und 5 führen nach Silberberg, Gleis 7 nach Windingen, Gleis 6 nach Neumark.</span>
      <span>An beiden Bahnhofsköpfen eine <strong>Gleisharfe</strong> aus je sechs Weichenpaaren: Damit ist jedes Gleis von jeder Richtung erreichbar.</span>
      <span>Weichennummern steigen mit der Kilometrierung der Strecke 1, also von West nach Ost (Ril 819.9001 Abschnitt 3 (1)).</span>
      <span>Die Zwischensignale ZU und ZR teilen die Gleise 1, 2 und 5 in die Abschnitte a und b – so passen zwei Vierteiler hintereinander an einen Bahnsteig.</span>
      <span>Alle Weichen EW 1:9, Abzweiggeschwindigkeit 40 km/h; in den Fahrwegen der durchgehenden Hauptgleise EW 1:14 mit 60 km/h.</span>
      <span>Beide Strecken elektrifiziert 15 kV 16,7 Hz. Die Fahrleitung selbst wird im sicherungstechnischen Lageplan nicht dargestellt.</span>
      <span>Regel- und Gegengleis beschreiben nur die freie Strecke; im Bahnhof gibt es Bahnhofsgleise und Fahrstraßen.</span>
    </div>
  </section>

  <section class="panel">
    <h2>Betriebsprogramm</h2>
    <p class="panel-note">
      Gleisbelegung und Abfahrtsminuten stammen aus der Projektarbeit. Sechs Bahnsteiggleise
      reichen, weil drei davon in die Abschnitte a und b geteilt sind: RB 62 und RB 63 enden
      beide in Gleis 1, die beiden Äste des Flügelzuges RE 70/71 stehen hintereinander in
      Gleis 2 und in Gleis 5. Ein Desiro HC und ein Mireo sind je Vierteiler – zwei davon
      passen an einen Bahnsteig.
    </p>
    <div class="table-scroll">
      <table>
        <thead><tr><th>Zug</th><th>Weg durch Obersosa</th><th>Gleis</th></tr></thead>
        <tbody>__PROGRAMM__</tbody>
      </table>
    </div>
  </section>

  <section class="panel">
    <div class="two-col">
      <div>
        <h3>Weichenverzeichnis</h3>
        <div class="table-scroll">
          <table>
            <thead><tr><th>Lageplan</th><th>Verbindung</th></tr></thead>
            <tbody>__WEICHEN__</tbody>
          </table>
        </div>
      </div>
      <div>
        <h3>Signalverzeichnis</h3>
        <div class="table-scroll">
          <table>
            <thead><tr><th>Lageplan</th><th>Funktion</th></tr></thead>
            <tbody>__SIGNALE__</tbody>
          </table>
        </div>
      </div>
    </div>

    <div class="caveat">
      <strong>Warum fünf Richtungen und nicht drei:</strong> Der Liniennetzplan der Projektarbeit
      zeigt Obersosa als Kreuzungsknoten. Nach Westen gehen drei Strecken ab – nach Krug und Erx,
      nach Silberberg und Bernstein sowie zum Güterbahnhof und nach Windingen –, nach Osten zwei:
      nach Lossow und Furth und nach Kirchheim und Neumark. Deshalb braucht jeder Bahnhofskopf
      eine vollständige Gleisharfe: Ein Zug aus Neumark muss Gleis 1 erreichen, ein Zug aus
      Windingen Gleis 6, und der Flügelzug RE 70/71 muss aus Gleis 5 in zwei verschiedene
      Richtungen ausfahren können. Das ist auch der Grund für die Zs 2 Richtungsanzeiger an
      sämtlichen Ausfahrsignalen.
    </div>

    <div class="caveat">
      <strong>Offene Punkte:</strong> Zugbeeinflussung, technisch gesicherter Bahnübergang und die
      Bedieneinrichtungen der Stellwerke fehlen in diesem Blatt noch. Die Kilometrierung der
      Einfahrsignale ist ebenfalls nachzutragen – der Bewertungsbogen fragt sie unter
      „Kilometrierung (Esig, Mitte/EG, Bksig)" ausdrücklich ab. Nicht übernommen sind die
      zweibuchstabigen Kästchen des handgezeichneten Plans (G,P · S,W · F,W · G,W), weil ihre
      Bedeutung nicht geklärt ist. Dieses Blatt ist ein sauber gezeichneter Gegenentwurf, kein
      Ersatz für den Originalplan.
    </div>
  </section>

  <footer class="foot">LF 2 Jahresprojekt 2026 „Mitteltrasse" · 5. Teilabschnitt (Los 5) — Chemiezentrum</footer>
</div>
</body>
</html>
"""

ZEICHNUNGSBLATT = """<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<title>Zeichnung Obersosa</title>
<style>html,body{margin:0;background:#fff}svg{display:block;width:100%;height:auto}</style>
</head>
<body>
<svg viewBox="0 0 3260 1480" xmlns="http://www.w3.org/2000/svg" role="img"
     aria-label="Technische Zeichnung, sicherungstechnischer Lageplan Obersosa"
     font-family="IBM Plex Sans, Calibri, Arial, sans-serif">
<rect width="3260" height="1480" fill="#fff"/>
<rect x="24" y="24" width="3212" height="1400" fill="none" stroke="#000" stroke-width="3"/>
<text x="60" y="80" font-size="22" font-weight="700" fill="#000" font-family="IBM Plex Mono, monospace">Lageplan Obersosa</text>
<text x="3200" y="80" font-size="14" fill="#000" text-anchor="end" font-family="IBM Plex Mono, monospace">Ril 819.9001 / 819.9002</text>
<line x1="60" y1="96" x2="3200" y2="96" stroke="#000" stroke-width="2"/>
<g transform="translate(70,170) scale(0.98)">__PLAN__</g>
<g font-family="IBM Plex Mono, monospace">
<rect x="60" y="1200" width="1900" height="190" fill="none" stroke="#000" stroke-width="1.5"/>
__LEGENDE__
</g>
<text x="68" y="1452" font-size="10.5" fill="#000" font-family="IBM Plex Mono, monospace">__FUSS__</text>
<g font-family="IBM Plex Mono, monospace">
<rect x="2020" y="1200" width="1120" height="190" fill="none" stroke="#000" stroke-width="2"/>
<line x1="2020" y1="1258" x2="3140" y2="1258" stroke="#000" stroke-width="1.5"/>
<line x1="2020" y1="1318" x2="3140" y2="1318" stroke="#000" stroke-width="1.5"/>
<line x1="2020" y1="1366" x2="3140" y2="1366" stroke="#000" stroke-width="1.5"/>
<line x1="2860" y1="1258" x2="2860" y2="1366" stroke="#000" stroke-width="1.5"/>
<text x="2034" y="1232" font-size="15" font-weight="700" fill="#000">LF 2 Jahresprojekt 2026 „Mitteltrasse"</text>
<text x="2034" y="1282" font-size="12" fill="#000">5. Teilabschnitt (Los 5) – Chemiezentrum</text>
<text x="2034" y="1308" font-size="11" fill="#333">Betriebsstelle</text>
<text x="2034" y="1308" font-size="11" fill="#333"></text>
<text x="2034" y="1342" font-size="15" font-weight="600" fill="#000">Obersosa</text>
<text x="2874" y="1308" font-size="11" fill="#333">Kennzahl</text>
<text x="2874" y="1342" font-size="15" font-weight="600" fill="#000">27</text>
<text x="2034" y="1386" font-size="11" fill="#333">Inhalt: Sicherungstechnischer Lageplan</text>
<text x="2874" y="1386" font-size="11" fill="#333">Maßstab: ohne</text>
</g>
</svg>
</body>
</html>
"""


def legende():
    """Sieben Felder mit den Symbolen, die in diesem Blatt vorkommen."""
    felder = [
        ('<line x1="0" y1="8" x2="50" y2="8" stroke="#000" stroke-width="1.5"/>'
         '<line x1="5" y1="3" x2="5" y2="13" stroke="#000" stroke-width="1.2"/>'
         '<line x1="17" y1="3" x2="17" y2="13" stroke="#000" stroke-width="1.2"/>'
         '<polygon points="17,8 34,8 34,17" fill="#000"/>', 'Weiche fern'),
        ('<line x1="2" y1="1" x2="2" y2="15" stroke="#000" stroke-width="1.5"/>'
         '<line x1="2" y1="8" x2="14" y2="8" stroke="#000" stroke-width="1.5"/>'
         '<rect x="14" y="2" width="16" height="11" rx="5.5" fill="#000"/>', 'Ks-Signal'),
        ('<polygon points="4,14 18,14 11,1" fill="#000"/>', 'Zs 3'),
        ('<polygon points="4,2 18,2 11,15" fill="#000"/>', 'Zs 3v'),
        ('<polygon points="4,15 4,6 11,0 18,6 18,15" fill="#000"/>', 'Zs 2'),
        ('<rect x="3" y="2" width="13" height="13" fill="none" stroke="#000" stroke-width="1.2"/>'
         '<polygon points="3,2 16,2 16,15" fill="#000"/>', 'Zs 6'),
        ('<g stroke="#000" stroke-width="2.5" fill="none"><line x1="0" y1="8" x2="13" y2="8"/>'
         '<line x1="13" y1="-3" x2="13" y2="19"/><line x1="13" y1="-3" x2="6" y2="-3"/>'
         '<line x1="13" y1="19" x2="6" y2="19"/></g>', 'Prellbock'),
        ('<line x1="0" y1="8" x2="26" y2="8" stroke="#000" stroke-width="1.5"/>'
         '<rect x="8" y="1" width="12" height="14" fill="#fff" stroke="#000" stroke-width="1"/>'
         '<text x="14" y="12" text-anchor="middle" font-size="10" font-weight="600" fill="#000">1</text>',
         'Gleisnr.'),
    ]
    x0, w = 60.0, 1900.0
    sw = w / len(felder)
    out = []
    for i, (icon, lab) in enumerate(felder):
        x = x0 + sw * i
        if i:
            out.append(f'<line x1="{x:.1f}" y1="1200" x2="{x:.1f}" y2="1390" stroke="#000" stroke-width="1"/>')
        out.append(f'<g transform="translate({x+16:.1f},1268)">{icon}</g>')
        out.append(f'<text x="{x+16:.1f}" y="1340" font-size="12" fill="#000">{lab}</text>')
    return "\n".join(out)


def zeilen(rows, spalten):
    out = []
    for r in rows:
        tds = "".join(f'<td class="mono">{v}</td>' if i in spalten else f'<td>{v}</td>'
                      for i, v in enumerate(r))
        out.append(f'<tr>{tds}</tr>')
    return "\n".join(out)


FUSS = ("Fünf Zulaufrichtungen · Gleisharfe an beiden Köpfen mit je sechs Weichenpaaren · "
        "Zs 2 an allen Ausfahrsignalen · Zs 6 an N2 und P2 · Zwischensignale ZU und ZR teilen "
        "die Gleise 1, 2 und 5 in die Abschnitte a und b · Gleis 7 ohne Bahnsteig")

if __name__ == "__main__":
    seite = (SEITE.replace("__CSS__", CSS)
                  .replace("__ARIA__", ARIA)
                  .replace("__PLAN__", o.LAGEPLAN)
                  .replace("__PROGRAMM__", zeilen(PROGRAMM, {0, 2}))
                  .replace("__WEICHEN__", zeilen(WEICHEN, {0}))
                  .replace("__SIGNALE__", zeilen(SIGNALE, {0})))
    with open(REPO + "lageplan-obersosa.html", "w", encoding="utf-8") as f:
        f.write(seite)
    blatt = (ZEICHNUNGSBLATT.replace("__PLAN__", o.ZEICHNUNG)
                            .replace("__LEGENDE__", legende())
                            .replace("__FUSS__", FUSS))
    with open(REPO + "zeichnung-obersosa.html", "w", encoding="utf-8") as f:
        f.write(blatt)
    print("geschrieben")
