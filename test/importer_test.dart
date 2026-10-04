import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:shuye_reader/importer.dart';
import 'package:shuye_reader/models.dart';

void main() {
  test(
    'long unstructured books get bounded virtual chapters without content loss',
    () {
      final text = List.filled(15000, '山😀').join();
      final chapters = splitChapters(text);
      expect(chapters.length, greaterThan(1));
      expect(chapters.map((c) => c.text).join(), text);
      expect(chapters.every((c) => c.text.length <= 12000), isTrue);
      expect(
        chapters.every(
          (c) =>
              c.text.codeUnitAt(c.text.length - 1) < 0xd800 ||
              c.text.codeUnitAt(c.text.length - 1) > 0xdbff,
        ),
        isTrue,
      );
    },
  );
  test('TXT detects headings, preserves preface and skips empty chapters', () {
    final chapters = splitChapters(
      '前面的一段\r\n第一章 起点\r\n你好。\r\n第二章 空\r\n第三章 结尾\r\n再见。',
    );
    expect(chapters.map((c) => c.title), ['正文', '第一章 起点', '第三章 结尾']);
    expect(chapters.last.text, '再见。');
    expect(() => splitChapters('  \n'), throwsFormatException);
  });
  test('UTF8, UTF16 LE/BE and GBK decode Chinese without corruption', () {
    const s = '第一章 山间来信';
    expect(decodeText(Uint8List.fromList(utf8.encode('\ufeff$s'))), s);
    expect(decodeText(Uint8List.fromList(gbk_bytes.encode(s))), s);
    for (final endian in [Endian.little, Endian.big]) {
      final data = ByteData(2 + s.codeUnits.length * 2);
      data.setUint16(0, 0xfeff, endian);
      for (var i = 0; i < s.codeUnits.length; i++) {
        data.setUint16(2 + i * 2, s.codeUnits[i], endian);
      }
      expect(decodeText(data.buffer.asUint8List()), s);
    }
  });
  test('purification is reversible and CJK spacing is selective', () {
    const text = '中文Flutter3阅读\n关注公众号领取\n正常正文';
    final s = ReaderSettings(purifyLines: '关注公众号');
    expect(cleanText(text, s), '中文 Flutter3 阅读\n正常正文');
    s.purifyLines = '';
    s.cjkSpacing = false;
    expect(cleanText(text, s), text);
    expect(() => validateRules('(a+)+', ''), throwsFormatException);
    expect(() => validateRules('[', ''), throwsFormatException);
  });
  test('EPUB follows spine rather than zip order and strips active markup', () {
    final zip = Archive();
    void add(String name, String text) {
      final bytes = utf8.encode(text);
      zip.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add(
      'META-INF/container.xml',
      '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
    );
    add(
      'OPS/book.opf',
      '<package><metadata><title>测试书</title><creator>作者</creator></metadata><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/><item id="two" href="two.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="two"/><itemref idref="one"/></spine></package>',
    );
    add(
      'OPS/one.xhtml',
      '<html><body><h1>一</h1><p>第一段</p><script>恶意脚本</script></body></html>',
    );
    add('OPS/two.xhtml', '<html><body><h1>二</h1><p>第二段</p></body></html>');
    final bytes = Uint8List.fromList(ZipEncoder().encode(zip));
    final book = parseBook({'bytes': bytes, 'name': 'test.epub'});
    expect(book.title, '测试书');
    expect(book.author, '作者');
    expect(book.chapters.map((c) => c.title), ['二', '一']);
    expect(book.chapters.last.text.contains('恶意脚本'), isFalse);
    expect(book.id, parseBook({'bytes': bytes, 'name': 'renamed.epub'}).id);
  });
  test('bad imports fail explicitly', () {
    expect(
      () => parseBook({'bytes': Uint8List(0), 'name': 'a.txt'}),
      throwsFormatException,
    );
    expect(
      () => parseBook({
        'bytes': Uint8List.fromList([1]),
        'name': 'a.pdf',
      }),
      throwsFormatException,
    );
    expect(
      () => parseBook({
        'bytes': Uint8List.fromList([1, 2, 3]),
        'name': 'bad.epub',
      }),
      throwsA(anything),
    );
  });
}
