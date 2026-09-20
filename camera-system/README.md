# Eigenes Kamerasystem (Reolink + Blink, ohne Cloud-Abo)

Vereint deine Reolink- und Blink-Kameras in einem lokalen Dashboard
(Home Assistant), mit dauerhafter lokaler Aufzeichnung fuer die
Reolink-Kameras (Frigate) — ganz ohne wiederkehrendes Abo.

## Was hier drinsteckt

- **Home Assistant**: zentrales Dashboard fuer beide Kamera-Marken.
- **Frigate**: lokaler NVR mit Bewegungs-/Objekterkennung, spricht direkt
  per RTSP mit den Reolink-Kameras. Aufzeichnung liegt komplett lokal.
- **Mosquitto**: MQTT-Broker, verbindet Frigate mit Home Assistant.
- **Blink**: laeuft ueber die eingebaute Blink-Integration in Home Assistant
  (Live-Bild, Bewegungsmelder, Akkustand) plus lokaler USB-Speicherung am
  Sync Module 2 (siehe unten) statt Cloud-Abo.

Reolink braucht grundsaetzlich kein Abo (RTSP ist nativ eingebaut), Blink
speichert Clips normalerweise nur in der Cloud gegen Abo — die lokale
USB-Speicherung am Sync Module 2 umgeht das.

## Voraussetzungen

- Ein immer laufendes Geraet im Heimnetz (z.B. Mini-PC, NAS, Raspberry Pi
  4/5) mit Docker und Docker Compose.
- Reolink- und Blink-Kameras im selben Netzwerk (WLAN oder LAN).
- Ein Blink-Account (App-Login) mit Sync Module 2.

## 1. Reolink-Kameras vorbereiten

1. In der Reolink-App/Weboberflaeche jeder Kamera: Standardpasswort
   aendern, RTSP ist normalerweise bereits aktiviert.
2. Im Router jeder Kamera eine feste IP per DHCP-Reservierung geben
   (verhindert, dass sich die Adresse spaeter aendert).
3. RTSP-Pfade notieren. Bei den meisten Reolink-Modellen:
   - Hauptstream (fuer Aufnahme): `/h264Preview_01_main`
   - Substream (fuer Erkennung, sparsamer): `/h264Preview_01_sub`
   Falls dein Modell abweicht, steht der korrekte Pfad im Reolink-Handbuch
   oder in der Frigate-Kompatibilitaetsliste.

## 2. Zugangsdaten eintragen

```bash
cd camera-system
cp .env.example .env
```

`.env` mit den echten Kamera-Zugangsdaten fuellen.

## 3. Kamera-IPs in Frigate eintragen

In `frigate/config.yml` bei `reolink_eingang` / `reolink_garten` die
IP-Adressen (`192.168.1.101` / `.102`) durch die echten IPs deiner
Kameras ersetzen. Fuer weitere Kameras den Block kopieren, umbenennen und
entsprechende Variablen in `.env` ergaenzen.

## 4. Starten

```bash
docker compose up -d
```

- Frigate-UI: `http://<geraete-ip>:5000` — hier pruefen, ob beide Kameras
  Bild liefern und Aufnahmen laufen.
- Home Assistant: `http://<geraete-ip>:8123` — Ersteinrichtungsassistent
  durchlaufen.

## 5. Home Assistant einrichten

1. **MQTT**: Einstellungen → Geraete & Dienste → Integration hinzufuegen →
   MQTT → Broker `mosquitto` (bzw. `localhost`, da `network_mode: host`),
   Port `1883`.
2. **Frigate-Karte**: [HACS](https://hacs.xyz/) installieren (eigene
   Anleitung auf der HACS-Seite), darueber die "Frigate"-Integration und
   die Lovelace-Kamera-Karte installieren. Als Frigate-URL
   `http://frigate:5000` (bzw. `http://localhost:5000`) eintragen.
3. **Blink**: Einstellungen → Geraete & Dienste → Integration hinzufuegen →
   "Blink" → mit Blink-Account-E-Mail/Passwort anmelden, 2FA-Code aus der
   Blink-App eingeben. Du bekommst Kamera-Snapshots, Bewegungssensoren und
   Akkustand-Sensoren fuer alle Blink-Kameras.

## 6. Blink lokal ohne Abo aufzeichnen

Home Assistant zeigt Blink-Live-Bilder/Events an, ersetzt aber nicht die
Cloud-Speicherung. Dafuer am Sync Module 2 selbst:

1. In der Blink-App: Sync Module → Local Storage aktivieren.
2. Einen USB-Stick (FAT32 oder exFAT, moeglichst schnell) ins Sync
   Module 2 stecken.
3. Clips werden jetzt lokal auf dem Stick gespeichert statt in der
   Blink-Cloud — kein Abo mehr noetig fuer die Aufzeichnung.

## Sicherheit / Fernzugriff

- Mosquitto laeuft hier ohne Zugangsdaten (`allow_anonymous true`) — das
  ist nur fuer den Betrieb im eigenen, vertrauenswuerdigen Heimnetz gedacht.
  Fuer mehr Sicherheit einen Nutzer/Passwort in `mosquitto/mosquitto.conf`
  einrichten.
- Frigate und Home Assistant NICHT direkt per Portweiterleitung ins
  Internet freigeben. Fuer Fernzugriff stattdessen ein VPN (z.B.
  Tailscale/WireGuard) oder Home Assistant Cloud (Nabu Casa) nutzen.

## Hardware-Hinweis

Die Objekterkennung laeuft standardmaessig auf der CPU (`detectors.cpu1`)
— das funktioniert ueberall, belastet aber den Prozessor spuerbar. Mit
einem Google-Coral-USB-Stick (siehe Kommentar in `frigate/config.yml`)
laeuft die Erkennung deutlich schneller und guenstiger.
