"""Erzeugt lageplan-waldenberg.html und zeichnung-waldenberg.html neu.

Aufruf aus dem Repo-Wurzelverzeichnis:  python3 tools/build_waldenberg.py
Die Gleisgeometrie steht in tools/waldenberg.py, hier nur der Seitenrahmen,
die Tabellen und die Begleittexte.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import waldenberg as w

REPO = str(pathlib.Path(__file__).resolve().parent.parent) + "/"

ARIA = ("Sicherungstechnischer Lageplan des Abzweigbahnhofs Waldenberg. Die zweigleisige "
        "Hauptbahn (Strecke 1, Krug–Furth, km 37,5) läuft mit Gleis 1 und Gleis 2 durchgehend "
        "gerade durch die Betriebsstelle. Gleis 3 ist Bahnsteiggleis der eingleisigen Nebenbahn "
        "und geht östlich in die Strecke 3 nach Wehrheim–Sandheide–Gbf über, deren Kilometrierung "
        "hier bei km 0,0 beginnt. Gleis 4 liegt als Lade- und Ausweichgleis nördlich davon und ist "
        "über die Weichen 4 und 5 an beiden Enden an Gleis 3 angebunden. Am Westkopf verbinden die "
        "Weichen 1 und 2 als Überleitverbinder Gleis 1 und Gleis 2, Weiche 3 führt von Gleis 2 auf "
        "Gleis 3. Am Ostkopf verbinden die Weichen 6 und 7 Gleis 2 mit der Nebenbahn, die Weichen 8 "
        "und 9 bilden einen zweiten Überleitverbinder zwischen Gleis 1 und Gleis 2. Bahnsteig 1 ist "
        "Hausbahnsteig an Gleis 1 am Empfangsgebäude, Bahnsteig 2 Mittelbahnsteig zwischen Gleis 2 "
        "und Gleis 3, verbunden über eine Personenunterführung. Einfahrsignale A und AA von "
        "Zollfurt, F und FF von Burgwald sowie G von Wehrheim; Ausfahrsignale N1, N2, N3, N4, P2 "
        "und P3 sowie Zwischensignal ZU4; N1 und P2 mit Gegengleisanzeiger für die "
        "Weiterfahrt auf dem Streckengleis der Gegenrichtung.")

LAGEPLAN = """<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Lageplan Waldenberg – Mitteltrasse Los 5</title>
</head>
<body>
<style>
  :root {
    --bg: #f5f3ed; --surface: #ffffff; --ink: #191b18; --ink-soft: #55594f;
    --line: #d9d5c7; --accent: #a8201a; --accent-soft: #f2dad8; --accent-ink: #741512;
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --bg: #141613; --surface: #1c1f1b; --ink: #edece7; --ink-soft: #a2a699;
      --line: #32352e; --accent: #e0574d; --accent-soft: #38221f; --accent-ink: #f3a49e;
    }
  }
  :root[data-theme="dark"] {
    --bg: #141613; --surface: #1c1f1b; --ink: #edece7; --ink-soft: #a2a699;
    --line: #32352e; --accent: #e0574d; --accent-soft: #38221f; --accent-ink: #f3a49e;
  }
  * { box-sizing: border-box; }
  body {
    background: var(--bg); color: var(--ink);
    font-family: "IBM Plex Sans", -apple-system, Segoe UI, sans-serif;
    margin: 0; padding-inline: 20px; padding-block: 28px 56px; line-height: 1.5;
  }
  .wrap { max-width: 1340px; margin: 0 auto; }
  .kicker {
    font-family: "IBM Plex Mono", ui-monospace, monospace; font-size: 11.5px;
    letter-spacing: 0.08em; text-transform: uppercase; color: var(--accent-ink);
    background: var(--accent-soft); display: inline-block; padding: 3px 9px;
    border-radius: 3px; margin-bottom: 12px;
  }
  h1 { font-size: clamp(26px, 4vw, 36px); margin: 0 0 6px; letter-spacing: -0.01em; }
  .sub { color: var(--ink-soft); font-size: 15px; max-width: 78ch; margin: 0 0 26px; }
  .panel { background: var(--surface); border: 1px solid var(--line); border-radius: 10px; padding: 20px; margin-bottom: 20px; }
  .diagram-scroll { overflow-x: auto; }
  svg.plan { width: 100%; height: auto; min-width: 1200px; display: block; }
  svg.plan text { font-family: "IBM Plex Mono", ui-monospace, monospace; }
  h2 { font-size: 19px; margin: 0 0 4px; }
  h3 { font-size: 13.5px; margin: 0 0 8px; }
  .panel-note { color: var(--ink-soft); font-size: 13.5px; margin: 0 0 16px; max-width: 80ch; }
  .rules {
    font-family: "IBM Plex Mono", ui-monospace, monospace; font-size: 11.5px;
    color: var(--ink-soft); border-top: 1px solid var(--line); margin-top: 14px; padding-top: 12px;
  }
  .rules span { display: block; }
  table { width: 100%; border-collapse: collapse; font-size: 13.5px; }
  thead th {
    text-align: left; font-family: "IBM Plex Mono", ui-monospace, monospace; font-size: 10.5px;
    letter-spacing: 0.06em; text-transform: uppercase; color: var(--ink-soft);
    padding: 0 10px 8px; border-bottom: 1px solid var(--line);
  }
  tbody td { padding: 9px 10px; border-bottom: 1px solid var(--line); vertical-align: top; }
  tbody tr:last-child td { border-bottom: none; }
  td.mono { font-family: "IBM Plex Mono", ui-monospace, monospace; color: var(--accent-ink); font-weight: 600; white-space: nowrap; }
  .table-scroll { overflow-x: auto; }
  .two-col { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
  @media (max-width: 720px) { .two-col { grid-template-columns: 1fr; } }
  .legend { display: flex; flex-wrap: wrap; gap: 20px; font-size: 13px; color: var(--ink-soft); }
  .legend-item { display: flex; align-items: center; gap: 8px; }
  .caveat {
    background: var(--accent-soft); border: 1px solid color-mix(in srgb, var(--accent) 30%, var(--line));
    border-radius: 8px; padding: 12px 14px; font-size: 13px; color: var(--ink); margin-top: 14px;
  }
  .caveat strong { color: var(--accent-ink); }
  footer.foot { margin-top: 26px; font-size: 12px; color: var(--ink-soft); text-align: center; }
</style>

<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500;600&display=swap">

<div class="wrap">
  <span class="kicker">Los 5 · Sicherungstechnischer Lageplan · Ril 819.9001 / 819.9002</span>
  <h1>Lageplan Waldenberg</h1>
  <p class="sub">
    Waldenberg ist <strong>Abzweigbahnhof</strong> zweier Strecken: Die zweigleisige Hauptbahn
    <strong>Strecke 1</strong> (Krug–Furth) durchläuft die Betriebsstelle bei km 37,5 mit den
    durchgehenden Hauptgleisen 1 und 2. Die eingleisige <strong>Strecke 3</strong> nach
    Wehrheim – Sandheide – Gbf beginnt hier bei <strong>km 0,0</strong>; ihr Bahnsteiggleis ist
    Gleis 3, das östlich des Bahnsteigs in die Nebenbahn übergeht. Weil Gleis 2 über die
    Weichen 6 und 7 eine <strong>eigene Anbindung an die Nebenbahn</strong> hat, kann ein Zug
    aus Gleis 2 auf die Nebenbahn ausfahren, während in Gleis 3 ein anderer wendet. Nördlich davon liegt
    <strong>Gleis 4</strong> als Lade- und Ausweichgleis; es ist über die Weichen 4 und 5 an
    beiden Enden an Gleis 3 angebunden und dient unter anderem der Bereitstellung des
    Übergabezuges Üg 1. Beide Hauptgleise bleiben
    durchgehend gerade, damit IC 11/13/15, RE 70/71 und die Güterzüge mit 120 km/h ohne
    abzweigend zu befahrende Weiche durchfahren können.
  </p>

  <section class="panel">
    <h2>Gleistopologie</h2>
    <p class="panel-note">
      Symbole nach Ril 819.9002: Weichenanfang und Weichenmitte je als senkrechter Strich,
      dazwischen das Stammgleis ungeteilt; ab der Weichenmitte die Schwärzung (ferngestellte
      Weiche) zum Zweiggleis, dahinter das Grenzzeichen. Die Weichennummer steht an der
      Weichenmitte auf der Seite des Zweiggleises. Hauptsignale sind
      <strong>Ks-Mehrabschnittssignale</strong> (Hp 0, Ks 1, Ks 2), in Fahrtrichtung
      abgeklappt, Schirm ausgefüllt = wärterbedient. Gleisnummern stehen in der
      unterbrochenen Gleislinie, Streckengleisbezeichnungen in Klammern.
    </p>

    <div class="diagram-scroll">
      <svg class="plan" viewBox="0 0 1920 560" role="img" aria-label="__ARIA__">
        __PLAN__
      </svg>
    </div>

    <div class="rules">
      <span>Sämtliche fernbediente Weichen mit Zungenprüfern.</span>
      <span>Gleisnummern sind einstellig.</span>
      <span>Gleis 1 liegt südlich: bei Rechtsverkehr ist das Regelgleis in Richtung der Kilometrierung das in Fahrtrichtung rechte. Die Nummerierung zählt zugleich vom Hauptzugang aufsteigend.</span>
      <span>Alle Weichen EW 1:9, Abzweiggeschwindigkeit 40 km/h.</span>
      <span>Hauptgleise 1 und 2 durchgehend gerade, Streckengeschwindigkeit 120 km/h.</span>
      <span>Strecke 3 (Nebenbahn) beginnt in Waldenberg bei km 0,0, eingleisig, 80 km/h.</span>
      <span>Regel- und Gegengleis sind Eigenschaften der freien Strecke; im Bahnhof gibt es nur Bahnhofsgleise.</span>
      <span>Gegengleisanzeiger an P2 und N1: der Zug fährt nach der Ausfahrt auf dem Streckengleis der Gegenrichtung weiter.</span>
      <span>AA und FF decken Einfahrten von Zügen, die auf der freien Strecke bereits auf dem Gegengleis ankommen.</span>
      <span>Gleis 3 und die Anbindung Gleis 2 → Nebenbahn (Weichen 6/7) sind voneinander unabhängig befahrbar.</span>
      <span>Gleis 4 ist Lade- und Ausweichgleis ohne Bahnsteig, an beiden Enden an Gleis 3 angebunden.</span>
    </div>
  </section>

  <section class="panel">
    <h2>Betriebsprogramm</h2>
    <p class="panel-note">
      Aus dem Fahrplan ergeben sich drei Verkehrsfälle, die das Layout bestimmen.
    </p>
    <div class="table-scroll">
      <table>
        <thead><tr><th>Zug</th><th>Weg durch Waldenberg</th><th>Gleis</th></tr></thead>
        <tbody>
          <tr><td class="mono">IC 11/13/15<br>RE 70/71<br>GZ 2/3/4</td><td>Durchfahrt Hauptbahn ohne Halt, gerade über beide Hauptgleise</td><td class="mono">1 / 2</td></tr>
          <tr><td class="mono">RE 71 · RB 61<br>RB 65</td><td>Halt an der Hauptbahn: Richtung Osten an Bahnsteig 1, Richtung Westen an Bahnsteig 2</td><td class="mono">1 / 2</td></tr>
          <tr><td class="mono">RB 64</td><td><strong>Wendet in Waldenberg.</strong> Einfahrt von Wehrheim über Signal G, Halt an Bahnsteig 2, Ausfahrt über N3 zurück zur Nebenbahn – ohne die Hauptgleise zu berühren</td><td class="mono">3</td></tr>
          <tr><td class="mono">RB 66</td><td><strong>Übergang Hauptbahn → Nebenbahn.</strong> Einfahrt von Krug über A, Überleitverbinder Weichen 1/2 auf Gleis 2, Halt an Bahnsteig 2, Ausfahrt über N2 (Zs 3) und die Weichen 6/7 auf die Nebenbahn – <strong>Gleis 3 bleibt dabei frei</strong></td><td class="mono">1 → 2</td></tr>
          <tr><td class="mono">Üg 1</td><td>Beginnt und endet in Waldenberg, bereitgestellt in <strong>Gleis 4</strong>. Ausfahrt über N4 und Weiche 5 auf Gleis 3 – die Fahrt berührt den Bahnsteigabschnitt von Gleis 3 nicht, die RB 64 kann dort gleichzeitig wenden</td><td class="mono">4</td></tr>
        </tbody>
      </table>
    </div>
  </section>

  <section class="panel">
    <div class="two-col">
      <div>
        <h3>Weichenverzeichnis</h3>
        <div class="table-scroll">
          <table>
            <thead><tr><th>Lageplan</th><th>Tabelle</th><th>Verbindung</th></tr></thead>
            <tbody>
              <tr><td class="mono">1</td><td class="mono">31W1</td><td>Gleis 1 → Verbindungsgleis (Westkopf, Überleitverbinder)</td></tr>
              <tr><td class="mono">2</td><td class="mono">31W2</td><td>Verbindungsgleis → Gleis 2 (Westkopf, Überleitverbinder)</td></tr>
              <tr><td class="mono">3</td><td class="mono">31W3</td><td>Gleis 2 → Gleis 3 (Westanbindung des Nebenbahngleises)</td></tr>
              <tr><td class="mono">4</td><td class="mono">31W4</td><td>Gleis 3 → Gleis 4 (Westanbindung des Lade- und Ausweichgleises)</td></tr>
              <tr><td class="mono">5</td><td class="mono">31W5</td><td>Gleis 3 → Gleis 4 (Ostanbindung, östlich des Bahnsteigs)</td></tr>
              <tr><td class="mono">6</td><td class="mono">31W6</td><td>Gleis 2 → Verbindungsgleis zur Nebenbahn (Ostkopf)</td></tr>
              <tr><td class="mono">7</td><td class="mono">31W7</td><td>Verbindungsgleis → Gleis 3 / Nebenbahn (Ostkopf)</td></tr>
              <tr><td class="mono">8</td><td class="mono">31W8</td><td>Gleis 1 → Verbindungsgleis (Ostkopf, Überleitverbinder)</td></tr>
              <tr><td class="mono">9</td><td class="mono">31W9</td><td>Verbindungsgleis → Gleis 2 (Ostkopf, Überleitverbinder)</td></tr>
            </tbody>
          </table>
        </div>
      </div>
      <div>
        <h3>Signalverzeichnis</h3>
        <div class="table-scroll">
          <table>
            <thead><tr><th>Lageplan</th><th>Tabelle</th><th>Funktion</th></tr></thead>
            <tbody>
              <tr><td class="mono">A</td><td class="mono">31A</td><td>Einfahrsignal Gleis 1, von Zollfurt/Krug · mit <strong>Zs 3 (4)</strong> für die Einfahrt nach Gleis 3 über die Weichen 1/2/3</td></tr>
              <tr><td class="mono">AA</td><td class="mono">31AA</td><td>Einfahrsignal für Züge, die von Zollfurt/Krug auf dem <strong>Gegengleis der freien Strecke</strong> – Streckengleis (2) – ankommen; Einfahrt in Gleis 2</td></tr>
              <tr><td class="mono">F</td><td class="mono">31F</td><td>Einfahrsignal Gleis 2, von Burgwald/Hyxel</td></tr>
              <tr><td class="mono">FF</td><td class="mono">31FF</td><td>Einfahrsignal für Züge, die von Burgwald/Hyxel auf dem <strong>Gegengleis der freien Strecke</strong> – Streckengleis (1) – ankommen; Einfahrt in Gleis 1</td></tr>
              <tr><td class="mono">G</td><td class="mono">31G</td><td>Einfahrsignal Nebenbahn, von Wehrheim (Strecke 3) · mit <strong>Zs 3 (4)</strong> für die Einfahrt nach Gleis 4 oder über Weiche 7 nach Gleis 2</td></tr>
              <tr><td class="mono">N1</td><td class="mono">31N1</td><td>Ausfahrsignal Gleis 1, Richtung Burgwald/Hyxel · am Ostende von Bahnsteig 1 · mit <strong>Gegengleisanzeiger</strong> und <strong>Zs 3 (4)</strong> für die Ausfahrt über die Weichen 8/9 und die Weiterfahrt auf Streckengleis (2), dem Gegengleis dieser Fahrtrichtung</td></tr>
              <tr><td class="mono">N2</td><td class="mono">31N2</td><td>Ausfahrsignal Gleis 2, Richtung Nebenbahn · am Ostende von Bahnsteig 2 · mit <strong>Zs 3 (4)</strong> für die Fahrt über die Weichen 6/7</td></tr>
              <tr><td class="mono">N3</td><td class="mono">31N3</td><td>Ausfahrsignal Gleis 3, Richtung Wehrheim · am Ostende von Bahnsteig 2</td></tr>
              <tr><td class="mono">N4</td><td class="mono">31N4</td><td>Ausfahrsignal Gleis 4, Richtung Wehrheim · mit <strong>Zs 3 (4)</strong> für die Fahrt über Weiche 5 auf Gleis 3</td></tr>
              <tr><td class="mono">ZU4</td><td class="mono">31ZU4</td><td>Zwischensignal Gleis 4, Richtung Westen · für die Ausfahrt aus Gleis 4 über Weiche 4 auf Gleis 3 · mit <strong>Zs 3 (4)</strong></td></tr>
              <tr><td class="mono">P2</td><td class="mono">31P2</td><td>Ausfahrsignal Gleis 2, Richtung Zollfurt/Krug · am Westende von Bahnsteig 2 · mit <strong>Gegengleisanzeiger</strong> und <strong>Zs 3 (4)</strong> für die Ausfahrt über die Weichen 2/1 und die Weiterfahrt auf Streckengleis (1), dem Gegengleis dieser Fahrtrichtung</td></tr>
              <tr><td class="mono">P3</td><td class="mono">31P3</td><td>Ausfahrsignal Gleis 3, Richtung Zollfurt/Krug über die Weichen 3/2 · mit <strong>Zs 3 (4)</strong></td></tr>
              <tr><td class="mono">—</td><td class="mono">—</td><td>Gesonderte Vorsignale entfallen: Vorsignalisierung über den Ks-2-Begriff der Mehrabschnittssignale</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <div class="caveat">
      <strong>Signalstandorte:</strong> Die Einfahrsignale A, F und G stehen an der jeweiligen
      Bahnhofsgrenze vor der ersten Einfahrweiche. Die Ausfahrsignale N1, N2, N3, N4, P2 und P3 stehen
      am Ende des jeweiligen Bahnhofsgleises unmittelbar hinter dem Bahnsteig; die Ausfahrstraße
      läuft von dort über alle Bahnhofsweichen. Einen Zs 3 tragen nur die Signale, deren
      Fahrstraße abzweigend über eine Weiche führt: A (Einfahrt nach Gleis 3), P3 (Ausfahrt über
      die Weichen 3/2) sowie P2 und N1 für die Fahrt über den jeweiligen Überleitverbinder.
      P2 und N1 tragen zusätzlich den <strong>Gegengleisanzeiger</strong>, weil der Zug dabei auf
      das Streckengleis der Gegenrichtung übergeht. Regel- und Gegengleis beschreiben immer
      nur die freie Strecke – innerhalb des Bahnhofs gibt es weder das eine noch das andere,
      sondern nur Bahnhofsgleise und die Fahrstraßen dorthin. Die Weichen 6 und 7 sind der Grund, warum das mit drei Gleisen aufgeht: Der Fahrplan
      verlangt um 10:34 eine Nebenbahn-Ausfahrt der RB 66, während die RB 64 von 10:22 bis 10:36
      in Gleis 3 wendet. Über Gleis 2 und die Weichen 6/7 sind beide Fahrten unabhängig.
    </div>
  </section>

  <section class="panel">
    <h3>Symbollegende (Ril 819.9002)</h3>
    <div class="legend">
      <div class="legend-item">
        <svg width="76" height="24" viewBox="0 0 76 24" aria-hidden="true">
          <line x1="0" y1="8" x2="76" y2="8" stroke="currentColor" stroke-width="2"/>
          <line x1="8" y1="3" x2="8" y2="13" stroke="currentColor" stroke-width="1.5"/>
          <line x1="26" y1="3" x2="26" y2="13" stroke="currentColor" stroke-width="1.5"/>
          <polygon points="26,8 50,8 50,19" fill="currentColor"/>
          <line x1="50" y1="19" x2="68" y2="23" stroke="currentColor" stroke-width="2"/>
          <line x1="58" y1="16" x2="56" y2="23" stroke="currentColor" stroke-width="1.5"/>
        </svg>
        <span>Ferngestellte Weiche: Weichenanfang · Weichenmitte · Schwärzung · Grenzzeichen</span>
      </div>
      <div class="legend-item">
        <svg width="44" height="18" viewBox="0 0 44 18" aria-hidden="true">
          <line x1="4" y1="2" x2="4" y2="16" stroke="currentColor" stroke-width="2"/>
          <line x1="4" y1="9" x2="20" y2="9" stroke="currentColor" stroke-width="2"/>
          <rect x="20" y="3" width="18" height="12" rx="6" fill="currentColor"/>
        </svg>
        <span>Ks-Mehrabschnittssignal, wärterbedient (Hp 0, Ks 1, Ks 2)</span>
      </div>
      <div class="legend-item">
        <svg width="56" height="18" viewBox="0 0 56 18" aria-hidden="true">
          <line x1="4" y1="2" x2="4" y2="16" stroke="currentColor" stroke-width="2"/>
          <line x1="4" y1="9" x2="20" y2="9" stroke="currentColor" stroke-width="2"/>
          <rect x="20" y="3" width="18" height="12" rx="6" fill="currentColor"/>
          <polygon points="41,3 51,9 41,15" fill="currentColor"/>
        </svg>
        <span>Zs 3 Geschwindigkeitsanzeiger (Lichtsignal), Kennzahl daneben</span>
      </div>
      <div class="legend-item">
        <svg width="58" height="20" viewBox="0 0 58 20" aria-hidden="true">
          <line x1="2" y1="3" x2="2" y2="17" stroke="currentColor" stroke-width="2"/>
          <line x1="2" y1="10" x2="16" y2="10" stroke="currentColor" stroke-width="2"/>
          <rect x="16" y="3.5" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.5"/>
          <polygon points="16,3.5 29,3.5 29,16.5" fill="currentColor"/>
          <rect x="29" y="4" width="18" height="12" rx="6" fill="currentColor"/>
        </svg>
        <span>Gegengleisanzeiger (Lichtsignal) am Ks-Hauptsignalschirm</span>
      </div>
      <div class="legend-item">
        <svg width="30" height="18" viewBox="0 0 30 18" aria-hidden="true">
          <line x1="0" y1="9" x2="30" y2="9" stroke="currentColor" stroke-width="2"/>
          <rect x="9" y="1" width="14" height="16" fill="var(--surface)"/>
          <text x="16" y="14" text-anchor="middle" font-size="12" font-weight="600" fill="currentColor" font-family="monospace">1</text>
        </svg>
        <span>Gleisnummer in der unterbrochenen Gleislinie</span>
      </div>
      <div class="legend-item">
        <svg width="34" height="18" viewBox="0 0 34 18" aria-hidden="true">
          <rect x="2" y="3" width="30" height="13" fill="none" stroke="currentColor" stroke-width="2"/>
        </svg>
        <span>Gebäude (Empfangsgebäude)</span>
      </div>
    </div>
  </section>

  <footer class="foot">LF 2 Jahresprojekt 2026 „Mitteltrasse" · 5. Teilabschnitt (Los 5) — Chemiezentrum</footer>
</div>

</body>
</html>
"""

ZEICHNUNG = """<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<title>Zeichnung Waldenberg</title>
<style>
  html,body{margin:0;padding:0;background:#ffffff;}
  .sheet{width:1600px;height:1131px;}
</style>
</head>
<body>
<div class="sheet">
<svg viewBox="0 0 1600 1131" width="100%" height="100%" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Technische Zeichnung, sicherungstechnischer Lageplan Waldenberg">
<rect x="0" y="0" width="1600" height="1131" fill="#ffffff"/>
<rect x="10" y="10" width="1580" height="1111" fill="none" stroke="#000" stroke-width="1"/>
<rect x="22" y="22" width="1556" height="1087" fill="none" stroke="#000" stroke-width="2.5"/>
<text x="42" y="60" font-size="15" font-weight="700" fill="#000" font-family="IBM Plex Mono, monospace">Lageplan Waldenberg</text>
<text x="1558" y="60" text-anchor="end" font-size="11" fill="#000" font-family="IBM Plex Mono, monospace">Ril 819.9001 / 819.9002</text>
<line x1="42" y1="70" x2="1558" y2="70" stroke="#000" stroke-width="1"/>
<g transform="translate(51,300) scale(0.78)" font-family="IBM Plex Mono, monospace">
        __PLAN__
</g>
<g font-family="IBM Plex Mono, monospace">
<rect x="60" y="900" width="940" height="176" fill="none" stroke="#000" stroke-width="1.5"/>
<g transform="translate(66,974)"><line x1="0" y1="8" x2="52" y2="8" stroke="#000" stroke-width="1.5"/><line x1="5" y1="3" x2="5" y2="13" stroke="#000" stroke-width="1.2"/><line x1="18" y1="3" x2="18" y2="13" stroke="#000" stroke-width="1.2"/><polygon points="18,8 36,8 36,17" fill="#000"/></g>
<text x="138" y="992" font-size="10" fill="#000">Weiche fern</text>
<line x1="216.667" y1="900" x2="216.667" y2="1076" stroke="#000" stroke-width="1"/>
<g transform="translate(226.667,979)"><line x1="2" y1="1" x2="2" y2="15" stroke="#000" stroke-width="1.5"/><line x1="2" y1="8" x2="14" y2="8" stroke="#000" stroke-width="1.5"/><rect x="14" y="2" width="16" height="11" rx="5.5" fill="#000"/></g>
<text x="294.667" y="992" font-size="10" fill="#000">Ks-Signal</text>
<line x1="373.333" y1="900" x2="373.333" y2="1076" stroke="#000" stroke-width="1"/>
<g transform="translate(383.333,979)"><rect x="2" y="2" width="24" height="13" fill="none" stroke="#000" stroke-width="1.5"/></g>
<text x="451.333" y="992" font-size="10" fill="#000">Gebäude</text>
<line x1="530" y1="900" x2="530" y2="1076" stroke="#000" stroke-width="1"/>
<g transform="translate(540,979)"><line x1="2" y1="1" x2="2" y2="15" stroke="#000" stroke-width="1.5"/><line x1="2" y1="8" x2="14" y2="8" stroke="#000" stroke-width="1.5"/><rect x="14" y="2" width="16" height="11" rx="5.5" fill="#000"/><polygon points="33,2 42,8 33,14" fill="#000"/></g>
<text x="608" y="992" font-size="10" fill="#000">Zs 3</text>
<line x1="686.667" y1="900" x2="686.667" y2="1076" stroke="#000" stroke-width="1"/>
<g transform="translate(696.667,979)"><line x1="0" y1="8" x2="26" y2="8" stroke="#000" stroke-width="1.5"/><rect x="8" y="1" width="12" height="14" fill="#fff" stroke="#000" stroke-width="1"/><text x="14" y="12" text-anchor="middle" font-size="10" font-weight="600" fill="#000">1</text></g>
<text x="764.667" y="992" font-size="10" fill="#000">Gleisnr.</text>
<line x1="843.333" y1="900" x2="843.333" y2="1076" stroke="#000" stroke-width="1"/>
<g transform="translate(853.333,972)"><line x1="0" y1="8" x2="26" y2="8" stroke="#000" stroke-width="1.5" stroke-dasharray="3,3"/><text x="13" y="26" text-anchor="middle" font-size="9" fill="#000">km 0,0</text></g>
<text x="915" y="992" font-size="9.5" fill="#000">Streckengrenze</text>
</g>
<text x="68" y="1094" font-size="10" fill="#000" font-family="IBM Plex Mono, monospace">Alle Weichen EW 1:9, 40 km/h · Gegengleisanzeiger an P2 und N1 · AA und FF für Ankunft auf dem Gegengleis · Gleis 4 = Lade- und Ausweichgleis</text>
<g font-family="IBM Plex Mono, monospace">
<rect x="1050" y="900" width="490" height="176" fill="none" stroke="#000" stroke-width="2"/>
<line x1="1050" y1="944" x2="1540" y2="944" stroke="#000" stroke-width="1"/>
<line x1="1050" y1="988" x2="1540" y2="988" stroke="#000" stroke-width="1"/>
<line x1="1050" y1="1018" x2="1540" y2="1018" stroke="#000" stroke-width="1"/>
<line x1="1050" y1="1048" x2="1540" y2="1048" stroke="#000" stroke-width="1"/>
<text x="1062" y="927" font-size="13" font-weight="700" fill="#000">LF 2 Jahresprojekt 2026 „Mitteltrasse"</text>
<text x="1062" y="971" font-size="11" fill="#000">5. Teilabschnitt (Los 5) – Chemiezentrum</text>
<line x1="1295" y1="988" x2="1295" y2="1048" stroke="#000" stroke-width="1"/>
<text x="1062" y="1000" font-size="10" fill="#333">Betriebsstelle</text>
<text x="1062" y="1013" font-size="13" font-weight="600" fill="#000">Waldenberg</text>
<text x="1307" y="1000" font-size="10" fill="#333">Kennzahl</text>
<text x="1307" y="1013" font-size="13" font-weight="600" fill="#000">31</text>
<text x="1062" y="1030" font-size="10" fill="#333">Inhalt</text>
<text x="1062" y="1043" font-size="11" fill="#000">Sicherungstechnischer Lageplan</text>
<text x="1307" y="1030" font-size="10" fill="#333">Blatt</text>
<text x="1307" y="1043" font-size="13" font-weight="600" fill="#000">2/5</text>
<line x1="1213.33" y1="1048" x2="1213.33" y2="1076" stroke="#000" stroke-width="1"/>
<line x1="1376.67" y1="1048" x2="1376.67" y2="1076" stroke="#000" stroke-width="1"/>
<text x="1060" y="1067" font-size="9.5" fill="#333">Maßstab: ohne</text>
<text x="1223.33" y="1067" font-size="9.5" fill="#333">Gezeichnet: LT-Azubi</text>
<text x="1386.67" y="1067" font-size="9.5" fill="#333">Datum: 2026</text>
</g>
</svg>
</div>
</body>
</html>
"""

open(REPO + "lageplan-waldenberg.html", "w").write(
    LAGEPLAN.replace("__PLAN__", w.LAGEPLAN).replace("__ARIA__", ARIA))
open(REPO + "zeichnung-waldenberg.html", "w").write(
    ZEICHNUNG.replace("__PLAN__", w.ZEICHNUNG))
print("geschrieben")
