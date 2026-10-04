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
    default:
      throw const FormatException('目前支持 TXT 和无加密的 EPUB 文件');
  }
}

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
  try {
    return utf8.decode(bytes).replaceFirst('\ufeff', '');
  } on FormatException {
    return gbk_bytes.decode(bytes);
  }
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
  final zip = ZipDecoder().decodeBytes(bytes, verify: true);
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
    if (text.isNotEmpty) {
      chapters.add(
        Chapter(
          heading?.isNotEmpty == true ? heading! : '第 ${chapters.length + 1} 节',
          text,
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
    chapters: splitLongChapters(chapters),
    cover: cover,
  );
}
