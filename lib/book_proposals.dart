import 'dart:async';

import 'package:flutter/material.dart';

import 'repository.dart';

class BookProposals extends StatefulWidget {
  final ReaderRepository repo;
  const BookProposals({super.key, required this.repo});
  @override
  State<BookProposals> createState() => _BookProposalsState();
}

class _BookProposalsState extends State<BookProposals> {
  List<Map<String, dynamic>> proposals = [];
  static const names = {
    'title': '书名',
    'author': '作者',
    'category': '分类',
    'tags': '标签',
    'list': '书单',
    'rating': '评分',
    'review': '书评',
  };
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    final data = await widget.repo.entries('bookProposals');
    if (mounted) setState(() => proposals = data);
  }

  Future<void> apply(String id) async {
    try {
      await widget.repo.applyBookProposal(id);
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已应用资料修改')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('书籍修改建议')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '阅读助手和 MCP 客户端只能提交建议。你检查后点击“应用”，才会修改书籍资料。正文、笔记和文件不会由建议修改。',
          style: TextStyle(height: 1.6),
        ),
        const SizedBox(height: 20),
        if (proposals.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('目前没有待检查的建议。可以把阅读助手的答复保存为书评建议。'),
          ),
        for (final item in proposals)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title'] as String,
                    style: const TextStyle(fontSize: 20),
                  ),
                  Text(item['status'] == 'applied' ? '已应用' : '待检查'),
                  for (final e in (item['changes'] as Map).entries)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SelectableText(
                        '${names[e.key] ?? e.key}\n原来：${(item['before'] as Map)[e.key] ?? '未填写'}\n建议：${e.value}',
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    children: [
                      if (item['status'] == 'pending')
                        FilledButton(
                          onPressed: () => apply(item['id'] as String),
                          child: const Text('应用这条建议'),
                        ),
                      TextButton(
                        onPressed: () async {
                          await widget.repo.removeEntry(item['id'] as String);
                          await load();
                        },
                        child: Text(
                          item['status'] == 'pending' ? '拒绝并删除' : '删除记录',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
