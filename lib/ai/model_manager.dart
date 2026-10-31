import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Which on-device model a download is for.
enum LocalModelKind { needle, whisper }

/// Downloads Cactus model bundles (Needle 3 and Whisper) from
/// huggingface.co/Cactus-Compute on first use and keeps them on the phone.
class ModelManager extends ChangeNotifier {
  late Directory _root;

  final Map<LocalModelKind, double?> progress = {};
  final Map<LocalModelKind, String?> errors = {};

  /// The Cactus engine only runs in the phone apps.
  static bool get supported => !kIsWeb;

  Future<void> init() async {
    if (kIsWeb) return;
    final support = await getApplicationSupportDirectory();
    _root = Directory('${support.path}/models');
    await _root.create(recursive: true);
  }

  Directory _dirFor(LocalModelKind kind) => Directory('${_root.path}/${kind.name}');

  /// Folder that cactus_init should load, or null if not downloaded yet.
  Future<String?> modelPath(LocalModelKind kind) async {
    if (kIsWeb) return null;
    final marker = File('${_dirFor(kind).path}/.ready');
    if (!await marker.exists()) return null;
    final path = (await marker.readAsString()).trim();
    return await Directory(path).exists() ? path : null;
  }

  bool isDownloading(LocalModelKind kind) => progress[kind] != null;

  /// Downloads and unpacks the newest 4-bit bundle from [repo]
  /// (e.g. "Cactus-Compute/needle3").
  Future<String> download(LocalModelKind kind, String repo) async {
    if (kIsWeb) throw StateError('On-device models run in the phone app, not in the browser.');
    if (isDownloading(kind)) throw StateError('Already downloading');
    errors[kind] = null;
    progress[kind] = 0;
    notifyListeners();
    final dir = _dirFor(kind);
    try {
      final file = await _pickArchive(repo);
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      final archivePath = '${dir.path}/${file.name.split('/').last}';

      final req = http.Request(
          'GET', Uri.parse('https://huggingface.co/$repo/resolve/main/${file.name}'));
      final res = await http.Client().send(req);
      if (res.statusCode != 200) {
        throw HttpException('Download failed (${res.statusCode})');
      }
      final total = res.contentLength ?? file.size ?? 0;
      var got = 0;
      final sink = File(archivePath).openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) {
          final p = got / total;
          if (p - (progress[kind] ?? 0) > 0.01) {
            progress[kind] = p > 0.99 ? 0.99 : p;
            notifyListeners();
          }
        }
      }
      await sink.close();

      final outDir = '${dir.path}/model';
      await Isolate.run(() => extractFileToDisk(archivePath, outDir));
      await File(archivePath).delete();

      final modelDir = await _findModelRoot(Directory(outDir));
      await File('${dir.path}/.ready').writeAsString(modelDir.path);
      return modelDir.path;
    } catch (e) {
      errors[kind] = '$e';
      rethrow;
    } finally {
      progress[kind] = null;
      notifyListeners();
    }
  }

  Future<void> remove(LocalModelKind kind) async {
    if (kIsWeb) return;
    final dir = _dirFor(kind);
    if (await dir.exists()) await dir.delete(recursive: true);
    notifyListeners();
  }

  /// If the archive wraps everything in one folder, use that folder.
  static Future<Directory> _findModelRoot(Directory d) async {
    var current = d;
    for (var i = 0; i < 3; i++) {
      final entries = await current
          .list()
          .where((e) => !e.path.split('/').last.startsWith('.'))
          .toList();
      final files = entries.whereType<File>().toList();
      final dirs = entries.whereType<Directory>().toList();
      if (files.isEmpty && dirs.length == 1) {
        current = dirs.first;
      } else {
        break;
      }
    }
    return current;
  }

  static Future<_HfFile> _pickArchive(String repo) async {
    final res = await http.get(
        Uri.parse('https://huggingface.co/api/models/$repo?blobs=true'),
        headers: {'User-Agent': 'cozy-pal'});
    if (res.statusCode != 200) {
      throw HttpException('Model "$repo" not found (${res.statusCode})');
    }
    final siblings = (jsonDecode(res.body)['siblings'] as List? ?? [])
        .map((s) => _HfFile(
              s['rfilename'] as String,
              (s['lfs']?['size'] ?? s['size']) as int?,
            ))
        .where((f) => RegExp(r'\.(zip|tar\.gz|tgz|tar)$', caseSensitive: false)
            .hasMatch(f.name))
        .toList();
    if (siblings.isEmpty) throw StateError('No model bundles in $repo');
    // Cactus names bundles like "<model>-cq4.zip"; prefer the 4-bit one.
    return siblings.firstWhere(
      (f) => RegExp(r'-cq4\.', caseSensitive: false).hasMatch(f.name),
      orElse: () => siblings.first,
    );
  }
}

class _HfFile {
  _HfFile(this.name, this.size);
  final String name;
  final int? size;
}
