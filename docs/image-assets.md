# 原创生图素材记录

示例书封使用 Codex 内置 image_gen 生成；0.3.2 应用封面与标记根据用户提供的图片使用同一工具编辑适配。书名和作者由 APP 原生文字叠加，便于替换、缩放和无障碍阅读。生成后仅做等比例缩小与 WebP 压缩。

初版生成日期：2026-10-04。三个示例书封使用米白、鼠尾草绿与陶土色。

0.3.2 更新为用户选定的黑底、白绿叠页图案，去掉外围圆角框，保持主体；横向封面完整展示叠页。完整编辑提示词见 [0.3.2 生图记录](branding-prompts.md)。应用封面 `shuye-cover.webp` 宽 1440 像素、12,074 字节；应用标记 `shuye-mark.webp` 为 256×256、4,104 字节。Android 自适应图标单独使用 432×432 WebP，并通过 14dp inset 保持圆形遮罩内的安全边距；另提供五种密度 PNG。所有应用文字由代码绘制。

pubspec 精确列出五幅在用图像。旧 `reading-garden.webp` 仅留在源文件中作历史记录，不再打入安装包。

## mountain.webp

文件：`assets/art/mountain.webp`

```text
Create one original portrait 2:3 literary book cover illustration, no lettering, no logos, no watermark. For an original Chinese short story called Mountain Letters: quiet layered misty mountains in sage green, warm ivory handmade paper grain, a small cream envelope resting on a wooden windowsill with a single leafy branch, distant warm cabin light. Sophisticated contemporary editorial gouache and restrained ink, soft natural light, elegant negative space in the upper third for app-rendered title. Full bleed artwork, flat cover image not a photographed physical book, high quality.
```

## poetry.webp

文件：`assets/art/poetry.webp`

```text
One original portrait 2:3 book cover artwork, no text, no typography, no watermark, no logo. Quiet literary poetry anthology illustration: warm ivory paper, terracotta teacup on a windowsill, a few tiny wildflowers in glass vase, soft morning sunlight casting poetic leaf shadows, a small pale blue sky opening. Contemporary editorial gouache and restrained ink, tactile paper grain, sage green and muted rust accents, refined composed minimalism, upper third mostly calm warm paper for app-rendered title. Flat full bleed cover artwork, not a physical book mockup. Match an elegant calm Chinese offline reader visual identity.
```

## notebook.webp

文件：`assets/art/notebook.webp`

```text
Original flat full bleed portrait 2:3 literary cover illustration with absolutely no text, no logo, no watermark: an open ivory notebook and a single green gingko leaf on a clean desk, gentle forest green cloth bookmark, soft ink lines and editorial gouache, warm handmade paper texture, sage and ivory palette with muted ochre accent, subtle shadows, calm sophisticated composition. For a guide to a personal reading app. Upper third clear light paper negative space for app-rendered Chinese title. No mockup, no perspective book product shot.
```

## reading-garden.webp

历史文件：`assets/art/reading-garden.webp`，0.3.2 已由新封面替换并移出打包清单。

```text
Generate one original panoramic horizontal 3:1 editorial illustration for a calm Chinese reading app bookshelf banner. A small open book in a peaceful indoor reading garden, sunlit arch window framing rolling sage mountains, a warm terracotta cup, gingko and olive leaves around edges, ivory plaster wall, soft pale golden afternoon light. Refined contemporary gouache with delicate ink and paper grain, flat painterly illustration, low visual clutter, muted cream and sage green palette. Keep middle left area spacious. Absolutely no letters, typography, logos or watermarks. No UI, no device mockup, no collage. Warm, quiet, sophisticated full bleed artwork.
```
