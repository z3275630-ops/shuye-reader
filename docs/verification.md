# 验证记录 · 0.3.2 · 2026-10-05

## 本轮修改与检查

- 更新应用封面、Android 桌面图标 / 自适应图标 / 启动背景；统一首页、书架、设置及关于页。关于页改成中文按钮、应用介绍与版本号，保留开源许可入口。
- `dart format lib test`：39 个文件。`flutter analyze --no-pub` 无问题；`flutter test --no-pub --concurrency=1`：42 项通过，默认跳过 2 项可选截图测试。
- 两项截图测试另行启用，生成 18 张真实 Flutter 控件预览：原 12 张页面与分享卡片、4 张热力图、设置应用卡片和关于页。检查新封面在首页、书架、设置、关于及深色页面的布局。截图使用 Windows 字体，不是 Android 真机截图；彩色热力图演示数据仅由测试注入。
- 0.3.1 热力图日期、颜色分档、年份选择、辅助功能、小屏与大字号测试继续通过；导入、数据、阅读及外观等既有测试通过。没有新增数据库 schema 或修改阅读计时规则。
- `flutter build apk --release --target-platform android-arm64 --split-per-abi --no-pub`：一个正式 ARM64 包，继续压缩原生库。
- `apksigner verify --print-certs`：沿用原正式证书；`aapt2 dump badging`：包名 dev.shuye.shuye_reader，版本 0.3.2、版本码 2005、最低 API 24、目标 API 36。可覆盖相同签名的旧 ARM64 包。
- `zipalign -c -P 16 4` 通过；6 个 ARM64 `.so` 均为 ZIP DEFLATE，ELF LOAD 段至少 16 KB。除必然变化的 Dart 程序 `libapp.so` 外，5 个原生运行库解压后的字节与 0.3.1 一致；全部模型文件保留且字节相同。
- APK 精确包含三幅示例书封、新应用封面和标记五幅 WebP，旧横幅不再打包。Android 清单使用新 mipmap 图标，API 26 的自适应前景 / 背景和旧密度 PNG 保留。
- APK 为 **27,311,802 字节 / 26.05 MiB / 27.31 MB**，上版为 26.08 MiB。下载大小与系统解压库、缓存及个人书籍后的安装占用不同。
- 发布内容为一个压缩 ARM64 APK、SHA256SUMS.txt 和升级说明；大尺寸原图保存在本机。用户在选定最终图案后明确要求上传，新版发布到原私有仓库。签名凭据、密钥及个人书库不进入 Git。

## 验证边界

本机未连接真实手机，尚无本版覆盖安装、桌面图标不同厂商遮罩、系统启动动画或 Android 原生服务的新设备回归。自动测试、图片预览及签名检查不能替代实际运行。云服务真实账号未用于联调。之前的验证边界见 [0.3.1 记录](verification-0.3.1.md) 和 [0.3.0 记录](verification-0.3.0.md)。

正式包 SHA-256：`4629305eb99685ca6e8994db3a900311a80e350eddd53d8a2e36080b5cf0d301`。

证书 SHA-256：`03f258a82e60226f8c9b305a1d1a97f1bd1871ff10f6754fe280a25432dbb8ce`。
