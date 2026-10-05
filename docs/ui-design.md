# 共用界面样式与成本

全应用通过 `applicationTheme` 共用文字层级、卡片、弹窗、底部面板、菜单、按钮、输入框、标签、列表行、提示及导航样式。正文阅读仍保留用户设置的字体、纸色与排版，独立绘制的书封和分享卡片不被通用主题覆盖。

所有应用层图标调用统一为 `ShuyeIcon`。内置常用图形使用同样的 1.65 / 24 线宽与圆角端点；路径按图形缓存，未映射的未来图标回退 Flutter Icon。底栏选中状态保留同一种线条图形，以颜色和背景提示，不切成粗重实心。

表单统一使用 `LabeledField`：字段名固定在框上方，与框左边缘对齐，间隔 8dp；框内只放内容或提示。聚焦、空值或预填内容不会改变字段名位置。下拉框同样处理；视觉标签不重复朗读，控件保留语义名称。搜索框保留原有提示文字。主题关闭浮动标签，新增表单不使用 InputDecoration.labelText。

没有新增图标库、字体包、网络图标、图片资源或后台任务；几何路径一次解析，重绘判定只比较路径、颜色与方向。装饰不使用模糊、持续动画或离屏图层。保持既有按钮的点击区域、辅助功能、系统减少动画和大字号行为。

代码量是维护成本之一，不等同于功耗。体积记录采用实际 ARM64 release APK 字节数；原生库与模型按解压后字节比较。发热、CPU / GPU、内存及真实帧耗时需要设备测量，Flutter 预览与自动测试不证明不会发热。

## 本地界面预览

可选测试默认跳过。安装本机中文字体后设置：

```powershell
$env:SHUYE_CAPTURE_DIR='C:/tmp/shuye-preview'
$env:SHUYE_PREVIEW_FONT='C:/Windows/Fonts/msyh.ttc'
$env:SHUYE_PREVIEW_SERIF='C:/Windows/Fonts/simsun.ttc'
$env:SHUYE_PREVIEW_ICONS='C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
flutter test --no-pub --concurrency=1 --plain-name capture test/preview_test.dart test/reading_heatmap_test.dart test/ui_design_test.dart
```

路径按本机环境调整。彩色热力图仅在截图测试使用演示数据；真实应用不填充假记录。检查首页、书架、笔记编辑、阅读设置、整理书库、工具箱、统计、设置、关于，以及新增弹窗、图标和浅深色 / 大字号预览。

设计成本参考 [Flutter 官方性能建议](https://docs.flutter.dev/perf/best-practices)，优先复用组件并避免昂贵的图层操作；这些方法不能代替真机性能测量。
