import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _androidNamespace = 'http://schemas.android.com/apk/res/android';

void main() {
  test('generated Android wrapper declares media playback components', () {
    final document = XmlDocument.parse(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
    );
    final permissions = document
        .findAllElements('uses-permission')
        .map(
          (element) =>
              element.getAttribute('name', namespace: _androidNamespace),
        )
        .toSet();
    expect(permissions, contains('android.permission.WAKE_LOCK'));
    expect(permissions, contains('android.permission.FOREGROUND_SERVICE'));
    expect(
      permissions,
      contains('android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK'),
    );

    expect(
      _componentNames(document, 'activity'),
      contains('dev.aethertune.aethertune.MainActivity'),
    );
    final activity = File(
      'android/app/src/main/kotlin/dev/aethertune/aethertune/MainActivity.kt',
    ).readAsStringSync();
    expect(activity, contains('class MainActivity : AudioServiceActivity()'));
    expect(activity, contains('dev.aethertune/playback_widget'));
    for (final action in <String>[
      'dev.aethertune.aethertune.shortcut.PREVIOUS',
      'dev.aethertune.aethertune.shortcut.PLAY_PAUSE',
      'dev.aethertune.aethertune.shortcut.NEXT',
    ]) {
      expect(activity, contains(action));
    }
    final shortcuts = XmlDocument.parse(
      File('android/app/src/main/res/xml/aethertune_launcher_shortcuts.xml')
          .readAsStringSync(),
    );
    final shortcutElements = shortcuts.findAllElements('shortcut').toList();
    expect(
      shortcutElements
          .map(
            (element) =>
                element.getAttribute('shortcutId', namespace: _androidNamespace),
          )
          .toSet(),
      <String?>{'previous', 'play_pause', 'next'},
    );
    expect(
      shortcutElements
          .map(
            (element) => element
                .findElements('intent')
                .single
                .getAttribute('action', namespace: _androidNamespace),
          )
          .toSet(),
      <String?>{
        'dev.aethertune.aethertune.shortcut.PREVIOUS',
        'dev.aethertune.aethertune.shortcut.PLAY_PAUSE',
        'dev.aethertune.aethertune.shortcut.NEXT',
      },
    );
    expect(
      _componentNames(document, 'service'),
      contains('com.ryanheise.audioservice.AudioService'),
    );
    expect(
      _componentNames(document, 'receiver'),
      contains('com.ryanheise.audioservice.MediaButtonReceiver'),
    );
    final application = document.findAllElements('application').single;
    expect(
      application.getAttribute('allowBackup', namespace: _androidNamespace),
      'false',
    );
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('minSdk = 23'));
  });

  test('generated iOS wrapper enables background audio', () {
    final document = XmlDocument.parse(
      File('ios/Runner/Info.plist').readAsStringSync(),
    );
    final entries = document.findAllElements('dict').first.childElements;
    final elements = entries.toList(growable: false);
    final keyIndex = elements.indexWhere(
      (element) => element.name.local == 'key' &&
          element.innerText == 'UIBackgroundModes',
    );
    expect(keyIndex, greaterThanOrEqualTo(0));
    final modes = elements[keyIndex + 1]
        .findElements('string')
        .map((element) => element.innerText);
    expect(modes, contains('audio'));
  });

  test('generated iOS wrapper targets iOS 14 for Darwin plugins', () {
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final targets = RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = ([^;]+);')
        .allMatches(project)
        .map((match) => match.group(1))
        .toSet();
    expect(targets, <String?>{'14.0'});

    final frameworkInfo = XmlDocument.parse(
      File('ios/Flutter/AppFrameworkInfo.plist').readAsStringSync(),
    );
    final elements = frameworkInfo.findAllElements('dict').first.childElements;
    final entries = elements.toList(growable: false);
    final keyIndex = entries.indexWhere(
      (element) =>
          element.name.local == 'key' &&
          element.innerText == 'MinimumOSVersion',
    );
    expect(keyIndex, greaterThanOrEqualTo(0));
    expect(entries[keyIndex + 1].innerText, '14.0');
  });

  test('generated Apple wrappers declare keychain entitlements', () {
    for (final path in <String>[
      'ios/Runner/DebugProfile.entitlements',
      'ios/Runner/Release.entitlements',
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ]) {
      final document = XmlDocument.parse(File(path).readAsStringSync());
      expect(
        document.findAllElements('key').map((key) => key.innerText),
        contains('keychain-access-groups'),
        reason: path,
      );
    }

    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(
      project,
      contains('CODE_SIGN_ENTITLEMENTS = Runner/DebugProfile.entitlements;'),
    );
    expect(
      project,
      contains('CODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements;'),
    );
  });
}

Set<String?> _componentNames(XmlDocument document, String elementName) {
  return document
      .findAllElements(elementName)
      .map(
        (element) =>
            element.getAttribute('name', namespace: _androidNamespace),
      )
      .toSet();
}
