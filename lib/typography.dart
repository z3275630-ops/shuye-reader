import 'package:flutter/services.dart';
import 'package:hyphenatorx/hyphenatorx.dart';
import 'package:hyphenatorx/languages/language_en_us.dart';

import 'models.dart';

class ChineseConverter {
  static final simplified = <String, String>{},
      traditional = <String, String>{};
  static Future<void> load() async {
    for (final name in [
      'STCharacters',
      'STPhrases',
      'TSCharacters',
      'TSPhrases',
    ]) {
      final data = await rootBundle.loadString('assets/chinese/$name.txt');
      final target = name.startsWith('ST') ? traditional : simplified;
      for (final line in data.split('\n')) {
        if (line.isEmpty || line.startsWith('#')) continue;
        final parts = line.split('\t');
        if (parts.length == 2) {
          target[parts[0]] = parts[1].trim().split(' ').first;
        }
      }
    }
  }

  static String convert(String input, String mode) {
    final dictionary = mode == 'traditional' ? traditional : simplified;
    if (dictionary.isEmpty || mode == 'none') return input;
    final result = StringBuffer();
    var at = 0;
    while (at < input.length) {
      String? replacement;
      var consumed = 1;
      for (var n = (input.length - at).clamp(1, 16); n >= 1; n--) {
        final match = dictionary[input.substring(at, at + n)];
        if (match != null) {
          replacement = match;
          consumed = n;
          break;
        }
      }
      result.write(replacement ?? input.substring(at, at + 1));
      at += consumed;
    }
    return result.toString();
  }
}

class MappedText {
  final String text;
  final List<int> offsets;
  const MappedText(this.text, this.offsets);
}

final _hyphenator = Hyphenator(Language_en_us());

MappedText prepareText(String raw, ReaderSettings settings) {
  final buffer = StringBuffer(), positions = <int>[];
  final rules = settings.purifyLines
      .split('\n')
      .where((s) => s.trim().isNotEmpty)
      .map((s) => RegExp(s.trim()))
      .toList();
  final dictionary = settings.value('reader.chinese', 'none') == 'traditional'
      ? ChineseConverter.traditional
      : ChineseConverter.simplified;
  final convert = settings.value('reader.chinese', 'none') != 'none';
  var start = 0;
  for (final line in raw.split('\n')) {
    if ((line.isEmpty && settings.flag('reader.ignoreBlank')) ||
        (line.length <= 4000 && rules.any((r) => r.hasMatch(line)))) {
      start += line.length + 1;
      continue;
    }
    final converted = StringBuffer(), indices = <int>[];
    var at = 0;
    while (at < line.length) {
      String? replacement;
      var consumed = 1;
      if (convert) {
        for (var n = (line.length - at).clamp(1, 16); n >= 1; n--) {
          final match = dictionary[line.substring(at, at + n)];
          if (match != null) {
            replacement = match;
            consumed = n;
            break;
          }
        }
      }
      final word = replacement ?? line.substring(at, at + 1);
      converted.write(word);
      for (var i = 0; i < word.length; i++) {
        indices.add(start + at + (i * consumed ~/ word.length));
      }
      at += consumed;
    }
    var value = converted.toString();
    var offsets = indices;
    void transform(RegExp pattern, String Function(RegExpMatch) replacement) {
      final next = StringBuffer(), nextOffsets = <int>[];
      var previous = 0;
      for (final m in pattern.allMatches(value)) {
        next.write(value.substring(previous, m.start));
        nextOffsets.addAll(offsets.sublist(previous, m.start));
        final v = replacement(m);
        next.write(v);
        var source = m.start;
        for (var i = 0; i < v.length; i++) {
          if (source < m.end && v[i] == value[source]) {
            nextOffsets.add(offsets[source++]);
          } else {
            nextOffsets.add(offsets[(source - 1).clamp(m.start, m.end - 1)]);
          }
        }
        previous = m.end;
      }
      next.write(value.substring(previous));
      nextOffsets.addAll(offsets.sublist(previous));
      value = next.toString();
      offsets = nextOffsets;
    }

    if (settings.cjkSpacing) {
      transform(
        RegExp(r'([\u3400-\u9fff])([a-zA-Z0-9])'),
        (m) => '${m[1]} ${m[2]}',
      );
      transform(
        RegExp(r'([a-zA-Z0-9])([\u3400-\u9fff])'),
        (m) => '${m[1]} ${m[2]}',
      );
    }
    if (settings.flag('reader.hyphenation')) {
      transform(
        RegExp(r'[a-zA-Z]{5,}'),
        (m) => _hyphenator.hyphenateWord(m[0]!),
      );
    }
    buffer.write(value);
    positions.addAll(offsets);
    if (start + line.length < raw.length) {
      buffer.write('\n');
      positions.add(start + line.length);
    }
    start += line.length + 1;
  }
  positions.add(raw.length);
  return MappedText(buffer.toString(), positions);
}
