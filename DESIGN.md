---
name: 书叶 Shuye Claude
version: 1
description: 暖白纸面 + 墨色文字 + 单一陶土橙强调的克劳德风格；近扁平，靠 1px 发丝线与色差分界。
colors:
  canvas: "#FAF9F5"
  card: "#FFFFFF"
  ink: "#141413"
  body: "#3D3D3A"
  muted: "#73726C"
  placeholder: "#9C9A92"
  hairline: "#C2C0B6"
  hairlineSoft: "#E3E1D8"
  fill: "#F0EFE9"
  accent: "#D97757"
  accentContainer: "#F5E3DB"
  accentDeep: "#9C4A2E"
  night: "#0B0B0B"
  nightElevated: "#1E1E1E"
  onNight: "#F5F4EE"
  onNightMuted: "#98989D"
typography:
  heading:
    fontFamily: serif
    fontWeight: 400
    note: 衬线只做标题且保持轻字重，不加粗；轻盈本身就是重点。
  body:
    fontFamily: sans
    fontWeight: 400
    note: 正文、按钮、辅助文字一律无衬线 400。
radius:
  control: 8
  input: 10
  card: 16
  sheet: 24
  note: 圆角随元素尺寸递增；小控件不要用大圆角。
spacing: [4, 6, 8, 12, 16, 20, 24, 32, 48]
elevation:
  note: 近扁平。层次靠白色卡片浮在暖白底上、1px 发丝线和 rgba(0,0,0,0.016–0.04) 的耳语级阴影，不靠强投影。
---

# 书叶设计规范（Claude 风格）

本文件是界面视觉的单一事实来源。写 UI 前先读本文件；颜色、字体、圆角只允许引用其中的 token（或 `lib/appearance.dart` 中由 token 构建的主题字段），**不允许在页面里内联写色值、自造圆角或另起字号体系**。

## 底色与层次

- 页面底色是暖白 `#FAF9F5`，**不用纯白做页面底**；纯白 `#FFFFFF` 只属于卡片、输入框等浮起元素。
- 深色模式不是灰黑而是近黑：底 `#0B0B0B`，浮层 `#1E1E1E`，文字 `#F5F4EE`。

## 色彩纪律

- 交互主色是**墨色**：浅色模式下主按钮是近黑底白字，不用品牌绿、不用陶土橙。
- 陶土橙 `#D97757` 是全系统唯一的彩色瞬间，只用于品牌点缀、选中态与强调；不用于大面积底色、不用作主按钮。
- 次级文字 `#73726C`、占位符 `#9C9A92`、发丝线 `#C2C0B6`；列表内分隔线用更浅的 `#E3E1D8`。

## 字体

- 标题（AppBar、对话框标题、headline/title 层级）用系统衬线（`fontFamily: 'serif'`），**字重不超过 w400**。
- 正文、按钮、列表、辅助文字用无衬线（Roboto / 系统默认），常规字重。
- 不引入新字体文件；Anthropic Serif/Sans 为专有字体，以系统衬线替代。

## 控件

- 圆角：按钮 8、输入框 10、卡片 16、底部面板与对话框 24；随元素尺寸递增。
- 间距只用 4/6/8/12/16/20/24/32/48 档。
- 阴影耳语级；分隔优先用 1px 发丝线而非投影。
- 图标沿用 `lib/app_icons.dart` 的细线 ShuyeIcon，不新增图标库。

## 阅读正文

- 四套纸色（`lib/reader.dart` 的 `readerSchemes`）是克劳德色系在正文的延伸：暖纸 `#FAF9F5`、纸白 `#FFFFFF`、青竹（暖白中一丝青）`#E9EEEA`、夜读近黑 `#0B0B0B`；正文一律墨色系文字。
- 阅读统计热力图七级色阶（`lib/reading_heatmap.dart`）从暖白过渡到陶土橙，见源码内调色板。

## 验证要求

- 改动后按 AGENTS.md 跑 `dart format` / `flutter analyze` / `flutter test`；
- 检查 320px 小屏、1.5 倍字号、浅色与深色四组合；
- 包体：本规范零新增依赖、零新增资源。
