import 'package:flutter/material.dart';

import 'models.dart';
import 'theme_mist.dart';

/// 可选的界面配色。`claude` 是原本的暖白纸面，`mist` 是新增的冷调海雾。
/// 正文阅读纸色是独立设置，不随这里切换。
const appThemes = <String, String>{'claude': '暖白', 'mist': '海雾'};

String appThemeId(String id) => appThemes.containsKey(id) ? id : 'claude';

class AppAppearance {
  final String mode;
  final String theme;
  final double scale;
  const AppAppearance({
    this.mode = 'system',
    this.theme = 'claude',
    this.scale = 1,
  });
  factory AppAppearance.fromSettings(ReaderSettings s) => AppAppearance(
    mode: s.value('app.themeMode', 'system'),
    theme: appThemeId(s.value('app.theme', 'claude')),
    scale: s.number('app.textScale', 1).clamp(.85, 1.5),
  );
  ThemeMode get themeMode => switch (mode) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };
  @override
  bool operator ==(Object other) =>
      other is AppAppearance &&
      other.mode == mode &&
      other.theme == theme &&
      other.scale == scale;
  @override
  int get hashCode => Object.hash(mode, theme, scale);
}

final appAppearance = ValueNotifier(const AppAppearance());

// Preserve Android's size-dependent accessibility scaling, then apply the
// user's app preference. Sampling scale(1) turns nonlinear scaling into a
// single, potentially much larger multiplier for headings.
class ApplicationTextScaler extends TextScaler {
  final TextScaler system;
  final double multiplier;
  const ApplicationTextScaler(this.system, this.multiplier);
  @override
  double scale(double fontSize) => system.scale(fontSize) * multiplier;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is ApplicationTextScaler &&
      other.system == system &&
      other.multiplier == multiplier;
  @override
  int get hashCode => Object.hash(system, multiplier);
}

// Mobile reader adaptation. Keep the palette and geometry in one place;
// reader paper, imported fonts and cover artwork have their own settings.
abstract final class ShuyeStyle {
  static const fontFamily = 'ShuyeSerif';
  static const readerAlignment = TextAlign.justify;
  static const canvas = Color(0xfffaf9f5);
  static const darkCanvas = Color(0xff1f1f1e);
  static const clay = Color(0xffd97757);
  static const controlRadius = 12.0;
  static const cardRadius = 16.0;
  static const sheetRadius = 24.0;
  static const panelTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w400,
    height: 1.3,
    letterSpacing: 0,
  );
  static const controlMotion = Duration(milliseconds: 100);
}

AnimationStyle applicationMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? AnimationStyle.noAnimation
    : const AnimationStyle(
        duration: Duration(milliseconds: 200),
        reverseDuration: Duration(milliseconds: 150),
      );

final _themes = <String, ThemeData>{};

/// 按配色与明暗分别缓存，切换主题时不必重建整套控件样式。
/// 配色取自 [appAppearance]，调用点（`MaterialApp`）已经监听它，
/// 因此用户改配色后重建会自然拿到新的 ThemeData。
ThemeData applicationTheme(Brightness brightness) {
  final id = appThemeId(appAppearance.value.theme);
  return _themes.putIfAbsent(
    '$id:${brightness.name}',
    () => _buildApplicationTheme(
      brightness,
      id == 'mist' ? mistColorScheme(brightness) : null,
    ),
  );
}

ThemeData _buildApplicationTheme(Brightness brightness, [ColorScheme? scheme]) {
  final dark = brightness == Brightness.dark;
  final colors =
      scheme ??
      ColorScheme.fromSeed(
        seedColor: ShuyeStyle.clay,
        brightness: brightness,
        surface: dark ? ShuyeStyle.darkCanvas : ShuyeStyle.canvas,
      ).copyWith(
        primary: dark ? const Color(0xffe5aa92) : const Color(0xff99513b),
        onPrimary: dark ? const Color(0xff262624) : Colors.white,
        primaryContainer: dark
            ? const Color(0xff45362f)
            : const Color(0xfff1e4db),
        onPrimaryContainer: dark
            ? const Color(0xfff0d3c6)
            : const Color(0xff56362a),
        secondary: dark ? const Color(0xffc2c0b6) : const Color(0xff57564f),
        // Warm focus; use the deeper clay to preserve text contrast as well.
        tertiary: dark ? const Color(0xffe5aa92) : const Color(0xff99513b),
        onTertiary: dark ? const Color(0xff121212) : Colors.white,
        onSecondary: dark ? const Color(0xff262624) : Colors.white,
        secondaryContainer: dark
            ? const Color(0xff3d3d38)
            : const Color(0xffeae9e2),
        onSecondaryContainer: dark
            ? ShuyeStyle.canvas
            : const Color(0xff30302e),
        surfaceContainerLowest: dark ? const Color(0xff171716) : Colors.white,
        surfaceContainerLow: dark
            ? const Color(0xff242422)
            : const Color(0xfff0efe9),
        surfaceContainer: dark
            ? const Color(0xff2c2c2a)
            : const Color(0xffefeee5),
        surfaceContainerHigh: dark
            ? const Color(0xff363632)
            : const Color(0xffeae9e2),
        surfaceContainerHighest: dark
            ? const Color(0xff40403b)
            : const Color(0xffe2e1d8),
        onSurface: dark ? ShuyeStyle.canvas : const Color(0xff22221f),
        onSurfaceVariant: dark
            ? const Color(0xffc2c0b6)
            : const Color(0xff626057),
        outline: dark ? const Color(0xff929088) : const Color(0xff87857d),
        // Light hairlines sit on a much brighter canvas than the dark ones, so
        // #d6d4cb only reached 1.41:1 there while the dark value reaches 2.03:1
        // against #1f1f1e. The documented strategy layers with 0.5-0.7dp lines
        // instead of shadows, so give the light side a comparable weight.
        outlineVariant: dark
            ? const Color(0xff50504a)
            : const Color(0xffc5c2b6),
        inverseSurface: dark ? ShuyeStyle.canvas : const Color(0xff30302e),
        onInverseSurface: dark ? const Color(0xff262624) : ShuyeStyle.canvas,
        surfaceTint: Colors.transparent,
      );
  final panel = dark ? colors.surfaceContainer : colors.surface;
  final border = colors.outlineVariant;
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(ShuyeStyle.controlRadius),
  );
  final text = ThemeData(brightness: brightness).textTheme.apply(
    fontFamily: ShuyeStyle.fontFamily,
    bodyColor: colors.onSurface,
    displayColor: colors.onSurface,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: ShuyeStyle.fontFamily,
    fontFamilyFallback: const ['serif'],
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    textTheme: text.copyWith(
      headlineLarge: text.headlineLarge?.copyWith(
        fontFamily: ShuyeStyle.fontFamily,
        fontSize: 34,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      headlineMedium: text.headlineMedium?.copyWith(
        fontFamily: ShuyeStyle.fontFamily,
        fontSize: 28,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontFamily: ShuyeStyle.fontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w400,
        height: 1.35,
        letterSpacing: 0,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      bodyLarge: text.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.5,
        letterSpacing: 0,
      ),
      bodyMedium: text.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.5,
        letterSpacing: 0,
      ),
      bodySmall: text.bodySmall?.copyWith(
        fontSize: 13,
        height: 1.5,
        letterSpacing: .2,
      ),
      labelLarge: text.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
    ),
    iconTheme: IconThemeData(size: 23, color: colors.onSurface),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.tertiary,
      selectionHandleColor: colors.tertiary,
      selectionColor: colors.tertiary.withValues(alpha: .2),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: ShuyeStyle.fontFamily,
        color: colors.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w400,
      ),
    ),
    cardTheme: CardThemeData(
      color: colors.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShuyeStyle.cardRadius),
        side: BorderSide(color: border.withValues(alpha: .6), width: .5),
      ),
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 74,
      backgroundColor: colors.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colors.secondaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShuyeStyle.controlRadius),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: ShuyeStyle.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? colors.onSurface
              : colors.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 23,
          color: states.contains(WidgetState.selected)
              ? colors.onSurface
              : colors.onSurfaceVariant,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShuyeStyle.sheetRadius),
        side: BorderSide(color: border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      titleTextStyle: TextStyle(
        fontFamily: ShuyeStyle.fontFamily,
        color: colors.onSurface,
        fontSize: 19,
        fontWeight: FontWeight.w400,
      ),
      contentTextStyle: TextStyle(
        fontFamily: ShuyeStyle.fontFamily,
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
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShuyeStyle.sheetRadius),
        ),
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
        fontFamily: ShuyeStyle.fontFamily,
        fontSize: 14,
        color: colors.onSurface,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colors.onSurface,
      horizontalTitleGap: 14,
      minLeadingWidth: 24,
      titleTextStyle: TextStyle(
        fontFamily: ShuyeStyle.fontFamily,
        color: colors.onSurface,
        fontSize: 15,
        height: 1.35,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: ShuyeStyle.fontFamily,
        color: colors.onSurfaceVariant,
        fontSize: 13,
        height: 1.45,
        letterSpacing: .2,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 44),
        backgroundColor: colors.onSurface,
        foregroundColor: colors.surface,
        overlayColor: colors.surface,
        animationDuration: ShuyeStyle.controlMotion,
        splashFactory: NoSplash.splashFactory,
        shape: buttonShape,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 44),
        foregroundColor: colors.onSurface,
        overlayColor: colors.onSurface,
        animationDuration: ShuyeStyle.controlMotion,
        splashFactory: NoSplash.splashFactory,
        shape: buttonShape,
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        foregroundColor: colors.onSurface,
        overlayColor: colors.onSurface,
        animationDuration: ShuyeStyle.controlMotion,
        splashFactory: NoSplash.splashFactory,
        shape: buttonShape,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: panel,
      selectedColor: colors.secondaryContainer,
      side: BorderSide(color: colors.outlineVariant),
      labelStyle: TextStyle(
        fontFamily: ShuyeStyle.fontFamily,
        fontSize: 14,
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
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
      elevation: 0,
      highlightElevation: 0,
      shape: buttonShape,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(buttonShape),
        side: WidgetStatePropertyAll(BorderSide(color: border)),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: colors.onSurface,
      inactiveTrackColor: colors.surfaceContainerHighest,
      thumbColor: colors.onSurface,
      trackHeight: 3,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) &&
                !states.contains(WidgetState.disabled)
            ? colors.onSurface
            : null,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) &&
                !states.contains(WidgetState.disabled)
            ? colors.surface
            : null,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) &&
                !states.contains(WidgetState.disabled)
            ? colors.onSurface
            : null,
      ),
      checkColor: WidgetStatePropertyAll(colors.surface),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(
        fontFamily: ShuyeStyle.fontFamily,
        color: colors.onInverseSurface,
        fontSize: 12,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      floatingLabelBehavior: FloatingLabelBehavior.never,
      filled: true,
      fillColor: panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(
        fontFamily: ShuyeStyle.fontFamily,
        color: colors.onSurfaceVariant,
        fontSize: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShuyeStyle.controlRadius),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShuyeStyle.controlRadius),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShuyeStyle.controlRadius),
        borderSide: BorderSide(color: colors.tertiary),
      ),
    ),
  );
}

class SettingSlider extends StatelessWidget {
  final String title, displayValue;
  final double value, min, max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  const SettingSlider({
    super.key,
    required this.title,
    required this.displayValue,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              displayValue,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        label: displayValue,
        semanticFormatterCallback: (_) => '$title，$displayValue',
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    ],
  );
}

class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
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
    sheetAnimationStyle: applicationMotion(context),
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
              Text('应用外观', style: ShuyeStyle.panelTitle),
              const SizedBox(height: 12),
              const Text('调整界面配色和文字；正文仍使用自己的阅读纸色。'),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '给自己，一页安静。',
                        style: Theme.of(c).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '书名、正文与按钮，按你舒服的大小显示。',
                        style: Theme.of(c).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('界面配色', style: Theme.of(c).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in appThemes.entries)
                    ChoiceChip(
                      label: Text(option.value),
                      selected:
                          appThemeId(settings.value('app.theme', 'claude')) ==
                          option.key,
                      onSelected: (_) async {
                        settings.extra['app.theme'] = option.key;
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
              const SizedBox(height: 16),
              Text('明暗', style: Theme.of(c).textTheme.titleMedium),
              const SizedBox(height: 8),
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
              SettingSlider(
                title: '界面文字大小',
                displayValue:
                    '${(settings.number('app.textScale', 1) * 100).round()}%',
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
