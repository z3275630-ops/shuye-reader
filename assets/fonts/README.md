# 书叶界面与阅读字体

`ShuyeSerif-Regular.ttf` 是 Noto Serif SC 的静态 400 字重裁剪版本。来源为 [google/fonts](https://github.com/google/fonts/tree/9710da1eacb3be272583c3224dcb70f9da6eadbb/ofl/notoserifsc)，原文件 `NotoSerifSC[wght].ttf`，SHA-256 为 `050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9`。原始字体与许可的 Git blob 已与固定提交核对。

沿用 [SIL Open Font License 1.1](OFL.txt)，保留上游版权。修改后的内部字体名称为 Shuye Serif，避免把裁剪产物当作完整原字体。没有使用 Anthropic 的专有字体或提取 Claude APP 资源。

- 覆盖 GB2312 常用字符、其 OpenCC 单字繁体映射、当前界面中的汉字、基础拉丁与常用标点，共 10,353 个码点。没有修改书籍文字；生僻字、其他语言及 emoji 由系统回退，不能保证所有 Unicode 字符都具有相同字形。
- 0.3.12 新增实际 600 字重 `ShuyeSerif-SemiBold.ttf`，供顶栏、小标题、列表与导航使用；正文保持 400。600 子集仅覆盖当前界面汉字、基础拉丁与标点，共 1,284 个码点，373,816 字节，压缩估算 235,395 字节。任意书名的生僻字可能回退，不宣称完整正文粗体覆盖。未完成所有 Android 厂商系统上的字体回退验证。
- 字体 4,622,324 字节；压缩估算 2,745,176 字节。最终 APK 增量以版本验证为准。`README.md`、`font-audit.json` 不打包；字体与 OFL 文本按 pubspec 显式注册。
- 许可通过 `LicenseRegistry` 显示于应用开源许可页面。

## 重新裁剪

开发工具为 Python、FontTools 4.66.1、Brotli 1.2.0；不属于 APP 运行依赖。将上述固定版本源文件另存于仓库外，在隔离 Python 环境中安装工具后运行：

```sh
python tools/subset_serif.py /path/to/NotoSerifSC-variable.ttf /path/to/output
python tools/subset_ui_semibold.py /path/to/NotoSerifSC-variable.ttf /path/to/output
```

脚本核对源文件 SHA-256，读取仓库的界面文字与既有 OpenCC 字典，输出字体及审计文件；不联网、不改动原文件。字体保存时间戳或工具版本可能影响二进制校验值，更新资源时重新记录校验、覆盖率与 APK 成本，并保留 OFL。不要按用户书库内容裁剪或提交个人书籍。

## 0.3.13：界面黑体与正文分开

界面改用 Shuye Sans（Noto Sans SC 的静态裁剪版本），操作文字 400、标题和导航 600；欢迎语保留书页衬线。正文独立选择“清晰黑体 / 书页宋体”，旧正文选择及个人导入字体不自动改写。界面采用 20dp 面板标题、18dp 顶栏、15dp 列表、14dp 导航，保留系统缩放；不通过放大字号制造层次。

固定上游：[google/fonts Noto Sans SC](https://github.com/google/fonts/tree/a85815a42757630ce188fdad368c2dfc444d4773/ofl/notosanssc)，源文件 `NotoSansSC[wght].ttf`，SHA-256 `a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da`。保留 [Sans-OFL.txt](Sans-OFL.txt) 原版权与 OFL；修改后改名 Shuye Sans。

- 400：10,353 码点、3,305,012 字节，DEFLATE 估算 2,038,112 字节。沿用既有公开常用中文与繁体映射覆盖；不是按个人书籍裁剪。书名和正文也可以使用，生僻字 / 其他语言 / emoji 由系统回退。
- 600：1,284 码点、268,576 字节，压缩估算 177,808 字节。覆盖当前 UI、基础拉丁和常用标点；不宣称任意正文或生僻书名的完整 600 字形覆盖。
- 没有字体包运行依赖，不打包 17.77 MB 的完整源字体。原阅读宋体资源与字重保留。最终 APK 增量见本版验证，不能直接把 TTF 大小当作安装包增量。
- `tools/subset_sans.py` 用 FontTools 4.66.1 验证源哈希，实例化 400 / 600，裁剪并改内部名称，输出 `sans-audit.json`。该审计文件不打包；APP 许可页显示 Noto Sans SC / Shuye Sans。

```sh
python tools/subset_sans.py /path/to/NotoSansSC-variable.ttf
```
