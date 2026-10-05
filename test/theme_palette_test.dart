import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuye_reader/appearance.dart';
import 'package:shuye_reader/models.dart';
import 'package:shuye_reader/reader.dart';
import 'package:shuye_reader/share_card.dart';

import 'preview_fonts.dart';

void main() {
  setUp(() => appAppearance.value = const AppAppearance());
  tearDown(() => appAppearance.value = const AppAppearance());
  test('palette restores, unknown palette falls back, reader paper stays independent', () {
    final settings = ReaderSettings();
    settings.extra['app.theme'] = 'mist';
    settings.theme = 'night';
    final restored = ReaderSettings.fromJson(settings.toJson());
    expect(AppAppearance.fromSettings(restored).theme, 'mist');
    expect(restored.theme, 'night');
    restored.extra['app.theme'] = 'unknown';
    expect(AppAppearance.fromSettings(restored).theme, 'claude');
  });
  test(
    'mist ink and action contrast holds in both modes and reader papers',
    () {
      double contrast(Color a, Color b) {
        final x = a.computeLuminance(), y = b.computeLuminance();
        return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
      }

      appAppearance.value = const AppAppearance(theme: 'mist');
      for (final brightness in Brightness.values) {
        final colors = applicationTheme(brightness).colorScheme;
        for (final surface in [
          colors.surface,
          colors.surfaceContainerLowest,
          colors.surfaceContainerLow,
          colors.surfaceContainer,
          colors.surfaceContainerHigh,
          colors.surfaceContainerHighest,
        ]) {
          expect(
            contrast(colors.onSurface, surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(colors.onSurfaceVariant, surface),
            greaterThanOrEqualTo(4.5),
          );
        }
        expect(
          contrast(colors.primary, colors.onPrimary),
          greaterThanOrEqualTo(4.5),
        );
      }
      for (final paper in readerSchemes.values) {
        final selection = readerSelectionTheme(paper);
        expect(
          contrast(selection.selectionHandleColor!, paper[0]),
          greaterThanOrEqualTo(3),
        );
        expect(
          contrast(
            paper[1],
            Color.alphaBlend(selection.selectionColor!, paper[0]),
          ),
          greaterThanOrEqualTo(4.5),
        );
      }
    },
  );
  for (final brightness in Brightness.values) {
    for (final large in [false, true]) {
      testWidgets('palette can change and save in $brightness, large $large', (
        tester,
      ) async {
        await loadShuyeSerif(tester);
        tester.view.physicalSize = large
            ? const Size(320, 640)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = ReaderSettings();
        settings.theme = 'night';
        var saves = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: applicationTheme(brightness),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(large ? 1.5 : 1)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () => configureAppearance(c, settings, () async {
                    saves++;
                  }),
                  child: const Text('外观'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('外观'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('海雾'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('海雾'));
        await tester.pumpAndSettle();
        expect(saves, 1);
        expect(settings.value('app.theme', ''), 'mist');
        expect(settings.theme, 'night');
        final chip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, '海雾'),
        );
        expect(chip.selected, isTrue);
        await tester.tap(find.text('暖白'));
        await tester.pumpAndSettle();
        expect(settings.value('app.theme', ''), 'claude');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  final output = Platform.environment['SHUYE_CAPTURE_DIR'];
  testWidgets('capture mist palette and share cards', (tester) async {
    await loadShuyeSerif(tester);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    appAppearance.value = const AppAppearance(theme: 'mist');
    for (final brightness in Brightness.values) {
      final key = GlobalKey();
      final settings = ReaderSettings();
      settings.extra['app.theme'] = 'mist';
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: applicationTheme(brightness),
            home: Scaffold(
              body: Builder(
                builder: (c) => ListView(
                  children: [
                    TextButton(
                      onPressed: () =>
                          configureAppearance(c, settings, () async {}),
                      child: const Text('外观'),
                    ),
                    QuoteCard(
                      quote: '翻开一页，听见生活的回声。',
                      title: '山间来信',
                      template: brightness == Brightness.dark
                          ? 'night'
                          : 'calendar',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/$name-${brightness.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('mist-share');
      await tester.tap(find.text('外观'));
      await tester.pumpAndSettle();
      await capture('mist-appearance');
      await tester.pumpWidget(const SizedBox());
    }
  }, skip: output == null);
}
