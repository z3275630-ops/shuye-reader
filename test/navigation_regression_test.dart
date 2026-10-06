import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shuye_reader/main.dart';
import 'package:shuye_reader/models.dart';
import 'package:shuye_reader/reader.dart';
import 'package:shuye_reader/repository.dart';
import 'package:shuye_reader/services.dart';

class _SlowBooks extends ReaderRepository {
  _SlowBooks(super.db);
  Completer<Book>? pending;
  int opens = 0;
  @override
  Future<Book> book(String id) {
    opens++;
    return pending?.future ?? super.book(id);
  }
}

Future<void> ready(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pumpAndSettle();
}

void main() {
  sqfliteFfiInit();
  testWidgets(
    'empty notes remain usable at 320dp with large text and keyboard',
    (tester) async {
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
      await tester.runAsync(
        () => repo.saveSettings(ReaderSettings()..extra['app.textScale'] = 1.5),
      );
      await tester.pumpWidget(ShuyeApp(repository: repo));
      await ready(tester);
      await tester.tap(find.text('笔记'));
      await tester.pumpAndSettle();
      expect(find.text('把心动的句子留下来'), findsOneWidget);
      await tester.tap(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('把心动的句子留下来'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await ready(tester);
      await tester.runAsync(repo.close);
    },
  );

  testWidgets('shelf and note queries survive tab changes and clear visibly', (
    tester,
  ) async {
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
    await ready(tester);
    await tester.tap(find.text('书架'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '山间');
    await tester.pumpAndSettle();
    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '不存在的摘录');
    await tester.pumpAndSettle();
    expect(find.text('没有找到匹配的摘录'), findsOneWidget);
    await tester.tap(find.text('书架'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '山间',
    );
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('把日子读成诗').last,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('把日子读成诗'), findsWidgets);
    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '不存在的摘录',
    );
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('把心动的句子留下来'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await ready(tester);
    await tester.runAsync(repo.close);
  });

  testWidgets(
    'slow book double tap opens once, then guard resets after return',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = (await tester.runAsync(
        () => ReaderRepository.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      final repo = _SlowBooks(original.db);
      final books = (await tester.runAsync(original.books))!;
      final book = (await tester.runAsync(
        () => original.book(books.first.id),
      ))!;
      await tester.pumpWidget(ShuyeApp(repository: repo));
      await ready(tester);
      await tester.tap(find.text('书架'));
      await tester.pumpAndSettle();
      final title = find.text(book.title).last;
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      repo.pending = Completer<Book>();
      await tester.tap(title);
      await tester.tap(title);
      expect(repo.opens, 1);
      repo.pending!.complete(book);
      await ready(tester);
      expect(find.byType(ReaderScreen, skipOffstage: false), findsOneWidget);
      await tester.binding.handlePopRoute();
      await ready(tester);
      expect(find.byType(ReaderScreen, skipOffstage: false), findsNothing);
      repo.pending = null;
      await tester.ensureVisible(find.text(book.title).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(book.title).last);
      await ready(tester);
      expect(repo.opens, 2);
      expect(find.byType(ReaderScreen, skipOffstage: false), findsOneWidget);
      await tester.binding.handlePopRoute();
      await ready(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await ready(tester);
      await tester.runAsync(repo.close);
    },
  );

  testWidgets('widget link can open another book while a reader is visible', (
    tester,
  ) async {
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
    final books = (await tester.runAsync(repo.books))!;
    await tester.pumpWidget(ShuyeApp(repository: repo));
    await ready(tester);
    DeviceReader.events.add(MethodCall('link', 'shuye://book/${books[0].id}'));
    await ready(tester);
    expect(find.byType(ReaderScreen), findsOneWidget);
    DeviceReader.events.add(MethodCall('link', 'shuye://book/${books[1].id}'));
    await ready(tester);
    expect(
      tester.widget<ReaderScreen>(find.byType(ReaderScreen)).book.id,
      books[1].id,
    );
    expect(find.byType(ReaderScreen, skipOffstage: false), findsNWidgets(2));
    await tester.binding.handlePopRoute();
    await ready(tester);
    expect(
      tester.widget<ReaderScreen>(find.byType(ReaderScreen)).book.id,
      books[0].id,
    );
    await tester.binding.handlePopRoute();
    await ready(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await ready(tester);
    await tester.runAsync(repo.close);
  });

  testWidgets('covered reader does not count another route as reading time', (
    tester,
  ) async {
    final repo = (await tester.runAsync(
      () => ReaderRepository.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    ))!;
    final book = (await tester.runAsync(
      () async => repo.book((await repo.books()).first.id),
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          book: book,
          repository: repo,
          settings: ReaderSettings(),
        ),
      ),
    );
    await ready(tester);
    await tester.pump(const Duration(seconds: 3));
    Navigator.of(tester.element(find.byType(ReaderScreen))).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('覆盖页面')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    final stats = (await tester.runAsync(repo.statistics))!;
    await tester.pump();
    expect(stats.values.fold<int>(0, (a, b) => a + b), inInclusiveRange(3, 4));
    expect(tester.takeException(), isNull);
    await tester.runAsync(repo.close);
  });
}
