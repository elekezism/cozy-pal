import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// web/oauth.html posts the provider's answer (the URL #fragment) back to
/// this page; this is the address to register as the redirect URI.
String get oauthRedirectUri => '${Uri.base.origin}/oauth.html';

/// Opens the provider's sign-in page in a popup and waits for the answer.
/// Returns the redirect parameters (access_token, expires_in, error…), or
/// null if the popup was closed or blocked.
Future<Map<String, String>?> oauthPopup(String url) {
  final done = Completer<Map<String, String>?>();
  final popup = globalContext.callMethod<JSObject?>('open'.toJS, url.toJS, 'cozypal_oauth'.toJS, 'width=520,height=680'.toJS);
  if (popup == null) {
    throw StateError('The sign-in window was blocked. Allow pop-ups for this site and try again.');
  }
  late final JSFunction listener;
  Timer? poll;
  void finish(Map<String, String>? v) {
    if (done.isCompleted) return;
    poll?.cancel();
    globalContext.callMethod<JSAny?>('removeEventListener'.toJS, 'message'.toJS, listener);
    done.complete(v);
  }

  listener = ((JSObject event) {
    final origin = (event['origin'] as JSString?)?.toDart;
    final data = event['data'];
    if (origin != Uri.base.origin || data == null || !data.typeofEquals('string')) return;
    final s = (data as JSString).toDart;
    if (!s.startsWith('cozypal-oauth:')) return;
    finish(Uri.splitQueryString(s.substring('cozypal-oauth:'.length)));
  }).toJS;
  globalContext.callMethod<JSAny?>('addEventListener'.toJS, 'message'.toJS, listener);
  poll = Timer.periodic(const Duration(milliseconds: 700), (_) {
    final closed = popup['closed'];
    if (closed != null && (closed as JSBoolean).toDart) {
      // give a just-sent message a moment to arrive
      Future.delayed(const Duration(milliseconds: 400), () => finish(null));
    }
  });
  Future.delayed(const Duration(minutes: 5), () => finish(null));
  return done.future;
}
