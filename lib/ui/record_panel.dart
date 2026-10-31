import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../pet_controller.dart';
import '../services/notes_service.dart';
import '../services/voice_service.dart';
import 'doodle.dart';

const _hand = TextStyle(fontFamily: handFont, color: ink, fontSize: 18, height: 1.2);

String formatDuration(Duration d) {
  final m = d.inMinutes, s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// The panel that slides up over the room while recording:
/// live timer + level bars, pause, cancel and done; then "writing it
/// down…"; then a review card to fix the words before saving.
class RecordPanel extends StatelessWidget {
  const RecordPanel({super.key, required this.pet});
  final PetController pet;

  @override
  Widget build(BuildContext context) {
    final state = pet.recState;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (c, a) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(a),
        child: c,
      ),
      child: switch (state) {
        RecState.idle => const SizedBox.shrink(key: ValueKey('idle')),
        RecState.recording => _Recording(key: const ValueKey('rec'), pet: pet),
        RecState.transcribing => const _Transcribing(key: ValueKey('tr')),
        RecState.review => _Review(key: ValueKey(pet.draft), pet: pet),
      },
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 10 + bottom),
      child: DoodleBox(
        seed: 77,
        radius: 24,
        shadow: 5,
        color: Pal.cream,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: child,
      ),
    );
  }
}

class _Recording extends StatelessWidget {
  const _Recording({super.key, required this.pet});
  final PetController pet;

  @override
  Widget build(BuildContext context) {
    final v = pet.voice;
    return _Shell(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ValueListenableBuilder<bool>(
          valueListenable: v.paused,
          builder: (context, paused, _) => Row(children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: paused ? ink.withValues(alpha: 0.3) : Pal.tomato,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(paused ? 'PAUSED' : 'RECORDING', style: _hand.copyWith(fontSize: 18, letterSpacing: 1.2)),
            const Spacer(),
            ValueListenableBuilder<Duration>(
              valueListenable: v.elapsed,
              builder: (context, d, _) => Text(
                formatDuration(d),
                style: _hand.copyWith(fontSize: 30, fontFeatures: const [FontFeature.tabularFigures()]),
                semanticsLabel: 'Recorded ${d.inSeconds} seconds',
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        SizedBox(height: 54, child: _LevelBars(level: v.level, paused: v.paused)),
        if (kIsWeb) // browser dictation: show the words as they come
          ValueListenableBuilder<String>(
            valueListenable: v.liveText,
            builder: (context, t, _) => Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 96),
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Pal.note, borderRadius: BorderRadius.circular(10), border: Border.all(color: ink, width: 1.4)),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(t.isEmpty ? 'Start talking…' : t,
                    style: _hand.copyWith(fontSize: 16, color: t.isEmpty ? ink.withValues(alpha: 0.5) : ink)),
              ),
            ),
          ),
        const SizedBox(height: 6),
        ValueListenableBuilder<Duration>(
          valueListenable: v.elapsed,
          builder: (context, d, _) {
            final left = VoiceService.maxRecording - d;
            return Text(
              left < const Duration(minutes: 1)
                  ? 'Stops by itself in ${left.inSeconds} s'
                  : 'Talk naturally. Tap Done when you finish.',
              style: _hand.copyWith(fontSize: 15, color: ink.withValues(alpha: 0.65)),
            );
          },
        ),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _RoundAction(
            label: 'Cancel',
            icon: Icons.close_rounded,
            color: Colors.white,
            onTap: pet.cancelRecording,
          ),
          ValueListenableBuilder<bool>(
            valueListenable: v.paused,
            builder: (context, paused, _) => _RoundAction(
              label: paused ? 'Resume' : 'Pause',
              icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: Pal.mustard,
              onTap: pet.pauseRecording,
            ),
          ),
          _RoundAction(
            label: 'Done',
            icon: Icons.check_rounded,
            color: Pal.sage,
            big: true,
            onTap: pet.finishRecording,
          ),
        ]),
      ]),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.label, required this.icon, required this.color, required this.onTap, this.big = false});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      DoodleButton(tooltip: label, size: big ? 66 : 54, color: color, onTap: onTap, child: Icon(icon, color: ink, size: big ? 34 : 28)),
      const SizedBox(height: 4),
      Text(label, style: _hand.copyWith(fontSize: 16)),
    ]);
  }
}

/// Bouncy hand-drawn level bars that scroll like a tiny waveform.
class _LevelBars extends StatefulWidget {
  const _LevelBars({required this.level, required this.paused});
  final ValueNotifier<double> level;
  final ValueNotifier<bool> paused;

  @override
  State<_LevelBars> createState() => _LevelBarsState();
}

class _LevelBarsState extends State<_LevelBars> {
  final _history = List<double>.filled(28, 0.05, growable: true);

  @override
  void initState() {
    super.initState();
    widget.level.addListener(_push);
  }

  @override
  void dispose() {
    widget.level.removeListener(_push);
    super.dispose();
  }

  void _push() {
    setState(() {
      _history
        ..removeAt(0)
        ..add(widget.paused.value ? 0.05 : math.max(0.05, widget.level.value));
    });
  }

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _BarsPainter(List.of(_history)), size: Size.infinite);
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final gap = size.width / n;
    final w = gap * 0.55;
    for (var i = 0; i < n; i++) {
      final h = math.max(4.0, values[i] * size.height);
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(gap * (i + 0.5), size.height / 2), width: w, height: h),
        Radius.circular(w / 2),
      );
      final recent = i > n - 6;
      canvas.drawRRect(r, fillPaint(recent ? Pal.tomato : Pal.pink));
      canvas.drawRRect(r, inkPaint(1.6));
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => true;
}

class _Transcribing extends StatelessWidget {
  const _Transcribing({super.key});

  @override
  Widget build(BuildContext context) {
    return _Shell(
      child: Row(children: [
        const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3, color: ink)),
        const SizedBox(width: 14),
        Expanded(child: Text('Writing down what you said…', style: _hand.copyWith(fontSize: 20))),
      ]),
    );
  }
}

class _Review extends StatefulWidget {
  const _Review({super.key, required this.pet});
  final PetController pet;

  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  late final TextEditingController _text;
  late final TextEditingController _title;
  bool _titleTouched = false;

  @override
  void initState() {
    super.initState();
    final d = widget.pet.draft!;
    _text = TextEditingController(text: d.text);
    _title = TextEditingController(text: d.transcribed ? _auto(d.text) : '');
    _text.addListener(() {
      if (!_titleTouched) _title.text = _auto(_text.text);
    });
  }

  String _auto(String t) => t.trim().isEmpty ? '' : VoiceNote.autoTitle(t);

  @override
  void dispose() {
    _text.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.pet.draft!;
    return _Shell(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('NEW NOTE', style: _hand.copyWith(fontSize: 20, letterSpacing: 1.2)),
          const Spacer(),
          Icon(Icons.graphic_eq_rounded, color: ink.withValues(alpha: 0.6), size: 20),
          const SizedBox(width: 4),
          Text(formatDuration(d.duration), style: _hand.copyWith(fontSize: 16, color: ink.withValues(alpha: 0.7))),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _title,
          style: _hand.copyWith(fontSize: 20),
          onChanged: (_) => _titleTouched = true,
          decoration: _box('Title', hint: d.transcribed ? null : 'Give it a name (optional)'),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.22),
          child: TextField(
            controller: _text,
            style: _hand,
            maxLines: null,
            minLines: 3,
            decoration: _box(
              d.transcribed ? 'What you said (tap to fix)' : 'Words',
              hint: d.transcribed ? null : 'The speech model isn\'t downloaded, so only the audio is kept. You can type the words here.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          TextButton.icon(
            onPressed: widget.pet.discardDraft,
            icon: const Icon(Icons.delete_outline_rounded, color: ink),
            label: Text('Discard', style: _hand),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => widget.pet.saveDraft(text: _text.text, title: _titleTouched ? _title.text : null),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(
                color: Pal.sage,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: ink, width: 2.4),
                boxShadow: const [BoxShadow(color: ink, offset: Offset(0, 3))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.inventory_2_rounded, color: ink, size: 20),
                const SizedBox(width: 8),
                Text('Put in notes box', style: _hand.copyWith(fontSize: 19)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  InputDecoration _box(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        hintMaxLines: 3,
        labelStyle: _hand.copyWith(color: ink.withValues(alpha: 0.7)),
        hintStyle: _hand.copyWith(fontSize: 15, color: ink.withValues(alpha: 0.45)),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: ink, width: 2)),
        enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: ink, width: 2)),
        focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Color(0xFF4E7A3E), width: 2.6)),
      );
}
