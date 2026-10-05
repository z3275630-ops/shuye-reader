# 书叶衬线字体

`ShuyeSerif-Regular.ttf` 是 Noto Serif SC 的静态 400 字重裁剪版本。来源为 [google/fonts](https://github.com/google/fonts/tree/9710da1eacb3be272583c3224dcb70f9da6eadbb/ofl/notoserifsc)，原文件 `NotoSerifSC[wght].ttf`，SHA-256 为 `050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9`。原始字体与许可的 Git blob 已与固定提交核对。

沿用 [SIL Open Font License 1.1](OFL.txt)，保留上游版权。修改后的内部字体名称为 Shuye Serif，避免把裁剪产物当作完整原字体。没有使用 Anthropic 的专有字体或提取 Claude APP 资源。

- 覆盖 GB2312 常用字符、其 OpenCC 单字繁体映射、当前界面中的汉字、基础拉丁与常用标点，共 10,353 个码点。没有修改书籍文字；生僻字、其他语言及 emoji 由系统回退，不能保证所有 Unicode 字符都具有相同字形。
- 只保留一个实际 400 字重。界面请求 500 / 600 时由 Flutter / 字体引擎处理，没有额外打包粗体或可变字体。未完成所有 Android 厂商系统上的字体回退验证。
- 字体 4,622,324 字节；压缩估算 2,745,176 字节。最终 APK 增量以版本验证为准。`README.md`、`font-audit.json` 不打包；字体与 OFL 文本按 pubspec 显式注册。
- 许可通过 `LicenseRegistry` 显示于应用开源许可页面。

## 重新裁剪

开发工具为 Python、FontTools 4.66.1、Brotli 1.2.0；不属于 APP 运行依赖。将上述固定版本源文件另存于仓库外，在隔离 Python 环境中安装工具后运行：

```sh
python tools/subset_serif.py /path/to/NotoSerifSC-variable.ttf /path/to/output
```

脚本核对源文件 SHA-256，读取仓库的界面文字与既有 OpenCC 字典，输出字体及审计文件；不联网、不改动原文件。字体保存时间戳或工具版本可能影响二进制校验值，更新资源时重新记录校验、覆盖率与 APK 成本，并保留 OFL。不要按用户书库内容裁剪或提交个人书籍。
