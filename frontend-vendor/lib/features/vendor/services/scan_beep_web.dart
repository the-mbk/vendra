// Scan confirmation in the browser: a short 1 kHz beep (Web Audio), like a till scanner
import 'package:web/web.dart' as web;

web.AudioContext? _audio;

void scanBeep() {
  try {
    final ctx = _audio ??= web.AudioContext();
    final osc = ctx.createOscillator();
    final gain = ctx.createGain();
    osc.type = 'square';
    osc.frequency.value = 1000;
    gain.gain.value = 0.08;
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.12);
  } catch (_) {
    // No audio (blocked autoplay, no output device): scanning still works
  }
}
