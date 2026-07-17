// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'AetherTune';

  @override
  String get home => 'الرئيسية';

  @override
  String get library => 'المكتبة';

  @override
  String get playlists => 'قوائم التشغيل';

  @override
  String get history => 'السجل';

  @override
  String get sources => 'المصادر';

  @override
  String get options => 'الخيارات';

  @override
  String get language => 'اللغة';

  @override
  String get languageSystem => 'لغة النظام';

  @override
  String get languageEnglish => 'الإنجليزية';

  @override
  String get languageTurkish => 'التركية';

  @override
  String get languageArabic => 'العربية';

  @override
  String get loading => 'جار تحميل AetherTune';

  @override
  String get setupSaveError => 'تعذر حفظ الإعداد. يرجى المحاولة مرة أخرى.';

  @override
  String get welcomeTitle => 'مرحبًا بك في AetherTune';

  @override
  String get welcomeDescription =>
      'ابدأ بالموسيقى التي تتحكم بها أو اختر مصدرًا قانونيًا. يمكنك تغيير جميع الخيارات لاحقًا من الخيارات.';

  @override
  String get localLibraryTitle => 'إعداد مكتبة محلية';

  @override
  String get localLibraryDescription =>
      'استورد ملفات صوتية أو مجلدًا، ثم حافظ على مزامنة المجلدات المراقبة أثناء فتح التطبيق.';

  @override
  String get openLibrary => 'فتح المكتبة';

  @override
  String get legalSourcesTitle => 'استكشف المصادر القانونية';

  @override
  String get legalSourcesDescription =>
      'أضف خلاصات بودكاست RSS، أو استعرض Radio Browser وInternet Archive، أو اتصل بخادم الوسائط المدعوم الخاص بك.';

  @override
  String get openSources => 'فتح المصادر';

  @override
  String get selfHostedLibraryTitle => 'ربط خادم الموسيقى الخاص بك';

  @override
  String get selfHostedLibraryDescription =>
      'أضف مكتبة Jellyfin أو Navidrome / Subsonic عبر اتصال آمن ومختبر.';

  @override
  String get connectServer => 'ربط الخادم';

  @override
  String get privacyFirstTitle => 'الخصوصية أولاً';

  @override
  String get privacyFirstDescription =>
      'لا يحتوي AetherTune على أي قياس عن بُعد. تكشف مزودات الشبكة عن النطاقات التي تتصل بها قبل الاستخدام.';

  @override
  String get startAtHome => 'البدء من الرئيسية';

  @override
  String get skipSetup => 'تخطي الإعداد';
}
