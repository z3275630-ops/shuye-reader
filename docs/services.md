# 服务配置与数据流

## AI

设置 → 阅读工具箱 → AI 服务配置。输入用户自己的兼容接口根地址（通常含 /v1）、模型与 API 密钥，填配置名称后可保存多套组合；“切换 AI 服务与模型”可选已有配置。密钥只进入平台安全存储，配置记录和备份不包含密钥。恢复到新手机后需重新输入。

阅读助手发送前显示范围：选中文字 / 当前页传入的摘录、当前章最多 3 万字符，或书名 / 作者 / 进度。点击发送才请求服务。自定义提示词中的记录可从助手界面直接使用；问答保存在本机。服务商可能计费。

## 加密快照

所有云上传先用用户提供的备份密码做 PBKDF2-SHA256（150000 次，随机 salt）和 AES-256-GCM。恢复先认证、验证数据，再事务替换。令牌 / 密码不写入快照。备份密码至少 8 个字符，APP 不保留密码。

WebDAV：完整 HTTPS 文件地址、账号、密码。S3：完整对象 HTTPS 地址、Access Key、Secret Key、区域。OneDrive / Dropbox / Google Drive：访问令牌放在“密码 / Secret Key”字段，云盘路径如 `/shuye-backup.json`；Google 使用文件 ID，首次上传成功自动记住。令牌需要用户相应文件权限，当前不自动 OAuth 登录或刷新。下载是替换恢复，不是合并。

## KOReader

选择书籍后填写服务器、用户、密码与原文件名。在 KOReader 选择按文件名匹配，也可手填文档校验值。下载后先显示当前 / 远端百分比，确认后才应用。文本书按总字符近似定位，不生成 KOReader xpointer；上传仅支持已打开、已确认页数的 PDF。

## MCP

在工具箱手动启动后显示地址和随机 Bearer 令牌。仅本机 loopback，退出工具箱 / 后台时关闭；下次启动令牌改变。客户端需完成 initialize 和 session handshake。

工具：`library`、`notes`、`statistics`、`search`、`propose_book_update`。最后一个只创建待检查建议，允许书名、作者、分类、标签、书单、评分和书评。应用中“书籍修改建议”显示前后差异；点击应用后事务更新，原资料已变化则拒绝过时建议。原文 / 删除 / 网络调用不向客户端开放。

## Wi-Fi 备份传输

只在用户输入加密密码、启动后临时监听本机局域网。电脑浏览器打开显示的随机链接即可下载加密文件；链接不包含备份密码，最多三次、十分钟失效。停止 / 关闭窗口 / 后台 / 离开工具箱会关闭。只有下载接口，无目录浏览、上传或修改功能。电脑与手机需连接可互通的同一网络，受系统防火墙限制时不会自动修改防火墙。

## 系统与本地模型

中文 ML Kit 模型打包进 APK；识字处理留在手机。系统 TTS 使用手机安装的引擎，联网语音会在列表标注；其隐私和可用性由系统引擎决定。后台音频可点击“允许播放通知”请求安卓通知权限，未允许时应在 APP 内控制。

## 实现依据

- [PDFium / pdfrx](https://pub.dev/packages/pdfrx)
- [ML Kit 文字识别](https://developers.google.com/ml-kit/vision/text-recognition/v2/android)
- [just_audio_background](https://pub.dev/packages/just_audio_background)
- [SQLCipher 插件](https://pub.dev/packages/sqflite_sqlcipher)
- [OpenCC](https://github.com/BYVoid/OpenCC)
- [OneDrive 文件上传](https://learn.microsoft.com/en-us/graph/api/driveitem-put-content?view=graph-rest-1.0)
- [Google Drive 上传](https://developers.google.com/workspace/drive/api/guides/manage-uploads)
- [Dropbox HTTP 文档](https://www.dropbox.com/developers/documentation/http/documentation)
- [KOReader 协议定义](https://github.com/koreader/koreader/blob/master/plugins/kosync.koplugin/api.json) 与 [认证实现](https://github.com/koreader/koreader/blob/master/plugins/kosync.koplugin/KOSyncClient.lua)
- [MCP 2025-11-25 传输规范](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)

协议适配及 mock 测试不等同于真实账号联调，验证状态单独记录。
