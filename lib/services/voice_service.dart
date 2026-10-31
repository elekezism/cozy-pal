import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';

import '../platform/platform.dart';
import '../platform/speech.dart';
import 'settings_service.dart';

/// Microphone in, pet voice out.
class VoiceService {
  VoiceService(this.settings);
  final SettingsService settings;

  final _recorder = AudioRecorder();
  final _tts = FlutterTts();
  final _player = AudioPlayer();

  /// True while the pet is speaking, so the room can animate its mouth.
  final speaking = ValueNotifier<bool>(false);

  /// 0..1 loudness while recording, for the listening animation.
  final level = ValueNotifier<double>(0);
  StreamSubscription<Amplitude>? _ampSub;

  /// Recording time so far (pauses excluded), updated ~8x a second.
  final elapsed = ValueNotifier<Duration>(Duration.zero);
  final paused = ValueNotifier<bool>(false);
  final _clock = Stopwatch();
  Timer? _tick;

  /// Recordings stop on their own after this long.
  static const maxRecording = Duration(minutes: 10);
  VoidCallback? onMaxReached;

  Future<void> init() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      if (isIOS) {
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          ],
        );
      }
      _tts.setStartHandler(() => speaking.value = true);
      _tts.setCompletionHandler(() => speaking.value = false);
      _tts.setCancelHandler(() => speaking.value = false);
      _tts.setErrorHandler((_) => speaking.value = false);
    } catch (e) {
      debugPrint('TTS init failed: $e');
    }
  }

  // ---------------- speaking ----------------

  Future<void> say(String text) async {
    if (text.trim().isEmpty) return;
    await stopSpeaking();
    try {
      await _tts.setLanguage(_ttsLanguage(settings.language));
      await _tts.setSpeechRate(settings.speechRate);
      await _tts.setPitch(settings.speechPitch);
      speaking.value = true;
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS failed: $e');
    } finally {
      speaking.value = false;
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
    speaking.value = false;
  }

  static String _ttsLanguage(String code) => switch (code) {
        'en' => 'en-US',
        'es' => 'es-ES',
        'fr' => 'fr-FR',
        'de' => 'de-DE',
        'it' => 'it-IT',
        'pt' => 'pt-BR',
        'ja' => 'ja-JP',
        'ko' => 'ko-KR',
        'zh' => 'zh-CN',
        'vi' => 'vi-VN',
        _ => code,
      };

  // ---------------- browser dictation (web) ----------------
  //
  // In the browser there's no Whisper, so "recording" is live dictation with
  // the browser's speech recognition: the words appear in [liveText] while you
  // talk, and there is no audio file. The same start / pause / stop calls work.

  final _speech = BrowserSpeech();
  final liveText = ValueNotifier<String>('');
  String _dictBase = '';
  bool _dictating = false;
  String? lastError;

  /// True when talking to the pet works here (browser speech or Whisper later).
  static bool get browserCanListen => kIsWeb && BrowserSpeech.supported;

  void _startDictation() {
    _speech.start(
      lang: _ttsLanguage(settings.language),
      continuous: true,
      onText: (t) {
        liveText.value = '$_dictBase $t'.trim();
        level.value = 0.5 + 0.5 * (DateTime.now().millisecond / 1000);
      },
      onEnd: () {
        level.value = 0;
        // browsers stop after a silence: keep listening until the user stops
        if (_dictating && !paused.value) {
          _dictBase = liveText.value;
          _startDictation();
        }
      },
      onError: (e) => lastError = e,
    );
  }

  // ---------------- recording ----------------

  Future<bool> get isRecording => kIsWeb ? Future.value(_dictating) : _recorder.isRecording();

  /// Starts recording 16 kHz mono 16-bit WAV — exactly what Whisper wants.
  /// In the browser: starts dictation instead (see [liveText]).
  Future<bool> startRecording(String path) async {
    if (kIsWeb) {
      if (!BrowserSpeech.supported) {
        lastError = "This browser can't do speech-to-text. Try Chrome, Edge or Safari, or type instead.";
        return false;
      }
      await stopSpeaking();
      lastError = null;
      liveText.value = '';
      _dictBase = '';
      _dictating = true;
      paused.value = false;
      _startDictation();
      _startClock();
      return true;
    }
    if (!await _recorder.hasPermission()) return false;
    await stopSpeaking();
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        noiseSuppress: true,
      ),
      path: path,
    );
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((a) {
      // dBFS (-60 quiet .. 0 loud) to 0..1
      level.value = paused.value ? 0 : ((a.current + 60) / 60).clamp(0.0, 1.0);
    });
    paused.value = false;
    _startClock();
    return true;
  }

  void _startClock() {
    _clock
      ..reset()
      ..start();
    elapsed.value = Duration.zero;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 125), (_) {
      elapsed.value = _clock.elapsed;
      if (kIsWeb && _clock.elapsed.inMilliseconds % 500 < 130) level.value *= 0.6; // let the bars settle
      if (_clock.elapsed >= maxRecording) onMaxReached?.call();
    });
  }

  Future<void> pauseRecording() async {
    if (paused.value) return;
    if (kIsWeb) {
      paused.value = true;
      _dictBase = liveText.value;
      _speech.stop();
      _clock.stop();
      level.value = 0;
      return;
    }
    await _recorder.pause();
    _clock.stop();
    paused.value = true;
    level.value = 0;
  }

  Future<void> resumeRecording() async {
    if (!paused.value) return;
    if (kIsWeb) {
      paused.value = false;
      _clock.start();
      _startDictation();
      return;
    }
    await _recorder.resume();
    _clock.start();
    paused.value = false;
  }

  void _stopClock() {
    _tick?.cancel();
    _tick = null;
    _clock.stop();
    paused.value = false;
  }

  /// Stops; returns the audio file path. In the browser returns null and the
  /// words are in [liveText].
  Future<String?> stopRecording() async {
    if (kIsWeb) {
      _dictating = false;
      _speech.stop();
      level.value = 0;
      _stopClock();
      // the last words can arrive just after stop()
      await Future.delayed(const Duration(milliseconds: 600));
      return null;
    }
    await _ampSub?.cancel();
    _ampSub = null;
    level.value = 0;
    _stopClock();
    return _recorder.stop();
  }

  Future<void> cancelRecording() async {
    if (kIsWeb) {
      _dictating = false;
      _speech.stop();
      liveText.value = '';
      level.value = 0;
      _stopClock();
      return;
    }
    await _ampSub?.cancel();
    _ampSub = null;
    level.value = 0;
    _stopClock();
    await _recorder.cancel();
  }

  // ---------------- playback ----------------

  Future<void> playFile(String path) async {
    await stopSpeaking();
    await _player.stop();
    await _player.play(DeviceFileSource(path));
  }

  Future<void> stopPlayback() => _player.stop();

  Future<void> dispose() async {
    _tick?.cancel();
    _speech.stop();
    await _ampSub?.cancel();
    if (!kIsWeb) await _recorder.dispose();
    await _player.dispose();
    await _tts.stop();
  }
}
