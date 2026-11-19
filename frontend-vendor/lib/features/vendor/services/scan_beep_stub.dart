// Scan confirmation on phones and desktop: a system click and a short vibration
import 'package:flutter/services.dart';

void scanBeep() {
  SystemSound.play(SystemSoundType.click);
  HapticFeedback.mediumImpact();
}
