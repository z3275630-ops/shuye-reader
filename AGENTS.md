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
