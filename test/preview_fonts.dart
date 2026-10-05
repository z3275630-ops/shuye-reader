import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuye_reader/appearance.dart';

// Load the actual shipped face, so previews do not substitute Windows fonts.
Future<void> loadShuyeSerif(WidgetTester tester) async {
  final bytes = (await tester.runAsync(
    () => File('assets/fonts/ShuyeSerif-Regular.ttf').readAsBytes(),
  ))!;
  await (FontLoader(
    ShuyeStyle.fontFamily,
  )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}
