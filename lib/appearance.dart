import 'package:flutter/material.dart';

import 'models.dart';

class AppAppearance {
  final String mode;
  final double scale;
  const AppAppearance({this.mode = 'system', this.scale = 1});
  factory AppAppearance.fromSettings(ReaderSettings s) => AppAppearance(
    mode: s.value('app.themeMode', 'system'),
    scale: s.number('app.textScale', 1).clamp(.85, 1.5),
  );
  ThemeMode get themeMode => switch (mode) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };
  @override
  bool operator ==(Object other) =>
      other is AppAppearance && other.mode == mode && other.scale == scale;
  @override
  int get hashCode => Object.hash(mode, scale);
}

final appAppearance = ValueNotifier(const AppAppearance());

ThemeData applicationTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xff58735f),
    brightness: brightness,
    surface: dark ? const Color(0xff171d19) : const Color(0xfff7f6f1),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: dark ? colors.surfaceContainer : Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? colors.surfaceContainerHigh : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

Future<void> configureAppearance(
  BuildContext context,
  ReaderSettings settings,
  Future<void> Function() save,
) async {
  String? error;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('应用外观', style: Theme.of(c).textTheme.headlineSmall),
              const SizedBox(height: 12),
              const Text('调整界面配色和文字；正文仍使用自己的阅读纸色。'),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in {
                    'system': '跟随系统',
                    'light': '浅色',
                    'dark': '深色',
                  }.entries)
                    ChoiceChip(
                      label: Text(option.value),
                      selected:
                          settings.value('app.themeMode', 'system') ==
                          option.key,
                      onSelected: (_) async {
                        settings.extra['app.themeMode'] = option.key;
                        appAppearance.value = AppAppearance.fromSettings(
                          settings,
                        );
                        set(() {});
                        try {
                          await save();
                        } catch (_) {
                          if (c.mounted) set(() => error = '保存失败，请重试。');
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                '界面文字大小 ${(settings.number('app.textScale', 1) * 100).round()}%',
              ),
              Slider(
                min: .85,
                max: 1.5,
                divisions: 13,
                value: settings.number('app.textScale', 1).clamp(.85, 1.5),
                onChanged: (v) {
                  settings.extra['app.textScale'] = v;
                  appAppearance.value = AppAppearance.fromSettings(settings);
                  set(() {});
                },
                onChangeEnd: (_) async {
                  try {
                    await save();
                  } catch (_) {
                    if (c.mounted) set(() => error = '保存失败，请重试。');
                  }
                },
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(c).colorScheme.error),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
