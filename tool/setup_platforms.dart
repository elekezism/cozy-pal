// Finishes the iOS and Android projects after `flutter create`.
//
// Usage (from the project folder):
//   flutter create --org com.cozypal --project-name cozy_pal --platforms android,ios .
//   dart run tool/setup_platforms.dart [--cactus <path to cactus repo>]
//
// Safe to run more than once. It:
//   * sets the app id to com.cozypal.app on both platforms
//   * adds microphone + internet permissions and the text-to-speech query
//   * registers the com.cozypal.app:// sign-in redirect for Gmail/Outlook
//   * raises iOS to 16.4 and Android to API 24 (Cactus needs these)
//   * copies the Cactus engine binaries into packages/cactus_native
import 'dart:io';

const appId = 'com.cozypal.app';
const scheme = appId;
const iosMin = '16.4';
const androidMinSdk = 24;

void main(List<String> args) {
  final root = Directory.current.path;
  if (!File('$root/pubspec.yaml').existsSync() ||
      !File('$root/pubspec.yaml').readAsStringSync().contains('name: cozy_pal')) {
    _fail('Run this from the cozy_pal project folder.');
  }
  if (!Directory('$root/android').existsSync() || !Directory('$root/ios').existsSync()) {
    _fail('No android/ or ios/ folder yet. First run:\n'
        '  flutter create --org com.cozypal --project-name cozy_pal --platforms android,ios .');
  }

  _android(root);
  _ios(root);

  final i = args.indexOf('--cactus');
  if (i >= 0 && i + 1 < args.length) _copyCactus(root, args[i + 1]);
  _reportCactus(root);

  stdout.writeln('\nAll set. Next: flutter pub get && flutter run');
}

// ---------------------------------------------------------------- Android

void _android(String root) {
  final manifest = File('$root/android/app/src/main/AndroidManifest.xml');
  var m = manifest.readAsStringSync();
  const perms = [
    'android.permission.INTERNET',
    'android.permission.RECORD_AUDIO',
    'android.permission.READ_CONTACTS',
  ];
  m = _insertAfterManifestTag(m, perms);
  m = m.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="Cozy Pal"');
  if (!m.contains('android.intent.action.TTS_SERVICE')) {
    if (m.contains('<queries>')) {
      m = m.replaceFirst('<queries>',
          '<queries>\n        <intent>\n            <action android:name="android.intent.action.TTS_SERVICE"/>\n        </intent>');
    } else {
      m = m.replaceFirst('</manifest>',
          '    <queries>\n        <intent>\n            <action android:name="android.intent.action.TTS_SERVICE"/>\n        </intent>\n    </queries>\n</manifest>');
    }
  }
  // lets Settings open "get a key" links in the browser (url_launcher)
  if (!m.contains('android:scheme="https"')) {
    m = m.replaceFirst('<queries>',
        '<queries>\n        <intent>\n            <action android:name="android.intent.action.VIEW"/>\n            <data android:scheme="https"/>\n        </intent>');
  }
  // lets the pet open Messages, Mail and the Play Store with a draft / search
  for (final q in const [
    ['android.intent.action.SENDTO', 'smsto'],
    ['android.intent.action.VIEW', 'sms'],
    ['android.intent.action.SENDTO', 'mailto'],
    ['android.intent.action.VIEW', 'market'],
  ]) {
    if (!m.contains('android:scheme="${q[1]}"')) {
      m = m.replaceFirst('<queries>',
          '<queries>\n        <intent>\n            <action android:name="${q[0]}"/>\n            <data android:scheme="${q[1]}"/>\n        </intent>');
    }
  }
  // lets itch.io games open in an in-app browser window (Chrome Custom Tabs)
  if (!m.contains('CustomTabsService')) {
    m = m.replaceFirst('<queries>',
        '<queries>\n        <intent>\n            <action android:name="android.support.customtabs.action.CustomTabsService"/>\n        </intent>');
  }
  manifest.writeAsStringSync(m);
  stdout.writeln('✓ Android manifest: permissions (mic, contacts), label, TTS, browser, custom tabs, messages, mail, Play Store');

  final kts = File('$root/android/app/build.gradle.kts');
  final groovy = File('$root/android/app/build.gradle');
  if (kts.existsSync()) {
    var g = kts.readAsStringSync();
    g = g.replaceFirst(RegExp(r'applicationId = "[^"]*"'), 'applicationId = "$appId"');
    g = g.replaceFirst(RegExp(r'minSdk = [^\n]*'), 'minSdk = $androidMinSdk');
    if (!g.contains('appAuthRedirectScheme')) {
      g = g.replaceFirst(RegExp(r'(applicationId = "[^"]*")'),
          'applicationId = "$appId"\n        manifestPlaceholders.putAll(mapOf("appAuthRedirectScheme" to "$scheme"))');
    }
    kts.writeAsStringSync(g);
  } else if (groovy.existsSync()) {
    var g = groovy.readAsStringSync();
    g = g.replaceFirst(RegExp(r'applicationId\s*=?\s*"[^"]*"'), 'applicationId = "$appId"');
    g = g.replaceFirst(RegExp(r'minSdk(Version)?\s*=?\s*[^\n]*'), 'minSdk = $androidMinSdk');
    if (!g.contains('appAuthRedirectScheme')) {
      g = g.replaceFirst(RegExp(r'(applicationId = "[^"]*")'),
          "applicationId = \"$appId\"\n        manifestPlaceholders += ['appAuthRedirectScheme': '$scheme']");
    }
    groovy.writeAsStringSync(g);
  } else {
    _fail('android/app/build.gradle(.kts) not found');
  }
  stdout.writeln('✓ Android gradle: app id $appId, minSdk $androidMinSdk, sign-in redirect');
}

String _insertAfterManifestTag(String m, List<String> perms) {
  final open = RegExp(r'<manifest[^>]*>').firstMatch(m);
  if (open == null) return m;
  final missing = perms.where((p) => !m.contains('android:name="$p"')).toList();
  if (missing.isEmpty) return m;
  final lines = missing.map((p) => '    <uses-permission android:name="$p"/>').join('\n');
  return '${m.substring(0, open.end)}\n$lines${m.substring(open.end)}';
}

// ---------------------------------------------------------------- iOS

void _ios(String root) {
  final plist = File('$root/ios/Runner/Info.plist');
  var p = plist.readAsStringSync();
  p = p.replaceFirstMapped(RegExp(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*'),
      (mm) => '${mm.group(1)}Cozy Pal');
  void add(String key, String xml) {
    if (p.contains('<key>$key</key>')) return;
    final end = p.lastIndexOf('</dict>');
    p = '${p.substring(0, end)}\t<key>$key</key>\n$xml\n${p.substring(end)}';
  }

  add('NSMicrophoneUsageDescription',
      '\t<string>Your pet listens when you tap the microphone, to save voice notes and hear your questions.</string>');
  add('NSContactsUsageDescription',
      '\t<string>Your pet looks up the friend you name when you ask it to text or email someone.</string>');
  add('LSApplicationQueriesSchemes', '''
\t<array>
\t\t<string>sms</string>
\t\t<string>mailto</string>
\t\t<string>whatsapp</string>
\t\t<string>itms-apps</string>
\t</array>''');
  add('CFBundleURLTypes', '''
\t<array>
\t\t<dict>
\t\t\t<key>CFBundleURLName</key>
\t\t\t<string>$appId.oauth</string>
\t\t\t<key>CFBundleURLSchemes</key>
\t\t\t<array>
\t\t\t\t<string>$scheme</string>
\t\t\t</array>
\t\t</dict>
\t</array>''');
  plist.writeAsStringSync(p);
  stdout.writeln('✓ iOS Info.plist: name, microphone message, sign-in redirect');

  final pbx = File('$root/ios/Runner.xcodeproj/project.pbxproj');
  var x = pbx.readAsStringSync();
  x = x.replaceAll(RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;'),
      'IPHONEOS_DEPLOYMENT_TARGET = $iosMin;');
  x = x.replaceAllMapped(RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);'), (mm) {
    final id = mm.group(1)!;
    final isTests = id.endsWith('.RunnerTests');
    return 'PRODUCT_BUNDLE_IDENTIFIER = ${isTests ? '$appId.RunnerTests' : appId};';
  });
  pbx.writeAsStringSync(x);
  stdout.writeln('✓ iOS project: bundle id $appId, iOS $iosMin');

  final podfile = File('$root/ios/Podfile');
  if (podfile.existsSync()) {
    var pf = podfile.readAsStringSync();
    pf = pf.replaceFirst(RegExp(r"^#?\s*platform :ios, '[0-9.]+'", multiLine: true),
        "platform :ios, '$iosMin'");
    if (!pf.contains("platform :ios, '$iosMin'")) pf = "platform :ios, '$iosMin'\n$pf";
    podfile.writeAsStringSync(pf);
  } else {
    podfile.writeAsStringSync(_podfile);
  }
  stdout.writeln('✓ iOS Podfile: platform $iosMin');
}

const _podfile = """
platform :ios, '$iosMin'

# CocoaPods analytics sends network stats synchronously affecting flutter build latency.
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

project 'Runner', {
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
}

def flutter_root
  generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcode_build_settings_path)
    raise "#{generated_xcode_build_settings_path} must exist. If you're running pod install manually, make sure flutter pub get is executed first"
  end

  File.foreach(generated_xcode_build_settings_path) do |line|
    matches = line.match(/FLUTTER_ROOT\\=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found in #{generated_xcode_build_settings_path}. Try deleting Generated.xcconfig, then run flutter pub get"
end

require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)

flutter_ios_podfile_setup

target 'Runner' do
  use_frameworks!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  target 'RunnerTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '$iosMin'
    end
  end
end
""";

// ---------------------------------------------------------------- Cactus

String get _soDest => 'packages/cactus_native/android/src/main/jniLibs/arm64-v8a/libcactus_engine.so';
String get _xcDest => 'packages/cactus_native/ios/cactus-ios.xcframework';

void _copyCactus(String root, String cactus) {
  final so = File('$cactus/android/libcactus_engine.so');
  if (so.existsSync()) {
    so.copySync('$root/$_soDest');
    stdout.writeln('✓ Copied Android Cactus engine');
  } else {
    stdout.writeln('! $cactus/android/libcactus_engine.so not found (run: bash android/build.sh in the cactus repo)');
  }
  final xc = Directory('$cactus/apple/cactus-ios.xcframework');
  if (xc.existsSync()) {
    final dest = Directory('$root/$_xcDest');
    if (dest.existsSync()) dest.deleteSync(recursive: true);
    _copyDir(xc, dest);
    stdout.writeln('✓ Copied iOS Cactus engine');
  } else if (Platform.isMacOS) {
    stdout.writeln('! $cactus/apple/cactus-ios.xcframework not found (run: bash apple/build.sh in the cactus repo)');
  }
}

void _copyDir(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final e in from.listSync(followLinks: false)) {
    final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (e is Directory) {
      _copyDir(e, Directory('${to.path}/$name'));
    } else if (e is File) {
      e.copySync('${to.path}/$name');
    } else if (e is Link) {
      Link('${to.path}/$name').createSync(e.targetSync());
    }
  }
}

void _reportCactus(String root) {
  final hasSo = File('$root/$_soDest').existsSync();
  final hasXc = Directory('$root/$_xcDest').existsSync();
  stdout.writeln(hasSo
      ? '✓ Android: Cactus engine included'
      : '• Android: Cactus engine not included yet (app works, without on-device AI)');
  stdout.writeln(hasXc
      ? '✓ iOS: Cactus engine included'
      : '• iOS: Cactus engine not included yet (app works, without on-device AI)');
}

Never _fail(String msg) {
  stderr.writeln('✗ $msg');
  exit(1);
}
