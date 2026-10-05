import 'form_field.dart';
import 'app_icons.dart';
import 'appearance.dart';

import 'package:flutter/material.dart';

import 'models.dart';

const shelfNames = {
  'grid': '网格',
  'list': '列表',
  'masonry': '瀑布流',
  'table': '表格',
  'simple': '极简',
};
Future<void> configureShelf(
  BuildContext context,
  ReaderSettings s,
  Future<void> Function() save, {
  List<Book> books = const [],
  Widget Function(Book)? cover,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: applicationMotion(context),
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('布置你的书架', style: Theme.of(c).textTheme.headlineSmall),
                const SizedBox(height: 16),
                if (cover != null)
                  ShelfPreview(books: books, settings: s, cover: cover),
                const SizedBox(height: 20),
                LabeledField(
                  label: '书架排序',
                  child: DropdownButtonFormField<String>(
                    initialValue: s.value('bookshelf.sort', 'recent'),
                    decoration: const InputDecoration(),
                    items: const [
                      DropdownMenuItem(value: 'recent', child: Text('最近阅读')),
                      DropdownMenuItem(value: 'added', child: Text('最近导入')),
                      DropdownMenuItem(value: 'title', child: Text('书名')),
                      DropdownMenuItem(value: 'author', child: Text('作者')),
                      DropdownMenuItem(value: 'progress', child: Text('阅读进度')),
                      DropdownMenuItem(value: 'rating', child: Text('评分')),
                    ],
                    onChanged: (v) => set(() => s.extra['bookshelf.sort'] = v),
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final e in shelfNames.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: s.value('bookshelf.layout', 'grid') == e.key,
                        onSelected: (_) =>
                            set(() => s.extra['bookshelf.layout'] = e.key),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                SettingSlider(
                  title: '列数',
                  displayValue: s.number('bookshelf.columns', 0).round() == 0
                      ? '自动'
                      : '${s.number('bookshelf.columns', 0).round()}',
                  value: s.number('bookshelf.columns', 0).clamp(0, 5),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  onChanged: (v) => set(() => s.extra['bookshelf.columns'] = v),
                ),
                SettingSlider(
                  title: '书籍间距',
                  displayValue: '${s.number('bookshelf.gap', 22).round()} dp',
                  value: s.number('bookshelf.gap', 22).clamp(8, 32),
                  min: 8,
                  max: 32,
                  divisions: 12,
                  onChanged: (v) => set(() => s.extra['bookshelf.gap'] = v),
                ),
                SettingSlider(
                  title: '网格卡片高度',
                  displayValue:
                      '${s.number('bookshelf.cardHeight', 290).round()} dp',
                  value: s.number('bookshelf.cardHeight', 290).clamp(220, 380),
                  min: 220,
                  max: 380,
                  divisions: 16,
                  onChanged: (v) =>
                      set(() => s.extra['bookshelf.cardHeight'] = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('显示原创阅读花园横幅'),
                  value: s.flag('bookshelf.banner', true),
                  onChanged: (v) => set(() => s.extra['bookshelf.banner'] = v),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('保存书架'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await save();
}

class ShelfPreview extends StatelessWidget {
  final List<Book> books;
  final ReaderSettings settings;
  final Widget Function(Book) cover;
  const ShelfPreview({
    super.key,
    required this.books,
    required this.settings,
    required this.cover,
  });
  @override
  Widget build(BuildContext context) {
    final sample = books.take(3).toList();
    final layout = settings.value('bookshelf.layout', 'grid');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '书架预览 · ${shelfNames[layout] ?? '网格'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (sample.isEmpty)
              const Text('导入书籍后，这里显示你的书架。')
            else if (layout == 'grid' || layout == 'masonry')
              LayoutBuilder(
                builder: (c, constraints) {
                  final count = settings.number('bookshelf.columns', 0).round();
                  final columns = layout == 'masonry'
                      ? count.clamp(2, 4)
                      : count == 0
                      ? 2
                      : count.clamp(1, 5);
                  final gap =
                      settings.number('bookshelf.gap', 22).clamp(8, 32) / 2;
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var i = 0; i < sample.length; i++)
                        SizedBox(
                          width: width,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: layout == 'grid'
                                    ? (settings
                                                      .number(
                                                        'bookshelf.cardHeight',
                                                        290,
                                                      )
                                                      .clamp(220, 380) /
                                                  2 -
                                              32)
                                          .clamp(64, 158)
                                    : width / (i.isEven ? .68 : .82),
                                width: width,
                                child: cover(sample[i]),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                sample[i].title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              )
            else if (layout == 'list')
              Column(
                children: [
                  for (final book in sample)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: SizedBox(
                        width: 32,
                        height: 48,
                        child: cover(book),
                      ),
                      title: Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              )
            else
              IgnorePointer(
                child: AlternativeShelf(
                  books: sample,
                  settings: settings,
                  open: (_) async {},
                  menu: (_) async {},
                  cover: cover,
                ),
              ),
            if (sample.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '用前三本藏书预览；实际大小以书架页面为准。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AlternativeShelf extends StatefulWidget {
  final List<Book> books;
  final ReaderSettings settings;
  final Future<void> Function(Book) open, menu;
  final Widget Function(Book) cover;
  const AlternativeShelf({
    super.key,
    required this.books,
    required this.settings,
    required this.open,
    required this.menu,
    required this.cover,
  });
  @override
  State<AlternativeShelf> createState() => _AlternativeShelfState();
}

class _AlternativeShelfState extends State<AlternativeShelf> {
  int sortColumn = 0;
  bool ascending = true;
  @override
  Widget build(BuildContext context) {
    final layout = widget.settings.value('bookshelf.layout', 'simple');
    if (layout == 'table') {
      final rows = List<Book>.from(widget.books)
        ..sort((a, b) {
          final n = switch (sortColumn) {
            1 => a.author.compareTo(b.author),
            2 => a.format.compareTo(b.format),
            3 => a.progress.compareTo(b.progress),
            _ => a.title.compareTo(b.title),
          };
          return ascending ? n : -n;
        });
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          sortColumnIndex: sortColumn,
          sortAscending: ascending,
          columns: [
            for (var i = 0; i < 4; i++)
              DataColumn(
                label: Text(['书名', '作者', '格式', '进度'][i]),
                onSort: (n, a) => setState(() {
                  sortColumn = n;
                  ascending = a;
                }),
              ),
          ],
          rows: [
            for (final b in rows)
              DataRow(
                cells: [
                  DataCell(
                    Text(b.title),
                    onTap: () => widget.open(b),
                    onLongPress: () => widget.menu(b),
                  ),
                  DataCell(Text(b.author)),
                  DataCell(Text(b.format)),
                  DataCell(Text('${(b.progress * 100).round()}%')),
                ],
              ),
          ],
        ),
      );
    }
    if (layout == 'masonry') {
      final count = widget.settings
          .number('bookshelf.columns', 2)
          .round()
          .clamp(2, 4);
      final cols = List.generate(count, (_) => <Book>[]);
      for (var i = 0; i < widget.books.length; i++) {
        cols[i % count].add(widget.books[i]);
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var col = 0; col < count; col++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.settings.number('bookshelf.gap', 22) / 2,
                  ),
                  child: Column(
                    children: [
                      for (final b in cols[col])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 22),
                          child: InkWell(
                            onTap: () => widget.open(b),
                            onLongPress: () => widget.menu(b),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AspectRatio(
                                  aspectRatio: col.isEven ? 0.68 : 0.82,
                                  child: widget.cover(b),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  b.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${b.author} · ${(b.progress * 100).round()}%',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final b in widget.books)
          ListTile(
            title: Text(b.title),
            subtitle: Text(
              '${b.author} · ${b.metadata['category'] ?? b.format} · ${(b.progress * 100).round()}%',
            ),
            trailing: const ShuyeIcon(Icons.chevron_right),
            onTap: () => widget.open(b),
            onLongPress: () => widget.menu(b),
          ),
      ],
    );
  }
}
