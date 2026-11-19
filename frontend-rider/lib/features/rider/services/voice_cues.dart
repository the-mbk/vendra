// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Voice cues
// A rider on a motorbike can't read the screen, so the key moments of a
// delivery are spoken: where to go, arriving at the store, heading to
// the customer, reaching the drop-off (ask for the code), done.
// Each cue is said once per delivery. Uses the browser's speech engine
// (Web Speech API); where there is none the cues are silent. The rider
// can switch them off (remembered on the device).
// ══════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/rider_models.dart';
import 'speech_stub.dart' if (dart.library.js_interop) 'speech_web.dart' as speech;

/// One thing to say, with a key so it is said only once
typedef VoiceCue = ({String key, String text});

/// The cue for where this delivery stands now (the latest stage only, so reopening
/// a delivery halfway through says one line, not the whole history)
VoiceCue? voiceCueFor(RiderOrder order, {double? metersToStore, double? metersToCustomer, required double geofenceMeters}) {
  final id = order.id;
  final store = order.storeName ?? 'the store';
  switch (order.step) {
    case DeliveryStep.headingToStore:
      if (metersToStore != null && metersToStore <= geofenceMeters) {
        return (key: 'store-$id', text: 'You have arrived at $store. Tap arrived at store.');
      }
      return (key: 'go-$id', text: 'New delivery. Head to $store.');
    case DeliveryStep.atStore:
      return (key: 'store-$id', text: 'You have arrived at $store. Collect the order.');
    case DeliveryStep.pickedUp:
    case DeliveryStep.onTheWay:
      if (metersToCustomer != null && metersToCustomer <= geofenceMeters) {
        return (
          key: 'door-$id',
          text: order.otpRequired
              ? 'You are at the drop-off. Ask the customer for the four digit code.'
              : 'You are at the drop-off. Hand over the order and confirm delivery.',
        );
      }
      return (key: 'picked-$id', text: 'Order picked up. Head to the customer.');
    case DeliveryStep.delivered:
      return (key: 'done-$id', text: 'Delivery complete. Well done.');
    case DeliveryStep.closed:
      return null;
  }
}

class VoiceCues extends ChangeNotifier {
  static final VoiceCues _instance = VoiceCues._();
  factory VoiceCues() => _instance;
  VoiceCues._();

  static const _kEnabled = 'rider_voice_cues';

  bool _enabled = true;
  bool _loaded = false;
  final Set<String> _spoken = {};

  /// This device can speak (a browser with speech synthesis)
  bool get supported => speech.speechSupported;

  /// Cues will be spoken
  bool get enabled => supported && _enabled;

  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      _enabled = (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? true;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setEnabled(bool on) async {
    _enabled = on;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(_kEnabled, on);
    } catch (_) {}
  }

  /// Says [cue] unless it was already said (or cues are off)
  void say(VoiceCue? cue) {
    if (cue == null || !enabled || !_spoken.add(cue.key)) return;
    speech.speak(cue.text);
  }
}
