import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shuye_reader/appearance.dart';
import 'package:shuye_reader/facets.dart';
import 'package:shuye_reader/home_dashboard.dart';
import 'package:shuye_reader/library_collections.dart';
import 'package:shuye_reader/models.dart';
import 'package:shuye_reader/main.dart';
import 'package:shuye_reader/privacy.dart';
import 'package:shuye_reader/repository.dart';
import 'package:shuye_reader/share_card.dart';
import 'package:shuye_reader/statistics_period.dart';
import 'package:shuye_reader/tool_catalog.dart';

class DelayedPrivacyRepo extends ReaderRepository {
  final Completer<ReaderSettings> ready;
  DelayedPrivacyRepo(super.db, this.ready);
  @override
  Future<ReaderSettings> settings() => ready.future;
}

void main() {
  sqfliteFfiInit();
  Future<ReaderRepository> memory() => ReaderRepository.open(
    path: inMemoryDatabasePath,
    factory: databaseFactoryFfi,
  );
  test('collection edits preserve full content, binary source, notes and unrelated metadata; invalid batches roll back', () async {
    final repo = await memory();
    final b = Book(
      id: 'facets',
      title: '真实正文',
      author: '甲',
      chapters: [const Chapter('第一章', '正文🙂'), const Chapter('第二章', '后续内容')],
      source: 'AQID',
      metadata: {
        'tags': '科幻，旅行, 科幻',
        'category': '小说',
        'rating': 4,
        'review': '保留书评',
      },
    );
    await repo.addBook(b);
    await repo.addNote(
      Note(
        id: 'n-facet',
        bookId: b.id,
        chapter: 1,
        offset: 1,
        quote: '后续',
        comment: '保留',
        created: 1,
      ),
    );
    await repo.putEntry('facets', {
      'field': 'tags',
      'name': '旅行',
    }, id: 'empty-facet');
    await repo.assignFacet('tags', '阅读', [b.id]);
    await repo.renameFacet('tags', '旅行', '科幻');
    var loaded = await repo.book(b.id);
    expect(splitTags(loaded.metadata['tags'] as String), ['科幻', '阅读']);
    expect(loaded.source, 'AQID');
    expect(loaded.chapters.map((c) => c.text), ['正文🙂', '后续内容']);
    expect((await repo.notes()).single.comment, '保留');
    expect(loaded.metadata['review'], '保留书评');
    expect(loaded.metadata['rating'], 4);
    await expectLater(
      repo.assignFacet('category', '错误批次', [b.id, 'missing-book']),
      throwsFormatException,
    );
    expect((await repo.book(b.id)).metadata['category'], '小说');
    await repo.renameFacet('tags', '科幻', '');
    await repo.renameFacet('author', '甲', '乙');
    loaded = await repo.book(b.id);
    expect(loaded.author, '乙');
    expect(loaded.metadata['tags'], '阅读');
    expect(await repo.entries('facets'), isEmpty);
    final settings = ReaderSettings(
      extra: {
        'home.sections': 'overview,continue',
        'home.banner': false,
        'app.themeMode': 'dark',
        'app.textScale': 1.25,
      },
    );
    await repo.saveSettings(settings);
    final snapshot = await repo.backup();
    await repo.restore(snapshot);
    expect((await repo.settings()).number('app.textScale', 1), 1.25);
    expect((await repo.settings()).flag('home.banner'), isFalse);
    expect((await repo.book(b.id)).chapters.last.text, '后续内容');
    await repo.close();
  });
  test(
    'statistics use calendar month, Monday weeks and exact year boundaries',
    () {
      final stats = {
        '2024-02-01': 60,
        '2024-02-29': 120,
        '2024-03-01': 180,
        '2024-12-31': 240,
        '2025-01-01': 300,
      };
      expect(
        periodBounds(ReadingPeriod.month, DateTime(2024, 2, 20)).$2,
        DateTime(2024, 3),
      );
      expect(statsInPeriod(stats, ReadingPeriod.month, DateTime(2024, 2)), {
        '2024-02-01': 60,
        '2024-02-29': 120,
      });
      expect(
        periodBounds(ReadingPeriod.week, DateTime(2025, 1, 1)).$1,
        DateTime(2024, 12, 30),
      );
      expect(statsInPeriod(stats, ReadingPeriod.week, DateTime(2025, 1, 1)), {
        '2024-12-31': 240,
        '2025-01-01': 300,
      });
      expect(
        statsInPeriod(
          stats,
          ReadingPeriod.year,
          DateTime(2024),
        ).values.fold<int>(0, (a, b) => a + b),
        600,
      );
      expect(
        visibleHomeSections(
          ReaderSettings(
            extra: {'home.sections': 'goal,unknown,goal,continue'},
          ),
        ),
        ['goal', 'continue'],
      );
      expect(
        visibleHomeSections(ReaderSettings(extra: {'home.sections': ''})),
        isEmpty,
      );
    },
  );
  testWidgets(
    'tool search shows actual actions on a small screen with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var clicked = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: Scaffold(
              body: ToolCatalog(
                actions: [
                  ToolAction(Icons.cloud, '上传加密书库', '先加密再上传', () => clicked++),
                  ToolAction(
                    Icons.font_download,
                    '导入阅读字体',
                    'TTF / OTF / TTC',
                    () => clicked += 10,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '字体');
      await tester.pumpAndSettle();
      expect(find.text('上传加密书库'), findsNothing);
      expect(find.text('导入阅读字体'), findsOneWidget);
      await tester.tap(find.text('导入阅读字体'));
      expect(clicked, 10);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'home configuration persists hiding, restoring and goal style without changing reader settings',
    (tester) async {
      final s = ReaderSettings(
        fontSize: 23,
        extra: {
          'ai.endpoint': 'https://example.test',
          'home.sections': 'continue,goal,overview',
        },
      );
      final repo = (await tester.runAsync(memory))!;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: Scaffold(
            body: Builder(
              builder: (c) => FilledButton(
                onPressed: () =>
                    configureHome(c, s, () => repo.saveSettings(s)),
                child: const Text('配置首页'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('配置首页'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('隐藏阅读概览'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(visibleHomeSections(s), ['continue', 'goal']);
      await tester.ensureVisible(find.text('进度条'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('进度条'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final saved = (await tester.runAsync(repo.settings))!;
      expect(saved.value('home.goalStyle', ''), 'bar');
      expect(saved.fontSize, 23);
      expect(saved.value('ai.endpoint', ''), 'https://example.test');
      await tester.ensureVisible(find.text('显示阅读概览'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('显示阅读概览'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(visibleHomeSections(s).last, 'overview');
      await tester.ensureVisible(find.byKey(const ValueKey('continue')));
      await tester.pumpAndSettle();
      final destination = tester.getCenter(
        find.byKey(const ValueKey('overview')),
      );
      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('continue'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await drag.moveBy(const Offset(0, 1));
      await tester.pump();
      final start = tester.getCenter(find.byKey(const ValueKey('continue')));
      final end = destination + const Offset(0, 56);
      for (var step = 1; step <= 12; step++) {
        await drag.moveTo(Offset.lerp(start, end, step / 12)!);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 500));
      await drag.up();
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      expect(visibleHomeSections((await tester.runAsync(repo.settings))!), [
        'goal',
        'overview',
        'continue',
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(repo.close);
    },
  );
  testWidgets(
    'collections browse real matching books and open the selected book',
    (tester) async {
      final repo = (await tester.runAsync(memory))!;
      final b = Book(
        id: 'grouped',
        title: '旅行之书',
        chapters: [const Chapter('正文', '正文')],
      );
      await tester.runAsync(() async {
        await repo.addBook(b);
        await repo.assignFacet('tags', '旅行', [b.id]);
      });
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryCollections(
            repo: repo,
            open: (book) async {
              opened = book.id;
            },
            cover: (_) => const Icon(Icons.book),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('旅行'));
      await tester.pumpAndSettle();
      expect(find.text('旅行之书'), findsOneWidget);
      expect(find.text('1 本书'), findsOneWidget);
      await tester.tap(find.text('旅行之书'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(opened, b.id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(repo.close);
    },
  );
  testWidgets(
    'privacy gate hides content during configuration load and while locked',
    (tester) async {
      final repo = (await tester.runAsync(memory))!;
      final ready = Completer<ReaderSettings>();
      await tester.pumpWidget(
        MaterialApp(
          home: PrivacyGate(
            repo: DelayedPrivacyRepo(repo.db, ready),
            child: const Text('私人书籍标题'),
          ),
        ),
      );
      expect(find.text('私人书籍标题'), findsNothing);
      ready.complete(ReaderSettings(extra: {'privacy.lock': true}));
      await tester.pumpAndSettle();
      expect(find.text('私人书籍标题'), findsNothing);
      expect(find.text('解锁书库'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      privacyEnabled.value = false;
      await tester.runAsync(repo.close);
    },
  );
  testWidgets(
    'share templates use selected content and retain complete emoji at the export limit',
    (tester) async {
      final quote = List.filled(810, '🙂').join();
      for (final template in shareTemplates.keys) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: QuoteCard(
                  quote: quote,
                  title: '真实标题',
                  template: template,
                  date: DateTime(2026, 10, 5),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('— 真实标题'), findsOneWidget);
        expect(
          find.text(String.fromCharCodes(quote.runes.take(800))),
          findsOneWidget,
        );
        if (template == 'calendar') {
          expect(find.text('2026 / 10'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'small-screen navigation and bookshelf retain contrast in dark mode with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = (await tester.runAsync(memory))!;
      await tester.runAsync(
        () => repo.saveSettings(
          ReaderSettings(
            extra: {'app.themeMode': 'dark', 'app.textScale': 1.4},
          ),
        ),
      );
      await tester.pumpWidget(ShuyeApp(repository: repo));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(NavigationBar))).brightness,
        Brightness.dark,
      );
      await tester.tap(find.text('书架'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('整理书库'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('统计'));
      await tester.pumpAndSettle();
      expect(find.text('阅读足迹'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      appAppearance.value = const AppAppearance();
      await tester.runAsync(repo.close);
    },
  );
  test('application appearance follows system or explicit mode and bounds text scaling', () {
    expect(
      AppAppearance.fromSettings(ReaderSettings()).themeMode,
      ThemeMode.system,
    );
    final a = AppAppearance.fromSettings(
      ReaderSettings(extra: {'app.themeMode': 'dark', 'app.textScale': 10}),
    );
    expect(a.themeMode, ThemeMode.dark);
    expect(a.scale, 1.5);
  });
}
