# 共用表单与 PDF 交互验证 · 2026-10-05

## 主线范围

从 main `5914e12` 接手，读取 AGENTS 新对话交接、README、功能对照、界面说明、验证与构建记录。开始和收尾核对远端：没有待审 PR / Issue，也没有其他 Agent 的 PRD 文件。按用户要求由主 Agent 直接推进 main；其他 Agent 提交 PR 后再核对需求、冲突与测试。后续对接见 [需求协作](prd/README.md)。

- 共用 `edit_dialog.dart` 按弹窗生命周期释放控制器，取消固定 300ms 延时；标题与字段一起滚动，保留固定标签、保存与取消。键盘支持下一项 / 完成、多行换行；密码默认隐藏，可切换显示，禁用自动更正和输入建议。字段校验失败保留表单和输入。分组名称复用共用组件，保留 120 字上限。
- 自定义阅读颜色在字段下提示错误；无效值不会修改原设置，留空继续恢复默认。增加关闭页面后的状态检查。
- PDF 搜索器从 initState 移至 onViewerReady，避免提前访问未就绪的控制器；书籍 ID 用作缓存标识，区分同名 PDF。加载完成前不记录阅读秒数。
- 点按 PDF 底部页码可输入 1 至总页数的整数跳转；加载和操作期间禁用不可用入口，首尾翻页按钮禁用。搜索显示进度 / 匹配数量 / 无结果，支持关闭，切换结果后更新序号。结果通知仅重建结果控件。
- PDF 目录与缩略图分为页签；目录保留层级，禁用无目标及越界目标。缩略图从当前页打开，用 ListView.builder 按需构建，78×108dp，DPI 上限 72，移除阴影。它减少预先创建整书控件的成本，不作为真机内存 / 功耗测量结论。

## 自动验证

Flutter 3.47.2 / Dart 3.13.2，依赖锁文件不变。中文路径下 analyze 的 LSP 管道出现 JSON 截断，改用独立英文构建副本；逐个比对 lib / test 的 Dart 文件哈希，与交付源码一致。

- `flutter pub get --enforce-lockfile` 通过。
- `dart format --output=none --set-exit-if-changed lib test`：46 个文件，无待格式化修改。
- `flutter analyze --no-pub` 无问题。
- 完整 `flutter test --no-pub --concurrency=1`：57 项通过，4 项可选预览默认跳过；比基线增加 8 项交互与生命周期测试。
- 新测试覆盖 320×640px、1.5 倍文字、浅深主题、220px 模拟键盘遮挡、下一项 / 完成、密码显示 / 隐藏、保存校验、颜色错误和修正、1000 页列表从第 500 页只构建附近页面、目录失效目标、超长页码、PDF 加载 / 就绪 / 退出计时，以及搜索切换 / 边界 / 关闭。
- PDF 生命周期测试使用延迟加载后端和可控就绪回调；搜索控件测试使用可控搜索后端，不包含原生 PDFium 页渲染。已有导入、数据库升级、正文阅读、笔记、备份与热力图回归通过。
- 4 项截图测试通过，生成 28 张预览，包含本轮浅深色表单和目录。使用 Windows 字体；目录使用测试数据，没有真实 PDF 页面，不是安卓真机截图。新截图见 [浅色表单](screenshots/editor-light.png)、[深色表单](screenshots/editor-dark.png)、[浅色目录](screenshots/pdf-contents-light.png)、[深色目录](screenshots/pdf-contents-dark.png)。

## ARM64 构建与体积

Android debug ARM64 split 构建通过。正式签名的 release QA 构建通过；只包含 ARM64，包名 dev.shuye.shuye_reader，API 24 / 36，extractNativeLibs=true。六个原生库均为 ZIP DEFLATE，ELF LOAD 对齐至少 16 KB；apksigner 与 zipalign 检查通过，证书 SHA-256 与正式 0.3.5 相同。

- 0.3.5 发布包：27,336,137 字节。
- 本轮 QA 包：27,386,717 字节，26.12 MiB / 27.39 MB。
- 差值：+50,580 字节，约 +0.19%。
- Flutter、PDFium、ML Kit OCR 和 SQLCipher 四个库与上版解压后字节完全一致；Dart 应用库随本轮代码改变。libdartjni.so 的 ELF section 对比仅 .note.gnu.build-id 不同，其余 sections 一致。
- 图片、OCR 模型、中文转换、断词数据等静态资源不变；已有 MaterialIcons 的裁剪字体子集因新增眼睛标识改变，没有新增字体包。pubspec.yaml、pubspec.lock、Android 工程与数据库结构没有改动。

本轮构建仅用于验证，沿用 0.3.5+8 / ARM64 2008，没有当作新版本分发或创建 Release。后续正式更新需同步 pubspec.yaml / branding.dart 并提升 build number。该 QA 包 SHA-256：`3bde03ccbaf3fdf9341a5da00088b412d4b8631dd273b70c0f9969d73f061983`。

## 未验证范围

没有手机连接，未验证安卓原生 PDF / OCR、覆盖升级、系统键盘、TTS、音频与厂商桌面组件，未测真实帧耗时、温度、内存和功耗。release 和 debug 构建证明可打包，不代表已完成真机回归。构建提示 file_picker / share_plus 的现有 KGP 将受未来 Flutter 版本影响，本轮保持锁定版本，不做未经验证的依赖升级。
