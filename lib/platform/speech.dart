/// Speech-to-text in the browser (Web Speech API), used on the web instead
/// of Whisper. On phones [BrowserSpeech.supported] is false.
library;

export 'speech_stub.dart' if (dart.library.js_interop) 'speech_web.dart';
