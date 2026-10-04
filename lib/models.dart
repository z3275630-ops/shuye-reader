import 'dart:convert';

const defaultChapterPattern =
    r'^\s*(?:第[零〇一二三四五六七八九十百千万两\d]+[章节卷回部篇].{0,50}|序章|序言|前言|后记|尾声|Chapter\s+\d+.{0,50})\s*$';

class Chapter {
  final String title;
  final String text;
  const Chapter(this.title, this.text);
  Map<String, dynamic> toJson() => {'title': title, 'text': text};
  factory Chapter.fromJson(Map<String, dynamic> j) =>
      Chapter(j['title'] as String, j['text'] as String);
}

class Book {
  final String id, title, author, format;
  final List<Chapter> chapters;
  final String? cover;
  final int added;
  int chapter, offset, lastRead;
  Book({
    required this.id,
    required this.title,
    required this.chapters,
    this.author = '未知作者',
    this.format = 'TXT',
    this.cover,
    int? added,
    this.chapter = 0,
    this.offset = 0,
    this.lastRead = 0,
  }) : added = added ?? DateTime.now().millisecondsSinceEpoch;
  int get words => chapters.fold(0, (n, c) => n + c.text.runes.length);
  double get progress {
    final total = chapters.fold<int>(0, (n, c) => n + c.text.length);
    if (total == 0) return 0;
    final read =
        chapters.take(chapter).fold<int>(0, (n, c) => n + c.text.length) +
        offset;
    return (read / total).clamp(0, 1);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'format': format,
    'cover': cover,
    'added': added,
    'chapter': chapter,
    'offset': offset,
    'lastRead': lastRead,
    'chapters': chapters.map((c) => c.toJson()).toList(),
  };
  factory Book.fromJson(Map<String, dynamic> j) {
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
  Map<String, Object?> toRow() => {
    'id': id,
    'title': title,
    'author': author,
    'format': format,
    'cover': cover,
    'added': added,
    'chapter': chapter,
    'offset': offset,
    'last_read': lastRead,
    'content': jsonEncode(chapters.map((c) => c.toJson()).toList()),
  };
  factory Book.fromRow(Map<String, Object?> r) => Book.fromJson({
    ...r,
    'lastRead': r['last_read'],
    'chapters': jsonDecode(r['content'] as String),
  });
}

class Note {
  final String id, bookId, quote, comment;
  final int chapter, offset, created;
  const Note({
    required this.id,
    required this.bookId,
    required this.chapter,
    required this.offset,
    required this.quote,
    required this.comment,
    required this.created,
  });
  Map<String, Object?> toJson() => {
    'id': id,
    'book_id': bookId,
    'chapter': chapter,
    'offset': offset,
    'quote': quote,
    'comment': comment,
    'created': created,
  };
  factory Note.fromJson(Map<String, dynamic> j) => Note(
    id: j['id'] as String,
    bookId: j['book_id'] as String,
    chapter: j['chapter'] as int,
    offset: j['offset'] as int,
    quote: j['quote'] as String,
    comment: j['comment'] as String,
    created: j['created'] as int,
  );
}

class ReaderSettings {
  double fontSize, lineHeight;
  String theme, font, chapterPattern, purifyLines;
  bool cjkSpacing;
  ReaderSettings({
    this.fontSize = 20,
    this.lineHeight = 1.85,
    this.theme = 'paper',
    this.font = 'serif',
    this.chapterPattern = defaultChapterPattern,
    this.purifyLines = '',
    this.cjkSpacing = true,
  });
  Map<String, dynamic> toJson() => {
    'reader.fontSize': fontSize,
    'reader.lineHeight': lineHeight,
    'reader.theme': theme,
    'reader.font': font,
    'reader.typography.cjkLatinSpacing': cjkSpacing,
    'reader.titleSplitPattern': chapterPattern,
    'reader.purifyLines': purifyLines,
  };
  factory ReaderSettings.fromJson(Map<String, dynamic> j) {
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
