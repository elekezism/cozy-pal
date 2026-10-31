import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../platform/platform.dart';

/// How a message goes out.
enum MessageChannel { text, whatsapp, email }

extension MessageChannelInfo on MessageChannel {
  String get label => switch (this) {
        MessageChannel.text => 'Text',
        MessageChannel.whatsapp => 'WhatsApp',
        MessageChannel.email => 'Email',
      };
}

/// One way to reach a person (a phone number or an email address).
class ContactRoute {
  ContactRoute({required this.value, required this.label, required this.isEmail});
  final String value;
  final String label; // "mobile", "work", "home"…
  final bool isEmail;
}

class ContactMatch {
  ContactMatch({required this.name, required this.phones, required this.emails});
  final String name;
  final List<ContactRoute> phones;
  final List<ContactRoute> emails;
}

/// A message the pet drafted. Nothing is sent until the user taps Send,
/// and even then it opens the user's own Messages / WhatsApp / Mail app
/// with everything filled in.
class MessageDraft {
  MessageDraft({required this.recipientName, required this.body, required this.channel, this.subject = ''});
  String recipientName;
  String body;
  String subject;
  MessageChannel channel;
  ContactMatch? contact;
  String? to; // chosen phone number or email address
}

class StoreApp {
  StoreApp({required this.name, required this.seller, required this.url, this.iconUrl, this.price, this.rating});
  final String name;
  final String seller;
  final String url;
  final String? iconUrl;
  final String? price;
  final double? rating;
}

class ActionsException implements Exception {
  ActionsException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Things the pet can do outside the app: draft messages to friends and
/// find apps in the store.
class ActionsService {
  List<Contact>? _contacts;

  // ------------------------------------------------------------------ contacts

  /// Browsers can't read your contacts: there you type the number or email.
  static bool get hasContacts => !kIsWeb;

  Future<bool> _loadContacts() async {
    if (kIsWeb) return false;
    if (_contacts != null) return true;
    if (!await FlutterContacts.requestPermission()) return false;
    _contacts = await FlutterContacts.getContacts(withProperties: true);
    return true;
  }

  /// Contacts whose name matches what the user said ("Ana", "mom", "Sam R").
  /// Throws if contacts permission was refused.
  Future<List<ContactMatch>> findContacts(String spokenName) async {
    if (!await _loadContacts()) {
      if (kIsWeb) return [];
      throw ActionsException('I need permission to see your contacts. You can still pick someone by hand.');
    }
    final q = _norm(spokenName);
    if (q.isEmpty) return [];
    final scored = <(int, Contact)>[];
    for (final c in _contacts!) {
      final names = {
        _norm(c.displayName),
        _norm(c.name.first),
        _norm(c.name.nickname),
        _norm('${c.name.first} ${c.name.last}'),
      }..remove('');
      var best = 0;
      for (final n in names) {
        if (n == q) {
          best = 3;
        } else if (n.split(' ').contains(q) && best < 2) {
          best = 2;
        } else if ((n.startsWith(q) || q.startsWith(n)) && q.length >= 3 && best < 1) {
          best = 1;
        }
      }
      if (best > 0) scored.add((best, c));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    final top = scored.isEmpty ? 0 : scored.first.$1;
    return scored.where((s) => s.$1 == top).take(5).map((s) => _toMatch(s.$2)).toList();
  }

  /// Opens the phone's own contact picker.
  Future<ContactMatch?> pickContact() async {
    if (kIsWeb) throw ActionsException("The browser can't open your contacts. Type their number or email instead.");
    if (!await FlutterContacts.requestPermission()) {
      throw ActionsException('Contacts permission is off. Allow it in your phone settings.');
    }
    final c = await FlutterContacts.openExternalPick();
    return c == null ? null : _toMatch(c);
  }

  ContactMatch _toMatch(Contact c) => ContactMatch(
        name: c.displayName,
        phones: [
          for (final p in c.phones)
            ContactRoute(value: p.normalizedNumber.isNotEmpty ? p.normalizedNumber : p.number, label: p.label.name, isEmail: false)
        ],
        emails: [for (final e in c.emails) ContactRoute(value: e.address, label: e.label.name, isEmail: true)],
      );

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9à-ÿ' ]"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  // ------------------------------------------------------------------ sending

  /// Opens Messages / WhatsApp / Mail with the draft filled in.
  /// The user presses send there.
  Future<void> openComposer(MessageDraft d) async {
    final to = d.to ?? '';
    final Uri uri;
    switch (d.channel) {
      case MessageChannel.text:
        final number = to.replaceAll(RegExp(r'[^0-9+]'), '');
        // iOS wants "sms:NUMBER&body=", Android "sms:NUMBER?body="
        final sep = isIOS ? '&' : '?';
        uri = Uri.parse('sms:$number${sep}body=${Uri.encodeComponent(d.body)}');
      case MessageChannel.whatsapp:
        final digits = to.replaceAll(RegExp(r'[^0-9]'), '');
        uri = Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(d.body)}');
      case MessageChannel.email:
        // percent-encoding (not "+") so mail apps show spaces correctly
        uri = Uri.parse('mailto:${Uri.encodeComponent(to).replaceAll('%40', '@')}'
            '?subject=${Uri.encodeComponent(d.subject)}&body=${Uri.encodeComponent(d.body)}');
    }
    if (!await _open(uri)) {
      throw ActionsException(switch (d.channel) {
        MessageChannel.text => "I couldn't open your messages app.",
        MessageChannel.whatsapp => "I couldn't open WhatsApp. Is it installed?",
        MessageChannel.email => "I couldn't open your mail app. Is one set up on this phone?",
      });
    }
  }

  static Future<bool> _open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------ apps

  /// Finds apps by name. On iPhone this uses Apple's public App Store search,
  /// so you can pick the exact app. On Android there is no public Play Store
  /// search, so this returns nothing and [openStoreSearch] is used instead.
  Future<List<StoreApp>> searchApps(String name) async {
    // iPhone app, or the web (shown as "App Store" picks) — not Android
    if (isAndroid) return [];
    final country = (ui.PlatformDispatcher.instance.locale.countryCode ?? 'US').toLowerCase();
    final url = Uri.https('itunes.apple.com', '/search', {
      'term': name,
      'entity': 'software',
      'limit': '4',
      'country': country,
    });
    try {
      final res = await http.get(viaProxy(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];
      final results = (jsonDecode(res.body)['results'] as List? ?? []);
      return [
        for (final r in results)
          StoreApp(
            name: r['trackName'] as String? ?? name,
            seller: r['sellerName'] as String? ?? '',
            url: kIsWeb ? (r['trackViewUrl'] as String? ?? 'https://apps.apple.com/app/id${r['trackId']}') : 'itms-apps://apps.apple.com/app/id${r['trackId']}',
            iconUrl: r['artworkUrl100'] == null ? null : viaProxy(Uri.parse(r['artworkUrl100'] as String)).toString(),
            price: r['formattedPrice'] as String?,
            rating: (r['averageUserRating'] as num?)?.toDouble(),
          )
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> openStoreApp(StoreApp app) async {
    if (!await _open(Uri.parse(app.url))) {
      throw ActionsException("I couldn't open the App Store.");
    }
  }

  /// Opens the store's search for [name] (Play Store on Android).
  Future<void> openStoreSearch(String name) async {
    final q = Uri.encodeComponent(name);
    final tries = kIsWeb
        ? ['https://apps.apple.com/us/search?term=$q', 'https://play.google.com/store/search?q=$q&c=apps']
        : isIOS
        ? ['itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?media=software&term=$q', 'https://apps.apple.com/search?term=$q']
        : ['market://search?q=$q&c=apps', 'https://play.google.com/store/search?q=$q&c=apps'];
    for (final t in tries) {
      if (await _open(Uri.parse(t))) return;
    }
    throw ActionsException("I couldn't open the app store.");
  }
}
