#!/usr/bin/env dart

/// Script a version.json fájl automatikus frissítéséhez a pubspec.yaml alapján.
library;

/// Használat:
///   dart tools/update_version.dart
///
/// Ez a script:
/// - Beolvassa a pubspec.yaml verzióját
/// - Frissíti a web/version.json fájlt
/// - Frissíti a build/web/version.json fájlt (ha létezik)

import 'dart:io';
import 'dart:convert';

void main() async {
  try {
    // Pubspec.yaml beolvasása
    final pubspecFile = File('pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      // ignore: avoid_print
      print('❌ Error: pubspec.yaml not found');
      exit(1);
    }

    final pubspecContent = await pubspecFile.readAsString();

    // Verzió kinyerése
    final versionRegex = RegExp(r'^version:\s*(.+)$', multiLine: true);
    final match = versionRegex.firstMatch(pubspecContent);

    if (match == null) {
      // ignore: avoid_print
      print('❌ Error: Version not found in pubspec.yaml');
      exit(1);
    }

    final version = match.group(1)!.trim();
    final buildDate = DateTime.now().toIso8601String().split('T')[0];

    // ignore: avoid_print
    print('📦 Version found: $version');
    // ignore: avoid_print
    print('📅 Build date: $buildDate');

    // Version JSON objektum
    final versionJson = {
      'version': version,
      'buildDate': buildDate,
    };

    final jsonContent = const JsonEncoder.withIndent('  ').convert(versionJson);

    // web/version.json írása
    final webVersionFile = File('web/version.json');
    await webVersionFile.writeAsString('$jsonContent\n');
    // ignore: avoid_print
    print('✅ Updated: web/version.json');

    // build/web/version.json írása (ha létezik a build mappa)
    final buildWebDir = Directory('build/web');
    if (buildWebDir.existsSync()) {
      final buildVersionFile = File('build/web/version.json');
      await buildVersionFile.writeAsString('$jsonContent\n');
      // ignore: avoid_print
      print('✅ Updated: build/web/version.json');
    }

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('🎉 Version update completed successfully!');
    // ignore: avoid_print
    print('   Version: $version');
  } catch (e) {
    // ignore: avoid_print
    print('❌ Error: $e');
    exit(1);
  }
}
