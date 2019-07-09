import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart';

part 'plurals_result.dart';

class FlutterModule {
  FlutterModule(Directory source, [Directory output])
      : assert(source != null),
        assert(source.existsSync(), 'The source folder does not exist.'),
        source = Directory(canonicalize(source.path)),
        output = output != null && output.existsSync() ? output : Directory(join(source.path, 'generated'))
          ..createSync(recursive: true);

  final Directory source;
  final Directory output;

  StreamSubscription<FileSystemEvent> _watchSub;

  void init() => _checkSourceFolder();

  void dispose() => _watchSub?.cancel();

  List<File> get files {
    _checkSourceFolder();

    return source //
        .listSync(recursive: true)
        .whereType<File>()
        .where(_isArb)
        .toList()
          ..sort((File a, File b) => a.path.compareTo(b.path));
  }

  // lang=>string_key=>string_value
  Map<String, Map<String, String>> get values => files
      .asMap()
      .map((_, File it) => MapEntry<String, Map<String, String>>(_languageFromPath(it.path), getLanguageData(it)));

  List<String> get languages => files //
      .map((File it) => basenameWithoutExtension(it.path).split('_').skip(1).join('_'))
      .toList();

  String get createGeneratedFile {
    final List<File> files = List<File>.from(this.files);
    if (files.isEmpty) {
      files.add(createFileForLanguage('en'));
    }

    final List<String> languages = this.languages;
    final Map<String, Map<String, String>> values = this.values;
    final Map<String, String> englishData = values['en'];

    final StringBuffer buffer = StringBuffer()
      ..writeln("import 'dart:async';")
      ..writeln()
      ..writeln("import 'package:flutter/foundation.dart';")
      ..writeln("import 'package:flutter/material.dart';")
      ..writeln()
      ..writeAll(languages.map<String>((String language) => "part 'strings_$language.dart';"), '\n')
      ..writeln()
      ..writeln()
      ..writeln('// ignore_for_file: camel_case_types')
      ..writeln('// ignore_for_file: non_constant_identifier_names')
      ..writeln('// ignore_for_file: prefer_single_quotes')
      ..writeln('// ignore_for_file: unnecessary_brace_in_string_interps')
      ..writeln()
      ..writeln('// This file is automatically generated. DO NOT EDIT, all your changes would be lost.')
      ..writeln(createSClass(englishData));

    buffer.write(createDelegateClass(languages));
    return buffer.toString();
  }

  void createFiles() {
    final File generatedFile = File(join(output.path, '$_generatedFileName.dart'));
    generatedFile.writeAsStringSync(createGeneratedFile);

    final Map<String, Map<String, String>> values = this.values;
    final Map<String, String> englishData = values['en'];
    final List<String> englishKeys = englishData.keys.toList();
    for (String language in values.keys) {
      final String data = createLanguageClass(language, englishKeys, values[language]);
      final File languageFile = File(join(output.path, 'strings_$language.dart'));
      languageFile.writeAsStringSync(data);
    }
  }

  StreamSubscription<FileSystemEvent> get watch {
    return _watchSub ??= source
        .watch(events: FileSystemEvent.create | FileSystemEvent.delete, recursive: true) //
        .where((FileSystemEvent it) => !it.isDirectory && _isArb(File(it.path)))
        .listen(_onFileChange);
  }

  void _onFileChange(FileSystemEvent event) {
    switch (event.type) {
      case FileSystemEvent.create:
        final File generatedFile = File(join(output.path, '$_generatedFileName.dart'));
        generatedFile.writeAsStringSync(createGeneratedFile);

        // ignore: unnecessary_this
        final Map<String, Map<String, String>> values = this.values;
        final Map<String, String> englishData = values['en'];
        final List<String> englishKeys = englishData.keys.toList();

        final String language = _languageFromPath(event.path);
        final String languageString = createLanguageClass(language, englishKeys, values[language]);
        dartFileForLanguage(language).writeAsStringSync(languageString);
        break;

      case FileSystemEvent.delete:
        final File generatedFile = File(join(output.path, '$_generatedFileName.dart'));
        generatedFile.writeAsStringSync(createGeneratedFile);

        final String language = _languageFromPath(event.path);
        dartFileForLanguage(language).deleteSync(recursive: true);
        break;
    }
  }

  File createFileForLanguage(String language) {
    _checkSourceFolder();

    return arbFileForLanguage(language)
      ..createSync()
      ..writeAsStringSync('{}');
  }

  File arbFileForLanguage(String language) {
    return File(setExtension(absolute(source.path, 'strings_$language'), '.arb'));
  }

  File dartFileForLanguage(String language) {
    return File(setExtension(absolute(output.path, 'strings_$language'), '.dart'));
  }

  String createSClass(Map<String, String> englishData) {
    final StringBuffer buffer = StringBuffer();
    final List<String> keys = englishData.keys.toList();

    final PluralsResult pluralsResult = findPluralsKeys(keys);
    final Map<String, List<String>> pluralsQuantities = pluralsResult.pluralsQuantities;
    final List<String> pluralsKeys = pluralsQuantities.keys.toList()..sort();
    keys.removeWhere(pluralsResult.pluralsIds.contains);

    final List<String> parametrized = keys.where((String key) => englishData[key].contains(r'$')).toList()..sort();
    keys
      ..removeWhere(parametrized.contains)
      ..sort();

    buffer
      ..writeln('class S implements WidgetsLocalizations {')
      ..writeln('  const S();')
      ..writeln()
      ..writeln('  static S current;')
      ..writeln()
      ..writeln('  static const GeneratedLocalizationsDelegate delegate =')
      ..writeln('    GeneratedLocalizationsDelegate();')
      ..writeln()
      ..writeln('  static S of(BuildContext context) => Localizations.of<S>(context, S);')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  TextDirection get textDirection => TextDirection.ltr;')
      ..writeln()
      ..writeAll(keys.map<String>((String key) => createValuesMethod(key, englishData[key])))
      ..writeln()
      ..writeAll(parametrized.map<String>((String key) => createParametrizedMethod(key, englishData[key])))
      ..writeln()
      ..writeAll(pluralsKeys.map<String>((String key) => createPluralMethod(key, pluralsQuantities[key], englishData)))
      ..writeln('}');

    return buffer.toString();
  }

  String createLanguageClass(String language, List<String> englishKeys, Map<String, String> languageData) {
    final StringBuffer buffer = StringBuffer()
      ..writeln("part of '$_generatedFileName.dart';")
      ..writeln()
      ..writeln('// ignore_for_file: camel_case_types')
      ..writeln('// ignore_for_file: non_constant_identifier_names')
      ..writeln('// ignore_for_file: prefer_single_quotes')
      ..writeln('// ignore_for_file: unnecessary_brace_in_string_interps')
      ..writeln()
      ..writeln('// This file is automatically generated. DO NOT EDIT, all your changes would be lost.');

    if (language == 'en') {
      buffer //
        ..writeln(r'class $en extends S {')
        ..writeln(r'  const $en();')
        ..writeln(r'}')
        ..writeln();
      return buffer.toString();
    }

    final List<String> keys = languageData.keys.where(englishKeys.contains).toList();

    final PluralsResult pluralsResult = findPluralsKeys(keys);
    final Map<String, List<String>> pluralsQuantities = pluralsResult.pluralsQuantities;
    final List<String> pluralsKeys = pluralsQuantities.keys.toList()..sort();
    keys.removeWhere(pluralsResult.pluralsIds.contains);

    final List<String> parametrized = keys.where((String key) => languageData[key].contains(r'$')).toList()..sort();
    keys
      ..removeWhere(parametrized.contains)
      ..sort();

    String className = '\$$language';
    final String textDirection = _rtl.contains(language.split('_')[0]) ? 'rtl' : 'ltr';

    buffer //
      ..writeln('class $className extends S {')
      ..writeln('  const $className();')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  TextDirection get textDirection => TextDirection.$textDirection;')
      ..writeln()
      ..writeAll(keys.map<String>((String key) => createValuesMethod(key, languageData[key], isOverride: true)))
      ..writeln()
      ..writeAll(
          parametrized.map<String>((String key) => createParametrizedMethod(key, languageData[key], isOverride: true)))
      ..writeln()
      ..writeAll(pluralsKeys
          .map<String>((String key) => createPluralMethod(key, pluralsQuantities[key], languageData, isOverride: true)))
      ..writeln('}');

    if (language.startsWith('iw')) {
      className = r'$he_IL';
      buffer //
        ..writeln()
        ..writeln('class $className extends \$$language {')
        ..writeln('  const $className();')
        ..writeln()
        ..writeln('  @override')
        ..writeln('  TextDirection get textDirection => TextDirection.rtl;')
        ..writeln('}');
    }

    return buffer.toString();
  }

  String createDelegateClass(List<String> languages) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('class GeneratedLocalizationsDelegate extends LocalizationsDelegate<S> {')
      ..writeln('  const GeneratedLocalizationsDelegate();')
      ..writeln()
      ..writeln('  List<Locale> get supportedLocales {')
      ..writeln('    return const <Locale>[');

    for (int i = 0; i < languages.length; i++) {
      final String language = languages[i];
      final List<String> languageParts = language.split('_');
      final String lang = languageParts[0];
      final String country = languageParts.length == 2 ? languageParts[1] : '';

      // for hebrew iw==he
      if (language.startsWith('iw')) {
        buffer.writeln('      Locale("he", "IL"),');
      } else {
        buffer.writeln('      Locale("$lang", "$country"),');
      }
    }

    buffer
      ..writeln(r'    ];')
      ..writeln(r'  }')
      ..writeln()
      ..writeln(r'  LocaleListResolutionCallback listResolution({Locale fallback, bool withCountry = true}) {')
      ..writeln(r'    return (List<Locale> locales, Iterable<Locale> supported) {')
      ..writeln(r'      if (locales == null || locales.isEmpty) {')
      ..writeln(r'        return fallback ?? supported.first;')
      ..writeln(r'      } else {')
      ..writeln(r'        return _resolve(locales.first, fallback, supported, withCountry);')
      ..writeln(r'      }')
      ..writeln(r'    };')
      ..writeln(r'  }')
      ..writeln()
      ..writeln(r'  LocaleResolutionCallback resolution({Locale fallback, bool withCountry = true}) {')
      ..writeln(r'    return (Locale locale, Iterable<Locale> supported) {')
      ..writeln(r'      return _resolve(locale, fallback, supported, withCountry);')
      ..writeln(r'    };')
      ..writeln(r'  }')
      ..writeln()
      ..writeln(r'  @override')
      ..writeln(r'  Future<S> load(Locale locale) {')
      ..writeln(r'    final String lang = getLang(locale);')
      ..writeln(r'    if (lang != null) {')
      ..writeln(r'      switch (lang) {');

    for (int i = 0; i < languages.length; i++) {
      final String language = languages[i];

      // for hebrew iw==he
      if (language.startsWith('iw')) {
        buffer
          ..writeln(r'        case "iw_IL":')
          ..writeln(r'        case "he_IL":')
          ..writeln(r'          S.current = const $he_IL();')
          ..writeln(r'          return SynchronousFuture<S>(S.current);');
      } else {
        buffer
          ..writeln('        case "$language":')
          ..writeln('          S.current = const \$$language();')
          ..writeln('          return SynchronousFuture<S>(S.current);');
      }
    }

    buffer
      ..writeln(r'        default:')
      ..writeln(r'          // NO-OP.')
      ..writeln(r'      }')
      ..writeln(r'    }')
      ..writeln(r'    S.current = const S();')
      ..writeln(r'    return SynchronousFuture<S>(S.current);')
      ..writeln(r'  }')
      ..writeln()
      ..writeln(r'  @override')
      ..writeln(r'  bool isSupported(Locale locale) => _isSupported(locale, true);')
      ..writeln()
      ..writeln(r'  @override')
      ..writeln(r'  bool shouldReload(GeneratedLocalizationsDelegate old) => false;')
      ..writeln()
      ..writeln(r'  /// Internal method to resolve a locale from a list of locales.')
      ..writeln(r'  Locale _resolve(Locale locale, Locale fallback, Iterable<Locale> supported, bool withCountry) {')
      ..writeln(r'    if (locale == null || !_isSupported(locale, withCountry)) {')
      ..writeln(r'      return fallback ?? supported.first;')
      ..writeln(r'    }')
      ..writeln()
      ..writeln(r'    final Locale languageLocale = Locale(locale.languageCode, "");')
      ..writeln(r'    if (supported.contains(locale)) {')
      ..writeln(r'      return locale;')
      ..writeln(r'    } else if (supported.contains(languageLocale)) {')
      ..writeln(r'      return languageLocale;')
      ..writeln(r'    } else {')
      ..writeln(r'      final Locale fallbackLocale = fallback ?? supported.first;')
      ..writeln(r'      return fallbackLocale;')
      ..writeln(r'    }')
      ..writeln(r'  }')
      ..writeln()
      ..writeln(r'  /// Returns true if the specified locale is supported, false otherwise.')
      ..writeln(r'  bool _isSupported(Locale locale, bool withCountry) {')
      ..writeln(r'    if (locale != null) {')
      ..writeln(r'      for (Locale supportedLocale in supportedLocales) {')
      ..writeln(r'        // Language must always match both locales.')
      ..writeln(r'        if (supportedLocale.languageCode != locale.languageCode) {')
      ..writeln(r'          continue;')
      ..writeln(r'        }')
      ..writeln()
      ..writeln(r'        // If country code matches, return this locale.')
      ..writeln(r'        if (supportedLocale.countryCode == locale.countryCode) {')
      ..writeln(r'          return true;')
      ..writeln(r'        }')
      ..writeln()
      ..writeln(r'        // If no country requirement is requested, check if this locale has no country.')
      ..writeln(
          r'        if (!withCountry && (supportedLocale.countryCode == null || supportedLocale.countryCode.isEmpty)) {')
      ..writeln(r'          return true;')
      ..writeln(r'        }')
      ..writeln(r'      }')
      ..writeln(r'    }')
      ..writeln(r'    return false;')
      ..writeln(r'  }')
      ..writeln(r'}')
      ..writeln()
      ..writeln(r'String getLang(Locale l) => l == null')
      ..writeln(r'  ? null')
      ..writeln(r'  : l.countryCode != null && l.countryCode.isEmpty')
      ..writeln(r'    ? l.languageCode')
      ..writeln(r'    : l.toString();');

    return buffer.toString();
  }

  PluralsResult findPluralsKeys(List<String> keys) {
    final List<String> pluralKeys = <String>[];
    final Map<String, List<String>> pluralsQuantities = <String, List<String>>{};

    for (int i = 0; i < keys.length; i++) {
      final String key = keys[i];
      final String quantity = _pluralEnding.firstWhere(
        (String quantity) => RegExp('$quantity\$', caseSensitive: false).hasMatch(key),
        orElse: () => null,
      );
      final bool isPlural = quantity != null;

      if (isPlural) {
        pluralKeys.add(key);
        final String actualKey = key.substring(0, key.length - quantity.length);

        pluralsQuantities[actualKey] = (pluralsQuantities[actualKey] ?? <String>[]) //
          ..add(quantity.toLowerCase());

        pluralsQuantities[actualKey].sort(_sortQuantities);
      }
    }

    pluralsQuantities.removeWhere((String actualId, List<String> quantities) {
      if (!quantities.any((String quantity) => quantity == 'other')) {
        for (int i = 0; i < quantities.length; i++) {
          final String quantity = quantities[i];

          pluralKeys.removeWhere((String key) => key.toLowerCase() == '$actualId$quantity'.toLowerCase());
        }

        return true;
      }

      return false;
    });

    return PluralsResult(pluralKeys, pluralsQuantities);
  }

  String createValuesMethod(String key, String value, {bool isOverride = false}) {
    final StringBuffer buffer = _createBuffer(isOverride);

    if (key.startsWith('@')) {
      return '';
    }
    buffer.writeln('  String get $key => """$value""";');

    return buffer.toString();
  }

  String createParametrizedMethod(String key, String value, {bool isOverride = false}) {
    final StringBuffer buffer = _createBuffer(isOverride);
    final List<Match> matches = parameterRegExp.allMatches(value).toList();

    bool hasParameters = false;
    for (int i = 0; i < matches.length; i++) {
      final Match m = matches[i];
      if (!hasParameters) {
        hasParameters = true;
        buffer.write('  String $key(');
      }

      final String parameter = _normalizeParameter(m.group(0));
      buffer.write('dynamic $parameter');

      if (i != matches.length - 1) {
        buffer.write(', ');
      }
    }

    if (hasParameters) {
      buffer.writeln(') => "$value";');
    } else {
      return createValuesMethod(key, value);
    }

    return buffer.toString();
  }

  String createPluralMethod(String key, List<String> quantities, Map<String, String> values,
      {bool isOverride = false}) {
    final StringBuffer buffer = _createBuffer(isOverride);
    final String parameterName = _extractOtherParameterName(key, values);

    key = key.endsWith('_') ? key.substring(0, key.length - 1) : key;
    buffer.writeln('  String $key(dynamic $parameterName) {\n    switch ($parameterName.toString().toLowerCase()) {');
    for (int i = 0; i < _pluralEnding.length; i++) {
      final String quantity = _pluralEnding[i];

      if (!quantities.contains(quantity)) {
        continue;
      }

      final String _key =
          values.keys.firstWhere((String possibleKey) => possibleKey.toLowerCase() == '$key$quantity'.toLowerCase());

      final String value = values[_key];
      if (quantity == 'other') {
        buffer //
          ..writeln('      default:')
          ..writeln('        return "$value";');
      } else {
        buffer //
          ..writeln('      case "${_quantityMapping(quantity)}":')
          ..writeln('        return "$value";');
      }
    }

    buffer.writeln('    }\n  }');
    return buffer.toString();
  }

  Map<String, String> getLanguageData(File file) {
    if (!file.existsSync()) {
      throw AssertionError('The file for this language does not exist.');
    }

    final dynamic json = jsonDecode(file.readAsStringSync());
    return (Map<String, dynamic>.from(json) //
          ..removeWhere((String key, dynamic value) => value is! String && key.startsWith('@')))
        .cast<String, String>();
  }

  String _extractOtherParameterName(String key, Map<String, String> values) {
    final String otherValueKey =
        values.keys.firstWhere((String _key) => _key.startsWith(key) && _key.toLowerCase().endsWith('other'));
    final String otherValueValue = values[otherValueKey];

    if (parameterRegExp.hasMatch(otherValueValue)) {
      return _normalizeParameter(parameterRegExp.firstMatch(otherValueValue).group(0));
    } else {
      return 'param';
    }
  }

  String _normalizeParameter(String parameter) {
    return parameter //
        .replaceAll(r'$', '')
        .replaceAll(r'{', '')
        .replaceAll(r'}', '');
  }

  StringBuffer _createBuffer([bool isOverride]) {
    final StringBuffer buffer = StringBuffer();

    isOverride ??= false;
    if (isOverride) {
      buffer.writeln('  @override');
    }

    return buffer;
  }

  String _languageFromPath(String path) => basenameWithoutExtension(path).split('_').skip(1).join('_');

  bool _isArb(File it) => extension(it.path) == '.arb' && basenameWithoutExtension(it.path).startsWith('strings_');

  void _checkSourceFolder() {
    if (!source.existsSync()) {
      throw ArgumentError('The source folder does not exist.');
    }
  }

  int _sortQuantities(String a, String b) => _pluralEndingSortOrder[a].compareTo(_pluralEndingSortOrder[b]);

  String _quantityMapping(String quantity) {
    switch (quantity) {
      case 'zero':
        return '0';
      case 'one':
        return '1';
      case 'two':
        return '2';
      default:
        return quantity;
    }
  }

  static const String _generatedFileName = 'i18n';
  static const List<String> _rtl = <String>['ar', 'dv', 'fa', 'ha', 'he', 'iw', 'ji', 'ps', 'ur', 'yi'];
  static const List<String> _pluralEnding = <String>['zero', 'one', 'two', 'few', 'many', 'other'];

  static const Map<String, int> _pluralEndingSortOrder = <String, int>{
    'zero': 0,
    'one': 1,
    'two': 2,
    'few': 3,
    'many': 4,
    'other': 5,
  };

  static final RegExp parameterRegExp = RegExp(r'(?<!\\)\$\{?(.+?\b)\}?');
}
