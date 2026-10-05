# 书叶项目协作

这是 Flutter Android 阅读器。功能入口和实际限制见 README.md、docs/report-coverage.md；修改前先阅读相关模块及现有测试。

## 新对话交接（基线：2026-10-05）

- 「书叶」公有仓库：https://github.com/z3275630-ops/shuye-reader，MIT 许可。基线已发布 0.3.5+8；接手检查最新 main、未提交修改和待审 PR，保留他人的工作。
- 已有导入、阅读、PDF / OCR、听书、笔记、备份与统计；待做及部分实现见 docs/report-coverage.md，不把调研报告当作全部已完成。
- 最近更新白绿叠页封面、统一细线图标与控件、固定框外上方且左对齐的表单标签。热力图支持本月 / 半年 / 全年，月格无数字，周历无边缘残格。
- 继续完善全应用功能与观感，重视弹窗、图标、对齐和间距；保持简洁、轻量、高效，优先共用组件。关于页只展示名称、版本和必要介绍，不强调「非官方」「独立实现」。
- 基线仅一个压缩 ARM64 APK，27.34 MB（27,336,137 字节）。49 项本地测试通过；预览是电脑字体的 Flutter 渲染，真机功耗、温度等未测。本节数据是交接快照，新改动须重新验证。
- 先读 README.md、docs/report-coverage.md、docs/ui-design.md、docs/verification.md；Windows 构建见 docs/windows-build.md。其余实现与签名约定见下文。

最新主线为 0.3.6+9（ARM64 版本码 2009），安装包验证见 `docs/verification-0.3.6.md`，下载见 README。协助 Agent 的 PR #16 / #21 已采纳，20 个 Issue 的处理与未完成边界见 `docs/prd/review-2026-10-05.md`；接续开发先查此表，避免重复或丢弃用户数据。

### 其他 Agent 的 PRD 与协作

后续 Agent 会提交 PRD 等文档，建议放在 docs/prd/ 并关联 Issue / PR。先核对用户要求、现有实现及需求冲突；提案不等于已实现或自动授权。主 Agent 直接推进 main，以小范围提交记录实现与验证；其他 Agent 提交 PR，由主 Agent 核对需求、冲突和测试后衔接。写清验证与体积 / 性能影响，正式发布按用户授权处理。流程与模板见 CONTRIBUTING.md。

## 开发与验证

- 使用 Flutter 3.47.2 / Dart 3.13.2，执行 `flutter pub get --enforce-lockfile`，保持已锁定依赖。
- 提交前运行 `dart format lib test`、`flutter analyze --no-pub`、`flutter test --no-pub --concurrency=1`。
- 安装包使用 `flutter build apk --release --target-platform android-arm64 --split-per-abi`。保留 `useLegacyPackaging = true`，不改回包含多架构的通用包。
- 正式签名由维护者本机保管。不要提交密钥、签名密码、个人书库或服务凭据；其他 Agent 可自行调试构建，不能用不同签名替换正式发布包。
- 发布时同步 pubspec.yaml 和 lib/branding.dart 的版本号，递增 build number；保留现有包名以支持覆盖升级。

## 实现约定

- 阅读统计来自已有每日秒数；不能向正式应用补造演示数据。处理自然日、闰年、跨年与未来日期，不直接用本地时区小时数推算天数。
- 本月按七列日历排列；半年 / 全年采用正方格、整周定位和滚动结束对齐。修改布局要检查 320px 屏幕、1.5 倍字体及浅深主题。
- 界面预览测试默认跳过，需要设置 SHUYE_CAPTURE_DIR 和本机字体路径；彩色演示数据仅在截图测试中使用，预览不能当作安卓真机验证。
- 保留现有导入、加密、备份、阅读位置与笔记数据行为。涉及 Android 原生服务的变化应明确区分自动测试和真机测试。
- 图像只打包 pubspec 中列出的压缩资源；标题、书名和作者用原生文本渲染。

## 贡献与界面

- Issue / PR 流程见 CONTRIBUTING.md，使用 .github 的模板；安全问题按 SECURITY.md 私有报告。
- 新增代码采用项目 MIT 许可，第三方声明见 THIRD_PARTY_NOTICES.md；不要以项目许可覆盖上游许可。
- 全应用样式集中于 lib/appearance.dart，图标使用 lib/app_icons.dart 的 ShuyeIcon。优先共用样式，避免重复实现和新图标 / 字体包。
- 美化不添加持续动画、装饰性定时器、后台任务或模糊叠层。记录 release APK 实际体积；设备发热与帧耗时没有真机测量不能宣称已验证。
- 表单字段名使用 lib/form_field.dart 的 LabeledField，固定在输入框上方并与框左边缘对齐。输入框内只放内容或提示，不使用浮动 labelText；下拉选择同样处理，保留控件语义名称。
