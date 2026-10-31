import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../pet_controller.dart';
import '../platform/store.dart' as store;
import '../services/cheer_service.dart';
import 'doodle.dart';

const _hand = TextStyle(fontFamily: handFont, color: ink, fontSize: 18, height: 1.2);

/// Shows what the pet brought. When the card closes, the pet puts it back
/// on the shelf and its files are deleted.
Future<void> showCheerSheet(BuildContext context, PetController pet, CheerItem item) async {
  final next = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    barrierColor: ink.withValues(alpha: 0.15),
    backgroundColor: Pal.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      side: BorderSide(color: ink, width: 2.4),
    ),
    builder: (c) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.86),
      child: _CheerBody(pet: pet, item: item),
    ),
  );
  await pet.endCheer(item, next: next ?? '');
}

class _CheerBody extends StatefulWidget {
  const _CheerBody({required this.pet, required this.item});
  final PetController pet;
  final CheerItem item;

  @override
  State<_CheerBody> createState() => _CheerBodyState();
}

class _CheerBodyState extends State<_CheerBody> {
  bool? _liked;

  CheerItem get item => widget.item;

  Future<void> _rate(bool liked) async {
    if (_liked == liked) return;
    setState(() => _liked = liked);
    await widget.pet.cheer.feedback(item, liked);
  }

  String get _heading => switch (item.kind) {
        CheerKind.song => 'A SONG FOR YOU',
        CheerKind.video => 'A VIDEO FOR YOU',
        CheerKind.meme => 'A LITTLE MEME',
        CheerKind.game => 'A GAME FOR YOU',
      };

  IconData get _icon => switch (item.kind) {
        CheerKind.song => Icons.music_note_rounded,
        CheerKind.video => Icons.smart_display_rounded,
        CheerKind.meme => Icons.sentiment_very_satisfied_rounded,
        CheerKind.game => Icons.sports_esports_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(width: 44, height: 5, decoration: BoxDecoration(color: ink.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(3))),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Icon(_icon, color: ink),
            const SizedBox(width: 8),
            Expanded(child: Text(_heading, style: _hand.copyWith(fontSize: 24, letterSpacing: 1.1))),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            _MatchChip(match: item.match),
            const SizedBox(width: 8),
            if (item.why.isNotEmpty)
              Expanded(child: Text(item.why, style: _hand.copyWith(fontSize: 15, color: ink.withValues(alpha: 0.7)))),
          ]),
          const SizedBox(height: 12),
          switch (item.kind) {
            CheerKind.meme => _PictureCard(item: item),
            CheerKind.song || CheerKind.video || CheerKind.game => _PlayCard(item: item, pet: widget.pet),
          },
          const SizedBox(height: 14),
          Row(children: [
              Text('Did it help?', style: _hand.copyWith(fontSize: 16, color: ink.withValues(alpha: 0.7))),
              const SizedBox(width: 6),
              _RoundToggle(icon: Icons.thumb_up_rounded, on: _liked == true, onTap: () => _rate(true)),
              const SizedBox(width: 6),
              _RoundToggle(icon: Icons.thumb_down_rounded, on: _liked == false, onTap: () => _rate(false)),
            ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
            _Pill(label: switch (item.kind) { CheerKind.game => 'Another game', CheerKind.song => 'Another song', CheerKind.video => 'Another video', _ => 'Another one' }, onTap: () => Navigator.pop(context, 'another')),
            _Pill(label: 'Something else', onTap: () => Navigator.pop(context, 'different')),
            _Pill(label: 'Done', color: Pal.sage, onTap: () => Navigator.pop(context, '')),
          ]),
          const SizedBox(height: 6),
          Text(
            'When you close this, it goes back on the shelf and is deleted from your phone.',
            textAlign: TextAlign.center,
            style: _hand.copyWith(fontSize: 13, color: ink.withValues(alpha: 0.5)),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- meme

class _PictureCard extends StatelessWidget {
  const _PictureCard({required this.item});
  final CheerItem item;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.45;
    return DoodleBox(
      seed: 73,
      color: Colors.white,
      radius: 18,
      shadow: 4,
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            // GIFs animate on their own: a cat clip plays on a loop
            child: store.localImage(item.mediaPath!, fit: BoxFit.contain),
          ),
        ),
        if (item.title.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(item.title, style: _hand.copyWith(fontSize: 17), maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: Text(item.subtitle, style: _hand.copyWith(fontSize: 13, color: ink.withValues(alpha: 0.5)))),
          if (item.openUrl != null)
            TextButton(
              onPressed: () => launchUrl(Uri.parse(item.openUrl!), mode: LaunchMode.externalApplication).catchError((_) => false),
              child: Text('See the post', style: _hand.copyWith(fontSize: 14)),
            ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- song / video / game

/// Something to open: a song or video on YouTube, or a game on itch.io.
/// "Play" opens it in a browser window over the room (Safari view on
/// iPhone, Chrome Custom Tab on Android); close it to come back.
class _PlayCard extends StatefulWidget {
  const _PlayCard({required this.item, required this.pet});
  final CheerItem item;
  final PetController pet;

  @override
  State<_PlayCard> createState() => _PlayCardState();
}

class _PlayCardState extends State<_PlayCard> with WidgetsBindingObserver {
  bool _rewarded = false;

  // How long they stayed in the YouTube / itch.io window is the strongest
  // hint of interest (like watch time). Android pauses the app while a
  // Custom Tab is open; on iPhone the Safari view sits on top, so the time
  // is measured until they're back on this card (see CheerService.closed).
  DateTime? _playAt;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_playAt == null) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) _left = true;
    if (state == AppLifecycleState.resumed && _left) {
      _left = false;
      widget.pet.cheer.dwell(widget.item, DateTime.now().difference(_playAt!));
      _playAt = null;
    }
  }

  bool get _youtube => widget.item.kind != CheerKind.game;

  Future<void> _play({bool app = false}) async {
    final url = Uri.parse(widget.item.openUrl!);
    var ok = false;
    for (final mode in app
        ? const [LaunchMode.externalNonBrowserApplication, LaunchMode.inAppBrowserView]
        : const [LaunchMode.inAppBrowserView, LaunchMode.externalApplication]) {
      try {
        ok = await launchUrl(url, mode: mode);
      } catch (_) {
        ok = false;
      }
      if (ok) break;
    }
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("I couldn't open the browser.", style: _hand.copyWith(color: Colors.white))));
      return;
    }
    _playAt = DateTime.now();
    widget.pet.cheer.opened(widget.item);
    if (!_rewarded) {
      _rewarded = true;
      widget.pet.playedCheer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final song = it.kind == CheerKind.song;
    final Widget cover = it.artPath != null
        ? store.localImage(it.artPath!)
        : Container(
            color: switch (it.kind) { CheerKind.song => Pal.lilac, CheerKind.video => Pal.pink, _ => const Color(0xFFBFE3F2) },
            child: Icon(
              switch (it.kind) { CheerKind.song => Icons.music_note_rounded, CheerKind.video => Icons.play_circle_fill_rounded, _ => Icons.sports_esports_rounded },
              color: ink,
              size: 64,
            ),
          );
    return DoodleBox(
      seed: 77,
      color: Colors.white,
      radius: 18,
      shadow: 4,
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (song)
          Row(children: [
            GestureDetector(onTap: _play, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 96, height: 96, child: cover))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.title, style: _hand.copyWith(fontSize: 21), maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(it.subtitle, style: _hand.copyWith(fontSize: 16, color: ink.withValues(alpha: 0.65)), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ])
        else ...[
          GestureDetector(
            onTap: _play,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(aspectRatio: it.kind == CheerKind.game ? 315 / 250 : 16 / 9, child: cover),
            ),
          ),
          const SizedBox(height: 8),
          Text(it.title, style: _hand.copyWith(fontSize: 21), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (it.subtitle.isNotEmpty)
            Text(it.subtitle, style: _hand.copyWith(fontSize: 15, color: ink.withValues(alpha: 0.7)), maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 10),
        _Pill(label: _youtube ? '▶  Play on YouTube' : '▶  Play in browser', color: Pal.mustard, onTap: _play),
        if (_youtube) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: () => _play(app: true),
              child: Text('Open in the YouTube app instead', style: _hand.copyWith(fontSize: 15)),
            ),
          ),
        ],
        Text(
          _youtube
              ? 'Opens a YouTube window right here (searching for the best match); close it to come back.'
              : 'Free on itch.io. It opens in a window here; close it to come back. '
                  'If a game needs a keyboard or a computer, tap Another game.',
          style: _hand.copyWith(fontSize: 13, color: ink.withValues(alpha: 0.55)),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- bits

/// "87% match" when picked from what Mochi knows; "New to try" when exploring.
class _MatchChip extends StatelessWidget {
  const _MatchChip({required this.match});
  final double? match;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final label = m == null || m < 0.05 ? '🧭 New to try' : '✨ ${(m * 100).round()}% match';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: m == null || m < 0.05 ? Pal.blue.withValues(alpha: 0.45) : Pal.note,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink, width: 1.4),
      ),
      child: Text(label, style: _hand.copyWith(fontSize: 14)),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap, this.color = Colors.white, this.small = false});
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 12 : 16, vertical: small ? 5 : 9),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: ink, width: small ? 1.6 : 2.2),
          boxShadow: small ? null : const [BoxShadow(color: ink, offset: Offset(0, 3))],
        ),
        child: Text(label, textAlign: TextAlign.center, style: _hand.copyWith(fontSize: small ? 15 : 18)),
      ),
    );
  }
}

class _RoundToggle extends StatelessWidget {
  const _RoundToggle({required this.icon, required this.on, required this.onTap});
  final IconData icon;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: on ? Pal.mustard : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: ink, width: on ? 2.6 : 1.6),
        ),
        child: Icon(icon, color: ink, size: 20),
      ),
    );
  }
}

// ---------------------------------------------------------------- support

/// Shown instead of a meme when someone may be in danger.
Future<void> showSupportSheet(BuildContext context) {
  final country = (ui.PlatformDispatcher.instance.locale.countryCode ?? '').toUpperCase();
  final lines = switch (country) {
    'US' || 'CA' => [('Call or text 988', 'tel:988'), ('Text 988', 'sms:988')],
    'GB' || 'IE' => [('Call Samaritans: 116 123', 'tel:116123')],
    'AU' => [('Call Lifeline: 13 11 14', 'tel:131114')],
    _ => <(String, String)>[],
  };
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Pal.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      side: BorderSide(color: ink, width: 2.4),
    ),
    builder: (c) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.favorite_rounded, color: Pal.tomato),
            const SizedBox(width: 8),
            Text('YOU\'RE NOT ALONE', style: _hand.copyWith(fontSize: 24, letterSpacing: 1.1)),
          ]),
          const SizedBox(height: 6),
          Text(
            'If you\'re thinking about hurting yourself, please reach out to someone now. '
            'Talking to a trained person can really help, any time of day.',
            style: _hand.copyWith(fontSize: 17),
          ),
          const SizedBox(height: 14),
          for (final l in lines) ...[
            _Pill(label: l.$1, color: Pal.sage, onTap: () => launchUrl(Uri.parse(l.$2)).catchError((_) => false)),
            const SizedBox(height: 8),
          ],
          _Pill(
            label: 'Find a helpline near you',
            onTap: () => launchUrl(Uri.parse('https://findahelpline.com'), mode: LaunchMode.externalApplication).catchError((_) => false),
          ),
          const SizedBox(height: 8),
          Text(
            'If you\'re in immediate danger, call your local emergency number. You can also text a friend or family member you trust.',
            style: _hand.copyWith(fontSize: 14, color: ink.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => Navigator.pop(c), child: Text('Close', style: _hand)),
          ),
        ]),
      ),
    ),
  );
}
