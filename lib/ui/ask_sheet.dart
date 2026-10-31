import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../pet_controller.dart';
import '../platform/store.dart' as store;
import '../services/settings_service.dart';
import 'doodle.dart';

const _hand = TextStyle(fontFamily: handFont, color: ink, fontSize: 18, height: 1.2);

/// Tap the bookshelf or the pet: a small "Ask or tell Mochi…" box. When you send,
/// the box closes so you can watch the pet search its books and read the
/// answer to you.
Future<void> showAskSheet(BuildContext context, PetController pet) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    barrierColor: ink.withValues(alpha: 0.12),
    backgroundColor: Pal.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      side: BorderSide(color: ink, width: 2.4),
    ),
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: _AskBody(pet: pet),
    ),
  );
}

class _AskBody extends StatefulWidget {
  const _AskBody({required this.pet});
  final PetController pet;

  @override
  State<_AskBody> createState() => _AskBodyState();
}

class _AskBodyState extends State<_AskBody> {
  final _q = TextEditingController();
  bool _listening = false;
  bool _transcribing = false;
  String? _path;

  PetController get pet => widget.pet;

  static const _examples = [
    "I'm bored",
    'Why do cats purr?',
    "Text Ana I'm running late",
    'Play some Taylor Swift',
    'Show me cat videos',
    'Email mom about dinner Sunday',
    'Download Spotify',
  ];

  @override
  void dispose() {
    if (_listening) pet.voice.cancelRecording();
    _q.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final q = (text ?? _q.text).trim();
    if (q.isEmpty) return;
    Navigator.of(context).pop();
    pet.talk(q);
  }

  Future<void> _voice() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_listening) {
      setState(() {
        _listening = false;
        _transcribing = true;
      });
      final path = await pet.voice.stopRecording() ?? _path ?? '';
      String? text;
      try {
        text = await pet.transcribeQuestion(path);
      } catch (_) {}
      await store.deleteFile(path);
      if (!mounted) return;
      setState(() => _transcribing = false);
      if (text == null || text.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text("I didn't catch that.", style: _hand.copyWith(color: Colors.white))));
        return;
      }
      _send(text);
      return;
    }
    if (!pet.canListen) {
      messenger.showSnackBar(SnackBar(
        content: Text(kIsWeb ? "This browser can't do speech-to-text. Try Chrome, Edge or Safari, or type." : 'Asking by voice needs the speech model (Settings → On-device AI).',
            style: _hand.copyWith(color: Colors.white)),
      ));
      return;
    }
    _path = await store.pathIn('tmp', 'ask_${DateTime.now().millisecondsSinceEpoch}.wav');
    if (await pet.voice.startRecording(_path!)) setState(() => _listening = true);
  }

  @override
  Widget build(BuildContext context) {
    final name = pet.character.name.split(' ').first;
    final provider = pet.settings.aiProvider.shortName;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(color: ink.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.menu_book_rounded, color: ink),
            const SizedBox(width: 8),
            Text('TALK TO $name'.toUpperCase(), style: _hand.copyWith(fontSize: 24, letterSpacing: 1.2)),
          ]),
          const SizedBox(height: 2),
          Text(
            'Ask $name anything and it looks it up in the bookshelf ($provider answers). '
            'Tell it how you feel and it finds a song or video on YouTube, a meme or a game. '
            'Or have it text or email a friend, or download an app.',
            style: _hand.copyWith(fontSize: 15, color: ink.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 12),
          DoodleBox(
            seed: 29,
            color: Pal.note,
            radius: 12,
            shadow: 4,
            padding: const EdgeInsets.only(left: 12, right: 2),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _q,
                  autofocus: true,
                  enabled: !_listening && !_transcribing,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: _hand.copyWith(fontSize: 20),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: _listening
                        ? 'Listening… tap ■ when done'
                        : _transcribing
                            ? 'Writing down what you said…'
                            : 'Ask or tell $name…',
                    hintStyle: _hand.copyWith(fontSize: 19, color: ink.withValues(alpha: 0.45)),
                  ),
                ),
              ),
              IconButton(
                tooltip: _listening ? 'Stop and ask' : 'Ask by voice',
                onPressed: _transcribing ? null : _voice,
                icon: _transcribing
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: ink))
                    : Icon(_listening ? Icons.stop_circle_rounded : Icons.mic_rounded,
                        color: _listening ? Pal.tomato : ink, size: 28),
              ),
              IconButton(
                tooltip: 'Ask',
                onPressed: _listening || _transcribing ? null : () => _send(),
                icon: const Icon(Icons.send_rounded, color: ink, size: 26),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _examples)
              GestureDetector(
                onTap: () => _send(e),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: ink, width: 1.6),
                  ),
                  child: Text(e, style: _hand.copyWith(fontSize: 16)),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}
