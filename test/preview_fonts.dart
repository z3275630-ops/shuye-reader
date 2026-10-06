import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuye_reader/appearance.dart';

// Load the actual shipped face, so previews do not substitute Windows fonts.
Future<void> loadShuyeSerif(WidgetTester tester) async {
  final bytes = (await tester.runAsync(
    () => File('assets/fonts/ShuyeSerif-Regular.ttf').readAsBytes(),
  ))!;
  final semibold = (await tester.runAsync(
    () => File('assets/fonts/ShuyeSerif-SemiBold.ttf').readAsBytes(),
  ))!;
  final lucide = (await tester.runAsync(() async {
    final config = File('.dart_tool/package_config.json');
    final packages =
        (jsonDecode(await config.readAsString())['packages'] as List);
    final rootPath =
        packages.firstWhere(
              (p) => p['name'] == 'lucide_icons_flutter',
            )['rootUri']
            as String;
    final root = config.absolute.uri.resolve(
      rootPath.endsWith('/') ? rootPath : '$rootPath/',
    );
    return File.fromUri(root.resolve('assets/lucide.ttf')).readAsBytes();
  }))!;
  await (FontLoader(
    'packages/lucide_icons_flutter/Lucide',
  )..addFont(Future.value(ByteData.sublistView(lucide)))).load();
  await (FontLoader(ShuyeStyle.fontFamily)
        ..addFont(Future.value(ByteData.sublistView(bytes)))
        ..addFont(Future.value(ByteData.sublistView(semibold))))
      .load();
}
