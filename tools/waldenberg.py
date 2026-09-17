"""Erzeugt den Gleisplan-SVG-Koerper fuer die Betriebsstelle Waldenberg.

build() liefert den Plan zweimal: einmal mit currentColor fuer den Lageplan
(Dark Mode faehig), einmal in Schwarz fuer das Zeichnungsblatt. Dadurch haben
beide Blaetter zwingend dieselbe Geometrie.

Abzweigbahnhof zweier Strecken:
  Strecke 1 (Krug-Furth, km 37,5), zweigleisig, 120 km/h
  Strecke 3 (Waldenberg-Gbf), eingleisig, 80 km/h, beginnt hier bei km 0,0

Von Sued nach Nord, also von unten nach oben im Plan:
  Gleis 1  durchgehendes Hauptgleis Richtung Kilometrierung (Burgwald/Hyxel)
  Gleis 2  durchgehendes Hauptgleis entgegen der Kilometrierung (Zollfurt/Krug)
  Gleis 3  Bahnsteiggleis der Nebenbahn, geht oestlich in Strecke 3 ueber
  Gleis 4  Lade- und Ausweichgleis, ueber W4 und W5 an Gleis 3 angebunden

  Westkopf: W1/W2 Ueberleitverbinder Gleis 1 <-> Gleis 2, W3 Gleis 2 -> Gleis 3
  Mitte:    W4 und W5 Anbindung Gleis 4
  Ostkopf:  W6/W7 Gleis 2 -> Nebenbahn, W8/W9 Ueberleitverbinder Gleis 1 <-> Gleis 2

Weichennummern steigen nach Ril 819.9001 Abschnitt 3(1) mit der Kilometrierung.
Wer eine Weiche verschiebt, muss die Nummerierung und die Verweise in
build_waldenberg.py mitziehen.
"""
import math

# Gleis 1 liegt unten: bei Rechtsverkehr ist das Regelgleis in Richtung der
# Kilometrierung das in Fahrtrichtung rechte, bei nordorientiertem Plan also das
# suedliche. Zugleich zaehlt die Nummerierung damit nach Ril 819.9001 Abschnitt
# 2(3) vom Hauptzugang (Empfangsgebaeude im Sueden) aufsteigend nach Norden.
G1, G2, G3, G4 = 370, 270, 190, 110
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

    # ---- Gleis 4: Lade- und Ausweichgleis, an beiden Enden an Gleis 3 angebunden ----
    A(f'<line x1="878" y1="{G4}" x2="1152" y2="{G4}" stroke="{c}" fill="none" stroke-width="3"/>')
    A(f'<text x="880" y="{G4-22}" font-size="10.5" fill="{soft}">Lade- und Ausweichgleis</text>')

    # ---- Westkopf: W1/W2 Ueberleitverbinder ----
    A(weiche(165, 207, 265, G1, -KEIL, 1, c, soft))
    A(weiche(440, 398, 340, G2, KEIL, 2, c, soft))
    A(f'<line x1="265" y1="{G1-KEIL}" x2="340" y2="{G2+KEIL}" stroke="{c}" stroke-width="3"/>')
    A(gz_auf(265, G1 - KEIL, 340, G2 + KEIL, 0.26, c))
    A(gz_auf(265, G1 - KEIL, 340, G2 + KEIL, 0.74, c))

    # ---- Westkopf: W3 Gleis 2 -> Gleis 3 ----
    A(weiche(470, 512, 570, G2, -KEIL, 3, c, soft))
    A(f'<line x1="570" y1="{G2-KEIL}" x2="658" y2="{G3}" stroke="{c}" stroke-width="3"/>')
    A(gz_auf(570, G2 - KEIL, 658, G3, 0.55, c))

    # ---- W4: Westanbindung Gleis 3 -> Gleis 4 ----
    A(weiche(690, 732, 790, G3, -KEIL, 4, c, soft))
    A(f'<line x1="790" y1="{G3-KEIL}" x2="878" y2="{G4}" stroke="{c}" stroke-width="3"/>')
    A(gz_auf(790, G3 - KEIL, 878, G4, 0.35, c))

    # ---- W5: Ostanbindung Gleis 3 -> Gleis 4, Zungen oestlich, damit die Ausfahrt
    # aus Gleis 4 den Bahnsteigabschnitt von Gleis 3 nicht beruehrt ----
    A(weiche(1340, 1298, 1240, G3, -KEIL, 5, c, soft))
    A(f'<line x1="1240" y1="{G3-KEIL}" x2="1152" y2="{G4}" stroke="{c}" stroke-width="3"/>')
    A(gz_auf(1240, G3 - KEIL, 1152, G4, 0.35, c))

    # ---- W6/W7: Anbindung Gleis 2 -> Nebenbahn, oestlich des Bahnsteigs. Damit faehrt
    # ein Zug aus Gleis 2 auf die Nebenbahn aus, waehrend in Gleis 3 ein anderer
    # Zug am Bahnsteig steht und wendet ----
    A(weiche(1210, 1252, 1310, G2, -KEIL, 6, c, soft))
    A(weiche(1460, 1418, 1360, G3, KEIL, 7, c, soft))
    A(f'<line x1="1310" y1="{G2-KEIL}" x2="1360" y2="{G3+KEIL}" stroke="{c}" stroke-width="3"/>')
    A(gz_auf(1310, G2 - KEIL, 1360, G3 + KEIL, 0.22, c))
    A(gz_auf(1310, G2 - KEIL, 1360, G3 + KEIL, 0.78, c))

    # ---- Ostkopf: W8/W9 Ueberleitverbinder Gleis 1 <-> Gleis 2 ----
    A(weiche(1430, 1472, 1530, G1, -KEIL, 8, c, soft))
    A(weiche(1705, 1663, 1605, G2, KEIL, 9, c, soft))
    A(f'<line x1="1530" y1="{G1-KEIL}" x2="1605" y2="{G2+KEIL}" stroke="{c}" stroke-width="3"/>')
    A(gz_auf(1530, G1 - KEIL, 1605, G2 + KEIL, 0.26, c))
    A(gz_auf(1530, G1 - KEIL, 1605, G2 + KEIL, 0.74, c))

    # ---- Bahnsteige und Empfangsgebaeude (Hauptzugang im Sueden) ----
    A(f'<rect x="820" y="213" width="245" height="34" fill="none" stroke="{soft}" '
      f'stroke-width="1.5" stroke-dasharray="5,4"/>')
    A(f'<text x="942" y="235" text-anchor="middle" fill="{soft}" font-size="12">Bahnsteig 2 (Mittelbahnsteig)</text>')
    A(f'<rect x="820" y="391" width="245" height="34" fill="none" stroke="{soft}" '
      f'stroke-width="1.5" stroke-dasharray="5,4"/>')
    A(f'<text x="942" y="413" text-anchor="middle" fill="{soft}" font-size="12">Bahnsteig 1 (Hausbahnsteig)</text>')

    A(f'<rect x="800" y="443" width="150" height="40" fill="none" stroke="{c}" stroke-width="2"/>')
    A(f'<text x="875" y="468" text-anchor="middle" font-size="11" fill="{c}">Empfangsgebäude</text>')
    A(f'<text x="962" y="468" font-size="10.5" fill="{soft}">Hauptzugang</text>')

    A(f'<line x1="1010" y1="213" x2="1010" y2="425" stroke="{soft}" stroke-width="1.5" stroke-dasharray="3,4"/>')
    A(f'<text x="1020" y="322" font-size="10.5" fill="{soft}">Personenunterführung</text>')

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

    # ---- Signale. Die Hauptbahnsignale liegen im freien Band zwischen Gleis 2
    # und Gleis 1, die Nebenbahnsignale ueber Gleis 3 bzw. unter Gleis 4. ----
    # A: Einfahrsignal Gleis 1 von Zollfurt/Krug, Zs 3 (4) fuer Einfahrt nach Gleis 3
    A(signal(95, G1, False, 'e', 'A', c, zs3='4'))
    # AA: Einfahrsignal Gleis 2 von Zollfurt/Krug fuer Fahrten auf dem Gegengleis
    A(signal(130, G2, True, 'e', 'AA', c))
    # P2: Ausfahrsignal Gleis 2 Richtung Zollfurt/Krug, am Westende Bahnsteig 2.
    # Fahrweg wahlweise gerade auf Streckengleis (2) oder ueber W2/W1 auf Gleis 1
    # = Gegengleisfahrt -> Gegengleisanzeiger und Zs 3 (4)
    A(signal(690, G2, True, 'w', 'P2', c, zs3='4', gga=True))
    # P3: Ausfahrsignal Gleis 3 Richtung Zollfurt/Krug ueber W3/W2 -> abzweigend, Zs 3 (4)
    A(signal(850, G3, False, 'w', 'P3', c, zs3='4'))
    # N1: Ausfahrsignal Gleis 1 Richtung Burgwald/Hyxel, am Ostende Bahnsteig 1.
    # Fahrweg wahlweise gerade auf Streckengleis (1) oder ueber W6/W7 auf Gleis 2
    # = Gegengleisfahrt -> Gegengleisanzeiger und Zs 3 (4)
    A(signal(1080, G1, False, 'e', 'N1', c, zs3='4', gga=True))
    # N2: Ausfahrsignal Gleis 2 Richtung Osten, am Ostende Bahnsteig 2.
    # Fahrweg ueber W4/W5 auf die Nebenbahn (abzweigend, Zs 3) oder gerade
    # auf Streckengleis (2) Richtung Burgwald = Gegengleisfahrt
    A(signal(1080, G2, True, 'e', 'N2', c, zs3='4'))
    # N3: Ausfahrsignal Gleis 3 Richtung Wehrheim (Nebenbahn), am Ostende Bahnsteig 2
    A(signal(1080, G3, False, 'e', 'N3', c))
    # N4: Ausfahrsignal Ladegleis Richtung Wehrheim, abzweigend ueber W4 -> Zs 3 (4)
    A(signal(1090, G4, True, 'e', 'N4', c, zs3='4'))
    # ZU4: Zwischensignal Gleis 4 Richtung Westen, abzweigend ueber W4 -> Zs 3 (4)
    A(signal(975, G4, True, 'w', 'ZU4', c, zs3='4'))
    # F: Einfahrsignal Gleis 2 von Burgwald/Hyxel
    A(signal(1810, G2, True, 'w', 'F', c))
    # FF: Einfahrsignal Gleis 1 von Burgwald/Hyxel fuer Fahrten auf dem Gegengleis
    A(signal(1770, G1, False, 'w', 'FF', c))
    # G: Einfahrsignal von Wehrheim (Nebenbahn); Zs 3 (4) fuer die Einfahrt nach
    # Gleis 4 oder ueber W6 nach Gleis 2
    A(signal(1760, G3, False, 'w', 'G', c, zs3='4'))

    # ---- Streckenwechsel Strecke 1 / Strecke 3 ----
    A(f'<line x1="1560" y1="{G3-22}" x2="1560" y2="{G3+22}" stroke="{soft}" '
      f'stroke-width="1.5" stroke-dasharray="4,3"/>')
    A(f'<text x="1568" y="{G3+34}" font-size="10.5" fill="{soft}">Strecke 3 · km 0,0</text>')

    # ---- Richtungshinweise ----
    A(f'<g fill="{soft}" font-size="12" font-style="italic">'
      f'<text x="{X0}" y="510">← Zollfurt (km 35,5) · Krug (km 34,5)</text>'
      f'<text x="{X0}" y="528">Strecke 1 · Hauptbahn 120 km/h · zweigleisig · Waldenberg km 37,5</text>'
      f'<text x="{X1}" y="510" text-anchor="end">Burgwald (km 40,0) · Hyxel (km 49,0) →</text>'
      f'<text x="{X1}" y="528" text-anchor="end">Strecke 3 · Wehrheim (km 7,0) · Sandheide · Gbf · 80 km/h · eingleisig →</text>'
      f'</g>')

    return "\n        ".join(s)


LAGEPLAN = build("currentColor", "var(--ink-soft)", "var(--surface)")
ZEICHNUNG = build("#000000", "#333333", "#ffffff")

if __name__ == "__main__":
    print(LAGEPLAN[:400])
