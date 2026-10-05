import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shuye_reader/models.dart';
import 'package:shuye_reader/repository.dart';

void main() {
  sqfliteFfiInit();
  late ReaderRepository repo;
  setUp(() async {
    repo = await ReaderRepository.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
  });
  tearDown(() async {
    await repo.close();
  });
  Book sample() => Book(
    id: 'test-book',
    title: '测试',
    chapters: const [Chapter('一', '这是第一章'), Chapter('二', '这是第二章')],
  );
  const note = Note(
    id: 'n1',
    bookId: 'test-book',
    chapter: 0,
    offset: 1,
    quote: '摘录',
    comment: '笔记',
    created: 1,
  );
  test('duplicates preserve existing progress; deleting a book cascades notes and records', () async {
    final b = sample();
    expect(await repo.addBook(b), isTrue);
    b.chapter = 1;
    b.offset = 3;
    b.lastRead = 10;
    await repo.saveProgress(b);
    expect(await repo.addBook(sample()), isFalse);
    expect(
      (await repo.books()).firstWhere((b) => b.id == 'test-book').offset,
      3,
    );
    await repo.addNote(note);
    await repo.record(b.id, 120);
    expect((await repo.notes()).length, 1);
    expect((await repo.statistics()).values.single, 120);
    await repo.deleteBook(b.id);
    expect(await repo.notes(), isEmpty);
    expect(await repo.statistics(), isEmpty);
  });
  test(
    'complete backup restores content, settings, anchors and statistics',
    () async {
      await repo.addBook(sample());
      await repo.addNote(note);
      await repo.record('test-book', 60);
      await repo.saveSettings(ReaderSettings(theme: 'night', fontSize: 25));
      final data = await repo.backup();
      await repo.deleteBook('test-book');
      await repo.restore(data);
      expect((await repo.books()).any((b) => b.id == 'test-book'), isTrue);
      expect((await repo.notes()).single.comment, '笔记');
      expect((await repo.settings()).theme, 'follow');
      expect((await repo.settings()).value('app.themeMode', ''), 'dark');
      expect((await repo.statistics()).values.single, 60);
    },
  );
  test('invalid foreign keys or late transaction failures never destroy existing data', () async {
    final before = (await repo.books()).map((b) => b.id).toList();
    final j = jsonDecode(await repo.backup()) as Map<String, dynamic>;
    j['records'] = [
      {'book_id': 'missing', 'seconds': 5, 'day': '2026-10-04'},
    ];
    await expectLater(repo.restore(jsonEncode(j)), throwsFormatException);
    expect((await repo.books()).map((b) => b.id), before);
    j['records'] = [];
    final rows = j['settings'] as List;
    rows.add(
      rows.first,
    ); // Fails after deleting/inserting books, inside transaction.
    await expectLater(repo.restore(jsonEncode(j)), throwsA(anything));
    expect((await repo.books()).map((b) => b.id), before);
  });
  test('settings, notes and progress survive close/reopen; samples do not return after deletion', () async {
    final dir = await Directory.systemTemp.createTemp('shuye-test-');
    final disk = await ReaderRepository.open(
      path: '${dir.path}/book.db',
      factory: databaseFactoryFfi,
    );
    for (final b in await disk.books()) {
      await disk.deleteBook(b.id);
    }
    final b = sample();
    await disk.addBook(b);
    b.offset = 2;
    await disk.saveProgress(b);
    await disk.addNote(note);
    await disk.close();
    final reopened = await ReaderRepository.open(
      path: '${dir.path}/book.db',
      factory: databaseFactoryFfi,
    );
    expect((await reopened.books()).length, 1);
    expect((await reopened.books()).single.offset, 2);
    expect((await reopened.notes()).length, 1);
    await reopened.close();
    await dir.delete(recursive: true);
  });
}
