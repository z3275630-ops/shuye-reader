import 'edit_dialog.dart';
import 'app_icons.dart';

import 'package:flutter/material.dart';

import 'models.dart';
import 'repository.dart';
import 'facets.dart';

class LibraryCollections extends StatefulWidget {
  final ReaderRepository repo;
  final Future<void> Function(Book) open;
  final Widget Function(Book) cover;
  const LibraryCollections({
    super.key,
    required this.repo,
    required this.open,
    required this.cover,
  });
  @override
  State<LibraryCollections> createState() => _LibraryCollectionsState();
}

class _LibraryCollectionsState extends State<LibraryCollections> {
  List<Book> books = [];
  List<Map<String, dynamic>> saved = [];
  String field = 'tags', query = '';
  String? selected, error;
  bool loading = true, busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final list = await widget.repo.books(summaries: true);
      final groups = await widget.repo.entries('facets');
      if (mounted) {
        setState(() {
          books = list;
          saved = groups;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = '读取失败，请返回重试。';
          loading = false;
        });
      }
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> nameDialog(String title, {String initial = ''}) async {
    final result = await editFields(
      context,
      title,
      {'名称': initial},
      maxLengths: const {'名称': 120},
      autofocus: true,
    );
    return result?['名称'];
  }

  Future<void> create() async {
    final name = await nameDialog('新建${libraryFacets[field]}');
    if (name == null || name.isEmpty) return;
    validateFacet(field, name);
    if (!saved.any(
      (entry) => entry['field'] == field && entry['name'] == name,
    )) {
      await widget.repo.putEntry('facets', {'field': field, 'name': name});
    }
    if (mounted) setState(() => selected = name);
    await chooseBooks(name);
  }

  Future<void> chooseBooks(String name) async {
    final ids = <String>{};
    final chosen = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('加入“$name”'),
          content: SizedBox(
            width: 420,
            height: MediaQuery.sizeOf(c).height * .45,
            child: ListView(
              children: [
                if (books.isEmpty) const Text('先从书架导入书籍。'),
                for (final b in books)
                  CheckboxListTile(
                    title: Text(b.title),
                    subtitle: Text(b.author),
                    value: ids.contains(b.id),
                    onChanged: (v) => set(() {
                      if (v == true) {
                        ids.add(b.id);
                      } else {
                        ids.remove(b.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('加入所选书籍'),
            ),
          ],
        ),
      ),
    );
    if (chosen == true && ids.isNotEmpty) {
      if (!mounted) return;
      final replacing = books
          .where(
            (b) =>
                ids.contains(b.id) &&
                field != 'tags' &&
                bookFacetValues(b, field).any((v) => v != name),
          )
          .toList();
      if (replacing.isNotEmpty) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('更改${libraryFacets[field]}？'),
            scrollable: true,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '每本书只能设置一个${libraryFacets[field]}。以下书籍的原值将替换为“$name”，正文、进度与笔记保留。',
                ),
                const SizedBox(height: 12),
                for (final b in replacing)
                  Text(
                    '${b.title}：${bookFacetValues(b, field).join('、')} → $name',
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('确认更改'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      await widget.repo.assignFacet(field, name, ids.toList());
    }
  }

  Future<void> rename(String name) async {
    final value = await nameDialog('重命名${libraryFacets[field]}', initial: name);
    if (value == null || value.isEmpty || value == name) return;
    await widget.repo.renameFacet(field, name, value);
    if (mounted) setState(() => selected = value);
  }

  Future<void> remove(String name) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('移除“$name”？'),
        content: const Text('移除分组及书籍上的对应标记，书籍、正文和笔记都会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('移除分组'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await widget.repo.renameFacet(field, name, '');
    if (mounted) setState(() => selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Book>>{};
    for (final b in books) {
      final values = bookFacetValues(b, field);
      for (final v in values.isEmpty ? [''] : values) {
        (groups[v] ??= []).add(b);
      }
    }
    for (final g in saved.where((g) => g['field'] == field)) {
      groups.putIfAbsent(g['name'] as String, () => []);
    }
    final visible =
        groups.entries
            .where((e) => e.key.toLowerCase().contains(query.toLowerCase()))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final shown = selected == null ? <Book>[] : groups[selected] ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          selected == null
              ? '整理书库'
              : selected!.isEmpty
              ? '未设置${libraryFacets[field]}'
              : selected!,
        ),
        leading: selected == null
            ? null
            : IconButton(
                tooltip: '返回分组',
                onPressed: () => setState(() => selected = null),
                icon: const ShuyeIcon(Icons.arrow_back),
              ),
        actions: [
          if (selected == null)
            IconButton(
              tooltip: '新建分组',
              onPressed: busy ? null : () => run(create),
              icon: const ShuyeIcon(Icons.add),
            ),
          if (selected != null && selected!.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (v) => run(
                () => v == 'add'
                    ? chooseBooks(selected!)
                    : v == 'rename'
                    ? rename(selected!)
                    : remove(selected!),
              ),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add', child: Text('加入书籍')),
                PopupMenuItem(value: 'rename', child: Text('重命名')),
                PopupMenuItem(value: 'remove', child: Text('移除分组')),
              ],
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (selected == null) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final kind in libraryFacets.entries)
                        ChoiceChip(
                          label: Text(kind.value),
                          selected: field == kind.key,
                          onSelected: busy
                              ? null
                              : (_) => setState(() {
                                  field = kind.key;
                                  query = '';
                                }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: ValueKey(field),
                    onChanged: (v) => setState(() => query = v),
                    decoration: InputDecoration(
                      prefixIcon: const ShuyeIcon(Icons.search),
                      hintText: '搜索${libraryFacets[field]}',
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(30),
                      child: Text('还没有分组，点击右上角 + 创建。'),
                    ),
                  for (final group in visible)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const ShuyeIcon(Icons.folder_outlined),
                        title: Text(
                          group.key.isEmpty
                              ? '未设置${libraryFacets[field]}'
                              : group.key,
                        ),
                        trailing: Text('${group.value.length} 本'),
                        onTap: () => setState(() => selected = group.key),
                      ),
                    ),
                ] else ...[
                  Text(
                    '${shown.length} 本书',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 14),
                  if (shown.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('这里还没有书籍，可从右上角菜单加入。'),
                    ),
                  for (final b in shown)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: SizedBox(
                          width: 42,
                          height: 64,
                          child: widget.cover(b),
                        ),
                        title: Text(
                          b.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${b.author} · ${(b.progress * 100).round()}%',
                        ),
                        onTap: () => run(() async {
                          await widget.open(b);
                        }),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
