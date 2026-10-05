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

// Claude-style design tokens: the single source of truth for the app chrome.
// Spelling, rationale and usage rules live in DESIGN.md at the repository root.
const claudeInk = Color(0xff141413);
const claudeBody = Color(0xff3d3d3a);
const claudeMuted = Color(0xff73726c);
const claudePlaceholder = Color(0xff9c9a92);
const claudeHairline = Color(0xffc2c0b6);
const claudeHairlineSoft = Color(0xffe3e1d8);
const claudeCanvas = Color(0xfffaf9f5);
const claudeCard = Color(0xffffffff);
const claudeFill = Color(0xfff0efe9);
const claudeAccent = Color(0xffd97757);
const claudeAccentContainer = Color(0xfff5e3db);
const claudeAccentDeep = Color(0xff9c4a2e);
const claudeNight = Color(0xff0b0b0b);
const claudeNightElevated = Color(0xff1e1e1e);
const claudeOnNight = Color(0xfff5f4ee);
const claudeOnNightMuted = Color(0xff98989d);

final _themes = <Brightness, ThemeData>{};
ThemeData applicationTheme(Brightness brightness) =>
    _themes.putIfAbsent(brightness, () => _buildApplicationTheme(brightness));

ThemeData _buildApplicationTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  // Ink is the interactive color in Claude's system: near-black buttons on the
  // cream canvas, near-white buttons at night. Terracotta stays the only
  // chromatic accent and is reserved for selection and brand moments.
  final colors = dark
      ? const ColorScheme.dark(
          primary: claudeOnNight,
          onPrimary: claudeNight,
          primaryContainer: Color(0xff2a2a28),
          onPrimaryContainer: claudeOnNight,
          secondary: claudeOnNightMuted,
          onSecondary: claudeNight,
          secondaryContainer: Color(0xff2a2a28),
          onSecondaryContainer: claudeOnNight,
          tertiary: claudeAccent,
          onTertiary: Color(0xffffffff),
          tertiaryContainer: Color(0xff5a3527),
          onTertiaryContainer: claudeAccentContainer,
          error: Color(0xfff2b8b5),
          onError: Color(0xff601410),
          errorContainer: Color(0xff8c1d18),
          onErrorContainer: Color(0xfff9dedc),
          surface: claudeNight,
          onSurface: claudeOnNight,
          onSurfaceVariant: claudeOnNightMuted,
          surfaceContainerLowest: Color(0xff000000),
          surfaceContainerLow: claudeNightElevated,
          surfaceContainer: claudeNightElevated,
          surfaceContainerHigh: Color(0xff262626),
          surfaceContainerHighest: Color(0xff2e2e2c),
          outline: Color(0xff3a3a38),
          outlineVariant: Color(0xff2a2a28),
          shadow: Color(0xff000000),
          scrim: Color(0xff000000),
          inverseSurface: claudeOnNight,
          onInverseSurface: claudeNightElevated,
          inversePrimary: claudeInk,
        )
      : const ColorScheme.light(
          primary: claudeInk,
          onPrimary: Color(0xffffffff),
          primaryContainer: claudeFill,
          onPrimaryContainer: claudeInk,
          secondary: claudeMuted,
          onSecondary: Color(0xffffffff),
          secondaryContainer: claudeFill,
          onSecondaryContainer: claudeBody,
          tertiary: claudeAccent,
          onTertiary: Color(0xffffffff),
          tertiaryContainer: claudeAccentContainer,
          onTertiaryContainer: claudeAccentDeep,
          error: Color(0xffb3261e),
          onError: Color(0xffffffff),
          errorContainer: Color(0xfff9dedc),
          onErrorContainer: Color(0xff410e0b),
          surface: claudeCanvas,
          onSurface: claudeInk,
          onSurfaceVariant: claudeMuted,
          surfaceContainerLowest: claudeCard,
          surfaceContainerLow: claudeCard,
          surfaceContainer: claudeFill,
          surfaceContainerHigh: claudeFill,
          surfaceContainerHighest: Color(0xffe9e7df),
          outline: claudeHairline,
          outlineVariant: claudeHairlineSoft,
          shadow: Color(0xff000000),
          scrim: Color(0xff000000),
          inverseSurface: claudeNightElevated,
          onInverseSurface: claudeOnNight,
          inversePrimary: claudeAccent,
        );
  // Radius grows with element size: 8 controls, 10 inputs, 16 cards, 24 sheets.
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
  );
  final text = ThemeData(brightness: brightness).textTheme
      .apply(bodyColor: colors.onSurface, displayColor: colors.onSurface);
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    // Serif at light weights carries headings; the lightness is the point.
    textTheme: text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(
        fontFamily: 'serif',
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      headlineMedium: text.headlineMedium?.copyWith(
        fontFamily: 'serif',
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontFamily: 'serif',
        fontSize: 20,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.5, letterSpacing: 0),
      bodySmall: text.bodySmall?.copyWith(
        height: 1.5,
        color: colors.onSurfaceVariant,
      ),
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
        fontFamily: 'serif',
        color: colors.onSurface,
        fontSize: 19,
        fontWeight: FontWeight.w400,
      ),
    ),
    cardTheme: CardThemeData(
      color: colors.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 74,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colors.surfaceContainerHigh,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'Roboto',
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w500
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
      backgroundColor: colors.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      titleTextStyle: TextStyle(
        fontFamily: 'serif',
        color: colors.onSurface,
        fontSize: 19,
        fontWeight: FontWeight.w400,
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
      backgroundColor: colors.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      dragHandleSize: const Size(32, 3),
      dragHandleColor: colors.outline,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
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
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: buttonShape,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: buttonShape,
        side: BorderSide(color: colors.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: buttonShape,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 0,
    ),
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant,
      thickness: .7,
      space: 20,
    ),
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
      floatingLabelBehavior: FloatingLabelBehavior.never,
      filled: true,
      fillColor: dark ? colors.surfaceContainerHigh : claudeCard,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(
        fontFamily: 'Roboto',
        color: claudePlaceholder,
        fontSize: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
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
