# 第三方代码与资源

根目录 LICENSE 的 MIT 许可适用于书叶自身的新增代码；不替代 Flutter、依赖、系统服务和第三方资源的各自许可。原始调研资料、反编译产物和用户书籍不属于发布源码。

- `assets/chinese/`：OpenCC 相关字典与许可见该目录的 `LICENSE.txt`；保留 Apache-2.0 原文。
- Flutter / Dart 和 pubspec.lock 中锁定的依赖：保留各上游许可。应用“关于书叶 → 开源许可”显示 Flutter 收集的依赖声明和本项目 MIT 声明。
- PDF、SQLCipher、音频和 ML Kit 等原生组件通过既有依赖或 Android 配置集成；具体组件和模型遵循其上游条款，不能以根目录 MIT 重新许可。ML Kit 服务条款及模型不应被描述为本项目原创开源代码。
- `lib/app_icons.dart`：项目内编写的轻量路径图标，不包含外部图标字体或新图标包。
- `assets/art/`：生成 / 编辑适配过程见 `docs/image-assets.md` 和 `docs/branding-prompts.md`；它们不是第三方原应用的资源提取结果。

引入新的代码、字体、插图、图标或模型时记录来源及许可，保留要求的声明。更新依赖时复核上游许可，不要仅凭包名猜测许可。
