import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shuye_reader/appearance.dart';
import 'package:shuye_reader/models.dart';
import 'package:shuye_reader/repository.dart';
import 'package:shuye_reader/shelf_layouts.dart';
import 'package:shuye_reader/workbench.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('mobile text and action colors remain readable: $brightness', () {
      final c = applicationTheme(brightness).colorScheme;
      double contrast(Color a, Color b) {
        final x = a.computeLuminance(), y = b.computeLuminance();
        return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
      }

      for (final surface in [
        c.surface,
        c.surfaceContainer,
        c.surfaceContainerLowest,
      ]) {
        expect(contrast(c.onSurface, surface), greaterThanOrEqualTo(4.5));
        expect(
          contrast(c.onSurfaceVariant, surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrast(c.primary, surface), greaterThanOrEqualTo(4.5));
      }
      expect(contrast(c.primary, c.onPrimary), greaterThanOrEqualTo(4.5));
    });

    testWidgets(
      'shelf preview and settings persist at 320px and large text: $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = ReaderSettings()
          ..extra['reader.background'] = 'F4EDDF';
        var saves = 0;
        final books = List.generate(
          3,
          (i) => Book(
            id: '$i',
            title: '藏书 $i',
            author: '作者',
            chapters: const [Chapter('一', '正文')],
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: applicationTheme(brightness),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () => configureShelf(
                    c,
                    settings,
                    () async {
                      saves++;
                    },
                    books: books,
                    cover: (_) => const ColoredBox(color: Colors.grey),
                  ),
                  child: const Text('布置书架'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('布置书架'));
        await tester.pumpAndSettle();
        for (final name in shelfNames.values) {
          await tester.ensureVisible(find.widgetWithText(ChoiceChip, name));
          await tester.tap(find.widgetWithText(ChoiceChip, name));
          await tester.pumpAndSettle();
          expect(find.text('书架预览 · $name'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.ensureVisible(find.byType(Slider).first);
        tester.widget<Slider>(find.byType(Slider).first).onChanged!(5);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('保存书架'));
        await tester.tap(find.text('保存书架'));
        await tester.pumpAndSettle();
        expect(saves, 1);
        expect(settings.value('bookshelf.layout', ''), 'simple');
        expect(settings.number('bookshelf.columns', 0), 5);
        expect(settings.value('reader.background', ''), 'F4EDDF');
      },
    );

    testWidgets(
      'assistant composer stays usable with keyboard and many prompts: $brightness',
      (tester) async {
        sqfliteFfiInit();
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final repo = (await tester.runAsync(
          () => ReaderRepository.open(
            path: inMemoryDatabasePath,
            factory: databaseFactoryFfi,
          ),
        ))!;
        await tester.runAsync(() async {
          for (var i = 0; i < 12; i++) {
            await repo.putEntry('prompts', {'名称': '提示词 $i', '提示词': '问题 $i'});
          }
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: applicationTheme(brightness),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () => showAiAssistant(c, repo, ReaderSettings()),
                  child: const Text('助手'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('助手'));
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('解释文字'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '解释文字',
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '这个章节的重点是什么？');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getRect(find.text('发送')).bottom, lessThanOrEqualTo(360));
        Navigator.of(tester.element(find.text('阅读助手'))).pop();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(repo.close);
      },
    );
  }

  final output = Platform.environment['SHUYE_CAPTURE_DIR'];
  testWidgets('capture mobile appearance and shelf panels', (tester) async {
    for (final font in [
      ('Roboto', 'SHUYE_PREVIEW_FONT'),
      ('serif', 'SHUYE_PREVIEW_SERIF'),
      ('MaterialIcons', 'SHUYE_PREVIEW_ICONS'),
    ]) {
      final bytes = (await tester.runAsync(
        () => File(Platform.environment[font.$2]!).readAsBytes(),
      ))!;
      await (FontLoader(
        font.$1,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    sqfliteFfiInit();
    final repo = (await tester.runAsync(
      () => ReaderRepository.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    ))!;
    for (final brightness in Brightness.values) {
      final settings = ReaderSettings();
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: applicationTheme(brightness),
            home: Scaffold(
              body: Builder(
                builder: (c) => Column(
                  children: [
                    TextButton(
                      onPressed: () =>
                          configureAppearance(c, settings, () async {}),
                      child: const Text('外观'),
                    ),
                    TextButton(
                      onPressed: () => configureShelf(c, settings, () async {}),
                      child: const Text('书架设置'),
                    ),
                    TextButton(
                      onPressed: () => showAiAssistant(c, repo, settings),
                      child: const Text('助手'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> capture(String name) async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output!).create(recursive: true);
          await File('$output/$name-${brightness.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.tap(find.text('外观'));
      await tester.pumpAndSettle();
      await capture('appearance');
      Navigator.of(tester.element(find.text('应用外观'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('书架设置'));
      await tester.pumpAndSettle();
      await capture('shelf-settings');
      Navigator.of(tester.element(find.text('布置你的书架'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('助手'));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await capture('assistant');
      Navigator.of(tester.element(find.text('阅读助手'))).pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox());
    }
    await tester.runAsync(repo.close);
  }, skip: output == null);
}
