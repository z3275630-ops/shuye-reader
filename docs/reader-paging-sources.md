# 翻页实现来源与适配 · 2026-10-09

用户要求停止自定义弹簧调参，直接采用成熟开源阅读器的实现。0.3.18 删除两版弹簧收尾，移植 Readium 的现成分页曲线和时长计算；整页缓存与连续手势的处理按已核验的阅读器源码适配 Flutter。微信读书、番茄的完整内部实现未公开，以下不冒称其私有源码。

## 已核验源码

| 来源 | 实际处理 | 书叶采用的部分 |
|---|---|---|
| [Readium R2WebView](https://github.com/readium/kotlin-toolkit/blob/1b1f6b308a7b6f968b2bf1e66c84912879466f75/readium/navigator/src/main/java/org/readium/r2/navigator/R2WebView.kt) | quintic 减速插值，释放速度及距离影响时长，最多 600ms；新触摸打断 Scroller，选字状态不启动翻页 | `sInterpolator`、`distanceInfluenceForSnapDuration`、`smoothScrollTo` 中的公式直接移植至 `lib/reader_scroller.dart`，不另调弹簧参数 |
| [Legado HorizontalPageDelegate](https://github.com/LegadoTeam/legado/blob/5198645f0a504b1f6d1259885317e056ff6a4a02/app/src/main/java/io/legado/app/ui/book/read/page/delegate/HorizontalPageDelegate.kt) / [SlidePageDelegate](https://github.com/LegadoTeam/legado/blob/5198645f0a504b1f6d1259885317e056ff6a4a02/app/src/main/java/io/legado/app/ui/book/read/page/delegate/SlidePageDelegate.kt) | 前后当前页的 CanvasRecorder，在动画中仅平移绘制记录；新触摸结束旧动画，已接受的翻页先完成，再开始新手势 | 当前 / 前后 RepaintBoundary 提前记录完整纸面；新手势结束已接受的旧收尾，缓冲至新页绑定，不再次拖同一页 |
| [Legado CanvasRecorderApi29Impl](https://github.com/LegadoTeam/legado/blob/5198645f0a504b1f6d1259885317e056ff6a4a02/app/src/main/java/io/legado/app/utils/canvasrecorder/CanvasRecorderApi29Impl.kt) | 记录 Picture，再录入 RenderNode；硬件画布重放 RenderNode | 对应 Flutter 的保留图层 / 绘制记录，不在每帧截图或重新排字。不是把 Android RenderNode 原样塞入 Flutter |
| [NBReader SlidePageAnimation](https://github.com/newbiechen1024/NBReader/blob/e423b13915578ab95c1683bfa7a70e59f19f2eab/app/src/main/java/com/newbiechen/nbreader/ui/component/widget/page/anim/SlidePageAnimation.kt) / [PageAnimation](https://github.com/newbiechen1024/NBReader/blob/e423b13915578ab95c1683bfa7a70e59f19f2eab/app/src/main/java/com/newbiechen/nbreader/ui/component/widget/page/anim/PageAnimation.kt) | 重放当前 / 目标页 Bitmap，按剩余距离决定时长；新触摸先终止旧动画 | 用于交叉核对整页缓存与连续翻页处理；不移植旧版方向判断 TODO 或固定匀速模型 |

补充对照 [libreadview SlideEffect](https://github.com/Peyilo/libreadview/blob/ceacbf3e172de6dad81c54a4ec336a2bd5891873/app/libreadview/src/main/java/org/peyilo/libreadview/turning/SlideEffect.kt)：已经存在的两个 View 一起平移；默认 200ms 匀速。没有把“成熟阅读器”归结为某一组速度参数，也不引入其阴影或 iBook 视差效果。

## 适配边界

- Readium 的 Kotlin 数学部分移植为 Dart，BSD 完整声明进入资源与开源许可页；原来源及版权保留。其 WebView、EPUB 导航、数据库和服务不引入。
- Legado / NBReader 作为方法参考，不将其 GPL 代码复制为 MIT。整页渲染采用 Flutter 现有组件；只有三张纸面，不新增截图缓存、后台常驻任务或绘图库。
- 滑动纸面仍包含章名、编号、正文及页脚。当前页长按选字保留，相邻页不接收输入或语义；全屏、设置区和用户认可的字体配色不改变。
- 之前相邻页只 Offstage 排版，首次拖动才 paint；现在平移模式下先在视口裁切范围之外绘制，框架缓存其绘制记录。此项不等于保证 GPU 已经将离屏页栅格化，真实帧耗时仍须测量。
- 新手势提前结束旧收尾时只完成之前已接受的一次翻页；下一次手势的位移和松手被缓冲至页面绑定。系统取消、锁定、后台或关闭页面仍不能提交新手势。
- 极长章节同步分页、设备限制应用 60Hz 等独立问题没有因曲线移植自动消失；不改用户系统刷新率来掩盖结果。


## 0.3.19：回翻与全书末页 · 2026-10-10

继续核验同一固定提交的 [Legado TextPageFactory](https://github.com/LegadoTeam/legado/blob/5198645f0a504b1f6d1259885317e056ff6a4a02/app/src/main/java/io/legado/app/ui/book/read/page/provider/TextPageFactory.kt)：`hasPrev` / `hasNext` 先判断真实相邻页，`moveToNext` / `moveToPrev` 无页时返回 false；`nextPlusPage` 单独取得更远页。HorizontalPageDelegate 无相邻页时返回，不做虚构纸面的移动。此轮参考其把实际翻页、相邻页准备和边界判断分开的处理。

书叶的真机日志显示：回翻落定帧既提升已准备的正文，又首次绘制更远的一页。Flutter 适配改为落定帧只保留已有纸面，下一帧再挂载 / 绘制新远页；仍最多三张纸面，没有新增 Bitmap 缓存。此安排是依据本项目测量作出的 Flutter 实现，不能称为直接移植 Legado 的空闲调度或后台分页。无下一页且可见状态未变时不请求纸面重建；实际到达末页已保存进度，重复越界不再保存相同位置。Readium 曲线与时长公式原样保留。

测量证明正常落定帧工作减少；新段落首次绘制被移至随后一帧，没有凭空消失。下一触摸提前完成旧翻页仍可能遇到较高耗时，极长章节同步分页也未解决。完整对照、回归与手机手感状态见 [0.3.19 验证](verification-0.3.19.md)。
