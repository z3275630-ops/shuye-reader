import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuye_reader/appearance.dart';
import 'package:shuye_reader/branding.dart';
import 'package:shuye_reader/home_dashboard.dart';
import 'package:shuye_reader/models.dart';

import 'preview_fonts.dart';

Widget _home() => HomeDashboard(
  books: const [],
  stats: const {},
  notes: 0,
  settings: ReaderSettings(),
  cover: (_) => const SizedBox(),
  open: (_) async {},
  shelf: () {},
  tools: () {},
  statistics: () {},
  goal: () {},
);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('brand cards remain readable on narrow screens: $brightness', (
      tester,
    ) async {
      await loadShuyeSerif(tester);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final palette in appThemes.keys) {
        await tester.pumpWidget(
          MaterialApp(
            theme: applicationTheme(brightness, palette: palette),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(20),
                children: const [
                  ShuyeWelcomeCard(subtitle: '10 月 6 日 · 留一点时间给阅读'),
                  ShuyeIdentityCard(),
                  ShuyeCover(),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final headline = find.text('给自己，\n一页安静。');
        expect(headline, findsOneWidget);
        // Artwork must not force scaled labels to extend outside their card.
        final card = tester.getRect(find.byType(ShuyeWelcomeCard));
        expect(card.contains(tester.getBottomRight(headline)), isTrue);
        await tester.ensureVisible(find.byType(ShuyeIdentityCard));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }

  final output = Platform.environment['SHUYE_CAPTURE_DIR'];
  testWidgets('capture theme-aware book-leaf branding', (tester) async {
    await loadShuyeSerif(tester);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    for (final width in [390.0, 320.0]) {
      tester.view.physicalSize = Size(width, 844);
      for (final brightness in Brightness.values) {
        for (final palette in appThemes.keys) {
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: applicationTheme(brightness, palette: palette),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(width == 320 ? 1.5 : 1),
                  ),
                  child: child!,
                ),
                home: Scaffold(
                  body: ListView(
                    padding: const EdgeInsets.all(20),
                    children: const [
                      ShuyeWelcomeCard(subtitle: '10 月 6 日 · 留一点时间给阅读'),
                      SizedBox(height: 18),
                      ShuyeIdentityCard(),
                      SizedBox(height: 18),
                      ShuyeCover(),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(output!).create(recursive: true);
            await File(
              '$output/brand-$palette-${brightness.name}-${width.toInt()}.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    }
    // Also render the actual dashboard, without adding sample reading records.
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: applicationTheme(Brightness.light, palette: 'claude'),
          home: Scaffold(body: _home()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$output/brand-empty-home.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
  }, skip: output == null);
}
