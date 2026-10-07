import 'package:flutter/material.dart';

import 'appearance.dart';
import 'brand_illustration.dart';
import 'editorial_art.dart';

const shuyeVersion = '0.3.15';
const shuyeCoverAsset = 'assets/art/shuye-cover.webp';
const shuyeMarkAsset = 'assets/art/shuye-mark.webp';

class ShuyeMark extends StatelessWidget {
  final double size;
  const ShuyeMark({super.key, this.size = 48});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .22),
    child: Image.asset(
      shuyeMarkAsset,
      width: size,
      height: size,
      fit: BoxFit.cover,
      semanticLabel: '书叶',
    ),
  );
}

class ShuyeCover extends StatelessWidget {
  final EditorialScene scene;
  const ShuyeCover({super.key, this.scene = EditorialScene.library});
  @override
  Widget build(BuildContext context) => Semantics(
    label: scene == EditorialScene.library ? '书架上的书' : '阅读旅程',
    image: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(ShuyeStyle.cardRadius),
      ),
      child: AspectRatio(
        aspectRatio: 4.2,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Center(child: EditorialArt(scene, width: 170, height: 100)),
        ),
      ),
    ),
  );
}

/// The homepage uses real text next to the concept art, rather than a screenshot
/// of a homepage. Large text and narrow windows give the title the full width.
class ShuyeWelcomeCard extends StatelessWidget {
  final String subtitle;
  const ShuyeWelcomeCard({super.key, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(ShuyeStyle.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 225 ||
                MediaQuery.textScalerOf(context).scale(22) > 27;
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '给自己，\n一页安静。',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontFamily: ShuyeStyle.readerFontFamily,
                    fontWeight: FontWeight.w400,
                    fontSize: 22,
                    height: 1.35,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            );
            return stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      const SizedBox(height: 6),
                      const Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: ShuyeBookLeaf(width: 126, height: 74),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 8),
                      ShuyeBookLeaf(
                        width: constraints.maxWidth < 285 ? 92 : 124,
                        height: 106,
                      ),
                    ],
                  );
          },
        ),
      ),
    );
  }
}

class ShuyeIdentityCard extends StatelessWidget {
  const ShuyeIdentityCard({super.key});
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            const ShuyeMark(size: 42),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '书叶',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '一本书，一段属于自己的时间。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void showShuyeAbout(BuildContext context) => showDialog<void>(
  context: context,
  animationStyle: applicationMotion(context),
  builder: (dialogContext) => AlertDialog(
    scrollable: true,
    title: Row(
      children: [
        const ShuyeMark(),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('书叶'),
            Text(
              shuyeVersion,
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ShuyeCover(scene: EditorialScene.balance),
        const SizedBox(height: 16),
        Text(
          '一本书，一段属于自己的时间。',
          style: Theme.of(dialogContext).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        const Text(
          '阅读、听书、摘录与记录阅读足迹。\n书籍和笔记保存在本机，记得定期备份。',
          style: TextStyle(height: 1.7),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => showLicensePage(
          context: dialogContext,
          applicationName: '书叶',
          applicationVersion: shuyeVersion,
          applicationIcon: const ShuyeMark(),
        ),
        child: const Text('开源许可'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('关闭'),
      ),
    ],
  ),
);
