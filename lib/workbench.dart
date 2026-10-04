import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'audio_library.dart';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'importer.dart';
import 'models.dart';
import 'repository.dart';
import 'services.dart';
import 'privacy.dart';
import 'presets.dart';
import 'book_proposals.dart';
import 'character_graph.dart';
import 'lan_backup.dart';

const originalCovers = [
  'assets/art/mountain.webp',
  'assets/art/poetry.webp',
  'assets/art/notebook.webp',
];
void toast(BuildContext ctx, String text) {
  if (ctx.mounted) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(text)));
  }
}

Future<Map<String, String>?> editFields(
  BuildContext ctx,
  String title,
  Map<String, String> fields, {
  Set<String> passwords = const {},
  String? description,
}) async {
  final controllers = {
    for (final e in fields.entries) e.key: TextEditingController(text: e.value),
  };
  final result = await showDialog<Map<String, String>>(
    context: ctx,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (description != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    description,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              for (final e in controllers.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: e.value,
                    obscureText: passwords.contains(e.key),
                    maxLines: passwords.contains(e.key)
                        ? 1
                        : (e.key.contains('正文') ||
                                  e.key.contains('提示词') ||
                                  e.key.contains('说明')
                              ? 5
                              : 1),
                    decoration: InputDecoration(labelText: e.key),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, {
            for (final e in controllers.entries) e.key: e.value.text.trim(),
          }),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  // Wait until the dialog's reverse animation releases its text fields.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  for (final c in controllers.values) {
    c.dispose();
  }
  return result;
}

Future<void> saveBytes(
  String name,
  List<int> bytes, {
  List<String>? extensions,
}) async {
  await FilePicker.platform.saveFile(
    dialogTitle: '保存文件',
    fileName: name,
    type: FileType.custom,
    allowedExtensions: extensions ?? [name.split('.').last],
    bytes: Uint8List.fromList(bytes),
  );
}

Uint8List exportEpub(Book book) {
  String escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  final zip = Archive();
  void add(String name, String text) => zip.addFile(
    ArchiveFile(name, utf8.encode(text).length, utf8.encode(text)),
  );
  add('mimetype', 'application/epub+zip');
  zip.files.first.compression = CompressionType.none;
  add(
    'META-INF/container.xml',
    '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
  );
  final manifest = StringBuffer(), spine = StringBuffer(), nav = StringBuffer();
  for (var i = 0; i < book.chapters.length; i++) {
    final chapter = book.chapters[i];
    final images = StringBuffer();
    for (var j = 0; j < chapter.images.length; j++) {
      final bytes = base64Decode(chapter.images[j]);
      final ext = bytes.length > 2 && bytes[0] == 0xff
          ? 'jpg'
          : bytes.length > 4 && bytes[0] == 137
          ? 'png'
          : 'webp';
      final path = 'image-$i-$j.$ext';
      zip.addFile(ArchiveFile('OEBPS/$path', bytes.length, bytes));
      manifest.write(
        '<item id="img$i-$j" href="$path" media-type="image/${ext == 'jpg' ? 'jpeg' : ext}"/>',
      );
      images.write('<img src="$path" alt="插图"/>');
    }
    add(
      'OEBPS/chapter$i.xhtml',
      '<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>${escape(chapter.title)}</title></head><body><h1>${escape(chapter.title)}</h1>${chapter.text.split('\n').map((p) => '<p>${escape(p)}</p>').join()}$images</body></html>',
    );
    manifest.write(
      '<item id="c$i" href="chapter$i.xhtml" media-type="application/xhtml+xml"/>',
    );
    spine.write('<itemref idref="c$i"/>');
    nav.write(
      '<li><a href="chapter$i.xhtml">${escape(chapter.title)}</a></li>',
    );
  }
  add(
    'OEBPS/nav.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目录</title></head><body><nav epub:type="toc"><ol>$nav</ol></nav></body></html>',
  );
  add(
    'OEBPS/content.opf',
    '<?xml version="1.0"?><package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">${escape(book.id)}</dc:identifier><dc:title>${escape(book.title)}</dc:title><dc:creator>${escape(book.author)}</dc:creator><dc:language>zh</dc:language><meta property="dcterms:modified">${DateTime.now().toUtc().toIso8601String().split('.').first}Z</meta></metadata><manifest>$manifest<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/></manifest><spine>$spine</spine></package>',
  );
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

Future<void> showBookDetails(
  BuildContext ctx,
  Book b,
  ReaderRepository repo,
  Future<void> Function() reload,
) async {
  await showModalBottomSheet<void>(
    context: ctx,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(b.title),
              subtitle: Text('${b.author} · ${b.format} · ${b.words} 字'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑书籍资料'),
              subtitle: const Text('分类、标签、评分、书单和阅读目标'),
              onTap: () async {
                final fields = await editFields(sheet, '书籍资料', {
                  '书名': b.title,
                  '作者': b.author,
                  '分类': b.metadata['category'] as String? ?? '',
                  '标签（逗号分隔）': b.metadata['tags'] as String? ?? '',
                  '评分（0–5）': '${b.metadata['rating'] ?? 0}',
                  '书单': b.metadata['list'] as String? ?? '',
                  '目标完成日期': b.metadata['goal'] as String? ?? '',
                  '书评说明': b.metadata['review'] as String? ?? '',
                });
                if (fields != null) {
                  if (fields['书名']!.isEmpty) return;
                  b.title = fields['书名']!;
                  b.author = fields['作者']!.isEmpty ? '未知作者' : fields['作者']!;
                  b.metadata.addAll({
                    'category': fields['分类'],
                    'tags': fields['标签（逗号分隔）'],
                    'rating': (double.tryParse(fields['评分（0–5）']!) ?? 0).clamp(
                      0,
                      5,
                    ),
                    'list': fields['书单'],
                    'goal': fields['目标完成日期'],
                    'review': fields['书评说明'],
                  });
                  await repo.updateBook(b);
                  await reload();
                  if (sheet.mounted) Navigator.pop(sheet);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('更换封面'),
              onTap: () async {
                await showModalBottomSheet<void>(
                  context: sheet,
                  showDragHandle: true,
                  builder: (c) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              for (final path in originalCovers)
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      b.cover = 'asset:$path';
                                      await repo.updateBook(b);
                                      await reload();
                                      if (c.mounted) Navigator.pop(c);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(5),
                                      child: AspectRatio(
                                        aspectRatio: 2 / 3,
                                        child: Image.asset(
                                          path,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        ListTile(
                          title: const Text('从手机选择图片'),
                          leading: const Icon(
                            Icons.add_photo_alternate_outlined,
                          ),
                          onTap: () async {
                            final f = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                            );
                            if (f == null) return;
                            final file = f.files.single;
                            if (file.size > 3 * 1024 * 1024) {
                              throw const FormatException('封面不能超过 3 MB');
                            }
                            b.cover = base64Encode(
                              await File(file.path!).readAsBytes(),
                            );
                            await repo.updateBook(b);
                            await reload();
                            if (c.mounted) Navigator.pop(c);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('人物与关系'),
              onTap: () => Navigator.push(
                sheet,
                MaterialPageRoute<void>(
                  builder: (_) => EntryScreen(
                    repo: repo,
                    kind: 'characters',
                    book: b,
                    title: '人物与关系',
                    fields: const ['人物', '角色', '关联人物', '关系说明'],
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.translate),
              title: const Text('生词本'),
              onTap: () => Navigator.push(
                sheet,
                MaterialPageRoute<void>(
                  builder: (_) => EntryScreen(
                    repo: repo,
                    kind: 'vocabulary',
                    book: b,
                    title: '生词本',
                    fields: const ['词语', '释义说明', '分组'],
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('编辑当前章节'),
              onTap: () async {
                final ch = b.chapters[b.chapter];
                final result = await editFields(sheet, '编辑章节', {
                  '标题': ch.title,
                  '正文': ch.text,
                });
                if (result == null || result['正文']!.isEmpty) return;
                await repo.editChapter(
                  b,
                  b.chapter,
                  Chapter(result['标题']!, result['正文']!, images: ch.images),
                );
                await reload();
                if (sheet.mounted) Navigator.pop(sheet);
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('导出 EPUB'),
              onTap: () async {
                try {
                  await saveBytes('${b.title}.epub', exportEpub(b));
                } catch (e) {
                  if (sheet.mounted) toast(sheet, '导出失败：$e');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_snippet_outlined),
              title: const Text('导出 TXT'),
              onTap: () => saveBytes(
                '${b.title}.txt',
                utf8.encode(
                  b.chapters.map((c) => '${c.title}\n\n${c.text}').join('\n\n'),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('重新读一遍'),
              onTap: () async {
                await repo.putEntry('readingRounds', {
                  'at': DateTime.now().toIso8601String(),
                  'progress': b.progress,
                }, bookId: b.id);
                b.chapter = 0;
                b.offset = 0;
                await repo.saveProgress(b);
                await reload();
                if (sheet.mounted) Navigator.pop(sheet);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class EntryScreen extends StatefulWidget {
  final ReaderRepository repo;
  final String kind, title;
  final Book? book;
  final List<String> fields;
  const EntryScreen({
    super.key,
    required this.repo,
    required this.kind,
    required this.title,
    required this.fields,
    this.book,
  });
  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  List<Map<String, dynamic>> entries = [];
  String search = '';
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    final e = await widget.repo.entries(widget.kind, bookId: widget.book?.id);
    if (mounted) setState(() => entries = e);
  }

  Future<void> edit([Map<String, dynamic>? e]) async {
    final data = await editFields(context, widget.title, {
      for (final key in widget.fields) key: e?[key] as String? ?? '',
    });
    if (data == null || data.values.every((v) => v.isEmpty)) return;
    await widget.repo.putEntry(
      widget.kind,
      data,
      bookId: widget.book?.id,
      id: e?['id'] as String?,
    );
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        if (widget.kind == 'characters')
          IconButton(
            tooltip: '人物关系图',
            icon: const Icon(Icons.account_tree_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CharacterGraph(characters: entries),
              ),
            ),
          ),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: edit,
      child: const Icon(Icons.add),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              hintText: '搜索',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => search = v),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('点击 +，添加你的第一条记录'))
              : ListView(
                  children: [
                    for (final e in entries.where(
                      (e) => e.values.any((v) => v.toString().contains(search)),
                    ))
                      Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 5,
                        ),
                        child: ListTile(
                          title: Text(e[widget.fields.first] as String? ?? ''),
                          subtitle: Text(
                            widget.fields
                                .skip(1)
                                .map((k) => '$k：${e[k] ?? ''}')
                                .join('\n'),
                          ),
                          onTap: () => edit(e),
                          trailing: IconButton(
                            tooltip: '删除记录',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await widget.repo.removeEntry(e['id'] as String);
                              await load();
                            },
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    ),
  );
}

Future<void> showAiAssistant(
  BuildContext ctx,
  ReaderRepository repo,
  ReaderSettings s, {
  Book? book,
  String? excerpt,
}) async {
  final prompt = TextEditingController(
    text: excerpt != null ? '解释这段文字，并列出值得思考的问题' : '帮我梳理这本书的重点',
  );
  final prompts = await repo.entries('prompts');
  if (!ctx.mounted) {
    prompt.dispose();
    return;
  }
  String result = '';
  bool busy = false;
  await showModalBottomSheet<void>(
    context: ctx,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(c).bottom + 20,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(c).height * .75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('阅读助手', style: TextStyle(fontSize: 22)),
                const SizedBox(height: 8),
                Text(
                  excerpt != null
                      ? '仅发送所选摘录'
                      : book != null
                      ? '仅发送当前章节（最多 3 万字符）'
                      : '仅发送书名、作者和阅读进度',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final q in ['解释文字', '总结重点', '解释生词', '制定阅读计划'])
                      ActionChip(
                        label: Text(q),
                        onPressed: () => prompt.text = q,
                      ),
                    for (final custom in prompts.take(12))
                      ActionChip(
                        label: Text(custom['名称'] as String? ?? '自定义'),
                        onPressed: () =>
                            prompt.text = custom['提示词'] as String? ?? '',
                      ),
                  ],
                ),
                TextField(
                  controller: prompt,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: '你想了解什么？'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          set(() => busy = true);
                          try {
                            final context =
                                excerpt ??
                                (book != null
                                    ? book.chapters[book.chapter].text
                                    : (await repo.books(summaries: true))
                                          .map(
                                            (b) =>
                                                '${b.title} / ${b.author} / ${(b.progress * 100).round()}%',
                                          )
                                          .join('\n'));
                            final answer = await AiClient().answer(
                              endpoint: s.value(
                                'ai.endpoint',
                                'https://api.openai.com/v1',
                              ),
                              key: await Secrets().read('ai.key'),
                              model: s.value('ai.model', ''),
                              prompt: prompt.text,
                              context: context,
                              system: s.value(
                                'ai.systemPrompt',
                                '你是阅读助手，引用原文并注明位置，不编造事实。',
                              ),
                            );
                            await repo.putEntry('aiChats', {
                              'question': prompt.text,
                              'answer': answer,
                            }, bookId: book?.id);
                            if (c.mounted) set(() => result = answer);
                          } catch (e) {
                            if (c.mounted) set(() => result = '请求未完成：$e');
                          } finally {
                            if (c.mounted) set(() => busy = false);
                          }
                        },
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(busy ? '正在思考…' : '发送'),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: SelectableText(
                        result.isEmpty ? '配置自己的 AI 服务后即可使用。输出请结合原文核对。' : result,
                      ),
                    ),
                  ),
                ),
                if (book != null && result.isNotEmpty && !busy)
                  TextButton.icon(
                    onPressed: () async {
                      try {
                        await repo.proposeBookUpdate(book.id, {
                          'review': result,
                        });
                        if (c.mounted) toast(c, '已保存建议，请在工具箱“书籍修改建议”中检查后应用');
                      } catch (e) {
                        if (c.mounted) toast(c, '保存未完成：$e');
                      }
                    },
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('保存为书评建议'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  prompt.dispose();
}

Future<void> showShareCard(BuildContext ctx, String quote, String title) async {
  final key = GlobalKey();
  var art = 0;
  await showDialog<void>(
    context: ctx,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  key: key,
                  child: Container(
                    width: 360,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: const Color(0xfff4eddf),
                      image: DecorationImage(
                        image: AssetImage(originalCovers[art]),
                        fit: BoxFit.cover,
                        opacity: .13,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.format_quote,
                          color: Color(0xff58735f),
                          size: 36,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          quote.length > 800 ? quote.substring(0, 800) : quote,
                          style: const TextStyle(
                            fontSize: 18,
                            height: 1.8,
                            color: Color(0xff263b32),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          '— $title',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xff58735f),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '书叶 · 把喜欢的文字留在身边',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xff58735f),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < 3; i++)
                      ChoiceChip(
                        label: Text(['山间', '诗意', '手记'][i]),
                        selected: art == i,
                        onSelected: (_) => set(() => art = i),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final boundary =
                    key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary;
                final image = await boundary.toImage(pixelRatio: 3);
                final png = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                image.dispose();
                final dir = await getTemporaryDirectory();
                final file = File(
                  '${dir.path}/shuye-share-${DateTime.now().microsecondsSinceEpoch}.png',
                );
                await file.writeAsBytes(png!.buffer.asUint8List());
                await SharePlus.instance.share(
                  ShareParams(files: [XFile(file.path)], text: '《$title》摘录'),
                );
              } catch (e) {
                if (c.mounted) toast(c, '分享未完成：$e');
              }
            },
            child: const Text('分享'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final boundary =
                    key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary;
                final image = await boundary.toImage(pixelRatio: 3);
                final png = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                image.dispose();
                await saveBytes('书叶摘录.png', png!.buffer.asUint8List());
                if (c.mounted) toast(c, '摘录卡片已保存');
              } catch (e) {
                if (c.mounted) toast(c, '保存失败：$e');
              }
            },
            child: const Text('保存图片'),
          ),
        ],
      ),
    ),
  );
}

class WorkshopScreen extends StatefulWidget {
  final ReaderRepository repo;
  final ReaderSettings settings;
  const WorkshopScreen({super.key, required this.repo, required this.settings});
  @override
  State<WorkshopScreen> createState() => _WorkshopScreenState();
}

class _WorkshopScreenState extends State<WorkshopScreen>
    with WidgetsBindingObserver {
  bool busy = false;
  McpService? mcp;
  LanBackup? lan;
  ReaderSettings get s => widget.settings;
  ReaderRepository get repo => widget.repo;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(lan?.stop());
    if (state != AppLifecycleState.resumed && mcp?.server != null) {
      unawaited(mcp!.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(mcp?.stop());
    unawaited(lan?.stop());
    super.dispose();
  }

  Future<void> run(Future<void> Function() task) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await task();
    } catch (e) {
      if (mounted) toast(context, '操作未完成：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> aiSettings() async {
    final key = await Secrets().read('ai.key');
    if (!mounted) return;
    final data = await editFields(
      context,
      'AI 服务',
      {
        '配置名称': s.value('ai.profileName', '我的阅读助手'),
        '接口根地址（含 /v1）': s.value('ai.endpoint', 'https://api.openai.com/v1'),
        '模型': s.value('ai.model', ''),
        'API 密钥': key,
        '系统提示词': s.value('ai.systemPrompt', '你是阅读助手，引用原文并注明位置，不编造事实。'),
      },
      passwords: {'API 密钥'},
    );
    if (data == null) return;
    secureEndpoint(data['接口根地址（含 /v1）']!, allowLocal: true);
    s.extra.addAll({
      'ai.endpoint': data['接口根地址（含 /v1）'],
      'ai.model': data['模型'],
      'ai.systemPrompt': data['系统提示词'],
    });
    await Secrets().write('ai.key', data['API 密钥']!);
    final providers = await repo.entries('aiProviders');
    final existing = providers
        .where((e) => e['name'] == data['配置名称'])
        .firstOrNull;
    final id =
        existing?['id'] as String? ??
        'ai-${DateTime.now().microsecondsSinceEpoch}';
    await repo.putEntry('aiProviders', {
      'name': data['配置名称'],
      'endpoint': data['接口根地址（含 /v1）'],
      'model': data['模型'],
      'system': data['系统提示词'],
    }, id: id);
    await Secrets().write('ai.provider.$id', data['API 密钥']!);
    s.extra['ai.profileName'] = data['配置名称'];
    await repo.saveSettings(s);
  }

  Future<void> shareLanBackup() async {
    final fields = await editFields(
      context,
      '同一 Wi-Fi 传备份',
      {'备份密码（至少 8 个字符）': ''},
      passwords: {'备份密码（至少 8 个字符）'},
      description: '先加密再传输。请保持此界面打开，在自己的电脑浏览器中输入链接下载；10 分钟后或离开 APP 自动关闭。',
    );
    if (fields == null) return;
    lan ??= LanBackup();
    await lan!.start(await repo.backup(), fields['备份密码（至少 8 个字符）']!);
    try {
      final urls = await lan!.urls();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('在电脑浏览器下载'),
          content: SingleChildScrollView(
            child: SelectableText(
              urls.isEmpty
                  ? '未发现局域网地址，请连接同一 Wi-Fi 后重试。'
                  : '${urls.join('\n\n')}\n\n加密密码不会出现在链接中。最多下载 3 次，关闭此窗口立即停止。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('停止传输'),
            ),
          ],
        ),
      );
    } finally {
      await lan!.stop();
    }
  }

  Future<void> aiProfiles() async {
    final profiles = await repo.entries('aiProviders');
    if (!mounted) return;
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择 AI 服务与模型')),
            for (final p in profiles)
              ListTile(
                title: Text(p['name'] as String),
                subtitle: Text('${p['model']} · ${p['endpoint']}'),
                onTap: () => Navigator.pop(c, p),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('新增配置'),
              onTap: () => Navigator.pop(c, <String, dynamic>{'add': true}),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    if (selected['add'] == true) {
      await aiSettings();
      return;
    }
    s.extra.addAll({
      'ai.endpoint': selected['endpoint'],
      'ai.model': selected['model'],
      'ai.systemPrompt': selected['system'],
      'ai.profileName': selected['name'],
    });
    await Secrets().write(
      'ai.key',
      await Secrets().read('ai.provider.${selected['id']}'),
    );
    await repo.saveSettings(s);
    if (mounted) toast(context, '已切换到 ${selected['name']}');
  }

  Future<void> syncSettings() async {
    final key = await Secrets().read('sync.key');
    if (!mounted) return;
    final data = await editFields(
      context,
      '加密同步配置',
      {
        '后端（webdav/s3/onedrive/dropbox/googledrive）': s.value(
          'sync.provider',
          'webdav',
        ),
        '完整文件地址': s.value('sync.endpoint', ''),
        '账号 / Access Key': s.value('sync.user', ''),
        '密码 / Secret Key': key,
        'S3 区域': s.value('sync.region', 'us-east-1'),
        '云盘文件路径': s.value('sync.path', '/shuye-backup.json'),
        'Google Drive 文件 ID': s.value('sync.fileId', ''),
      },
      passwords: {'密码 / Secret Key'},
    );
    if (data == null) return;
    final provider = data['后端（webdav/s3/onedrive/dropbox/googledrive）'];
    if (![
      'webdav',
      's3',
      'onedrive',
      'dropbox',
      'googledrive',
    ].contains(provider)) {
      throw const FormatException('请填写列出的后端之一');
    }
    if (['webdav', 's3'].contains(provider)) {
      secureEndpoint(data['完整文件地址']!, allowLocal: true);
    }
    s.extra.addAll({
      'sync.provider': provider,
      'sync.endpoint': data['完整文件地址'],
      'sync.user': data['账号 / Access Key'],
      'sync.region': data['S3 区域'],
      'sync.path': data['云盘文件路径'],
      'sync.fileId': data['Google Drive 文件 ID'],
    });
    await Secrets().write('sync.key', data['密码 / Secret Key']!);
    await repo.saveSettings(s);
  }

  Future<void> koReader() async {
    final books = await repo.books(summaries: true);
    if (!mounted) return;
    final chosen = await showModalBottomSheet<Book>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('与 KOReader 同步哪本书？')),
            for (final book in books)
              ListTile(
                title: Text(book.title),
                subtitle: Text(book.format),
                onTap: () => Navigator.pop(c, book),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final book = await repo.book(chosen.id);
    final password = await Secrets().read('ko.password');
    if (!mounted) return;
    final fields = await editFields(
      context,
      'KOReader 进度',
      {
        '服务地址': s.value('ko.endpoint', 'https://sync.koreader.rocks'),
        '用户名': s.value('ko.user', ''),
        '密码': password,
        'KOReader 中的原文件名':
            book.metadata['originalName'] as String? ??
            '${book.title}.${book.format.toLowerCase()}',
        '文档校验值（可留空）': book.metadata['ko.digest'] as String? ?? '',
        '操作（读取 / 上传 PDF）': '读取',
      },
      passwords: {'密码'},
      description: '请在 KOReader 选择“按文件名”匹配；也可填写该书的校验值。文本进度按百分比近似定位，PDF 可双向同步。',
    );
    if (fields == null) return;
    if (!['读取', '上传 PDF'].contains(fields['操作（读取 / 上传 PDF）'])) {
      throw const FormatException('操作请填“读取”或“上传 PDF”');
    }
    secureEndpoint(fields['服务地址']!);
    final document = fields['文档校验值（可留空）']!.isEmpty
        ? KoReaderProgress.filenameDigest(fields['KOReader 中的原文件名']!)
        : fields['文档校验值（可留空）']!;
    final service = KoReaderProgress();
    if (fields['操作（读取 / 上传 PDF）'] == '上传 PDF') {
      await service.uploadPdf(
        fields['服务地址']!,
        fields['用户名']!,
        fields['密码']!,
        document,
        book,
      );
    } else {
      final percent = await service.download(
        fields['服务地址']!,
        fields['用户名']!,
        fields['密码']!,
        document,
      );
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('跳到 ${(percent * 100).round()}%？'),
          content: Text(
            '《${book.title}》当前为 ${(book.progress * 100).round()}%，只调整进度，不替换正文。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('应用进度'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      if (book.format == 'PDF') {
        final count = book.metadata['pdfPages'] as int? ?? 0;
        if (count == 0) throw const FormatException('请先打开这本 PDF，以确认总页数');
        book.metadata['pdfPage'] = 1 + (percent * (count - 1)).round();
        await repo.saveMetadata(book);
      } else {
        var target =
            (book.chapters.fold<int>(0, (n, c) => n + c.text.length) * percent)
                .round();
        for (var i = 0; i < book.chapters.length; i++) {
          if (target <= book.chapters[i].text.length ||
              i == book.chapters.length - 1) {
            book.chapter = i;
            book.offset = target.clamp(0, book.chapters[i].text.length);
            break;
          }
          target -= book.chapters[i].text.length;
        }
        await repo.saveProgress(book);
      }
    }
    book.metadata['ko.digest'] = document;
    await repo.saveMetadata(book);
    s.extra.addAll({'ko.endpoint': fields['服务地址'], 'ko.user': fields['用户名']});
    await Secrets().write('ko.password', fields['密码']!);
    await repo.saveSettings(s);
    if (mounted) toast(context, 'KOReader 进度已同步');
  }

  Future<void> sync(bool download) async {
    final input = await editFields(
      context,
      download ? '下载将替换当前书库，请先备份' : '上传加密书库',
      {'备份加密密码': ''},
      passwords: {'备份加密密码'},
    );
    if (input == null) return;
    await SyncService(
      repo,
      Secrets(),
    ).run(s, download: download, password: input['备份加密密码']!);
    if (mounted) toast(context, download ? '已恢复远端书库' : '已加密上传');
  }

  Future<void> encryptedBackup(bool restore) async {
    final input = await editFields(
      context,
      restore ? '恢复加密备份（替换当前书库）' : '导出加密备份',
      {'备份密码': ''},
      passwords: {'备份密码'},
    );
    if (input == null) return;
    if (restore) {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (picked == null) return;
      final f = picked.files.single;
      if (f.size > 80 * 1024 * 1024) throw const FormatException('备份超过 80 MB');
      await repo.restore(
        await BackupCipher.decrypt(
          await File(f.path!).readAsString(),
          input['备份密码']!,
        ),
      );
    } else {
      await saveBytes(
        'shuye-encrypted-backup.json',
        utf8.encode(
          await BackupCipher.encrypt(await repo.backup(), input['备份密码']!),
        ),
      );
    }
    if (mounted) toast(context, '已完成');
  }

  Future<void> recognize() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image);
    if (picked == null) return;
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(picked.files.single.path!),
      );
      if (!mounted) return;
      final edited = await editFields(context, '识别结果（可修改后保存）', {
        '书名': '图片识字 ${DateTime.now().toString().substring(0, 16)}',
        '正文': result.text,
      });
      if (edited == null || edited['正文']!.isEmpty) return;
      await repo.addBook(
        Book(
          id: 'ocr-${DateTime.now().microsecondsSinceEpoch}',
          title: edited['书名']!,
          format: 'OCR',
          chapters: splitChapters(edited['正文']!, s.chapterPattern),
        ),
      );
      if (mounted) toast(context, '文字已保存到书架');
    } finally {
      await recognizer.close();
    }
  }

  Future<void> importFont() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf', 'ttc'],
    );
    if (picked == null) return;
    final file = picked.files.single;
    if (file.size > 10 * 1024 * 1024) throw const FormatException('字体超过 10 MB');
    final bytes = await File(file.path!).readAsBytes();
    final name = 'user-${DateTime.now().microsecondsSinceEpoch}';
    final loader = FontLoader(name)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    await repo.putEntry('fonts', {
      'name': name,
      'title': file.name,
      'data': base64Encode(bytes),
    });
    s.extra['reader.customFont'] = name;
    await repo.saveSettings(s);
    if (mounted) toast(context, '已启用 ${file.name}');
  }

  Future<void> opds() async {
    final input = await editFields(context, '在线书库 OPDS', {
      '目录地址': s.value('opds.url', ''),
    });
    if (input == null) return;
    final uri = secureEndpoint(input['目录地址']!);
    s.extra['opds.url'] = uri.toString();
    await repo.saveSettings(s);
    final response = await request('GET', uri);
    final entries = parseOpds(utf8.decode(response.bodyBytes), uri);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          children: [
            const ListTile(
              title: Text('在线书库'),
              subtitle: Text('点击下载并导入；支持公开 OPDS 1.x 目录'),
            ),
            for (final e in entries)
              ListTile(
                title: Text(e['title']!),
                subtitle: Text(e['author']!),
                leading: const Icon(Icons.download),
                onTap: () async {
                  try {
                    final url = secureEndpoint(e['url']!);
                    final r = await request('GET', url);
                    final mime = e['type']!;
                    final ext = mime.contains('epub')
                        ? 'epub'
                        : mime.contains('pdf')
                        ? 'pdf'
                        : 'txt';
                    await repo.addBook(
                      parseBook({
                        'name': '${e['title']}.$ext',
                        'bytes': r.bodyBytes,
                        'pattern': s.chapterPattern,
                      }),
                    );
                    if (c.mounted) toast(c, '已导入 ${e['title']}');
                  } catch (e) {
                    if (c.mounted) toast(c, '导入未完成：$e');
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('阅读工具箱')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (busy) const LinearProgressIndicator(),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            '按需启用。正文不会自动上传，服务密钥留在手机安全存储中。',
            style: TextStyle(height: 1.6),
          ),
        ),
        tile(
          Icons.auto_awesome,
          'AI 服务配置',
          '使用自己的服务地址、模型和密钥',
          () => run(aiSettings),
        ),
        tile(
          Icons.chat_bubble_outline,
          '切换 AI 服务与模型',
          '保存多套配置；密钥单独加密保存',
          () => run(aiProfiles),
        ),
        tile(
          Icons.chat_bubble_outline,
          '书库阅读助手',
          '书库概览、阅读建议和计划',
          () => showAiAssistant(context, repo, s),
        ),
        tile(
          Icons.history,
          '书籍修改建议',
          '检查阅读助手或 MCP 提出的修改，再决定是否应用',
          () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => BookProposals(repo: repo)),
          ),
        ),
        tile(
          Icons.history,
          'AI 问答记录',
          '保存在本地，可搜索、编辑和删除',
          () => entries('aiChats', '问答记录', ['question', 'answer']),
        ),
        tile(
          Icons.document_scanner_outlined,
          '图片识字',
          '本地中文识别，校对后加入书架',
          () => run(recognize),
        ),
        tile(
          Icons.headphones,
          '播放有声书',
          '手机音频文件、倍速和定时关闭',
          () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => AudioScreen(repo: repo)),
          ),
        ),
        tile(Icons.language, '在线书库', 'OPDS 公开目录', () => run(opds)),
        tile(
          Icons.font_download_outlined,
          '导入阅读字体',
          'TTF / OTF / TTC',
          () => run(importFont),
        ),
        tile(
          Icons.folder_outlined,
          '主题与规则方案',
          '保存、切换或导入阅读配色与排版规则',
          () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ReadingPresets(repo: repo, settings: s),
            ),
          ),
        ),
        tile(
          Icons.folder_outlined,
          '生词与词典',
          '分组保存生词和释义',
          () => entries('vocabulary', '生词本', ['词语', '释义说明', '分组']),
        ),
        tile(
          Icons.style_outlined,
          '自定义提示词',
          '保存常用阅读指令',
          () => entries('prompts', '提示词', ['名称', '提示词']),
        ),
        tile(
          Icons.cloud_outlined,
          '配置网盘同步',
          'WebDAV、S3 或云盘访问令牌；先加密再上传',
          () => run(syncSettings),
        ),
        tile(
          Icons.cloud_upload_outlined,
          '上传加密书库',
          '手动上传快照，不覆盖手机内容',
          () => run(() => sync(false)),
        ),
        tile(
          Icons.cloud_download_outlined,
          '从网盘恢复',
          '下载并替换当前书库，请先备份',
          () => run(() => sync(true)),
        ),
        tile(
          Icons.receipt_long,
          'KOReader 进度',
          '读取阅读百分比；PDF 可双向同步',
          () => run(koReader),
        ),
        tile(
          Icons.receipt_long,
          '同步记录',
          '查看执行结果',
          () => entries('syncHistory', '同步记录', [
            'at',
            'direction',
            'provider',
            'error',
          ]),
        ),
        tile(
          Icons.lock_outline,
          '导出加密备份',
          'AES-256-GCM；请牢记密码',
          () => run(() => encryptedBackup(false)),
        ),
        tile(
          Icons.lock_open_outlined,
          '恢复加密备份',
          '保留恢复前的备份',
          () => run(() => encryptedBackup(true)),
        ),
        tile(
          Icons.fingerprint,
          '同一 Wi-Fi 传备份',
          '临时传输加密文件到自己的电脑',
          () => run(shareLanBackup),
        ),
        tile(
          Icons.fingerprint,
          s.flag('privacy.lock') ? '关闭书库锁' : '开启书库锁',
          '指纹或手机屏幕锁验证；离开 APP 自动锁定',
          () => run(() async {
            if (await authenticateLibrary()) {
              s.extra['privacy.lock'] = !s.flag('privacy.lock');
              privacyEnabled.value = s.flag('privacy.lock');
              await repo.saveSettings(s);
            }
          }),
        ),
        tile(
          Icons.hub_outlined,
          mcp?.server == null ? '启动 MCP 服务' : '停止 MCP 服务',
          '仅本机；读取书库，资料修改须在 APP 内确认',
          () => run(() async {
            mcp ??= McpService(repo);
            if (mcp!.server != null) {
              await mcp!.stop();
            } else {
              await mcp!.start();
              if (!context.mounted) return;
              if (context.mounted) {
                await showDialog<void>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('本机 MCP 服务'),
                    content: SelectableText(
                      '${mcp!.address}\n\nAuthorization: Bearer ${mcp!.token}\n\n仅在工具箱打开期间运行，离开即关闭。',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('知道了'),
                      ),
                    ],
                  ),
                );
              }
            }
          }),
        ),
        const SizedBox(height: 20),
      ],
    ),
  );
  Widget tile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback action,
  ) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: busy ? null : action,
    ),
  );
  void entries(String kind, String title, List<String> fields) =>
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              EntryScreen(repo: repo, kind: kind, title: title, fields: fields),
        ),
      );
}
