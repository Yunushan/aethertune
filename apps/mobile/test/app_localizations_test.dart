import 'package:aethertune/l10n/app_localizations_ar.dart';
import 'package:aethertune/l10n/app_localizations_en.dart';
import 'package:aethertune/l10n/app_localizations_tr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('localizes active sleep timer status and duration labels', () {
    final english = AppLocalizationsEn();
    final turkish = AppLocalizationsTr();
    final arabic = AppLocalizationsAr();

    expect(english.sleepTimer, 'Sleep timer');
    expect(english.sleepTimerStopsIn(english.sleepTimerMinutes(5)),
        'Playback stops in 5 minutes.');
    expect(turkish.sleepTimerActive, 'Uyku zamanlayıcısı etkin');
    expect(
      turkish.sleepTimerStopsIn(turkish.sleepTimerHours(2)),
      'Çalma 2 saat sonra durur.',
    );
    expect(arabic.sleepTimerActive, 'مؤقت النوم نشط');
    expect(arabic.sleepTimerMinutes(2), 'دقيقتان');
    expect(
      arabic.sleepTimerStopsIn(arabic.sleepTimerLessThanOneMinute),
      'سيتوقف التشغيل خلال أقل من دقيقة واحدة.',
    );
  });
}
