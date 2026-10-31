/// Sign-in popup for Gmail / Outlook in the browser (OAuth implicit flow).
/// Phones use flutter_appauth instead.
library;

export 'oauth_stub.dart' if (dart.library.js_interop) 'oauth_web.dart';
