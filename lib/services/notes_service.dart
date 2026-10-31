import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../platform/store.dart' as store;

class VoiceNote {
  VoiceNote({
    required this.id,
    required this.text,
    required this.createdAt,
    String? title,
    DateTime? updatedAt,
    this.audioPath,
    this.durationMs = 0,
    this.pinned = false,
  })  : title = (title == null || title.trim().isEmpty) ? autoTitle(text) : title.trim(),
        updatedAt = updatedAt ?? createdAt;

  final String id;
  String text;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  final String? audioPath;
  final int durationMs;
  bool pinned;

  bool get isVoice => audioPath != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'audioPath': audioPath,
        'durationMs': durationMs,
        'pinned': pinned,
      };

  static VoiceNote fromJson(Map<String, dynamic> j) => VoiceNote(
        id: j['id'] as String,
        text: j['text'] as String? ?? '',
        title: j['title'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
        audioPath: j['audioPath'] as String?,
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        pinned: j['pinned'] as bool? ?? false,
      );

  /// A short title from the first words of the note, minus filler.
  static String autoTitle(String text) {
    var t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    t = t.replaceFirst(
        RegExp(r'^((um+|uh+|so|okay|ok|alright|hey|hi|well|right)[,.]?\s+)+', caseSensitive: false), '');
    t = t.replaceFirst(RegExp(r'^(note( to self)?|remember( that)?|reminder)[:,]?\s+', caseSensitive: false), '');
    final firstSentence = t.split(RegExp(r'(?<=[.!?])\s')).first;
    final words = firstSentence.split(' ');
    var title = words.take(7).join(' ').replaceAll(RegExp(r'[.,;:!?]+$'), '');
    if (words.length > 7) title = '$title…';
    if (title.isEmpty) return 'Voice note';
    return title[0].toUpperCase() + title.substring(1);
  }
}

/// The notes box. Notes (text + original recording) stay on the phone only.
class NotesService extends ChangeNotifier {
  final List<VoiceNote> _notes = [];
  static const _index = 'notes/notes.json';

  /// Newest first; pinned notes are kept in place (screens decide grouping).
  List<VoiceNote> get notes => List.unmodifiable(_notes);

  VoiceNote? byId(String id) {
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  Future<void> load() async {
    final raw = await store.readText(_index);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _notes
          ..clear()
          ..addAll(list.map((e) => VoiceNote.fromJson(e as Map<String, dynamic>)));
      } catch (_) {
        // corrupted index: keep a copy and start fresh rather than crash
        try {
          await store.writeText('$_index.broken', raw);
        } catch (_) {}
      }
    }
    _sort();
    notifyListeners();
  }

  void _sort() => _notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// A fresh file path for the next recording.
  Future<String> newRecordingPath() => store.pathIn('notes', '${const Uuid().v4()}.wav');

  Future<VoiceNote> add(String text, {String? title, String? audioPath, int durationMs = 0}) async {
    final note = VoiceNote(
      id: const Uuid().v4(),
      text: text.trim(),
      title: title,
      createdAt: DateTime.now(),
      audioPath: audioPath,
      durationMs: durationMs,
    );
    _notes.insert(0, note);
    await _save();
    notifyListeners();
    return note;
  }

  Future<void> update(VoiceNote note, {String? text, String? title}) async {
    if (text != null) {
      final oldAuto = VoiceNote.autoTitle(note.text);
      note.text = text.trim();
      // keep the title in step if the user never changed it
      if (title == null && note.title == oldAuto) note.title = VoiceNote.autoTitle(note.text);
    }
    if (title != null) note.title = title.trim().isEmpty ? VoiceNote.autoTitle(note.text) : title.trim();
    note.updatedAt = DateTime.now();
    await _save();
    notifyListeners();
  }

  Future<void> togglePin(VoiceNote note) async {
    note.pinned = !note.pinned;
    await _save();
    notifyListeners();
  }

  /// Removes the note but keeps its recording until [purge] (so it can be undone).
  Future<void> delete(VoiceNote note) async {
    _notes.removeWhere((n) => n.id == note.id);
    await _save();
    notifyListeners();
  }

  Future<void> restore(VoiceNote note) async {
    if (byId(note.id) != null) return;
    _notes.add(note);
    _sort();
    await _save();
    notifyListeners();
  }

  /// Deletes the audio file of a note that was deleted for good.
  Future<void> purge(VoiceNote note) async {
    if (byId(note.id) != null || note.audioPath == null) return;
    await store.deleteFile(note.audioPath);
  }

  Future<void> _save() async {
    await store.writeText(_index, jsonEncode(_notes.map((n) => n.toJson()).toList()));
  }
}
