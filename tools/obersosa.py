"""Erzeugt den Gleisplan-SVG-Koerper fuer die Betriebsstelle Obersosa.

Obersosa ist der Knoten des Loses: Strecke 1 (Krug - Furth) laeuft durch,
Strecke 2 (Bernstein - Silberberg - Obersosa) endet hier. Beide muenden am
Westkopf zusammen, der Ostkopf fuehrt nur die Strecke 1 weiter.

Die Lage der Strecke 2 am Westkopf ist aus dem Fahrplan hergeleitet: Der
IC 11 Bernstein - Furth haelt in Obersosa nicht (an und ab 10:15), er muss
also durchfahren koennen. Das geht nur, wenn die Strecke 2 auf der Seite
einmuendet, die der Fahrtrichtung nach Furth entgegengesetzt ist - also am
Westkopf. Der IC 15 Bernstein - Erx macht folgerichtig Kopf (an 10:30,
ab 10:45), wofuer die 15 Minuten Aufenthalt reichen.

Gleisbelegung aus dem Zwei-Stunden-Fahrplan: hoechstens fuenf Gleise
gleichzeitig belegt (11:02). Laengste Belegung ist die RB 63 mit 27 Minuten
Wendezeit, dazu RE 72 und IC 15 mit je 15 Minuten.

  Gleis 1  durchgehendes Hauptgleis Strecke 1, Streckengleis (1) Ri Furth
  Gleis 2  durchgehendes Hauptgleis Strecke 1, Streckengleis (2) Ri Krug
  Gleis 3  Bahnsteiggleis, Ueberholung und Verstaerker, beidseitig angebunden
  Gleis 4  Strecke 2, Streckengleis (1); durchgehend nach Osten fuer den
           Fernverkehr Bernstein - Furth, der in Obersosa nicht haelt
  Gleis 5  Strecke 2, Streckengleis (2); Wendegleis, Prellbock im Osten
  Gleis 6  Wendegleis der RB 63 mit 27 Minuten Wendezeit, Prellbock im Osten
  Gleis 7  Ueberholungs- und Gueterzuggleis, Prellbock im Osten

Weichennummern steigen nach Ril 819.9001 Abschnitt 3(1) mit der
Kilometrierung der Strecke 1, also von West nach Ost.
"""
import math

# Gleislagen, Hauptzugang und Empfangsgebaeude liegen unten -> Gleis 1 unten
G7, G6, G5, G4, G3, G2, G1 = 120, 212, 304, 396, 488, 580, 672
X0, X1 = 40, 3000
KEIL = 34
TICK = 9

BS_W, BS_O = 1210, 1740         # Bahnsteigkanten
P_X, N_X = 1150, 1780           # Standort der Ausfahrsignale
PRELL = 1830                    # Prellboecke der Wendegleise
MITTE = 1475                    # Gleisnummern und Personenunterfuehrung


def tick(x, y, c):
    return f'<line x1="{x}" y1="{y-TICK}" x2="{x}" y2="{y+TICK}" stroke="{c}" stroke-width="2"/>'


def weiche(wa, wm, we, y, dy, nr, c, soft):
    """Weiche nach Ril 819.9002 Abschnitt 3(1): Weichenanfang, Luecke,
    Weichenmitte, Schwaerzung bis Weichenende. Nummer an der Weichenmitte auf
    der Seite des Zweiggleises."""
    out = [tick(wa, y, c), tick(wm, y, c),
           f'<polygon points="{wm},{y} {we},{y} {we},{y+dy}" fill="{c}"/>']
    ny = y + (28 if dy > 0 else -17)
    out.append(f'<text x="{wm}" y="{ny}" text-anchor="middle" font-size="13" '
               f'font-weight="600" fill="{c}">{nr}</text>')
    return "\n".join(out)


def grenzzeichen(px, py, dx, dy, c):
    L = math.hypot(dx, dy)
    ux, uy = dx / L, dy / L
    return (f'<line x1="{px - uy*6:.1f}" y1="{py + ux*6:.1f}" '
            f'x2="{px + uy*6:.1f}" y2="{py - ux*6:.1f}" stroke="{c}" stroke-width="2"/>')


def verbindung(x1, y1, x2, y2, c, gz=(0.28, 0.72)):
    """Verbindungsgleis zwischen zwei Weichenenden, mit Grenzzeichen."""
    out = [f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{c}" stroke-width="3"/>']
    dx, dy = x2 - x1, y2 - y1
    for t in gz:
        out.append(grenzzeichen(x1 + dx * t, y1 + dy * t, dx, dy, c))
    return "\n".join(out)


def prellbock(x, y, c):
    """Festprellbock nach Ril 819.9002 Abschnitt 12."""
    return (f'<g stroke="{c}" stroke-width="3" fill="none">'
            f'<line x1="{x-14}" y1="{y}" x2="{x}" y2="{y}"/>'
            f'<line x1="{x}" y1="{y-13}" x2="{x}" y2="{y+13}"/>'
            f'<line x1="{x}" y1="{y-13}" x2="{x-9}" y2="{y-13}"/>'
            f'<line x1="{x}" y1="{y+13}" x2="{x-9}" y2="{y+13}"/></g>')


def signal(mx, ytrack, below, richtung, name, c, zs3=None, zs3v=None,
           zs2=None, zs6=False):
    """Ks-Mehrabschnittssignal, waerterbedient (Schirm ausgefuellt).
    Zusatzsignale nach Ril 819.9002A01: Zs 2 Richtungsanzeiger als
    ausgefuelltes Fuenfeck mit Spitze nach oben, Zs 3 Geschwindigkeitsanzeiger
    als ausgefuelltes Dreieck mit Spitze nach oben, Zs 3v
    Geschwindigkeitsvoranzeiger mit Spitze nach unten, Zs 6
    Gleiswechselanzeiger als Quadrat mit Diagonale, obere Haelfte geschwaerzt.
    Die Symbole stehen wie an einem stehenden Mast angeordnet."""
    y0 = ytrack + 10 if below else ytrack - 24
    ya = y0 + 7
    d = 1 if richtung == 'e' else -1
    arm = 14 if zs6 else 16
    gx = mx + d * arm
    sx = gx + d * (13 if zs6 else 0)
    o = [f'<g stroke="{c}" stroke-width="2" fill="none">'
         f'<line x1="{mx}" y1="{y0}" x2="{mx}" y2="{y0+14}"/>'
         f'<line x1="{mx}" y1="{ya}" x2="{gx}" y2="{ya}"/></g>']
    if zs6:
        a, b = sorted((gx, sx))
        o.append(f'<rect x="{a}" y="{ya-6.5}" width="13" height="13" fill="none" '
                 f'stroke="{c}" stroke-width="1.5"/>')
        if d == 1:
            o.append(f'<polygon points="{a},{ya-6.5} {b},{ya-6.5} {b},{ya+6.5}" fill="{c}"/>')
        else:
            o.append(f'<polygon points="{b},{ya-6.5} {a},{ya-6.5} {a},{ya+6.5}" fill="{c}"/>')
    rx = sx if d == 1 else sx - 18
    o.append(f'<rect x="{rx}" y="{ya-6}" width="18" height="12" rx="6" fill="{c}"/>')

    x = sx + d * 22                      # Standort des ersten Zusatzsignals
    if zs3:
        o.append(f'<polygon points="{x-7},{ya+6} {x+7},{ya+6} {x},{ya-7}" fill="{c}"/>')
        o.append(f'<text x="{x}" y="{ya-11}" text-anchor="middle" font-size="11" '
                 f'font-weight="600" fill="{c}">{zs3}</text>')
        x += d * 30
    if zs3v:
        o.append(f'<polygon points="{x-7},{ya-6} {x+7},{ya-6} {x},{ya+7}" fill="{c}"/>')
        o.append(f'<text x="{x}" y="{ya+19}" text-anchor="middle" font-size="11" '
                 f'font-weight="600" fill="{c}">{zs3v}</text>')
        x += d * 30
    if zs2:
        o.append(f'<polygon points="{x-7},{ya+7} {x-7},{ya-2} {x},{ya-8} {x+7},{ya-2} '
                 f'{x+7},{ya+7}" fill="{c}"/>')
        o.append(f'<text x="{x}" y="{ya-13}" text-anchor="middle" font-size="10" '
                 f'font-weight="600" fill="{c}">{zs2}</text>')
    if d == 1:
        o.append(f'<text x="{mx-8}" y="{ya+4}" text-anchor="end" font-size="13" '
                 f'font-weight="600" fill="{c}">{name}</text>')
    else:
        o.append(f'<text x="{mx+8}" y="{ya+4}" font-size="13" font-weight="600" fill="{c}">{name}</text>')
    return "\n".join(o)


def gleisnummer(x, y, n, c, surface):
    return (f'<rect x="{x-12}" y="{y-10}" width="24" height="20" fill="{surface}"/>'
            f'<text x="{x}" y="{y+6}" text-anchor="middle" font-size="14" '
            f'font-weight="600" fill="{c}">{n}</text>')


def bahnsteig(y1, y2, nr, text, c, soft):
    return (f'<rect x="{BS_W}" y="{y1}" width="{BS_O-BS_W}" height="{y2-y1}" fill="none" '
            f'stroke="{soft}" stroke-width="1.5" stroke-dasharray="5,4"/>'
            f'<text x="{(BS_W+BS_O)/2}" y="{(y1+y2)/2+5}" text-anchor="middle" '
            f'fill="{soft}" font-size="12">{text}</text>')


def build(c, soft, surface):
    s = []
    A = s.append
    A(f'<text x="{MITTE}" y="30" text-anchor="middle" font-size="18" font-weight="700" fill="{c}">Obersosa</text>')
    A(f'<text x="{MITTE}" y="48" text-anchor="middle" font-size="11" fill="{soft}">'
      f'(Os) 27 · Trennungsbahnhof · Strecke 1 km 63,5 · Strecke 2 km 51,0</text>')

    # ---- Gleise ----
    G = f'<g stroke="{c}" fill="none" stroke-width="3">'
    A(G + f'<line x1="{X0}" y1="{G1}" x2="{X1}" y2="{G1}"/>'
        + f'<line x1="{X0}" y1="{G2}" x2="{X1}" y2="{G2}"/>'
        + f'<line x1="770" y1="{G3}" x2="2300" y2="{G3}"/>'
        + f'<line x1="{X0}" y1="{G4}" x2="2000" y2="{G4}"/>'
        + f'<line x1="{X0}" y1="{G5}" x2="{PRELL}" y2="{G5}"/>'
        + f'<line x1="770" y1="{G6}" x2="{PRELL}" y2="{G6}"/>'
        + f'<line x1="1070" y1="{G7}" x2="{PRELL}" y2="{G7}"/></g>')
    for y in (G5, G6, G7):
        A(prellbock(PRELL, y, c))

    # ---- Weichen ----
    # Jede Weichenverbindung als Paar; die Nummern werden anschliessend nach
    # der Weichenmitte vergeben, damit sie nach Ril 819.9001 Abschnitt 3(1)
    # mit der Kilometrierung steigen.
    paare = [
        # (Gleis A: wa, wm, we, y, dy) , (Gleis B: ...) , Beschreibung
        ((170, 212, 270, G1, -KEIL), (490, 448, 390, G2,  KEIL)),   # UELV Gleis 1 <-> 2
        ((190, 232, 290, G4, -KEIL), (510, 468, 410, G5,  KEIL)),   # UELV Strecke 2
        ((560, 602, 660, G2, -KEIL), None),                          # Gleis 2 -> Gleis 3
        ((580, 622, 680, G5, -KEIL), None),                          # Gleis 5 -> Gleis 6
        ((860, 902, 960, G6, -KEIL), None),                          # Gleis 6 -> Gleis 7
        ((880, 922, 980, G4,  KEIL), (1120, 1078, 1020, G3, -KEIL)), # Gleis 4 <-> Gleis 3
        ((1900, 1942, 2000, G4, KEIL), (2160, 2118, 2060, G3, -KEIL)),  # Ostkopf Gleis 4 -> 3
        ((2200, 2242, 2300, G3, KEIL), (2460, 2418, 2360, G2, -KEIL)),  # Ostkopf Gleis 3 -> 2
        ((2500, 2542, 2600, G2, KEIL), (2790, 2748, 2690, G1, -KEIL)),  # UELV Gleis 2 <-> 1
    ]
    # freie Enden: Weiche -> Gleisanfang
    frei = {2: (770, G3), 3: (770, G6), 4: (1070, G7)}

    nummern = sorted(wm for a, b in paare for (_, wm, _, _, _) in
                     ([a] + ([b] if b else [])))
    assert len(nummern) == len(set(nummern)), \
        'zwei Weichen auf derselben Weichenmitte: Nummerierung waere nicht eindeutig'
    nr_von = {wm: i + 1 for i, wm in enumerate(nummern)}
    for i, (a, b) in enumerate(paare):
        wa, wm, we, y, dy = a
        A(weiche(wa, wm, we, y, dy, nr_von[wm], c, soft))
        if b:
            wa2, wm2, we2, y2, dy2 = b
            A(weiche(wa2, wm2, we2, y2, dy2, nr_von[wm2], c, soft))
            A(verbindung(we, y + dy, we2, y2 + dy2, c))
        else:
            zx, zy = frei[i]
            A(verbindung(we, y + dy, zx, zy, c, gz=(0.5,)))

    # ---- Bahnsteige und Empfangsgebaeude ----
    A(bahnsteig(G7 + 22, G6 - 22, 4, 'Bahnsteig 4 (Mittelbahnsteig)', c, soft))
    A(bahnsteig(G5 + 22, G4 - 22, 3, 'Bahnsteig 3 (Mittelbahnsteig)', c, soft))
    A(bahnsteig(G3 + 22, G2 - 22, 2, 'Bahnsteig 2 (Mittelbahnsteig)', c, soft))
    A(bahnsteig(G1 + 22, G1 + 68, 1, 'Bahnsteig 1 (Hausbahnsteig)', c, soft))
    A(f'<rect x="{MITTE-150}" y="{G1+100}" width="300" height="48" fill="none" stroke="{c}" stroke-width="2"/>')
    A(f'<text x="{MITTE}" y="{G1+130}" text-anchor="middle" font-size="12" fill="{c}">Empfangsgebäude</text>')
    A(f'<text x="{MITTE+165}" y="{G1+130}" font-size="10.5" fill="{soft}">Hauptzugang</text>')
    A(f'<line x1="{MITTE}" y1="{G7+22}" x2="{MITTE}" y2="{G1+68}" stroke="{soft}" '
      f'stroke-width="1.5" stroke-dasharray="3,4"/>')
    A(f'<text x="{MITTE+10}" y="{G1-34}" font-size="10.5" fill="{soft}">Personenunterführung</text>')

    # ---- Gleisnummern ----
    for y, n in ((G1, 1), (G2, 2), (G3, 3), (G4, 4), (G5, 5), (G6, 6), (G7, 7)):
        A(gleisnummer(MITTE, y, n, c, surface))

    # ---- Streckengleisbezeichnungen ----
    A(f'<g fill="{soft}" font-size="12">'
      f'<text x="46" y="{G1+22}">(1)</text><text x="46" y="{G2-10}">(2)</text>'
      f'<text x="46" y="{G4+22}">(1)</text><text x="46" y="{G5-10}">(2)</text>'
      f'<text x="{X1-6}" y="{G1+22}" text-anchor="end">(1)</text>'
      f'<text x="{X1-6}" y="{G2-10}" text-anchor="end">(2)</text></g>')

    # ---- Signale ----
    # Einfahrsignale in Richtung der Kilometrierung: A-E (Ril 819.9001 Abs. 4(2)),
    # doppelter Buchstabe fuer Einfahrten vom Gegengleis
    A(signal(100, G1, False, 'e', 'A',  c, zs3='6'))
    A(signal(140, G2, True,  'e', 'AA', c, zs3='6'))
    A(signal(100, G4, False, 'e', 'B',  c, zs3='6'))
    A(signal(140, G5, True,  'e', 'BB', c, zs3='6'))
    # Einfahrsignale entgegen der Kilometrierung: F-K
    A(signal(X1 - 30, G2, True,  'w', 'F',  c, zs3='6'))
    A(signal(X1 - 80, G1, False, 'w', 'FF', c, zs3='6'))
    # Ausfahrsignale entgegen der Kilometrierung: P + Gleisnummer.
    # Zs 2 Richtungsanzeiger dort, wo die Ausfahrt nach Hyxel (H) oder
    # Silberberg (S) fuehren kann.
    A(signal(P_X, G1, False, 'w', 'P1', c, zs3='6'))
    A(signal(P_X, G2, True,  'w', 'P2', c, zs3='6', zs6=True))
    A(signal(P_X, G3, True,  'w', 'P3', c, zs3='4', zs2='H,S'))
    A(signal(P_X, G4, True,  'w', 'P4', c, zs3='6', zs2='H,S'))
    A(signal(P_X, G5, True,  'w', 'P5', c, zs3='6'))
    A(signal(P_X, G6, True,  'w', 'P6', c, zs3='4'))
    A(signal(P_X, G7, True,  'w', 'P7', c, zs3='4'))
    # Ausfahrsignale in Richtung der Kilometrierung: N + Gleisnummer.
    # Nur die Gleise 1 bis 4 haben eine Ausfahrt nach Osten.
    A(signal(N_X, G1, False, 'e', 'N1', c, zs3='6'))
    A(signal(N_X, G2, True,  'e', 'N2', c, zs3='6', zs6=True))
    A(signal(N_X, G3, True,  'e', 'N3', c, zs3='4'))
    A(signal(N_X, G4, True,  'e', 'N4', c, zs3='4'))

    # ---- Streckenangaben ----
    A(f'<g fill="{soft}" font-size="12" font-style="italic">'
      f'<text x="{X0}" y="{G1+200}">← Altensund (km 62,0) · Hyxel (km 49,0) · Krug · Erx</text>'
      f'<text x="{X0}" y="{G1+218}">Strecke 1 · Hauptbahn · zweigleisig mit Gleiswechselbetrieb · Hg 120 km/h</text>'
      f'<text x="{X0}" y="{G1+236}">elektrifiziert 15 kV 16,7 Hz · Obersosa km 63,5</text>'
      f'<text x="{X0}" y="{G7-58}">← Hochstein (km 46,0) · Silberberg (km 24,5) · Bernstein</text>'
      f'<text x="{X0}" y="{G7-40}">Strecke 2 · Hauptbahn · zweigleisig · Hg 120 km/h · elektrifiziert · endet hier bei km 51,0</text>'
      f'<text x="{X1}" y="{G1+200}" text-anchor="end">Kunststoffwerk (km 65,5) · Rotheim · Feldheim (km 75,5) · Furth →</text>'
      f'<text x="{X1}" y="{G1+218}" text-anchor="end">Strecke 1 · Angaben wie links</text></g>')
    return "\n".join(s)


LAGEPLAN = build("currentColor", "var(--ink-soft)", "var(--surface)")
ZEICHNUNG = build("#000000", "#333333", "#ffffff")
