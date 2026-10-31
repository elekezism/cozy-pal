// Minimal Dart FFI bindings to the Cactus engine (cactus_engine.h).
// Adapted from github.com/cactus-compute/cactus bindings/flutter/cactus.dart
// (Copyright (c) 2025 Cactus Compute, Inc. — see their LICENSE).
//
// The native library comes from building the Cactus repo:
//   Android: libcactus_engine.so in android/app/src/main/jniLibs/arm64-v8a/
//   iOS:     cactus-ios.xcframework, linked through cactus_native/CactusEngine.podspec
// tool/setup_platforms.dart and the GitHub workflow put them in place.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _InitN = Pointer<Void> Function(
    Pointer<Utf8> modelPath, Pointer<Utf8> corpusDir, Bool cacheIndex);
typedef _InitD = Pointer<Void> Function(
    Pointer<Utf8> modelPath, Pointer<Utf8> corpusDir, bool cacheIndex);

typedef _DestroyN = Void Function(Pointer<Void> model);
typedef _DestroyD = void Function(Pointer<Void> model);

typedef _CompleteN = Int32 Function(
    Pointer<Void> model,
    Pointer<Utf8> messagesJson,
    Pointer<Utf8> responseBuffer,
    IntPtr bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<Utf8> toolsJson,
    Pointer<Void> callback,
    Pointer<Void> userData,
    Pointer<Uint8> pcmBuffer,
    IntPtr pcmBufferSize);
typedef _CompleteD = int Function(
    Pointer<Void> model,
    Pointer<Utf8> messagesJson,
    Pointer<Utf8> responseBuffer,
    int bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<Utf8> toolsJson,
    Pointer<Void> callback,
    Pointer<Void> userData,
    Pointer<Uint8> pcmBuffer,
    int pcmBufferSize);

typedef _TranscribeN = Int32 Function(
    Pointer<Void> model,
    Pointer<Utf8> audioFilePath,
    Pointer<Utf8> prompt,
    Pointer<Utf8> responseBuffer,
    IntPtr bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<Void> callback,
    Pointer<Void> userData,
    Pointer<Uint8> pcmBuffer,
    IntPtr pcmBufferSize);
typedef _TranscribeD = int Function(
    Pointer<Void> model,
    Pointer<Utf8> audioFilePath,
    Pointer<Utf8> prompt,
    Pointer<Utf8> responseBuffer,
    int bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<Void> callback,
    Pointer<Void> userData,
    Pointer<Uint8> pcmBuffer,
    int pcmBufferSize);

typedef _EmbedN = Int32 Function(Pointer<Void> model, Pointer<Utf8> text,
    Pointer<Float> buffer, IntPtr bufferBytes, Pointer<IntPtr> dim, Bool normalize);
typedef _EmbedD = int Function(Pointer<Void> model, Pointer<Utf8> text,
    Pointer<Float> buffer, int bufferBytes, Pointer<IntPtr> dim, bool normalize);

typedef _LastErrorN = Pointer<Utf8> Function();
typedef _LastErrorD = Pointer<Utf8> Function();

/// Lazily loaded bindings. `CactusEngine.instance` is null when the native
/// library is not bundled (e.g. on an emulator), and the app falls back to
/// simpler behaviour instead of crashing.
class CactusEngine {
  CactusEngine._(DynamicLibrary lib)
      : init = lib.lookupFunction<_InitN, _InitD>('cactus_init'),
        destroy = lib.lookupFunction<_DestroyN, _DestroyD>('cactus_destroy'),
        complete = lib.lookupFunction<_CompleteN, _CompleteD>('cactus_complete'),
        transcribe =
            lib.lookupFunction<_TranscribeN, _TranscribeD>('cactus_transcribe'),
        embed = lib.lookupFunction<_EmbedN, _EmbedD>('cactus_embed'),
        lastError =
            lib.lookupFunction<_LastErrorN, _LastErrorD>('cactus_get_last_error');

  final _InitD init;
  final _DestroyD destroy;
  final _CompleteD complete;
  final _TranscribeD transcribe;
  final _EmbedD embed;
  final _LastErrorD lastError;

  static bool _tried = false;
  static CactusEngine? _instance;
  static String? loadError;

  static CactusEngine? get instance {
    if (_tried) return _instance;
    _tried = true;
    try {
      _instance = CactusEngine._(_open());
    } catch (e) {
      loadError = '$e';
      _instance = null;
    }
    return _instance;
  }

  static DynamicLibrary _open() {
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('libcactus_engine.so');
    }
    if (Platform.isIOS || Platform.isMacOS) {
      try {
        return DynamicLibrary.open('cactus.framework/cactus');
      } catch (_) {
        return DynamicLibrary.process();
      }
    }
    throw UnsupportedError('Cactus is not available on this platform');
  }

  String lastErrorMessage() {
    final p = lastError();
    return p == nullptr ? 'unknown error' : p.toDartString();
  }

  /// Runs cactus_complete and returns the JSON response string.
  String runComplete(int modelAddress, String messagesJson,
      {String? optionsJson, String? toolsJson, int bufferSize = 1 << 16}) {
    final msgs = messagesJson.toNativeUtf8();
    final opts = optionsJson?.toNativeUtf8() ?? nullptr;
    final tools = toolsJson?.toNativeUtf8() ?? nullptr;
    final buf = calloc<Uint8>(bufferSize);
    try {
      final rc = complete(Pointer<Void>.fromAddress(modelAddress), msgs,
          buf.cast(), bufferSize, opts, tools, nullptr, nullptr, nullptr, 0);
      if (rc < 0) throw StateError(lastErrorMessage());
      return buf.cast<Utf8>().toDartString();
    } finally {
      calloc.free(msgs);
      if (opts != nullptr) calloc.free(opts);
      if (tools != nullptr) calloc.free(tools);
      calloc.free(buf);
    }
  }

  /// Runs cactus_transcribe on a 16 kHz mono 16-bit WAV file.
  String runTranscribe(int modelAddress, String wavPath,
      {String? optionsJson, int bufferSize = 1 << 16}) {
    final path = wavPath.toNativeUtf8();
    final opts = optionsJson?.toNativeUtf8() ?? nullptr;
    final buf = calloc<Uint8>(bufferSize);
    try {
      final rc = transcribe(Pointer<Void>.fromAddress(modelAddress), path,
          nullptr, buf.cast(), bufferSize, opts, nullptr, nullptr, nullptr, 0);
      if (rc < 0) throw StateError(lastErrorMessage());
      return buf.cast<Utf8>().toDartString();
    } finally {
      calloc.free(path);
      if (opts != nullptr) calloc.free(opts);
      calloc.free(buf);
    }
  }

  /// Runs cactus_embed and returns an L2-normalised vector.
  List<double> runEmbed(int modelAddress, String text, {int maxDim = 4096}) {
    final t = text.toNativeUtf8();
    final buf = calloc<Float>(maxDim);
    final dim = calloc<IntPtr>();
    try {
      final rc = embed(Pointer<Void>.fromAddress(modelAddress), t, buf,
          maxDim * sizeOf<Float>(), dim, true);
      if (rc < 0) throw StateError(lastErrorMessage());
      final n = dim.value > 0 ? dim.value : rc;
      return List<double>.generate(n, (i) => buf[i]);
    } finally {
      calloc.free(t);
      calloc.free(buf);
      calloc.free(dim);
    }
  }

  void destroyModel(int address) =>
      destroy(Pointer<Void>.fromAddress(address));

  /// Loads a model folder; returns its handle as an address (0 on failure)
  /// so it can be passed between isolates.
  int loadModel(String dir) {
    final p = dir.toNativeUtf8();
    try {
      return init(p, nullptr, false).address;
    } finally {
      calloc.free(p);
    }
  }
}
