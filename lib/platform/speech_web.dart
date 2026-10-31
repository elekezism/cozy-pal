import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Dictation with the browser's own speech recognition (Chrome, Edge,
/// Safari). Audio is processed by the browser, not by this app.
class BrowserSpeech {
  static JSFunction? get _ctor {
    if (globalContext.has('SpeechRecognition')) return globalContext['SpeechRecognition'] as JSFunction;
    if (globalContext.has('webkitSpeechRecognition')) return globalContext['webkitSpeechRecognition'] as JSFunction;
    return null;
  }

  static bool get supported => _ctor != null;

  JSObject? _rec;
  bool _listening = false;
  bool get listening => _listening;

  /// Starts listening. [onText] gets everything heard so far (final words
  /// plus the guess for the words still being spoken). [continuous] keeps
  /// going through pauses until [stop] (for notes).
  void start({
    String lang = 'en-US',
    bool continuous = false,
    required void Function(String text) onText,
    void Function()? onEnd,
    void Function(String error)? onError,
  }) {
    final ctor = _ctor;
    if (ctor == null) {
      onError?.call("This browser can't do speech-to-text. Try Chrome, Edge or Safari, or type instead.");
      return;
    }
    final rec = ctor.callAsConstructor<JSObject>();
    rec['lang'] = lang.toJS;
    rec['interimResults'] = true.toJS;
    rec['continuous'] = continuous.toJS;
    var finalText = '';
    rec['onresult'] = ((JSObject event) {
      final results = event['results'] as JSObject;
      final start = (event['resultIndex'] as JSNumber).toDartInt;
      final length = (results['length'] as JSNumber).toDartInt;
      var interim = '';
      for (var i = start; i < length; i++) {
        final result = results.callMethod<JSObject>('item'.toJS, i.toJS);
        final alt = result.callMethod<JSObject>('item'.toJS, 0.toJS);
        final words = (alt['transcript'] as JSString).toDart;
        if ((result['isFinal'] as JSBoolean).toDart) {
          finalText = '$finalText $words'.trim();
        } else {
          interim = '$interim $words';
        }
      }
      onText('$finalText $interim'.replaceAll(RegExp(r'\s+'), ' ').trim());
    }).toJS;
    rec['onerror'] = ((JSObject event) {
      final code = (event['error'] as JSString?)?.toDart ?? 'error';
      if (code == 'no-speech' || code == 'aborted') return;
      onError?.call(code == 'not-allowed' || code == 'service-not-allowed'
          ? 'Microphone access was blocked. Allow it in the browser to talk to your pet.'
          : 'Speech recognition stopped ($code).');
    }).toJS;
    rec['onend'] = ((JSAny? _) {
      _listening = false;
      onEnd?.call();
    }).toJS;
    _rec = rec;
    _listening = true;
    rec.callMethod<JSAny?>('start'.toJS);
  }

  void stop() {
    _rec?.callMethod<JSAny?>('stop'.toJS);
  }
}
