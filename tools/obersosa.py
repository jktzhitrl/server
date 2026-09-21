"""Erzeugt den Gleisplan-SVG-Koerper fuer die Betriebsstelle Obersosa.

Obersosa ist der Knoten des Loses. Die Grundlage ist die Projektarbeit selbst:
Der Gleisbelegungsplan (Seite 5) gibt sechs Bahnsteiggleise mit a- und
b-Abschnitten vor, der Liniennetzplan (Seite 19) fuenf Zulaufrichtungen, und
die Abfahrtsminuten (Seite 3) die Belegung.

  Richtungen am Westkopf   Krug/Waldenberg/Erx, Silberberg/Bernstein, Windingen/Gbf
  Richtungen am Ostkopf    Lossow/Furth, Kirchheim/Neumark

  Gleis 1  RB 62 aus Neumark (1a) und RB 63 aus Krug (1b), beide enden hier
  Gleis 2  RE 71 und RE 70 Richtung Furth (2a / 2b)
  Gleis 3  RB 61 Richtung Furth, dazu Fernverkehr
  Gleis 4  RB 61 Richtung Waldenberg und Windingen, dazu Fernverkehr
  Gleis 5  RE 71 nach Bernstein (5a) und RE 70 nach Erx (5b) - hier wird der
           Fluegelzug RE 70/71 geteilt und vereinigt
  Gleis 6  RB 65 Richtung Sandheide und Furth
  Gleis 7  Gueter- und Abstellgleis ohne Bahnsteig

Die a/b-Teilung der Bahnsteiggleise wird durch Zwischensignale hergestellt:
ZR nach Ril 819.9001 Abschnitt 4(3) in Richtung der Kilometrierung, ZU
entgegen. Damit koennen zwei Vierteiler - RE Desiro HC, RB Mireo - hinter-
einander am selben Bahnsteig stehen.

Weichennummern steigen mit der Kilometrierung der Strecke 1, also von West
nach Ost. Die Nummern vergibt der Generator selbst aus den Weichenmitten.
"""
import math

# Gleislagen, Hauptzugang und Empfangsgebaeude liegen unten -> Gleis 1 unten
G7, G6, G5, G4, G3, G2, G1 = 110, 198, 286, 374, 462, 550, 638
X0, X1 = 40, 3060
KEIL = 34
TICK = 9

BS_W, BS_O = 1240, 1880         # Bahnsteigkanten
P_X, N_X = 1180, 1940           # Standort der Ausfahrsignale
Z_X = 1560                      # Zwischensignale der a/b-Teilung
MITTE = 1560                    # Gleisnummern und Personenunterfuehrung
PRELL = 2960                    # Prellbock Gueter- und Abstellgleis


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
      f'Knoten mit fünf Zulaufrichtungen · Strecke 1 km 63,5 · Strecke 2 km 51,0</text>')

    # ---- Gleise ----
    # Streckengleise: Westkopf Krug (Gleis 1/2), Silberberg (Gleis 4/5),
    # Windingen (Gleis 7); Ostkopf Furth (Gleis 1/2), Neumark (Gleis 6).
    G = f'<g stroke="{c}" fill="none" stroke-width="3">'
    A(G + f'<line x1="{X0}" y1="{G1}" x2="{X1}" y2="{G1}"/>'
        + f'<line x1="{X0}" y1="{G2}" x2="{X1}" y2="{G2}"/>'
        + f'<line x1="590" y1="{G3}" x2="2760" y2="{G3}"/>'
        + f'<line x1="{X0}" y1="{G4}" x2="2630" y2="{G4}"/>'
        + f'<line x1="{X0}" y1="{G5}" x2="2500" y2="{G5}"/>'
        + f'<line x1="200" y1="{G6}" x2="{X1}" y2="{G6}"/>'
        + f'<line x1="{X0}" y1="{G7}" x2="{PRELL}" y2="{G7}"/></g>')
    A(prellbock(PRELL, G7, c))

    # ---- Weichen ----
    # An beiden Koepfen eine Gleisharfe, die jeweils benachbarte Gleise
    # verbindet. Dadurch ist jedes Bahnhofsgleis von jeder Richtung erreichbar.
    paare = []
    # Westkopf: von oben nach unten aufgefaechert
    west = [(G7, G6, 200), (G6, G5, 330), (G5, G4, 460), (G4, G3, 590),
            (G3, G2, 720), (G2, G1, 850)]
    for yo, yu, x in west:
        paare.append(((x, x + 42, x + 100, yo, KEIL),
                      (x + 270, x + 228, x + 170, yu, -KEIL)))
    # Ostkopf: spiegelbildlich, Zungen nach Osten
    ost = [(G7, G6, 2100), (G6, G5, 2230), (G5, G4, 2360), (G4, G3, 2490),
           (G3, G2, 2620), (G2, G1, 2750)]
    for yo, yu, x in ost:
        paare.append(((x + 270, x + 228, x + 170, yo, KEIL),
                      (x, x + 42, x + 100, yu, -KEIL)))

    nummern = sorted(wm for a_, b_ in paare for (_, wm, _, _, _) in
                     ([a_] + ([b_] if b_ else [])))
    assert len(nummern) == len(set(nummern)), \
        'zwei Weichen auf derselben Weichenmitte: Nummerierung waere nicht eindeutig'
    nr_von = {wm: i + 1 for i, wm in enumerate(nummern)}
    for a_, b_ in paare:
        wa, wm, we, y, dy = a_
        A(weiche(wa, wm, we, y, dy, nr_von[wm], c, soft))
        wa2, wm2, we2, y2, dy2 = b_
        A(weiche(wa2, wm2, we2, y2, dy2, nr_von[wm2], c, soft))
        A(verbindung(we, y + dy, we2, y2 + dy2, c))

    # ---- Bahnsteige und Empfangsgebaeude ----
    A(bahnsteig(G6 + 20, G5 - 20, 4, 'Bahnsteig 4 · Gleis 6 und 5', c, soft))
    A(bahnsteig(G4 + 20, G3 - 20, 3, 'Bahnsteig 3 · Gleis 4 und 3', c, soft))
    A(bahnsteig(G2 + 20, G1 - 20, 2, 'Bahnsteig 2 · Gleis 2 und 1', c, soft))
    A(bahnsteig(G1 + 24, G1 + 66, 1, 'Bahnsteig 1 (Hausbahnsteig) · Gleis 1', c, soft))
    A(f'<rect x="{MITTE-150}" y="{G1+100}" width="300" height="48" fill="none" stroke="{c}" stroke-width="2"/>')
    A(f'<text x="{MITTE}" y="{G1+130}" text-anchor="middle" font-size="12" fill="{c}">Empfangsgebäude</text>')
    A(f'<text x="{MITTE+165}" y="{G1+130}" font-size="10.5" fill="{soft}">Hauptzugang</text>')
    A(f'<line x1="{MITTE}" y1="{G7+22}" x2="{MITTE}" y2="{G1+68}" stroke="{soft}" '
      f'stroke-width="1.5" stroke-dasharray="3,4"/>')
    A(f'<text x="{MITTE+14}" y="{G7+40}" font-size="10.5" fill="{soft}">Personenunterführung</text>')

    # ---- Gleisnummern ----
    for y, n in ((G1, 1), (G2, 2), (G3, 3), (G4, 4), (G5, 5), (G6, 6), (G7, 7)):
        A(gleisnummer(MITTE, y, n, c, surface))

    # ---- Streckengleisbezeichnungen ----
    A(f'<g fill="{soft}" font-size="12">'
      f'<text x="46" y="{G1+22}">(1)</text><text x="46" y="{G2-10}">(2)</text>'
      f'<text x="46" y="{G4+22}">(1)</text><text x="46" y="{G5-10}">(2)</text>'
      f'<text x="46" y="{G7-10}">(1)</text>'
      f'<text x="{X1-6}" y="{G6-10}" text-anchor="end">(1)</text>'
      f'<text x="{X1-6}" y="{G1+22}" text-anchor="end">(1)</text>'
      f'<text x="{X1-6}" y="{G2-10}" text-anchor="end">(2)</text></g>')

    # ---- Signale ----
    # Einfahrsignale: A-E in Richtung der Kilometrierung (Westkopf), F-K
    # entgegen (Ostkopf). Doppelter Buchstabe fuer Einfahrten vom Gegengleis.
    A(signal(95,  G1, False, 'e', 'A',  c, zs3='6'))
    A(signal(145, G2, True,  'e', 'AA', c, zs3='6'))
    A(signal(95,  G4, False, 'e', 'B',  c, zs3='6'))
    A(signal(145, G5, True,  'e', 'BB', c, zs3='6'))
    A(signal(95,  G7, False, 'e', 'C',  c, zs3='4'))
    A(signal(X1 - 35, G2, True,  'w', 'F',  c, zs3='6'))
    A(signal(X1 - 90, G1, False, 'w', 'FF', c, zs3='6'))
    A(signal(X1 - 35, G6, True,  'w', 'G',  c, zs3='4'))
    # Ausfahrsignale: P + Gleisnummer entgegen der Kilometrierung (nach Westen),
    # N + Gleisnummer in Richtung der Kilometrierung (nach Osten). Zs 2
    # Richtungsanzeiger, weil die Ausfahrt mehrere Strecken erreichen kann:
    # K = Krug, S = Silberberg, W = Windingen, F = Furth, N = Neumark.
    for y, nr in ((G1, 1), (G2, 2), (G3, 3), (G4, 4), (G5, 5), (G6, 6), (G7, 7)):
        A(signal(P_X, y, y != G1, 'w', f'P{nr}', c,
                 zs3='6' if nr in (1, 2) else '4',
                 zs2=None if nr == 7 else 'K,S,W', zs6=(nr == 2)))
    for y, nr in ((G1, 1), (G2, 2), (G3, 3), (G4, 4), (G5, 5), (G6, 6), (G7, 7)):
        A(signal(N_X, y, y != G1, 'e', f'N{nr}', c,
                 zs3='6' if nr in (1, 2) else '4',
                 zs2=None if nr == 7 else 'F,N', zs6=(nr == 2)))
    # Zwischensignale teilen die Bahnsteiggleise in die Abschnitte a und b.
    # Erst dadurch koennen zwei Vierteiler hintereinander am Bahnsteig stehen.
    for y, nr in ((G1, 1), (G2, 2), (G5, 5)):
        A(signal(Z_X - 40, y, y != G1, 'w', f'ZU{nr}', c, zs3='4'))
        A(signal(Z_X + 40, y, y != G1, 'e', f'ZR{nr}', c, zs3='4'))

    # ---- Streckenangaben ----
    A(f'<g fill="{soft}" font-size="12" font-style="italic">'
      f'<text x="{X0}" y="{G1+190}">← Altensund · Hyxel (km 49,0) · Waldenberg · Krug (km 34,5) · Erx</text>'
      f'<text x="{X0}" y="{G1+208}">Strecke 1 · Hauptbahn · zweigleisig mit Gleiswechselbetrieb · Hg 120 km/h · elektrifiziert · Obersosa km 63,5</text>'
      f'<text x="{X0}" y="{G7-76}">← Hochstein (km 46,0) · Silberberg (km 24,5) · Bernstein · zweigleisig</text>'
      f'<text x="{X0}" y="{G7-58}">← Gbf · Windingen · eingleisig</text>'
      f'<text x="{X1}" y="{G1+190}" text-anchor="end">Kunststoffwerk · Rotheim · Feldheim (km 75,5) · Lossow · Furth (km 117,5) →</text>'
      f'<text x="{X1}" y="{G1+208}" text-anchor="end">Strecke 1 · Angaben wie links</text>'
      f'<text x="{X1}" y="{G7-58}" text-anchor="end">Kirchheim Hbf · Neumark · eingleisig →</text></g>')
    return "\n".join(s)


LAGEPLAN = build("currentColor", "var(--ink-soft)", "var(--surface)")
ZEICHNUNG = build("#000000", "#333333", "#ffffff")
