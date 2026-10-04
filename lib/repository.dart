import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'samples.dart';

class ReaderRepository {
  final Database db;
  ReaderRepository(this.db);
  static Future<ReaderRepository> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    final f = factory ?? databaseFactory;
    final location = path ?? '${await f.getDatabasesPath()}/shuye.db';
    final db = await f.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE books (id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL, format TEXT NOT NULL, cover TEXT, added INTEGER NOT NULL, chapter INTEGER NOT NULL, offset INTEGER NOT NULL, last_read INTEGER NOT NULL, content TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE notes (id TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE, chapter INTEGER NOT NULL, offset INTEGER NOT NULL, quote TEXT NOT NULL, comment TEXT NOT NULL, created INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE read_records (id INTEGER PRIMARY KEY AUTOINCREMENT, book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE, day TEXT NOT NULL, seconds INTEGER NOT NULL CHECK(seconds >= 0))',
          );
          await db.execute('CREATE INDEX notes_book ON notes(book_id)');
          await db.execute('CREATE INDEX records_day ON read_records(day)');
        },
      ),
    );
    final repo = ReaderRepository(db);
    if ((await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['_migration_seed_v1_completed'],
    )).isEmpty) {
      await db.transaction((txn) async {
        for (final b in sampleBooks()) {
          await txn.insert(
            'books',
            b.toRow(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await txn.insert('settings', {
          'key': '_migration_seed_v1_completed',
          'value': 'true',
        });
      });
    }
    return repo;
  }

  Future<List<Book>> books() async => (await db.query(
    'books',
    orderBy: 'last_read DESC, added DESC',
  )).map(Book.fromRow).toList();
  Future<bool> addBook(Book b) async {
    if ((await db.query(
      'books',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [b.id],
    )).isNotEmpty) {
      return false;
    }
    await db.insert('books', b.toRow());
    return true;
  }

  Future<void> saveProgress(Book b) async => db.update(
    'books',
    {'chapter': b.chapter, 'offset': b.offset, 'last_read': b.lastRead},
    where: 'id = ?',
    whereArgs: [b.id],
  );
  Future<void> deleteBook(String id) async =>
      db.delete('books', where: 'id = ?', whereArgs: [id]);
  Future<List<Note>> notes() async => (await db.query(
    'notes',
    orderBy: 'created DESC',
  )).map((r) => Note.fromJson(Map<String, dynamic>.from(r))).toList();
  Future<void> addNote(Note n) async => db.insert('notes', n.toJson());
  Future<void> deleteNote(String id) async =>
      db.delete('notes', where: 'id = ?', whereArgs: [id]);
  Future<ReaderSettings> settings() async {
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['reader.config'],
    );
    return rows.isEmpty
        ? ReaderSettings()
        : ReaderSettings.fromJson(jsonDecode(rows.first['value'] as String));
  }

  Future<void> saveSettings(ReaderSettings s) async => db.insert('settings', {
    'key': 'reader.config',
    'value': jsonEncode(s.toJson()),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> record(String bookId, int seconds) async {
    if (seconds < 5) return;
    final now = DateTime.now();
    final day =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await db.insert('read_records', {
      'book_id': bookId,
      'day': day,
      'seconds': seconds,
    });
  }

  Future<Map<String, int>> statistics() async => {
    for (final r in await db.rawQuery(
      'SELECT day, SUM(seconds) AS seconds FROM read_records GROUP BY day',
    ))
      r['day'] as String: r['seconds'] as int,
  };
  Future<String> backup() async {
    // One transaction gives a consistent snapshot of books + notes + progress.
    return db.transaction(
      (txn) async => jsonEncode({
        'app': 'shuye-reader',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'books': (await txn.query('books'))
            .map(Book.fromRow)
            .map((b) => b.toJson())
            .toList(),
        'notes': await txn.query('notes'),
        'settings': await txn.query('settings'),
        'records': await txn.query('read_records'),
      }),
    );
  }

  Future<void> restore(String data) async {
    if (data.length > 80 * 1024 * 1024) {
      throw const FormatException('备份超过 80 MB');
    }
    final j = jsonDecode(data) as Map<String, dynamic>;
    if (j['app'] != 'shuye-reader' || j['version'] != 1) {
      throw const FormatException('不是受支持的书叶备份');
    }
    final books = (j['books'] as List)
        .map((b) => Book.fromJson(Map<String, dynamic>.from(b as Map)))
        .toList();
    final ids = books.map((b) => b.id).toSet();
    if (ids.length != books.length) throw const FormatException('备份中存在重复书籍');
    final notes = (j['notes'] as List)
        .map((n) => Note.fromJson(Map<String, dynamic>.from(n as Map)))
        .toList();
    for (final n in notes) {
      final b = books.where((b) => b.id == n.bookId).firstOrNull;
      if (b == null ||
          n.chapter < 0 ||
          n.chapter >= b.chapters.length ||
          n.offset < 0 ||
          n.offset > b.chapters[n.chapter].text.length) {
        throw const FormatException('备份笔记位置无效');
      }
    }
    final settings = (j['settings'] as List)
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();
    for (final s in settings) {
      if (s['key'] is! String || s['value'] is! String) {
        throw const FormatException('设置数据无效');
      }
      if (s['key'] == 'reader.config') {
        ReaderSettings.fromJson(jsonDecode(s['value'] as String));
      }
    }
    final records = (j['records'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    for (final r in records) {
      if (!ids.contains(r['book_id']) ||
          r['seconds'] is! int ||
          (r['seconds'] as int) < 0 ||
          r['day'] is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(r['day'] as String)) {
        throw const FormatException('阅读记录无效');
      }
    }
    await db.transaction((txn) async {
      await txn.delete('read_records');
      await txn.delete('notes');
      await txn.delete('books');
      await txn.delete('settings');
      for (final b in books) {
        await txn.insert('books', b.toRow());
      }
      for (final n in notes) {
        await txn.insert('notes', n.toJson());
      }
      for (final s in settings) {
        await txn.insert('settings', {'key': s['key'], 'value': s['value']});
      }
      await txn.insert('settings', {
        'key': '_migration_seed_v1_completed',
        'value': 'true',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      for (final r in records) {
        await txn.insert('read_records', {
          'book_id': r['book_id'],
          'day': r['day'],
          'seconds': r['seconds'],
        });
      }
    });
  }

  Future<void> close() => db.close();
}
