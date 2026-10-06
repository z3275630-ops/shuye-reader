import 'reader_test_support.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shuye_reader/appearance.dart';
import 'package:shuye_reader/home_dashboard.dart';
import 'package:shuye_reader/main.dart';
import 'package:shuye_reader/repository.dart';
import 'package:shuye_reader/services.dart';
import 'package:shuye_reader/statistics_period.dart';

import 'preview_fonts.dart';

Future<void> ready(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => appAppearance.value = const AppAppearance());
  for (final brightness in Brightness.values) {
    testWidgets(
      'period charts use real dates and units at 320dp large text: $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final today = DateTime.now();
        await tester.pumpWidget(
          MaterialApp(
            theme: applicationTheme(brightness),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                children: [
                  PeriodStatistics(stats: {dayKey(today): 420}),
                ],
              ),
            ),
          ),
        );
        for (final period in ['周', '月', '年']) {
          await tester.ensureVisible(find.widgetWithText(ChoiceChip, period));
          await tester.tap(find.widgetWithText(ChoiceChip, period));
          await tester.pumpAndSettle();
          final chart = tester.widget<ReadingDurationChart>(
            find.byType(ReadingDurationChart),
          );
          expect(chart.values.fold<int>(0, (a, b) => a + b), 420);
          expect(
            chart.labels.every(
              (s) => period == '周'
                  ? s.startsWith('周')
                  : s.endsWith(period == '月' ? '日' : '月'),
            ),
            isTrue,
          );
          final index = chart.values.indexOf(420);
          final bar = find.byKey(ValueKey('duration-bar-$index'));
          await tester.ensureVisible(bar);
          await tester.tap(bar);
          await tester.pumpAndSettle();
          expect(find.textContaining('· 7 分钟'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(children: const [PeriodStatistics(stats: {})]),
            ),
          ),
        );
        expect(find.byType(ReadingDurationChart), findsNothing);
        expect(find.text('这个时段还没有阅读记录。'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  final output = Platform.environment['SHUYE_CAPTURE_DIR'];
  testWidgets('capture Claude linked application, reader and duration charts', (
    tester,
  ) async {
    await loadShuyeSerif(tester);
    final iconBytes = (await tester.runAsync(
      () => File(Platform.environment['SHUYE_PREVIEW_ICONS']!).readAsBytes(),
    ))!;
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(iconBytes)))).load();
    sqfliteFfiInit();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = (await tester.runAsync(
      () => ReaderRepository.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    ))!;
    final book = (await tester.runAsync(repo.books))!
        .where((b) => b.title == '山间来信')
        .first;
    final key = GlobalKey();
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output!).create(recursive: true);
        await File('$output/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    Future<void> open() async {
      DeviceReader.events.add(MethodCall('link', 'shuye://book/${book.id}'));
      await ready(tester);
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ShuyeApp(repository: repo),
      ),
    );
    await ready(tester);
    await tester.runAsync(() async {
      for (final asset in [
        'mountain.webp',
        'poetry.webp',
        'notebook.webp',
        'shuye-cover.webp',
        'shuye-mark.webp',
      ]) {
        await precacheImage(
          AssetImage('assets/art/$asset'),
          key.currentContext!,
        );
      }
    });
    await capture('claude-home');
    await tester.tap(find.text('书架'));
    await ready(tester);
    await capture('claude-bookshelf');
    await open();
    await capture('claude-reader-default');
    await tester.tapAt(tester.getCenter(find.byType(SelectableText).first));
    await tester.pump(const Duration(milliseconds: 300));
    await capture('claude-reader-controls');
    await tester.tapAt(tester.getCenter(find.byType(SelectableText).first));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    for (final palette in ['海雾', '夜读']) {
      await revealReaderControls(tester);
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, palette));
      await tester.tap(find.widgetWithText(ChoiceChip, palette));
      await tester.pumpAndSettle();
      await capture(
        palette == '海雾' ? 'mist-settings' : 'claude-night-settings',
      );
      await tester.ensureVisible(find.text('开始阅读'));
      await tester.tap(find.text('开始阅读'));
      await ready(tester);
      await capture(palette == '海雾' ? 'mist-reader' : 'claude-night-reader');
      await tester.binding.handlePopRoute();
      await ready(tester);
      await capture(
        palette == '海雾'
            ? 'mist-bookshelf-linked'
            : 'claude-night-bookshelf-linked',
      );
      await open();
    }
    await tester.binding.handlePopRoute();
    await ready(tester);
    await tester.tap(find.text('首页'));
    await ready(tester);
    await capture('claude-night-home-linked');
    await tester.pumpWidget(const SizedBox());
    await ready(tester);
    await tester.runAsync(repo.close);

    // Synthetic chart data is restricted to this preview; never seed the application.
    final now = DateTime.now();
    final stats = {
      for (var i = 0; i < 20; i++)
        dayKey(DateTime(now.year, now.month, now.day - i)): (i % 5 + 1) * 120,
    };
    for (final brightness in Brightness.values) {
      appAppearance.value = const AppAppearance();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: applicationTheme(brightness),
            home: Scaffold(
              appBar: AppBar(title: const Text('阅读时长')),
              body: ListView(
                padding: const EdgeInsets.all(12),
                children: [PeriodStatistics(stats: stats)],
              ),
            ),
          ),
        ),
      );
      for (final period in ['周', '月', '年']) {
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, period));
        await tester.tap(find.widgetWithText(ChoiceChip, period));
        await capture('duration-${brightness.name}-$period');
      }
    }
    await tester.pumpWidget(const SizedBox());
  }, skip: output == null);
}
