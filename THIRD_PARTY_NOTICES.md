# 第三方代码与资源

根目录 LICENSE 的 MIT 许可适用于书叶自身的新增代码；不替代 Flutter、依赖、系统服务和第三方资源的各自许可。原始调研资料、反编译产物和用户书籍不属于发布源码。

- `assets/chinese/`：OpenCC 相关字典与许可见该目录的 `LICENSE.txt`；保留 Apache-2.0 原文。
- Flutter / Dart 和 pubspec.lock 中锁定的依赖：保留各上游许可。应用“关于书叶 → 开源许可”显示 Flutter 收集的依赖声明和本项目 MIT 声明。
- PDF、SQLCipher、音频和 ML Kit 等原生组件通过既有依赖或 Android 配置集成；具体组件和模型遵循其上游条款，不能以根目录 MIT 重新许可。ML Kit 服务条款及模型不应被描述为本项目原创开源代码。
- `lib/app_icons.dart`：功能图标通过统一适配层使用 `lucide_icons_flutter 3.1.22` 的本地修改子集 `3.1.22+shuye.1`（[vqh2602/lucide-flutter-main](https://github.com/vqh2602/lucide-flutter-main)，MIT，Copyright 2024 vqhapp）。固定来源与校验见 `third_party/lucide_icons_flutter/audit.json`，保留应用使用的 59 个默认字形；未修改共享缓存，也不是未修改的上游发行包。依赖许可由 Flutter 收集并显示。品牌叶子仍为本项目路径。
- `assets/art/`：生成 / 编辑适配过程见 `docs/image-assets.md` 和 `docs/branding-prompts.md`；它们不是第三方原应用的资源提取结果。
- `assets/fonts/ShuyeSerif-Regular.ttf` / `ShuyeSerif-SemiBold.ttf`：源自 Google / Noto Serif SC 的静态裁剪版本，改名 Shuye Serif，按 SIL Open Font License 1.1 分发。保留 `assets/fonts/OFL.txt` 的版权与完整许可，来源、校验和裁剪说明见该目录 README；APP 开源许可页登记 Noto Serif SC / Shuye Serif。没有使用 Anthropic 专有字体。
- `lib/editorial_art.dart`：参考用户提供的黑色墨线、纸片形状与少量陶土色关系，以原生 Path 创作书脊、笔记本和桥；没有截取或打包参考图、平台水印或原应用图标。

引入新的代码、字体、插图、图标或模型时记录来源及许可，保留要求的声明。更新依赖时复核上游许可，不要仅凭包名猜测许可。

Lucide 图形本身的 ISC 声明及其中 Feather 图形的 MIT 声明保留于 `assets/licenses/Lucide.txt`，来源为 [Lucide 固定提交](https://github.com/lucide-icons/lucide/blob/500620a2e8123f8d1db191538886dc0c223f69a9/LICENSE)。与 Flutter 包的 MIT 声明分别显示在 APP 开源许可页。

- `assets/fonts/ShuyeSans-Regular.ttf` / `ShuyeSans-SemiBold.ttf`：Google / Noto Sans SC 的静态裁剪版，改名 Shuye Sans，OFL 1.1；固定上游、覆盖和哈希见字体 README / sans-audit.json。完整声明为 `assets/fonts/Sans-OFL.txt`，APP 开源许可页单独登记。
