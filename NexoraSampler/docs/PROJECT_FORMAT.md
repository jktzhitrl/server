# NEXORA Sampler – Dateiformate

Alle Formate sind UTF-8-JSON mit sortierten Schlüsseln. Datumswerte sind ISO 8601,
Binärdaten (macOS-Bookmarks) Base64. Unbekannte Schlüssel werden beim Lesen ignoriert,
fehlende Schlüssel erhalten Standardwerte – ältere und neuere Dateien bleiben dadurch lesbar.
Dateien mit einer **höheren** `formatVersion` als unterstützt werden mit einer Fehlermeldung abgelehnt.

## 1. Projekt – `Name.nexora/`

Ein Projekt ist ein **Ordner-Paket** (unter macOS als Dokumentpaket registriert, erscheint im Finder als eine Datei):

```
MeinBeat.nexora/
├── project.json          ProjectDocument
└── Samples/              Kopien ALLER verwendeten Samples
    ├── 01-Kick.wav       Präfix = Pad-Nummer, Originalformat bleibt erhalten
    ├── 02-SNARE.wav      synthetisierte Werks-Samples: 32-Bit-Float-WAV (verlustfrei)
    └── …
```

Gespeichert wird atomar: Das Paket wird zuerst in einem temporären Ordner
(`.Name.nexora.saving-<UUID>`) erzeugt und erst nach erfolgreichem Schreiben gegen das
bestehende Paket getauscht.

### `project.json` (ProjectDocument)

| Schlüssel | Typ | Beschreibung |
|---|---|---|
| `format` | String | immer `de.nexora.sampler.project` |
| `formatVersion` | Int | aktuell `1` |
| `name`, `kitName` | String | Projekt- und Kit-Name |
| `createdAt`, `modifiedAt` | Datum | ISO 8601 |
| `bpm` | Double | 40 … 300 |
| `swing` | Double | 50 … 75 (%) – 50 = gerade, 66,7 = Triolen-Feel |
| `pads` | [PadConfig] × 16 | Pad-Belegungen |
| `master` | MasterSettings | Master-Effektkette |
| `engine` | EngineSettings | Polyphonie, Voice-Stealing |
| `sequencer` | SequencerState | Patterns A–H, Mutes/Solos, Quantisierung |
| `xyPad` | XYPadAssignment | Achsenzuweisung |
| `midi` | MIDISettings | Kanal, Pad-Noten, CC-Mappings |
| `export` | ExportSettings | zuletzt verwendete Export-Einstellungen |
| `patternChain` | [Int] | Slot-Reihenfolge für den Ketten-Export (0 = A) |

### PadConfig

| Schlüssel | Typ | Beschreibung |
|---|---|---|
| `index` | Int | 0 … 15 (Pad 1 = unten links) |
| `name` | String | Anzeigename |
| `keyboardKey` | String | auslösende Taste (ein Zeichen) |
| `sample` | SampleReference? | Verweis auf die Audiodatei |
| `settings` | PadSettings | Klangeinstellungen |

### SampleReference – zuverlässiges Wiederfinden

| Schlüssel | Typ | Beschreibung |
|---|---|---|
| `fileName` | String | ursprünglicher Dateiname |
| `packagePath` | String? | Pfad relativ zum Paket, z. B. `Samples/01-Kick.wav` |
| `libraryItemID` | UUID? | Eintrag in der Sample-Bibliothek |
| `bookmark` | Data? | macOS-Bookmark der Originaldatei (überlebt Umbenennen/Verschieben) |
| `originalPath` | String? | absoluter Pfad beim Import |
| `fileSize`, `frameCount`, `sampleRate` | Zahl? | Metadaten zur Plausibilitätsprüfung |

Suchreihenfolge beim Öffnen (`SampleResolver`):
1. Kopie im Paket (`packagePath`) – Normalfall, da jedes Speichern alle Samples ins Paket kopiert
2. Sample-Bibliothek (`libraryItemID`)
3. Bookmark
4. Originalpfad
5. Suche nach `fileName` in Bibliotheksordner, Projektordner und `~/Music` (bei mehreren Treffern gewinnt gleiche `fileSize`)

Nicht gefundene Samples werden nach dem Öffnen aufgelistet; das Pad behält Namen und Einstellungen.

### PadSettings

| Schlüssel | Bereich | Standard | Bedeutung |
|---|---|---|---|
| `volume` | 0 … 1.25 | 0.8 | lineare Verstärkung |
| `pan` | −1 … 1 | 0 | Balance |
| `pitch` | −24 … 24 | 0 | Halbtöne |
| `fineTune` | −100 … 100 | 0 | Cent |
| `speed` | 0.25 … 4 | 1 | Wiedergabegeschwindigkeit |
| `pitchMode` | `varispeed` \| `timeStretch` | varispeed | gekoppelt (Resampling) oder unabhängig (granular) |
| `start`, `end` | 0 … 1 | 0 / 1 | Sample-Bereich relativ zur Länge |
| `reverse` | Bool | false | rückwärts |
| `playMode` | `oneShot` \| `gate` \| `loop` | oneShot | |
| `attack`, `decay`, `release` | Sekunden | 0.001 / 0.4 / 0.08 | Hüllkurve |
| `sustain` | 0 … 1 | 1 | |
| `filterMode` | `off` \| `lowPass` \| `highPass` \| `bandPass` | off | Pad-Filter (12 dB/Okt., SVF) |
| `cutoff` | 20 … 20000 Hz | 18000 | |
| `resonance` | 0 … 1 | 0.1 | |
| `lfoRate` | 0.05 … 30 Hz | 4 | Pad-LFO |
| `lfoDepth` | 0 … 1 | 0 | |
| `lfoShape` | `sine` \| `triangle` \| `square` \| `sawUp` \| `sawDown` \| `sampleHold` | sine | |
| `lfoTarget` | `off` \| `pitch` \| `volume` \| `cutoff` \| `pan` | off | Vibrato / Tremolo / Filter / Auto-Pan |
| `drive` | 0 … 1 | 0 | Sättigung |
| `crushBits` | 1 … 16 | 16 | Bitcrusher-Tiefe (16 = aus) |
| `crushDownsample` | 1 … 32 | 1 | Sample-Rate-Reduktion (1 = aus) |
| `reverbSend`, `delaySend` | 0 … 1 | 1 | Send-Pegel |
| `velocitySensitivity` | 0 … 1 | 0.7 | |
| `chokeGroup` | 0 … 8 | 0 | 0 = keine |
| `mono` | Bool | false | neuer Anschlag beendet vorherige Stimme |

### MasterSettings

`volume`, `filterMode`, `filterCutoff`, `filterResonance`, `drive`, `crushBits`, `crushDownsample`,
`delayTime` (s), `delaySync` (`off`, `whole`, `half`, `quarter`, `dottedEighth`, `eighth`, `tripletEighth`,
`sixteenth`, `tripletSixteenth`, `thirtySecond`), `delayFeedback`, `delayMix`, `delayPingPong`, `delayDamping`,
`reverbSize`, `reverbDamping`, `reverbMix`, `reverbWidth`, `eqLow`/`eqMid`/`eqHigh` (dB, ±15), `eqMidFrequency` (Hz),
`compThreshold` (dB), `compRatio`, `compAttack` (s), `compRelease` (s), `compMakeup` (dB),
`modRate` (Hz), `modDepth` (0…1), `modShape`, `modTarget` (`filter`, `tremolo`, `vibrato`, `pan`).

### SequencerState / Pattern

```json
"sequencer": {
  "currentPattern": 0,
  "quantize": "sixteenth",          // off | sixteenth | eighth | quarter (Live-Aufnahme)
  "metronome": false,
  "switchAtBarEnd": true,
  "trackMutes": [false, …],          // 16 Einträge
  "trackSolos": [false, …],
  "patterns": [                      // 8 Slots (A–H)
    {
      "id": "UUID", "name": "Pattern A", "length": 16,
      "gates": [1, 1, …],            // Notenlänge je Spur in Schritten (Gate/Loop-Pads)
      "steps": [                     // [Spur 0…15][Schritt 0…15]
        [ {"active": true, "velocity": 1, "offset": 0}, … ], …
      ]
    }
  ]
}
```

`offset` ist das Mikro-Timing einer unquantisiert aufgenommenen Note in Schritten (−0.5 … 0.5).
Spur *n* spielt immer Pad *n*.

### MIDISettings

```json
"midi": {
  "inputChannel": 0,                 // 0 = Omni
  "padNotes": [36, 37, …, 51],       // MIDI-Note je Pad
  "ccMappings": [ {"id": "UUID", "channel": 1, "controller": 74,
                   "parameter": "masterFilterCutoff", "padIndex": null} ],
  "respondToTransport": true,
  "fixedVelocity": false
}
```

`parameter` ist ein `ParameterID` (siehe `Packages/NexoraCore/Sources/NexoraCore/Models/Parameters.swift`).
CC-Werte 0 … 127 werden linear auf den normierten Parameterbereich abgebildet (Kennlinie je Parameter).

## 2. Drum-Kit – `Name.nexorakit/`

Gleicher Aufbau wie ein Projekt, jedoch mit `kit.json`:
`{ "format": "de.nexora.sampler.kit", "formatVersion": 1, "name": "…", "pads": [PadConfig × 16] }`

## 3. Effekt-Preset – `Name.nexorafx`

`{ "format": "de.nexora.sampler.effects", "formatVersion": 1, "name": "…", "master": MasterSettings }`

## 4. Pattern-Preset – `Name.nexorapattern`

`{ "format": "de.nexora.sampler.pattern", "formatVersion": 1, "name": "…", "pattern": Pattern, "bpm": 120, "swing": 50 }`

Presets liegen unter `~/Library/Application Support/NEXORA Sampler/Presets/{Kits,Effects,Patterns}`.

## 5. Sample-Bibliothek

`~/Library/Application Support/NEXORA Sampler/Library/library.json`:

```json
{ "formatVersion": 1,
  "collections": [ { "id": "UUID", "name": "My Samples",
     "items": [ { "id": "UUID", "name": "Kick", "relativePath": "Collections/<UUID>/Kick.wav",
                  "absolutePath": null, "duration": 0.42, "sampleRate": 44100, "channels": 2,
                  "addedAt": "2026-11-01T12:00:00Z" } ] } ] }
```

Kopierte Dateien liegen unter `Collections/<Sammlungs-ID>/`; referenzierte (nicht kopierte) Dateien
werden über `absolutePath` gefunden.

## 6. Audio-Export

WAV (RIFF, PCM 16/24 Bit oder IEEE-Float 32 Bit) bzw. AIFF (PCM 16/24 Bit), immer stereo,
44,1 oder 48 kHz. 16-Bit-Export mit TPDF-Dither.
