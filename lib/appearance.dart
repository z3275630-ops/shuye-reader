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

final _themes = <Brightness, ThemeData>{};
ThemeData applicationTheme(Brightness brightness) =>
    _themes.putIfAbsent(brightness, () => _buildApplicationTheme(brightness));

ThemeData _buildApplicationTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xff58735f),
    brightness: brightness,
    surface: dark ? const Color(0xff171d19) : const Color(0xfff7f6f1),
  );
  final panel = dark ? colors.surfaceContainer : Colors.white;
  final border = colors.outlineVariant.withValues(alpha: .45);
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );
  final text = ThemeData(brightness: brightness).textTheme
      .apply(bodyColor: colors.onSurface, displayColor: colors.onSurface);
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.45, letterSpacing: 0),
      labelLarge: text.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
    ),
    iconTheme: IconThemeData(size: 22, color: colors.onSurfaceVariant),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: colors.onSurface,
        fontSize: 19,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 74,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colors.secondaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'Roboto',
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : colors.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 23,
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : colors.onSurfaceVariant,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: colors.onSurface,
        fontSize: 19,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: colors.onSurfaceVariant,
        fontSize: 14,
        height: 1.55,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      dragHandleSize: const Size(32, 3),
      dragHandleColor: colors.outlineVariant,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: panel,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
      textStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 14,
        color: colors.onSurface,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colors.onSurfaceVariant,
      horizontalTitleGap: 14,
      minLeadingWidth: 24,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: colors.onSurface,
        fontSize: 15,
        height: 1.35,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: colors.onSurfaceVariant,
        fontSize: 12,
        height: 1.45,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 44),
        shape: buttonShape,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 44),
        shape: buttonShape,
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: buttonShape,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: colors.outlineVariant),
      labelStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 13,
        color: colors.onSurface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
    ),
    dividerTheme: DividerThemeData(color: border, thickness: .7, space: 20),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.primary),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(
        fontFamily: 'Roboto',
        color: colors.onInverseSurface,
        fontSize: 12,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? colors.surfaceContainerHigh : colors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(
        fontFamily: 'Roboto',
        color: colors.onSurfaceVariant,
        fontSize: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.primary),
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
