import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../pet_controller.dart';
import '../services/email_service.dart';
import '../services/memory_service.dart';
import '../services/notes_service.dart';
import 'doodle.dart';
import 'note_detail_page.dart';
import 'record_panel.dart' show formatDuration;

const hand = TextStyle(fontFamily: handFont, color: ink, fontSize: 18, height: 1.22);

// ---------------------------------------------------------------- dates

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String clock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'am' : 'pm'}';
}

/// "Today", "Yesterday", "Tuesday", "Oct 12", "Oct 12, 2025".
String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7 && diff > 0) return _days[d.weekday - 1];
  return d.year == now.year ? '${_months[d.month - 1]} ${d.day}' : '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

String shortWhen(DateTime d) {
  final l = dayLabel(d);
  return l == 'Today' ? clock(d) : l;
}

// ---------------------------------------------------------------- cards

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, required this.color, this.onTap, this.onLongPress, this.semantics});
  final Widget child;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: semantics,
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: ink, width: 2)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: const EdgeInsets.fromLTRB(14, 11, 10, 11), child: child),
        ),
      ),
    );
  }
}

/// A sticky-note card for one note.
class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.note, required this.onTap, this.related, this.highlight, this.onPlay});
  final VoiceNote note;
  final VoidCallback onTap;
  final EmailItem? related;
  final String? highlight;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      color: Pal.note,
      onTap: onTap,
      semantics: 'Note: ${note.title}, ${shortWhen(note.createdAt)}',
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (note.pinned) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.push_pin_rounded, size: 16, color: Pal.tomato)),
              Expanded(child: Text(note.title, style: hand.copyWith(fontSize: 19), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            if (note.text != note.title && note.text.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(note.text, style: hand.copyWith(fontSize: 16, color: ink.withValues(alpha: 0.78)), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(shortWhen(note.createdAt), style: hand.copyWith(fontSize: 14, color: ink.withValues(alpha: 0.6))),
              if (note.isVoice) _Chip(icon: Icons.graphic_eq_rounded, text: formatDuration(Duration(milliseconds: note.durationMs))),
              if (!note.isVoice) const _Chip(icon: Icons.edit_rounded, text: 'typed'),
              if (related != null) _Chip(icon: Icons.mail_rounded, text: related!.from, color: Pal.blue.withValues(alpha: 0.5)),
            ]),
          ]),
        ),
        if (note.isVoice && onPlay != null)
          IconButton(
            tooltip: 'Play recording',
            onPressed: onPlay,
            icon: const Icon(Icons.play_circle_fill_rounded, color: ink, size: 32),
          ),
      ]),
    );
  }
}

/// An envelope card for one email.
class MailCard extends StatelessWidget {
  const MailCard({super.key, required this.email, required this.onTap});
  final EmailItem email;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      color: Colors.white,
      onTap: onTap,
      semantics: 'Email from ${email.from}: ${email.subject}',
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          margin: const EdgeInsets.only(right: 10, top: 2),
          decoration: BoxDecoration(color: Pal.blue, shape: BoxShape.circle, border: Border.all(color: ink, width: 2)),
          alignment: Alignment.center,
          child: Text(email.from.isEmpty ? '?' : email.from.characters.first.toUpperCase(), style: hand.copyWith(fontSize: 18)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(email.from,
                    style: hand.copyWith(fontSize: 17, color: ink.withValues(alpha: email.unread ? 1 : 0.75)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (email.date != null) Text(shortWhen(email.date!), style: hand.copyWith(fontSize: 14, color: ink.withValues(alpha: 0.6))),
            ]),
            Text(email.subject, style: hand.copyWith(fontSize: 18), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (email.snippet.isNotEmpty)
              Text(email.snippet, style: hand.copyWith(fontSize: 15, color: ink.withValues(alpha: 0.7)), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: color ?? Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ink.withValues(alpha: 0.5), width: 1.2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: ink),
        const SizedBox(width: 3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Text(text, style: hand.copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

/// A card for a search hit (note or email).
class HitCard extends StatelessWidget {
  const HitCard({super.key, required this.hit, required this.pet});
  final SearchHit hit;
  final PetController pet;

  @override
  Widget build(BuildContext context) {
    final it = hit.item;
    if (it.isNote) {
      return NoteCard(note: it.note!, onTap: () => openNote(context, pet, it.note!));
    }
    return MailCard(email: it.email!, onTap: () => showMailSheet(context, pet, it.email!));
  }
}

// ---------------------------------------------------------------- audio

/// Play/pause + scrubber for a note's recording.
class NotePlayer extends StatefulWidget {
  const NotePlayer({super.key, required this.path, required this.durationMs, this.autoplay = false});
  final String path;
  final int durationMs;
  final bool autoplay;

  @override
  State<NotePlayer> createState() => _NotePlayerState();
}

class _NotePlayerState extends State<NotePlayer> {
  final _player = AudioPlayer();
  Duration _pos = Duration.zero;
  late Duration _len = Duration(milliseconds: widget.durationMs);
  bool _playing = false;
  final _subs = <StreamSubscription<dynamic>>[];

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPositionChanged.listen((p) => setState(() => _pos = p)));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (d > Duration.zero) setState(() => _len = d);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) => setState(() {
          _playing = false;
          _pos = Duration.zero;
        })));
    if (widget.autoplay) _toggle();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
    } else {
      if (_pos > Duration.zero && _pos < _len) {
        await _player.resume();
      } else {
        await _player.play(DeviceFileSource(widget.path));
      }
      setState(() => _playing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final max = _len.inMilliseconds <= 0 ? 1.0 : _len.inMilliseconds.toDouble();
    return DoodleBox(
      seed: 5,
      radius: 18,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(6, 4, 14, 4),
      child: Row(children: [
        IconButton(
          tooltip: _playing ? 'Pause' : 'Play',
          onPressed: _toggle,
          icon: Icon(_playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: ink, size: 40),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Pal.tomato,
              inactiveTrackColor: Pal.pink.withValues(alpha: 0.6),
              thumbColor: ink,
              trackHeight: 5,
            ),
            child: Slider(
              value: _pos.inMilliseconds.clamp(0, max.toInt()).toDouble(),
              max: max,
              onChanged: (v) => _player.seek(Duration(milliseconds: v.round())),
            ),
          ),
        ),
        Text('${formatDuration(_pos)} / ${formatDuration(_len)}',
            style: hand.copyWith(fontSize: 15, fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

// ---------------------------------------------------------------- navigation

void openNote(BuildContext context, PetController pet, VoiceNote note) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => NoteDetailPage(pet: pet, note: note)));
}

Future<void> showMailSheet(BuildContext context, PetController pet, EmailItem e) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Pal.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      side: BorderSide(color: ink, width: 2.4),
    ),
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (c, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 14, 20, 30), children: [
        Center(
          child: Container(width: 44, height: 5, decoration: BoxDecoration(color: ink.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(3))),
        ),
        const SizedBox(height: 14),
        Text(e.subject, style: hand.copyWith(fontSize: 24)),
        const SizedBox(height: 4),
        Text('From ${e.from}${e.date == null ? '' : ' · ${dayLabel(e.date!)}, ${clock(e.date!)}'}',
            style: hand.copyWith(fontSize: 16, color: ink.withValues(alpha: 0.7))),
        const SizedBox(height: 12),
        DoodleBox(
          seed: 9,
          color: Colors.white,
          radius: 14,
          padding: const EdgeInsets.all(14),
          child: Text(e.snippet.isEmpty ? '(No preview)' : e.snippet, style: hand.copyWith(fontSize: 17)),
        ),
        const SizedBox(height: 6),
        Text('This is the preview your pet keeps for searching. Open the email to read all of it.',
            style: hand.copyWith(fontSize: 14, color: ink.withValues(alpha: 0.6))),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          if (e.webLink != null)
            _Pill(
              icon: Icons.open_in_new_rounded,
              label: 'Open email',
              onTap: () => launchUrl(Uri.parse(e.webLink!), mode: LaunchMode.externalApplication),
            ),
          _Pill(
            icon: Icons.record_voice_over_rounded,
            label: 'Read it to me',
            onTap: () {
              Navigator.pop(c);
              pet.voice.say('${e.from} wrote: ${e.subject}. ${e.snippet}');
            },
          ),
        ]),
        const SizedBox(height: 18),
        RelatedList(pet: pet, item: MemoryItem.fromEmail(e), title: 'Your notes about this'),
      ]),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: ink, width: 2),
            boxShadow: const [BoxShadow(color: ink, offset: Offset(0, 3))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: ink, size: 18),
            const SizedBox(width: 6),
            Text(label, style: hand.copyWith(fontSize: 17)),
          ]),
        ),
      ),
    );
  }
}

/// "Goes with…" list: emails related to a note, or notes related to an email.
class RelatedList extends StatelessWidget {
  const RelatedList({super.key, required this.pet, required this.item, required this.title});
  final PetController pet;
  final MemoryItem item;
  final String title;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SearchHit>>(
      future: pet.memory.related(item, limit: 3),
      builder: (context, snap) {
        final hits = snap.data ?? const [];
        if (hits.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.link_rounded, color: ink, size: 20),
            const SizedBox(width: 6),
            Text(title.toUpperCase(), style: hand.copyWith(fontSize: 17, letterSpacing: 1)),
          ]),
          const SizedBox(height: 8),
          for (final h in hits) ...[HitCard(hit: h, pet: pet), const SizedBox(height: 8)],
        ]);
      },
    );
  }
}
