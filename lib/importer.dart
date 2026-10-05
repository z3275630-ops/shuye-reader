import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'models.dart';

const maxImportBytes = 20 * 1024 * 1024;

Book parseBook(Map<String, dynamic> request) {
  final book = _parseBook(request);
  book.metadata['originalName'] = p.basename(request['name'] as String);
  return book;
}

Book _parseBook(Map<String, dynamic> request) {
  final bytes = request['bytes'] as Uint8List;
  final name = request['name'] as String;
  final pattern = request['pattern'] as String? ?? defaultChapterPattern;
  if (bytes.isEmpty || bytes.length > maxImportBytes) {
    throw const FormatException('文件为空或超过 20 MB');
  }
  final id = sha256.convert(bytes).toString();
  final title = p.basenameWithoutExtension(name);
  switch (p.extension(name).toLowerCase()) {
    case '.txt':
      return Book(
        id: id,
        title: title,
        chapters: splitChapters(decodeText(bytes), pattern),
      );
    case '.epub':
      return _parseEpub(bytes, id, title);
    case '.pdf':
      if (!ascii
          .decode(bytes.take(5).toList(), allowInvalid: true)
          .startsWith('%PDF-')) {
        throw const FormatException('PDF 文件头无效');
      }
      return Book(
        id: id,
        title: title,
        format: 'PDF',
        chapters: const [Chapter('PDF 原版', '请使用原版阅读；可提取文字重排。')],
        source: base64Encode(bytes),
      );
    case '.md':
    case '.markdown':
      final text = decodeText(bytes)
          .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
          .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
          .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!);
      return Book(
        id: id,
        title: title,
        format: 'MD',
        chapters: splitChapters(text, pattern),
      );
    case '.html':
    case '.htm':
      final doc = html.parse(decodeText(bytes));
      return Book(
        id: id,
        title: doc.querySelector('title')?.text ?? title,
        format: 'HTML',
        chapters: splitChapters(htmlText(doc), pattern),
      );
    case '.docx':
      final zip = checkedZip(bytes);
      final doc = zip.findFile('word/document.xml');
      if (doc == null) throw const FormatException('DOCX 缺少正文');
      final xml = XmlDocument.parse(utf8.decode(doc.content));
      final text = xml.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'p')
          .map(
            (p) => p.descendants
                .whereType<XmlElement>()
                .where((e) => e.name.local == 't')
                .map((e) => e.innerText)
                .join(),
          )
          .join('\n\n');
      return Book(
        id: id,
        title: title,
        format: 'DOCX',
        chapters: splitChapters(text, pattern),
      );
    case '.rtf':
      var text = decodeText(bytes);
      text = text.replaceAllMapped(
        RegExp(r'\\u(-?\d+)\??'),
        (m) => String.fromCharCode(int.parse(m[1]!) & 0xffff),
      );
      text = text
          .replaceAllMapped(
            RegExp(r"\\'([0-9a-fA-F]{2})"),
            (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
          )
          .replaceAll(RegExp(r'\\(?:par|line)\b\s?'), '\n')
          .replaceAll(RegExp(r'\\[a-zA-Z]+-?\d*\s?'), '')
          .replaceAll(RegExp('[{}]'), '');
      return Book(
        id: id,
        title: title,
        format: 'RTF',
        chapters: splitChapters(text, pattern),
      );
    case '.cbz':
      final images =
          checkedZip(bytes)
              .where(
                (f) =>
                    f.isFile &&
                    RegExp(
                      r'\.(png|jpe?g|webp)$',
                      caseSensitive: false,
                    ).hasMatch(f.name),
              )
              .toList()
            ..sort((a, b) => naturalCompare(a.name, b.name));
      if (images.isEmpty) throw const FormatException('漫画压缩包中没有图片');
      return Book(
        id: id,
        title: title,
        format: 'CBZ',
        cover: base64Encode(images.first.content),
        chapters: [
          for (var i = 0; i < images.length; i++)
            Chapter(
              '第 ${i + 1} 页',
              '第 ${i + 1} 页',
              images: [base64Encode(images[i].content)],
            ),
        ],
      );
    case '.mobi':
    case '.azw':
    case '.azw3':
      return Book(
        id: id,
        title: title,
        format: 'MOBI',
        chapters: splitChapters(decodePalmDoc(bytes), pattern),
      );
    default:
      throw const FormatException(
        '格式不支持；旧 DOC、RAR/CBR、DRM 或 HUFF/CDIC Kindle 请先转换为 EPUB、DOCX 或 CBZ',
      );
  }
}

Archive checkedZip(Uint8List bytes) {
  const maxTotal = 60 * 1024 * 1024;
  final zip = ZipDecoder().decodeBytes(bytes, verify: true);
  if (zip.length > 4000 || zip.fold<int>(0, (n, f) => n + f.size) > maxTotal) {
    throw const FormatException('压缩包内容过大');
  }
  // The sizes above come from the ZIP central directory, which the file author
  // can forge, and this archive version never verifies CRCs on decode. Inflate
  // every entry into a budgeted sink and count the bytes that really come out.
  // The budget is the remaining archive total, not the per-file limit, so a
  // single oversized file still reaches the per-book failure list that
  // decodeArchive builds instead of rejecting the whole archive.
  var total = 0;
  for (final f in zip.where((f) => f.isFile)) {
    final sink = _BudgetedOutput(maxTotal - total);
    try {
      f.decompress(sink);
    } on FormatException {
      rethrow;
    } catch (_) {
      // Encrypted or corrupt entries; keep the failure type the import flow
      // reports per file.
      throw const FormatException('压缩包内容已损坏或已加密');
    }
    // Replace the declared size with the measured one so the per-file limit in
    // decodeArchive cannot be bypassed by editing the central directory.
    f.size = sink.length;
    total += sink.length;
  }
  return zip;
}

/// Counts written bytes and discards them, so inflating a forged ZIP entry
/// aborts as soon as its real size exceeds the budget instead of allocating it.
class _BudgetedOutput extends OutputStream {
  _BudgetedOutput(this.budget) : super(byteOrder: ByteOrder.littleEndian);

  final int budget;
  int _length = 0;

  @override
  int get length => _length;

  void _count(int bytes) {
    _length += bytes;
    if (_length > budget) throw const FormatException('压缩包内容过大');
  }

  @override
  void writeByte(int value) => _count(1);

  @override
  void writeBytes(List<int> bytes, {int? length}) =>
      _count(length ?? bytes.length);

  @override
  void writeStream(InputStream stream) => _count(stream.length);

  @override
  void writeBackReference(int distance, int count) => _count(count);

  @override
  void clear() => _length = 0;

  @override
  void flush() {}

  @override
  Uint8List subset(int start, [int? end]) => Uint8List(0);
}

int naturalCompare(String a, String b) {
  String key(String s) => s.toLowerCase().replaceAllMapped(
    RegExp(r'\d+'),
    (m) => m[0]!.padLeft(12, '0'),
  );
  return key(a).compareTo(key(b));
}

String htmlText(dom.Document doc) {
  for (final e in doc.querySelectorAll('script, style, nav')) {
    e.remove();
  }
  for (final e in doc.querySelectorAll(
    'p, div, h1, h2, h3, li, blockquote, br',
  )) {
    e.nodes.add(dom.Text('\n'));
  }
  return (doc.body?.text ?? '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n\s*\n+'), '\n\n')
      .trim();
}

String decodePalmDoc(Uint8List bytes) {
  if (bytes.length < 94) throw const FormatException('Kindle 文件不完整');
  final data = ByteData.sublistView(bytes);
  final count = data.getUint16(76);
  if (count < 2 || 78 + count * 8 > bytes.length) {
    throw const FormatException('Kindle 记录表无效');
  }
  final offsets = [
    for (var i = 0; i < count; i++) data.getUint32(78 + i * 8),
    bytes.length,
  ];
  if (offsets.any((n) => n < 78 + count * 8 || n > bytes.length) ||
      offsets.asMap().entries.any(
        (e) => e.key > 0 && e.value < offsets[e.key - 1],
      )) {
    throw const FormatException('Kindle 文件偏移无效');
  }
  final start = offsets.first;
  if (start + 16 > bytes.length) throw const FormatException('Kindle 头不完整');
  final compression = data.getUint16(start), texts = data.getUint16(start + 8);
  if (data.getUint16(start + 12) != 0 ||
      ![1, 2].contains(compression) ||
      texts >= count) {
    throw const FormatException('暂不支持加密或 HUFF/CDIC Kindle；请转换为 EPUB');
  }
  final output = <int>[];
  for (var r = 1; r <= texts; r++) {
    final record = <int>[];
    for (var i = offsets[r]; i < offsets[r + 1]; i++) {
      final c = bytes[i];
      if (compression == 1 || c == 0 || (c >= 9 && c <= 127)) {
        record.add(c);
      } else if (c <= 8) {
        for (var j = 0; j < c; j++) {
          if (++i >= offsets[r + 1]) {
            throw const FormatException('PalmDOC 数据截断');
          }
          record.add(bytes[i]);
        }
      } else if (c >= 192) {
        record.addAll([32, c ^ 128]);
      } else {
        if (++i >= offsets[r + 1]) throw const FormatException('PalmDOC 数据截断');
        final pair = ((c << 8) | bytes[i]) & 0x3fff;
        final distance = pair >> 3, length = (pair & 7) + 3;
        if (distance == 0 || distance > record.length) {
          throw const FormatException('PalmDOC 引用无效');
        }
        for (var j = 0; j < length; j++) {
          record.add(record[record.length - distance]);
        }
      }
      if (record.length > 2 * 1024 * 1024 ||
          output.length + record.length > 60 * 1024 * 1024) {
        throw const FormatException('Kindle 正文过大');
      }
    }
    output.addAll(record);
  }
  final text = decodeText(Uint8List.fromList(output));
  return htmlText(html.parse(text));
}

/// Decodes text without letting one corrupt byte ruin a whole book: a BOM is
/// trusted first, a NUL-heavy stream is read as BOM-less UTF-16, then strict
/// UTF-8 wins. Only when strict UTF-8 fails is the damage measured: sparse
/// damage is repaired locally, and GBK stays the last resort for legacy
/// Chinese files, because a single stray byte used to send an entire UTF-8
/// book through the GBK path and silently store mojibake.
String decodeText(Uint8List bytes) {
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
          (bytes[0] == 0xfe && bytes[1] == 0xff))) {
    final little = bytes[0] == 0xff;
    if ((bytes.length - 2).isOdd) throw const FormatException('UTF-16 文件不完整');
    final data = ByteData.sublistView(bytes);
    return String.fromCharCodes([
      for (var i = 2; i < bytes.length; i += 2)
        data.getUint16(i, little ? Endian.little : Endian.big),
    ]);
  }
  var data = bytes;
  if (data.length >= 3 &&
      data[0] == 0xef &&
      data[1] == 0xbb &&
      data[2] == 0xbf) {
    data = Uint8List.sublistView(data, 3);
  }
  final utf16 = _decodeUtf16WithoutBom(data);
  if (utf16 != null) return utf16;
  try {
    return utf8.decode(data);
  } on FormatException {
    final repaired = utf8.decode(data, allowMalformed: true);
    final damaged = '\ufffd'.allMatches(repaired).length;
    // Sparse damage means the file is UTF-8 with a few bad bytes: a stray
    // 0xFF in the middle, or a multi-byte character cut off at the end, where
    // strict decoding only fails inside the last bytes of the file. The ratio
    // is deliberately strict: legacy GBK text is decoded as malformed UTF-8
    // with damage spread over its high bytes, and a mostly-ASCII file with a
    // few GBK characters must still reach the GBK decoder below rather than
    // being repaired into U+FFFD.
    if (damaged <= 4 &&
        (damaged * 100 <= data.length || _validUtf8Prefix(data))) {
      return repaired;
    }
    final gbk = gbk_bytes.decode(data);
    var blanks = 0;
    for (final unit in gbk.codeUnits) {
      if (unit == 0) blanks++;
    }
    if (blanks * 10 > gbk.length) {
      throw const FormatException('无法识别文件编码，请另存为 UTF-8 后重试');
    }
    return gbk;
  }
}

/// Detects BOM-less UTF-16 before the UTF-8 attempt: such text keeps a NUL byte
/// in almost every other byte, which strict UTF-8 accepts as valid input but
/// turns into unusable text.
String? _decodeUtf16WithoutBom(Uint8List bytes) {
  if (bytes.length < 8) return null;
  final head = bytes.length < 64 ? bytes.length : 64;
  var odd = 0, even = 0;
  for (var i = 0; i < head; i++) {
    if (bytes[i] == 0) {
      if (i.isOdd) {
        odd++;
      } else {
        even++;
      }
    }
  }
  if ((odd + even) * 2 < head) return null;
  if (bytes.length.isOdd) throw const FormatException('UTF-16 文件不完整');
  final data = ByteData.sublistView(bytes);
  final little = odd >= even;
  return String.fromCharCodes([
    for (var i = 0; i + 1 < bytes.length; i += 2)
      data.getUint16(i, little ? Endian.little : Endian.big),
  ]);
}

/// True when only the last few bytes are invalid UTF-8, which is how a
/// multi-byte character truncated at the end of a file looks.
bool _validUtf8Prefix(Uint8List bytes) {
  for (var cut = 1; cut <= 3 && cut < bytes.length; cut++) {
    try {
      utf8.decode(Uint8List.sublistView(bytes, 0, bytes.length - cut));
      return true;
    } on FormatException {
      // Try a shorter prefix.
    }
  }
  return false;
}

List<Chapter> splitChapters(
  String text, [
  String pattern = defaultChapterPattern,
]) {
  validateRules(pattern, '');
  final heading = RegExp(pattern, caseSensitive: false);
  final chapters = <Chapter>[];
  var title = '正文';
  var body = <String>[];
  void flush() {
    final content = body.join('\n').trim();
    if (content.isNotEmpty) chapters.add(Chapter(title, content));
    body = [];
  }

  for (final line
      in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
    if (line.length < 200 && heading.hasMatch(line)) {
      flush();
      title = line.trim();
    } else {
      body.add(line);
    }
  }
  flush();
  if (chapters.isEmpty) throw const FormatException('文件里没有可阅读的正文');
  if (chapters.length > 10000) {
    throw const FormatException('章节超过 10000 个，请检查分章规则');
  }
  return splitLongChapters(chapters);
}

// Virtual chapters bound foreground pagination work without changing content.
List<Chapter> splitLongChapters(List<Chapter> chapters) {
  final result = <Chapter>[];
  for (final chapter in chapters) {
    if (chapter.text.length <= 12000) {
      result.add(chapter);
      continue;
    }
    var start = 0, part = 1;
    while (start < chapter.text.length) {
      var end = (start + 12000).clamp(0, chapter.text.length);
      if (end < chapter.text.length) {
        final newline = chapter.text.lastIndexOf('\n', end - 1);
        if (newline > start + 6000) {
          end = newline + 1;
        }
        if (chapter.text.codeUnitAt(end - 1) >= 0xd800 &&
            chapter.text.codeUnitAt(end - 1) <= 0xdbff) {
          end--;
        }
      }
      result.add(
        Chapter(
          '${chapter.title} · 分段 $part',
          chapter.text.substring(start, end),
        ),
      );
      part++;
      start = end;
    }
  }
  if (result.length > 10000) {
    throw const FormatException('分段后章节超过 10000 个');
  }
  return result;
}

String cleanText(String text, ReaderSettings settings) {
  final rules = settings.purifyLines
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map(RegExp.new)
      .toList();
  var result = text
      .split('\n')
      .where(
        (line) => line.length > 4000 || !rules.any((r) => r.hasMatch(line)),
      )
      .join('\n');
  if (settings.cjkSpacing) {
    result = result
        .replaceAllMapped(
          RegExp(r'([\u3400-\u9fff])([a-zA-Z0-9])'),
          (m) => '${m[1]} ${m[2]}',
        )
        .replaceAllMapped(
          RegExp(r'([a-zA-Z0-9])([\u3400-\u9fff])'),
          (m) => '${m[1]} ${m[2]}',
        );
  }
  return result;
}

Book _parseEpub(Uint8List bytes, String id, String fallbackTitle) {
  final zip = checkedZip(bytes);
  if (zip.length > 4000 ||
      zip.fold<int>(0, (n, f) => n + f.size) > 60 * 1024 * 1024) {
    throw const FormatException('EPUB 解压内容过大');
  }
  final files = {
    for (final f in zip.where((f) => f.isFile)) p.posix.normalize(f.name): f,
  };
  String read(String name) {
    final f = files[p.posix.normalize(name)];
    if (f == null) throw FormatException('EPUB 缺少文件：$name');
    return utf8.decode(f.content, allowMalformed: true);
  }

  if (files.containsKey('META-INF/encryption.xml')) {
    final encryption = read('META-INF/encryption.xml');
    // IDPF font obfuscation is not DRM. Other encryption is unsupported.
    if (encryption.contains('EncryptedData') &&
        !encryption.contains('http://www.idpf.org/2008/embedding')) {
      throw const FormatException('不支持加密 EPUB');
    }
  }
  final container = XmlDocument.parse(read('META-INF/container.xml'));
  final root = container.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'rootfile')
      .first;
  final opfPath = root.getAttribute('full-path')!;
  final opf = XmlDocument.parse(read(opfPath));
  final dir = p.posix.dirname(opfPath);
  final items = <String, XmlElement>{};
  String? title, author, cover;
  for (final e in opf.descendants.whereType<XmlElement>()) {
    if (e.name.local == 'title') title ??= e.innerText.trim();
    if (e.name.local == 'creator') author ??= e.innerText.trim();
    if (e.name.local == 'item' && e.getAttribute('id') != null) {
      items[e.getAttribute('id')!] = e;
    }
  }
  final coverId = opf.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'meta' && e.getAttribute('name') == 'cover')
      .firstOrNull
      ?.getAttribute('content');
  final coverItem = items.values
      .where(
        (e) =>
            e.getAttribute('properties')?.split(' ').contains('cover-image') ==
                true ||
            e.getAttribute('id') == coverId,
      )
      .firstOrNull;
  if (coverItem != null) {
    final f =
        files[p.posix.normalize(
          p.posix.join(
            dir,
            Uri.decodeComponent(coverItem.getAttribute('href')!),
          ),
        )];
    if (f != null &&
        f.size < 2 * 1024 * 1024 &&
        [
          'image/jpeg',
          'image/png',
          'image/webp',
        ].contains(coverItem.getAttribute('media-type'))) {
      cover = base64Encode(f.content);
    }
  }
  final chapters = <Chapter>[];
  for (final ref in opf.descendants.whereType<XmlElement>().where(
    (e) => e.name.local == 'itemref' && e.getAttribute('linear') != 'no',
  )) {
    final item = items[ref.getAttribute('idref')];
    if (item == null ||
        !(item.getAttribute('media-type') ?? '').contains('html')) {
      continue;
    }
    final href = Uri.decodeComponent(
      item.getAttribute('href')!.split('#').first,
    );
    final doc = html.parse(read(p.posix.join(dir, href)));
    final chapterImages = <String>[];
    for (final image in doc.querySelectorAll('img')) {
      final src = image.attributes['src'];
      if (src == null || src.startsWith('http') || src.startsWith('data:')) {
        continue;
      }
      final file =
          files[p.posix.normalize(
            p.posix.join(
              dir,
              p.posix.dirname(href),
              Uri.decodeComponent(src.split('#').first),
            ),
          )];
      if (file != null &&
          file.size < 3 * 1024 * 1024 &&
          RegExp(
            r'\.(png|jpe?g|webp)$',
            caseSensitive: false,
          ).hasMatch(file.name)) {
        chapterImages.add(base64Encode(file.content));
      }
    }
    for (final e in doc.querySelectorAll('script, style, nav')) {
      e.remove();
    }
    final heading = doc.querySelector('h1, h2, h3')?.text.trim();
    // Add block boundaries before flattening. Imported HTML is never executed.
    for (final e in doc.querySelectorAll(
      'p, div, h1, h2, h3, li, blockquote, br',
    )) {
      e.nodes.add(dom.Text('\n'));
    }
    final text = (doc.body?.text ?? '')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n\s*\n+'), '\n\n')
        .trim();
    if (text.isNotEmpty || chapterImages.isNotEmpty) {
      chapters.add(
        Chapter(
          heading?.isNotEmpty == true ? heading! : '第 ${chapters.length + 1} 节',
          text.isEmpty ? '本章包含 ${chapterImages.length} 幅插图' : text,
          images: chapterImages,
        ),
      );
    }
  }
  if (chapters.isEmpty) throw const FormatException('EPUB 没有可读取的文字章节（图片书暂不支持）');
  return Book(
    id: id,
    title: title?.isNotEmpty == true ? title! : fallbackTitle,
    author: author ?? '未知作者',
    format: 'EPUB',
    chapters: chapters.expand((c) {
      final pieces = splitLongChapters([c]);
      return pieces.asMap().entries.map(
        (e) => Chapter(
          e.value.title,
          e.value.text,
          images: e.key == 0 ? c.images : const [],
        ),
      );
    }).toList(),
    cover: cover,
  );
}
