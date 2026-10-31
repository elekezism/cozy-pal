/// Small persistent storage that works on phones (files) and in the browser
/// (localStorage via shared_preferences). See store_io.dart / store_web.dart.
library;

export 'store_io.dart' if (dart.library.js_interop) 'store_web.dart';
