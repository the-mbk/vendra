// Speech output in the browser (Web Speech API, window.speechSynthesis)
import 'package:web/web.dart' as web;

bool get speechSupported => true;

/// Queues [text]; earlier cues still finish first
void speak(String text) {
  final utterance = web.SpeechSynthesisUtterance(text)
    ..lang = 'en-US'
    ..rate = 1.0;
  web.window.speechSynthesis.speak(utterance);
}
