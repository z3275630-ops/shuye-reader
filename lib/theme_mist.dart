import 'package:flutter/material.dart';

/// 海雾配色：书叶的第二套可选主题。
///
/// 色相取自 Tidal_Echo（AGPL-3.0）默认预设的语义令牌——冷白画布 `#F7FAFC`、
/// 深钢笔蓝墨 `#253447`、单一低饱和灰蓝强调 `#4C6378`、实心动作块 `#2C4056`，
/// 以及只差一级明度的表面阶梯（`#EEF4FA` / `#ECEEF3` / `#DFE5EE`）。
/// 只借鉴配色关系与排版思路，未复制该项目任何代码。它只有浅色预设，
/// 这里的深色一套是按同一冷调色相自行推导的。
///
/// 两处刻意偏离，都是为了让纯色底、无壁纸、无毛玻璃的书叶仍然成立：
/// - 它的卡片与输入底是给照片准备的半透明层（`rgba(244,248,250,.42)`），
///   合成到纯色面上与底色只差 1/255，等于看不见；这里换成本色板的实色阶梯，
///   相邻层仍只差一级明度（1.06 / 1.11 / 1.21），保留那种“几乎看不出来”的层次。
/// - 它的发丝线只有 1.27:1（靠照片压住可读性），纯色底上太弱，提到约 1.6:1，
///   与暖白主题的发丝线（1.69:1）保持相当的分量。
///
/// 正文 12.1:1、二级墨 5.6:1（在最强表面层上仍有 4.6:1）、强调 6.0:1，
/// 均在 WCAG AA 之上；二级墨刻意比正文浅一档，三级信息才用更弱的 `outline`。
ColorScheme mistColorScheme(Brightness brightness) =>
    brightness == Brightness.dark ? _mistDark() : _mistLight();

const _mistSeed = Color(0xff4c6378);

ColorScheme _mistLight() =>
    ColorScheme.fromSeed(
      seedColor: _mistSeed,
      brightness: Brightness.light,
      surface: const Color(0xfff7fafc),
    ).copyWith(
      primary: const Color(0xff2c4056),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xffdfe5ee),
      onPrimaryContainer: const Color(0xff253447),
      secondary: const Color(0xff4c6378),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xffeceef3),
      onSecondaryContainer: const Color(0xff253447),
      tertiary: const Color(0xff4c6378),
      onTertiary: Colors.white,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xfff2f7fb),
      surfaceContainer: const Color(0xffeef4fa),
      surfaceContainerHigh: const Color(0xffe9eff6),
      surfaceContainerHighest: const Color(0xffe3eaf2),
      onSurface: const Color(0xff253447),
      onSurfaceVariant: const Color(0xff556779),
      outline: const Color(0xff7e93a4),
      outlineVariant: const Color(0xffbecad6),
      inverseSurface: const Color(0xff2c4056),
      onInverseSurface: const Color(0xfff7fafc),
      error: const Color(0xffb3261e),
      onError: Colors.white,
      surfaceTint: Colors.transparent,
    );

ColorScheme _mistDark() =>
    ColorScheme.fromSeed(
      seedColor: _mistSeed,
      brightness: Brightness.dark,
      surface: const Color(0xff141a20),
    ).copyWith(
      primary: const Color(0xff9dbbd7),
      onPrimary: const Color(0xff16212b),
      primaryContainer: const Color(0xff2b3b4a),
      onPrimaryContainer: const Color(0xffcfe0ee),
      secondary: const Color(0xffafc0ce),
      onSecondary: const Color(0xff16212b),
      secondaryContainer: const Color(0xff24313d),
      onSecondaryContainer: const Color(0xffdce6ee),
      tertiary: const Color(0xff9dbbd7),
      onTertiary: const Color(0xff16212b),
      surfaceContainerLowest: const Color(0xff0f1418),
      surfaceContainerLow: const Color(0xff1b222a),
      surfaceContainer: const Color(0xff212a33),
      surfaceContainerHigh: const Color(0xff29333d),
      surfaceContainerHighest: const Color(0xff313d48),
      onSurface: const Color(0xffe7edf3),
      onSurfaceVariant: const Color(0xffb6c4d0),
      outline: const Color(0xff7c8c9b),
      outlineVariant: const Color(0xff414e5a),
      inverseSurface: const Color(0xffe7edf3),
      onInverseSurface: const Color(0xff1b222a),
      error: const Color(0xfff2b8b5),
      onError: const Color(0xff601410),
      surfaceTint: Colors.transparent,
    );
