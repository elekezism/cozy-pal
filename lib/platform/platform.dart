import 'package:flutter/foundation.dart';

/// Where we're running. Uses [defaultTargetPlatform] (works in the browser)
/// instead of dart:io's Platform (which throws there).
bool get isWeb => kIsWeb;
bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Browsers block most cross-site requests (CORS). On the web, requests to
/// Apple's song search, meme-api.com and itch.io go through this site's own
/// Cloudflare Pages Function (functions/api/fetch.js), which only forwards to
/// a short allow-list of hosts. On phones the URL is used as is.
Uri viaProxy(Uri url) => kIsWeb ? Uri.parse('${Uri.base.origin}/api/fetch?url=${Uri.encodeComponent(url.toString())}') : url;
