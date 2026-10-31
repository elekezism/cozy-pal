import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Phone storage: notes live in Documents/notes, everything else in the app
/// support folder (same places as before, so existing data is kept).
Future<Directory> _base(String name) async =>
    name.startsWith('notes/') ? await getApplicationDocumentsDirectory() : await getApplicationSupportDirectory();

Future<File> _file(String name) async {
  final f = File('${(await _base(name)).path}/$name');
  await f.parent.create(recursive: true);
  return f;
}

Future<String?> readText(String name) async {
  final f = await _file(name);
  return await f.exists() ? f.readAsString() : null;
}

/// Writes atomically (temp file + rename).
Future<void> writeText(String name, String data) async {
  final f = await _file(name);
  final tmp = File('${f.path}.tmp');
  await tmp.writeAsString(data);
  await tmp.rename(f.path);
}

/// A path for a new file in [folder] (e.g. a recording). Empty on the web.
Future<String> pathIn(String folder, String fileName) async {
  final base = folder.startsWith('notes') ? await getApplicationDocumentsDirectory() : await getTemporaryDirectory();
  final d = Directory('${base.path}/$folder');
  await d.create(recursive: true);
  return '${d.path}/$fileName';
}

/// Saves downloaded bytes; returns the path (null on the web).
Future<String?> saveBytes(String folder, String fileName, List<int> bytes) async {
  final p = await pathIn(folder, fileName);
  await File(p).writeAsBytes(bytes, flush: true);
  return p;
}

Future<void> deleteFile(String? path) async {
  if (path == null || path.isEmpty) return;
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

/// Deletes files in a temp [folder] older than [age].
Future<void> sweepFolder(String folder, Duration age) async {
  try {
    final d = Directory('${(await getTemporaryDirectory()).path}/$folder');
    if (!await d.exists()) return;
    final cutoff = DateTime.now().subtract(age);
    await for (final f in d.list()) {
      if (f is File && (await f.lastModified()).isBefore(cutoff)) await f.delete();
    }
  } catch (_) {}
}

/// Shows a downloaded image (a file on phones, a URL on the web).
Widget localImage(String path, {BoxFit fit = BoxFit.cover, double? width, double? height}) =>
    Image.file(File(path), fit: fit, width: width, height: height, gaplessPlayback: true);

/// Files can be recorded and played back on phones.
const bool canRecordAudio = true;
