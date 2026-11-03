# HotSpotAlive

原生 macOS 菜单栏热点保活程序，支持 **Intel 和 Apple Silicon（M 系列）Mac、macOS 13 及以上**。无需同一 iCloud 账号，无第三方运行依赖，无 Dock 图标。

原始 logo 保留在项目根目录的 `app logo.png`；应用图标使用去除外围黑色背景的 `Resources/AppIconArtwork.png`，构建时通过原生圆角裁切生成多尺寸、透明背景的 macOS 图标。菜单栏只显示 `HSA 开` 或 `HSA 关` 文字。

## 安装

在 [GitHub Releases](https://github.com/shawnZheng3927/HotSpotAlive/releases/latest) 中下载 `HotSpotAlive-版本号-Universal.dmg`，双击后把 `HotSpotAlive.app` 拖到 `Applications`（应用程序）文件夹，再从“应用程序”打开。也可以解压 `Universal.zip`，手动复制 app。通用版在两种芯片上原生运行，Apple 芯片不需要 Rosetta。

如果尚未发布到 GitHub，本地安装包位于 `build/release/`。DMG 内附中文安装说明；源码包可以单独备份，换电脑后仍能重新构建。

当前版本使用本机临时签名，尚未进行 Apple 开发者公证。从网上下载后首次打开可能被拦截：先尝试打开，再在“系统设置 → 隐私与安全性”中查看该应用对应的“仍要打开”。仅在确认文件来源后允许；具体以 [Apple 官方说明](https://support.apple.com/102445) 为准。如果系统没有提供允许选项，可以在新 Mac 本机构建。

## 使用

1. 从“应用程序”打开 HotSpotAlive。开发时也可双击 `build/HotSpotAlive.app`。
2. 顶部菜单栏出现 `HSA 开`。点击文字，勾选/取消“启用 HotSpotAlive”即可开关；设置会保留。
3. 连接 iPhone 热点。菜单显示当前是否检测到网络流量、最近一次保活结果，以及本次启动的保活次数和估计流量。
4. 可在菜单勾选“登录时启动”。如 macOS 要求批准，去“系统设置 → 通用 → 登录项与扩展”允许。
5. “退出 HotSpotAlive”完全结束进程并释放睡眠限制；单纯关闭保活会保留菜单栏图标。

程序默认为启用保活。默认只在系统标记为按流量计费的 Wi-Fi 或网关为 `172.20.10.1` 的 Wi-Fi 上工作。macOS 可能无法准确识别不同账号的热点；如果连接了 iPhone，菜单却显示“普通 Wi-Fi”，可以开启“也在普通 Wi-Fi 上保活”。这项设置也会作用于之后连接的普通 Wi-Fi，用完可关闭。

状态栏的“开”表示功能开关已启用，不代表热点已连接或保活一定成功，具体情况看菜单内状态。

## 保活和流量

- 每 5 秒读取 Wi-Fi 接口累计收发字节数，无需管理员权限。读取计数本身不产生网络请求。
- 只要观察到字节增加，本轮就跳过请求，并重新计算空闲时间。后台程序、系统服务、VPN 加密流量都包括在内。
- 连续空闲默认 25 秒后，向公共 DNS 发送一次 `example.com` 的 A 记录查询；也可选 15、45、60 秒。不会下载网页，不会通过本地 DNS 缓存假装产生了外网流量。
- 默认服务器为阿里 DNS `223.5.5.5:53`，菜单可改腾讯 DNS `119.29.29.29` 或 Cloudflare `1.1.1.1`。查询固定公共域名，无遥测、不读取浏览记录。服务器会看到正常 DNS 查询所带的公网 IP。
- 请求明确绑定当前 Wi-Fi 接口，可能绕过 VPN/HTTP 代理。若网络策略禁止公共 UDP DNS，请勿开启，或在允许该流量的网络使用。没有可用 Wi-Fi 时不发送。
- 每次只有一个 UDP 查询，超时 5 秒；失败后等待新的空闲窗口，没有快速重试。保活收到回复表示公共 DNS 可达，并不证明所有网站或 AI 服务都可达。
- 查询负载 29 字节，加 IPv4/UDP 头约 57 字节。典型回复后，一来一回约 130～200 字节；若全天持续空闲、每 25 秒一轮，约 **0.45～0.70 MB/天**。这是网络层估算，链路、运营商计费、重传和回复大小会影响实际流量。有其他流量时会更低。
- 菜单流量仅累计本程序报告发送成功及实际收到的数据，含估计 IP/UDP 头，不是所有软件流量，也不是运营商账单。

接口计数也包含局域网、系统组播等流量，无法精确区分“真正消耗蜂窝流量”和“仅在局域网活动”。频繁的本地流量可能推迟保活。这个实现选择不抓包、不申请管理员权限和定位权限，避免额外常驻服务及隐私权限。

## 睡眠和断连的边界

默认勾选“保活时防止自动睡眠（允许熄屏）”：仅在开关启用且识别到可用目标 Wi-Fi、成功读取流量计数时阻止系统自动空闲睡眠；普通 Wi-Fi、断网、关闭保活或退出时释放。显示器仍可自动关闭。取消勾选可以省电，但 Mac 自动睡眠后无法继续发请求。该功能不阻止手动睡眠或合盖睡眠。

Apple 说明热点闲置时可能为了省电断开。少量外网活动是缓解方法，不能保证阻止 iPhone 的热点管理策略、弱信号、运营商限制或系统故障，也不能在热点已关闭时把它重新打开。不同 iCloud 账号不妨碍普通 Wi-Fi 保活，但此程序不依赖同账号的 Instant Hotspot 自动重连。真正断开后仍需手动连接；有持续流量时也断线，通常需要另查原因。

参考：[Apple 热点使用说明](https://support.apple.com/guide/iphone/share-your-internet-connection-iph45447ca6/ios)、[Apple 热点故障排查](https://support.apple.com/en-ie/119837)、[Network.framework 的按流量计费路径说明](https://developer.apple.com/documentation/network/nwpath/isexpensive)。

## 构建和验证

需 Apple Command Line Tools（`xcode-select --install`），无需完整 Xcode 或第三方包。

```sh
./scripts/test.sh
./scripts/build.sh
open build/HotSpotAlive.app
```

默认输出 `build/HotSpotAlive.app` 和 `build/HotSpotAlive-Universal.zip`。分别以 `x86_64-apple-macosx13.0`、`arm64-apple-macosx13.0` 编译后合并为 Universal Binary，使用本机临时签名（ad hoc）。也可以运行 `./scripts/build.sh intel` 或 `./scripts/build.sh arm64` 仅生成单架构版本。

生成完整的分发文件：

```sh
./scripts/release.sh
```

`build/release/` 内包含 DMG 安装包、Universal ZIP、源码 ZIP 和 SHA-256 校验文件。该命令始终构建双架构版本；所有源码和图标保存在项目内，发布过程不依赖本机的用户目录。

`Tests/main.swift` 验证空闲阈值、忙时零额外请求、收发流量抑制、计数重置、唤醒后重新计时、热点范围和 DNS 回复校验。菜单栏快速检查可运行：

```sh
build/HotSpotAlive.app/Contents/MacOS/HotSpotAlive --smoke-test
```

该检查启动菜单栏应用，约 8 秒后打印状态并退出；请先退出已运行的实例。不会主动改变用户设置。热点持续保活的最终效果需在真实 iPhone 上长时间验证。

`./scripts/network-test.sh` 会在当前 Wi-Fi 上真实发送一次 DNS 保活查询，验证接口计数、热点识别和回复。没有 Wi-Fi 时跳过；它会产生约一两百字节的流量。

## GitHub 发布

源码目录已包含 GitHub Actions：提交到 `main` 或创建 Pull Request 时自动测试、构建安装包；推送与 `Info.plist` 版本一致的标签（例如 `v1.0`）时，自动生成 GitHub Release 并附上安装包、源码包和校验文件。普通构建产物保留 14 天，已发布的安装包通过 Releases 下载。

首次上传、发布和后续更新方法见 [发布说明](docs/PUBLISHING.md)。工作流只执行本地逻辑检查，不会向公共 DNS 发送网络测试请求。

## 卸载

先在菜单取消“登录时启动”，再选择“退出 HotSpotAlive”，删除 app 即可。没有守护进程、抓包组件或额外安装的后台服务。偏好设置保存在 `local.hotspotalive.app`，可选执行 `defaults delete local.hotspotalive.app` 清除。
