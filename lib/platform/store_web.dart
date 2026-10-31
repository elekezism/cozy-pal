import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Browser storage: small JSON "files" in localStorage. Nothing is written
/// to disk and media is shown straight from its (proxied) URL.
Future<String?> readText(String name) async => (await SharedPreferences.getInstance()).getString('file:$name');

Future<void> writeText(String name, String data) async {
  await (await SharedPreferences.getInstance()).setString('file:$name', data);
}

Future<String> pathIn(String folder, String fileName) async => '';

Future<String?> saveBytes(String folder, String fileName, List<int> bytes) async => null;

Future<void> deleteFile(String? path) async {}

Future<void> sweepFolder(String folder, Duration age) async {}

Widget localImage(String path, {BoxFit fit = BoxFit.cover, double? width, double? height}) =>
    Image.network(path, fit: fit, width: width, height: height, gaplessPlayback: true);

/// In the browser, notes are dictated (speech → text) rather than recorded.
const bool canRecordAudio = false;
