import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../platform/store.dart' as store;

import '../ai/local_ai.dart';
import 'email_service.dart';
import 'notes_service.dart';

/// One searchable thing: a note or an email.
class MemoryItem {
  MemoryItem.fromNote(VoiceNote n)
      : id = 'note:${n.id}',
        isNote = true,
        note = n,
        email = null,
        date = n.createdAt,
        title = n.title,
        body = n.text;

  MemoryItem.fromEmail(EmailItem e)
      : id = e.id,
        isNote = false,
        note = null,
        email = e,
        date = e.date ?? DateTime.fromMillisecondsSinceEpoch(0),
        title = e.subject,
        body = '${e.from}. ${e.subject}. ${e.snippet}';

  final String id;
  final bool isNote;
  final VoiceNote? note;
  final EmailItem? email;
  final DateTime date;
  final String title;
  final String body;

  /// What gets embedded / keyword-indexed.
  String get searchText => isNote ? '$title. $body' : body;
}

class SearchHit {
  SearchHit(this.item, this.score);
  final MemoryItem item;
  final double score;
}

/// "The notes box remembers": meaning-based search over notes and recent
/// email, entirely on the phone. Uses Needle 3 embeddings through Cactus
/// when available and falls back to keyword search otherwise.
class MemoryService extends ChangeNotifier {
  MemoryService({required this.notes, required this.email, required this.ai}) {
    notes.addListener(_onNotesChanged);
    ai.addListener(_onAiChanged);
  }

  final NotesService notes;
  final EmailService email;
  final LocalAi ai;

  static const _mailFile = 'mail_cache.json', _vecFile = 'memory_vectors.json';
  final Map<String, EmailItem> _mail = {};
  final Map<String, _Vec> _vectors = {};
  DateTime? lastMailSync;
  bool syncing = false;
  String? syncError;
  Timer? _debounce;
  bool _wasEmbedding = false;

  static const keepMailDays = 90;
  static const maxMail = 400;

  bool get meaningSearch => ai.canEmbed;
  int get mailCount => _mail.length;

  Future<void> load() async {
    try {
      final raw = await store.readText(_mailFile);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        lastMailSync = DateTime.tryParse(j['synced'] as String? ?? '');
        for (final m in (j['mail'] as List? ?? [])) {
          final e = EmailItem.fromJson(m as Map<String, dynamic>);
          _mail[e.id] = e;
        }
      }
    } catch (_) {}
    try {
      final raw = await store.readText(_vecFile);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        j.forEach((k, v) => _vectors[k] = _Vec.fromJson(v as Map<String, dynamic>));
      }
    } catch (_) {}
    _wasEmbedding = ai.canEmbed;
  }

  // ------------------------------------------------------------------ items

  List<MemoryItem> _items(MemorySource source) => [
        if (source != MemorySource.mail) ...notes.notes.map(MemoryItem.fromNote),
        if (source != MemorySource.notes) ..._mail.values.map(MemoryItem.fromEmail),
      ];

  List<EmailItem> get cachedMail =>
      _mail.values.toList()..sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));

  // ------------------------------------------------------------------ indexing

  void _onNotesChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () => _reindex());
  }

  void _onAiChanged() {
    // Needle just finished loading: build the meaning index in the background.
    if (ai.canEmbed && !_wasEmbedding) _reindex();
    _wasEmbedding = ai.canEmbed;
  }

  /// Embeds any items whose text changed since they were last embedded.
  Future<void> _reindex() async {
    if (!ai.canEmbed) return;
    final items = _items(MemorySource.all);
    final todo = items.where((i) => _vectors[i.id]?.hash != _hash(i.searchText)).toList();
    // forget vectors of deleted things
    final live = items.map((i) => i.id).toSet();
    _vectors.removeWhere((k, _) => !live.contains(k));
    for (var i = 0; i < todo.length; i += 16) {
      final batch = todo.sublist(i, math.min(i + 16, todo.length));
      final vecs = await ai.embed(batch.map((b) => _clip(b.searchText)).toList());
      if (vecs == null) return;
      for (var k = 0; k < batch.length; k++) {
        _vectors[batch[k].id] = _Vec(_hash(batch[k].searchText), vecs[k]);
      }
    }
    await _saveVectors();
    notifyListeners();
  }

  /// Fetches the last month of inbox mail into the local search cache.
  Future<void> syncMail({bool force = false}) async {
    if (syncing || !email.isConfigured || !await email.isSignedIn()) return;
    if (!force && lastMailSync != null && DateTime.now().difference(lastMailSync!) < const Duration(minutes: 15)) {
      return;
    }
    syncing = true;
    syncError = null;
    notifyListeners();
    try {
      addEmails(await email.fetchRecent(days: 30, max: 60), save: false);
      lastMailSync = DateTime.now();
      await _saveMail();
      await _reindex();
    } catch (e) {
      syncError = '$e';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// Adds emails the mailbox just fetched (e.g. the unread ones).
  void addEmails(List<EmailItem> items, {bool save = true}) {
    for (final e in items) {
      _mail[e.id] = e;
    }
    final cutoff = DateTime.now().subtract(const Duration(days: keepMailDays));
    _mail.removeWhere((_, e) => e.date != null && e.date!.isBefore(cutoff));
    if (_mail.length > maxMail) {
      final sorted = cachedMail;
      for (final e in sorted.skip(maxMail)) {
        _mail.remove(e.id);
      }
    }
    if (save) {
      _saveMail();
      _reindex();
    }
    notifyListeners();
  }

  /// Forgets all cached mail (e.g. when the mailbox is disconnected).
  Future<void> clearMail() async {
    _mail.clear();
    lastMailSync = null;
    _vectors.removeWhere((k, _) => !k.startsWith('note:'));
    await _saveMail();
    await _saveVectors();
    notifyListeners();
  }

  // ------------------------------------------------------------------ search

  /// Finds the notes/emails that best match [query], best first.
  Future<List<SearchHit>> search(String query, {MemorySource source = MemorySource.all, int limit = 8}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final window = _timeWindow(q);
    var items = _items(source);
    if (window != null) {
      items = items.where((i) => !i.date.isBefore(window.$1) && i.date.isBefore(window.$2)).toList();
    }
    if (items.isEmpty) return [];

    final kw = _KeywordIndex(items);
    final kwScores = kw.score(_stripTimeWords(q));
    List<double>? qv;
    if (ai.canEmbed) {
      await _reindex();
      qv = (await ai.embed([_clip(q)]))?.first;
    }

    final hits = <SearchHit>[];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final k = kwScores[i];
      double score;
      final v = _vectors[it.id];
      if (qv != null && v != null && v.vector.length == qv.length) {
        final cos = _cosine(qv, v.vector);
        score = 0.72 * cos + 0.28 * k;
      } else {
        score = k;
      }
      // a time phrase on its own ("notes from yesterday") lists everything in range
      if (window != null && _KeywordIndex._terms(_stripTimeWords(q)).isEmpty) score = math.max(score, 0.5);
      hits.add(SearchHit(it, score));
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    final best = hits.isEmpty ? 0.0 : hits.first.score;
    final floor = qv != null ? math.max(0.3, best * 0.72) : math.max(0.12, best * 0.5);
    return hits.where((h) => h.score >= floor).take(limit).toList();
  }

  /// Notes that relate to an email, or emails that relate to a note.
  Future<List<SearchHit>> related(MemoryItem item, {int limit = 3}) async {
    final other = item.isNote ? MemorySource.mail : MemorySource.notes;
    final candidates = _items(other);
    if (candidates.isEmpty) return [];
    final v = _vectors[item.id];
    final kw = _KeywordIndex(candidates);
    final kwScores = kw.score(item.searchText, overlapOnly: true);
    final hits = <SearchHit>[];
    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      final cv = _vectors[c.id];
      final k = kwScores[i];
      double s;
      if (v != null && cv != null && cv.vector.length == v.vector.length) {
        final cos = _cosine(v.vector, cv.vector);
        s = cos > 0.62 || (cos > 0.5 && k > 0.15) ? 0.7 * cos + 0.3 * k : 0;
      } else {
        s = k >= 0.34 ? k : 0;
      }
      if (s > 0) hits.add(SearchHit(c, s));
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList();
  }

  /// For freshly arrived mail: pairs of (email, the note it relates to).
  Future<List<(EmailItem, VoiceNote)>> connections(List<EmailItem> fresh) async {
    final out = <(EmailItem, VoiceNote)>[];
    for (final e in fresh) {
      final r = await related(MemoryItem.fromEmail(e), limit: 1);
      if (r.isNotEmpty && r.first.item.note != null) out.add((e, r.first.item.note!));
    }
    return out;
  }

  // ------------------------------------------------------------------ helpers

  static String _clip(String s) => s.length > 1200 ? s.substring(0, 1200) : s;

  static int _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  static double _cosine(List<double> a, List<double> b) {
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  static final _timeRe = RegExp(
      r'\b(today|yesterday|this week|last week|this month|last month|(on |last )?(monday|tuesday|wednesday|thursday|friday|saturday|sunday))\b',
      caseSensitive: false);

  static String _stripTimeWords(String q) =>
      q.replaceAll(_timeRe, ' ').replaceAll(RegExp(r'\b(from|on|in|during)\s*$', caseSensitive: false), '');

  /// "yesterday", "last week", "on Tuesday"… → a date range.
  static (DateTime, DateTime)? _timeWindow(String q) {
    final m = _timeRe.firstMatch(q.toLowerCase());
    if (m == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final word = m.group(0)!;
    DateTime d(int days) => today.add(Duration(days: days));
    final weekStart = d(-(now.weekday - 1));
    switch (word) {
      case 'today':
        return (today, d(1));
      case 'yesterday':
        return (d(-1), today);
      case 'this week':
        return (weekStart, d(1));
      case 'last week':
        return (weekStart.subtract(const Duration(days: 7)), weekStart);
      case 'this month':
        return (DateTime(now.year, now.month), d(1));
      case 'last month':
        return (DateTime(now.year, now.month - 1), DateTime(now.year, now.month));
    }
    const days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    final dayName = days.firstWhere((x) => word.contains(x), orElse: () => '');
    if (dayName.isEmpty) return null;
    var back = (now.weekday - 1 - days.indexOf(dayName)) % 7;
    if (back == 0 && word.startsWith('last')) back = 7;
    final start = d(-back);
    return (start, start.add(const Duration(days: 1)));
  }

  Future<void> _saveMail() async {
    await store.writeText(_mailFile, jsonEncode({
      'synced': lastMailSync?.toIso8601String(),
      'mail': _mail.values.map((e) => e.toJson()).toList(),
    }));
  }

  Future<void> _saveVectors() async {
    await store.writeText(_vecFile, jsonEncode(_vectors.map((k, v) => MapEntry(k, v.toJson()))));
  }

  @override
  void dispose() {
    notes.removeListener(_onNotesChanged);
    ai.removeListener(_onAiChanged);
    _debounce?.cancel();
    super.dispose();
  }
}

class _Vec {
  _Vec(this.hash, this.vector);
  final int hash;
  final List<double> vector;

  Map<String, dynamic> toJson() => {'h': hash, 'v': [for (final x in vector) double.parse(x.toStringAsFixed(5))]};
  static _Vec fromJson(Map<String, dynamic> j) =>
      _Vec((j['h'] as num).toInt(), [for (final x in (j['v'] as List)) (x as num).toDouble()]);
}

/// Small keyword scorer used on its own (no Needle) and blended with
/// meaning scores (with Needle). Light stemming + idf weighting + prefixes.
class _KeywordIndex {
  _KeywordIndex(List<MemoryItem> items) {
    docs = [for (final i in items) _terms(i.searchText).toSet()];
    for (final d in docs) {
      for (final t in d) {
        df[t] = (df[t] ?? 0) + 1;
      }
    }
  }

  late final List<Set<String>> docs;
  final Map<String, int> df = {};

  double _idf(String t) => math.log(1 + docs.length / (1 + (df[t] ?? 0)));

  /// Scores 0..1 per document.
  List<double> score(String query, {bool overlapOnly = false}) {
    final q = _terms(query).toSet().toList();
    if (q.isEmpty) return List.filled(docs.length, 0);
    final total = q.fold<double>(0, (s, t) => s + _idf(t));
    return [
      for (final d in docs)
        () {
          var s = 0.0;
          for (final t in q) {
            if (d.contains(t)) {
              s += _idf(t);
            } else if (!overlapOnly && t.length >= 4 && d.any((w) => w.length >= 4 && (w.startsWith(t) || t.startsWith(w)))) {
              s += _idf(t) * 0.6;
            }
          }
          return total == 0 ? 0.0 : (s / total).clamp(0.0, 1.0);
        }()
    ];
  }

  static const _stop = {
    'a', 'an', 'the', 'and', 'or', 'but', 'of', 'to', 'in', 'on', 'at', 'for', 'with', 'about', 'from', 'by', 'is',
    'are', 'was', 'were', 'be', 'been', 'it', 'its', 'this', 'that', 'these', 'those', 'i', 'me', 'my', 'we', 'our',
    'you', 'your', 'he', 'she', 'they', 'them', 'his', 'her', 'their', 'what', 'which', 'who', 'when', 'where', 'why',
    'how', 'did', 'do', 'does', 'say', 'said', 'tell', 'find', 'search', 'show', 'any', 'anything', 'some', 'note',
    'notes', 'email', 'emails', 'mail', 'inbox', 'message', 'messages', 'there', 'have', 'has', 'had', 'can', 'could',
    'should', 'would', 'will', 'just', 'so', 'um', 'uh', 'like', 'get', 'got', 'mention', 'mentioned', 'remind',
    'wrote', 'write', 'sent', 'send', 'anyone', 'someone', 'please', 're', 'fwd', 'fw',
  };

  static Iterable<String> _terms(String s) sync* {
    for (final raw in s.toLowerCase().split(RegExp(r"[^a-z0-9à-ÿ']+"))) {
      var w = raw.replaceAll("'", '');
      if (w.length < 2 || _stop.contains(w)) continue;
      if (w.length > 4 && w.endsWith('ies')) {
        w = '${w.substring(0, w.length - 3)}y';
      } else if (w.length > 5 && w.endsWith('ing')) {
        w = w.substring(0, w.length - 3);
      } else if (w.length > 4 && w.endsWith('ed')) {
        w = w.substring(0, w.length - 2);
      } else if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) {
        w = w.substring(0, w.length - 1);
      }
      yield w;
    }
  }
}
