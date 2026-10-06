# Claude 风格方向稿与应用内落地

本目录四份 SVG 是协助 Agent 提交的设计资料；main 233bb7e 包含全部原稿。0.3.11 根据用户确认，采用 hero 的书页生叶轮廓与 home 的文字 / 插画布局，适配到 Flutter 原生组件和现有主题。实际实现为 lib/brand_illustration.dart、lib/branding.dart 和 lib/home_dashboard.dart。

原图的固定画布、文字、模拟进度与图标符号不是应用控件；没有将完整 SVG 打包为界面。路径静态缓存，没有 SVG 解析、额外资源、持续动画或新的字体。深色与其他主题使用现有 ColorScheme；小屏和大字优先保证文字可读。原白绿应用图标保留，icon / splash 稿尚未采用。详见 ../../verification-0.3.11.md 与 ../../claude-style.md。
