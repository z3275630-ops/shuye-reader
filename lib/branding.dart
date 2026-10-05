import 'package:flutter/material.dart';

import 'appearance.dart';

const shuyeVersion = '0.3.9';
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
  const ShuyeCover({super.key});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: AspectRatio(
      aspectRatio: 4.2,
      child: Image.asset(
        shuyeCoverAsset,
        fit: BoxFit.cover,
        semanticLabel: '白绿叠页与黑色背景',
      ),
    ),
  );
}

class ShuyeIdentityCard extends StatelessWidget {
  const ShuyeIdentityCard({super.key});
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ShuyeCover(),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
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
                          ?.copyWith(fontWeight: FontWeight.w400),
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
      ],
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
        const ShuyeCover(),
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
