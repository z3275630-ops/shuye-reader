import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shuye_reader/main.dart';
import 'package:shuye_reader/repository.dart';

void main() {
  sqfliteFfiInit();
  testWidgets(
    'reader supports turn page, note creation, outline, search and resume',
    (tester) async {
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
      await tester.pumpWidget(ShuyeApp(repository: repo));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.text('山间来信'), findsWidgets);
      await tester.ensureVisible(find.text('山间来信').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('山间来信').last);
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 /'), findsWidgets);
      await tester.tap(find.byTooltip('摘录与笔记'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '测试笔记');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect((await repo.notes()).single.comment, '测试笔记');
      });
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(of: find.text('夜读'), matching: find.byType(ChoiceChip)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始阅读'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).style!.color,
        const Color(0xffbcc4b7),
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('章节目录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第二章 慢一点的日子'));
      await tester.pumpAndSettle();
      expect(find.text('第二章 慢一点的日子'), findsOneWidget);
      await tester.tap(find.byTooltip('全文搜索'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '邮局');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.textContaining('找到'), findsOneWidget);
      await tester.tap(find.text('第一章 风从山里来').first);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('继续上次的故事'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => repo.close());
    },
  );
  for (final size in [const Size(320, 640), const Size(600, 800)]) {
    testWidgets('navigation fits $size and exposes honest empty statistics', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = (await tester.runAsync(
        () => ReaderRepository.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      await tester.pumpWidget(ShuyeApp(repository: repo));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('统计'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('最近 28 天'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('最近 28 天'), findsOneWidget);
      await tester.tap(find.text('笔记'));
      await tester.pumpAndSettle();
      expect(find.text('把心动的句子留下来'), findsOneWidget);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.text('字体与纸色'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => repo.close());
    });
  }
}
