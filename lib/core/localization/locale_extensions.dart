import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/gen/translations.g.dart';

extension AppLocaleX on AppLocale {
  String get preferredFontFamily =>
      this == AppLocale.fa ? FontFamily.shabnam : (kIsWeb || !Platform.isWindows ? "" : FontFamily.emoji);

  /// Locale to hand to [MaterialApp.locale]/[Localizations].
  ///
  /// Flutter's built-in Material/Widgets/Cupertino localizations only ship
  /// translations for a fixed set of languages, which doesn't include Yakut
  /// (sah). Passing an unsupported locale straight through makes framework
  /// widgets that depend on MaterialLocalizations throw once the UI touches
  /// one (observed: Settings page crashing to a blank screen after
  /// switching to Yakut). Our own `t.` strings don't go through
  /// Localizations at all (see translationsProvider), so this fallback only
  /// affects framework-internal localization, not app text.
  Locale get flutterSupportedLocale => this == AppLocale.sah ? const Locale('ru') : flutterLocale;

  String get localeName => switch (flutterLocale.toString()) {
    "ar" => "العربية",
    "en" => "English",
    "es" => "Spanish",
    "fa" => "فارسی",
    "fr" => "Français",
    "id" => "Indonesian",
    "pt_BR" => "Portuguese (Brazil)",
    "ru" => "Русский",
    "sah" => "Саха тыла",
    "tr" => "Türkçe",
    "zh" || "zh_CN" => "中文 (中国)",
    "zh_TW" => "中文 (台湾)",
    _ => "Unknown",
  };
}
