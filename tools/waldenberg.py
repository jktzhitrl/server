"""Erzeugt den Gleisplan-SVG-Koerper fuer die Betriebsstelle Waldenberg.

build() liefert den Plan zweimal: einmal mit currentColor fuer den Lageplan
(Dark Mode faehig), einmal in Schwarz fuer das Zeichnungsblatt. Dadurch haben
beide Blaetter zwingend dieselbe Geometrie.

Abzweigbahnhof zweier Strecken:
  Strecke 1 (Krug-Furth, km 37,5), zweigleisig, 120 km/h
  Strecke 3 (Waldenberg-Gbf), eingleisig, 80 km/h, beginnt hier bei km 0,0

  Gleis 2 (oben)  durchgehendes Hauptgleis, geht in Streckengleis (2) ueber
  Gleis 1 (Mitte) durchgehendes Hauptgleis, geht in Streckengleis (1) ueber
  Gleis 3         Bahnsteiggleis der Nebenbahn, geht oestlich in Strecke 3 ueber
  Gleis 4         Lade- und Ausweichgleis, ueber W4 und W5 an Gleis 3 angebunden

  Westkopf: W1/W2 Ueberleitverbinder Gleis 2 <-> Gleis 1, W3 Gleis 1 -> Gleis 3
  Mitte:    W4 und W5 Anbindung Gleis 4
  Ostkopf:  W6/W7 Gleis 1 -> Nebenbahn, W8/W9 Ueberleitverbinder Gleis 2 <-> Gleis 1

Die Zungen der beiden Ueberleitverbinder liegen so, dass ein Zug, der auf dem
Gegengleis der freien Strecke ankommt, ins jeweils andere Bahnhofsgleis wechseln
kann (AA ueber W1/W2, FF ueber W9/W8) und dass ein Zug aus dem Bahnhofsgleis der
Gegenrichtung auf sein Regelgleis ausfahren kann (N2 ueber W8/W9, P3 ueber W2/W1).

Weichennummern steigen nach Ril 819.9001 Abschnitt 3(1) mit der Kilometrierung.
Wer eine Weiche verschiebt, muss die Nummerierung und die Verweise in
build_waldenberg.py mitziehen.
"""
import math

# Gleis 1 ist das mittlere, Gleis 2 das obere Hauptgleis: bei Rechtsverkehr ist
# das Regelgleis in Richtung der Kilometrierung das in Fahrtrichtung rechte, im
# Plan also das suedlichere der beiden Hauptgleise.
G1, G2, G3, G4 = 275, 175, 355, 435
X0, X1 = 40, 1860
KEIL = 32          # Hoehe der Schwaerzung am Weichenende
TICK = 9           # halbe Hoehe von Weichenanfang / Weichenmitte


def tick(x, y, c):
    return f'<line x1="{x}" y1="{y-TICK}" x2="{x}" y2="{y+TICK}" stroke="{c}" stroke-width="2"/>'


def weiche(wa, wm, we, y, dy, nr, c, soft):
    """Einfache Weiche nach Ril 819.9002: Weichenanfang, Luecke, Weichenmitte,
    Schwaerzung bis Weichenende. Weichennummer an der Weichenmitte auf der
    Seite des Zweiggleises. wa darf oestlich von wm liegen (gespiegelte Weiche)."""
    out = [tick(wa, y, c), tick(wm, y, c)]
    out.append(f'<polygon points="{wm},{y} {we},{y} {we},{y+dy}" fill="{c}"/>')
    ny = y + (27 if dy > 0 else -16)
    out.append(f'<text x="{wm}" y="{ny}" text-anchor="middle" font-size="13" '
               f'font-weight="600" fill="{c}">{nr}</text>')
    return "\n".join(out)


def grenzzeichen(px, py, dx, dy, c):
    """Kurzer Strich quer zum Zweiggleis, hinter dem Weichenende."""
    L = math.hypot(dx, dy)
    ux, uy = dx / L, dy / L
    return (f'<line x1="{px - uy*6:.1f}" y1="{py + ux*6:.1f}" '
            f'x2="{px + uy*6:.1f}" y2="{py - ux*6:.1f}" stroke="{c}" stroke-width="2"/>')


def gz_auf(x1, y1, x2, y2, t, c):
    """Grenzzeichen an Position t (0..1) auf der Strecke (x1,y1)->(x2,y2)."""
    dx, dy = x2 - x1, y2 - y1
    return grenzzeichen(x1 + dx * t, y1 + dy * t, dx, dy, c)


def signal(mx, ytrack, below, richtung, name, c, zs3=None, gga=False):
    """Ks-Mehrabschnittssignal, waerterbedient (Schirm ausgefuellt), in Fahrtrichtung
    abgeklappt. richtung 'e' = Schirm oestlich des Mastes, 'w' = westlich.
    gga = Gegengleisanzeiger als Lichtsignal am Schirm (Quadrat mit Diagonale,
    obere Haelfte geschwaerzt) zwischen Mast und Signalschirm."""
    y0 = ytrack + 10 if below else ytrack - 24
    ya = y0 + 7
    d = 1 if richtung == 'e' else -1          # Richtung, in die das Symbol aufgebaut wird
    arm = 14 if gga else 16
    gx = mx + d * arm                          # Aussenkante Gegengleisanzeiger
    sx = gx + d * (13 if gga else 0)           # Aussenkante Signalschirm
    o = [f'<g stroke="{c}" stroke-width="2" fill="none">'
         f'<line x1="{mx}" y1="{y0}" x2="{mx}" y2="{y0+14}"/>'
         f'<line x1="{mx}" y1="{ya}" x2="{gx}" y2="{ya}"/></g>']
    if gga:
        x0, x1 = sorted((gx, sx))
        o.append(f'<rect x="{x0}" y="{ya-6.5}" width="13" height="13" fill="none" '
                 f'stroke="{c}" stroke-width="1.5"/>')
        # Diagonale von oben aussen nach unten innen, obere Haelfte geschwaerzt
        if d == 1:
            o.append(f'<polygon points="{x0},{ya-6.5} {x1},{ya-6.5} {x1},{ya+6.5}" fill="{c}"/>')
        else:
            o.append(f'<polygon points="{x1},{ya-6.5} {x0},{ya-6.5} {x0},{ya+6.5}" fill="{c}"/>')
    rx = sx if d == 1 else sx - 18
    o.append(f'<rect x="{rx}" y="{ya-6}" width="18" height="12" rx="6" fill="{c}"/>')
    if zs3:
        zx = sx + d * 21
        if d == 1:
            o.append(f'<polygon points="{zx},{ya-6} {zx+10},{ya} {zx},{ya+6}" fill="{c}"/>')
            o.append(f'<text x="{zx+14}" y="{ya+4}" font-size="11" font-weight="600" fill="{c}">{zs3}</text>')
        else:
            o.append(f'<polygon points="{zx},{ya-6} {zx-10},{ya} {zx},{ya+6}" fill="{c}"/>')
            o.append(f'<text x="{zx-14}" y="{ya+4}" text-anchor="end" font-size="11" '
                     f'font-weight="600" fill="{c}">{zs3}</text>')
    if d == 1:
        o.append(f'<text x="{mx-8}" y="{ya+4}" text-anchor="end" font-size="13" '
                 f'font-weight="600" fill="{c}">{name}</text>')
    else:
        o.append(f'<text x="{mx+8}" y="{ya+4}" font-size="13" font-weight="600" fill="{c}">{name}</text>')
    return "\n".join(o)


def gleissperre(x, y, nr, c, surface):
    """Gleissperre nach Ril 819.9002 Abschnitt 3(2): Sperrschuh als geschwaerztes
    Rechteck (ferngestellt) quer zum Gleis = Grundstellung aufliegend, Pfeil fuer
    Fahrt- und Auswurfrichtung, Nummer nah am Symbol."""
    return "\n".join([
        f'<rect x="{x-6}" y="{y-15}" width="12" height="32" fill="{c}"/>',
        f'<line x1="{x-6}" y1="{y+17}" x2="{x+6}" y2="{y-15}" stroke="{surface}" stroke-width="1.5"/>',
        f'<line x1="{x+5}" y1="{y+14}" x2="{x+16}" y2="{y+25}" stroke="{c}" stroke-width="2"/>',
        f'<polygon points="{x+23},{y+32} {x+18.7},{y+22.1} {x+13.1},{y+27.7}" fill="{c}"/>',
        f'<line x1="{x+6}" y1="{y-13}" x2="{x+20}" y2="{y-27}" stroke="{c}" stroke-width="1.5"/>',
        f'<text x="{x+24}" y="{y-25}" font-size="13" font-weight="600" fill="{c}">{nr}</text>',
    ])


def ohne_fahrleitung(x1, y1, x2, y2, t, seite, c):
    """Symbol "Nicht elektrifiziertes Gleis" nach Ril 819.9002 Abschnitt 12:
    Raute auf der Gleislinie mit senkrechtem Strich; der nicht elektrifizierte
    Bereich liegt auf der Seite des Striches. Das Symbol sitzt im Punkt t der
    Strecke (x1,y1)->(x2,y2) und liegt in deren Richtung; seite = +1 zeigt den
    nicht elektrifizierten Bereich nach (x2,y2), seite = -1 nach (x1,y1).
    Die Ril verlangt, das Symbol vom Weichensymbol weg in den nicht
    elektrifizierten Bereich zu schieben, bis es sich nicht mehr ueberlagert.
    Die Fahrleitung selbst wird im sicherungstechnischen Lageplan nicht
    dargestellt, Schaltabschnittsgrenzen bleiben nach Ril 819.9002A01 ohne
    Darstellung."""
    r = 9
    x = x1 + (x2 - x1) * t
    y = y1 + (y2 - y1) * t
    w = math.degrees(math.atan2(y2 - y1, x2 - x1))
    sx = seite * r
    return (f'<g transform="translate({x:.1f},{y:.1f}) rotate({w:.2f})">'
            f'<polygon points="{-r},0 0,{-r} {r},0 0,{r}" '
            f'fill="none" stroke="{c}" stroke-width="2.5"/>'
            f'<line x1="{sx}" y1="{-r-3}" x2="{sx}" y2="{r+3}" '
            f'stroke="{c}" stroke-width="2.5"/></g>')


def gleisnummer(x, y, n, c, surface):
    return (f'<rect x="{x-12}" y="{y-10}" width="24" height="20" fill="{surface}"/>'
            f'<text x="{x}" y="{y+6}" text-anchor="middle" font-size="14" '
            f'font-weight="600" fill="{c}">{n}</text>')


def build(c, soft, surface):
    s = []
    A = s.append

    # ---- Betriebsstelle ----
    A(f'<text x="850" y="28" text-anchor="middle" font-size="17" font-weight="700" fill="{c}">Waldenberg</text>')
    A(f'<text x="850" y="45" text-anchor="middle" font-size="11" fill="{soft}">(Wbg) 31 · Abzweigbahnhof</text>')

    # ---- Durchgehende Hauptgleise ----
    A(f'<g stroke="{c}" fill="none" stroke-width="3">'
      f'<line x1="{X0}" y1="{G1}" x2="{X1}" y2="{G1}"/>'
      f'<line x1="{X0}" y1="{G2}" x2="{X1}" y2="{G2}"/></g>')

    # ---- Gleis 3 / Nebenbahn (Strecke 3, km 0,0) ----
    A(f'<g stroke="{c}" fill="none" stroke-width="3">'
      f'<line x1="658" y1="{G3}" x2="{X1}" y2="{G3}"/></g>')

    # ---- Gleis 4: Lade- und Ausweichgleis, an beiden Enden an Gleis 3 angebunden.
    # Nebengleis -> duennere Gleislinie nach Ril 819.9002 Abschnitt 12.
    A(f'<line x1="878" y1="{G4}" x2="1152" y2="{G4}" stroke="{c}" fill="none" stroke-width="2"/>')
    A(f'<text x="880" y="{G4+35}" font-size="10.5" fill="{soft}">Lade- und Ausweichgleis · ohne Fahrleitung</text>')

    # ---- Westkopf: W1/W2 Ueberleitverbinder ----
    A(weiche(165, 207, 265, G2, KEIL, 1, c, soft))
    A(weiche(440, 398, 340, G1, -KEIL, 2, c, soft))
    A(f'<line x1="265" y1="{G2+KEIL}" x2="340" y2="{G1-KEIL}" stroke="{c}" stroke-width="3"/>')
    A(gz_auf(265, G2 + KEIL, 340, G1 - KEIL, 0.26, c))
    A(gz_auf(265, G2 + KEIL, 340, G1 - KEIL, 0.74, c))

    # ---- Westkopf: W3 Gleis 1 -> Gleis 3 ----
    A(weiche(470, 512, 570, G1, KEIL, 3, c, soft))
    A(f'<line x1="570" y1="{G1+KEIL}" x2="658" y2="{G3}" stroke="{c}" stroke-width="3"/>')
    A(gz_auf(570, G1 + KEIL, 658, G3, 0.55, c))

    # ---- W4: Westanbindung Gleis 3 -> Gleis 4 ----
    A(weiche(690, 732, 790, G3, KEIL, 4, c, soft))
    A(f'<line x1="790" y1="{G3+KEIL}" x2="878" y2="{G4}" stroke="{c}" stroke-width="2"/>')
    A(gz_auf(790, G3 + KEIL, 878, G4, 0.35, c))
    # Gleis 4 ohne Fahrleitung: Ladearbeiten unter Fahrdraht sind nicht zulaessig
    A(ohne_fahrleitung(790, G3 + KEIL, 878, G4, 0.74, 1, c))

    # ---- Ostkopf: W6/W7 Anbindung Gleis 1 -> Nebenbahn, oestlich des Bahnsteigs.
    # Damit faehrt ein Zug aus Gleis 1 auf die Nebenbahn aus, waehrend in Gleis 3
    # ein anderer Zug am Bahnsteig steht und wendet.
    # W5: Ostanbindung Gleis 3 -> Gleis 4, Zungen oestlich, damit die Ausfahrt aus
    # Gleis 4 den Bahnsteigabschnitt von Gleis 3 nicht beruehrt
    A(weiche(1340, 1298, 1240, G3, KEIL, 5, c, soft))
    A(f'<line x1="1240" y1="{G3+KEIL}" x2="1152" y2="{G4}" stroke="{c}" stroke-width="2"/>')
    A(gz_auf(1240, G3 + KEIL, 1152, G4, 0.35, c))
    A(ohne_fahrleitung(1240, G3 + KEIL, 1152, G4, 0.74, 1, c))

    # W6/W7: Anbindung Gleis 1 -> Nebenbahn, oestlich des Bahnsteigs
    A(weiche(1210, 1252, 1310, G1, KEIL, 6, c, soft))
    A(weiche(1460, 1418, 1360, G3, -KEIL, 7, c, soft))
    A(f'<line x1="1310" y1="{G1+KEIL}" x2="1360" y2="{G3-KEIL}" stroke="{c}" stroke-width="3"/>')
    A(gz_auf(1310, G1 + KEIL, 1360, G3 - KEIL, 0.22, c))
    A(gz_auf(1310, G1 + KEIL, 1360, G3 - KEIL, 0.78, c))

    # ---- Ostkopf: W8/W9 Ueberleitverbinder Gleis 2 <-> Gleis 1 ----
    A(weiche(1430, 1472, 1530, G2, KEIL, 8, c, soft))
    A(weiche(1705, 1663, 1605, G1, -KEIL, 9, c, soft))
    A(f'<line x1="1530" y1="{G2+KEIL}" x2="1605" y2="{G1-KEIL}" stroke="{c}" stroke-width="3"/>')
    A(gz_auf(1530, G2 + KEIL, 1605, G1 - KEIL, 0.26, c))
    A(gz_auf(1530, G2 + KEIL, 1605, G1 - KEIL, 0.74, c))

    # ---- Empfangsgebaeude und Bahnsteige ----
    A(f'<rect x="800" y="58" width="150" height="40" fill="none" stroke="{c}" stroke-width="2"/>')
    A(f'<text x="875" y="83" text-anchor="middle" font-size="11" fill="{c}">Empfangsgebäude</text>')
    A(f'<text x="962" y="83" font-size="10.5" fill="{soft}">Hauptzugang</text>')

    A(f'<rect x="820" y="120" width="245" height="34" fill="none" stroke="{soft}" '
      f'stroke-width="1.5" stroke-dasharray="5,4"/>')
    A(f'<text x="942" y="142" text-anchor="middle" fill="{soft}" font-size="12">Bahnsteig 1 (Hausbahnsteig)</text>')
    A(f'<rect x="820" y="295" width="245" height="34" fill="none" stroke="{soft}" '
      f'stroke-width="1.5" stroke-dasharray="5,4"/>')
    A(f'<text x="942" y="317" text-anchor="middle" fill="{soft}" font-size="12">Bahnsteig 2 (Mittelbahnsteig)</text>')

    A(f'<line x1="1010" y1="120" x2="1010" y2="329" stroke="{soft}" stroke-width="1.5" stroke-dasharray="3,4"/>')
    A(f'<text x="1020" y="238" font-size="10.5" fill="{soft}">Personenunterführung</text>')

    # ---- Gleisnummern in unterbrochener Gleislinie ----
    for y, n in ((G1, 1), (G2, 2), (G3, 3)):
        A(gleisnummer(860, y, n, c, surface))
    A(gleisnummer(900, G4, 4, c, surface))

    # ---- Streckengleisbezeichnungen ----
    A(f'<g fill="{soft}" font-size="12">'
      f'<text x="46" y="{G1+22}">(1)</text>'
      f'<text x="46" y="{G2-10}">(2)</text>'
      f'<text x="{X1-6}" y="{G1+22}" text-anchor="end">(1)</text>'
      f'<text x="{X1-6}" y="{G2-10}" text-anchor="end">(2)</text></g>')

    # ---- Signale ----
    # A: Einfahrsignal Gleis 1 von Zollfurt/Krug, Zs 3 (4) fuer die abzweigende
    # Einfahrt ueber W3 nach Gleis 3
    A(signal(95, G1, False, 'e', 'A', c, zs3='4'))
    # AA: Einfahrsignal fuer Zuege, die auf dem Gegengleis (2) ankommen; Einfahrt
    # gerade nach Gleis 2 oder abzweigend ueber W1/W2 nach Gleis 1 -> Zs 3 (4)
    A(signal(130, G2, True, 'e', 'AA', c, zs3='4'))
    # P2: Ausfahrsignal Gleis 2 Richtung Zollfurt/Krug, am Westende Bahnsteig 1.
    # Einziger Fahrweg: gerade und stumpf durch W1 auf Streckengleis (2), das
    # Regelgleis dieser Richtung -> weder Zs 3 noch Gegengleisanzeiger
    A(signal(690, G2, True, 'w', 'P2', c))
    # P3: Ausfahrsignal Gleis 3 Richtung Zollfurt/Krug, abzweigend ueber W3 -> Zs 3 (4).
    # Weiter ueber W2/W1 auf Streckengleis (2) oder gerade durch W2 auf Streckengleis
    # (1) = Gegengleis dieser Richtung -> Gegengleisanzeiger
    A(signal(850, G3, True, 'w', 'P3', c, zs3='4', gga=True))
    # N1: Ausfahrsignal Gleis 1 Richtung Burgwald/Hyxel, am Ostende Bahnsteig 2.
    # Gerade auf Streckengleis (1), das Regelgleis dieser Richtung, oder abzweigend
    # ueber W6/W7 auf die Nebenbahn -> Zs 3 (4), kein Gegengleisanzeiger
    A(signal(1080, G1, False, 'e', 'N1', c, zs3='4'))
    # N2: Ausfahrsignal Gleis 2 Richtung Burgwald/Hyxel, am Ostende Bahnsteig 1.
    # Abzweigend ueber W8/W9 auf Streckengleis (1) -> Zs 3 (4), oder gerade auf
    # Streckengleis (2) = Gegengleis dieser Richtung -> Gegengleisanzeiger
    A(signal(1080, G2, True, 'e', 'N2', c, zs3='4', gga=True))
    # N3: Ausfahrsignal Gleis 3 Richtung Wehrheim (Nebenbahn), am Ostende Bahnsteig 2,
    # gerade und stumpf durch W7 -> kein Zs 3
    A(signal(1080, G3, True, 'e', 'N3', c))
    # N4: Ausfahrsignal Ladegleis Richtung Wehrheim, abzweigend ueber W4 -> Zs 3 (4)
    A(signal(1090, G4, True, 'e', 'N4', c, zs3='4'))
    # ZU4: Zwischensignal Gleis 4 Richtung Westen, abzweigend ueber W4 -> Zs 3 (4)
    A(signal(975, G4, True, 'w', 'ZU4', c, zs3='4'))
    # F: Einfahrsignal Gleis 2 von Burgwald/Hyxel; einziger Fahrweg gerade und stumpf
    # durch W8 nach Gleis 2 -> kein Zs 3
    A(signal(1810, G2, True, 'w', 'F', c))
    # FF: Einfahrsignal fuer Zuege, die auf dem Gegengleis (1) ankommen; Einfahrt
    # gerade nach Gleis 1 oder abzweigend ueber W9/W8 nach Gleis 2 -> Zs 3 (4)
    A(signal(1770, G1, False, 'w', 'FF', c, zs3='4'))
    # G: Einfahrsignal von Wehrheim (Nebenbahn); Zs 3 (4) fuer die Einfahrt nach
    # Gleis 4 (W5) oder ueber W7/W6 nach Gleis 1
    A(signal(1760, G3, True, 'w', 'G', c, zs3='4'))

    # ---- Streckenwechsel Strecke 1 / Strecke 3 ----
    A(f'<line x1="1560" y1="{G3-22}" x2="1560" y2="{G3+22}" stroke="{soft}" '
      f'stroke-width="1.5" stroke-dasharray="4,3"/>')
    A(f'<text x="1568" y="{G3-26}" font-size="10.5" fill="{soft}">Strecke 3 · km 0,0</text>')

    # ---- Richtungshinweise ----
    A(f'<g fill="{soft}" font-size="12" font-style="italic">'
      f'<text x="{X0}" y="498">← Zollfurt (km 35,5) · Krug (km 34,5)</text>'
      f'<text x="{X0}" y="516">Strecke 1 · Hauptbahn · zweigleisig mit Gleiswechselbetrieb · Hg 120 km/h</text>'
      f'<text x="{X0}" y="534">elektrifiziert 15 kV 16,7 Hz · Waldenberg km 37,5</text>'
      f'<text x="{X1}" y="498" text-anchor="end">Burgwald (km 40,0) · Hyxel (km 49,0) →</text>'
      f'<text x="{X1}" y="516" text-anchor="end">Strecke 3 · Wehrheim (km 7,0) · Sandheide · Gbf →</text>'
      f'<text x="{X1}" y="534" text-anchor="end">Nebenbahn · eingleisig · Hg 80 km/h · elektrifiziert 15 kV 16,7 Hz</text>'
      f'</g>')

    return "\n        ".join(s)


LAGEPLAN = build("currentColor", "var(--ink-soft)", "var(--surface)")
ZEICHNUNG = build("#000000", "#333333", "#ffffff")

if __name__ == "__main__":
    print(LAGEPLAN[:400])
