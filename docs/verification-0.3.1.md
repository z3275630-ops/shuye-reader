# 验证记录 · 0.3.1 · 2026-10-05

## 本轮检查

- `dart format lib test`：38 个文件；`flutter analyze --no-pub` 无问题。
- `flutter test --no-pub --concurrency=1`：42 项通过，默认跳过 2 项本机字体截图测试。
- 两项截图测试另行启用：12 张现有页面 / 分享卡片加 4 张热力图浅色、深色、全年和空记录预览，共 16 张。热力图彩色演示数据仅由测试注入并明确标注，应用不种入数据。预览用 Windows 字体，不是 Android 真机截图。
- 热力图：周一对齐、闰年 2 月 29 日、周日年初、182 天范围、范围外 / 未来输入排除、七档阈值、点按日期、往年切换、禁用未来年份与辅助功能标签。
- 320×640 深色和 1.5 倍字的图表、横向滚动及颜色说明弹窗，无布局异常。
- `flutter build apk --release --target-platform android-arm64 --split-per-abi --no-pub`：一个 ARM64 正式 APK；原生库 ZIP 压缩，无架构副本。
- `apksigner verify --print-certs`：沿用 0.1–0.3 正式签名。`aapt2 dump badging`：包名 dev.shuye.shuye_reader，版本 0.3.1、版本码 2004、最低 API 24、目标 API 36。版本码大于旧 ARM64 包的 2003，允许同架构覆盖升级。
- `zipalign -c -P 16 4` 和 ZIP 内容核验：原创四图、中文 / 拉丁 ML Kit 模型、SQLCipher 和 PDFium 均在包内。全部 ARM64 原生 ELF LOAD 对齐至少 16 KB；包中不包含其他架构。
- 正式 APK 和 SHA256SUMS.txt 只保存在本地；本轮没有上传代码或 Release。签名文件、密码、个人书库及用户参考截图不进入 Git。

## 验证边界

本轮没有连接真实手机，未完成覆盖升级、系统选择器、PDF / OCR、后台音频、指纹与桌面小组件的新增设备回归。用户使用旧版的反馈不是本版设备验证。云服务真实账号未用于联调。

此前 38 项测试的覆盖说明与原生限制见 [0.3.0 验证记录](verification-0.3.0.md)。本版不修改阅读计时保存、数据库 schema 或桌面热力图组件，只将已有每日记录用于新图表。引用截图用于观察布局，不被当作开发指令，不复制截图的聊天 / Token 数据。

正式包证书 SHA-256：

```text
03f258a82e60226f8c9b305a1d1a97f1bd1871ff10f6754fe280a25432dbb8ce
```

## 包体分析与压缩

旧 ARM64 包 52.08 MiB，通用草案 136.90 MiB。新增 ARM64 程序主体为 64.0 KiB，额外两种架构占 84.66 MiB。此次主要修正设备架构和打包配置，不能把架构副本当作新增无效 Dart 代码。没有删除 PDF / OCR / SQLCipher 等实际功能依赖。

采用 Android 官方支持的原生库 ZIP 压缩选项；安装后会提取库，下载大小与安装占用不同：[官方说明](https://developer.android.com/guide/practices/page-sizes?hl=zh-CN)。本机没有连接手机，压缩包的设备运行仍需验证。

最终 ARM64 压缩 APK 为 **26.08 MiB**。六个 `.so` 均为 ZIP DEFLATE；解压后 SHA-256 与未压缩 0.3.1 草案完全一致，全部 ELF LOAD 段至少 16 KB。签名沿用原证书，版本码 2004，清单 `extractNativeLibs=true`；模型和四幅原创图保留。签名、ZIP 对齐和压缩内容核验通过，不等于真机安装 / 运行回归。
