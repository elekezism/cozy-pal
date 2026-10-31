import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pet_controller.dart';
import '../services/memory_service.dart';
import '../services/notes_service.dart';
import 'doodle.dart';
import 'memory_widgets.dart';

/// One note, full size: edit the words and title (saved as you type),
/// play the recording, pin, copy, read aloud, delete, and see which
/// emails and notes go with it.
class NoteDetailPage extends StatefulWidget {
  const NoteDetailPage({super.key, required this.pet, required this.note});
  final PetController pet;
  final VoiceNote note;

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  late final TextEditingController _title = TextEditingController(text: widget.note.title);
  late final TextEditingController _text = TextEditingController(text: widget.note.text);
  Timer? _saveTimer;
  bool _saved = true;

  VoiceNote get note => widget.note;
  NotesService get notes => widget.pet.notes;

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (!_saved) _saveNow();
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() => _saved = false);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _saveNow);
  }

  Future<void> _saveNow() async {
    if (notes.byId(note.id) == null) return;
    final titleChanged = _title.text.trim() != note.title;
    await notes.update(note, text: _text.text, title: titleChanged ? _title.text : null);
    if (!titleChanged && _title.text != note.title && mounted) _title.text = note.title;
    if (mounted) setState(() => _saved = true);
  }

  Future<void> _delete() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    _saveTimer?.cancel();
    _saved = true;
    await notes.delete(note);
    nav.pop();
    messenger.showSnackBar(SnackBar(
      content: Text('Note deleted', style: hand.copyWith(color: Colors.white)),
      action: SnackBarAction(label: 'Undo', onPressed: () => notes.restore(note)),
      duration: const Duration(seconds: 5),
    )).closed.then((reason) {
      if (reason != SnackBarClosedReason.action) notes.purge(note);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pet = widget.pet;
    return Scaffold(
      backgroundColor: Pal.sky,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
            child: Row(children: [
              DoodleButton(
                tooltip: 'Back',
                onTap: () => Navigator.of(context).maybePop(),
                child: const Icon(Icons.arrow_back_rounded, color: ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${dayLabel(note.createdAt)}, ${clock(note.createdAt)}',
                  style: hand.copyWith(fontSize: 18, color: ink.withValues(alpha: 0.75)),
                ),
              ),
              AnimatedOpacity(
                opacity: _saved ? 0.6 : 1,
                duration: const Duration(milliseconds: 200),
                child: Text(_saved ? 'Saved' : 'Saving…', style: hand.copyWith(fontSize: 15)),
              ),
              IconButton(
                tooltip: note.pinned ? 'Unpin' : 'Pin to top',
                onPressed: () async {
                  await notes.togglePin(note);
                  setState(() {});
                },
                icon: Icon(note.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, color: note.pinned ? Pal.tomato : ink),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                DoodleBox(
                  seed: 31,
                  color: Pal.note,
                  radius: 18,
                  shadow: 4,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TextField(
                      controller: _title,
                      onChanged: (_) => _changed(),
                      style: hand.copyWith(fontSize: 26),
                      decoration: const InputDecoration(border: InputBorder.none, hintText: 'Title'),
                    ),
                    Divider(color: ink.withValues(alpha: 0.3), height: 8, thickness: 1.5),
                    TextField(
                      controller: _text,
                      onChanged: (_) => _changed(),
                      maxLines: null,
                      minLines: 4,
                      style: hand.copyWith(fontSize: 20, height: 1.35),
                      decoration: const InputDecoration(border: InputBorder.none, hintText: 'Write something…'),
                    ),
                  ]),
                ),
                if (note.isVoice) ...[
                  const SizedBox(height: 14),
                  NotePlayer(path: note.audioPath!, durationMs: note.durationMs),
                ],
                const SizedBox(height: 14),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  _Action(
                    icon: Icons.record_voice_over_rounded,
                    label: 'Read aloud',
                    onTap: () => pet.voice.say(_text.text),
                  ),
                  _Action(
                    icon: Icons.copy_rounded,
                    label: 'Copy',
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: '${_title.text}\n\n${_text.text}'));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Copied', style: hand.copyWith(color: Colors.white))));
                      }
                    },
                  ),
                  _Action(icon: Icons.delete_outline_rounded, label: 'Delete', onTap: _delete),
                ]),
                const SizedBox(height: 22),
                ListenableBuilder(
                  listenable: pet.memory,
                  builder: (context, _) => RelatedList(pet: pet, item: MemoryItem.fromNote(note), title: 'Goes with'),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
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
