"""Gemeinsames Seitenlayout der Lageplan-Blaetter.

Das Stylesheet wird von den Seitengeneratoren geteilt, damit alle Blaetter
gleich aussehen. build_waldenberg.py fuehrt bisher noch eine eigene Kopie.
"""

CSS = """
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
"""
