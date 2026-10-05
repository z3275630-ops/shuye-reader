import 'preview_fonts.dart';

// Optional screenshots of real Flutter widgets, not Android device screenshots.
// SHUYE_CAPTURE_DIR and local font paths are supplied only for local visual QA.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shuye_reader/main.dart';
import 'package:shuye_reader/branding.dart';
import 'package:shuye_reader/repository.dart';
import 'package:shuye_reader/share_card.dart';

void main() {
  final output = Platform.environment['SHUYE_CAPTURE_DIR'];
  testWidgets('capture actual bookshelf and reading widgets', (tester) async {
    await loadShuyeSerif(tester);
    sqfliteFfiInit();
    for (final pair in [
      ('Roboto', Platform.environment['SHUYE_PREVIEW_FONT']!),
      ('serif', Platform.environment['SHUYE_PREVIEW_SERIF']!),
      ('MaterialIcons', Platform.environment['SHUYE_PREVIEW_ICONS']!),
    ]) {
      final bytes = (await tester.runAsync(() => File(pair.$2).readAsBytes()))!;
      final loader = FontLoader(pair.$1)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
    tester.view.physicalSize = const Size(390, 1040);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = (await tester.runAsync(
      () => ReaderRepository.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    ))!;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ShuyeApp(repository: repo),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final ctx = key.currentContext!;
      for (final asset in [
        'mountain.webp',
        'poetry.webp',
        'notebook.webp',
        'shuye-cover.webp',
        'shuye-mark.webp',
      ]) {
        await precacheImage(AssetImage('assets/art/$asset'), ctx);
      }
    });
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output!).create(recursive: true);
        await File('$output/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('home');
    await tester.tap(find.byTooltip('调整首页布局'));
    await tester.pumpAndSettle();
    await capture('home-layout');
    await tester.ensureVisible(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('书架'));
    await tester.pumpAndSettle();
    await capture('bookshelf');
    await tester.tap(find.byTooltip('书架选项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书架装修'));
    await tester.pumpAndSettle();
    await capture('shelf-preview');
    Navigator.of(tester.element(find.text('布置你的书架'))).pop();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('山间来信').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('山间来信').last);
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await capture('reader');
    await tester.tap(find.byTooltip('阅读设置'));
    await tester.pumpAndSettle();
    await capture('typography');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Claude'));
    await tester.pumpAndSettle();
    await capture('typography-claude');
    await tester.tap(find.text('开始阅读'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await capture('reader-claude');
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    await capture('reader-claude-page2');
    await tester.tap(find.byTooltip('摘录与笔记'));
    await tester.pumpAndSettle();
    await capture('note-editor');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('阅读工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生成摘录卡片'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('日历手记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日历手记'));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<QuoteCard>(find.byType(QuoteCard)).template,
      'calendar',
    );
    final quoteBoundary = tester
        .element(find.byType(QuoteCard))
        .findAncestorRenderObjectOfType<RenderRepaintBoundary>()!;
    await tester.runAsync(() async {
      final image = await quoteBoundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$output/share-calendar.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();
    await capture('statistics');
    await tester.tap(find.text('书架'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('整理书库'));
    await tester.pump();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    await capture('collections');
    await tester.pageBack();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('阅读工具箱'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阅读工具箱'));
    await tester.pumpAndSettle();
    await capture('toolbox');
    await tester.pageBack();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(ShuyeIdentityCard));
    await tester.pumpAndSettle();
    await capture('settings-brand');
    await tester.scrollUntilVisible(find.text('关于书叶'), 300);
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于书叶'));
    await tester.pumpAndSettle();
    expect(find.text(shuyeVersion), findsOneWidget);
    expect(find.textContaining('非 Reeden 官方'), findsNothing);
    await capture('about');
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('应用外观'), -300);
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用外观'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    await capture('home-dark');
    await tester.tap(find.text('书架'));
    await tester.pumpAndSettle();
    await capture('bookshelf-dark');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => repo.close());
  }, skip: output == null);
}
