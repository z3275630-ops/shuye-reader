import 'models.dart';

const libraryFacets = {
  'tags': '标签',
  'category': '分类',
  'list': '书单',
  'author': '作者',
};
List<String> splitTags(String value) => value
    .split(RegExp(r'[,，、;；\n]'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toSet()
    .toList();
List<String> bookFacetValues(Book book, String field) {
  final value = field == 'author'
      ? book.author
      : book.metadata[field] as String? ?? '';
  return field == 'tags'
      ? splitTags(value)
      : value.trim().isEmpty
      ? []
      : [value.trim()];
}

void validateFacet(String field, String name) {
  if (!libraryFacets.containsKey(field) ||
      name.length > 120 ||
      name.contains('\n') ||
      name.contains('\r') ||
      (field == 'tags' && splitTags(name).length > 1)) {
    throw const FormatException('名称需在 120 字内，标签不能包含分隔符。');
  }
}
