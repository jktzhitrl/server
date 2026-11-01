# Architektur

```
┌──────────────────────────── NexoraSampler.app (SwiftUI, macOS 14+) ─────────────────────────────┐
│ Views/ Components/        SamplerController (@MainActor, @Observable)       MeterModel (30 Hz)  │
│  LCD, Knobs, Pads, XY ──▶ Projektmodell ⇄ Engine-Befehle, Dateien, Presets, MIDI-Learn, Export  │
│                                   │ send(EngineCommand)        ▲ EngineStatus / EngineEvent     │
│ Audio/AudioEngineHost ── AVAudioEngine ── AVAudioSourceNode ── render() ──┐                       │
│ MIDI/MIDIManager ─ Core MIDI (UMP) ─ Noten direkt an die Engine (MIDI-Thread)                     │
└────────────────────────────────────────────────────────────────────────────┼──────────────────────┘
┌──────────────────────────── NexoraCore (Swift Package, plattformunabhängig) ┼─────────────────────┐
│ Engine/SamplerEngine   80 Stimmen-Slots, Voice-Stealing, Choke, Vorhören, Metronom               │
│ Sequencer/SequencerClock  sample-genaue Planung im Audio-Thread, Swing, Mikro-Timing              │
│ DSP/  SVF-Filter, Biquad-EQ, ADSR, LFO, Delay, Freeverb-Hall, Drive, Bitcrusher, Kompressor,      │
│       Vibrato (moduliertes Delay), Vektor-Operationen (Accelerate/vDSP)                           │
│ Models/  ProjectDocument, PadSettings, MasterSettings, Pattern, ParameterID-Registry               │
│ Presets/ ProjectPackage, PresetStore, SampleLibrary, SampleResolver                               │
│ Export/  OfflineRenderer (gleiche Engine), WAV/AIFF-Writer/Reader                                 │
│ MIDI/    MIDIParser (Bytes + Universal MIDI Packets)     Audio/ AudioFileLoader (AVAudioFile)     │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Signalfluss

```
Pad-Stimme:  Sample (Hermite-Interpolation | granularer Time-Stretch) → Start/End/Reverse/Loop
             → ADSR → Pad-Filter (LP/HP/BP) → Drive → Bitcrusher → Volume·Velocity·Tremolo → Pan
             → Dry-Bus  +  Reverb-Send  +  Delay-Send
Master:      Dry + Delay-Return·Mix + Reverb-Return·Mix → Filter (XY) → Drive → Bitcrusher
             → Modulation (Filter/Tremolo/Vibrato/Auto-Pan) → 3-Band-EQ → Kompressor
             → Master-Volume → (+ Vorhören, Metronom) → Clip-Schutz → Ausgang
```

## Echtzeit-Regeln im Audio-Thread

* Keine Allokationen: Stimmen, Busse, Delay- und Hall-Puffer werden beim Start angelegt.
* Keine blockierenden Locks: Befehle werden über einen Ringpuffer übergeben; der Audio-Thread
  verwendet ausschließlich `tryLock` (bei Konflikt im nächsten Block, ≈ 3–6 ms später).
* Keine Speicherfreigabe: ersetzte Samples/Patterns wandern in eine „Garbage“-Queue, die der
  Haupt-Thread mit 30 Hz leert.
* UI-Werte (Pegel, Schritt, Stimmen) werden als ausgerichtete 32-Bit-Werte geschrieben und von der
  UI gepollt – die Wiedergabe hängt nie von SwiftUI ab.
* Geglättete Parameter (Lautstärke, Cutoff, Mix, Delay-Zeit) verhindern Zipper-Geräusche;
  Mindest-Attack (0,5 ms), Mindest-Release (2 ms), End-Fade (48 Samples) und 3–4-ms-Fades bei
  Voice-Stealing/Choke verhindern Klicks.

## Sequencer-Timing

Positionen werden in Sequencer-Schritten (16tel) gezählt, nicht in Samples. Pro Audio-Block plant
der Sequencer alle Schritte bis eine Schrittlänge voraus und teilt den Block exakt an den
Ereignis-Zeitpunkten. Ereignisse liegen damit auf ±1 Sample genau (durch Tests belegt); Tempo-
und Swing-Änderungen wirken sofort.

## Threads

| Thread | Aufgaben |
|---|---|
| Audio (Core Audio IO) | `SamplerEngine.render` – DSP, Sequencer, Stimmen |
| MIDI (Core MIDI) | UMP-Parsing, Note-On/Off direkt an die Engine |
| Main | UI, Projektmodell, CC-Mappings, MIDI-Learn, Status-Polling (30 Hz) |
| Hintergrund-Tasks | Dekodieren von Audiodateien, Offline-Export |
