import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cloud AI that writes the answers. The user picks one in Settings.
/// (New entries go at the end: the choice is saved by position.)
enum AiProvider { claude, openai, gemini, custom, cozy }

extension AiProviderInfo on AiProvider {
  String get label => switch (this) {
        AiProvider.claude => 'Claude (Anthropic)',
        AiProvider.openai => 'ChatGPT (OpenAI)',
        AiProvider.gemini => 'Gemini (Google)',
        AiProvider.custom => 'Other (OpenAI-compatible)',
        AiProvider.cozy => 'Cozy Pal AI (free)',
      };

  String get defaultModel => switch (this) {
        AiProvider.claude => 'claude-haiku-5-5',
        AiProvider.openai => 'gpt-5.4-mini',
        AiProvider.gemini => 'gemini-flash-latest',
        AiProvider.custom => '',
        AiProvider.cozy => 'nvidia/nemotron-3.5-super-vl:free',
      };

  /// Short line shown on the picker card.
  String get blurb => switch (this) {
        AiProvider.claude => 'Thoughtful, clear answers',
        AiProvider.openai => 'The ChatGPT models',
        AiProvider.gemini => "Google's fast Flash models",
        AiProvider.custom => 'OpenRouter, Groq, Ollama…',
        AiProvider.cozy => 'Free, no key: 10 min a day, 20 with an account',
      };

  String get shortName => switch (this) {
        AiProvider.claude => 'Claude',
        AiProvider.openai => 'ChatGPT',
        AiProvider.gemini => 'Gemini',
        AiProvider.custom => 'Other',
        AiProvider.cozy => 'Cozy Pal AI',
      };

  /// Where to create an API key.
  String get keyUrl => switch (this) {
        AiProvider.claude => 'https://console.anthropic.com/settings/keys',
        AiProvider.openai => 'https://platform.openai.com/api-keys',
        AiProvider.gemini => 'https://aistudio.google.com/apikey',
        AiProvider.custom => 'https://openrouter.ai/keys',
        AiProvider.cozy => 'https://openrouter.ai/nvidia/nemotron-3.5-super-vl:free',
      };

  String get keyHint => switch (this) {
        AiProvider.claude => 'sk-ant-…  (console.anthropic.com)',
        AiProvider.openai => 'sk-…  (platform.openai.com)',
        AiProvider.gemini => 'AIza…  (aistudio.google.com)',
        AiProvider.custom => 'Key for your provider (blank for local servers)',
        AiProvider.cozy => '',
      };
}

/// Where the mailbox reads from.
enum EmailProvider { none, gmail, outlook, yahoo, icloud, otherImap }

extension EmailProviderInfo on EmailProvider {
  String get label => switch (this) {
        EmailProvider.none => 'Not set up',
        EmailProvider.gmail => 'Gmail',
        EmailProvider.outlook => 'Outlook / Hotmail / Microsoft 365',
        EmailProvider.yahoo => 'Yahoo Mail',
        EmailProvider.icloud => 'iCloud Mail',
        EmailProvider.otherImap => 'Other (IMAP)',
      };

  String get shortName => switch (this) {
        EmailProvider.none => 'None',
        EmailProvider.gmail => 'Gmail',
        EmailProvider.outlook => 'Outlook',
        EmailProvider.yahoo => 'Yahoo',
        EmailProvider.icloud => 'iCloud',
        EmailProvider.otherImap => 'Other',
      };

  String get blurb => switch (this) {
        EmailProvider.none => '',
        EmailProvider.gmail => 'Sign in with Google',
        EmailProvider.outlook => 'Hotmail, Live, Microsoft 365',
        EmailProvider.yahoo => 'Uses an app password',
        EmailProvider.icloud => 'Uses an app-specific password',
        EmailProvider.otherImap => 'Any IMAP mailbox',
      };

  /// Where to create an app password (IMAP providers).
  String get passwordUrl => switch (this) {
        EmailProvider.yahoo => 'https://login.yahoo.com/account/security',
        EmailProvider.icloud => 'https://account.apple.com',
        _ => '',
      };

  bool get usesImap =>
      this == EmailProvider.yahoo ||
      this == EmailProvider.icloud ||
      this == EmailProvider.otherImap;

  String get defaultImapHost => switch (this) {
        EmailProvider.yahoo => 'imap.mail.yahoo.com',
        EmailProvider.icloud => 'imap.mail.me.com',
        _ => '',
      };
}

/// All user choices. Plain values live in SharedPreferences;
/// API keys, passwords and tokens live in the phone's secure keychain.
class SettingsService extends ChangeNotifier {
  static const _secure = FlutterSecureStorage();
  late SharedPreferences _p;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
  }

  // ---------- AI ----------
  AiProvider get aiProvider =>
      AiProvider.values[_p.getInt('ai_provider') ?? AiProvider.cozy.index]; // free built-in AI by default
  set aiProvider(AiProvider v) {
    _p.setInt('ai_provider', v.index);
    notifyListeners();
  }

  String modelFor(AiProvider p) =>
      _p.getString('ai_model_${p.name}') ?? p.defaultModel;
  Future<void> setModelFor(AiProvider p, String model) async {
    await _p.setString('ai_model_${p.name}', model.trim());
    notifyListeners();
  }

  /// Where the Cozy Pal server (the Cloudflare Pages site) lives. The web
  /// version uses its own address; the phone apps use this.
  String get cozyServer => kIsWeb
      ? Uri.base.origin
      : (_p.getString('cozy_server') ?? const String.fromEnvironment('COZY_SERVER', defaultValue: 'https://cozy-pal.pages.dev'));
  set cozyServer(String v) {
    _p.setString('cozy_server', v.trim().replaceAll(RegExp(r'/+$'), ''));
    notifyListeners();
  }

  String get customBaseUrl =>
      _p.getString('custom_base_url') ?? 'https://openrouter.ai/api/v1';
  set customBaseUrl(String v) {
    _p.setString('custom_base_url', v.trim());
    notifyListeners();
  }

  Future<String?> apiKeyFor(AiProvider p) => _secure.read(key: 'key_${p.name}');
  Future<void> setApiKeyFor(AiProvider p, String key) async {
    await _secure.write(key: 'key_${p.name}', value: key.trim());
    notifyListeners();
  }

  Future<void> clearApiKeyFor(AiProvider p) async {
    await _secure.delete(key: 'key_${p.name}');
    notifyListeners();
  }

  // ---------- Email ----------
  EmailProvider get emailProvider => EmailProvider
      .values[_p.getInt('email_provider') ?? EmailProvider.none.index];
  set emailProvider(EmailProvider v) {
    _p.setInt('email_provider', v.index);
    notifyListeners();
  }

  String get googleClientId => _p.getString('google_client_id') ?? '';
  set googleClientId(String v) => _p.setString('google_client_id', v.trim());

  String get microsoftClientId => _p.getString('ms_client_id') ?? '';
  set microsoftClientId(String v) => _p.setString('ms_client_id', v.trim());

  String get imapHost => _p.getString('imap_host') ?? '';
  set imapHost(String v) => _p.setString('imap_host', v.trim());

  int get imapPort => _p.getInt('imap_port') ?? 993;
  set imapPort(int v) => _p.setInt('imap_port', v);

  String get imapUser => _p.getString('imap_user') ?? '';
  set imapUser(String v) => _p.setString('imap_user', v.trim());

  Future<String?> readSecret(String name) => _secure.read(key: name);
  Future<void> writeSecret(String name, String? value) async {
    if (value == null) {
      await _secure.delete(key: name);
    } else {
      await _secure.write(key: name, value: value);
    }
  }

  /// When the mailbox was last summarised; only newer mail counts as "new".
  DateTime? get lastMailCheck {
    final ms = _p.getInt('last_mail_check');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  set lastMailCheck(DateTime? v) => v == null
      ? _p.remove('last_mail_check')
      : _p.setInt('last_mail_check', v.millisecondsSinceEpoch);

  // ---------- On-device models ----------
  String get needleRepo => _p.getString('needle_repo') ?? 'Cactus-Compute/needle3';
  set needleRepo(String v) => _p.setString('needle_repo', v.trim());

  String get whisperRepo =>
      _p.getString('whisper_repo') ?? 'Cactus-Compute/whisper-base';
  set whisperRepo(String v) => _p.setString('whisper_repo', v.trim());

  String get language => _p.getString('language') ?? 'en';
  set language(String v) {
    _p.setString('language', v);
    notifyListeners();
  }

  // ---------- Voice ----------
  double get speechRate => _p.getDouble('speech_rate') ?? 0.48;
  set speechRate(double v) {
    _p.setDouble('speech_rate', v);
    notifyListeners();
  }

  double get speechPitch => _p.getDouble('speech_pitch') ?? 1.25;
  set speechPitch(double v) {
    _p.setDouble('speech_pitch', v);
    notifyListeners();
  }

  // ---------- Characters ----------
  String get characterId => _p.getString('character') ?? 'cat';
  set characterId(String v) {
    _p.setString('character', v);
    notifyListeners();
  }

  /// Fish treats: earned by every interaction, used to unlock friends.
  int get treats => _p.getInt('treats') ?? 0;
  void addTreats(int n) {
    _p.setInt('treats', treats + n);
    notifyListeners();
  }
}
