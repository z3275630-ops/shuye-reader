# Windows 构建说明

本机存在中文用户名。为了避免 Kotlin 脚本编译和 Flutter tester 的临时 dill 文件路径问题，本次构建使用临时英文工作区、英文 Gradle 缓存与 `TEMP` / `TMP`。原项目保存在交付目录，不修改现有 Flutter 安装或 Windows 全局环境。

可在英文路径中的 checkout 运行下面命令。SDK / JDK 路径按实际安装修改：

```powershell
$env:ANDROID_HOME = 'C:\android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PUB_CACHE = 'C:\pub-cache'
$env:GRADLE_USER_HOME = 'C:\tmp\shuye-gradle'
$env:TEMP = 'C:\tmp\shuye-temp'
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Path $env:TEMP,$env:GRADLE_USER_HOME -Force
& 'C:\flutter\bin\flutter.bat' pub get --enforce-lockfile
& 'C:\flutter\bin\flutter.bat' analyze
& 'C:\flutter\bin\flutter.bat' test --concurrency=1
& 'C:\flutter\bin\flutter.bat' build apk --release --target-platform android-arm64 --split-per-abi
```

如果复制本地源码到英文工作区，排除 `.git`、`.dart_tool`、`build`、`android/.gradle` 和 `android/local.properties`，在新目录重新 `flutter pub get`。签名路径要指向真实可用的英文路径，不能只建立目录联接来规避 Java 解析后的中文路径。

如果依赖下载被网络阻断，可在自己指定的 `GRADLE_USER_HOME/gradle.properties` 配置当前可用的本地 HTTP 代理。代理地址取决于本机配置，不应写进项目或提交 Git。连接恢复后再构建；不要关闭 TLS 验证。

GitHub Actions 使用 Linux runner，不使用这些本机路径、密码或代理配置。

## 多 Agent 共用本机

每个 Agent 必须使用独立 checkout / 构建副本、项目 build、.dart_tool 和 TEMP / TMP；只切换同一目录的分支不能隔离文件。不要在同一副本同时运行 Flutter 测试、截图与 APK 构建，避免原生测试资源文件锁。SDK 启动锁或 Gradle 缓存锁出现等待时先等，不删除锁、清缓存、升级 SDK 或结束其他 Agent 的进程。

0.3.9 主 Agent 的验证副本为 `C:/tmp/shuye-main-039-20261005`，临时文件为 `C:/tmp/shuye-temp-039`；正式源码仍以原仓库 main 为准。这些是本轮保留目录，不供其他 Agent 同时使用；后续任务另选独立目录。共享 PUB_CACHE / Gradle 依赖缓存有各自的锁，不能靠清理缓存解决别人的正在运行的构建。

追加修复后的回归副本为 `C:/tmp/shuye-main-039-verify-20261005`、临时目录 `C:/tmp/shuye-verify-temp-039`，与 APK 构建分别运行；源码与依赖锁、字体在交付前核对一致。不要把旧构建副本当作正式源码。
