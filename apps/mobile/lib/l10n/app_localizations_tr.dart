// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get appTitle => 'AetherTune';

  @override
  String get home => 'Ana Sayfa';

  @override
  String get library => 'Kitaplık';

  @override
  String get playlists => 'Listeler';

  @override
  String get history => 'Geçmiş';

  @override
  String get sources => 'Kaynaklar';

  @override
  String get options => 'Seçenekler';

  @override
  String get language => 'Dil';

  @override
  String get languageSystem => 'Sistem varsayılanı';

  @override
  String get languageEnglish => 'İngilizce';

  @override
  String get languageTurkish => 'Türkçe';

  @override
  String get languageArabic => 'Arapça';

  @override
  String get loading => 'AetherTune yükleniyor';

  @override
  String get setupSaveError => 'Kurulum kaydedilemedi. Lütfen yeniden deneyin.';

  @override
  String get welcomeTitle => 'AetherTune\'a hoş geldiniz';

  @override
  String get welcomeDescription =>
      'Kontrol ettiğiniz müzikle başlayın veya yasal bir kaynak seçin. Tüm seçimleri daha sonra Seçenekler\'den değiştirebilirsiniz.';

  @override
  String get localLibraryTitle => 'Yerel kitaplık kurun';

  @override
  String get localLibraryDescription =>
      'Ses dosyalarını veya bir klasörü içe aktarın; uygulama açıkken izlenen klasörleri eşzamanlı tutun.';

  @override
  String get openLibrary => 'Kitaplığı aç';

  @override
  String get importAudio => 'Ses içe aktar';

  @override
  String get scanningSelectedAudio => 'Seçilen ses taranıyor...';

  @override
  String get scanningAudioFolder => 'Ses klasörü taranıyor...';

  @override
  String get legalSourcesTitle => 'Yasal kaynakları keşfedin';

  @override
  String get legalSourcesDescription =>
      'Podcast RSS beslemeleri ekleyin, Radio Browser ve Internet Archive\'da gezinin veya desteklenen kendi medya sunucunuza bağlanın.';

  @override
  String get openSources => 'Kaynakları aç';

  @override
  String get selfHostedLibraryTitle => 'Müzik sunucunuzu bağlayın';

  @override
  String get selfHostedLibraryDescription =>
      'Jellyfin veya Navidrome / Subsonic kitaplığınızı güvenli ve test edilmiş bir bağlantıyla ekleyin.';

  @override
  String get connectServer => 'Sunucuyu bağla';

  @override
  String get privacyFirstTitle => 'Önce gizlilik';

  @override
  String get privacyFirstDescription =>
      'AetherTune telemetri içermez. Ağ sağlayıcıları, kullanım öncesinde bağlantı kuracakları alan adlarını açıklar.';

  @override
  String get startAtHome => 'Ana Sayfada başla';

  @override
  String get skipSetup => 'Kurulumu atla';

  @override
  String get desktopTrayMinimizeOnClose => 'Kapatırken sistem tepsisine küçült';

  @override
  String get desktopTrayMinimizeOnCloseDescription =>
      "Çalma işlemini, Çıkış'ı seçene kadar sistem tepsisinde sürdürün.";

  @override
  String get desktopTrayPrevious => 'Tepsi menüsünde önceki';

  @override
  String get desktopTrayPreviousDescription =>
      'Her zaman kullanılabilen Göster ve Çıkış eylemlerinin yanında Önceki komutunu gösterin.';

  @override
  String get desktopTrayPlayPause => 'Tepsi menüsünde oynat / duraklat';

  @override
  String get desktopTrayPlayPauseDescription =>
      'Her zaman kullanılabilen Göster ve Çıkış eylemlerinin yanında oynatma düğmesini gösterin.';

  @override
  String get desktopTrayNext => 'Tepsi menüsünde sonraki';

  @override
  String get desktopTrayNextDescription =>
      'Her zaman kullanılabilen Göster ve Çıkış eylemlerinin yanında Sonraki komutunu gösterin.';

  @override
  String get sleepTimer => 'Uyku zamanlayıcısı';

  @override
  String get sleepTimerActive => 'Uyku zamanlayıcısı etkin';

  @override
  String get sleepTimerStopsAtEnd => 'Çalma bu parçanın sonunda durur.';

  @override
  String sleepTimerStopsIn(String remaining) => 'Çalma $remaining sonra durur.';

  @override
  String get sleepTimerLessThanOneMinute => '1 dakikadan az';

  @override
  String sleepTimerMinutes(int count) => '$count dakika';

  @override
  String sleepTimerHours(int count) => '$count saat';
}
