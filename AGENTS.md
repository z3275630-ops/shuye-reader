# 书叶项目协作

这是 Flutter Android 阅读器。功能入口和实际限制见 README.md、docs/report-coverage.md；修改前先阅读相关模块及现有测试。

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
