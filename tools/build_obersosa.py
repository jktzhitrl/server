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

ARIA = ("Sicherungstechnischer Lageplan des Trennungsbahnhofs Obersosa. Die zweigleisige "
        "Hauptbahn Strecke 1 (Krug–Furth) durchläuft die Betriebsstelle bei km 63,5 mit den "
        "durchgehenden Hauptgleisen 1 und 2. Die zweigleisige Strecke 2 aus Silberberg und "
        "Bernstein endet hier bei km 51,0 und mündet am Westkopf mit den Gleisen 4 und 5 ein. "
        "Gleis 3 ist Bahnsteiggleis für Überholungen, Gleis 4 führt durchgehend nach Osten, "
        "die Gleise 5, 6 und 7 enden im Osten am Prellbock und dienen als Wendegleise. "
        "Vier Bahnsteige, Empfangsgebäude und Hauptzugang im Süden. Einfahrsignale A und AA "
        "von Hyxel, B und BB von Silberberg, F und FF von Feldheim; Ausfahrsignale N1 bis N4 "
        "in Richtung der Kilometrierung und P1 bis P7 entgegen; Zs 2 Richtungsanzeiger an "
        "P3 und P4, Zs 6 Gleiswechselanzeiger an N2 und P2.")

WEICHEN = [
    ("1 / 3",  "Überleitverbinder Gleis 1 ↔ Gleis 2 · Westkopf, Gleiswechselbetrieb Strecke 1"),
    ("2 / 4",  "Überleitverbinder Gleis 4 ↔ Gleis 5 · Westkopf, Gleiswechselbetrieb Strecke 2"),
    ("5",      "Gleis 2 → Gleis 3 · Westanbindung des Überholungsgleises"),
    ("6",      "Gleis 5 → Gleis 6 · Westanbindung des Wendegleises"),
    ("7",      "Gleis 6 → Gleis 7 · Westanbindung des zweiten Wendegleises"),
    ("8 / 9",  "Verbindung Gleis 4 ↔ Gleis 3 · einzige Verbindung zwischen Strecke 2 und Strecke 1"),
    ("10 / 11", "Gleis 4 → Gleis 3 · Ostkopf, Fahrweg des durchgehenden Fernverkehrs"),
    ("12 / 13", "Gleis 3 → Gleis 2 · Ostkopf"),
    ("14 / 15", "Überleitverbinder Gleis 2 ↔ Gleis 1 · Ostkopf, Gleiswechselbetrieb Strecke 1"),
]

SIGNALE = [
    ("A",  "Einfahrsignal Gleis 1 von Altensund/Hyxel · Zs 3 (6)"),
    ("AA", "Einfahrt vom <strong>Gegengleis (2)</strong> der Strecke 1 · Zs 3 (6)"),
    ("B",  "Einfahrsignal Gleis 4 von Hochstein/Silberberg · Zs 3 (6)"),
    ("BB", "Einfahrt vom <strong>Gegengleis (2)</strong> der Strecke 2 · Zs 3 (6)"),
    ("F",  "Einfahrsignal Gleis 2 von Kunststoffwerk/Feldheim · Zs 3 (6)"),
    ("FF", "Einfahrt vom <strong>Gegengleis (1)</strong> von Feldheim · Zs 3 (6)"),
    ("N1 · N2", "Ausfahrt Gleis 1 und 2 Richtung Feldheim/Furth · N2 mit <strong>Zs 6</strong>, "
                "weil die Ausfahrt über die Weichen 14/15 auf das Gegengleis führen kann"),
    ("N3 · N4", "Ausfahrt Gleis 3 und 4 Richtung Feldheim/Furth · abzweigend über die "
                "Weichen 10 bis 13 · <strong>Zs 3 (4)</strong>"),
    ("P1 · P2", "Ausfahrt Gleis 1 und 2 Richtung Hyxel · P2 mit <strong>Zs 6</strong>"),
    ("P3 · P4", "Ausfahrt Gleis 3 und 4 · mit <strong>Zs 2 Richtungsanzeiger (H, S)</strong>, "
                "weil die Fahrt nach Hyxel oder nach Silberberg führen kann"),
    ("P5 · P6 · P7", "Ausfahrt der Wendegleise Richtung Hochstein/Silberberg"),
    ("—", "Gesonderte Vorsignale entfallen: Vorsignalisierung über den Ks-2-Begriff der "
          "Mehrabschnittssignale"),
]

PROGRAMM = [
    ("IC 11<br>Bernstein – Furth", "Durchfahrt ohne Halt: an und ab 10:15. Der Zug läuft aus "
     "Strecke 2 über Gleis 4 und die Weichen 10 bis 13 durch. <strong>Dieser Zug bestimmt die "
     "Lage der Strecke 2 am Westkopf</strong> – nur so ist die Durchfahrt ohne Kopfmachen möglich.", "4"),
    ("IC 13<br>Bernstein – Furth", "Halt an Bahnsteig 3: an 10:45, ab 10:57", "4"),
    ("IC 15<br>Bernstein – Erx", "an 10:30, ab 10:45. <strong>Macht Kopf</strong>, weil Herkunft "
     "und Ziel beide am Westkopf liegen. Die 15 Minuten Aufenthalt reichen dafür. Ausfahrt über "
     "P4 mit Zs 2 Richtung Hyxel", "4"),
    ("RB 63", "<strong>Wendet mit 27 Minuten</strong>: an 10:11, ab 10:38. Längste Belegung des "
     "Bahnhofs – deshalb ein eigenes Wendegleis abseits der Fahrwege", "6"),
    ("RE 72", "Wendet: an 10:30, ab 10:45", "7"),
    ("RE 70", "Wendet kurz: an 11:00, ab 11:02", "5"),
    ("RE 71 · RE 70/71<br>RB 61 · RB 65 · RB 66", "Halt an der Hauptbahn, Richtung Osten in "
     "Gleis 1 an Bahnsteig 1, Richtung Westen in Gleis 2 an Bahnsteig 2", "1 / 2"),
    ("GZ 4", "Durchfahrt Hauptbahn ohne Halt, gerade über beide Hauptgleise", "1 / 2"),
    ("GZ 1", "Aus Strecke 2, Überholung durch den Reiseverkehr", "5"),
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
    Obersosa ist der <strong>Knoten des Loses</strong>: Die zweigleisige Hauptbahn
    <strong>Strecke 1</strong> (Krug–Furth) durchläuft die Betriebsstelle bei km 63,5, die
    ebenfalls zweigleisige <strong>Strecke 2</strong> aus Bernstein und Silberberg endet hier
    bei km 51,0 und mündet am Westkopf ein. Sieben Bahnhofsgleise an vier Bahnsteigen, das
    Empfangsgebäude liegt im Süden – von dort zählen die Gleisnummern nach Ril 819.9001
    Abschnitt 2 (3) aufsteigend.
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
      <svg class="plan" viewBox="0 0 3040 1000" role="img" aria-label="__ARIA__">
        __PLAN__
      </svg>
    </div>
    <div class="rules">
      <span>Gleis 1 und 2 sind die durchgehenden Hauptgleise der Strecke 1, Gleis 4 und 5 die Streckengleise der Strecke 2.</span>
      <span>Die Gleise 5, 6 und 7 enden im Osten am Prellbock: Alle Züge der Strecke 2 wenden hier, ein Ostzulauf ist für sie nutzlos.</span>
      <span>Weichennummern steigen mit der Kilometrierung der Strecke 1, also von West nach Ost (Ril 819.9001 Abschnitt 3 (1)).</span>
      <span>Die Weichen 8 und 9 sind die einzige Verbindung zwischen Strecke 2 und Strecke 1 am Westkopf.</span>
      <span>Alle Weichen EW 1:9, Abzweiggeschwindigkeit 40 km/h; im Fahrweg des durchgehenden Fernverkehrs EW 1:14 mit 60 km/h.</span>
      <span>Beide Strecken elektrifiziert 15 kV 16,7 Hz. Die Fahrleitung selbst wird im sicherungstechnischen Lageplan nicht dargestellt.</span>
      <span>Regel- und Gegengleis beschreiben nur die freie Strecke; im Bahnhof gibt es Bahnhofsgleise und Fahrstraßen.</span>
    </div>
  </section>

  <section class="panel">
    <h2>Betriebsprogramm</h2>
    <p class="panel-note">
      Aus dem Bildfahrplan über zwei Stunden. Im Zwei-Stunden-Fenster halten oder fahren
      <strong>62 Züge</strong> durch Obersosa; höchstens <strong>fünf Gleise</strong> sind
      gleichzeitig belegt (11:02). Die Gleiszahl folgt daraus und nicht aus dem Gefühl.
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
      <strong>Warum die Strecke 2 am Westkopf einmündet:</strong> Der IC 11 Bernstein – Furth hält
      in Obersosa nicht, er ist um 10:15 an und ab. Ein Zug kann eine Betriebsstelle nur dann ohne
      Halt durchfahren, wenn Herkunft und Ziel auf verschiedenen Seiten liegen. Da sein Ziel Furth
      im Osten liegt, muss die Strecke 2 im Westen einmünden. Die Gegenprobe liefert der
      IC 15 Bernstein – Erx: Er kommt aus derselben Richtung und fährt nach Westen weiter, muss
      also Kopf machen – und hat mit 15 Minuten genau dafür Aufenthalt. Die Geometrie ist damit
      aus dem Fahrplan hergeleitet und nicht angenommen.
    </div>

    <div class="caveat">
      <strong>Offene Punkte:</strong> Zugbeeinflussung, technisch gesicherter Bahnübergang und die
      Bedieneinrichtungen der Stellwerke fehlen in diesem Blatt noch. Die Kilometrierung der
      Einfahrsignale ist ebenfalls nachzutragen – der Bewertungsbogen fragt sie unter
      „Kilometrierung (Esig, Mitte/EG, Bksig)" ausdrücklich ab. Dieses Blatt ist aus dem Fahrplan
      und den vorhandenen Skizzen hergeleitet; es ersetzt den handgezeichneten Plan nicht,
      sondern ist ein sauber gezeichneter Gegenentwurf.
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
<svg viewBox="0 0 3200 1500" xmlns="http://www.w3.org/2000/svg" role="img"
     aria-label="Technische Zeichnung, sicherungstechnischer Lageplan Obersosa"
     font-family="IBM Plex Sans, Calibri, Arial, sans-serif">
<rect width="3200" height="1500" fill="#fff"/>
<rect x="24" y="24" width="3152" height="1452" fill="none" stroke="#000" stroke-width="3"/>
<text x="60" y="80" font-size="22" font-weight="700" fill="#000" font-family="IBM Plex Mono, monospace">Lageplan Obersosa</text>
<text x="3140" y="80" font-size="14" fill="#000" text-anchor="end" font-family="IBM Plex Mono, monospace">Ril 819.9001 / 819.9002</text>
<line x1="60" y1="96" x2="3140" y2="96" stroke="#000" stroke-width="2"/>
<g transform="translate(70,190) scale(0.985)">__PLAN__</g>
<g font-family="IBM Plex Mono, monospace">
<rect x="60" y="1230" width="1900" height="200" fill="none" stroke="#000" stroke-width="1.5"/>
__LEGENDE__
</g>
<text x="68" y="1462" font-size="11" fill="#000" font-family="IBM Plex Mono, monospace">__FUSS__</text>
<g font-family="IBM Plex Mono, monospace">
<rect x="2020" y="1230" width="1120" height="200" fill="none" stroke="#000" stroke-width="2"/>
<line x1="2020" y1="1288" x2="3140" y2="1288" stroke="#000" stroke-width="1.5"/>
<line x1="2020" y1="1348" x2="3140" y2="1348" stroke="#000" stroke-width="1.5"/>
<line x1="2020" y1="1396" x2="3140" y2="1396" stroke="#000" stroke-width="1.5"/>
<line x1="2860" y1="1288" x2="2860" y2="1396" stroke="#000" stroke-width="1.5"/>
<text x="2034" y="1262" font-size="15" font-weight="700" fill="#000">LF 2 Jahresprojekt 2026 „Mitteltrasse"</text>
<text x="2034" y="1312" font-size="12" fill="#000">5. Teilabschnitt (Los 5) – Chemiezentrum</text>
<text x="2034" y="1338" font-size="11" fill="#333">Betriebsstelle</text>
<text x="2034" y="1338" font-size="11" fill="#333"></text>
<text x="2034" y="1372" font-size="15" font-weight="600" fill="#000">Obersosa</text>
<text x="2874" y="1338" font-size="11" fill="#333">Kennzahl</text>
<text x="2874" y="1372" font-size="15" font-weight="600" fill="#000">27</text>
<text x="2034" y="1420" font-size="11" fill="#333">Inhalt: Sicherungstechnischer Lageplan</text>
<text x="2874" y="1420" font-size="11" fill="#333">Maßstab: ohne</text>
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
            out.append(f'<line x1="{x:.1f}" y1="1230" x2="{x:.1f}" y2="1430" stroke="#000" stroke-width="1"/>')
        out.append(f'<g transform="translate({x+16:.1f},1312)">{icon}</g>')
        out.append(f'<text x="{x+16:.1f}" y="1370" font-size="12" fill="#000">{lab}</text>')
    return "\n".join(out)


def zeilen(rows, spalten):
    out = []
    for r in rows:
        tds = "".join(f'<td class="mono">{v}</td>' if i in spalten else f'<td>{v}</td>'
                      for i, v in enumerate(r))
        out.append(f'<tr>{tds}</tr>')
    return "\n".join(out)


FUSS = ("Alle Weichen EW 1:9, 40 km/h · im Fahrweg des Fernverkehrs EW 1:14, 60 km/h · "
        "Zs 2 an P3 und P4 · Zs 6 an N2 und P2 · beide Strecken elektrifiziert 15 kV 16,7 Hz · "
        "Gleise 5 bis 7 als Wendegleise mit Prellbock")

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
