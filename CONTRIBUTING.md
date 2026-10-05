# 参与书叶开发

欢迎人工开发者和 Agent 提交 Issue、改进和 PR。先读 [README](README.md)、[AGENTS.md](AGENTS.md)、[功能与限制](docs/report-coverage.md) 和相关模块，再开始修改。

## 提 Issue

使用 Bug 或功能建议模板。Bug 请给出应用版本、Android 版本、手机型号、最短复现步骤、预期和实际表现。截图和日志要去除个人书籍、笔记、账号、密钥与服务地址。无法在真机复现时直接说明，不把模拟截图当作设备验证。

建议请说明使用场景和带来的改善。涉及安全漏洞时遵循 [SECURITY.md](SECURITY.md)，不要公开敏感细节。

## 开发与提交 PR

1. Fork 仓库，从最新 main 建立 `codex/描述` 分支，例如 `codex/dialog-spacing`。本地工作区有未提交修改时先检查，不覆盖他人的工作。
2. 使用 Flutter 3.47.2 / Dart 3.13.2、JDK 21、Android SDK 36；`flutter pub get --enforce-lockfile`。中文 Windows 路径的构建方法见 [Windows 说明](docs/windows-build.md)。
3. 修改相关代码，保留书库、笔记、密钥及进度兼容；不要为了演示向用户数据填入虚假记录。依赖变更需说明理由、许可证及包体 / 运行成本。
4. 执行 `dart format lib test`、`flutter analyze --no-pub`、`flutter test --no-pub --concurrency=1`。界面修改检查小屏、1.5 倍字号、浅深色、点击与辅助功能；需要截图时按 [预览说明](docs/ui-design.md) 启用可选测试。
5. Android 调试构建：`flutter build apk --debug --target-platform android-arm64 --split-per-abi`。不要上传 debug 包冒充正式包；它无法覆盖正式签名版本。
6. PR 填写问题、改动、验证与限制，附关联 Issue 和必要的界面截图；自动检查会运行格式、静态检查、测试和 Android 构建。跨多项需求时说明范围，不提交无关格式修改。

PR 审核和正式发布由维护者处理。提交 PR 不是自动获准合并；发生冲突时更新分支并保留他人的修改。Agent 应注明哪些检查实际运行、哪些未验证，无需公开隐藏推理或完整聊天记录。

## 性能与体积

共用样式和 `ShuyeIcon` 位于 `lib/appearance.dart` / `lib/app_icons.dart`。优先扩展现有组件，避免每页复制样式、整套字体 / 大图资源、装饰性定时刷新、持续动画、模糊叠层和昂贵的离屏渲染。保留系统减少动画与文字缩放行为；不要为省几行代码压缩掉可读性。

正式发布仅构建压缩 ARM64 包，保留 `useLegacyPackaging = true`。版本号同时更新 pubspec.yaml 与 lib/branding.dart，递增 build number。任何精简必须核对原生库、模型和功能，不能靠移除 PDF / OCR / 加密缩小包体。耗电、发热和帧耗时必须在真实设备 release / profile 模式测量后才能作出结论。

## 许可与发布材料

项目自身代码采用 [MIT](LICENSE)；提交的新增代码采用同一许可，第三方代码和资源必须保留许可及来源，详见 [第三方说明](THIRD_PARTY_NOTICES.md)。不要提交原应用反编译内容、来源不明的资源、签名密钥、密码、个人数据库或设备日志中的秘密。无需提交正式签名文件即可协作和调试。
