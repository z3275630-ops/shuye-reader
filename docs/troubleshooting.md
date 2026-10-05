# 症状 → 真因

排错时先查这张表。每一行都指向**已定位过的具体原因**，而不是猜测；新增行请附证据（Issue 编号、验证记录或源码位置），没有证据的观察不要写进来。

范围：本书只覆盖「能被症状检索到」的实现坑。功能边界与待做项见 [功能对照](report-coverage.md)，逐版本验证见 `verification-*.md`。

## 日期与统计

| 症状 | 真因与定位 | 来源 |
| --- | --- | --- |
| 热力图或统计的日期整体偏一天 | 用绝对时间减法（`Duration(days:)` / ±24 小时）推算自然日，跨夏令时或时区变化后偏移。正确做法是按自然日构造（`DateTime(y, m, d ± n)`），天数差用 UTC 分量计算 | [#4](https://github.com/z3275630-ops/shuye-reader/issues/4)、`docs/architecture.md:60` |
| 「累计阅读 / 阅读天数」与热力图数字对不上 | 热力图主动排除未来与范围外日期，汇总却对整张表求和。备份来自时钟被调快的设备、或恢复过手工编辑的备份时最明显 | [#53](https://github.com/z3275630-ops/shuye-reader/issues/53) |
| 日历上永远看不到某一天，但总时长算得进去 | 恢复备份时 `day` 只做形状正则（`^\d{4}-\d{2}-\d{2}$`），`2026-02-31` 一类非法日期被入库；热力图按网格推算合法日期，永远匹配不到 | [#53](https://github.com/z3275630-ops/shuye-reader/issues/53) |
| 桌面小组件的「近 7 天 / 28 天」在时区变化后偏一天 | 同第一行：用绝对时间减法取日历日 | [#4](https://github.com/z3275630-ops/shuye-reader/issues/4) |

## 书库、迁移与备份

| 症状 | 真因与定位 | 来源 |
| --- | --- | --- |
| 升级到加密库后每次启动都停在「无法打开本地书库」 | 迁移把整库快照交给带 80 MB 上限的 `restore()`，抛错点早于写入迁移标记与删除旧库，于是每次启动重跑同一段必然失败的代码；另一条路径是单本解析失败使迁移循环 | [#34](https://github.com/z3275630-ops/shuye-reader/issues/34)、[#2](https://github.com/z3275630-ops/shuye-reader/issues/2) |
| 磁盘上一直有一份 `shuye-migration-recovery.json` | 迁移恢复快照只写不读、无清理点也无应用内入口 | [#50](https://github.com/z3275630-ops/shuye-reader/issues/50) |
| 云端恢复成功后，设置又变回旧的 | 恢复只更新数据库，内存里的 `ReaderSettings` 未刷新；而设置写入是整行覆盖，同一次工具箱会话内任何保存都会把旧配置写回 | [#51](https://github.com/z3275630-ops/shuye-reader/issues/51) |
| 备份里少了刚读的几分钟 | `backup()` / `restore()` 未 flush 阅读计时队列（`deleteBook` 有 flush），内存中未落库的批次不在备份里 | [#52](https://github.com/z3275630-ops/shuye-reader/issues/52) |
| `reader.config` 损坏后首页/书架/统计全空 | 读取失败时的恢复体验问题，需要设备身份验证后恢复设置并保留原内容 | [#3](https://github.com/z3275630-ops/shuye-reader/issues/3) |

## 导入

| 症状 | 真因与定位 | 来源 |
| --- | --- | --- |
| 导入后整本书是乱码，但显示「导入成功」 | `decodeText` 整文件二选一编码探测（严格 UTF-8 失败即整本转 GBK），而 GBK 解码器对任何字节序列都不抛错，于是静默产出垃圾 | [#35](https://github.com/z3275630-ops/shuye-reader/issues/35) |
| EPUB 的书名、作者、正文一起变成 `U+FFFD` | EPUB 内部文件一律 `utf8.decode(..., allowMalformed: true)`，忽略 `<?xml encoding?>` 与 `<meta charset>` | [#46](https://github.com/z3275630-ops/shuye-reader/issues/46) |
| 中文 RTF 导入后是 `µÚÒ»ÕÂ` 这类字符 | `\'hh` 被逐字节当 Latin-1，没有按 `\ansicpgN` 组装双字节 | [#48](https://github.com/z3275630-ops/shuye-reader/issues/48) |
| 结构略有瑕疵的 EPUB 被整本拒收 | spine 中任一文件缺失（或大小写不一致）即抛异常，已解析的章节一并丢弃 | [#47](https://github.com/z3275630-ops/shuye-reader/issues/47) |
| 导入或阅读时应用假死，无进度也无法取消 | 分章/净化规则命中灾难性回溯；`validateRules` 只拦带括号的嵌套量词，无括号的 `.*` 连写可放行 | [#49](https://github.com/z3275630-ops/shuye-reader/issues/49) |
| 导入 ZIP / CBZ / EPUB 时 OOM 或被系统杀掉 | 解压上限用中央目录里可伪造的声明大小判断，且该版本 `archive` 的 `verify` 对 ZIP 无效、解压本身没有输出上限 | [#33](https://github.com/z3275630-ops/shuye-reader/issues/33) |
| 大书库导入 / 备份 / 恢复长时间无响应 | CBZ/PDF 正文在单列内拼接常驻，属已知的存储规模问题 | [#18](https://github.com/z3275630-ops/shuye-reader/issues/18) |

## 界面与交互

| 症状 | 真因与定位 | 来源 |
| --- | --- | --- |
| 深色或夜读纸面下选中文字看不清 | 阅读子主题未按纸色派生 `textSelectionTheme`，沿用了应用主题的强调色 | [#37](https://github.com/z3275630-ops/shuye-reader/issues/37) |
| 深色主题下某处文字或线条不可读 | 硬编码颜色未走 `ColorScheme`。历史位置已随 PR #16 修复，仍有新位置（例如雨雪粒子） | [#15](https://github.com/z3275630-ops/shuye-reader/issues/15)、[#11](https://github.com/z3275630-ops/shuye-reader/issues/11) |
| 320dp 屏幕或 1.5 倍字号下界面溢出 | 固定尺寸控件加没有收缩能力的文本；验收要求见 `AGENTS.md`「实现约定」 | [#38](https://github.com/z3275630-ops/shuye-reader/issues/38) |
| 快速连点书籍封面出现两个阅读页、时长翻倍 | 书籍入口无重入保护，且阅读页只跟应用前后台判断是否计时，被压在下面的页面仍在计时 | [#39](https://github.com/z3275630-ops/shuye-reader/issues/39) |
| 切 Tab 回来后书架像「丢了书」 | 搜索框没有 controller，`query` 留在 State 里继续生效，输入框却被销毁 | [#40](https://github.com/z3275630-ops/shuye-reader/issues/40) |
| 翻页时整屏刷白 | 曾经是「淡入」伪装成翻页，已改为真平移 + 真淡入 | [#20](https://github.com/z3275630-ops/shuye-reader/issues/20) |

## 构建、测试与体积

| 症状 | 真因与定位 | 来源 |
| --- | --- | --- |
| 预览截图测试被跳过 | 需要 `SHUYE_CAPTURE_DIR` 与本机字体路径，默认跳过；预览不能当作真机验证 | `docs/ui-design.md:22` |
| Windows 中文路径下构建失败 | 着色器编译器在含非 ASCII 的路径上会崩溃，改用纯 ASCII 路径构建 | `docs/windows-build.md` |
| release 包体积异常增大 | 新增字体 / 图片 / 原生库；`AGENTS.md` 要求记录 release APK 实测体积，图像只打包 pubspec 列出的压缩资源 | `AGENTS.md` |
| 「已修复」的功耗或帧耗时结论无法复现 | 耗电、发热、帧耗时必须真机 release / profile 测量，预览渲染不能代替 | `AGENTS.md` |

## 怎么加一行

1. 先确认**真因**而不只是现象：能指到某个文件的具体位置，或有复现记录；
2. 填「来源」列：关联 Issue、`docs/verification-*.md`、或源码位置；
3. 如果只是一个待验证的猜测，写进对应 Issue，不要放进本表——这张表的价值在于**每一行都可信**。
