import 'preview_fonts.dart';

import 'package:shuye_reader/form_field.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuye_reader/app_icons.dart';
import 'package:shuye_reader/appearance.dart';

const examples = <IconData>[
  Icons.home,
  Icons.auto_stories,
  Icons.bookmarks,
  Icons.bar_chart,
  Icons.tune,
  Icons.search,
  Icons.folder_outlined,
  Icons.edit_outlined,
  Icons.ios_share,
  Icons.delete_outline,
  Icons.headphones,
  Icons.cloud_download_outlined,
  Icons.cloud_upload_outlined,
  Icons.lock_outline,
  Icons.fingerprint,
  Icons.palette_outlined,
  Icons.translate,
  Icons.auto_awesome,
  Icons.document_scanner_outlined,
  Icons.grid_view_rounded,
  Icons.photo_outlined,
  Icons.info_outline,
  Icons.people_outline,
  Icons.handyman_outlined,
  Icons.account_tree_outlined,
];

class DesignHarness extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> save;
  const DesignHarness({
    super.key,
    required this.controller,
    required this.save,
  });
  @override
  State<DesignHarness> createState() => _DesignHarnessState();
}

class _DesignHarnessState extends State<DesignHarness> {
  var selected = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('书叶'),
      leading: const ShuyeIcon(Icons.arrow_back, semanticLabel: '返回'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('轻一点，读久一点。', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 23,
              runSpacing: 22,
              children: [
                for (final icon in examples) ShuyeIcon(icon, size: 24),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('本月'),
              selected: true,
              onSelected: (_) {},
            ),
            ChoiceChip(
              label: const Text('全年'),
              selected: false,
              onSelected: (_) {},
            ),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const ShuyeIcon(Icons.auto_stories),
                title: const Text('阅读设置'),
                subtitle: const Text('字体、纸色与排版'),
                trailing: const ShuyeIcon(Icons.chevron_right),
              ),
              ListTile(
                leading: const ShuyeIcon(Icons.edit_outlined),
                title: const Text('编辑书籍'),
                subtitle: const Text('书名和作者'),
                trailing: const ShuyeIcon(Icons.chevron_right),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (c) => AlertDialog(
                    scrollable: true,
                    title: const Text('编辑书籍'),
                    content: LabeledField(
                      label: '书名',
                      child: TextField(
                        controller: widget.controller,
                        decoration: const InputDecoration(),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () {
                          widget.save(widget.controller.text);
                          Navigator.pop(c);
                        },
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () {},
          icon: const ShuyeIcon(Icons.add),
          label: const Text('导入书籍'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () {}, child: const Text('查看阅读记录')),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: selected,
      onDestinationSelected: (v) => setState(() => selected = v),
      destinations: const [
        NavigationDestination(icon: ShuyeIcon(Icons.home), label: '首页'),
        NavigationDestination(icon: ShuyeIcon(Icons.auto_stories), label: '书架'),
        NavigationDestination(icon: ShuyeIcon(Icons.bookmarks), label: '笔记'),
        NavigationDestination(icon: ShuyeIcon(Icons.bar_chart), label: '统计'),
        NavigationDestination(icon: ShuyeIcon(Icons.tune), label: '设置'),
      ],
    ),
  );
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'shared chrome keeps navigation, labels and dialog input usable: $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        String? saved;
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: applicationTheme(brightness),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: DesignHarness(controller: controller, save: (v) => saved = v),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in ['本月', '全年']) {
          final text = tester.renderObject<RenderParagraph>(find.text(label));
          final luminance = text.text.style!.color!.computeLuminance();
          expect(
            luminance,
            brightness == Brightness.light ? lessThan(.4) : greaterThan(.4),
          );
        }
        expect(find.bySemanticsLabel('返回'), findsOneWidget);
        final leading = find.descendant(
          of: find.bySemanticsLabel('返回'),
          matching: find.byType(CustomPaint),
        );
        expect(tester.getSize(leading).width, lessThanOrEqualTo(24));
        expect(tester.getSize(leading).height, tester.getSize(leading).width);
        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          4,
        );
        await tester.ensureVisible(find.text('编辑书籍'));
        await tester.tap(find.text('编辑书籍'));
        await tester.pumpAndSettle();
        final labelBefore = tester.getRect(find.text('书名'));
        final fieldBefore = tester.getRect(find.byType(TextField));
        expect(labelBefore.left, closeTo(fieldBefore.left, .1));
        expect(fieldBefore.top - labelBefore.bottom, closeTo(8, .1));
        expect(
          tester.getSemantics(find.byType(EditableText)).label,
          contains('书名'),
        );
        await tester.enterText(find.byType(TextField), '山间来信');
        await tester.pumpAndSettle();
        final labelAfter = tester.getRect(find.text('书名'));
        final fieldAfter = tester.getRect(find.byType(TextField));
        expect(labelAfter.left, closeTo(fieldAfter.left, .1));
        expect(fieldAfter.top - labelAfter.bottom, closeTo(8, .1));
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        expect(saved, '山间来信');
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
      },
    );
  }

  final output = Platform.environment['SHUYE_CAPTURE_DIR'];
  testWidgets('capture shared icon and dialog previews', (tester) async {
    await loadShuyeSerif(tester);
    final font = FontLoader('Roboto')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            (await tester.runAsync(
              () =>
                  File(Platform.environment['SHUYE_PREVIEW_FONT']!)
                      .readAsBytes(),
            ))!,
          ),
        ),
      );
    await font.load();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController(text: '山间来信');
    addTearDown(controller.dispose);
    for (final brightness in Brightness.values) {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: applicationTheme(brightness),
            home: DesignHarness(controller: controller, save: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output!).create(recursive: true);
          await File('$output/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      final suffix = brightness == Brightness.dark ? 'dark' : 'light';
      await capture('ui-icons-$suffix');
      await tester.tap(find.text('编辑书籍'));
      await tester.pumpAndSettle();
      await capture('ui-dialog-$suffix');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  }, skip: output == null);
}
