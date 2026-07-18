import 'dart:js_interop';

/// Web: a short two-tone chime via the Web Audio API — no audio asset, no
/// plugin. Browsers block audio until the user has interacted with the page;
/// by the time a notification can arrive the patient has signed in, so the
/// context is allowed to run (and we resume() defensively).
@JS('AudioContext')
extension type _AudioContext._(JSObject _) implements JSObject {
  external factory _AudioContext();
  external _Oscillator createOscillator();
  external _Gain createGain();
  external JSObject get destination;
  external double get currentTime;
  external String get state;
  external JSPromise resume();
}

extension type _Oscillator._(JSObject _) implements JSObject {
  external void connect(JSObject destination);
  external void start();
  external void stop(double when);
  external set type(String value);
  external _AudioParam get frequency;
}

extension type _Gain._(JSObject _) implements JSObject {
  external void connect(JSObject destination);
  external _AudioParam get gain;
}

extension type _AudioParam._(JSObject _) implements JSObject {
  external set value(double value);
  external void setValueAtTime(double value, double startTime);
  external void exponentialRampToValueAtTime(double value, double endTime);
}

_AudioContext? _ctx;

Future<void> playNotificationBeep() async {
  try {
    final ctx = _ctx ??= _AudioContext();
    if (ctx.state == 'suspended') ctx.resume();
    final t0 = ctx.currentTime;
    // Two quick ascending tones (E6 -> A6), fading out — a friendly "ding-ding".
    for (final (i, freq) in const [(0, 1318.5), (1, 1760.0)]) {
      final osc = ctx.createOscillator();
      final gain = ctx.createGain();
      final start = t0 + i * 0.12;
      osc.type = 'sine';
      osc.frequency.value = freq;
      gain.gain.setValueAtTime(0.20, start);
      gain.gain.exponentialRampToValueAtTime(0.001, start + 0.25);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start();
      osc.stop(start + 0.25);
    }
  } catch (_) {
    // Sound is best-effort — never let it break the notification flow.
  }
}
