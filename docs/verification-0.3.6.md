# 验证记录 · 0.3.6 · 2026-10-05

版本同步为 0.3.6+9，ARM64 split 版本码 2009。包名 `dev.shuye.shuye_reader`，最低 Android 7.0 / API 24，目标 API 36。保留正式签名、压缩原生库、既有依赖与数据库结构。

## 整合结果

- 采纳协助 Agent 的 PR #16、#21；保留贡献提交，主 Agent 直接在 main 补充修正与验证，没有另提 PR。
- 共用表单、颜色校验、PDF 就绪保护 / 页码 / 搜索 / 目录交互见 [前期验证](verification-usability.md)。本轮追加深色主题、左右平移与淡入、连续翻页、系统关闭动画、夜读遮罩、实时排版预览及阅读控制分节。
- 计时失败批次在仓库中保留原小时与日期，串行重试；PDF 显示错误而非抛出未处理异常。失败记录尚未落盘时仍在内存中，不承诺强制结束或持续写入失败时不丢失。
- ZIP 超限支持条目进入失败清单；作者 / 分类 / 书单覆盖前展示差异与确认；统计明确“本期最长连续”，组件日期与周范围使用自然日。
- MCP 只取文本正文、跳过 PDF / CBZ，同章返回多次命中，100 项 / 5 秒协作预算并在服务停止或会话失效后停止后续扫描。单本章节 JSON 的图片与同步解码仍需后续存储改造。
- 修正备份提示；记录列表区分加载、错误和空数据。全量提案决定见 [PR / Issue 衔接表](prd/review-2026-10-05.md)，保留未完成的恢复安全、索引、存储和音频等工作。

## 自动检查与界面

- `dart format lib test`：48 个 Dart 文件；`flutter pub get --enforce-lockfile` 通过，依赖锁文件不变；`flutter analyze --no-pub` 无问题。
- 全量 69 项自动测试通过，默认跳过 5 项可选截图测试。新增验证涵盖真实 SQLite 写入失败重试、原日期 / 小时、短记录、并发写入、跳过损坏 PDF / CBZ 的文本搜索、重复命中 / 数量 / 时间 / 取消、ZIP 超限文件、左右平移和淡入像素、连续翻页、关闭动画、320px / 1.5 倍字号的实时预览、作者替换取消与记录加载失败。
- 5 项可选截图测试通过，共 32 张预览；检查新增浅深色阅读预览 / 阅读控制、关于页 0.3.6，以及此前表单、PDF 控件、首页 / 书架 / 统计的代表界面。预览字体、图标和标题清晰，未见布局异常。
- Windows 预览与全量测试共用 sqlite3 测试库，最终按顺序运行避免文件占用。正式 ARM64 release 构建通过，耗时 168.4 秒；现有 file_picker / share_plus 的未来 KGP 迁移提示保留，本版不升级已锁定依赖。

界面预览使用 Windows 字体，是实际 Flutter 控件截图，不能当作安卓真机截图。PDF 缩略图测试使用占位内容；热力图彩色数据仅限截图测试，不进入正式书库。新增 [浅色阅读预览](screenshots/reading-preview-light.png)、[深色阅读预览](screenshots/reading-preview-dark.png)、[浅色阅读控制](screenshots/reading-controls-light.png)、[深色阅读控制](screenshots/reading-controls-dark.png)。

## 安装包

- APK：**27,401,693 字节，26.13 MiB / 27.40 MB**。0.3.5 基线为 27,336,137 字节；本版 +65,556 字节，约 +0.24%。
- APK SHA-256：`914bf03c32b6132f97e75012f2f46a7836fa0dfc397dbe592ed5268626574a9e`。
- `aapt` 核对版本名 0.3.6 / 版本码 2009 / 包名 / API 24、36 / 仅 arm64-v8a；应用关于页显示 0.3.6。
- `apksigner verify --verbose --print-certs` 通过（v2）；证书 SHA-256 与下载的正式 0.3.5 一致：`03f258a82e60226f8c9b305a1d1a97f1bd1871ff10f6754fe280a25432dbb8ce`。
- `zipalign -c -P 16 4` 通过；清单 `extractNativeLibs=true`，六个原生库均为 ZIP DEFLATE，ELF LOAD 段最低对齐均至少 16 KB。
- Flutter、PDFium、ML Kit OCR、SQLCipher 四个库与 0.3.5 解压后字节完全相同；Dart 应用库随代码变化；libdartjni 的 ELF section 对比仅 `.note.gnu.build-id` 不同。
- 静态图片、OCR 模型、简繁转换、断词等资源字节不变；只有既有 MaterialIcons 的裁剪字体子集变化，没有新增字体 / 图片包。数据库结构与 Android 工程不变。发布只提供一个 APK，另附校验和更新说明。

## 验证边界

没有连接 Android 手机。本版未完成真机覆盖安装、PDF / OCR 渲染、后台音频、桌面组件、系统键盘、SQLCipher 原生升级与服务账号联调，未测真实帧耗时、内存、功耗或温度。电脑自动测试和成功打包不能代替这些验证。

更新前请导出备份，使用正式签名 ARM64 包覆盖安装，不卸载或清除应用数据。音频备份不包含音频文件，换设备后仍需重新关联本地文件。自动恢复点、全库检索界面和多集听书尚未完成。
