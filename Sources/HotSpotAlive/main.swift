import AppKit
import Network
import ServiceManagement
import IOKit.pwr_mgt

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private let monitor = NWPathMonitor()
    private let heartbeat = TinyHeartbeat()
    private var path: NWPath?
    private var policy = IdlePolicy()
    private var timer: Timer?
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let enabledItem = NSMenuItem()
    private let statusLine = NSMenuItem()
    private let networkLine = NSMenuItem()
    private let resultLine = NSMenuItem()
    private let usageLine = NSMenuItem()
    private let loginItem = NSMenuItem()
    private let otherWiFiItem = NSMenuItem()
    private let sleepItem = NSMenuItem()
    private var intervalItems: [NSMenuItem] = []
    private var serverItems: [NSMenuItem] = []
    private var networkSignature: String?
    private var sleeping = false
    private var assertion: IOPMAssertionID = 0
    private var activity: NSObjectProtocol?
    private var status = "正在检查网络"
    private var network = "尚未连接"
    private var lastResult = "本次尚未发送保活请求"
    private var attempts = 0
    private var successes = 0
    private var estimatedBytes = 0
    private var enabled: Bool { defaults.bool(forKey: "enabled") }
    private var interval: Double { defaults.double(forKey: "interval") }
    private var server: String { defaults.string(forKey: "server") ?? "223.5.5.5" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LaunchServices normally ensures a single instance. Cover direct executable launches too.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: {
               $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
           }) {
            NSApp.terminate(nil)
            return
        }
        defaults.register(defaults: ["enabled": true, "interval": 25.0,
                                     "server": "223.5.5.5", "otherWiFi": false, "preventSleep": true])
        if ![15.0, 25.0, 45.0, 60.0].contains(interval) { defaults.set(25.0, forKey: "interval") }
        if !["223.5.5.5", "119.29.29.29", "1.1.1.1"].contains(server) {
            defaults.set("223.5.5.5", forKey: "server")
        }
        NSApp.setActivationPolicy(.accessory)
        buildMenu()
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                self.path = path
                self.resetNetwork()
                self.tick()
            }
        }
        monitor.start(queue: DispatchQueue(label: "HotSpotAlive.path", qos: .utility))
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refreshMenu()

        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self else { return }
                print("menu=\(self.statusItem.button?.title ?? "missing")")
                print("status=\(self.status)")
                print("network=\(self.network)")
                print("items=\(self.menu.items.count), heartbeatAttempts=\(self.attempts)")
                NSApp.terminate(nil)
            }
        }
    }

    @discardableResult
    private func item(_ title: String, action: Selector? = nil, into parent: NSMenu? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        (parent ?? menu).addItem(item)
        return item
    }

    private func configure(_ item: NSMenuItem, title: String, action: Selector? = nil) {
        item.title = title
        item.action = action
        item.target = self
        menu.addItem(item)
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        menu.delegate = self
        menu.autoenablesItems = false
        configure(enabledItem, title: "启用 HotSpotAlive", action: #selector(toggleEnabled))
        menu.addItem(.separator())
        for line in [statusLine, networkLine, resultLine, usageLine] {
            line.isEnabled = false
            menu.addItem(line)
        }
        menu.addItem(.separator())
        let intervals = NSMenu()
        intervals.autoenablesItems = false
        item("空闲多久后保活").submenu = intervals
        for seconds in [15, 25, 45, 60] {
            let child = item("\(seconds) 秒" + (seconds == 25 ? "（推荐）" : ""), action: #selector(setInterval(_:)), into: intervals)
            child.tag = seconds
            intervalItems.append(child)
        }
        let servers = NSMenu()
        servers.autoenablesItems = false
        item("保活服务器（DNS）").submenu = servers
        for (index, name) in ["阿里 DNS · 223.5.5.5", "腾讯 DNS · 119.29.29.29", "Cloudflare · 1.1.1.1"].enumerated() {
            let child = item(name, action: #selector(setServer(_:)), into: servers)
            child.tag = index
            serverItems.append(child)
        }
        configure(otherWiFiItem, title: "也在普通 Wi-Fi 上保活", action: #selector(toggleOtherWiFi))
        configure(sleepItem, title: "保活时防止自动睡眠（允许熄屏）", action: #selector(toggleSleep))
        configure(loginItem, title: "登录时启动", action: #selector(toggleLogin))
        menu.addItem(.separator())
        item("使用说明…", action: #selector(showHelp))
        item("打开 Wi-Fi 设置…", action: #selector(openWiFi))
        item("退出 HotSpotAlive", action: #selector(quit)).keyEquivalent = "q"
    }

    private func tick() {
        defer { refreshMenu() }
        guard enabled, !sleeping else {
            status = enabled ? "Mac 正在睡眠，暂停保活" : "已关闭保活"
            stopWork()
            return
        }
        guard let path, path.status == .satisfied,
              path.usesInterfaceType(.wifi),
              let interface = path.availableInterfaces.first(where: { $0.type == .wifi }) else {
            status = "等待 Wi-Fi 连接"
            network = "没有可用的 Wi-Fi 出口"
            stopWork()
            return
        }
        let router = InterfaceTraffic.router(interface.name)
        let isHotspot = HotspotPolicy.allows(isWiFi: true, isExpensive: path.isExpensive,
                                            router: router, allowOtherWiFi: false)
        network = "\(interface.name) · \(isHotspot ? "热点/按流量计费网络" : "普通 Wi-Fi")"
        guard HotspotPolicy.allows(isWiFi: true, isExpensive: path.isExpensive,
                                  router: router, allowOtherWiFi: defaults.bool(forKey: "otherWiFi")) else {
            status = "等待热点（普通 Wi-Fi 不保活）"
            stopWork()
            return
        }
        let signature = InterfaceTraffic.signature(interface.name) + ":" + (router ?? "")
        if signature != networkSignature {
            resetNetwork()
            networkSignature = signature
        }
        guard let sample = InterfaceTraffic.read(interface.name) else {
            status = "无法读取流量计数，已暂停"
            stopWork()
            return
        }
        updatePower(active: true)
        guard !heartbeat.isRunning else { status = "正在发送微量保活请求"; return }
        switch policy.sample(sample, now: ProcessInfo.processInfo.systemUptime, interval: interval) {
        case .active: status = "网络有流量，跳过保活"
        case .warmingUp, .waiting: status = "监测空闲中（\(Int(interval)) 秒后保活）"
        case .unavailable: status = "无法读取流量计数，已暂停"
        case .heartbeat:
            status = "正在发送微量保活请求"
            attempts += 1
            heartbeat.start(interface: interface, server: server) { [weak self] success, sent, received in
                guard let self else { return }
                self.estimatedBytes += sent + received
                if success { self.successes += 1 }
                let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                self.lastResult = "\(time) · " + (success ? "保活收到回应" : "未收到有效回应，可尝试更换服务器")
                self.status = success ? "保活成功，继续监测" : "本次保活未确认，继续监测"
                // Start a fresh idle window so our own response is not counted as another app.
                self.policy.reset()
                _ = self.policy.sample(InterfaceTraffic.read(interface.name),
                                      now: ProcessInfo.processInfo.systemUptime, interval: self.interval)
                self.refreshMenu()
            }
        }
    }

    private func resetNetwork() {
        policy.reset()
        heartbeat.cancel()
        networkSignature = nil
    }

    private func stopWork() {
        resetNetwork()
        updatePower(active: false)
    }

    private func updatePower(active: Bool) {
        if active && activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                             reason: "定期检查热点空闲状态")
        } else if !active, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        if active && defaults.bool(forKey: "preventSleep") {
            if assertion == 0 {
                let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                        "HotSpotAlive 热点保活（允许显示器休眠）" as CFString, &assertion)
                if result != kIOReturnSuccess { assertion = 0 }
            }
        } else if assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
    }

    private func refreshMenu() {
        statusItem.button?.title = enabled ? "HSA 开" : "HSA 关"
        statusItem.button?.image = nil
        statusItem.button?.imagePosition = .noImage
        statusItem.button?.toolTip = "HotSpotAlive · \(status)"
        enabledItem.state = enabled ? .on : .off
        statusLine.title = status
        networkLine.title = network
        resultLine.title = lastResult
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(estimatedBytes), countStyle: .decimal)
        usageLine.title = "本次启动：\(attempts) 次尝试 / \(successes) 次回应 · 约 \(bytes)"
        otherWiFiItem.state = defaults.bool(forKey: "otherWiFi") ? .on : .off
        sleepItem.state = defaults.bool(forKey: "preventSleep") ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginItem.title = SMAppService.mainApp.status == .requiresApproval ? "登录时启动（等待系统批准）…" : "登录时启动"
        for item in intervalItems { item.state = Double(item.tag) == interval ? .on : .off }
        let index = ["223.5.5.5", "119.29.29.29", "1.1.1.1"].firstIndex(of: server)
        for item in serverItems { item.state = item.tag == index ? .on : .off }
    }

    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }

    @objc private func toggleEnabled() {
        defaults.set(!enabled, forKey: "enabled")
        resetNetwork()
        tick()
    }
    @objc private func toggleOtherWiFi() {
        defaults.set(!defaults.bool(forKey: "otherWiFi"), forKey: "otherWiFi")
        resetNetwork()
        tick()
    }
    @objc private func toggleSleep() {
        defaults.set(!defaults.bool(forKey: "preventSleep"), forKey: "preventSleep")
        tick()
    }
    @objc private func setInterval(_ sender: NSMenuItem) {
        defaults.set(Double(sender.tag), forKey: "interval")
        resetNetwork()
        tick()
    }
    @objc private func setServer(_ sender: NSMenuItem) {
        defaults.set(["223.5.5.5", "119.29.29.29", "1.1.1.1"][sender.tag], forKey: "server")
        resetNetwork()
        tick()
    }
    @objc private func toggleLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled: try SMAppService.mainApp.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法更改登录启动设置"
            alert.informativeText = "请先将 HotSpotAlive.app 放入“应用程序”文件夹，再重新打开。\n\(error.localizedDescription)"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        refreshMenu()
    }
    @objc private func willSleep() { sleeping = true; tick() }
    @objc private func didWake() { sleeping = false; resetNetwork(); tick() }
    @objc private func openWiFi() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") { NSWorkspace.shared.open(url) }
    }
    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "HotSpotAlive 1.0"
        alert.informativeText = "勾选“启用 HotSpotAlive”后，默认只在系统识别为热点/按流量计费的 Wi-Fi，或网关为 172.20.10.1 的网络工作。无需同一 iCloud 账号。\n\n每 5 秒读取一次接口计数；有任何收发流量就推迟保活，连续空闲 25 秒才发送一次微量 DNS 查询。若热点没有被识别，可勾选“也在普通 Wi-Fi 上保活”。\n\n默认向阿里 DNS（223.5.5.5）查询固定的 example.com，单次发送含 IP/UDP 头约 57 字节，另有少量回复；不上传浏览记录。请求绑定 Wi-Fi，可能绕过 VPN/代理；可在菜单更换服务器。\n\n默认在保活工作时防止 Mac 自动睡眠，允许屏幕熄灭；可取消勾选以节电。合盖、手动睡眠及 iPhone 主动断开无法阻止，断开后需手动重连。\n\n流量显示为本次启动的估计值，不是运营商账单。"
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        monitor.cancel()
        stopWork()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
