import 'dart:convert';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_appauth/flutter_appauth.dart';

import '../platform/oauth.dart';
import 'package:http/http.dart' as http;

import 'settings_service.dart';

class EmailException implements Exception {
  EmailException(this.message);
  final String message;
  @override
  String toString() => message;
}

class EmailItem {
  EmailItem({
    required this.id,
    required this.from,
    required this.subject,
    required this.snippet,
    this.date,
    this.unread = true,
    this.webLink,
  });
  final String id;
  final String from;
  final String subject;
  final String snippet;
  final DateTime? date;
  final bool unread;

  /// Opens the message in the provider's web/mail app, when known.
  final String? webLink;

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'subject': subject,
        'snippet': snippet,
        'date': date?.toIso8601String(),
        'unread': unread,
        'webLink': webLink,
      };

  static EmailItem fromJson(Map<String, dynamic> j) => EmailItem(
        id: j['id'] as String,
        from: j['from'] as String? ?? '',
        subject: j['subject'] as String? ?? '',
        snippet: j['snippet'] as String? ?? '',
        date: DateTime.tryParse(j['date'] as String? ?? ''),
        unread: j['unread'] as bool? ?? false,
        webLink: j['webLink'] as String?,
      );
}

/// Reads *unread* inbox mail from the service the user picked.
/// Nothing is ever sent, deleted or marked as read.
class EmailService {
  EmailService(this.settings);
  final SettingsService settings;
  final _appAuth = const FlutterAppAuth();

  /// Must match the URL scheme registered by tool/setup_platforms.dart.
  static const redirectScheme = 'com.cozypal.app';
  static const googleRedirect = '$redirectScheme:/oauthredirect';
  static const microsoftRedirect = '$redirectScheme://oauth/redirect';

  static const _googleDiscovery =
      'https://accounts.google.com/.well-known/openid-configuration';
  static const _googleScopes = [
    'openid',
    'email',
    'https://www.googleapis.com/auth/gmail.readonly',
  ];
  static const _msDiscovery =
      'https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration';
  static const _msScopes = ['openid', 'offline_access', 'Mail.Read'];

  static const maxEmails = 10;

  bool get isConfigured => settings.emailProvider != EmailProvider.none;

  // ------------------------------------------------------------------
  // Sign in / out
  // ------------------------------------------------------------------

  /// Opens the provider's sign-in page (Gmail / Outlook) or checks the
  /// IMAP login. Returns a short description of the connected account.
  Future<String> connect() async {
    final p = settings.emailProvider;
    switch (p) {
      case EmailProvider.gmail:
        await _oauthSignIn('gmail', settings.googleClientId, googleRedirect,
            _googleDiscovery, _googleScopes);
        return 'Gmail connected';
      case EmailProvider.outlook:
        await _oauthSignIn('outlook', settings.microsoftClientId,
            microsoftRedirect, _msDiscovery, _msScopes);
        return 'Outlook connected';
      case EmailProvider.yahoo:
      case EmailProvider.icloud:
      case EmailProvider.otherImap:
        if (kIsWeb) throw EmailException('IMAP mail needs the phone app. In the browser, use Gmail or Outlook.');
        await _fetchImap(testOnly: true);
        return '${settings.imapUser} connected';
      case EmailProvider.none:
        throw EmailException('Pick an email service first.');
    }
  }

  Future<void> disconnect() async {
    await settings.writeSecret('tokens_gmail', null);
    await settings.writeSecret('tokens_outlook', null);
    await settings.writeSecret('imap_password', null);
    settings.lastMailCheck = null;
  }

  Future<bool> isSignedIn() async {
    final p = settings.emailProvider;
    if (p == EmailProvider.gmail) {
      return await settings.readSecret('tokens_gmail') != null;
    }
    if (p == EmailProvider.outlook) {
      return await settings.readSecret('tokens_outlook') != null;
    }
    if (p.usesImap) {
      return settings.imapHost.isNotEmpty &&
          settings.imapUser.isNotEmpty &&
          (await settings.readSecret('imap_password') ?? '').isNotEmpty;
    }
    return false;
  }

  Future<void> _oauthSignIn(String name, String clientId, String redirect,
      String discovery, List<String> scopes) async {
    if (clientId.isEmpty) {
      throw EmailException('Add your OAuth client ID in Settings first.');
    }
    if (kIsWeb) return _webSignIn(name, clientId, scopes.where((s) => s != 'offline_access').toList());
    try {
      final res = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientId,
          redirect,
          discoveryUrl: discovery,
          scopes: scopes,
          promptValues: const ['consent'],
        ),
      );
      await _saveTokens(name, res.accessToken, res.refreshToken,
          res.accessTokenExpirationDateTime);
    } on FlutterAppAuthUserCancelledException {
      throw EmailException('Sign-in was cancelled.');
    } catch (e) {
      throw EmailException('Sign-in failed: $e');
    }
  }

  /// Browser sign-in: a popup to Google / Microsoft that returns a short-lived
  /// access token (about an hour). The OAuth client must be a "Web
  /// application" (Google) / "Single-page application" (Microsoft) with
  /// [oauthRedirectUri] (this site's /oauth.html) as its redirect URI.
  Future<void> _webSignIn(String name, String clientId, List<String> scopes) async {
    final gmail = name == 'gmail';
    final url = Uri.https(
      gmail ? 'accounts.google.com' : 'login.microsoftonline.com',
      gmail ? '/o/oauth2/v2/auth' : '/common/oauth2/v2.0/authorize',
      {
        'client_id': clientId,
        'redirect_uri': oauthRedirectUri,
        'response_type': 'token',
        'scope': scopes.join(' '),
        'prompt': gmail ? 'consent' : 'select_account',
        'include_granted_scopes': 'true',
      },
    );
    Map<String, String>? res;
    try {
      res = await oauthPopup(url.toString());
    } catch (e) {
      throw EmailException('$e');
    }
    if (res == null) throw EmailException('Sign-in was cancelled.');
    if (res['error'] != null) {
      throw EmailException('Sign-in failed: ${res['error_description'] ?? res['error']}');
    }
    final token = res['access_token'];
    if (token == null) throw EmailException('Sign-in failed: no access token came back.');
    final secs = int.tryParse(res['expires_in'] ?? '') ?? 3600;
    await _saveTokens(name, token, null, DateTime.now().add(Duration(seconds: secs)));
  }

  Future<void> _saveTokens(
      String name, String? access, String? refresh, DateTime? expiry) async {
    final old = await _readTokens(name);
    await settings.writeSecret(
      'tokens_$name',
      jsonEncode({
        'access': access,
        'refresh': refresh ?? old?['refresh'],
        'expiry': expiry?.millisecondsSinceEpoch,
      }),
    );
  }

  Future<Map<String, dynamic>?> _readTokens(String name) async {
    final raw = await settings.readSecret('tokens_$name');
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Returns a fresh access token, refreshing it if it expired.
  Future<String> _accessToken(String name) async {
    final t = await _readTokens(name);
    if (t == null) throw EmailException('Please sign in to your email first.');
    final expiry = t['expiry'] == null
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.fromMillisecondsSinceEpoch(t['expiry'] as int);
    if (t['access'] != null &&
        expiry.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return t['access'] as String;
    }
    final refresh = t['refresh'] as String?;
    if (refresh == null || kIsWeb) {
      throw EmailException('Your email sign-in expired. Sign in again.');
    }
    final gmail = name == 'gmail';
    try {
      final res = await _appAuth.token(TokenRequest(
        gmail ? settings.googleClientId : settings.microsoftClientId,
        gmail ? googleRedirect : microsoftRedirect,
        discoveryUrl: gmail ? _googleDiscovery : _msDiscovery,
        refreshToken: refresh,
        scopes: gmail ? _googleScopes : _msScopes,
      ));
      await _saveTokens(name, res.accessToken, res.refreshToken,
          res.accessTokenExpirationDateTime);
      return res.accessToken!;
    } catch (_) {
      throw EmailException('Your email sign-in expired. Sign in again.');
    }
  }

  // ------------------------------------------------------------------
  // Fetch new mail
  // ------------------------------------------------------------------

  /// Unread inbox mail from the last week, newest first (for the mailbox).
  Future<List<EmailItem>> fetchNewEmails() => _fetch(unreadOnly: true, days: 7, max: maxEmails);

  /// Recent inbox mail, read or not, for the search index.
  Future<List<EmailItem>> fetchRecent({int days = 30, int max = 60}) =>
      _fetch(unreadOnly: false, days: days, max: max);

  Future<List<EmailItem>> _fetch({required bool unreadOnly, required int days, required int max}) async {
    final items = switch (settings.emailProvider) {
      EmailProvider.gmail => await _fetchGmail(unreadOnly, days, max),
      EmailProvider.outlook => await _fetchOutlook(unreadOnly, days, max),
      EmailProvider.none =>
        throw EmailException('Set up your mailbox in Settings first.'),
      _ => await _fetchImap(unreadOnly: unreadOnly, days: days, max: max),
    };
    items.sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
    return items.take(max).toList();
  }

  /// Plain-text digest that is sent to the AI for summarising.
  static String digest(List<EmailItem> items) {
    final b = StringBuffer('New unread emails:\n');
    for (var i = 0; i < items.length; i++) {
      final e = items[i];
      final snippet = e.snippet.length > 400
          ? '${e.snippet.substring(0, 400)}…'
          : e.snippet;
      b.writeln('${i + 1}. From: ${e.from}\n   Subject: ${e.subject}\n'
          '   Preview: $snippet');
    }
    return b.toString();
  }

  Future<List<EmailItem>> _fetchGmail(bool unreadOnly, int days, int max) async {
    final token = await _accessToken('gmail');
    final headers = {'Authorization': 'Bearer $token'};
    final listUrl = Uri.https(
        'gmail.googleapis.com', '/gmail/v1/users/me/messages', {
      'q': '${unreadOnly ? 'is:unread ' : ''}in:inbox newer_than:${days}d',
      'maxResults': '$max',
    });
    final list = await http.get(listUrl, headers: headers);
    _check(list);
    final ids = ((jsonDecode(list.body)['messages'] as List?) ?? [])
        .map((m) => m['id'] as String)
        .toList();
    final results = await Future.wait(ids.map((id) async {
      final url = Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/'
          'messages/$id?format=metadata&metadataHeaders=From'
          '&metadataHeaders=Subject&metadataHeaders=Date');
      final r = await http.get(url, headers: headers);
      _check(r);
      final m = jsonDecode(r.body);
      final hs = <String, String>{
        for (final h in (m['payload']?['headers'] as List? ?? []))
          (h['name'] as String).toLowerCase(): h['value'] as String
      };
      final ms = int.tryParse('${m['internalDate']}');
      final labels = (m['labelIds'] as List? ?? []).cast<String>();
      return EmailItem(
        id: 'gmail:$id',
        unread: labels.contains('UNREAD'),
        webLink: 'https://mail.google.com/mail/u/0/#all/${m['threadId'] ?? id}',
        from: _niceSender(hs['from'] ?? 'Someone'),
        subject: hs['subject'] ?? '(no subject)',
        snippet: _unescape(m['snippet'] as String? ?? ''),
        date: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
      );
    }));
    return results;
  }

  Future<List<EmailItem>> _fetchOutlook(bool unreadOnly, int days, int max) async {
    final token = await _accessToken('outlook');
    final since = DateTime.now().toUtc().subtract(Duration(days: days)).toIso8601String();
    final filter = unreadOnly
        ? 'isRead eq false and receivedDateTime ge $since'
        : 'receivedDateTime ge $since';
    final url = Uri.https('graph.microsoft.com', '/v1.0/me/mailFolders/inbox/messages', {
      '\$filter': filter,
      '\$top': '$max',
      '\$orderby': 'receivedDateTime desc',
      '\$select': 'id,from,subject,bodyPreview,receivedDateTime,isRead,webLink',
    });
    final r = await http.get(url, headers: {'Authorization': 'Bearer $token'});
    _check(r);
    final values = (jsonDecode(r.body)['value'] as List?) ?? [];
    return values.map((m) {
      final addr = m['from']?['emailAddress'];
      return EmailItem(
        id: 'outlook:${m['id']}',
        unread: m['isRead'] != true,
        webLink: m['webLink'] as String?,
        from: (addr?['name'] as String?)?.isNotEmpty == true
            ? addr['name'] as String
            : (addr?['address'] as String? ?? 'Someone'),
        subject: m['subject'] as String? ?? '(no subject)',
        snippet: m['bodyPreview'] as String? ?? '',
        date: DateTime.tryParse(m['receivedDateTime'] as String? ?? ''),
      );
    }).toList();
  }

  Future<List<EmailItem>> _fetchImap({bool testOnly = false, bool unreadOnly = true, int days = 7, int max = maxEmails}) async {
    final host = settings.imapHost.isNotEmpty
        ? settings.imapHost
        : settings.emailProvider.defaultImapHost;
    final pass = await settings.readSecret('imap_password') ?? '';
    if (host.isEmpty || settings.imapUser.isEmpty || pass.isEmpty) {
      throw EmailException('Fill in your email address and app password.');
    }
    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(host, settings.imapPort, isSecure: true);
      await client.login(settings.imapUser, pass);
      await client.selectInbox();
      if (testOnly) return [];

      final since = DateTime.now().subtract(Duration(days: days));
      const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final sinceStr = '${since.day}-${mon[since.month - 1]}-${since.year}';
      final search = await client.searchMessages(
          searchCriteria: unreadOnly ? 'UNSEEN SINCE $sinceStr' : 'SINCE $sinceStr');
      final seq = search.matchingSequence;
      if (seq == null || seq.isEmpty) return [];
      final all = seq.toList();
      final newest = all.sublist(all.length > max ? all.length - max : 0);

      // Envelope + size first, so huge emails with attachments are skipped.
      final heads = await client.fetchMessages(
          MessageSequence.fromIds(newest), '(UID FLAGS ENVELOPE RFC822.SIZE)');
      final out = <EmailItem>[];
      for (final m in heads.messages) {
        final env = m.envelope;
        final sender = env?.from?.isNotEmpty == true ? env!.from!.first : null;
        var snippet = '';
        final seqId = m.sequenceId;
        if (seqId != null && (m.size ?? 0) < 300000) {
          final full = await client.fetchMessages(
              MessageSequence.fromId(seqId), 'BODY.PEEK[]');
          if (full.messages.isNotEmpty) {
            final body = full.messages.first;
            snippet = body.decodeTextPlainPart() ??
                _stripHtml(body.decodeTextHtmlPart() ?? '');
          }
        }
        out.add(EmailItem(
          id: 'imap:${settings.imapUser}:${m.uid ?? seqId ?? env?.messageId ?? out.length}',
          unread: !m.isSeen,
          from: sender == null
              ? 'Someone'
              : ((sender.personalName?.isNotEmpty ?? false)
                  ? sender.personalName!
                  : sender.email),
          subject: env?.subject ?? '(no subject)',
          snippet: snippet.replaceAll(RegExp(r'\s+'), ' ').trim(),
          date: env?.date,
        ));
      }
      return out;
    } on ImapException catch (e) {
      throw EmailException('Mail server said: ${e.message ?? e}');
    } catch (e) {
      if (e is EmailException) rethrow;
      throw EmailException(
          "Couldn't open your mailbox. Check the address and app password.");
    } finally {
      try {
        await client.logout();
      } catch (_) {}
    }
  }

  void _check(http.Response r) {
    if (r.statusCode == 401) {
      throw EmailException('Your email sign-in expired. Sign in again.');
    }
    if (r.statusCode >= 400) {
      throw EmailException('Email service error (${r.statusCode}).');
    }
  }

  static String _niceSender(String raw) {
    final m = RegExp(r'^\s*"?([^"<]+?)"?\s*<').firstMatch(raw);
    return (m?.group(1) ?? raw).trim();
  }

  static String _unescape(String s) => s
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  static String _stripHtml(String html) => _unescape(html
      .replaceAll(RegExp(r'<(style|script)[^>]*>.*?</\1>', dotAll: true), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' '));
}
