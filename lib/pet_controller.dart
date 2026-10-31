import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'ai/local_ai.dart';
import 'ai/model_manager.dart';
import 'models/character.dart';
import 'platform/store.dart' as store;
import 'services/account_service.dart';
import 'services/actions_service.dart';
import 'services/cheer_service.dart';
import 'services/email_service.dart';
import 'services/llm_service.dart';
import 'services/memory_service.dart';
import 'services/notes_service.dart';
import 'services/settings_service.dart';
import 'services/voice_service.dart';

/// What the pet is doing right now; the painter draws a pose for each.
enum PetMood {
  idle,
  walking,
  thinking,
  searching, // pulling books off the shelf
  reading, // holding an open book and talking
  mail, // rummaging in the mailbox / holding a letter
  listening, // holding the microphone
  dropping, // dropping a note into the box
  digging, // rummaging through the notes box while searching
  happy,
  sad,
  dancing, // bopping along to a song it brought you
}

/// What the pet holds in its paws.
enum HeldItem { none, book, letter, note, mic, gift }

/// Requests from the pet to the screen.
enum PetEvent { openSettings, openNotes, openFind, openMailSettings, newTreatFriend, composeMessage, getApp, cheer, support, openAccount }

/// Where the pet stands for each job, in room ("world") units on the
/// 10 x 10 isometric floor (see ui/room_layout.dart).
class Spots {
  static const home = Offset(5.0, 5.2);
  static const bookshelf = Offset(2.4, 6.2);
  static const mailbox = Offset(8.1, 9.0);
  static const mic = Offset(6.0, 2.7);
  static const notesBox = Offset(4.5, 7.1);

  /// Places on the rug the pet strolls to when it has nothing to do.
  static const wander = [
    Offset(5.0, 5.2), Offset(4.2, 6.2), Offset(6.0, 4.4), Offset(5.6, 6.4), Offset(3.8, 4.4),
  ];
}

class PetController extends ChangeNotifier {
  PetController({
    required this.settings,
    required this.llm,
    required this.email,
    required this.notes,
    required this.voice,
    required this.localAi,
    required this.models,
    required this.memory,
    required this.actions,
    required this.cheer,
    required this.account,
  }) {
    voice.speaking.addListener(notifyListeners);
  }

  final SettingsService settings;
  final LlmService llm;
  final EmailService email;
  final NotesService notes;
  final VoiceService voice;
  final LocalAi localAi;
  final ModelManager models;
  final MemoryService memory;
  final ActionsService actions;
  final CheerService cheer;
  final AccountService account;

  /// Set before [PetEvent.cheer]: the song / clip / meme / game to show.
  CheerItem? pendingCheer;

  /// Set before [PetEvent.composeMessage] / [PetEvent.getApp] is sent.
  MessageDraft? pendingDraft;
  String? pendingAppName;

  final _events = StreamController<PetEvent>.broadcast();
  Stream<PetEvent> get events => _events.stream;

  // ---- pose state read by the room painter ----
  Offset position = Spots.home;
  Offset _target = Spots.home;
  Completer<void>? _arrival;
  bool facingLeft = false;
  PetMood mood = PetMood.idle;
  HeldItem held = HeldItem.none;
  String? bubble;
  bool bubbleIsUser = false;
  bool get talking => voice.speaking.value;

  bool busy = false;
  String? _recordingPath;

  PetCharacter get character => PetCharacter.byId(settings.characterId);

  /// One-line status shown in the banner above the room.
  String get status {
    final n = character.name.split(' ').first;
    return switch (mood) {
      PetMood.searching => '$n is searching the bookshelf',
      PetMood.thinking => recording ? '$n is writing it down' : '$n is thinking',
      PetMood.mail => '$n is checking the mail',
      PetMood.listening => '$n is listening…',
      PetMood.dropping => '$n is filing your note',
      PetMood.digging => '$n is digging through your notes',
      PetMood.reading => '$n is reading to you',
      PetMood.walking => busy ? '$n is on the way' : '$n is wandering',
      PetMood.sad => '$n needs a hand',
      PetMood.happy => '$n is happy',
      PetMood.dancing => '$n is dancing with you',
      PetMood.idle => '$n is ready to help',
    };
  }

  // ------------------------------------------------------------------
  // Movement (driven by the room's ticker)
  // ------------------------------------------------------------------

  static const _speed = 3.2; // floor tiles per second
  double _clock = 0;
  double _nextWander = 6;

  /// Called every frame with the elapsed seconds.
  void tick(double dt) {
    _clock += dt;
    if (!busy && !recording && mood == PetMood.idle && _arrival == null && _clock > _nextWander) {
      _nextWander = _clock + 7 + (_clock * 997 % 6);
      final spot = Spots.wander[(_clock * 13).floor() % Spots.wander.length];
      walkTo(spot);
    }
    final delta = _target - position;
    final dist = delta.distance;
    if (dist < 0.02) {
      if (_arrival != null) {
        position = _target;
        final a = _arrival!;
        _arrival = null;
        if (mood == PetMood.walking) mood = PetMood.idle;
        a.complete();
        notifyListeners();
      }
      return;
    }
    final step = _speed * dt;
    position = step >= dist ? _target : position + delta / dist * step;
    // screen direction in the isometric view is x - y
    final screenDx = delta.dx - delta.dy;
    if (screenDx.abs() > 0.05) facingLeft = screenDx < 0;
    notifyListeners();
  }

  Future<void> walkTo(Offset spot) {
    if ((spot - position).distance < 0.02) return Future.value();
    _arrival?.complete();
    _target = spot;
    mood = PetMood.walking;
    _arrival = Completer<void>();
    notifyListeners();
    return _arrival!.future;
  }

  void _set({PetMood? mood, HeldItem? held, String? bubble, bool clearBubble = false}) {
    if (mood != null) this.mood = mood;
    if (held != null) this.held = held;
    if (clearBubble) {
      this.bubble = null;
      bubbleIsUser = false;
    } else if (bubble != null) {
      this.bubble = bubble;
      bubbleIsUser = false;
    }
    notifyListeners();
  }

  Timer? _bubbleTimer;
  void _clearBubbleLater([Duration d = const Duration(seconds: 6)]) {
    _bubbleTimer?.cancel();
    _bubbleTimer = Timer(d, () {
      if (!busy && !talking) _set(clearBubble: true);
    });
  }

  Future<void> _goHome() async {
    await walkTo(Spots.home);
    _set(mood: PetMood.idle, held: HeldItem.none);
  }

  void _reward() {
    final before = PetCharacter.all.where((c) => c.unlocked(settings.treats)).length;
    settings.addTreats(1);
    final after = PetCharacter.all.where((c) => c.unlocked(settings.treats)).length;
    if (after > before) _events.add(PetEvent.newTreatFriend);
  }

  Future<void> _fail(Object e) async {
    final msg = e is LlmException || e is EmailException
        ? e.toString()
        : 'Oops, something went wrong. Please try again.';
    debugPrint('Pet error: $e');
    _set(mood: PetMood.sad, held: HeldItem.none, bubble: msg);
    // out of free AI time: guests get the sign-up sheet (20 min a day)
    if (e is LlmException && e.outOfTime && !account.signedIn) _events.add(PetEvent.openAccount);
    await voice.say(msg);
  }

  /// Tapping the pet itself.
  Future<void> pet() async {
    if (busy || recording) return;
    _set(mood: PetMood.happy, bubble: _greetings[DateTime.now().second % _greetings.length]);
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!busy && !recording) _set(mood: PetMood.idle);
    _clearBubbleLater(const Duration(seconds: 2));
  }

  static const _greetings = [
    'Purr… tap RECORD and tell me something!',
    'Tap the bookshelf to ask me anything!',
    'I love helping you!',
    'Hehe, that tickles!',
  ];

  // ------------------------------------------------------------------
  // Find: search notes + mail (the main way to ask the pet things)
  // ------------------------------------------------------------------

  /// Handles anything typed or said to the pet. Returns search results when
  /// the request was a search, so the Find screen can show them.
  Future<FindResult?> ask(String text, {MemorySource? source}) async {
    text = text.trim();
    if (text.isEmpty || busy || recording) return null;
    if (source != null) return find(text, source: source);
    if (CheerService.isCrisis(text)) {
      await support(text);
      return null;
    }
    busy = true;
    _bubbleTimer?.cancel();
    bubble = text;
    bubbleIsUser = true;
    mood = PetMood.thinking;
    notifyListeners();
    RoutedRequest routed;
    try {
      routed = await localAi.route(text);
    } catch (_) {
      routed = LocalAi.keywordRoute(text);
    }
    busy = false;
    switch (routed.action) {
      case PetAction.searchMemory:
        return find(routed.text.isEmpty ? text : routed.text, source: routed.source, original: text);
      case PetAction.answerQuestion:
        await _guard(() => _answer(routed.text.isEmpty ? text : routed.text));
      case PetAction.checkEmail:
        await checkMail();
      case PetAction.saveNote:
        await addTypedNote(routed.text.isEmpty ? text : routed.text);
      case PetAction.readNotes:
        await _guard(_readNotesAloud);
      case PetAction.sendMessage:
        await draftMessage(routed.recipient, routed.text.isEmpty ? text : routed.text, channel: routed.channel);
      case PetAction.installApp:
        await getApp(routed.text.isEmpty ? text : routed.text);
      case PetAction.cheerUp:
        await cheerUp(CheerService.parseMood(routed.mood), want: CheerKindInfo.parse(routed.want), said: text, topic: routed.recipient);
    }
    return null;
  }

  /// The bookshelf box: questions about the world go to the books, and
  /// spoken jobs ("text Ana I'm late", "download Spotify", "note that…",
  /// "check my mail") are done instead. Notes/mail searches live in the
  /// notes box, so here they are treated as questions for the books.
  Future<void> talk(String text) async {
    text = text.trim();
    if (text.isEmpty || busy || recording) return;
    if (CheerService.isCrisis(text)) return support(text);
    cheer.learnFrom(text);
    _bubbleTimer?.cancel();
    bubble = text;
    bubbleIsUser = true;
    mood = PetMood.thinking;
    notifyListeners();
    RoutedRequest routed;
    try {
      routed = await localAi.route(text);
    } catch (_) {
      routed = LocalAi.keywordRoute(text);
    }
    // Needle sometimes calls a message an answer: double-check with the parser
    if (routed.action != PetAction.sendMessage) routed = LocalAi.parseMessage(text) ?? routed;
    // …and sometimes calls "I'm so bored" a question
    if (routed.action == PetAction.answerQuestion || routed.action == PetAction.searchMemory) {
      routed = LocalAi.cheerRoute(text) ?? routed;
    }
    switch (routed.action) {
      case PetAction.sendMessage:
        await draftMessage(routed.recipient, routed.text.isEmpty ? text : routed.text, channel: routed.channel);
      case PetAction.installApp:
        await getApp(routed.text.isEmpty ? text : routed.text);
      case PetAction.checkEmail:
        await checkMail();
      case PetAction.saveNote:
        await addTypedNote(routed.text.isEmpty ? text : routed.text);
      case PetAction.readNotes:
        await _guard(_readNotesAloud);
      case PetAction.cheerUp:
        await cheerUp(CheerService.parseMood(routed.mood), want: CheerKindInfo.parse(routed.want), said: text, topic: routed.recipient);
      case PetAction.searchMemory:
      case PetAction.answerQuestion:
        await askBookshelf(text);
    }
  }

  // ------------------------------------------------------------------
  // Cheer up: "I'm bored" / "I'm sad" → the pet fetches something you'll like
  // ------------------------------------------------------------------

  /// Comforts you, runs to the bookshelf, comes back with a present (a song
  /// preview, cat clip, meme or game) and hands it over. The screen shows it
  /// on [PetEvent.cheer]; [endCheer] puts it back and deletes the files.
  Future<void> cheerUp(Mood feeling, {CheerKind? want, String said = '', String topic = ''}) async {
    if (busy || recording) return;
    busy = true;
    _bubbleTimer?.cancel();
    try {
      final name = character.name.split(' ').first;
      final opening = want == null ? CheerService.comfort(feeling, name) : 'Coming right up!';
      _set(mood: feeling == Mood.okay ? PetMood.happy : PetMood.thinking, held: HeldItem.none, bubble: opening);
      // fetch while the pet talks and walks
      // (Future.wait listens right away, so a fast failure is never "unhandled")
      final work = Future.wait<Object?>([_planAndFetch(feeling, want, said, topic), voice.say(opening)]);
      await walkTo(Spots.bookshelf);
      facingLeft = true;
      _set(mood: PetMood.searching, bubble: want == null ? 'Something you\'ll like… hmm…' : 'Looking for ${want.label}…');
      final results = await Future.wait<Object?>([work, Future<void>.delayed(const Duration(milliseconds: 1600))]);
      final item = (results.first as List<Object?>).first as CheerItem;
      _set(mood: PetMood.happy, held: HeldItem.gift, bubble: 'Found it!');
      await Future.delayed(const Duration(milliseconds: 800));
      _set(mood: PetMood.walking, held: HeldItem.gift);
      await walkTo(Spots.home);
      facingLeft = false;
      final line = item.why.isNotEmpty
          ? item.why
          : switch (item.kind) {
              CheerKind.song => 'Here\'s a song for you: ${item.title}${item.subtitle.isEmpty ? '' : ' by ${item.subtitle}'}. Tap Play to open it on YouTube.',
              CheerKind.video => 'I found some ${item.title.toLowerCase()} for you. Tap Play to watch on YouTube.',
              CheerKind.meme => 'This one made me giggle.',
              CheerKind.game => 'I found a game for you: ${item.title}! Tap Play and it opens right here.',
            };
      _set(mood: PetMood.happy, held: HeldItem.gift, bubble: line);
      await voice.say(line);
      pendingCheer = item;
      cheer.shown(item);
      _set(mood: item.kind == CheerKind.song ? PetMood.dancing : PetMood.happy, held: HeldItem.none);
      _events.add(PetEvent.cheer);
      // stays busy (no wandering off) until the screen calls endCheer
    } catch (e) {
      busy = false;
      final msg = e is CheerException ? e.message : 'Oops, the shelf wobbled. Try again?';
      debugPrint('Cheer failed: $e');
      _set(mood: PetMood.sad, held: HeldItem.none, bubble: msg);
      await voice.say(msg);
      await _goHome();
      _clearBubbleLater();
    }
  }

  Future<CheerItem> _planAndFetch(Mood feeling, CheerKind? want, String said, [String topic = '']) async {
    CheerPlan? plan;
    cheer.setMood(feeling);
    // named it? ("play some Taylor Swift", "videos of otters") → that exactly
    if (want == CheerKind.song || want == CheerKind.video) {
      var named = topic.trim().toLowerCase();
      if (named.isNotEmpty && want == CheerKind.video && !named.contains('video')) named = '$named videos';
      if (named.isEmpty) named = CheerService.topicFrom(said, want!);
      if (named.isNotEmpty) {
        cheer.askedFor(want!, named);
        plan = CheerPlan(want!, query: named, feature: 'topic:${named.replaceAll(RegExp(r'\s+(videos?|clips?)$'), '')}');
      }
    }
    if (plan == null && await llm.isConfigured()) {
      try {
        final hints = <String>[];
        try {
          final hits = await memory.search('things I love enjoy favourite music songs bands shows games', source: MemorySource.notes, limit: 3);
          for (final h in hits) {
            final t = h.item.note?.text ?? '';
            if (t.isNotEmpty) hints.add(t.length > 140 ? '${t.substring(0, 140)}…' : t);
          }
        } catch (_) {}
        final reply = await llm
            .chat(CheerService.planSystem, cheer.planPrompt(feeling, said, want: want, noteHints: hints))
            .timeout(const Duration(seconds: 10));
        plan = cheer.parsePlan(reply, want: want);
      } catch (e) {
        debugPrint('Cheer plan by AI failed, choosing locally: $e');
      }
    }
    plan ??= cheer.localPlan(feeling, want: want);
    if (plan.kind == CheerKind.song && plan.query.isEmpty) {
      final local = cheer.localPlan(feeling, want: CheerKind.song);
      plan = CheerPlan(CheerKind.song, query: local.query, why: plan.why.isNotEmpty ? plan.why : local.why);
    }
    try {
      return await cheer.fetch(plan);
    } on CheerException {
      if (want != null) rethrow;
      // the pet's own pick failed (e.g. a source is down): try the others
      for (final k in [CheerKind.video, CheerKind.song, CheerKind.game]) {
        if (k == plan.kind) continue;
        try {
          return await cheer.fetch(cheer.localPlan(feeling, want: k));
        } on CheerException {
          // try the next one
        }
      }
      rethrow;
    }
  }

  /// Called when the cheer card closes. Deletes the files and the pet puts
  /// the present back on the shelf. [next]: "another" (same kind) or
  /// "different" (something else).
  Future<void> endCheer(CheerItem item, {String next = ''}) async {
    pendingCheer = null;
    cheer.closed(item, next);
    await cheer.discard(item);
    busy = false;
    if (next == 'another' || next == 'different') {
      CheerKind? want;
      final mood = cheer.mood;
      if (next == 'another') {
        want = item.kind;
      } else {
        want = cheer.otherKind(item.kind); // the ranker's best kind that isn't this one
      }
      await cheerUp(mood, want: want);
      return;
    }
    busy = true;
    try {
      _set(mood: PetMood.walking, held: HeldItem.gift, bubble: 'Putting it back on the shelf…');
      await walkTo(Spots.bookshelf);
      facingLeft = true;
      _set(mood: PetMood.searching, held: HeldItem.none);
      await Future.delayed(const Duration(milliseconds: 700));
      _set(mood: PetMood.happy, bubble: 'Feel a little better? I\'m always here.');
      await Future.delayed(const Duration(milliseconds: 900));
      await _goHome();
    } finally {
      busy = false;
      notifyListeners();
      _clearBubbleLater();
    }
  }

  /// Opening a game, song or video Mochi found earns a treat (once each).
  void playedCheer() => _reward();

  /// Someone may be in danger: no memes. The pet answers kindly and the
  /// screen shows where to find a real person to talk to.
  Future<void> support(String text) async {
    _bubbleTimer?.cancel();
    const line = "I'm really glad you told me. You matter, and you deserve to talk to a real person right now. "
        "Can I show you someone to call or text?";
    _set(mood: PetMood.idle, held: HeldItem.none, bubble: line);
    _events.add(PetEvent.support);
    await voice.say(line);
  }

  /// Drafts a message to a friend. Nothing is sent: the screen shows a
  /// letter card the user can edit, and Send opens their own messaging app.
  Future<void> draftMessage(String recipient, String said, {String channel = ''}) async {
    if (busy) return;
    busy = true;
    try {
      await walkTo(Spots.mic); // the desk
      facingLeft = false;
      _set(mood: PetMood.thinking, held: HeldItem.letter, bubble: 'Writing a note to ${recipient.isEmpty ? 'your friend' : recipient}…');
      var subject = '';
      var body = said.trim();
      final about = RegExp(r'^about\s+(.+)$', caseSensitive: false).firstMatch(body);
      if (about != null) {
        subject = _capitalise(about.group(1)!.replaceAll(RegExp(r'[.!?]+$'), ''));
        body = '';
      } else {
        body = _capitalise(body);
        if (!RegExp(r'[.!?…)]$').hasMatch(body)) body = '$body.';
      }
      final d = MessageDraft(
        recipientName: _capitalise(recipient),
        body: body,
        subject: subject,
        channel: switch (channel) {
          'email' => MessageChannel.email,
          'whatsapp' => MessageChannel.whatsapp,
          _ => MessageChannel.text,
        },
      );
      try {
        final matches = recipient.isEmpty ? <ContactMatch>[] : await actions.findContacts(recipient.replaceFirst(RegExp(r'^my\s+', caseSensitive: false), ''));
        if (matches.length == 1) {
          d.contact = matches.first;
          _pickRoute(d);
        }
      } catch (_) {
        // no contacts permission: the card lets the user pick or type
      }
      // A topic but no words yet ("email mom about dinner"): let the AI write it.
      if (d.body.isEmpty && await llm.isConfigured()) {
        try {
          final r = await llm.polishMessage(recipient: d.recipientName, said: said, email: d.channel == MessageChannel.email);
          d.body = r.body;
          if (d.subject.isEmpty) d.subject = r.subject;
        } catch (_) {}
      }
      pendingDraft = d;
      _set(mood: PetMood.happy, bubble: 'Here\'s your message. Check it, then tap Send.');
      _events.add(PetEvent.composeMessage);
    } finally {
      busy = false;
      notifyListeners();
      _clearBubbleLater();
    }
  }

  /// Chooses a phone number or email for the draft's channel.
  void _pickRoute(MessageDraft d) {
    final c = d.contact;
    if (c == null) return;
    if (d.channel == MessageChannel.email) {
      d.to = c.emails.isEmpty ? null : c.emails.first.value;
      if (d.to == null && c.phones.isNotEmpty) {
        d.channel = MessageChannel.text;
        d.to = _bestPhone(c);
      }
    } else {
      d.to = _bestPhone(c);
      if (d.to == null && c.emails.isNotEmpty) {
        d.channel = MessageChannel.email;
        d.to = c.emails.first.value;
      }
    }
  }

  static String? _bestPhone(ContactMatch c) {
    if (c.phones.isEmpty) return null;
    return (c.phones.firstWhere((p) => p.label == 'mobile' || p.label == 'iPhone', orElse: () => c.phones.first)).value;
  }

  void applyContact(MessageDraft d, ContactMatch c) {
    d.contact = c;
    d.recipientName = c.name;
    _pickRoute(d);
  }

  static String _capitalise(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Called when the user taps Send on the letter card.
  Future<void> sendDraft(MessageDraft d) async {
    await actions.openComposer(d);
    pendingDraft = null;
    _reward();
    // a little celebration: the pet posts the letter
    if (busy) return;
    busy = true;
    try {
      _set(mood: PetMood.walking, held: HeldItem.letter, bubble: 'Off it goes to ${d.recipientName}!');
      await walkTo(Spots.mailbox);
      facingLeft = true;
      _set(mood: PetMood.mail, held: HeldItem.letter);
      await Future.delayed(const Duration(milliseconds: 900));
      _set(mood: PetMood.happy, held: HeldItem.none);
      await Future.delayed(const Duration(milliseconds: 700));
      await _goHome();
    } finally {
      busy = false;
      notifyListeners();
      _clearBubbleLater();
    }
  }

  /// "Download Spotify": the pet finds it in the store; the user taps Get.
  Future<void> getApp(String name) async {
    name = name.trim().replaceFirst(RegExp(r'\s+app$', caseSensitive: false), '');
    if (name.isEmpty) return;
    pendingAppName = name;
    _set(mood: PetMood.happy, bubble: "Let's find $name in the app store!");
    _events.add(PetEvent.getApp);
    _clearBubbleLater();
  }

  /// Bookshelf: a question about the world. The pet always looks it up in
  /// its books (your cloud AI) and reads the answer out loud.
  Future<String?> askBookshelf(String question) async {
    question = question.trim();
    if (question.isEmpty || busy || recording) return null;
    _bubbleTimer?.cancel();
    bubble = question;
    bubbleIsUser = true;
    notifyListeners();
    final result = FindResult(query: question, source: MemorySource.all);
    await _guard(() => _answer(question, into: result));
    return result.answer.isEmpty ? null : result.answer;
  }

  Future<void> _guard(Future<void> Function() job) async {
    busy = true;
    try {
      await job();
    } catch (e) {
      await _fail(e);
      await _goHome();
    } finally {
      busy = false;
      notifyListeners();
      _clearBubbleLater();
    }
  }

  /// Searches notes and recent mail on the phone and has the pet answer.
  Future<FindResult> find(String query, {MemorySource source = MemorySource.all, String? original}) async {
    final asked = original ?? query;
    final result = FindResult(query: query, source: source);
    if (busy || recording) return result..answer = "I'm busy right now, try again in a moment.";
    busy = true;
    _bubbleTimer?.cancel();
    bubble = asked;
    bubbleIsUser = true;
    notifyListeners();
    try {
      final spot = source == MemorySource.mail ? Spots.mailbox : Spots.notesBox;
      final walking = walkTo(spot);
      // refresh the mail cache now and then, without making the user wait long
      final sync = source == MemorySource.notes
          ? Future<void>.value()
          : memory.syncMail().timeout(const Duration(seconds: 8), onTimeout: () {});
      await walking;
      facingLeft = true;
      _set(mood: PetMood.digging, bubble: source == MemorySource.mail ? 'Looking through your letters…' : 'Digging through your notes…');
      final started = DateTime.now();
      await sync;
      result.hits = await memory.search(query, source: source);
      final cloud = await llm.isConfigured();

      if (result.hits.isEmpty) {
        if (cloud && source == MemorySource.all && _looksGeneral(asked)) {
          result.fellBackToBooks = true;
          _set(bubble: "Nothing in your notes. I'll check my books!");
          await _answer(asked, into: result);
          return result;
        }
        result.answer = switch (source) {
          MemorySource.notes => "I couldn't find that in your notes.",
          MemorySource.mail => "I couldn't find that in your recent mail.",
          MemorySource.all => "I couldn't find that in your notes or mail.",
        };
      } else if (cloud) {
        try {
          result.answer = await llm.answerFromMemory(asked, _digest(result.hits.take(5).toList()));
          result.usedCloud = true;
        } catch (_) {
          result.answer = _localAnswer(result.hits);
        }
      } else {
        result.answer = _localAnswer(result.hits);
      }

      final waited = DateTime.now().difference(started);
      if (waited < const Duration(milliseconds: 1200)) {
        await Future.delayed(const Duration(milliseconds: 1200) - waited);
      }
      final top = result.hits.isEmpty ? null : result.hits.first.item;
      _set(
        mood: result.hits.isEmpty ? PetMood.sad : PetMood.reading,
        held: top == null ? HeldItem.none : (top.isNote ? HeldItem.note : HeldItem.letter),
        bubble: result.answer,
      );
      await walkTo(Spots.home);
      if (result.hits.isNotEmpty) _set(mood: PetMood.reading);
      await voice.say(result.answer);
      _set(mood: PetMood.idle, held: HeldItem.none);
      if (result.hits.isNotEmpty) _reward();
    } catch (e) {
      result.answer = e is LlmException || e is EmailException ? '$e' : 'Oops, I dropped my notes. Try again?';
      await _fail(e);
      await _goHome();
    } finally {
      busy = false;
      notifyListeners();
      _clearBubbleLater();
    }
    return result;
  }

  static bool _looksGeneral(String q) {
    final t = q.toLowerCase();
    final personal = RegExp(r"\b(i|my|me|mine|i'm|did|we|our)\b").hasMatch(t);
    return !personal && RegExp(r'^(what|who|how|why|when|where|is|are|can|should|tell)\b').hasMatch(t);
  }

  static String _when(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'today';
    if (diff == 1) return 'yesterday';
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    if (diff < 7) return 'on ${names[d.weekday - 1]}';
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return 'on ${months[d.month - 1]} ${d.day}';
  }

  static String _digest(List<SearchHit> hits) {
    final b = StringBuffer();
    for (var i = 0; i < hits.length; i++) {
      final it = hits[i].item;
      final date = '${it.date.year}-${it.date.month.toString().padLeft(2, '0')}-${it.date.day.toString().padLeft(2, '0')}';
      if (it.isNote) {
        b.writeln('${i + 1}. Voice note saved $date (${_when(it.date)}): "${_cut(it.note!.text, 500)}"');
      } else {
        final e = it.email!;
        b.writeln('${i + 1}. Email from ${e.from}, received $date (${_when(it.date)}). '
            'Subject: ${e.subject}. Preview: ${_cut(e.snippet, 400)}');
      }
    }
    return b.toString();
  }

  static String _cut(String s, int n) => s.length > n ? '${s.substring(0, n)}…' : s;

  /// Answer without a cloud AI: read out the best match.
  static String _localAnswer(List<SearchHit> hits) {
    final it = hits.first.item;
    final more = hits.length > 1 ? ' I found ${hits.length - 1} more, too.' : '';
    if (it.isNote) {
      return 'In your note from ${_when(it.date).replaceFirst('on ', '')}: ${_cut(it.note!.text, 160)}$more';
    }
    final e = it.email!;
    return '${e.from} emailed ${_when(it.date)} about "${e.subject}".$more';
  }

  Future<void> _answer(String question, {FindResult? into}) async {
    // Start the cloud call right away; the bookshelf search covers the wait.
    final answerFuture = llm.answer(question);
    await walkTo(Spots.bookshelf);
    _set(mood: PetMood.searching, held: HeldItem.none, bubble: 'Let me find the right book…');
    facingLeft = true;
    final started = DateTime.now();
    String answer;
    try {
      answer = await answerFuture;
    } catch (e) {
      into?.answer = '$e';
      await _fail(e);
      await _goHome();
      return;
    }
    // Always search a little, it's cute.
    final waited = DateTime.now().difference(started);
    if (waited < const Duration(milliseconds: 1800)) {
      await Future.delayed(const Duration(milliseconds: 1800) - waited);
    }
    if (answer.trim().isEmpty) answer = "Hmm, my books didn't have an answer for that.";
    into?.answer = answer;
    _set(mood: PetMood.reading, held: HeldItem.book, bubble: answer);
    await walkTo(Spots.home);
    _set(mood: PetMood.reading, held: HeldItem.book);
    await voice.say(answer);
    _set(mood: PetMood.idle, held: HeldItem.none);
    _reward();
  }

  // ------------------------------------------------------------------
  // Mailbox
  // ------------------------------------------------------------------

  Future<void> checkMail() async {
    if (busy || recording) return;
    if (!email.isConfigured || !await email.isSignedIn()) {
      _set(bubble: "Let's connect your mailbox first!", mood: PetMood.thinking);
      _events.add(PetEvent.openMailSettings);
      _clearBubbleLater();
      _set(mood: PetMood.idle);
      return;
    }
    busy = true;
    try {
      await walkTo(Spots.mailbox);
      facingLeft = true;
      _set(mood: PetMood.mail, held: HeldItem.none, bubble: 'Checking the mailbox…');
      final items = await email.fetchNewEmails();
      memory.addEmails(items);
      String summary;
      if (items.isEmpty) {
        summary = 'No new mail right now. Your inbox is all cozy!';
      } else {
        _set(mood: PetMood.mail, held: HeldItem.letter,
            bubble: 'Found ${items.length} new ${items.length == 1 ? 'letter' : 'letters'}! Reading…');
        final links = await memory.connections(items);
        if (await llm.isConfigured()) {
          var digest = EmailService.digest(items);
          if (links.isNotEmpty) {
            digest += "\nThe user's own notes that relate to these emails:\n";
            for (final (e, n) in links) {
              digest += '- Note from ${_when(n.createdAt)}: "${_cut(n.text, 200)}" relates to the email "${e.subject}"\n';
            }
          }
          summary = await llm.summarizeEmails(digest);
        } else {
          summary = _localMailSummary(items, links);
        }
        settings.lastMailCheck = DateTime.now();
      }
      _set(mood: PetMood.reading, held: HeldItem.letter, bubble: summary);
      await walkTo(Spots.home);
      _set(mood: PetMood.reading, held: HeldItem.letter);
      await voice.say(summary);
      _set(mood: PetMood.idle, held: HeldItem.none);
      _reward();
    } catch (e) {
      await _fail(e);
      await _goHome();
    } finally {
      busy = false;
      notifyListeners();
      _clearBubbleLater();
    }
  }

  static String _localMailSummary(List<EmailItem> items, List<(EmailItem, VoiceNote)> links) {
    final n = items.length;
    final senders = items.map((e) => e.from).toSet().take(3).toList();
    final who = senders.length == 1
        ? senders.first
        : '${senders.sublist(0, senders.length - 1).join(', ')} and ${senders.last}';
    var s = 'You have $n new ${n == 1 ? 'email' : 'emails'} from $who. The newest is about "${items.first.subject}".';
    if (links.isNotEmpty) {
      s += ' ${links.first.$1.from} wrote about something from your note "${links.first.$2.title}".';
    }
    return s;
  }

  // ------------------------------------------------------------------
  // Record → review → notes box
  // ------------------------------------------------------------------

  RecState recState = RecState.idle;
  RecordingDraft? draft;

  bool get recording => recState == RecState.recording;

  Future<void> toggleRecording() async {
    if (recState == RecState.recording) {
      await finishRecording();
    } else if (recState == RecState.idle) {
      await startRecording();
    }
  }

  /// Starts recording right away; the pet runs to the mic meanwhile.
  Future<bool> startRecording() async {
    if (recState != RecState.idle) return false;
    if (busy) {
      // interrupt whatever the pet was saying
      await voice.stopSpeaking();
    }
    final path = await notes.newRecordingPath();
    final ok = await voice.startRecording(path);
    if (!ok) {
      await _fail(LlmException(kIsWeb
          ? (voice.lastError ?? 'I need the microphone to take notes. Allow it in your browser.')
          : 'I need microphone permission to take notes. You can allow it in your phone settings.'));
      return false;
    }
    _recordingPath = path;
    recState = RecState.recording;
    voice.onMaxReached = () {
      if (recState == RecState.recording) finishRecording();
    };
    _bubbleTimer?.cancel();
    _set(bubble: "I'm listening!");
    notifyListeners();
    walkTo(Spots.mic).then((_) {
      if (recState == RecState.recording) {
        facingLeft = false;
        _set(mood: PetMood.listening, held: HeldItem.mic);
      }
    });
    return true;
  }

  Future<void> pauseRecording() async {
    if (recState != RecState.recording) return;
    if (voice.paused.value) {
      await voice.resumeRecording();
      _set(mood: PetMood.listening, bubble: "I'm listening!");
    } else {
      await voice.pauseRecording();
      _set(mood: PetMood.idle, bubble: 'Paused. Tap ▶ to keep going.');
    }
    notifyListeners();
  }

  /// Stops, transcribes and moves to the review step.
  Future<void> finishRecording() async {
    if (recState != RecState.recording) return;
    final duration = voice.elapsed.value;
    recState = RecState.transcribing;
    _set(mood: PetMood.thinking, held: HeldItem.note, bubble: 'Writing it down…');
    try {
      String? text;
      String? path;
      if (kIsWeb) {
        await voice.stopRecording();
        text = voice.liveText.value.trim(); // dictated in the browser, no audio file
      } else {
        path = await voice.stopRecording() ?? _recordingPath;
        if (path != null && localAi.whisperReady) {
          text = await localAi.transcribe(path, language: settings.language);
        }
      }
      if (duration < const Duration(milliseconds: 700) || (text != null && text.isEmpty)) {
        await store.deleteFile(path);
        recState = RecState.idle;
        _set(mood: PetMood.sad, held: HeldItem.none, bubble: "I didn't hear anything. Try again?");
        await voice.say("I didn't hear anything.");
        await _goHome();
        return;
      }
      draft = RecordingDraft(
        path: path,
        duration: duration,
        text: text ?? '',
        transcribed: text != null,
      );
      recState = RecState.review;
      _set(mood: PetMood.happy, bubble: text == null ? 'Got your recording!' : 'Does this look right?');
    } catch (e) {
      recState = RecState.idle;
      await _fail(e);
      await _goHome();
    } finally {
      _recordingPath = null;
      notifyListeners();
    }
  }

  /// Saves the reviewed note; the pet carries it to the notes box.
  Future<VoiceNote?> saveDraft({required String text, String? title}) async {
    final d = draft;
    if (d == null) return null;
    final body = text.trim().isEmpty && !d.transcribed ? 'Voice note' : text.trim();
    if (body.isEmpty) return null;
    final note = await notes.add(body, title: title, audioPath: d.path, durationMs: d.duration.inMilliseconds);
    cheer.learnFrom(note.text);
    draft = null;
    recState = RecState.idle;
    notifyListeners();
    _carryToBox(note, spoken: d.transcribed ? null : 'I saved your recording. Download the speech model in Settings so I can write the words too.');
    return note;
  }

  Future<void> discardDraft() async {
    final d = draft;
    draft = null;
    recState = RecState.idle;
    await store.deleteFile(d?.path);
    _set(clearBubble: true);
    notifyListeners();
    await _goHome();
  }

  Future<void> cancelRecording() async {
    if (recState == RecState.recording) {
      await voice.cancelRecording();
      recState = RecState.idle;
      _recordingPath = null;
      _set(clearBubble: true);
      notifyListeners();
      await _goHome();
    } else if (recState == RecState.review) {
      await discardDraft();
    }
  }

  /// A note typed by hand (from the notes box or "note that …").
  Future<VoiceNote?> addTypedNote(String text, {String? title}) async {
    if (text.trim().isEmpty) return null;
    final note = await notes.add(text, title: title);
    cheer.learnFrom(note.text);
    _carryToBox(note);
    return note;
  }

  Future<void> _carryToBox(VoiceNote note, {String? spoken}) async {
    if (busy) return;
    busy = true;
    try {
      _set(mood: PetMood.walking, held: HeldItem.note, bubble: '“${note.title}”');
      await walkTo(Spots.notesBox);
      facingLeft = true;
      _set(mood: PetMood.dropping, held: HeldItem.note);
      await Future.delayed(const Duration(milliseconds: 900));
      final links = await memory.related(MemoryItem.fromNote(note), limit: 1);
      final link = links.isEmpty ? null : links.first.item.email;
      _set(
        mood: PetMood.happy,
        held: HeldItem.none,
        bubble: link == null ? 'Saved in your notes box!' : 'Saved! It goes with ${link.from}\'s email "${link.subject}".',
      );
      await voice.say(spoken ?? (link == null ? 'Got it! I put your note in the box.' : 'Got it! This goes with an email from ${link.from}.'));
      _reward();
      await _goHome();
    } finally {
      busy = false;
      notifyListeners();
      _clearBubbleLater();
    }
  }

  // ------------------------------------------------------------------
  // Notes box
  // ------------------------------------------------------------------

  void openNotes() => _events.add(PetEvent.openNotes);
  void openFind() => _events.add(PetEvent.openFind);

  Future<void> _readNotesAloud() async {
    final all = notes.notes;
    _events.add(PetEvent.openNotes);
    if (all.isEmpty) {
      _set(bubble: 'Your notes box is empty.', mood: PetMood.idle);
      await voice.say('Your notes box is empty.');
      return;
    }
    final newest = all.first.text;
    final line = all.length == 1
        ? 'You have one note. It says: $newest'
        : 'You have ${all.length} notes. The newest says: $newest';
    _set(mood: PetMood.reading, held: HeldItem.note, bubble: line);
    await voice.say(line);
    _set(mood: PetMood.idle, held: HeldItem.none);
  }

  Future<void> readNote(VoiceNote note) async {
    _set(mood: PetMood.reading, held: HeldItem.note, bubble: note.text);
    await voice.say(note.text);
    _set(mood: PetMood.idle, held: HeldItem.none);
    _clearBubbleLater();
  }

  /// Transcribe a spoken search.
  /// Words from a spoken question: Whisper on phones, the browser's own
  /// dictation on the web (already in voice.liveText).
  Future<String?> transcribeQuestion(String path) async =>
      kIsWeb ? voice.liveText.value.trim() : localAi.transcribe(path, language: settings.language);

  /// Whether the pet can understand speech right now.
  bool get canListen => kIsWeb ? VoiceService.browserCanListen : localAi.whisperReady;

  void openSettings() => _events.add(PetEvent.openSettings);
  void openAccount() => _events.add(PetEvent.openAccount);

  @override
  void dispose() {
    voice.speaking.removeListener(notifyListeners);
    _bubbleTimer?.cancel();
    _events.close();
    super.dispose();
  }
}

enum RecState { idle, recording, transcribing, review }

class RecordingDraft {
  RecordingDraft({required this.path, required this.duration, required this.text, required this.transcribed});
  final String? path;
  final Duration duration;
  final String text;

  /// False when Whisper isn't available and only the audio was kept.
  final bool transcribed;
}

class FindResult {
  FindResult({required this.query, required this.source});
  final String query;
  final MemorySource source;
  List<SearchHit> hits = [];
  String answer = '';
  bool usedCloud = false;
  bool fellBackToBooks = false;
}
