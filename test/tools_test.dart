import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shuye_reader/book_proposals.dart';
import 'package:shuye_reader/character_graph.dart';
import 'package:shuye_reader/models.dart';
import 'package:shuye_reader/presets.dart';
import 'package:shuye_reader/reader.dart';
import 'package:shuye_reader/repository.dart';
import 'package:shuye_reader/workbench.dart';

void main() {
  sqfliteFfiInit();
  testWidgets(
    'small-screen toolbox, reading presets and character graph remain navigable at large text size',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = (await tester.runAsync(
        () => ReaderRepository.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      final settings = ReaderSettings();
      Widget app(Widget child) => MaterialApp(
        key: UniqueKey(),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(1.4)),
          child: child!,
        ),
        home: child,
      );
      await tester.pumpWidget(
        app(WorkshopScreen(repo: repo, settings: settings)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('主题与规则方案'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('主题与规则方案'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReadingPresets), findsOneWidget);
      await tester.tap(find.text('墨水屏'));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(settings.flag('reader.eink'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        app(
          const CharacterGraph(
            characters: [
              {'人物': '林夏', '关联人物': '老邮差', '关系说明': '朋友'},
              {'人物': '老邮差', '角色': '配角'},
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('林夏 → 老邮差'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(app(BookProposals(repo: repo)));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('目前没有'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(repo.close);
    },
  );
  testWidgets(
    'wide reader shows two pages and responds to keyboard without splitting Unicode',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = (await tester.runAsync(
        () => ReaderRepository.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      final b = Book(
        id: 'wide',
        title: '宽屏',
        chapters: [Chapter('正文', List.filled(1200, '文字🙂阅读。').join())],
      );
      await tester.runAsync(() => repo.addBook(b));
      final settings = ReaderSettings(
        extra: {'reader.doublePage': true, 'reader.animation': 'none'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(book: b, repository: repo, settings: settings),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsNWidgets(2));
      final initial = b.offset;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(b.offset, greaterThan(initial));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await repo.close();
      });
    },
  );
}
