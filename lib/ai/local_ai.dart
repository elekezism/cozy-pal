import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

// dart:ffi doesn't exist in the browser: the web build gets a stub engine
import 'cactus_bindings.dart' if (dart.library.js_interop) 'cactus_stub.dart';
import 'model_manager.dart';

/// What the user wants the pet to do.
enum PetAction { searchMemory, answerQuestion, checkEmail, saveNote, readNotes, sendMessage, installApp, cheerUp }

/// Where a memory search should look.
enum MemorySource { all, notes, mail }

class RoutedRequest {
  RoutedRequest(this.action,
      {this.text = '',
      this.byNeedle = false,
      this.source = MemorySource.all,
      this.recipient = '',
      this.channel = '',
      this.mood = '',
      this.want = ''});

  /// For [PetAction.cheerUp]: how they feel ("sad", "bored"…) and what they
  /// asked for ("song", "video", "meme", "game", or empty = pet's choice).
  final String mood;
  final String want;

  /// For [PetAction.sendMessage]: who to send to, and "text" / "whatsapp" / "email" (or empty).
  final String recipient;
  final String channel;
  final PetAction action;

  /// The search query, the question to answer or the note to save.
  final String text;

  /// For [PetAction.searchMemory]: notes, mail or both.
  final MemorySource source;

  /// True when Needle 3 made the decision (false = keyword fallback).
  final bool byNeedle;
}

/// On-device brains: Needle 3 picks the tool, Whisper turns speech into text.
/// Both run through the Cactus engine on a background isolate so the room
/// animation never stutters.
class LocalAi extends ChangeNotifier {
  LocalAi(this.models);
  final ModelManager models;

  int _needle = 0; // native model handles (addresses), 0 = not loaded
  int _whisper = 0;
  Future<void> _queue = Future.value();

  bool get engineAvailable => CactusEngine.instance != null;
  String? get engineError => CactusEngine.loadError;
  bool get needleReady => _needle != 0;
  bool get whisperReady => _whisper != 0;

  /// Needle tools, in the OpenAI function-calling format Cactus expects.
  static final String toolsJson = jsonEncode([
    {
      'type': 'function',
      'function': {
        'name': 'search_memory',
        'description': "Find something in the user's own saved notes or emails: what they said, "
            'wrote down, were told, or who emailed about what. Use for "what did I say about…", '
            '"find my note about…", "did anyone email me about…", "when is…" questions about their own stuff.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': 'What to look for, in a few words'},
            'source': {
              'type': 'string',
              'enum': ['all', 'notes', 'mail'],
              'description': 'notes = only voice notes, mail = only emails, all = both',
            },
          },
          'required': ['query'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'send_message',
        'description': 'Send a text message, WhatsApp message or email to a friend, family member or contact. '
            'Use for "text Ana that…", "tell Sam I am late", "email mom about…", "message Leo…".',
        'parameters': {
          'type': 'object',
          'properties': {
            'recipient': {'type': 'string', 'description': 'Who to send it to, as the user said it (a name like "Ana" or "mom")'},
            'message': {'type': 'string', 'description': 'What the message should say, written as the message itself'},
            'channel': {
              'type': 'string',
              'enum': ['text', 'whatsapp', 'email'],
              'description': 'How to send it, only if the user said so',
            },
          },
          'required': ['recipient', 'message'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'cheer_up',
        'description': 'The user feels bored, sad, lonely, stressed or tired, or asks for something fun: '
            'play a song or music (by an artist), show a video (e.g. cat videos), show a meme, or play a game. '
            'Use for "I\'m bored", "I feel sad", "cheer me up", "play me a song", "show me a cat video".',
        'parameters': {
          'type': 'object',
          'properties': {
            'mood': {
              'type': 'string',
              'enum': ['bored', 'sad', 'stressed', 'lonely', 'tired', 'okay'],
              'description': 'How the user feels',
            },
            'kind': {
              'type': 'string',
              'enum': ['any', 'song', 'video', 'meme', 'game'],
              'description': 'What they asked for; any if they did not say',
            },
            'topic': {
              'type': 'string',
              'description': 'The artist, song or video topic if they named one, e.g. "Taylor Swift" or "otters"',
            },
          },
          'required': ['mood'],
        },
      },
    },
    _tool('install_app', 'Download, install or get an app from the app store.',
        {'app_name': 'The name of the app, e.g. "Spotify"'}),
    _tool('answer_question',
        'Answer a general knowledge question, explain something, or give advice '
            "about the world (not about the user's own notes or emails).",
        {'question': 'The full question the user asked'}),
    _tool('check_email',
        'Check the inbox and summarise new or unread email messages.', {}),
    _tool('save_note',
        'Save a note, reminder, idea or something the user wants remembered.',
        {'text': 'The exact words of the note to save'}),
    _tool('read_notes', 'Read back the notes the user saved earlier.', {}),
  ]);

  static Map<String, dynamic> _tool(
          String name, String description, Map<String, String> params) =>
      {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': {
            'type': 'object',
            'properties': {
              for (final e in params.entries)
                e.key: {'type': 'string', 'description': e.value}
            },
            'required': params.keys.toList(),
          },
        },
      };

  /// Loads whichever models are downloaded. Safe to call repeatedly.
  Future<void> loadModels() async {
    if (!engineAvailable) return;
    final needlePath = await models.modelPath(LocalModelKind.needle);
    if (_needle == 0 && needlePath != null) {
      _needle = await _serial(() => _isoLoad(needlePath));
    }
    final whisperPath = await models.modelPath(LocalModelKind.whisper);
    if (_whisper == 0 && whisperPath != null) {
      _whisper = await _serial(() => _isoLoad(whisperPath));
    }
    notifyListeners();
  }

  Future<void> unload(LocalModelKind kind) async {
    final addr = kind == LocalModelKind.needle ? _needle : _whisper;
    if (addr == 0) return;
    if (kind == LocalModelKind.needle) {
      _needle = 0;
    } else {
      _whisper = 0;
    }
    await _serial(() => _isoDestroy(addr));
    notifyListeners();
  }

  // Static so the isolate closures never capture `this`.
  static Future<int> _isoLoad(String path) =>
      Isolate.run(() => CactusEngine.instance?.loadModel(path) ?? 0);

  static Future<void> _isoDestroy(int addr) =>
      Isolate.run(() => CactusEngine.instance?.destroyModel(addr));

  static Future<String> _isoRoute(int addr, String text) {
    final tools = toolsJson;
    return Isolate.run(() => CactusEngine.instance!.runComplete(
          addr,
          jsonEncode([
            {'role': 'user', 'content': text}
          ]),
          toolsJson: tools,
        ));
  }

  static Future<List<List<double>>> _isoEmbed(int addr, List<String> texts) =>
      Isolate.run(() => [for (final t in texts) CactusEngine.instance!.runEmbed(addr, t)]);

  static Future<String> _isoTranscribe(int addr, String path, String opts) =>
      Isolate.run(() =>
          CactusEngine.instance!.runTranscribe(addr, path, optionsJson: opts));

  /// One native call at a time.
  Future<T> _serial<T>(Future<T> Function() job) {
    final c = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        c.complete(await job());
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }

  // ------------------------------------------------------------------
  // Needle 3: decide what to do
  // ------------------------------------------------------------------

  Future<RoutedRequest> route(String userText) async {
    final text = userText.trim();
    if (_needle != 0) {
      try {
        final addr = _needle;
        final raw = await _serial(() => _isoRoute(addr, text));
        final res = jsonDecode(raw) as Map<String, dynamic>;
        final calls = (res['function_calls'] as List?) ?? [];
        if (calls.isNotEmpty) {
          final call = calls.first as Map<String, dynamic>;
          final args = (call['arguments'] as Map?)?.cast<String, dynamic>() ?? {};
          final routed = _fromTool(call['name'] as String?, args, text);
          if (routed != null) return routed;
        }
        // Needle returns no call when nothing fits: treat it as a question.
        return RoutedRequest(PetAction.answerQuestion, text: text, byNeedle: true);
      } catch (e) {
        debugPrint('Needle routing failed, using keywords: $e');
      }
    }
    return keywordRoute(text);
  }

  static RoutedRequest? _fromTool(
      String? name, Map<String, dynamic> args, String original) {
    String arg(String k) {
      final v = '${args[k] ?? ''}'.trim();
      return v.isEmpty ? original : v;
    }

    return switch (name) {
      'search_memory' => RoutedRequest(PetAction.searchMemory,
          text: arg('query'),
          byNeedle: true,
          source: switch ('${args['source'] ?? 'all'}') {
            'notes' => MemorySource.notes,
            'mail' => MemorySource.mail,
            _ => MemorySource.all,
          }),
      'send_message' => RoutedRequest(PetAction.sendMessage,
          text: '${args['message'] ?? ''}'.trim(),
          recipient: '${args['recipient'] ?? ''}'.trim(),
          channel: '${args['channel'] ?? ''}'.trim(),
          byNeedle: true),
      'cheer_up' => RoutedRequest(PetAction.cheerUp,
          text: original,
          mood: '${args['mood'] ?? 'okay'}'.trim(),
          want: '${args['kind'] ?? ''}' == 'any' ? '' : '${args['kind'] ?? ''}'.trim(),
          recipient: '${args['topic'] ?? ''}'.trim(), // the named artist / topic
          byNeedle: true),
      'install_app' => RoutedRequest(PetAction.installApp, text: arg('app_name'), byNeedle: true),
      'answer_question' => RoutedRequest(PetAction.answerQuestion,
          text: arg('question'), byNeedle: true),
      'check_email' => RoutedRequest(PetAction.checkEmail, byNeedle: true),
      'save_note' =>
        RoutedRequest(PetAction.saveNote, text: arg('text'), byNeedle: true),
      'read_notes' => RoutedRequest(PetAction.readNotes, byNeedle: true),
      _ => null,
    };
  }

  /// Simple fallback when Needle is not downloaded or the engine is missing.
  static RoutedRequest keywordRoute(String text) {
    final t = text.toLowerCase();
    final msg = parseMessage(text);
    if (msg != null) return msg;
    final cheer = cheerRoute(text);
    if (cheer != null) return cheer;
    final app = RegExp(r"^(please )?(can you )?(download|install|get me|get)( the| an?)? (.+?)( app)?[.!?]*$", caseSensitive: false)
        .firstMatch(text.trim());
    if (app != null && !RegExp(r'^(get|download) (my|the) (notes?|mail|emails?)').hasMatch(t)) {
      return RoutedRequest(PetAction.installApp, text: app.group(5)!.trim());
    }
    final aboutMine = RegExp(
            r"\b(what did i|did i (say|mention|note|write)|my notes?\b|find (my|the)|search|look (for|up) my|"
            r"remind me what|where did i|when did i|who (emailed|wrote|sent)|did (anyone|anybody|someone) (email|write|send)|"
            r"(email|mail|message)s? (about|from)|in my (notes|mail|email|inbox))")
        .hasMatch(t);
    if (aboutMine) {
      final mailOnly = RegExp(r'\b(e-?mails?|mail|inbox|emailed|wrote|sent|message)').hasMatch(t) &&
          !RegExp(r'\bnotes?\b').hasMatch(t);
      final notesOnly = RegExp(r'\b(notes?|did i (say|mention|note)|what did i)\b').hasMatch(t) &&
          !RegExp(r'\b(e-?mail|mail|inbox)').hasMatch(t);
      return RoutedRequest(PetAction.searchMemory,
          text: text,
          source: mailOnly ? MemorySource.mail : notesOnly ? MemorySource.notes : MemorySource.all);
    }
    if (RegExp(r'\b(e-?mails?|inbox|mail)\b').hasMatch(t) &&
        RegExp(r'\b(check|read|any|new|summar|what|unread|got)').hasMatch(t)) {
      return RoutedRequest(PetAction.checkEmail);
    }
    if (RegExp(r'\b(my notes|read (me )?(my )?notes|what did i (note|save))')
        .hasMatch(t)) {
      return RoutedRequest(PetAction.readNotes);
    }
    final note = RegExp(
            r'^(please )?(take a note|note( that)?|remember( that)?|remind me( to)?|save (a )?note)[:,]?\s+(.*)$')
        .firstMatch(t);
    if (note != null && (note.group(7) ?? '').isNotEmpty) {
      return RoutedRequest(PetAction.saveNote,
          text: text.substring(text.length - note.group(7)!.length));
    }
    // Most things people type to the pet are about their own stuff, so
    // search first; the pet falls back to the bookshelf when nothing matches.
    return RoutedRequest(PetAction.searchMemory, text: text);
  }

  /// "I'm bored", "feeling sad today", "cheer me up", "play me a song",
  /// "show me a cat video", "send me a meme", "let's play a game".
  static RoutedRequest? cheerRoute(String text) {
    final t = text.toLowerCase().replaceAll('’', "'");
    String want = '';
    if (RegExp(r"\b(play (me )?(a |some |something )?(song|music|tunes?)|put on (some )?music|sing (me )?(a )?song|i want (some )?music)\b").hasMatch(t)) {
      want = 'song';
    } else if (RegExp(r'\b(videos?|clips?|youtube|funny cats?|show me (a |some )?(cute )?(cats?|kitt(y|ies|ens?)))\b').hasMatch(t) &&
        (RegExp(r'\b(show|watch|play|find|want to see|wanna see|put on)\b').hasMatch(t) ||
            RegExp(r'\b(cat|kitten|funny|cute) (videos?|clips?)\b').hasMatch(t))) {
      want = 'video';
    } else if (RegExp(r'\b(memes?)\b').hasMatch(t) && RegExp(r'\b(show|send|give|get|want|a meme|some memes|meme me)\b').hasMatch(t)) {
      want = 'meme';
    } else if (RegExp(r"\b(play a game|let'?s play|play with me|i want to play|play something|games?)\b").hasMatch(t) &&
        RegExp(r'\b(play|game)\b').hasMatch(t) && !RegExp(r'\b(what time|score|who won|when is)\b').hasMatch(t)) {
      want = 'game';
    } else if (RegExp(r"^(?:can you\s+)?(?:please\s+)?(?:play|put on)\s+(?:me\s+)?(?:some\s+)?\S").hasMatch(t)) {
      want = 'song'; // "play some Taylor Swift", "put on lofi"
    }
    final cheerMe = RegExp(r'\b(cheer me up|make me (smile|laugh|happy)|entertain me|something fun|i need a (laugh|smile|break))\b').hasMatch(t);
    final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final aboutMe = words <= 4 || RegExp(r"\b(i'?m|i am|im|i feel|feeling|i've been|i have been|so|kinda|today)\b").hasMatch(t);
    final question = RegExp(r'^(why|what|how|when|where|who|is|are|does|do|can|should)\b').hasMatch(t) && !RegExp(r'^(can|could) you\b').hasMatch(t);
    String mood = '';
    if (aboutMe && !question) {
      for (final e in {
        'sad': r"\b(sad|down|blue|unhappy|upset|crying|depressed|heartbroken|miserable|awful|bad day|rough day|feel(ing)? (bad|low|crappy))\b",
        'bored': r'\b(bored|boring|nothing to do|meh)\b',
        'stressed': r'\b(stressed|anxious|overwhelmed|worried|nervous|tense)\b',
        'lonely': r'\b(lonely|alone)\b',
        'tired': r'\b(tired|exhausted|sleepy|drained|burn(ed|t) out)\b',
      }.entries) {
        if (RegExp(e.value).hasMatch(t)) {
          mood = e.key;
          break;
        }
      }
    }
    if (want.isEmpty && mood.isEmpty && !cheerMe) return null;
    return RoutedRequest(PetAction.cheerUp, text: text, mood: mood.isEmpty ? 'okay' : mood, want: want);
  }

  /// "text Ana that I'm late", "email mom about dinner on Sunday",
  /// "tell Sam I'll be there", "whatsapp Leo see you soon".
  static RoutedRequest? parseMessage(String text) {
    final head = RegExp(
      r"^(?:please\s+)?(?:can you\s+)?(text|message|msg|whatsapp|email|e-mail|mail|tell|send)\s+"
      r"(?:(?:a|an)\s+(?:text|message|email|whatsapp)\s+to\s+|to\s+)?",
      caseSensitive: false,
    ).firstMatch(text.trim());
    if (head == null) return null;
    final verb = head.group(1)!.toLowerCase();
    final rest = text.trim().substring(head.end);
    final words = rest.split(RegExp(r'\s+'));
    if (words.length < 2) return null;
    String clean(String w) => w.replaceAll(RegExp(r'[,:;]+$'), '');
    var first = clean(words[0]);
    if (RegExp(r'^(me|it|this|that|them|us|him|her|the|a|an)$', caseSensitive: false).hasMatch(first)) return null;
    var used = 1;
    var who = first;
    final endsName = words[0].endsWith(',') || words[0].endsWith(':');
    if (!endsName && words.length > 2) {
      final second = clean(words[1]);
      final isMy = first.toLowerCase() == 'my';
      final capitalised = second.isNotEmpty && second[0] == second[0].toUpperCase() && second[0] != second[0].toLowerCase();
      final connector = RegExp(r"^(i|i'm|i'll|i've|we|you|the|to|that|saying|about|asking|on|by|is|are|can|will|please)$",
              caseSensitive: false)
          .hasMatch(second);
      if (isMy || (capitalised && !connector)) {
        who = '$first $second';
        used = 2;
      }
    }
    var body = words.skip(used).join(' ').trim();
    body = body.replaceFirst(RegExp(r'^(on\s+whatsapp|by\s+email|by\s+text)\s*', caseSensitive: false), '');
    body = body.replaceFirst(RegExp(r'^(,|:|that|saying|to\s+say|asking)\s+', caseSensitive: false), '');
    if (body.isEmpty) return null;
    final lower = text.toLowerCase();
    final channel = verb.contains('mail') || lower.contains('by email')
        ? 'email'
        : verb == 'whatsapp' || lower.contains('whatsapp')
            ? 'whatsapp'
            : verb == 'text' || lower.contains('by text')
                ? 'text'
                : '';
    return RoutedRequest(PetAction.sendMessage, text: body, recipient: who, channel: channel);
  }

  // ------------------------------------------------------------------
  // Needle 3: text embeddings for memory search
  // ------------------------------------------------------------------

  bool _embedBroken = false;

  /// Whether meaning-based search is available (otherwise keyword search).
  bool get canEmbed => _needle != 0 && !_embedBroken;

  /// Embeds [texts] on the phone. Returns null when embeddings aren't
  /// available, so callers can fall back to keyword search.
  Future<List<List<double>>?> embed(List<String> texts) async {
    if (!canEmbed || texts.isEmpty) return null;
    final addr = _needle;
    try {
      return await _serial(() => _isoEmbed(addr, texts));
    } catch (e) {
      debugPrint('Embedding failed, using keyword search: $e');
      _embedBroken = true;
      notifyListeners();
      return null;
    }
  }

  // ------------------------------------------------------------------
  // Whisper: speech to text
  // ------------------------------------------------------------------

  /// Transcribes a 16 kHz mono WAV. Returns null if Whisper isn't ready.
  Future<String?> transcribe(String wavPath, {String language = 'en'}) async {
    if (_whisper == 0) return null;
    final addr = _whisper;
    final opts = jsonEncode({'language': language});
    final raw = await _serial(() => _isoTranscribe(addr, wavPath, opts));
    final res = jsonDecode(raw) as Map<String, dynamic>;
    if (res['success'] == false) {
      throw StateError('${res['error'] ?? 'Transcription failed'}');
    }
    return (res['response'] as String? ?? '')
        .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)'), '') // [BLANK_AUDIO], (music)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
