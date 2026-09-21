"""Erzeugt die Uebersichtsdarstellung Gleisband fuer Los 5.

Der Bewertungsbogen "Praesentation Gleisband LF 2" verlangt unter
Vollstaendigkeit a) eine Uebersichtsdarstellung des Gleisbandes der Aus- und
Neubaustrecken. Dieses Blatt zeigt die drei Strecken des Loses je fuer sich
massstaeblich kilometriert, mit Betriebsstellenart und der Unterscheidung
zwischen selbst geplanten und ausgenommenen Betriebsstellen.

Alle Kilometerwerte stammen aus der Aufgabenstellung bzw. aus den
Fahrplandaten des Projekts. Es werden keine Werte geschaetzt.
"""
import pathlib

REPO = str(pathlib.Path(__file__).resolve().parent.parent) + "/"

# (Name, km, Art)  Art: bf = Betriebsstelle mit eigenem Lageplan, bst = sonstige
# Betriebsstelle im Los, hp = Haltepunkt, anst = Anschlussstelle,
# ausgen = nicht Teil von Los 5.
# Kilometer nach Aufgabenstellung, Zwischenbetriebsstellen nach den
# Fahrplandaten des Projekts.
STRECKE_1 = [("Krug", 34.5, "ausgen"), ("Zollfurt", 35.5, "hp"),
             ("Waldenberg", 36.5, "bf"), ("Burgwald", 40.0, "hp"),
             ("Steinbruch", 42.0, "anst"), ("Langenbach", 45.0, "hp"),
             ("Hyxel", 49.0, "bf"), ("Lindenau", 58.0, "hp"),
             ("Großraffinerie", 60.0, "anst"), ("Altensund", 62.0, "hp"),
             ("Obersosa", 63.5, "bf"), ("Kunststoffwerk", 65.5, "anst"),
             ("Rotheim", 68.0, "hp"), ("Feldheim", 75.5, "bst"),
             ("Unterfels", 81.5, "hp"), ("Lossow", 88.0, "bst"),
             ("Furth", 117.5, "ausgen")]
STRECKE_2 = [("Bernstein", 0.0, "ausgen"), ("Silberberg", 24.5, "bf"),
             ("Chemiewerk I", 30.0, "anst"), ("Feldkirchen", 31.0, "hp"),
             ("Finsterberg", 40.0, "hp"), ("Chemiewerk II", 41.0, "anst"),
             ("Hochstein", 46.0, "hp"), ("Obersosa", 51.0, "bf")]
STRECKE_3 = [("Waldenberg", 0.0, "bf"), ("Wehrheim", 7.0, "bf"),
             ("Sandheide", 14.5, "bf"), ("Getreidesilo", 18.0, "anst"),
             ("Wassergrund", 19.0, "bf"), ("Gbf", 29.5, "ausgen")]

W, X0, X1 = 2720, 400, 2670
ROT, TIEF, STAHL, GRAU, SOFT = "#C8102E", "#16202E", "#4A6FA5", "#98A4B4", "#5C6879"
FARBE = {"bf": ROT, "bst": TIEF, "hp": TIEF, "anst": STAHL, "ausgen": GRAU}
# Beschriftungsspuren: drei ueber, drei unter dem Gleisband
SPUREN = [(-26, -41), (-64, -79), (-102, -117),
          (34, 49), (72, 87), (110, 125)]


def km_text(km):
    return ("%.1f" % km).replace(".", ",")


def band(y, nummer, strecke, angabe, stationen, kmin, kmax, linienfarbe):
    o = [f'<text x="40" y="{y-6}" font-size="21" font-weight="700" fill="{TIEF}">{nummer}</text>',
         f'<line x1="{X0}" y1="{y}" x2="{X1}" y2="{y}" stroke="{linienfarbe}" stroke-width="4"/>',
         f'<text x="40" y="{y+18}" font-size="12.5" fill="{SOFT}">{strecke}</text>',
         f'<text x="40" y="{y+36}" font-size="12.5" fill="{SOFT}">{angabe}</text>']
    belegt = [-1e9] * len(SPUREN)
    for name, km, art in stationen:
        x = X0 + (X1 - X0) * (km - kmin) / (kmax - kmin)
        breite = max(len(name) * 8.2, 54) + 14
        spur = 0
        for i in range(len(SPUREN)):
            if x - belegt[i] >= breite:
                spur = i
                break
        belegt[spur] = x
        dy_name, dy_km = SPUREN[spur]
        c = FARBE[art]
        if art == "bf":
            o.append(f'<circle cx="{x:.1f}" cy="{y}" r="9" fill="#fff" stroke="{c}" stroke-width="4"/>')
        elif art == "anst":
            o.append(f'<rect x="{x-6:.1f}" y="{y-6}" width="12" height="12" fill="{c}"/>')
        elif art in ("bst", "hp"):
            o.append(f'<line x1="{x:.1f}" y1="{y-10}" x2="{x:.1f}" y2="{y+10}" stroke="{c}" stroke-width="4"/>')
        else:
            o.append(f'<circle cx="{x:.1f}" cy="{y}" r="8" fill="#fff" stroke="{c}" '
                     f'stroke-width="3" stroke-dasharray="3,3"/>')
        if abs(dy_name) > 36:          # zweite und dritte Spur brauchen eine Fuehrungslinie
            y1 = y + (14 if dy_name > 0 else -14)
            y2 = y + (dy_name - 11 if dy_name > 0 else dy_name + 5)
            o.append(f'<line x1="{x:.1f}" y1="{y1}" x2="{x:.1f}" y2="{y2}" stroke="#C9D2DE" stroke-width="1.5"/>')
        fett = "700" if art in ("bf", "bst") else "400"
        farbe_txt = TIEF if art != "ausgen" else GRAU
        o.append(f'<text x="{x:.1f}" y="{y+dy_name}" font-size="15" font-weight="{fett}" '
                 f'fill="{farbe_txt}" text-anchor="middle">{name}</text>')
        o.append(f'<text x="{x:.1f}" y="{y+dy_km}" font-size="11" fill="{SOFT}" text-anchor="middle" '
                 f'font-family="Courier New, monospace">{km_text(km)}</text>')
    return "\n".join(o)


def legende(y):
    eintraege = [("bf", "Betriebsstelle mit eigenem Lageplan"), ("bst", "weitere Betriebsstelle im Los"),
                 ("hp", "Haltepunkt"), ("anst", "Anschlussstelle"),
                 ("ausgen", "ausgenommen, nicht Teil von Los 5")]
    o = [f'<text x="40" y="{y}" font-size="13.5" font-weight="700" fill="{TIEF}">Zeichenerklärung</text>']
    x = 40
    for art, text in eintraege:
        c, cy = FARBE[art], y + 28
        if art == "bf":
            o.append(f'<circle cx="{x+8}" cy="{cy}" r="9" fill="#fff" stroke="{c}" stroke-width="4"/>')
        elif art in ("bst", "hp"):
            o.append(f'<line x1="{x+8}" y1="{cy-10}" x2="{x+8}" y2="{cy+10}" stroke="{c}" stroke-width="4"/>')
        elif art == "anst":
            o.append(f'<rect x="{x+2}" y="{cy-6}" width="12" height="12" fill="{c}"/>')
        else:
            o.append(f'<circle cx="{x+8}" cy="{cy}" r="8" fill="#fff" stroke="{c}" '
                     f'stroke-width="3" stroke-dasharray="3,3"/>')
        o.append(f'<text x="{x+26}" y="{cy+5}" font-size="13" fill="{SOFT}">{text}</text>')
        x += 26 + len(text) * 6.6 + 40
    o.append(f'<text x="{X1}" y="{y+33}" font-size="12.5" fill="{SOFT}" font-style="italic" '
             f'text-anchor="end">Kilometrierung je Strecke maßstäblich · Zahlen über den Betriebsstellen sind Streckenkilometer</text>')
    return "\n".join(o)


def build():
    s1_west = [z for z in STRECKE_1 if z[1] <= 63.5]
    s1_ost = [z for z in STRECKE_1 if z[1] >= 63.5]
    teile = [
        band(280, "Strecke 1 · West", "Krug (ausgen.) – Waldenberg – Hyxel – Obersosa",
             "Hauptbahn · zweigleisig · 120 km/h · elektrifiziert", s1_west, 34.5, 63.5, TIEF),
        band(570, "Strecke 1 · Ost", "Obersosa – Feldheim – Lossow – Furth (ausgen.)",
             "Hauptbahn · zweigleisig · 120 km/h · elektrifiziert", s1_ost, 63.5, 117.5, TIEF),
        band(860, "Strecke 2", "Bernstein (ausgen.) – Silberberg – Obersosa",
             "Hauptbahn · zweigleisig · 120 km/h · elektrifiziert", STRECKE_2, 0.0, 51.0, TIEF),
        band(1150, "Strecke 3", "Waldenberg – Gbf (ausgen.)",
             "Nebenbahn · eingleisig · 80 km/h · elektrifiziert", STRECKE_3, 0.0, 29.5, STAHL),
        legende(1330),
    ]
    return (f'<svg id="gleisband" width="{W}" height="1410" viewBox="0 0 {W} 1410" '
            f'xmlns="http://www.w3.org/2000/svg" font-family="Calibri, Arial, sans-serif">'
            f'<rect width="{W}" height="1410" fill="#fff"/>{"".join(teile)}</svg>')


# ---------------------------------------------------------------------------
# Einzelblätter im Folienformat
#
# Auf einer Folie bestimmt die Schriftgröße im Verhältnis zur Bildbreite die
# Lesbarkeit. Im Übersichtsblatt sind die Namen 15 px bei 2720 px Breite, also
# ein halbes Prozent - auf einer 13-Zoll-Folie rund 5 pt. Für etwa 14 pt müssen
# die Namen rund 1,6 Prozent der Bildbreite hoch sein. Deshalb bekommt jeder
# Streckenabschnitt ein eigenes Blatt mit deutlich größerer Schrift.

EB_W, EB_H = 1900, 540
EB_X0, EB_X1 = 120, 1810
EB_Y = 300
EB_SPUREN = [(-42, -68), (-100, -126), (56, 82), (114, 140)]


def einzelband(stationen, kmin, kmax, linienfarbe):
    o = [f'<line x1="{EB_X0}" y1="{EB_Y}" x2="{EB_X1}" y2="{EB_Y}" '
         f'stroke="{linienfarbe}" stroke-width="6"/>']
    belegt = [-1e9] * len(EB_SPUREN)
    for name, km, art in stationen:
        x = EB_X0 + (EB_X1 - EB_X0) * (km - kmin) / (kmax - kmin)
        breite = max(len(name) * 14.5, 96) + 24
        spur = 0
        for i in range(len(EB_SPUREN)):
            if x - belegt[i] >= breite:
                spur = i
                break
        belegt[spur] = x
        dy_name, dy_km = EB_SPUREN[spur]
        c = FARBE[art]
        if art == "bf":
            o.append(f'<circle cx="{x:.1f}" cy="{EB_Y}" r="16" fill="#fff" stroke="{c}" stroke-width="7"/>')
        elif art == "anst":
            o.append(f'<rect x="{x-11:.1f}" y="{EB_Y-11}" width="22" height="22" fill="{c}"/>')
        elif art in ("bst", "hp"):
            w = 7 if art == "bst" else 5
            o.append(f'<line x1="{x:.1f}" y1="{EB_Y-18}" x2="{x:.1f}" y2="{EB_Y+18}" '
                     f'stroke="{c}" stroke-width="{w}"/>')
        else:
            o.append(f'<circle cx="{x:.1f}" cy="{EB_Y}" r="14" fill="#fff" stroke="{c}" '
                     f'stroke-width="5" stroke-dasharray="5,5"/>')
        if abs(dy_name) > 60:
            y1 = EB_Y + (24 if dy_name > 0 else -24)
            y2 = EB_Y + (dy_name - 20 if dy_name > 0 else dy_name + 10)
            o.append(f'<line x1="{x:.1f}" y1="{y1}" x2="{x:.1f}" y2="{y2}" stroke="#C9D2DE" stroke-width="2.5"/>')
        fett = "700" if art in ("bf", "bst") else "400"
        farbe_txt = TIEF if art != "ausgen" else GRAU
        o.append(f'<text x="{x:.1f}" y="{EB_Y+dy_name}" font-size="27" font-weight="{fett}" '
                 f'fill="{farbe_txt}" text-anchor="middle">{name}</text>')
        o.append(f'<text x="{x:.1f}" y="{EB_Y+dy_km}" font-size="20" fill="{SOFT}" '
                 f'text-anchor="middle" font-family="Courier New, monospace">km {km_text(km)}</text>')
    return "\n".join(o)


def einzelblatt(kennung, nummer, strecke, angabe, stationen, kmin, kmax, linienfarbe):
    leg = [("bf", "eigener Lageplan"), ("bst", "Betriebsstelle"),
           ("hp", "Haltepunkt"), ("anst", "Anschlussstelle"), ("ausgen", "ausgenommen")]
    o = [f'<text x="{EB_X0}" y="58" font-size="34" font-weight="700" fill="{TIEF}">{nummer}</text>',
         f'<text x="{EB_X0}" y="90" font-size="20" fill="{SOFT}">{strecke}</text>',
         f'<text x="{EB_X0}" y="116" font-size="18" fill="{SOFT}">{angabe}</text>',
         einzelband(stationen, kmin, kmax, linienfarbe)]
    x = EB_X0
    for art, text in leg:
        c, cy = FARBE[art], EB_H - 30
        if art == "bf":
            o.append(f'<circle cx="{x+10}" cy="{cy-5}" r="11" fill="#fff" stroke="{c}" stroke-width="5"/>')
        elif art == "anst":
            o.append(f'<rect x="{x+2}" y="{cy-13}" width="16" height="16" fill="{c}"/>')
        elif art in ("bst", "hp"):
            w = 6 if art == "bst" else 4
            o.append(f'<line x1="{x+10}" y1="{cy-17}" x2="{x+10}" y2="{cy+7}" stroke="{c}" stroke-width="{w}"/>')
        else:
            o.append(f'<circle cx="{x+10}" cy="{cy-5}" r="10" fill="#fff" stroke="{c}" '
                     f'stroke-width="4" stroke-dasharray="4,4"/>')
        o.append(f'<text x="{x+30}" y="{cy+2}" font-size="19" fill="{SOFT}">{text}</text>')
        x += 30 + len(text) * 10.2 + 46
    o.append(f'<text x="{EB_X1}" y="{EB_H-28}" font-size="18" fill="{SOFT}" font-style="italic" '
             f'text-anchor="end">maßstäblich</text>')
    return (f'<svg id="{kennung}" width="{EB_W}" height="{EB_H}" viewBox="0 0 {EB_W} {EB_H}" '
            f'xmlns="http://www.w3.org/2000/svg" font-family="Calibri, Arial, sans-serif">'
            f'<rect width="{EB_W}" height="{EB_H}" fill="#fff"/>{"".join(o)}</svg>')


def einzelblaetter():
    s1w = [z for z in STRECKE_1 if z[1] <= 63.5]
    s1o = [z for z in STRECKE_1 if z[1] >= 63.5]
    return [
        einzelblatt("eb-s1-west", "Strecke 1 · West", "Krug (ausgen.) – Waldenberg – Hyxel – Obersosa",
                    "Hauptbahn · zweigleisig · 120 km/h · elektrifiziert", s1w, 34.5, 63.5, TIEF),
        einzelblatt("eb-s1-ost", "Strecke 1 · Ost", "Obersosa – Feldheim – Lossow – Furth (ausgen.)",
                    "Hauptbahn · zweigleisig · 120 km/h · elektrifiziert", s1o, 63.5, 117.5, TIEF),
        einzelblatt("eb-s2", "Strecke 2", "Bernstein (ausgen.) – Silberberg – Obersosa",
                    "Hauptbahn · zweigleisig · 120 km/h · elektrifiziert", STRECKE_2, 0.0, 51.0, TIEF),
        einzelblatt("eb-s3", "Strecke 3", "Waldenberg – Gbf (ausgen.)",
                    "Nebenbahn · eingleisig · 80 km/h · elektrifiziert", STRECKE_3, 0.0, 29.5, STAHL),
    ]


SEITE = """<!DOCTYPE html>
<html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Gleisband Los 5 – Chemiezentrum</title>
<style>
  body {{ margin:0; background:#fff; color:#16202E;
         font-family:'IBM Plex Sans',Calibri,Arial,sans-serif; }}
  .wrap {{ max-width:1280px; margin:0 auto; padding:32px 20px 48px; }}
  h1 {{ font-size:26px; margin:0 0 4px; }}
  .sub {{ color:#5C6879; font-size:14px; margin:0 0 24px; }}
  .scroll {{ overflow-x:auto; }}
  svg {{ width:100%; height:auto; min-width:1500px; }}
  footer {{ margin-top:28px; color:#5C6879; font-size:12.5px; }}
</style></head><body><div class="wrap">
<h1>Gleisband Los 5 – Chemiezentrum</h1>
<p class="sub">Übersichtsdarstellung der drei Strecken mit Kilometrierung · Strecke 1 in zwei Abschnitten ·
LF 2 Jahresprojekt 2026 „Mitteltrasse", 5. Teilabschnitt</p>
<div class="scroll">{svg}</div>
<h2 style="font-size:19px;margin:36px 0 6px">Einzelblätter für die Präsentation</h2>
<p class="sub" style="margin-bottom:16px">Je ein Abschnitt pro Blatt, Schrift für die Projektion vergrößert.</p>
{einzel}
<footer>Kilometerangaben nach Aufgabenstellung; Zwischenbetriebsstellen nach den
Fahrplandaten des Projekts.</footer>
</div></body></html>
"""

if __name__ == "__main__":
    with open(REPO + "gleisband-los5.html", "w", encoding="utf-8") as f:
        f.write(SEITE.format(svg=build(),
                             einzel="\n".join(f'<div class="scroll" style="margin-bottom:26px">{b}</div>'
                                               for b in einzelblaetter())))
    print("geschrieben")
