// Speech output where the browser API isn't available (Android / desktop builds):
// voice cues are simply off there.
bool get speechSupported => false;

void speak(String text) {}
