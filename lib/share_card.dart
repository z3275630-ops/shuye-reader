import 'app_icons.dart';
import 'appearance.dart';

import 'package:flutter/material.dart';

const shareTemplates = {
  'paper': '插画纸页',
  'night': '夜色摘录',
  'calendar': '日历手记',
  'minimal': '简洁留白',
};

class QuoteCard extends StatelessWidget {
  final String quote, title, template;
  final int art;
  final DateTime? date;
  const QuoteCard({
    super.key,
    required this.quote,
    required this.title,
    this.template = 'paper',
    this.art = 0,
    this.date,
  });
  @override
  Widget build(BuildContext context) {
    final dark = template == 'night';
    final colors = applicationTheme(dark ? Brightness.dark : Brightness.light)
        .colorScheme;
    final fg = colors.onSurface;
    final accent = colors.primary;
    final now = date ?? DateTime.now();
    final text = String.fromCharCodes(quote.runes.take(800));
    return Container(
      width: 360,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: dark
            ? ShuyeStyle.darkCanvas
            : template == 'minimal'
            ? Colors.white
            : ShuyeStyle.canvas,
        image: template == 'paper'
            ? DecorationImage(
                image: AssetImage(
                  [
                    'assets/art/mountain.webp',
                    'assets/art/poetry.webp',
                    'assets/art/notebook.webp',
                  ][art.clamp(0, 2)],
                ),
                fit: BoxFit.cover,
                opacity: .13,
              )
            : null,
        border: template == 'minimal'
            ? Border.all(color: colors.outlineVariant)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (template == 'calendar') ...[
            Text(
              '${now.day}'.padLeft(2, '0'),
              style: TextStyle(
                color: fg,
                fontSize: 58,
                height: 1,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${now.year} / ${now.month.toString().padLeft(2, '0')}',
              style: TextStyle(color: accent, fontSize: 12, letterSpacing: 2),
            ),
            const SizedBox(height: 24),
            Divider(color: accent.withValues(alpha: .4)),
          ] else
            ShuyeIcon(Icons.format_quote, color: accent, size: 36),
          const SizedBox(height: 20),
          Text(text, style: TextStyle(fontSize: 18, height: 1.8, color: fg)),
          if (quote.runes.length > 800) ...[
            const SizedBox(height: 12),
            Text(
              '…（长摘录仅展示前 800 字）',
              style: TextStyle(fontSize: 10, color: accent),
            ),
          ],
          const SizedBox(height: 32),
          Text('— $title', style: TextStyle(fontSize: 12, color: accent)),
          const SizedBox(height: 8),
          Text(
            '书叶 · 把喜欢的文字留在身边',
            style: TextStyle(fontSize: 10, color: accent),
          ),
        ],
      ),
    );
  }
}
