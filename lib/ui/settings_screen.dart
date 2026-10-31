import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/model_manager.dart';
import '../pet_controller.dart';
import '../platform/oauth.dart';
import '../services/cheer_service.dart';
import '../services/email_service.dart';
import '../services/settings_service.dart';
import '../services/voice_service.dart';
import 'doodle.dart';

/// Settings, drawn in the same hand-made style as the room:
/// pick the AI that writes answers (and add its key), pick the mailbox,
/// download the on-device models and tune the pet's voice.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.pet, this.focusEmail = false});
  final PetController pet;
  final bool focusEmail;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _mailKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.focusEmail) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _mailKey.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pet = widget.pet;
    return Theme(
      data: Theme.of(context).copyWith(inputDecorationTheme: _inputTheme),
      child: Scaffold(
        backgroundColor: Pal.sky,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(children: [
                DoodleButton(
                  tooltip: 'Back',
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Icon(Icons.arrow_back_rounded, color: ink),
                ),
                const SizedBox(width: 14),
                const Text('SETTINGS', style: TextStyle(fontFamily: handFont, fontSize: 28, color: ink, letterSpacing: 1.2)),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
                children: [
                  _StatusStrip(pet: pet),
                  _AiSection(pet: pet),
                  _MailSection(key: _mailKey, pet: pet),
                  _ModelsSection(pet: pet),
                  _VoiceSection(pet: pet),
                  _TasteSection(pet: pet),
                  const SizedBox(height: 16),
                  Text(
                    'Your notes and recordings stay on this phone. Questions and email previews go only to '
                    'the AI service you pick. Keys and passwords are kept in the phone\'s secure keychain.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: handFont, color: ink.withValues(alpha: 0.7), fontSize: 15, height: 1.25),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ======================================================================
// shared bits
// ======================================================================

const _hand = TextStyle(fontFamily: handFont, color: ink, fontSize: 18, height: 1.2);

final _inputTheme = InputDecorationTheme(
  filled: true,
  fillColor: Colors.white,
  isDense: true,
  labelStyle: _hand.copyWith(color: ink.withValues(alpha: 0.75)),
  floatingLabelStyle: _hand,
  hintStyle: _hand.copyWith(color: ink.withValues(alpha: 0.4)),
  helperStyle: _hand.copyWith(fontSize: 14, color: ink.withValues(alpha: 0.65)),
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: ink, width: 2)),
  enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: ink, width: 2)),
  focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Color(0xFF4E7A3E), width: 2.6)),
);

void _toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: _hand.copyWith(color: Colors.white))));

Future<void> _open(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!ok && context.mounted) {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) _toast(context, 'Link copied: $url');
  }
}

/// A section card with a hand-lettered title.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.children, this.subtitle, this.seed = 1});
  final String title;
  final IconData icon;
  final String? subtitle;
  final List<Widget> children;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: DoodleBox(
        seed: seed,
        radius: 20,
        shadow: 4,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, color: ink, size: 24),
            const SizedBox(width: 8),
            Flexible(child: Text(title.toUpperCase(), style: _hand.copyWith(fontSize: 22, letterSpacing: 1))),
          ]),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: _hand.copyWith(fontSize: 16, color: ink.withValues(alpha: 0.75))),
          ],
          const SizedBox(height: 12),
          ...children,
        ]),
      ),
    );
  }
}

/// A chunky, tappable choice card used for both pickers.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.blurb,
    required this.selected,
    required this.onTap,
    required this.color,
    required this.badge,
    this.done = false,
  });
  final String title;
  final String blurb;
  final bool selected;
  final bool done;
  final VoidCallback onTap;
  final Color color;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $blurb${done ? '. Connected' : ''}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.35) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ink, width: selected ? 3 : 2),
            boxShadow: [BoxShadow(color: ink, offset: Offset(0, selected ? 1 : 3))],
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: ink, width: 2)),
              child: Text(badge, style: _hand.copyWith(fontSize: 20)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(title, style: _hand.copyWith(fontSize: 19), overflow: TextOverflow.ellipsis)),
                  if (done) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.check_circle, size: 18, color: Color(0xFF4E7A3E))),
                ]),
                Text(blurb, style: _hand.copyWith(fontSize: 14, color: ink.withValues(alpha: 0.7)), maxLines: 2),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Two choice cards per row on phones, three on wider screens.
class _ChoiceGrid extends StatelessWidget {
  const _ChoiceGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth > 520 ? 3 : 2;
      const gap = 10.0;
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final c in children) SizedBox(width: w, child: c)],
      );
    });
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap, this.icon, this.color = Pal.sage, this.busy = false});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled || busy ? 1 : 0.5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: ink, width: 2.2),
              boxShadow: const [BoxShadow(color: ink, offset: Offset(0, 3))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              if (busy)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: ink))
              else if (icon != null)
                Icon(icon, color: ink, size: 20),
              if (busy || icon != null) const SizedBox(width: 8),
              Flexible(child: Text(label, style: _hand.copyWith(fontSize: 18), overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _LinkLine extends StatelessWidget {
  const _LinkLine({required this.lead, required this.url});
  final String lead;
  final String url;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context, url),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          const Icon(Icons.open_in_new_rounded, size: 18, color: Color(0xFF3B6FA0)),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '$lead '),
                TextSpan(
                  text: Uri.parse(url).host,
                  style: const TextStyle(color: Color(0xFF3B6FA0), decoration: TextDecoration.underline),
                ),
              ]),
              style: _hand.copyWith(fontSize: 16),
            ),
          ),
        ]),
      ),
    );
  }
}

// ======================================================================
// status strip
// ======================================================================

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.pet});
  final PetController pet;

  Future<(bool, bool)> _check() async {
    final key = await pet.settings.apiKeyFor(pet.settings.aiProvider) ?? '';
    final ai = key.isNotEmpty || pet.settings.aiProvider == AiProvider.custom;
    final mail = await pet.email.isSignedIn();
    return (ai, mail);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([pet.settings, pet.localAi]),
      builder: (context, _) => FutureBuilder<(bool, bool)>(
        future: _check(),
        builder: (context, snap) {
          final ai = snap.data?.$1 ?? false;
          final mail = snap.data?.$2 ?? false;
          final speech = pet.canListen;
          Widget chip(String label, bool ok) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: ok ? const Color(0xFFE6F2D2) : Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: ink, width: 1.8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(ok ? Icons.check_rounded : Icons.circle_outlined, size: 16, color: ok ? const Color(0xFF4E7A3E) : ink),
                  const SizedBox(width: 4),
                  Text(label, style: _hand.copyWith(fontSize: 16)),
                ]),
              );
          return Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            chip(ai ? 'Answers: ${pet.settings.aiProvider.shortName}' : 'Answers: add a key', ai),
            chip(mail ? 'Mail: ${pet.settings.emailProvider.shortName}' : 'Mail: not set up', mail),
            chip(speech ? 'Voice notes: ready' : 'Voice notes: audio only', speech),
          ]);
        },
      ),
    );
  }
}

// ======================================================================
// AI provider
// ======================================================================

class _AiSection extends StatefulWidget {
  const _AiSection({required this.pet});
  final PetController pet;
  @override
  State<_AiSection> createState() => _AiSectionState();
}

class _AiSectionState extends State<_AiSection> {
  final _key = TextEditingController();
  final _model = TextEditingController();
  final _base = TextEditingController();
  final Map<AiProvider, bool> _hasKey = {};
  bool _showKey = false;
  bool _testing = false;

  SettingsService get s => widget.pet.settings;

  static const _colors = {
    AiProvider.claude: Color(0xFFF2B98B),
    AiProvider.openai: Pal.mint,
    AiProvider.gemini: Pal.blue,
    AiProvider.custom: Pal.lilac,
  };
  static const _badges = {
    AiProvider.claude: 'C',
    AiProvider.openai: 'G',
    AiProvider.gemini: '✦',
    AiProvider.custom: '…',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    _base.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    for (final p in AiProvider.values) {
      _hasKey[p] = (await s.apiKeyFor(p) ?? '').isNotEmpty;
    }
    if (!mounted) return;
    final p = s.aiProvider;
    setState(() {
      _key.clear();
      _showKey = false;
      _model.text = s.modelFor(p);
      _base.text = s.customBaseUrl;
    });
  }

  Future<void> _save() async {
    final p = s.aiProvider;
    if (_key.text.trim().isNotEmpty) await s.setApiKeyFor(p, _key.text);
    await s.setModelFor(p, _model.text);
    if (p == AiProvider.custom) s.customBaseUrl = _base.text;
    await _load();
  }

  Future<void> _removeKey() async {
    await s.clearApiKeyFor(s.aiProvider);
    await _load();
    if (mounted) _toast(context, 'Key removed');
  }

  Future<void> _pickModel() async {
    await _save();
    try {
      final models = await widget.pet.llm.listModels(s.aiProvider);
      if (!mounted) return;
      final picked = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Pal.cream,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: ink, width: 2),
        ),
        builder: (c) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text('CHOOSE A MODEL', style: _hand.copyWith(fontSize: 22, letterSpacing: 1)),
            ),
            if (models.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('No models found for this key.', style: _hand)),
            for (final m in models)
              ListTile(
                title: Text(m, style: _hand),
                trailing: m == _model.text ? const Icon(Icons.check_rounded, color: ink) : null,
                onTap: () => Navigator.pop(c, m),
              ),
          ]),
        ),
      );
      if (picked != null) {
        _model.text = picked;
        await _save();
      }
    } catch (e) {
      if (mounted) _toast(context, '$e');
    }
  }

  Future<void> _test() async {
    await _save();
    setState(() => _testing = true);
    try {
      final a = await widget.pet.llm.answer('Say hello to me in one short, cheerful sentence.');
      if (mounted) _toast(context, 'It works! "$a"');
    } catch (e) {
      if (mounted) _toast(context, '$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = s.aiProvider;
    final hasKey = _hasKey[p] ?? false;
    return _Section(
      title: 'AI for answers',
      icon: Icons.menu_book_rounded,
      subtitle: 'The bookshelf and mailbox ask this AI. Answers are kept to 3 short sentences.',
      seed: 21,
      children: [
        _ChoiceGrid(children: [
          for (final a in AiProvider.values)
            _ChoiceCard(
              title: a.shortName,
              blurb: a.blurb,
              badge: _badges[a]!,
              color: _colors[a]!,
              selected: a == p,
              done: _hasKey[a] ?? false,
              onTap: () async {
                await _save();
                s.aiProvider = a;
                await _load();
              },
            ),
        ]),
        const SizedBox(height: 14),
        if (p == AiProvider.custom) ...[
          TextField(
            controller: _base,
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: _hand,
            decoration: const InputDecoration(
              labelText: 'Server address',
              helperText: 'Any OpenAI-compatible URL, e.g. https://api.groq.com/openai/v1',
            ),
            onEditingComplete: _save,
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _key,
          obscureText: !_showKey,
          autocorrect: false,
          enableSuggestions: false,
          style: _hand,
          decoration: InputDecoration(
            labelText: hasKey ? '${p.shortName} API key  •  saved ✓' : '${p.shortName} API key',
            hintText: hasKey ? 'Type a new key to replace it' : p.keyHint,
            suffixIcon: IconButton(
              tooltip: _showKey ? 'Hide key' : 'Show key',
              icon: Icon(_showKey ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: ink),
              onPressed: () => setState(() => _showKey = !_showKey),
            ),
          ),
          onEditingComplete: _save,
        ),
        _LinkLine(lead: p == AiProvider.custom ? 'For OpenRouter, get a key at' : 'Get a key at', url: p.keyUrl),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _model,
              autocorrect: false,
              style: _hand,
              decoration: const InputDecoration(labelText: 'Model'),
              onEditingComplete: _save,
            ),
          ),
          const SizedBox(width: 8),
          _PillButton(label: 'Choose', color: Colors.white, onTap: _pickModel),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _PillButton(label: 'Save & test', icon: Icons.check_circle_outline_rounded, busy: _testing, onTap: _test),
          if (hasKey) _PillButton(label: 'Remove key', icon: Icons.delete_outline_rounded, color: Colors.white, onTap: _removeKey),
        ]),
      ],
    );
  }
}

// ======================================================================
// Email
// ======================================================================

class _MailSection extends StatefulWidget {
  const _MailSection({super.key, required this.pet});
  final PetController pet;
  @override
  State<_MailSection> createState() => _MailSectionState();
}

class _MailSectionState extends State<_MailSection> {
  final _clientId = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _signedIn = false;
  bool _working = false;
  bool _showPass = false;

  SettingsService get s => widget.pet.settings;
  EmailService get mail => widget.pet.email;

  static const _choices = [
    EmailProvider.gmail,
    EmailProvider.outlook,
    EmailProvider.yahoo,
    EmailProvider.icloud,
    EmailProvider.otherImap,
  ];
  static const _colors = {
    EmailProvider.gmail: Color(0xFFF4B6B0),
    EmailProvider.outlook: Pal.blue,
    EmailProvider.yahoo: Pal.lilac,
    EmailProvider.icloud: Color(0xFFD6E6F2),
    EmailProvider.otherImap: Pal.note,
  };
  static const _badges = {
    EmailProvider.gmail: 'G',
    EmailProvider.outlook: 'O',
    EmailProvider.yahoo: 'Y',
    EmailProvider.icloud: '☁',
    EmailProvider.otherImap: '@',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_clientId, _host, _port, _user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final p = s.emailProvider;
    _clientId.text = p == EmailProvider.gmail ? s.googleClientId : s.microsoftClientId;
    _host.text = s.imapHost.isNotEmpty ? s.imapHost : p.defaultImapHost;
    _port.text = '${s.imapPort}';
    _user.text = s.imapUser;
    _pass.clear();
    final signed = await mail.isSignedIn();
    if (mounted) setState(() => _signedIn = signed);
  }

  Future<void> _pick(EmailProvider v) async {
    if (v == s.emailProvider) return;
    await mail.disconnect();
    await widget.pet.memory.clearMail();
    s.emailProvider = v;
    if (v.usesImap) {
      s.imapHost = v.defaultImapHost;
      s.imapPort = 993;
    }
    await _load();
  }

  Future<void> _connect() async {
    final p = s.emailProvider;
    if (p == EmailProvider.gmail) s.googleClientId = _clientId.text;
    if (p == EmailProvider.outlook) s.microsoftClientId = _clientId.text;
    if (p.usesImap) {
      s.imapHost = p == EmailProvider.otherImap ? _host.text : p.defaultImapHost;
      s.imapPort = int.tryParse(_port.text) ?? 993;
      s.imapUser = _user.text;
      if (_pass.text.isNotEmpty) await s.writeSecret('imap_password', _pass.text);
    }
    setState(() => _working = true);
    try {
      final msg = await mail.connect();
      widget.pet.memory.syncMail(force: true);
      if (mounted) _toast(context, msg);
    } catch (e) {
      if (p.usesImap) await s.writeSecret('imap_password', null);
      if (mounted) _toast(context, '$e');
    } finally {
      await _load();
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _disconnect() async {
    await mail.disconnect();
    await widget.pet.memory.clearMail();
    await _load();
    if (mounted) _toast(context, 'Mailbox disconnected');
  }

  Future<void> _turnOff() async {
    await mail.disconnect();
    await widget.pet.memory.clearMail();
    s.emailProvider = EmailProvider.none;
    await _load();
  }

  Widget _help(EmailProvider p) {
    switch (p) {
      case EmailProvider.gmail when kIsWeb:
        return Text(
          'Paste an OAuth client ID of type "Web application" from your Google Cloud project (Gmail API on). '
          'Authorized JavaScript origin: ${Uri.base.origin}, redirect URI: $oauthRedirectUri. '
          'In the browser you sign in again about once an hour.',
          style: _hand.copyWith(fontSize: 15, color: ink.withValues(alpha: 0.75)),
        );
      case EmailProvider.outlook when kIsWeb:
        return Text(
          'Paste the Application (client) ID from Microsoft Entra. Add a "Single-page application" platform with '
          'redirect URI $oauthRedirectUri, tick "Access tokens", permission: Mail.Read.',
          style: _hand.copyWith(fontSize: 15, color: ink.withValues(alpha: 0.75)),
        );
      case EmailProvider.gmail:
        return Text(
          'Paste the OAuth client ID from your Google Cloud project (Gmail API on, iOS client with '
          'bundle ID com.cozypal.app). README → "Connect email" has the steps.',
          style: _hand.copyWith(fontSize: 15, color: ink.withValues(alpha: 0.75)),
        );
      case EmailProvider.outlook:
        return Text(
          'Paste the Application (client) ID from Microsoft Entra. Redirect URI: '
          '${EmailService.microsoftRedirect}, permission: Mail.Read.',
          style: _hand.copyWith(fontSize: 15, color: ink.withValues(alpha: 0.75)),
        );
      case EmailProvider.yahoo:
      case EmailProvider.icloud:
        return _LinkLine(lead: 'Make an app password at', url: p.passwordUrl);
      case EmailProvider.otherImap:
        return Text('Most providers need an "app password" for IMAP. The port is usually 993.',
            style: _hand.copyWith(fontSize: 15, color: ink.withValues(alpha: 0.75)));
      case EmailProvider.none:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = s.emailProvider;
    return _Section(
      title: 'Mailbox',
      icon: Icons.markunread_mailbox_rounded,
      subtitle: 'Your pet reads only unread mail. It never sends, deletes or marks anything.',
      seed: 33,
      children: [
        _ChoiceGrid(children: [
          for (final e in _choices)
            if (!kIsWeb || !e.usesImap) // IMAP needs a raw socket: phone app only
            _ChoiceCard(
              title: e.shortName,
              blurb: e.blurb,
              badge: _badges[e]!,
              color: _colors[e]!,
              selected: e == p,
              done: e == p && _signedIn,
              onTap: () => _pick(e),
            ),
        ]),
        if (p == EmailProvider.none) ...[
          const SizedBox(height: 10),
          Text('Pick where your email lives to turn on the mailbox.',
              style: _hand.copyWith(fontSize: 16, color: ink.withValues(alpha: 0.75))),
        ] else ...[
          const SizedBox(height: 14),
          if (_signedIn)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F2D2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ink, width: 2),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle, color: Color(0xFF4E7A3E)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.usesImap ? '${p.shortName} connected as ${s.imapUser}' : '${p.shortName} connected',
                    style: _hand,
                  ),
                ),
                TextButton(onPressed: _disconnect, child: Text('Disconnect', style: _hand.copyWith(fontSize: 16))),
              ]),
            )
          else ...[
            _help(p),
            const SizedBox(height: 10),
            if (p == EmailProvider.gmail || p == EmailProvider.outlook)
              TextField(
                controller: _clientId,
                autocorrect: false,
                style: _hand,
                decoration: const InputDecoration(labelText: 'OAuth client ID'),
              ),
            if (p.usesImap) ...[
              TextField(
                controller: _user,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                style: _hand,
                decoration: const InputDecoration(labelText: 'Email address'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pass,
                obscureText: !_showPass,
                autocorrect: false,
                enableSuggestions: false,
                style: _hand,
                decoration: InputDecoration(
                  labelText: 'App password',
                  suffixIcon: IconButton(
                    tooltip: _showPass ? 'Hide password' : 'Show password',
                    icon: Icon(_showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: ink),
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                ),
              ),
              if (p == EmailProvider.otherImap) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _host,
                      autocorrect: false,
                      style: _hand,
                      decoration: const InputDecoration(labelText: 'IMAP server'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      style: _hand,
                      decoration: const InputDecoration(labelText: 'Port'),
                    ),
                  ),
                ]),
              ],
            ],
            const SizedBox(height: 14),
            _PillButton(
              label: p.usesImap ? 'Connect' : 'Sign in to ${p.shortName}',
              icon: Icons.login_rounded,
              busy: _working,
              onTap: _connect,
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _turnOff,
              child: Text('Turn off mailbox', style: _hand.copyWith(fontSize: 15, color: ink.withValues(alpha: 0.7))),
            ),
          ),
        ],
      ],
    );
  }
}

// ======================================================================
// On-device models
// ======================================================================

class _ModelsSection extends StatelessWidget {
  const _ModelsSection({required this.pet});
  final PetController pet;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([pet.models, pet.localAi, pet.settings]),
      builder: (context, _) => _Section(
        title: 'On-device AI',
        icon: Icons.eco_rounded,
        subtitle: 'Small Cactus models that run privately on your phone. Download once, ideally on Wi-Fi.',
        seed: 45,
        children: [
          if (kIsWeb)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE7C2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ink, width: 1.6),
              ),
              child: Text(
                'You\'re using the web version. Needle and Whisper run in the phone app; here your pet uses keyword '
                'matching, and your browser\'s speech recognition for talking and notes '
                '(${VoiceService.browserCanListen ? 'available in this browser' : 'not available in this browser — try Chrome, Edge or Safari'}).',
                style: _hand.copyWith(fontSize: 15),
              ),
            )
          else if (!pet.localAi.engineAvailable)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE7C2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ink, width: 1.6),
              ),
              child: Text(
                'This build doesn\'t include the Cactus engine yet, so simple keyword matching is used instead of '
                'Needle, and voice notes are saved as audio only. README → "Add the Cactus engine".',
                style: _hand.copyWith(fontSize: 15),
              ),
            ),
          if (!kIsWeb) ...[
            _ModelTile(pet: pet, kind: LocalModelKind.needle, title: 'Needle 3: understands requests',
                ready: pet.localAi.needleReady, repo: pet.settings.needleRepo),
            const Divider(height: 22, color: ink, thickness: 1),
            _ModelTile(pet: pet, kind: LocalModelKind.whisper, title: 'Whisper: speech to text',
                ready: pet.localAi.whisperReady, repo: pet.settings.whisperRepo),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: pet.settings.language,
            style: _hand,
            decoration: const InputDecoration(labelText: 'Language you speak'),
            items: const [
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(value: 'es', child: Text('Español')),
              DropdownMenuItem(value: 'fr', child: Text('Français')),
              DropdownMenuItem(value: 'de', child: Text('Deutsch')),
              DropdownMenuItem(value: 'it', child: Text('Italiano')),
              DropdownMenuItem(value: 'pt', child: Text('Português')),
              DropdownMenuItem(value: 'vi', child: Text('Tiếng Việt')),
              DropdownMenuItem(value: 'ja', child: Text('日本語')),
              DropdownMenuItem(value: 'ko', child: Text('한국어')),
              DropdownMenuItem(value: 'zh', child: Text('中文')),
            ],
            onChanged: (v) => pet.settings.language = v ?? 'en',
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Advanced: model sources', style: _hand.copyWith(fontSize: 16)),
              children: [
                TextFormField(
                  initialValue: pet.settings.needleRepo,
                  style: _hand,
                  decoration: const InputDecoration(labelText: 'Needle Hugging Face repo'),
                  onChanged: (v) => pet.settings.needleRepo = v,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: pet.settings.whisperRepo,
                  style: _hand,
                  decoration: const InputDecoration(
                    labelText: 'Whisper repo',
                    helperText: 'whisper-tiny is smaller, whisper-small is more accurate',
                  ),
                  onChanged: (v) => pet.settings.whisperRepo = v,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({required this.pet, required this.kind, required this.title, required this.ready, required this.repo});
  final PetController pet;
  final LocalModelKind kind;
  final String title;
  final bool ready;
  final String repo;

  Future<void> _download(BuildContext context) async {
    try {
      await pet.localAi.unload(kind);
      await pet.models.download(kind, repo);
      await pet.localAi.loadModels();
      if (context.mounted) _toast(context, pet.localAi.engineAvailable ? 'Downloaded and ready!' : 'Downloaded.');
    } catch (e) {
      if (context.mounted) _toast(context, 'Download failed: $e');
    }
  }

  Future<void> _remove() async {
    await pet.localAi.unload(kind);
    await pet.models.remove(kind);
  }

  @override
  Widget build(BuildContext context) {
    final progress = pet.models.progress[kind];
    final engine = pet.localAi.engineAvailable;
    return FutureBuilder<String?>(
      future: pet.models.modelPath(kind),
      builder: (context, snap) {
        final downloaded = snap.data != null;
        final status = progress != null
            ? 'Downloading… ${(progress * 100).round()}%'
            : ready
                ? 'Ready ✓'
                : downloaded
                    ? (engine ? 'Downloaded, but it failed to load' : 'Downloaded (engine missing)')
                    : 'Not downloaded';
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: _hand),
                Text(status, style: _hand.copyWith(fontSize: 15, color: ink.withValues(alpha: 0.65))),
              ]),
            ),
            if (progress == null)
              downloaded
                  ? IconButton(tooltip: 'Remove', onPressed: _remove, icon: const Icon(Icons.delete_outline_rounded, color: ink))
                  : _PillButton(label: 'Download', color: Pal.mustard, onTap: () => _download(context)),
          ]),
          if (progress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: Pal.sageDark,
              backgroundColor: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ]);
      },
    );
  }
}

// ======================================================================
// Voice
// ======================================================================

class _VoiceSection extends StatelessWidget {
  const _VoiceSection({required this.pet});
  final PetController pet;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pet.settings,
      builder: (context, _) => _Section(
        title: 'Pet voice',
        icon: Icons.record_voice_over_rounded,
        seed: 57,
        children: [
          Text('Speed', style: _hand.copyWith(fontSize: 16)),
          Slider(
            value: pet.settings.speechRate,
            min: 0.25,
            max: 0.75,
            activeColor: Pal.sageDark,
            onChanged: (v) => pet.settings.speechRate = v,
          ),
          Text('Pitch', style: _hand.copyWith(fontSize: 16)),
          Slider(
            value: pet.settings.speechPitch,
            min: 0.7,
            max: 1.8,
            activeColor: Pal.sageDark,
            onChanged: (v) => pet.settings.speechPitch = v,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _PillButton(
              label: 'Hear my voice',
              icon: Icons.volume_up_rounded,
              color: Colors.white,
              onTap: () => pet.voice.say('Hi! I am ${pet.character.name}. Nice to meet you!'),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// What the pet knows about you (for cheering you up)
// ======================================================================

class _TasteSection extends StatelessWidget {
  const _TasteSection({required this.pet});
  final PetController pet;

  static String _type(String t) => switch (t) {
        'artist' => 'Artist',
        'genre' => 'Genre',
        'tag' => 'Game tag',
        _ => 'Topic',
      };

  static String _nice(String s) => s.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

  @override
  Widget build(BuildContext context) {
    final c = pet.cheer;
    final e = c.engine;
    final name = pet.character.name.split(' ').first;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final top = e.top(limit: 15);
        final dislikes = e.dislikes;
        final kinds = [for (final k in CheerKind.values) (k, e.affinity('kind:${k.name}'))]..sort((a, b) => b.$2.compareTo(a.$2));
        final best = e.bestPerMood([for (final k in CheerKind.values) k.name]);
        final empty = top.isEmpty && dislikes.isEmpty && best.isEmpty;
        return _Section(
          title: 'What $name knows about you',
          icon: Icons.favorite_rounded,
          seed: 63,
          subtitle: 'Tell $name you\'re bored or sad and it brings a song or video on YouTube, a meme, or an itch.io game. '
              'Like YouTube or Amazon, it learns from what you do: what you open, how long you stay, what you skip, '
              'your 👍 / 👎, and "I love…" in what you say and your notes. Old interests fade over a few weeks. '
              'It all stays on this phone.',
          children: [
            Row(children: [
              Expanded(child: Text('Keep learning', style: _hand.copyWith(fontSize: 17))),
              Switch(value: !c.learningPaused, activeThumbColor: Pal.sageDark, onChanged: (v) => c.learningPaused = !v),
            ]),
            if (empty)
              Text('Nothing yet. Try saying "I love Lana Del Rey", or tell $name you\'re bored.',
                  style: _hand.copyWith(fontSize: 16, color: ink.withValues(alpha: 0.7))),
            if (top.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Top interests', style: _hand.copyWith(fontSize: 18)),
              const SizedBox(height: 6),
              for (final f in top)
                _InterestRow(
                  type: _type(f.type),
                  name: _nice(f.label ?? f.name),
                  value: e.affinity(f.key),
                  detail: [
                    e.explain(f.key),
                    [
                      if (f.shows > 0) 'shown ${f.shows}',
                      if (f.opens > 0) 'opened ${f.opens}',
                      if ((f.counts['liked'] ?? 0) > 0) '👍 ${f.counts['liked']}',
                      if ((f.counts['disliked'] ?? 0) > 0) '👎 ${f.counts['disliked']}',
                    ].join(' · '),
                  ].whereType<String>().where((x) => x.isNotEmpty).join('  '),
                  onMute: () => c.mute(f.key),
                  onForget: () => c.forget(f.key),
                ),
            ],
            if (kinds.any((k) => k.$2 > 0)) ...[
              const SizedBox(height: 10),
              Text('What you enjoy most', style: _hand.copyWith(fontSize: 18)),
              const SizedBox(height: 6),
              for (final (k, v) in kinds) _Bar(label: k.chip, value: v),
            ],
            if (best.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('What helps when you feel…', style: _hand.copyWith(fontSize: 18)),
              const SizedBox(height: 4),
              for (final m in best.entries)
                Text('${m.key}: ${CheerKindInfo.parse(m.value.$1)?.label ?? m.value.$1} (${(m.value.$2 * 100).round()}% of the time)',
                    style: _hand.copyWith(fontSize: 16)),
            ],
            if (dislikes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Not for you (tap ✕ to give it another chance)', style: _hand.copyWith(fontSize: 16)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final f in dislikes.take(20))
                  InputChip(
                    label: Text(_nice(f.label ?? f.name), style: _hand.copyWith(fontSize: 15)),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: ink, width: 1.4),
                    onDeleted: () => c.forget(f.key),
                  ),
              ]),
            ],
            if (!empty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: _PillButton(label: 'Forget all of it', icon: Icons.delete_outline_rounded, color: Colors.white, onTap: c.forgetAll),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _InterestRow extends StatelessWidget {
  const _InterestRow({required this.type, required this.name, required this.value, required this.detail, required this.onMute, required this.onForget});
  final String type, name, detail;
  final double value;
  final VoidCallback onMute, onForget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: Pal.note, borderRadius: BorderRadius.circular(8), border: Border.all(color: ink, width: 1)),
                child: Text(type, style: _hand.copyWith(fontSize: 12)),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(name, style: _hand.copyWith(fontSize: 17), overflow: TextOverflow.ellipsis)),
              Text('${(value * 100).round()}%', style: _hand.copyWith(fontSize: 15)),
            ]),
            const SizedBox(height: 3),
            _Bar(value: value),
            if (detail.isNotEmpty) Text(detail, style: _hand.copyWith(fontSize: 13, color: ink.withValues(alpha: 0.6))),
          ]),
        ),
        IconButton(tooltip: 'Not for me', visualDensity: VisualDensity.compact, onPressed: onMute, icon: const Icon(Icons.block_rounded, size: 20, color: ink)),
        IconButton(tooltip: 'Forget', visualDensity: VisualDensity.compact, onPressed: onForget, icon: const Icon(Icons.close_rounded, size: 20, color: ink)),
      ]),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, this.label});
  final double value;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Container(
        height: 9,
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: ink, width: 1.2), borderRadius: BorderRadius.circular(5)),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(color: Pal.sageDark),
        ),
      ),
    );
    if (label == null) return bar;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(width: 80, child: Text(label!, style: _hand.copyWith(fontSize: 15))),
        Expanded(child: bar),
        const SizedBox(width: 8),
        SizedBox(width: 40, child: Text('${(value * 100).round()}%', textAlign: TextAlign.right, style: _hand.copyWith(fontSize: 14))),
      ]),
    );
  }
}
