# 共用界面样式与成本

全应用通过 `applicationTheme` 共用文字层级、卡片、弹窗、底部面板、菜单、按钮、输入框、标签、列表行、提示及导航样式。默认文字采用打包的 Shuye Serif 衬线字体；正文保留用户导入字体、纸色与排版，分享模板复用主题语义色，书封继续保留独立插画。

所有应用层图标调用统一为 `ShuyeIcon`。内置常用图形使用同样的 1.9 / 24 线宽与圆角端点；路径按图形缓存，未映射的未来图标回退 Flutter Icon。底栏选中状态保留同一种线条图形，以颜色和背景提示。

0.3.10 的 Claude 风格适配见 [参数与来源](claude-style.md)：页面底色 `#FAF9F5` / `#212121`，米灰卡片、深色文字和线条，黑白主操作、灰底选中态。控件 / 卡片 / 面板圆角为 12 / 16 / 24dp；助手输入卡为 20dp。设置数值使用 `SettingSlider`，分组使用 `SettingsSection`；默认文字统一 Shuye Serif。默认正文跟随全应用配色，18dp / 1.65 行距 / 0 字距并两端对齐；短末行自然留白，导入字体保留。暖纸重复选项合并。

常用面板通过 `applicationMotion` 使用 200ms 入场、150ms 退场，系统关闭动画时立即切换；按钮使用 Flutter 自带 100ms 颜色反馈。阅读助手仍连接已有服务与检查流程；新的输入卡与提示词布局只调整交互。书架紧凑预览最多绘制三本真实藏书，避免复制整库列表。

表单统一使用 `LabeledField`：字段名固定在框上方，与框左边缘对齐，间隔 8dp；框内只放内容或提示。聚焦、空值或预填内容不会改变字段名位置。下拉框同样处理；视觉标签不重复朗读，控件保留语义名称。搜索框保留原有提示文字。主题关闭浮动标签，新增表单不使用 InputDecoration.labelText。

没有新增运行依赖、图标库、网络图标、图片资源或后台任务；新增一份裁剪字体资源及 OFL 许可，0.3.8 添加字体的成本见其历史验证，当前实际成本见 [0.3.11 验证](verification-0.3.11.md)。几何路径一次解析，重绘判定只比较路径、颜色与方向。装饰不使用模糊、持续动画或离屏图层。保持既有按钮的点击区域、辅助功能、系统减少动画和大字号行为。

代码量是维护成本之一，不等同于功耗。体积记录采用实际 ARM64 release APK 字节数；原生库与模型按解压后字节比较。发热、CPU / GPU、内存及真实帧耗时需要设备测量，Flutter 预览与自动测试不证明不会发热。

## 本地界面预览

可选测试默认跳过。安装本机中文字体后设置：

```powershell
$env:SHUYE_CAPTURE_DIR='C:/tmp/shuye-preview'
$env:SHUYE_PREVIEW_FONT='C:/Windows/Fonts/msyh.ttc'
$env:SHUYE_PREVIEW_SERIF='C:/Windows/Fonts/simsun.ttc'
$env:SHUYE_PREVIEW_ICONS='C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
flutter test --no-pub --concurrency=1 --plain-name capture test/preview_test.dart test/reading_heatmap_test.dart test/ui_design_test.dart test/usability_test.dart test/review_integration_test.dart test/mobile_style_test.dart test/compact_style_test.dart test/theme_palette_test.dart
```

路径按本机环境调整。测试先加载 APP 打包的 Shuye Serif，本机字体只负责回退；仍不是安卓真机截图。彩色热力图仅在截图测试使用演示数据；真实应用不填充假记录。检查首页、书架、笔记编辑、阅读设置、整理书库、工具箱、统计、设置、关于，以及新增弹窗、图标和浅深色 / 大字号预览。

设计成本参考 [Flutter 官方性能建议](https://docs.flutter.dev/perf/best-practices)，优先复用组件并避免昂贵的图层操作；这些方法不能代替真机性能测量。

## 后续共用表单与 PDF 控件

`edit_dialog.dart` 管理表单及控制器的完整生命周期，路由移除时释放，不用固定延时猜测弹窗动画。标题与内容共同滚动，操作按钮保留；固定标签、边缘与 8dp 间距沿用 `LabeledField`。单行字段提供下一项 / 完成，多行字段保留换行；密码默认隐藏，可临时显示，关闭建议与自动更正。校验失败留在原字段，不写入设置。

`pdf_controls.dart` 将目录与缩略图分为两页签，用惰性列表构建可见内容；缩略图 78×108dp，DPI 上限 72，去掉缩略图阴影。底部页码允许换行，搜索控件在有查询时出现并自动换行；搜索通知只刷新结果控件，不重建整个阅读页。没有新增依赖、字体、图片、数据库字段或装饰性定时器。

本轮截图与验证见 [验证记录](verification-usability.md)。PDF 目录预览使用测试目录数据，没有原生 PDF 页渲染，不能替代手机验证。

普通阅读设置 / 阅读控制预览为 390dp、100% 字号；同名 `-large.png` 为 320dp、150% 压力测试。近七天彩色图只在可选截图测试使用演示数据。设置面板 20dp 常规字重、控件标题 15dp；系统 TextScaler 不再被线性化。

## 0.3.11 品牌组件

`ShuyeBookLeaf` 的轮廓 / 纸页 / 点缀跟随应用主题；三个 Path 静态缓存，CustomPainter 只在颜色变化时请求重绘。首页用 `ShuyeWelcomeCard` 合并原本重复的横幅和标题；`ShuyeIdentityCard` 去掉整幅横幅，窄屏或大字时让文字优先。`ShuyeCover` 复用同一图形用于书架和关于页，不重复添加新素材或运行解码器。四份原 SVG 只作为设计资料，旧封面资源仍保留，桌面图标不改。
