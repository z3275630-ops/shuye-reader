import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

import 'models.dart';
import 'samples.dart';
import 'services.dart';
import 'facets.dart';
import 'reading_time.dart';

class ReaderRepository {
  final Database db;
  ReaderRepository(this.db);
  late final _readingTime = ReadingTimeQueue((bookId, seconds, at) async {
    await db.insert('read_records', {
      'book_id': bookId,
      'day':
          '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}',
      'hour': at.hour,
      'seconds': seconds,
    });
  });
  static Future<ReaderRepository> open({
    String? path,
    DatabaseFactory? factory,
    String? password,
  }) async {
    if (factory == null && path == null && Platform.isAndroid) {
      return _openEncrypted();
    }
    final f = factory ?? databaseFactory;
    final location = path ?? '${await f.getDatabasesPath()}/shuye.db';
    final db = await f.openDatabase(
      location,
      options: cipher.SqlCipherOpenDatabaseOptions(
        password: password,
        version: 3,
        onUpgrade: (db, old, next) async {
          if (old < 2) {
            await db.execute(
              "ALTER TABLE books ADD COLUMN metadata TEXT NOT NULL DEFAULT '{}'",
            );
            await db.execute(
              'CREATE TABLE entries (id TEXT PRIMARY KEY, kind TEXT NOT NULL, book_id TEXT REFERENCES books(id) ON DELETE CASCADE, data TEXT NOT NULL, updated INTEGER NOT NULL)',
            );
            await db.execute(
              'CREATE INDEX entries_kind ON entries(kind, book_id)',
            );
          }
          if (old < 3) {
            await db.execute(
              "ALTER TABLE notes ADD COLUMN tags TEXT NOT NULL DEFAULT ''",
            );
            await db.execute('ALTER TABLE books ADD COLUMN source BLOB');
            await db.execute(
              'ALTER TABLE read_records ADD COLUMN hour INTEGER NOT NULL DEFAULT -1',
            );
            for (final row in await db.query('books')) {
              final metadata =
                  jsonDecode(row['metadata'] as String) as Map<String, dynamic>;
              final binary = metadata.remove('binary') as String?;
              if (binary != null) {
                await db.update(
                  'books',
                  {
                    'metadata': jsonEncode(metadata),
                    'source': base64Decode(binary),
                  },
                  where: 'id = ?',
                  whereArgs: [row['id']],
                );
              }
              final book = Book.fromRow({
                ...row,
                'metadata': jsonEncode(metadata),
                'source': binary == null ? null : base64Decode(binary),
              });
              book.toRow();
              await db.update(
                'books',
                {'metadata': jsonEncode(book.metadata)},
                where: 'id = ?',
                whereArgs: [book.id],
              );
            }
          }
        },
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute(
            "CREATE TABLE books (id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL, format TEXT NOT NULL, cover TEXT, source BLOB, added INTEGER NOT NULL, chapter INTEGER NOT NULL, offset INTEGER NOT NULL, last_read INTEGER NOT NULL, content TEXT NOT NULL, metadata TEXT NOT NULL DEFAULT '{}')",
          );
          await db.execute(
            "CREATE TABLE notes (id TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE, chapter INTEGER NOT NULL, offset INTEGER NOT NULL, quote TEXT NOT NULL, comment TEXT NOT NULL, tags TEXT NOT NULL DEFAULT '', created INTEGER NOT NULL)",
          );
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE read_records (id INTEGER PRIMARY KEY AUTOINCREMENT, book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE, day TEXT NOT NULL, hour INTEGER NOT NULL DEFAULT -1, seconds INTEGER NOT NULL CHECK(seconds >= 0))',
          );
          await db.execute('CREATE INDEX notes_book ON notes(book_id)');
          await db.execute('CREATE INDEX records_day ON read_records(day)');
          await db.execute(
            'CREATE TABLE entries (id TEXT PRIMARY KEY, kind TEXT NOT NULL, book_id TEXT REFERENCES books(id) ON DELETE CASCADE, data TEXT NOT NULL, updated INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE INDEX entries_kind ON entries(kind, book_id)',
          );
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

  static Future<ReaderRepository> _openEncrypted() async {
    final root = await databaseFactory.getDatabasesPath();
    final oldPath = '$root/shuye.db', newPath = '$root/shuye-encrypted.db';
    final secrets = Secrets();
    var key = await secrets.read('_database_key');
    if (key.isEmpty) {
      if (await File(newPath).exists()) throw StateError('无法读取书库密钥，请保留应用数据');
      key = base64UrlEncode(
        List<int>.generate(32, (_) => Random.secure().nextInt(256)),
      );
      await secrets.write('_database_key', key);
    }
    final encrypted = await open(
      path: newPath,
      factory: cipher.databaseFactory,
      password: key,
    );
    final marker = await encrypted.db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['_encrypted_migration_done'],
    );
    if (marker.isEmpty && await File(oldPath).exists()) {
      final old = await open(path: oldPath, factory: databaseFactory);
      var migrationFailed = false;
      try {
        final snapshot = await old.backup();
        // The local library can be larger than a user-picked backup file, so the
        // migration is allowed to skip the interactive size limit.
        await encrypted.restore(snapshot, internal: true);
        final before = jsonDecode(snapshot) as Map<String, dynamic>;
        final after =
            jsonDecode(await encrypted.backup()) as Map<String, dynamic>;
        // Compare every persisted table, ignoring only generated record IDs.
        Object? canonical(dynamic value) {
          if (value is Map) {
            final keys = value.keys.map((k) => k.toString()).toList()..sort();
            return {for (final k in keys) k: canonical(value[k])};
          }
          if (value is List) {
            final rows = value.map(canonical).toList();
            rows.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
            return rows;
          }
          return value;
        }

        for (final data in [before, after]) {
          for (final r in data['records'] as List) {
            (r as Map).remove('id');
          }
        }
        if (['books', 'notes', 'settings', 'records', 'entries'].any(
          (table) =>
              jsonEncode(canonical(before[table])) !=
              jsonEncode(canonical(after[table])),
        )) {
          throw StateError('升级核验失败，原书库已保留');
        }
        // Keep a recoverable encrypted snapshot before removing the plain database.
        await File(
          '$root/shuye-migration-recovery.json',
        ).writeAsString(await BackupCipher.encrypt(snapshot, key), flush: true);
        await encrypted.db.insert('settings', {
          'key': '_encrypted_migration_done',
          'value': 'true',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      } on FormatException {
        // Migration data itself was rejected, for example a snapshot beyond the
        // size limit; fall back to the plain database below.
        migrationFailed = true;
      } on StateError {
        // Upgrade verification failed; fall back to the plain database below.
        migrationFailed = true;
      } finally {
        await old.close();
      }
      if (migrationFailed) {
        // Keep the app usable instead of failing startup: reopen the plain
        // database, leave the migration marker unwritten and the plain file in
        // place, so the next launch retries the migration. Failures of the
        // encrypted database itself are not caught here.
        return open(path: oldPath, factory: databaseFactory);
      }
      await databaseFactory.deleteDatabase(oldPath);
    } else if (marker.isEmpty) {
      await encrypted.db.insert('settings', {
        'key': '_encrypted_migration_done',
        'value': 'true',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return encrypted;
  }

  Future<List<Book>> books({bool summaries = false}) async => (await db.query(
    'books',
    columns: summaries
        ? [
            'id',
            'title',
            'author',
            'format',
            'cover',
            'added',
            'chapter',
            'offset',
            'last_read',
            'metadata',
          ]
        : null,
    orderBy: 'last_read DESC, added DESC',
  )).map(summaries ? Book.fromSummary : Book.fromRow).toList();
  Future<Book> book(String id) async => Book.fromRow(
    (await db.query('books', where: 'id = ?', whereArgs: [id])).single,
  );
  // Search reads only chapter text, never PDF source or comic page images.
  Future<({List<Map<String, dynamic>> matches, bool truncated})> searchText(
    String query, {
    int limit = 100,
    Duration budget = const Duration(seconds: 5),
    bool Function()? isCancelled,
  }) async {
    if (query.isEmpty || query.length > 100 || limit < 1 || limit > 100) {
      throw const FormatException('查询长度 1–100，结果上限 1–100');
    }
    final watch = Stopwatch()..start();
    final matches = <Map<String, dynamic>>[];
    final rows = await db.query(
      'books',
      columns: ['id', 'title'],
      where: 'format NOT IN (?, ?)',
      whereArgs: ['PDF', 'CBZ'],
      orderBy: 'last_read DESC, added DESC',
    );
    for (final row in rows) {
      if (watch.elapsed >= budget || (isCancelled?.call() ?? false)) {
        return (matches: matches, truncated: true);
      }
      final content =
          (await db.query(
                'books',
                columns: ['content'],
                where: 'id = ?',
                whereArgs: [row['id']],
              )).firstOrNull?['content']
              as String?;
      if (content == null) continue;
      final chapters = jsonDecode(content) as List;
      for (var i = 0; i < chapters.length; i++) {
        final text = (chapters[i] as Map)['text'] as String;
        var from = 0;
        while (from < text.length) {
          final at = text.indexOf(query, from);
          if (at < 0) break;
          matches.add({
            'book': row['title'],
            'chapter': i,
            'offset': at,
            'excerpt': text.substring(
              max(0, at - 40),
              min(text.length, at + query.length + 80),
            ),
          });
          if (matches.length >= limit) {
            return (matches: matches, truncated: true);
          }
          from = at + query.length;
        }
        await Future<void>.delayed(Duration.zero);
        if (watch.elapsed >= budget || (isCancelled?.call() ?? false)) {
          return (matches: matches, truncated: true);
        }
      }
    }
    return (matches: matches, truncated: false);
  }

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
  Future<void> deleteBook(String id) async {
    await _readingTime.flush();
    await db.delete('books', where: 'id = ?', whereArgs: [id]);
  }

  Future<String> proposeBookUpdate(
    String bookId,
    Map<String, dynamic> changes,
  ) async {
    validateBookChanges(changes);
    final b = await book(bookId);
    final before = {
      for (final key in changes.keys)
        key: key == 'title'
            ? b.title
            : key == 'author'
            ? b.author
            : b.metadata[key],
    };
    final id = 'proposal-${DateTime.now().microsecondsSinceEpoch}';
    await putEntry(
      'bookProposals',
      {
        'title': b.title,
        'before': before,
        'changes': changes,
        'status': 'pending',
      },
      bookId: bookId,
      id: id,
    );
    return id;
  }

  static void validateBookChanges(Map<String, dynamic> changes) {
    const allowed = {
      'title',
      'author',
      'category',
      'tags',
      'list',
      'rating',
      'review',
    };
    if (changes.isEmpty || changes.keys.any((k) => !allowed.contains(k))) {
      throw const FormatException('修改建议仅支持书名、作者、分类、标签、书单、评分和书评');
    }
    for (final e in changes.entries) {
      if (e.key == 'rating') {
        if (e.value is! num ||
            !(e.value as num).isFinite ||
            (e.value as num) < 0 ||
            (e.value as num) > 5) {
          throw const FormatException('评分范围为 0–5');
        }
      } else if (e.value is! String ||
          (e.value as String).length > 4000 ||
          (['title', 'author'].contains(e.key) &&
              (e.value as String).trim().isEmpty)) {
        throw const FormatException('修改建议文字无效');
      }
    }
  }

  Future<void> applyBookProposal(String id) async => db.transaction((
    txn,
  ) async {
    final row = (await txn.query(
      'entries',
      where: 'id = ? AND kind = ?',
      whereArgs: [id, 'bookProposals'],
    )).single;
    final data = Map<String, dynamic>.from(
      jsonDecode(row['data'] as String) as Map,
    );
    if (data['status'] != 'pending') throw StateError('这条建议已处理');
    final b = Book.fromRow(
      (await txn.query(
        'books',
        where: 'id = ?',
        whereArgs: [row['book_id']],
      )).single,
    );
    final changes = Map<String, dynamic>.from(data['changes'] as Map);
    validateBookChanges(changes);
    final before = Map<String, dynamic>.from(data['before'] as Map);
    if (before.keys.toSet().difference(changes.keys.toSet()).isNotEmpty ||
        changes.keys.toSet().difference(before.keys.toSet()).isNotEmpty) {
      throw const FormatException('建议核验数据不完整');
    }
    for (final e in before.entries) {
      final current = e.key == 'title'
          ? b.title
          : e.key == 'author'
          ? b.author
          : b.metadata[e.key];
      if (current != e.value) throw StateError('该书资料已更新，请重新生成建议，避免覆盖新修改');
    }
    for (final e in changes.entries) {
      if (e.key == 'title') {
        b.title = e.value as String;
      } else if (e.key == 'author') {
        b.author = e.value as String;
      } else if ([
        'category',
        'tags',
        'list',
        'rating',
        'review',
      ].contains(e.key)) {
        b.metadata[e.key] = e.value;
      } else {
        throw const FormatException('建议含有不支持的字段');
      }
    }
    await txn.update('books', b.toRow(), where: 'id = ?', whereArgs: [b.id]);
    data['status'] = 'applied';
    await txn.update(
      'entries',
      {'data': jsonEncode(data)},
      where: 'id = ?',
      whereArgs: [id],
    );
  });
  Future<void> updateBook(Book b) async =>
      db.update('books', b.toRow(), where: 'id = ?', whereArgs: [b.id]);
  Future<void> editChapter(Book b, int index, Chapter replacement) async {
    final updated = Book.fromJson(b.toJson());
    updated.chapters[index] = replacement;
    if (updated.chapter == index) {
      updated.offset = updated.offset.clamp(0, replacement.text.length);
    }
    await db.transaction((txn) async {
      await txn.update(
        'books',
        updated.toRow(),
        where: 'id = ?',
        whereArgs: [b.id],
      );
      final rows = await txn.query(
        'notes',
        where: 'book_id = ? AND chapter = ?',
        whereArgs: [b.id, index],
      );
      for (final row in rows) {
        // Keep quotations intact; relocate their anchor when an edit moved the text.
        final quote = row['quote'] as String;
        final found = quote.isEmpty ? -1 : replacement.text.indexOf(quote);
        final offset = found >= 0
            ? found
            : (row['offset'] as int).clamp(0, replacement.text.length);
        await txn.update(
          'notes',
          {'offset': offset},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    });
    b.chapters = updated.chapters;
    b.offset = updated.offset;
    b.metadata = updated.metadata;
  }

  Future<void> saveMetadata(Book b) async => db.update(
    'books',
    {'metadata': jsonEncode(b.metadata), 'last_read': b.lastRead},
    where: 'id = ?',
    whereArgs: [b.id],
  );
  Future<List<Map<String, dynamic>>> entries(
    String kind, {
    String? bookId,
  }) async =>
      (await db.query(
            'entries',
            where: bookId == null ? 'kind = ?' : 'kind = ? AND book_id = ?',
            whereArgs: [kind, ?bookId],
            orderBy: 'updated DESC',
          ))
          .map(
            (r) => {
              'id': r['id'],
              'book_id': r['book_id'],
              ...Map<String, dynamic>.from(
                jsonDecode(r['data'] as String) as Map,
              ),
            },
          )
          .toList();
  Future<void> putEntry(
    String kind,
    Map<String, dynamic> data, {
    String? bookId,
    String? id,
  }) async => db.insert('entries', {
    'id': id ?? DateTime.now().microsecondsSinceEpoch.toString(),
    'kind': kind,
    'book_id': bookId,
    'data': jsonEncode(data),
    'updated': DateTime.now().millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> removeEntry(String id) async =>
      db.delete('entries', where: 'id = ?', whereArgs: [id]);
  Future<List<Note>> notes() async => (await db.query(
    'notes',
    orderBy: 'created DESC',
  )).map((r) => Note.fromJson(Map<String, dynamic>.from(r))).toList();
  Future<void> addNote(Note n) async => db.insert('notes', n.toJson());
  Future<void> updateNote(Note n) async =>
      db.update('notes', n.toJson(), where: 'id = ?', whereArgs: [n.id]);
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
  Future<void> record(String bookId, int seconds, {DateTime? at}) async {
    await _readingTime.record(bookId, seconds, at ?? DateTime.now());
  }

  Future<Map<String, int>> statistics() async => {
    for (final r in await db.rawQuery(
      'SELECT day, SUM(seconds) AS seconds FROM read_records GROUP BY day',
    ))
      r['day'] as String: r['seconds'] as int,
  };
  Future<Map<int, int>> hourlyStatistics() async => {
    for (final r in await db.rawQuery(
      'SELECT hour, SUM(seconds) AS seconds FROM read_records WHERE hour >= 0 GROUP BY hour',
    ))
      r['hour'] as int: r['seconds'] as int,
  };
  Future<String> backup() async {
    // One transaction gives a consistent snapshot of books + notes + progress.
    return db.transaction(
      (txn) async => jsonEncode({
        'app': 'shuye-reader',
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'books': (await txn.query('books'))
            .map(Book.fromRow)
            .map((b) => b.toJson())
            .toList(),
        'notes': await txn.query('notes'),
        'settings': await txn.query('settings'),
        'records': await txn.query('read_records'),
        'entries': await txn.query('entries'),
      }),
    );
  }

  // [internal] is only for the SQLCipher migration, which moves the whole local
  // library rather than a user-picked file, so it skips the size limit below.
  // Every other caller keeps the default and behaves exactly as before.
  Future<void> restore(String data, {bool internal = false}) async {
    // Measured in UTF-8 bytes to match the byte-based file checks in the UI
    // (main.dart, workbench.dart). This is stricter than the previous UTF-16
    // code-unit count for non-ASCII payloads, so it can reject earlier.
    // Internal callers skip the check and never pay the encoding cost.
    if (!internal && utf8.encode(data).length > 80 * 1024 * 1024) {
      throw const FormatException('备份超过 80 MB');
    }
    final j = jsonDecode(data) as Map<String, dynamic>;
    if (j['app'] != 'shuye-reader' || ![1, 2].contains(j['version'])) {
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
          (r['hour'] != null &&
              (r['hour'] is! int ||
                  (r['hour'] as int) < -1 ||
                  (r['hour'] as int) > 23)) ||
          r['seconds'] is! int ||
          (r['seconds'] as int) < 0 ||
          r['day'] is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(r['day'] as String)) {
        throw const FormatException('阅读记录无效');
      }
    }
    final entries = (j['entries'] as List? ?? [])
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    for (final e in entries) {
      if (e['id'] is! String ||
          e['kind'] is! String ||
          e['data'] is! String ||
          e['updated'] is! int ||
          (e['book_id'] != null && !ids.contains(e['book_id'])) ||
          jsonDecode(e['data'] as String) is! Map) {
        throw const FormatException('扩展数据无效');
      }
    }
    await db.transaction((txn) async {
      await txn.delete('entries');
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
          'hour': r['hour'] as int? ?? -1,
          'day': r['day'],
          'seconds': r['seconds'],
        });
      }
      for (final e in entries) {
        await txn.insert('entries', e);
      }
    });
  }

  Future<void> assignFacet(
    String field,
    String name,
    List<String> bookIds,
  ) async {
    name = name.trim();
    validateFacet(field, name);
    if (name.isEmpty) throw const FormatException('名称不能为空');
    await db.transaction((txn) async {
      for (final id in bookIds.toSet()) {
        final rows = await txn.query(
          'books',
          columns: ['author', 'metadata'],
          where: 'id = ?',
          whereArgs: [id],
        );
        if (rows.isEmpty) throw const FormatException('书籍已不存在，请刷新后重试');
        final meta = Map<String, dynamic>.from(
          jsonDecode(rows.single['metadata'] as String),
        );
        if (field == 'tags') {
          meta[field] = ({
            ...splitTags(meta[field] as String? ?? ''),
            name,
          }).join(', ');
        } else if (field != 'author') {
          meta[field] = name;
        }
        await txn.update(
          'books',
          field == 'author' ? {'author': name} : {'metadata': jsonEncode(meta)},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  Future<void> renameFacet(String field, String oldName, String newName) async {
    newName = newName.trim();
    validateFacet(field, oldName);
    validateFacet(field, newName);
    if (oldName.isEmpty) throw const FormatException('不能重命名未设置分组');
    await db.transaction((txn) async {
      final rows = await txn.query(
        'books',
        columns: ['id', 'author', 'metadata'],
      );
      for (final row in rows) {
        final meta = Map<String, dynamic>.from(
          jsonDecode(row['metadata'] as String),
        );
        final value = field == 'author'
            ? row['author'] as String
            : meta[field] as String? ?? '';
        if (field == 'tags') {
          final tags = splitTags(value);
          if (!tags.contains(oldName)) continue;
          meta[field] = tags
              .map((t) => t == oldName ? newName : t)
              .where((t) => t.isNotEmpty)
              .toSet()
              .join(', ');
        } else {
          if (value.trim() != oldName) continue;
          if (field != 'author') meta[field] = newName;
        }
        await txn.update(
          'books',
          field == 'author'
              ? {'author': newName}
              : {'metadata': jsonEncode(meta)},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      for (final row in await txn.query(
        'entries',
        where: 'kind = ?',
        whereArgs: ['facets'],
      )) {
        final data = Map<String, dynamic>.from(
          jsonDecode(row['data'] as String),
        );
        if (data['field'] == field && data['name'] == oldName) {
          if (newName.isEmpty) {
            await txn.delete(
              'entries',
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          } else {
            data['name'] = newName;
            await txn.update(
              'entries',
              {
                'data': jsonEncode(data),
                'updated': DateTime.now().millisecondsSinceEpoch,
              },
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          }
        }
      }
    });
  }

  Future<void> close() => db.close();
}
