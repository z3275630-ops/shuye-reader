import 'dart:convert';

const defaultChapterPattern =
    r'^\s*(?:第[零〇一二三四五六七八九十百千万两\d]+[章节卷回部篇].{0,50}|序章|序言|前言|后记|尾声|Chapter\s+\d+.{0,50})\s*$';

class Chapter {
  final String title;
  final String text;
  final List<String> images;
  const Chapter(this.title, this.text, {this.images = const []});
  Map<String, dynamic> toJson() => {
    'title': title,
    'text': text,
    'images': images,
  };
  factory Chapter.fromJson(Map<String, dynamic> j) => Chapter(
    j['title'] as String,
    j['text'] as String,
    images: List<String>.from(j['images'] as List? ?? []),
  );
}

class Book {
  final String id, format;
  String title, author;
  List<Chapter> chapters;
  String? cover;
  String? source;
  Map<String, dynamic> metadata;
  final bool isSummary;
  final int added;
  int chapter, offset, lastRead;
  Book({
    required this.id,
    required this.title,
    required this.chapters,
    this.author = '未知作者',
    this.format = 'TXT',
    this.cover,
    this.source,
    Map<String, dynamic>? metadata,
    this.isSummary = false,
    int? added,
    this.chapter = 0,
    this.offset = 0,
    this.lastRead = 0,
  }) : metadata = metadata ?? {},
       added = added ?? DateTime.now().millisecondsSinceEpoch;
  int get words => isSummary
      ? metadata['_words'] as int? ?? 0
      : chapters.fold(0, (n, c) => n + c.text.runes.length);
  double get progress {
    if (format == 'PDF') {
      final count = metadata['pdfPages'] as int? ?? 0;
      return count <= 1
          ? 0
          : (((metadata['pdfPage'] as int? ?? 1) - 1) / (count - 1)).clamp(
              0,
              1,
            );
    }
    final lengths = isSummary
        ? List<int>.from(metadata['_lengths'] as List? ?? [])
        : chapters.map((c) => c.text.length).toList();
    final total = lengths.fold<int>(0, (n, c) => n + c);
    if (total == 0) return 0;
    final read = lengths.take(chapter).fold<int>(0, (n, c) => n + c) + offset;
    return (read / total).clamp(0, 1);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'format': format,
    'cover': cover,
    'source': source,
    'metadata': metadata,
    'added': added,
    'chapter': chapter,
    'offset': offset,
    'lastRead': lastRead,
    'chapters': chapters.map((c) => c.toJson()).toList(),
  };
  factory Book.fromJson(Map<String, dynamic> j) {
    final metadata = Map<String, dynamic>.from(j['metadata'] as Map? ?? {});
    final source =
        j['source'] as String? ?? metadata.remove('binary') as String?;
    final chapters = (j['chapters'] as List)
        .map((c) => Chapter.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList();
    if (chapters.isEmpty ||
        chapters.length > 10000 ||
        chapters.any((c) => c.text.isEmpty)) {
      throw const FormatException('备份中存在无效章节');
    }
    final chapter = (j['chapter'] as int? ?? 0).clamp(0, chapters.length - 1);
    return Book(
      id: j['id'] as String,
      title: j['title'] as String,
      author: j['author'] as String? ?? '未知作者',
      format: j['format'] as String? ?? 'TXT',
      cover: j['cover'] as String?,
      source: source,
      metadata: metadata,
      added: j['added'] as int?,
      chapter: chapter,
      offset: (j['offset'] as int? ?? 0).clamp(
        0,
        chapters[chapter].text.length,
      ),
      lastRead: j['lastRead'] as int? ?? 0,
      chapters: chapters,
    );
  }
  Map<String, Object?> toRow() {
    if (isSummary) throw StateError('请先加载书籍正文再修改');
    metadata.addAll({
      '_words': words,
      '_titles': chapters.map((c) => c.title).toList(),
      '_lengths': chapters.map((c) => c.text.length).toList(),
    });
    return {
      'id': id,
      'title': title,
      'author': author,
      'format': format,
      'cover': cover,
      'source': source == null ? null : base64Decode(source!),
      'metadata': jsonEncode(metadata),
      'added': added,
      'chapter': chapter,
      'offset': offset,
      'last_read': lastRead,
      'content': jsonEncode(chapters.map((c) => c.toJson()).toList()),
    };
  }

  factory Book.fromRow(Map<String, Object?> r) => Book.fromJson({
    ...r,
    'source': r['source'] == null
        ? null
        : base64Encode(r['source'] as List<int>),
    'metadata': jsonDecode(r['metadata'] as String? ?? '{}'),
    'lastRead': r['last_read'],
    'chapters': jsonDecode(r['content'] as String),
  });
  factory Book.fromSummary(Map<String, Object?> r) {
    final metadata = Map<String, dynamic>.from(
      jsonDecode(r['metadata'] as String) as Map,
    );
    return Book(
      id: r['id'] as String,
      title: r['title'] as String,
      author: r['author'] as String,
      format: r['format'] as String,
      cover: r['cover'] as String?,
      added: r['added'] as int,
      chapter: r['chapter'] as int,
      offset: r['offset'] as int,
      lastRead: r['last_read'] as int,
      metadata: metadata,
      isSummary: true,
      chapters: [
        for (final title in metadata['_titles'] as List? ?? ['正文'])
          Chapter(title as String, ' '),
      ],
    );
  }
}

class Note {
  final String id, bookId, quote, comment;
  final String tags;
  final int chapter, offset, created;
  const Note({
    required this.id,
    required this.bookId,
    required this.chapter,
    required this.offset,
    required this.quote,
    required this.comment,
    required this.created,
    this.tags = '',
  });
  Map<String, Object?> toJson() => {
    'id': id,
    'book_id': bookId,
    'chapter': chapter,
    'offset': offset,
    'quote': quote,
    'comment': comment,
    'created': created,
    'tags': tags,
  };
  factory Note.fromJson(Map<String, dynamic> j) => Note(
    id: j['id'] as String,
    bookId: j['book_id'] as String,
    chapter: j['chapter'] as int,
    offset: j['offset'] as int,
    quote: j['quote'] as String,
    comment: j['comment'] as String,
    created: j['created'] as int,
    tags: j['tags'] as String? ?? '',
  );
}

class ReaderSettings {
  double fontSize, lineHeight;
  String theme, font, chapterPattern, purifyLines;
  bool cjkSpacing;
  final Map<String, dynamic> extra;
  bool flag(String key, [bool fallback = false]) =>
      extra[key] as bool? ?? fallback;
  double number(String key, double fallback) =>
      (extra[key] as num? ?? fallback).toDouble();
  String value(String key, String fallback) =>
      extra[key] as String? ?? fallback;
  ReaderSettings({
    this.fontSize = 20,
    this.lineHeight = 1.85,
    this.theme = 'paper',
    this.font = 'serif',
    this.chapterPattern = defaultChapterPattern,
    this.purifyLines = '',
    this.cjkSpacing = true,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};
  Map<String, dynamic> toJson() => {
    ...extra,
    'reader.fontSize': fontSize,
    'reader.lineHeight': lineHeight,
    'reader.theme': theme,
    'reader.font': font,
    'reader.typography.cjkLatinSpacing': cjkSpacing,
    'reader.titleSplitPattern': chapterPattern,
    'reader.purifyLines': purifyLines,
  };
  factory ReaderSettings.fromJson(Map<String, dynamic> j) {
    const booleanKeys = {
      'reader.keepOn',
      'reader.volumeKeys',
      'reader.physicalKeys',
      'reader.sound',
      'reader.oneHand',
      'reader.tapPages',
      'reader.doublePage',
      'reader.eink',
      'reader.ignoreBlank',
      'reader.bionic',
      'reader.hyphenation',
      'reader.punctuation',
      'reader.nightSchedule',
      'reader.typography.cjkLatinSpacing',
      'bookshelf.banner',
      'privacy.lock',
    };
    const numberKeys = {
      'reader.fontSize',
      'reader.lineHeight',
      'reader.autoInterval',
      'reader.charsPerSecond',
      'reader.brightness',
      'reader.margin',
      'reader.reminderMinutes',
      'reader.speechRate',
      'bookshelf.columns',
      'bookshelf.gap',
      'bookshelf.cardHeight',
      'stats.goalMinutes',
    };
    for (final e in j.entries) {
      if ((booleanKeys.contains(e.key) && e.value is! bool) ||
          (numberKeys.contains(e.key) &&
              (e.value is! num || !(e.value as num).isFinite))) {
        throw const FormatException('设置数据类型无效');
      }
      if (!booleanKeys.contains(e.key) &&
          !numberKeys.contains(e.key) &&
          e.value is! String) {
        throw const FormatException('设置数据类型无效');
      }
    }
    final s = ReaderSettings(
      fontSize: (j['reader.fontSize'] as num? ?? 20).toDouble().clamp(14, 32),
      lineHeight: (j['reader.lineHeight'] as num? ?? 1.85).toDouble().clamp(
        1.3,
        2.4,
      ),
      theme: j['reader.theme'] as String? ?? 'paper',
      font: j['reader.font'] as String? ?? 'serif',
      cjkSpacing: j['reader.typography.cjkLatinSpacing'] as bool? ?? true,
      chapterPattern:
          j['reader.titleSplitPattern'] as String? ?? defaultChapterPattern,
      purifyLines: j['reader.purifyLines'] as String? ?? '',
      extra: Map<String, dynamic>.from(j),
    );
    validateRules(s.chapterPattern, s.purifyLines);
    if (!['paper', 'white', 'sage', 'night'].contains(s.theme)) {
      s.theme = 'paper';
    }
    if (!['serif', 'sans'].contains(s.font)) s.font = 'serif';
    return s;
  }
}

// Keep regular expressions line-scoped; Dart's backtracking regex engine has no
// timeout, so intentionally reject complex expressions rather than freezing UI.
void validateRules(String chapterPattern, String purifyLines) {
  if (chapterPattern.isEmpty || chapterPattern.length > 300) {
    throw const FormatException('分章规则长度需为 1–300 个字符');
  }
  for (final pattern in [
    chapterPattern,
    ...purifyLines.split('\n').where((s) => s.trim().isNotEmpty),
  ]) {
    if (pattern.length > 300 ||
        (pattern != defaultChapterPattern &&
            (pattern.contains('(') || pattern.contains(')'))) ||
        RegExp(r'\([^)]*[+*][^)]*\)[+*{]').hasMatch(pattern)) {
      throw const FormatException('请使用简单规则，避免嵌套重复或回溯表达式');
    }
    RegExp(pattern);
  }
  if (purifyLines.split('\n').length > 30) {
    throw const FormatException('净化规则最多 30 行');
  }
}
