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
      contains('com.ryanheise.audioservice.AudioServiceActivity'),
    );
    expect(
      _componentNames(document, 'service'),
      contains('com.ryanheise.audioservice.AudioService'),
    );
    expect(
      _componentNames(document, 'receiver'),
      contains('com.ryanheise.audioservice.MediaButtonReceiver'),
    );
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
