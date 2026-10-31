import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../ai/local_ai.dart';
import '../pet_controller.dart';
import '../platform/store.dart' as store;
import '../services/email_service.dart';
import '../services/memory_service.dart';
import '../services/notes_service.dart';
import 'doodle.dart';
import 'memory_widgets.dart';
import 'settings_screen.dart';

enum _Filter { all, pinned, voice, typed }

/// The notes box, full screen. It is also where you search:
/// choose Notes, Emails or Both, type (or say) what you're looking for and
/// results appear as you type; press search and the pet answers out loud.
class NotesPage extends StatefulWidget {
  const NotesPage({super.key, required this.pet, this.focusSearch = false});
  final PetController pet;
  final bool focusSearch;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  MemorySource _scope = MemorySource.notes;
  _Filter _filter = _Filter.all;
  List<SearchHit>? _hits; // null = not searching
  Timer? _debounce;
  int _searchId = 0;
  FindResult? _answer;
  bool _asking = false;
  bool _listening = false;
  String? _voicePath;

  PetController get pet => widget.pet;
  bool get _mailOn => pet.email.isConfigured;

  @override
  void initState() {
    super.initState();
    if (widget.focusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
    }
    // keep the mail copy fresh for searching
    if (_mailOn) pet.memory.syncMail();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    if (_listening) pet.voice.cancelRecording();
    super.dispose();
  }

  // ------------------------------------------------------------ search

  void _onSearch(String q) {
    _debounce?.cancel();
    if (_answer != null) setState(() => _answer = null);
    if (q.trim().isEmpty) {
      setState(() => _hits = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    final id = ++_searchId;
    final hits = await pet.memory.search(q, source: _scope, limit: 30);
    if (mounted && id == _searchId) setState(() => _hits = hits);
  }

  void _setScope(MemorySource s) {
    setState(() {
      _scope = s;
      _answer = null;
    });
    if (s != MemorySource.notes && _mailOn) pet.memory.syncMail();
    if (_search.text.trim().isNotEmpty) _runSearch();
  }

  /// Pressing search: the pet looks and answers out loud.
  Future<void> _ask() async {
    final q = _search.text.trim();
    if (q.isEmpty || _asking) return;
    _searchFocus.unfocus();
    setState(() => _asking = true);
    await _runSearch();
    final r = await pet.find(q, source: _scope);
    if (!mounted) return;
    setState(() {
      _asking = false;
      _answer = r;
    });
  }

  Future<void> _voice() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_listening) {
      setState(() => _listening = false);
      final path = await pet.voice.stopRecording() ?? _voicePath ?? '';
      String? text;
      try {
        text = await pet.transcribeQuestion(path);
      } catch (_) {}
      await store.deleteFile(path);
      if (text == null || text.isEmpty) {
        _snack("I didn't catch that.");
        return;
      }
      _search.text = text;
      await _ask();
      return;
    }
    if (!pet.canListen) {
      messenger.showSnackBar(SnackBar(
          content: Text(kIsWeb ? "This browser can't do speech-to-text. Try Chrome, Edge or Safari." : 'Voice search needs the speech model (Settings → On-device AI).',
              style: hand.copyWith(color: Colors.white))));
      return;
    }
    _voicePath = await store.pathIn('tmp', 'find_${DateTime.now().millisecondsSinceEpoch}.wav');
    if (await pet.voice.startRecording(_voicePath!)) setState(() => _listening = true);
  }

  // ------------------------------------------------------------ notes actions

  bool _keep(VoiceNote n) => switch (_filter) {
        _Filter.all => true,
        _Filter.pinned => n.pinned,
        _Filter.voice => n.isVoice,
        _Filter.typed => !n.isVoice,
      };

  Future<void> _write() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Pal.cream,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: ink, width: 2.4)),
        title: Text('WRITE A NOTE', style: hand.copyWith(fontSize: 22, letterSpacing: 1)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 6,
          minLines: 3,
          style: hand,
          decoration: InputDecoration(
            hintText: 'What should I remember?',
            hintStyle: hand.copyWith(color: ink.withValues(alpha: 0.45)),
            filled: true,
            fillColor: Colors.white,
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text('Cancel', style: hand)),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text), child: Text('Save', style: hand.copyWith(fontSize: 19))),
        ],
      ),
    );
    if (text != null && text.trim().isNotEmpty) {
      final note = await pet.addTypedNote(text);
      if (note != null && mounted) _snack('Saved "${note.title}"');
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: hand.copyWith(color: Colors.white))));

  Future<void> _delete(VoiceNote n) async {
    final messenger = ScaffoldMessenger.of(context);
    await pet.notes.delete(n);
    messenger
        .showSnackBar(SnackBar(
          content: Text('Deleted "${n.title}"', style: hand.copyWith(color: Colors.white)),
          action: SnackBarAction(label: 'Undo', onPressed: () => pet.notes.restore(n)),
          duration: const Duration(seconds: 5),
        ))
        .closed
        .then((reason) {
      if (reason != SnackBarClosedReason.action) pet.notes.purge(n);
    });
  }

  void _record() {
    Navigator.of(context).pop();
    pet.startRecording();
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pal.sky,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([pet.notes, pet.memory]),
          builder: (context, _) {
            final all = pet.notes.notes;
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Row(children: [
                  DoodleButton(
                    tooltip: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Icon(Icons.arrow_back_rounded, color: ink),
                  ),
                  const SizedBox(width: 12),
                  Text('NOTES BOX', style: hand.copyWith(fontSize: 28, letterSpacing: 1.2)),
                  const Spacer(),
                  Text('${all.length}', style: hand.copyWith(fontSize: 22, color: ink.withValues(alpha: 0.6))),
                ]),
              ),
              _searchBar(),
              _scopeRow(),
              if (_scope != MemorySource.notes) _mailStatus(),
              if (_scope != MemorySource.mail) _filterRow(),
              Expanded(child: _body(all)),
              _BottomBar(onWrite: _write, onRecord: _record),
            ]);
          },
        ),
      ),
    );
  }

  Widget _searchBar() {
    final hint = _listening
        ? 'Listening… tap ■ when done'
        : switch (_scope) {
            MemorySource.notes => pet.memory.meaningSearch ? 'Search notes, e.g. "mom\'s gift"' : 'Search your notes',
            MemorySource.mail => 'Search emails, e.g. "from the vet"',
            MemorySource.all => 'Search notes and emails',
          };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: DoodleBox(
        seed: 13,
        color: Colors.white,
        radius: 14,
        shadow: 3,
        padding: const EdgeInsets.only(left: 12),
        child: Row(children: [
          const Icon(Icons.search_rounded, color: ink),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              enabled: !_listening,
              onChanged: _onSearch,
              onSubmitted: (_) => _ask(),
              textInputAction: TextInputAction.search,
              style: hand.copyWith(fontSize: 19),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle: hand.copyWith(fontSize: 18, color: ink.withValues(alpha: 0.45)),
              ),
            ),
          ),
          if (_search.text.isNotEmpty && !_listening)
            IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                _search.clear();
                _onSearch('');
              },
              icon: const Icon(Icons.close_rounded, color: ink),
            ),
          IconButton(
            tooltip: _listening ? 'Stop and search' : 'Search by voice',
            onPressed: _asking ? null : _voice,
            icon: Icon(_listening ? Icons.stop_circle_rounded : Icons.mic_rounded, color: _listening ? Pal.tomato : ink),
          ),
        ]),
      ),
    );
  }

  Widget _scopeRow() {
    Widget seg(MemorySource s, String label, IconData icon) => Expanded(
          child: Semantics(
            button: true,
            selected: _scope == s,
            label: 'Search $label',
            child: GestureDetector(
              onTap: () => _setScope(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: _scope == s ? Pal.mustard : Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ink, width: _scope == s ? 2.6 : 1.8),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 18, color: ink),
                  const SizedBox(width: 5),
                  Text(label, style: hand.copyWith(fontSize: 17)),
                ]),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(children: [
        seg(MemorySource.notes, 'Notes', Icons.sticky_note_2_rounded),
        const SizedBox(width: 8),
        seg(MemorySource.mail, 'Emails', Icons.mail_rounded),
        const SizedBox(width: 8),
        seg(MemorySource.all, 'Both', Icons.all_inbox_rounded),
      ]),
    );
  }

  Widget _mailStatus() {
    final mem = pet.memory;
    if (!_mailOn) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 16, 2),
        child: Row(children: [
          Expanded(child: Text("Email isn't connected yet.", style: hand.copyWith(fontSize: 15, color: ink.withValues(alpha: 0.7)))),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SettingsScreen(pet: pet, focusEmail: true),
            )),
            child: Text('Connect email', style: hand.copyWith(fontSize: 15)),
          ),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
      child: Row(children: [
        Expanded(
          child: Text(
            mem.syncing
                ? 'Fetching recent email…'
                : mem.syncError != null
                    ? mem.syncError!
                    : '${mem.mailCount} emails from the last month${mem.lastMailSync == null ? '' : ' · updated ${shortWhen(mem.lastMailSync!)}'}',
            style: hand.copyWith(fontSize: 14, color: ink.withValues(alpha: 0.6)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!mem.syncing)
          TextButton(onPressed: () => mem.syncMail(force: true), child: Text('Refresh', style: hand.copyWith(fontSize: 14))),
      ]),
    );
  }

  Widget _filterRow() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          for (final f in _Filter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FilterChip(
                label: switch (f) {
                  _Filter.all => 'All notes',
                  _Filter.pinned => 'Pinned',
                  _Filter.voice => 'Voice',
                  _Filter.typed => 'Typed',
                },
                selected: _filter == f,
                onTap: () => setState(() => _filter = f),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(List<VoiceNote> all) {
    final searching = _hits != null;
    final top = <Widget>[
      if (_asking)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: ink)),
            const SizedBox(width: 10),
            Text('${pet.character.name.split(' ').first} is looking…', style: hand.copyWith(fontSize: 18)),
          ]),
        ),
      if (_answer != null && !_asking) _AnswerCard(pet: pet, result: _answer!),
      if (searching && !_asking && _answer == null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('Press search to have ${pet.character.name.split(' ').first} answer out loud.',
              style: hand.copyWith(fontSize: 14, color: ink.withValues(alpha: 0.55))),
        ),
    ];

    // --- searching: results by relevance
    if (searching) {
      final hits = _hits!.where((h) => !h.item.isNote || _keep(h.item.note!)).toList();
      if (hits.isEmpty) {
        return _list([
          ...top,
          _Empty(
            icon: Icons.search_off_rounded,
            text: switch (_scope) {
              MemorySource.notes => 'No notes match that.',
              MemorySource.mail => _mailOn ? 'No recent emails match that.' : 'Connect email to search it.',
              MemorySource.all => 'Nothing in your notes or email matches that.',
            },
          ),
        ]);
      }
      return _list([...top, for (final h in hits) h.item.isNote ? _swipe(h.item.note!) : _mail(h.item.email!)]);
    }

    // --- browsing emails
    if (_scope == MemorySource.mail) {
      final mail = pet.memory.cachedMail;
      if (!_mailOn) return const _Empty(icon: Icons.mail_outline_rounded, text: 'Connect your email in Settings\nto browse and search it here.');
      if (mail.isEmpty) {
        return _Empty(
          icon: Icons.mail_outline_rounded,
          text: pet.memory.syncing ? 'Fetching your recent email…' : 'No email from the last month yet.\nTap Refresh to fetch it.',
        );
      }
      final rows = <Widget>[];
      String? lastDay;
      for (final e in mail) {
        final d = e.date == null ? 'Earlier' : dayLabel(e.date!);
        if (d != lastDay) {
          rows.add(_Header(d));
          lastDay = d;
        }
        rows.add(_mail(e));
      }
      return _list(rows);
    }

    // --- browsing notes (Notes or Both): pinned first, then by day
    if (all.isEmpty) {
      return const _Empty(
        icon: Icons.inventory_2_outlined,
        text: 'Your notes box is empty.\nTap Record and tell your pet something to remember.',
      );
    }
    final shown = all.where(_keep).toList();
    if (shown.isEmpty) return const _Empty(icon: Icons.filter_alt_off_rounded, text: 'Nothing here yet.');
    final pinned = shown.where((n) => n.pinned).toList();
    final rest = shown.where((n) => !n.pinned).toList();
    final rows = <Widget>[];
    if (pinned.isNotEmpty && _filter != _Filter.pinned) {
      rows.add(const _Header('Pinned'));
      rows.addAll(pinned.map(_swipe));
    }
    String? lastDay;
    for (final n in (_filter == _Filter.pinned ? pinned : rest)) {
      final d = dayLabel(n.createdAt);
      if (d != lastDay) {
        rows.add(_Header(d));
        lastDay = d;
      }
      rows.add(_swipe(n));
    }
    return _list(rows);
  }

  Widget _list(List<Widget> rows) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: rows.length,
        separatorBuilder: (_, i) => rows[i] is _Header ? const SizedBox(height: 2) : const SizedBox(height: 10),
        itemBuilder: (_, i) => rows[i],
      );

  Widget _mail(EmailItem e) => MailCard(email: e, onTap: () => showMailSheet(context, pet, e));

  Widget _swipe(VoiceNote n) {
    return Dismissible(
      key: ValueKey('note-${n.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(color: Pal.tomato, borderRadius: BorderRadius.circular(16), border: Border.all(color: ink, width: 2)),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) => _delete(n),
      child: _NoteWithLink(pet: pet, note: n),
    );
  }
}

/// What the pet said for the last search, with "say it again".
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.pet, required this.result});
  final PetController pet;
  final FindResult result;

  @override
  Widget build(BuildContext context) {
    final name = pet.character.name.split(' ').first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DoodleBox(
        seed: 23,
        color: Pal.cream,
        radius: 16,
        shadow: 3,
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(result.fellBackToBooks ? '$name checked the bookshelf:' : '$name says:',
                  style: hand.copyWith(fontSize: 15, color: ink.withValues(alpha: 0.65))),
              const SizedBox(height: 2),
              Text(result.answer, style: hand.copyWith(fontSize: 19)),
            ]),
          ),
          IconButton(
            tooltip: 'Say it again',
            onPressed: () => pet.voice.say(result.answer),
            icon: const Icon(Icons.volume_up_rounded, color: ink),
          ),
        ]),
      ),
    );
  }
}

/// Note card that also shows an email it goes with, if any.
class _NoteWithLink extends StatelessWidget {
  const _NoteWithLink({required this.pet, required this.note});
  final PetController pet;
  final VoiceNote note;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SearchHit>>(
      future: pet.memory.related(MemoryItem.fromNote(note), limit: 1),
      builder: (context, snap) => NoteCard(
        note: note,
        related: (snap.data?.isNotEmpty ?? false) ? snap.data!.first.item.email : null,
        onTap: () => openNote(context, pet, note),
        onPlay: note.isVoice ? () => pet.voice.playFile(note.audioPath!) : null,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4, left: 4),
        child: Text(text.toUpperCase(), style: hand.copyWith(fontSize: 16, letterSpacing: 1.2, color: ink.withValues(alpha: 0.7))),
      );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? Pal.note : Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ink, width: selected ? 2.2 : 1.4),
          ),
          child: Text(label, style: hand.copyWith(fontSize: 15)),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 46, color: ink.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: hand.copyWith(fontSize: 18, color: ink.withValues(alpha: 0.75))),
          ]),
        ),
      );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onWrite, required this.onRecord});
  final VoidCallback onWrite;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String label, Color color, VoidCallback onTap) => Expanded(
          child: Semantics(
            button: true,
            label: label,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: ink, width: 2.4),
                  boxShadow: const [BoxShadow(color: ink, offset: Offset(0, 4))],
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, color: ink),
                  const SizedBox(width: 8),
                  Text(label, style: hand.copyWith(fontSize: 20)),
                ]),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Row(children: [
        btn(Icons.edit_rounded, 'Write', Colors.white, onWrite),
        const SizedBox(width: 12),
        btn(Icons.mic_rounded, 'Record', Pal.tomato, onRecord),
      ]),
    );
  }
}
