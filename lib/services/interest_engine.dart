import 'dart:convert';
import 'dart:math';

/// Everything Mochi notices about what you enjoy. Like a feed ranker, it
/// learns from what you *do* (open, watch for a while, skip, come back for
/// another) as well as what you *say* ("I love cats") and rate (👍 / 👎).
///
/// How it works, in short:
///  * Every thing Mochi brings has **features**: its kind (`kind:song`),
///    and what it's about (`artist:phoebe bridgers`, `genre:indie pop`,
///    `topic:cats`, `tag:cozy`).
///  * Each **signal** adds a weight to those features. Weights are summed
///    with **time decay** (half-life 30 days), so new interests rise and old
///    ones fade, the way "recent activity" counts more on big platforms.
///  * The **kind** (song / video / meme / game) is chosen per **context**
///    (your mood and the time of day) with **Thompson sampling** over Beta
///    distributions: it mostly brings what has worked in that context, but
///    keeps trying the others now and then.
///  * The **topic** is ranked by interest score + a small **exploration
///    bonus** for things it hasn't shown much (UCB), minus **fatigue** for
///    things shown recently. Muted things are never picked.
///  * It all stays on the phone. Only a short summary of your top interests
///    is sent to your chosen cloud AI, and only when it's helping choose.
class InterestEngine {
  InterestEngine({DateTime Function()? clock, Random? random})
      : _now = clock ?? DateTime.now,
        _rand = random ?? Random();

  final DateTime Function() _now;
  final Random _rand;

  static const halfLife = Duration(days: 30);
  static const contextHalfLife = Duration(days: 45);

  final Map<String, FeatureStat> features = {};
  final Map<String, BetaStat> contexts = {}; // "mood:sad|kind:video", "time:night|kind:song"
  final Set<String> muted = {};
  bool paused = false;

  // ------------------------------------------------------------------ signals

  /// Weight of each signal on the item's features.
  static double weightOf(Signal s, {Duration? dwell}) => switch (s) {
        Signal.said => 3.0,
        Signal.saidDislike => -4.0,
        Signal.noteMention => 1.5,
        Signal.askedFor => 2.0,
        Signal.shown => 0.0, // counts an impression only
        Signal.opened => 1.0,
        Signal.watched => _dwellWeight(dwell ?? Duration.zero),
        Signal.liked => 3.0,
        Signal.disliked => -3.0,
        Signal.another => 0.3, // "more of this kind" (topic gets a small minus, see record)
        Signal.somethingElse => -0.6,
        Signal.skipped => -0.4, // closed without opening
      };

  /// Long sessions mean real interest; a quick bounce means a miss.
  static double _dwellWeight(Duration d) {
    final s = d.inSeconds;
    if (s < 10) return -0.7;
    if (s < 45) return 0.3;
    if (s < 180) return 1.5;
    return 2.5;
  }

  /// Whether the signal counts as a win for the context bandit.
  static double? _reward(Signal s, double w) => switch (s) {
        Signal.opened || Signal.liked || Signal.askedFor => 1.0,
        Signal.watched => w > 0 ? min(1.0, w / 2) : 0.0,
        Signal.another => 0.6,
        Signal.disliked || Signal.skipped || Signal.somethingElse => 0.0,
        _ => null,
      };

  /// Records a signal on [keys] (e.g. `['kind:song', 'artist:x', 'genre:pop']`).
  /// [mood] adds it to the mood / time-of-day context for the item's kind.
  void record(Signal s, List<String> keys, {String? mood, Duration? dwell, String? label}) {
    if (paused || keys.isEmpty) return;
    final now = _now();
    final w = weightOf(s, dwell: dwell);
    for (final k in keys) {
      final f = features.putIfAbsent(k, () => FeatureStat(k));
      if (label != null && !k.startsWith('kind:')) f.label ??= label;
      var wk = w;
      // "Another one" likes the kind but this exact topic wasn't quite it.
      if (s == Signal.another && !k.startsWith('kind:')) wk = -0.4;
      if (s == Signal.somethingElse && !k.startsWith('kind:')) wk = -0.2;
      f.add(wk, now);
      if (s == Signal.shown) f.shows++;
      if (s == Signal.opened) f.opens++;
      f.counts[s.name] = (f.counts[s.name] ?? 0) + 1;
      if (s == Signal.shown) f.lastShown = now;
    }
    final kind = keys.firstWhere((k) => k.startsWith('kind:'), orElse: () => '');
    final r = _reward(s, w);
    if (kind.isNotEmpty && r != null) {
      for (final c in [if (mood != null) 'mood:$mood|$kind', 'time:${timeBucket(now)}|$kind']) {
        contexts.putIfAbsent(c, () => BetaStat()).add(r, now);
      }
    }
  }

  static String timeBucket(DateTime t) => switch (t.hour) {
        >= 5 && < 12 => 'morning',
        >= 12 && < 17 => 'afternoon',
        >= 17 && < 22 => 'evening',
        _ => 'night',
      };

  // ------------------------------------------------------------------ reading

  /// Decayed interest score (can be negative).
  double score(String key) => features[key]?.value(_now()) ?? 0;

  /// 0..1 "how sure Mochi is you like this" for display.
  double affinity(String key) {
    final v = score(key);
    return v <= 0 ? 0 : 1 - exp(-v / 5);
  }

  bool isMuted(String key) => muted.contains(key) || score(key) <= -3;

  /// Strongest interests, optionally only of some types ("artist", "topic"…).
  List<FeatureStat> top({Set<String>? types, int limit = 20, bool includeKinds = false}) {
    final now = _now();
    final l = features.values
        .where((f) => (includeKinds || !f.key.startsWith('kind:')) && !muted.contains(f.key))
        .where((f) => types == null || types.contains(f.type))
        .where((f) => f.value(now) > 0.25)
        .toList()
      ..sort((a, b) => b.value(now).compareTo(a.value(now)));
    // "Phoebe Bridgers" as a topic you said and as an artist you played: show once
    final seen = <String>{};
    return l.where((f) => seen.add((f.label ?? f.name).toLowerCase())).take(limit).toList();
  }

  List<FeatureStat> get dislikes {
    final now = _now();
    return features.values.where((f) => !f.key.startsWith('kind:') && (f.value(now) <= -2 || muted.contains(f.key))).toList();
  }

  // ------------------------------------------------------------------ choosing

  /// Thompson sampling over kinds for this mood and time of day. [prior] is
  /// the cold-start guess per kind (roughly 0.5..2). [avoid] is down-weighted
  /// (the kind shown last time).
  String chooseKind(List<String> kinds, {required String mood, Map<String, double> prior = const {}, String? avoid}) {
    final now = _now();
    final time = timeBucket(now);
    // ~10% of the time try any kind: keeps learning, avoids a filter bubble
    final open = kinds.where((k) => !isMuted('kind:$k')).toList();
    if (open.length > 1 && _rand.nextDouble() < 0.1) return open[_rand.nextInt(open.length)];
    String? best;
    var bestScore = -1.0;
    for (final k in kinds) {
      final p = prior[k] ?? 1.0;
      final m = contexts['mood:$mood|kind:$k']?.decayed(now) ?? const (0.0, 0.0);
      final t = contexts['time:$time|kind:$k']?.decayed(now) ?? const (0.0, 0.0);
      // prior pseudo-counts: a cold start leans on the mood defaults
      final sMood = _betaSample(1 + p * 1.5 + m.$1, 1 + 1.5 + m.$2);
      final sTime = _betaSample(1 + t.$1, 1 + t.$2);
      final kindPref = 1 / (1 + exp(-score('kind:$k') / 3)); // 0.5 when unknown
      var s = 0.6 * sMood + 0.15 * sTime + 0.25 * kindPref;
      if (k == avoid) s *= 0.6;
      if (isMuted('kind:$k')) s *= 0.1;
      if (s > bestScore) {
        bestScore = s;
        best = k;
      }
    }
    return best ?? kinds.first;
  }

  /// Ranks [candidates] (feature keys like `artist:x`, `topic:cats`) and
  /// picks one: interest + exploration bonus − fatigue, sampled with a
  /// softmax so it isn't always the same. [defaults] are cold-start / new
  /// ideas that get a fair chance too (exploration).
  RankedPick? pickTopic(List<String> candidates, {List<String> defaults = const [], double explore = 0.12}) {
    final now = _now();
    final pool = <String>{...candidates, ...defaults}.where((k) => !isMuted(k)).toList();
    if (pool.isEmpty) return null;
    // ε-exploration: sometimes try something new on purpose
    if (defaults.isNotEmpty && _rand.nextDouble() < explore) {
      final fresh = defaults.where((d) => (features[d]?.shows ?? 0) < 2 && !isMuted(d)).toList();
      if (fresh.isNotEmpty) {
        final k = fresh[_rand.nextInt(fresh.length)];
        return RankedPick(k, 0, explored: true);
      }
    }
    final totalShows = pool.fold<int>(0, (a, k) => a + (features[k]?.shows ?? 0)) + 1;
    final scored = <String, double>{};
    for (final k in pool) {
      final f = features[k];
      final interest = f?.value(now) ?? (defaults.contains(k) ? 0.6 : 0);
      final ctr = f == null ? 0.5 : (f.opens + 1) / (f.shows + 2); // smoothed open rate
      final bonus = 0.8 * sqrt(log(totalShows + 1) / ((f?.shows ?? 0) + 1));
      var fatigue = 0.0;
      if (f?.lastShown != null) {
        final hours = now.difference(f!.lastShown!).inMinutes / 60;
        // shown an hour ago: strongly held back; a day ago: barely
        fatigue = (2.0 + 0.6 * max(0.0, interest)) * exp(-hours / 12);
      }
      scored[k] = interest + 1.5 * (ctr - 0.5) + bonus - fatigue;
    }
    // softmax sampling (temperature 0.8)
    final maxS = scored.values.reduce(max);
    final ws = {for (final e in scored.entries) e.key: exp((e.value - maxS) / 0.8)};
    var r = _rand.nextDouble() * ws.values.reduce((a, b) => a + b);
    for (final e in ws.entries) {
      r -= e.value;
      if (r <= 0) return RankedPick(e.key, scored[e.key]!);
    }
    final k = ws.keys.last;
    return RankedPick(k, scored[k]!);
  }

  /// A short, honest reason: "You've liked 2 songs by Phoebe Bridgers."
  String? explain(String key, {String? mood, String? kind}) {
    final f = features[key];
    if (f == null) return null;
    final name = f.label ?? f.name;
    final c = f.counts;
    if ((c['said'] ?? 0) > 0) return 'You told me you love $name.';
    if ((c['liked'] ?? 0) >= 2) return "You've given $name a thumbs up ${c['liked']} times.";
    if ((c['liked'] ?? 0) == 1) return 'You gave $name a thumbs up.';
    if ((c['askedFor'] ?? 0) > 0) return 'You asked me for $name before.';
    if ((c['watched'] ?? 0) + (c['opened'] ?? 0) >= 2) return 'You keep coming back to $name.';
    if ((c['noteMention'] ?? 0) > 0) return 'Your notes say you like $name.';
    if (mood != null && kind != null) {
      final m = contexts['mood:$mood|kind:$kind'];
      if (m != null && m.a >= 2 && m.mean > 0.6) return 'When you feel $mood, ${kind == 'song' ? 'a song' : 'this'} usually helps.';
    }
    return null;
  }

  /// What usually helps per mood, for the profile screen.
  Map<String, (String kind, double rate)> bestPerMood(List<String> kinds) {
    final now = _now();
    final out = <String, (String, double)>{};
    for (final mood in ['sad', 'bored', 'stressed', 'lonely', 'tired', 'okay']) {
      (String, double)? best;
      for (final k in kinds) {
        final b = contexts['mood:$mood|kind:$k'];
        if (b == null) continue;
        final (a, bb) = b.decayed(now);
        if (a + bb < 2) continue;
        final rate = (a + 1) / (a + bb + 2);
        if (best == null || rate > best.$2) best = (k, rate);
      }
      if (best != null) out[mood] = best;
    }
    return out;
  }

  // ------------------------------------------------------------------ manage

  void mute(String key) {
    muted.add(key);
  }

  void unmute(String key) {
    muted.remove(key);
    final f = features[key];
    if (f != null && f.value(_now()) < 0) f.reset(_now());
  }

  void forget(String key) {
    features.remove(key);
    muted.remove(key);
  }

  void clear() {
    features.clear();
    contexts.clear();
    muted.clear();
  }

  // ------------------------------------------------------------------ storage

  Map<String, dynamic> toJson() => {
        'v': 1,
        'paused': paused,
        'muted': muted.toList(),
        'features': {for (final f in features.values) f.key: f.toJson()},
        'contexts': {for (final e in contexts.entries) e.key: e.value.toJson()},
      };

  void loadJson(Map<String, dynamic> j) {
    clear();
    paused = j['paused'] == true;
    muted.addAll((j['muted'] as List? ?? []).map((e) => '$e'));
    for (final e in (j['features'] as Map? ?? {}).entries) {
      features['${e.key}'] = FeatureStat.fromJson('${e.key}', (e.value as Map).cast<String, dynamic>());
    }
    for (final e in (j['contexts'] as Map? ?? {}).entries) {
      contexts['${e.key}'] = BetaStat.fromJson((e.value as Map).cast<String, dynamic>());
    }
    // keep storage small: drop faded, unimportant features
    final now = _now();
    if (features.length > 600) {
      final l = features.values.toList()..sort((a, b) => a.value(now).abs().compareTo(b.value(now).abs()));
      for (final f in l.take(features.length - 500)) {
        if (!muted.contains(f.key)) features.remove(f.key);
      }
    }
  }

  String encode() => jsonEncode(toJson());

  // ------------------------------------------------------------------ math

  /// Beta(a, b) sample via two Gamma samples (Marsaglia–Tsang).
  double _betaSample(double a, double b) {
    final x = _gamma(a), y = _gamma(b);
    return x / (x + y);
  }

  double _gamma(double k) {
    if (k < 1) return _gamma(k + 1) * pow(_rand.nextDouble(), 1 / k);
    final d = k - 1 / 3, c = 1 / sqrt(9 * d);
    while (true) {
      double x, v;
      do {
        x = _normal();
        v = 1 + c * x;
      } while (v <= 0);
      v = v * v * v;
      final u = _rand.nextDouble();
      if (u < 1 - 0.0331 * x * x * x * x) return d * v;
      if (log(u) < 0.5 * x * x + d * (1 - v + log(v))) return d * v;
    }
  }

  double _normal() {
    final u1 = max(1e-12, _rand.nextDouble()), u2 = _rand.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }
}

/// Things the app notices.
enum Signal { said, saidDislike, noteMention, askedFor, shown, opened, watched, liked, disliked, another, somethingElse, skipped }

class RankedPick {
  RankedPick(this.key, this.score, {this.explored = false});
  final String key;
  final double score;

  /// True when Mochi picked it to try something new.
  final bool explored;
}

/// One feature's running, time-decayed interest.
class FeatureStat {
  FeatureStat(this.key);
  final String key;
  String? label;
  double _score = 0;
  DateTime? _at;
  int shows = 0;
  int opens = 0;
  DateTime? lastShown;
  final Map<String, int> counts = {};

  /// "artist", "genre", "topic", "tag", "kind"
  String get type => key.contains(':') ? key.substring(0, key.indexOf(':')) : 'topic';
  String get name => key.contains(':') ? key.substring(key.indexOf(':') + 1) : key;

  double value(DateTime now) {
    if (_at == null) return 0;
    final age = now.difference(_at!).inMinutes / InterestEngine.halfLife.inMinutes;
    return _score * pow(0.5, max(0, age));
  }

  /// Scores are kept in −12..12 so nothing becomes "100% forever".
  void add(double w, DateTime now) {
    _score = (value(now) + w).clamp(-12.0, 12.0);
    _at = now;
  }

  void reset(DateTime now) {
    _score = 0;
    _at = now;
  }

  Map<String, dynamic> toJson() => {
        's': double.parse(_score.toStringAsFixed(3)),
        if (_at != null) 't': _at!.millisecondsSinceEpoch,
        if (label != null) 'l': label,
        'sh': shows,
        'op': opens,
        if (lastShown != null) 'ls': lastShown!.millisecondsSinceEpoch,
        'c': counts,
      };

  static FeatureStat fromJson(String key, Map<String, dynamic> j) {
    final f = FeatureStat(key)
      .._score = (j['s'] as num? ?? 0).toDouble()
      .._at = j['t'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['t'] as int)
      ..label = j['l'] as String?
      ..shows = j['sh'] as int? ?? 0
      ..opens = j['op'] as int? ?? 0
      ..lastShown = j['ls'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['ls'] as int);
    f.counts.addAll((j['c'] as Map? ?? {}).map((k, v) => MapEntry('$k', (v as num).toInt())));
    return f;
  }
}

/// Wins (a) and misses (b) for one context, both decayed over time.
class BetaStat {
  double a = 0, b = 0;
  DateTime? _at;

  (double, double) decayed(DateTime now) {
    if (_at == null) return (0, 0);
    final age = now.difference(_at!).inMinutes / InterestEngine.contextHalfLife.inMinutes;
    final k = pow(0.5, max(0, age)).toDouble();
    return (a * k, b * k);
  }

  double get mean => (a + 1) / (a + b + 2);

  void add(double reward, DateTime now) {
    final (da, db) = decayed(now);
    a = da + reward;
    b = db + (1 - reward);
    _at = now;
  }

  Map<String, dynamic> toJson() => {'a': a, 'b': b, if (_at != null) 't': _at!.millisecondsSinceEpoch};

  static BetaStat fromJson(Map<String, dynamic> j) => BetaStat()
    ..a = (j['a'] as num? ?? 0).toDouble()
    ..b = (j['b'] as num? ?? 0).toDouble()
    .._at = j['t'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['t'] as int);
}
