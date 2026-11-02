// Web MIDI: alle Eingänge, Hot-Plug, Running Status. Nachrichten im gleichen Schema wie MIDIParser.swift.

export class MIDIInput {
  constructor(onMessage, onDevices) {
    this.onMessage = onMessage;
    this.onDevices = onDevices;
    this.access = null;
    this.names = [];
    this.error = null;
  }

  async start() {
    if (!navigator.requestMIDIAccess) { this.error = 'Web MIDI wird nicht unterstützt.'; return; }
    try {
      this.access = await navigator.requestMIDIAccess({ sysex: false });
      this.access.onstatechange = () => this.connect();
      this.connect();
    } catch (err) {
      this.error = `MIDI nicht verfügbar: ${err.message ?? err}`;
    }
  }

  connect() {
    if (!this.access) return;
    const names = [];
    for (const input of this.access.inputs.values()) {
      input.onmidimessage = (e) => this.parse(e.data);
      if (input.state === 'connected') names.push(input.name || 'MIDI-Gerät');
    }
    this.names = names;
    this.onDevices?.(names);
  }

  parse(data) {
    const status = data[0];
    if (status >= 0xf8) {
      const rt = { 0xf8: 'clock', 0xfa: 'start', 0xfb: 'continue', 0xfc: 'stop' }[status];
      if (rt) this.onMessage({ type: rt });
      return;
    }
    const channel = (status & 0x0f) + 1;
    const d1 = data[1] ?? 0, d2 = data[2] ?? 0;
    switch (status & 0xf0) {
      case 0x90: this.onMessage(d2 === 0 ? { type: 'noteOff', channel, note: d1, velocity: 0 } : { type: 'noteOn', channel, note: d1, velocity: d2 }); break;
      case 0x80: this.onMessage({ type: 'noteOff', channel, note: d1, velocity: d2 }); break;
      case 0xb0: this.onMessage({ type: 'cc', channel, controller: d1, value: d2 }); break;
      default: break;
    }
  }
}

export function noteName(n) {
  if (n < 0 || n > 127) return '—';
  return `${['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'][n % 12]}${Math.floor(n / 12) - 2} (${n})`;
}
