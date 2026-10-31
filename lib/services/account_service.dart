import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'settings_service.dart';

/// Today's built-in AI time for this account.
class AiQuota {
  AiQuota({required this.member, this.email, required this.usedSec, required this.limitSec, required this.resetsAt});

  final bool member;
  final String? email;
  final double usedSec;
  final double limitSec;
  final DateTime resetsAt;

  double get remainingSec => (limitSec - usedSec).clamp(0, limitSec).toDouble();
  bool get empty => remainingSec <= 0;
  double get fraction => limitSec <= 0 ? 0 : (usedSec / limitSec).clamp(0, 1).toDouble();

  /// "7 min left", "40 s left"
  String get leftLabel {
    final r = remainingSec;
    if (r <= 0) return 'No AI time left today';
    if (r < 60) return '${r.ceil()} s left';
    return '${(r / 60).ceil()} min left';
  }

  static AiQuota fromJson(Map<String, dynamic> j) => AiQuota(
        member: j['kind'] == 'member',
        email: j['email'] as String?,
        usedSec: (j['usedSec'] as num? ?? 0).toDouble(),
        limitSec: (j['limitSec'] as num? ?? 0).toDouble(),
        resetsAt: DateTime.tryParse('${j['resetsAt']}')?.toLocal() ?? DateTime.now().add(const Duration(days: 1)),
      );
}

class AccountException implements Exception {
  AccountException(this.code, this.message, {this.quota});
  final String code; // out_of_time, busy, wrong, exists, network…
  final String message;
  final AiQuota? quota;
  bool get outOfTime => code == 'out_of_time';
  @override
  String toString() => message;
}

/// The Cozy Pal account and its "AI time" (see server/cozy.js).
///
/// Everyone starts as a guest automatically (10 minutes of the built-in AI
/// a day). Making an account with an email and password raises it to 20
/// minutes. The time each answer takes is counted on the server, so the
/// allowance is the same on the web and in the phone apps.
class AccountService extends ChangeNotifier {
  AccountService(this.settings);
  final SettingsService settings;

  static const _tokenKey = 'cozy_token';
  static const _timeout = Duration(seconds: 50);

  AiQuota? quota;
  String? lastError;
  bool busy = false;

  bool get signedIn => quota?.member ?? false;
  String? get email => quota?.email;

  Uri _url(String path) => Uri.parse('${settings.cozyServer}$path');

  Future<String?> _token() => settings.readSecret(_tokenKey);

  Future<Map<String, dynamic>> _call(String method, String path, {Map<String, dynamic>? body, bool auth = true, Duration? timeout}) async {
    final token = auth ? await _token() : null;
    final headers = {
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    };
    http.Response res;
    try {
      res = await (method == 'GET'
              ? http.get(_url(path), headers: headers)
              : http.post(_url(path), headers: headers, body: jsonEncode(body ?? {})))
          .timeout(timeout ?? _timeout);
    } catch (_) {
      throw AccountException('network', "I couldn't reach Cozy Pal's server. Check your internet.");
    }
    Map<String, dynamic> j;
    try {
      j = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      j = {'error': 'server', 'message': 'The server sent something odd (${res.statusCode}).'};
    }
    if (j['quota'] is Map) _setQuota(AiQuota.fromJson((j['quota'] as Map).cast<String, dynamic>()));
    if (res.statusCode >= 400) {
      throw AccountException('${j['error'] ?? 'server'}', '${j['message'] ?? 'Something went wrong (${res.statusCode}).'}', quota: quota);
    }
    return j;
  }

  void _setQuota(AiQuota q) {
    quota = q;
    notifyListeners();
  }

  /// Makes sure there's a session (a guest one if needed) and refreshes the quota.
  Future<void> ensureSession() async {
    try {
      if (await _token() != null) {
        try {
          _setQuota(AiQuota.fromJson(await _call('GET', '/api/me')));
          return;
        } on AccountException catch (e) {
          if (e.code != 'no_session') rethrow;
          await settings.writeSecret(_tokenKey, null); // expired: start again as a guest
        }
      }
      final j = await _call('POST', '/api/auth/guest', auth: false);
      await settings.writeSecret(_tokenKey, j['token'] as String);
      _setQuota(AiQuota.fromJson((j['quota'] as Map).cast<String, dynamic>()));
      lastError = null;
    } on AccountException catch (e) {
      lastError = e.message;
      notifyListeners();
    }
  }

  Future<void> refresh() => ensureSession();

  Future<void> register(String email, String password) => _signIn('/api/auth/register', email, password);
  Future<void> login(String email, String password) => _signIn('/api/auth/login', email, password);

  Future<void> _signIn(String path, String email, String password) async {
    busy = true;
    notifyListeners();
    try {
      // the guest token goes along so today's usage carries over
      final j = await _call('POST', path, body: {'email': email.trim(), 'password': password});
      await settings.writeSecret(_tokenKey, j['token'] as String);
      _setQuota(AiQuota.fromJson((j['quota'] as Map).cast<String, dynamic>()));
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      await _call('POST', '/api/auth/logout');
    } catch (_) {}
    await settings.writeSecret(_tokenKey, null);
    quota = null;
    notifyListeners();
    await ensureSession(); // back to being a guest
  }

  /// Asks the built-in AI. Throws [AccountException] (e.g. out_of_time).
  Future<String> chat(String system, String user, {int maxTokens = 400}) async {
    if (await _token() == null) await ensureSession();
    Future<Map<String, dynamic>> go() =>
        _call('POST', '/api/ai/chat', body: {'system': system, 'user': user, 'maxTokens': maxTokens});
    Map<String, dynamic> j;
    try {
      j = await go();
    } on AccountException catch (e) {
      if (e.code != 'no_session') rethrow;
      await settings.writeSecret(_tokenKey, null);
      await ensureSession();
      j = await go();
    }
    return '${j['text'] ?? ''}'.trim();
  }
}
