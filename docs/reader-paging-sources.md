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

## 0.3.20：审查后的手势与冷加载修复

继续对照上列固定提交的 Readium `mInitialVelocity` / 释放方向判定。本项目记录横滑被识别后的首个非零位移作为初始方向，释放方向相反时撤回；保留距离型慢拖及零速度释放，没有复制 Readium 的完整 fling-only 接受门槛。此前 450 的反向门槛移除，不换成另一个猜测速度值。收尾数学公式不变，来源声明继续有效。

新增对照 [Legado TextChapterLayout](https://github.com/LegadoTeam/legado/blob/5198645f0a504b1f6d1259885317e056ff6a4a02/app/src/main/java/io/legado/app/ui/book/read/page/provider/TextChapterLayout.kt)：排版在 IO context，页面完成时逐页发布。本项目仅参考准备状态、取消和分批供给方法；Flutter TextPainter 不能原样搬进 [后台 isolate](https://docs.flutter.dev/perf/isolates#no-rootbundle-access-or-dartui-methods)。共用既有真实字体分页算法，拆成测量步骤，每帧至多一页并在 2ms 批次预算后让出执行权；单次字体测量不可抢占，整章准备完成后才发布缓存。没有移植 Legado 后台排版源码，不能称为其完整引擎。

相邻页明确区分准备中与全书边界。首次冷跨章先等待实际纸面就绪和绘制，再沿用已有滑动 / 交接机制；取消或失效准备不提交。前后章提前预热，拖动 / 收尾暂停，等待目标章时恢复。缓存与纸面数量不增加。实现、真实回归及边界见 [0.3.20 验证](verification-0.3.20.md)。


## 2026-10-11：正式版对照候选，绘制复用与共享预热预算

先阅读实际源码，再做本轮修改：

- [微信读书 Android 卡顿测试，2018](https://www.infoq.cn/news/weixin-reading-stuck-monitor-and-test)：滑动窗口 / 异步读取削峰；当前、前、后三个物理页面提前布局，翻页只绘制；CPU、GPU、GC 分开定位。这是腾讯测试工程师的历史经验，不代表当前微信读书实现。文中 60fps、16.6ms 及监控阈值也不直接作为本手机的验收标准。
- [微信读书团队 iOS 分享，2016](https://wereadteam.github.io/2016/05/03/WeRead-Performance/)：优先预处理阅读排版、延后非关键数据；控制并发、验证排版结果。这是历史 iOS 实践，没有直接移植 Objective-C 排版引擎。
- [V2EX 1195212](https://www.v2ex.com/t/1195212)：阅读了问题和评论。发帖者明确没有实锤，原生 / WebView 判断只是社区推测；评论链接的开源方案可以核验，但不能据此认定番茄或起点的现行架构。
- Legado 固定提交 `5198645f0a504b1f6d1259885317e056ff6a4a02` 的 PageDelegate、HorizontalPageDelegate、SlidePageDelegate、PageView、ReadView、CanvasRecorder：完整核对触摸、取消、abortAnim、录制 / 平移 / 交接。它依赖 Android View / Canvas / StaticLayout，直接接入会替换 Flutter 选字、字体排版和页面体系；本轮不做这个高风险迁移。保留已有三纸面绘制记录、接管已接受旧翻页的方法，没有声称移植整个 Legado 引擎。
- [readest/foliate-js 5003bbbd0fd260682b9875af5ac11c40191570a2](https://github.com/readest/foliate-js/commit/5003bbbd0fd260682b9875af5ac11c40191570a2)：分开样式、宿主加载、分页；异步返回后重新检查是否正在拖动；备用内容等待两个空闲帧，真正需要的边界页优先。本轮参考这个调度方法，在 Flutter UI isolate 中共用一个队列；不是复制 JS / DOM 引擎。
- [readest/foliate-js 15fc999f854a41ed6111b8d57c7f25fb97693419](https://github.com/readest/foliate-js/commit/15fc999f854a41ed6111b8d57c7f25fb97693419)：动画复用不变的背景 / 几何数据，暂停拖动中的备用章排版。书叶没有 DOM 强制布局，但原 AnimatedBuilder 每帧重建纸面外层；对应采用框架自带的 [Flow](https://api.flutter.dev/flutter/widgets/Flow-class.html)，直接复用 Flutter 的 RenderFlow、裁切、变换后命中测试、绘制层，而非自己写渲染器。
- upstream foliate-js `9fd2209b4d33fd759760a56cc8247cc9e29f03b4` paginator 的 `scrollBy`：把实际滚动位置限制到有效邻页。对应修复书叶在全书边界累计不可见位移的死区；无相邻页时丢弃越界位移，反向增量立即移动。不改已认可的 Readium 收尾曲线 / 时长；另外按 Legado HorizontalPageDelegate 的跨原点方向切换，完整越过原点的反向拖动更新初始方向，仅反向收手仍撤回。
- [Readest PR 3827](https://github.com/readest/readest/pull/3827)，合并 `030a7c08238d152316942539a2396b97518d3a1c`：核对实际 diff，主要处理大书库索引、状态更新、存储及稳定 debounce。书叶保存的是 SQLite 的三个进度字段，已有 ProgressQueue 合并写入，没有每翻一页序列化整座书库；因此不生搬这套 Zustand / JSON 存储代码。

本轮复用的是 Flutter 官方组件；外部阅读器提供方法对照，适配代码由书叶实现。没有新增依赖、字体、图片或原生渲染后端。平移每帧只重定位准备好的三纸面，拖动位移由 ValueNotifier 通知绘制，不重新构造组件树；实际页面交接和首次新远页仍需要更新内容。前后章原本各有 2ms 预算，现在合起来每帧至多供给一页 / 一批测量，并轮流推进；文本预处理独占一个准备批次。必需目标章优先，拖动中暂停备用任务；失效工作不能发布缓存。

2ms 是让出执行权的目标，不是单次 TextPainter / prepareText 的耗时上限；整章完成才发布、极长章节冷加载和当前章首次同步分页仍有边界。真实手感以 release 对 release 的同设备人工验收为准，记录见 verification-paging-2026-10-11.md。
