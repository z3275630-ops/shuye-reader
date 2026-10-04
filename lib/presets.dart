import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'repository.dart';
import 'workbench.dart';

class ReadingPresets extends StatefulWidget {
  final ReaderRepository repo;
  final ReaderSettings settings;
  const ReadingPresets({super.key, required this.repo, required this.settings});
  @override
  State<ReadingPresets> createState() => _ReadingPresetsState();
}

class _ReadingPresetsState extends State<ReadingPresets> {
  List<Map<String, dynamic>> saved = [];
  static const builtIn = <String, Map<String, dynamic>>{
    '暖纸慢读': {
      'reader.theme': 'paper',
      'reader.fontSize': 20,
      'reader.lineHeight': 1.85,
      'reader.animation': 'curl',
      'reader.atmosphere': 'none',
    },
    '夜间安静': {
      'reader.theme': 'night',
      'reader.fontSize': 21,
      'reader.lineHeight': 1.8,
      'reader.atmosphere': 'none',
    },
    '墨水屏': {
      'reader.theme': 'white',
      'reader.eink': true,
      'reader.animation': 'none',
      'reader.atmosphere': 'none',
    },
    '英文专注': {
      'reader.theme': 'white',
      'reader.hyphenation': true,
      'reader.bionic': true,
      'reader.ignoreBlank': false,
    },
  };
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    final data = await widget.repo.entries('readingPresets');
    if (mounted) setState(() => saved = data);
  }

  Future<void> apply(Map<String, dynamic> values) async {
    final s = widget.settings;
    final onlyReader = {
      for (final e in values.entries)
        if (e.key.startsWith('reader.')) e.key: e.value,
    };
    final next = ReaderSettings.fromJson({...s.toJson(), ...onlyReader});
    s.fontSize = next.fontSize;
    s.lineHeight = next.lineHeight;
    s.font = next.font;
    s.theme = next.theme;
    s.chapterPattern = next.chapterPattern;
    s.purifyLines = next.purifyLines;
    s.cjkSpacing = next.cjkSpacing;
    s.extra.addAll(onlyReader);
    await widget.repo.saveSettings(s);
    if (mounted) toast(context, '已应用，下次打开正文即可使用');
  }

  Future<void> save() async {
    final name = await editFields(context, '保存当前阅读方案', {'名称': ''});
    if (name == null || name['名称']!.isEmpty) return;
    await widget.repo.putEntry('readingPresets', {
      'name': name['名称'],
      'values': {
        for (final e in widget.settings.toJson().entries)
          if (e.key.startsWith('reader.')) e.key: e.value,
      },
    });
    await load();
  }

  Future<void> import() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (picked == null) return;
      if (picked.files.single.size > 1024 * 1024 ||
          picked.files.single.path == null) {
        throw const FormatException('方案文件过大或无法读取');
      }
      final j = jsonDecode(
        await File(picked.files.single.path!).readAsString(),
      ) as Map<String, dynamic>;
      if (j['app'] != 'shuye-reading-preset' ||
          j['version'] != 1 ||
          j['name'] is! String) {
        throw const FormatException('不是书叶阅读方案');
      }
      final values = Map<String, dynamic>.from(j['values'] as Map);
      if (values.keys.any((k) => !k.startsWith('reader.'))) {
        throw const FormatException('阅读方案包含不相关设置');
      }
      ReaderSettings.fromJson(values);
      await widget.repo.putEntry('readingPresets', {
        'name': j['name'],
        'values': values,
      });
      await load();
      if (mounted) toast(context, '已导入方案，点击后应用');
    } catch (e) {
      if (mounted) toast(context, '导入未完成：$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('主题与规则方案'),
      actions: [
        IconButton(
          tooltip: '导入阅读方案',
          onPressed: import,
          icon: const Icon(Icons.file_open_outlined),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: save,
      child: const Icon(Icons.add),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '保存纸色、字体排版、翻页、净化与分章规则。方案不改变书架、账号或书库锁。',
          style: TextStyle(height: 1.6),
        ),
        const SizedBox(height: 12),
        for (final e in builtIn.entries)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: Text(e.key),
              onTap: () => apply({
                'reader.eink': false,
                'reader.bionic': false,
                'reader.hyphenation': false,
                ...e.value,
              }),
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('我的方案', style: TextStyle(fontSize: 20)),
        ),
        for (final item in saved)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(item['name'] as String),
              onTap: () =>
                  apply(Map<String, dynamic>.from(item['values'] as Map)),
              trailing: PopupMenuButton<String>(
                onSelected: (action) async {
                  if (action == 'export') {
                    try {
                      await saveBytes(
                        'shuye-reading-preset.json',
                        utf8.encode(
                          jsonEncode({
                            'app': 'shuye-reading-preset',
                            'version': 1,
                            'name': item['name'],
                            'values': item['values'],
                          }),
                        ),
                      );
                    } catch (e) {
                      if (context.mounted) toast(context, '导出未完成：$e');
                    }
                  }
                  if (action == 'delete') {
                    await widget.repo.removeEntry(item['id'] as String);
                    await load();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'export', child: Text('导出方案')),
                  PopupMenuItem(value: 'delete', child: Text('删除方案')),
                ],
              ),
            ),
          ),
        if (saved.isEmpty) const Text('点击 + 保存你当前的设置。'),
        const SizedBox(height: 80),
      ],
    ),
  );
}
