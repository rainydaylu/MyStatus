import Foundation

public enum DeckLanguage: String, CaseIterable {
    case system
    case chinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case french = "fr"
    case german = "de"
    case japanese = "ja"
    case korean = "ko"

    public static var current: DeckLanguage {
        DeckLanguage(rawValue: UserDefaults.standard.string(forKey: "ui.language") ?? "system") ?? .system
    }

    public func resolved(preferredLanguage: String? = Locale.preferredLanguages.first) -> DeckLanguage {
        guard self == .system else { return self }
        let parts = (preferredLanguage ?? "").lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" })
        guard let language = parts.first else { return .english }
        if language == "zh" || language == "yue" {
            if parts.contains("hans") { return .chinese }
            return language == "yue" || parts.contains(where: { ["hant", "tw", "hk", "mo"].contains($0) })
                ? .traditionalChinese : .chinese
        }
        return DeckLanguage.allCases.dropFirst().first { $0.rawValue == language } ?? .english
    }

    public var isEnglish: Bool { resolved() == .english }

    public var locale: Locale { Locale(identifier: resolved().rawValue) }

    public var displayName: String {
        switch self {
        case .system: DeckL("跟随系统", "System default")
        case .chinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        case .french: "Français"
        case .german: "Deutsch"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }
}

/// Source strings only. Never pass clipboard contents or user data here.
public func DeckL(_ chinese: String, _ english: String? = nil) -> String {
    DeckLanguage.current.translation(chinese, english: english)
}

public func DeckLF(_ chinese: String, _ english: String, _ arguments: CVarArg...) -> String {
    let language = DeckLanguage.current.resolved()
    return String(format: language.translation(chinese, english: english), locale: language.locale, arguments: arguments)
}

public extension DeckLanguage {
    func translation(_ chinese: String, english: String? = nil) -> String {
        let language = resolved()
        switch language {
        case .chinese: return chinese
        case .traditionalChinese: return DeckTranslations.traditional(chinese)
        default: break
        }
        let base = english ?? DeckTranslations.values[chinese] ?? DeckTranslations.fragments.reduce(chinese) {
            $0.replacingOccurrences(of: $1.0, with: $1.1)
        }
        return DeckLocaleCatalog.values[language]?[base] ?? base
    }
}

enum DeckTranslations {
    static let values: [String: String] = [
        "插件 4 · wxtsky/CodeIsland 原生刘海面板与会话发现。": "Plugin 4 · The native wxtsky/CodeIsland notch panel and session discovery.",
        "wxtsky/CodeIsland 原生刘海面板与会话状态": "Native wxtsky/CodeIsland notch panel and session status",
        "读取本机 AI 工具的会话记录；可选择接收已配置的 CodeIsland 本机 Hook。": "Reads local AI session logs. Receiving configured local CodeIsland hooks is optional.",
        "插件 2 · 截图与图片晾衣绳": "Plugin 2 · Hang screenshots and images",
        "悬浮剪贴板": "Hanging clipboard",
        "Mos 平滑滚动": "Mos smooth scrolling",
        "仅在启用时读取复制的图片和监听截图文件夹。": "Reads copied images and watches screenshot folders only while enabled.",
        "需要辅助功能权限来处理鼠标滚轮；不改变触控板手势。": "Requires Accessibility permission for mouse-wheel events; trackpad gestures remain unchanged.",
        "只在启用时读取本地 Claude / Codex 会话记录，不连接远程设备或发送推送。": "Reads local Claude / Codex transcripts only while enabled. No remote devices or push notifications.",
        "插件 3 · 平滑鼠标滚轮、独立反转方向、速度、惯性和应用排除。": "Plugin 3 · Smooth mouse-wheel scrolling, independent axis reversal, speed, inertia, and app exclusions.",
        "插件 2 · 将截图和复制的图片挂在屏幕顶部。保留 Tendedero 的拖拽、预览、标注和晾衣绳交互。": "Plugin 2 · Hang screenshots and copied images across the top of the screen, with drag, preview, and annotation.",
        "插件 4 · Claude / Codex 会话监测与顶部悬浮岛，使用原始 CodeIslandCore 解析内核。": "Plugin 4 · Claude / Codex session monitoring and a floating island, powered by the original CodeIslandCore parser.",
    "1 秒": "1 second",
    "2 秒": "2 seconds",
    "5 秒": "5 seconds",
    "1000 条": "1,000 items",
    "200 条": "200 items",
    "5000 条": "5,000 items",
    "30 天": "30 days",
    "7 天": "7 days",
    "90 天": "90 days",
    "一年": "One year",
    "永久": "Forever",
    "CPU 与 GPU": "CPU & GPU",
    "App 内存": "App memory",
    "上传": "Upload",
    "下载": "Download",
    "不可用": "Unavailable",
    "不用了": "Cancel",
    "不能调节音量": "Volume cannot be adjusted",
    "主板": "Mainboard",
    "仅 IPv6": "IPv6 only",
    "从运行中的应用添加…": "Add a running app…",
    "代码": "Code",
    "优先 DDC": "Prefer DDC",
    "优先软件音量": "Prefer software volume",
    "传感器": "Sensors",
    "传输速率": "Transmit rate",
    "低电量模式": "Low Power Mode",
    "使用电池": "On battery",
    "侧边栏剪贴板": "Clipboard sidebar",
    "保留时间": "Retention",
    "信号": "Signal",
    "信道": "Channel",
    "充入电池": "Charging battery",
    "充电中": "Charging",
    "全部": "All",
    "全部清空": "Clear all",
    "关": "Stopped",
    "关闭": "Off",
    "关闭软件音量": "Turn off software volume",
    "内存": "Memory",
    "内建": "Built-in",
    "内置插件": "Built-in plugin",
    "写入": "Write",
    "写入分页": "Page-outs",
    "分辨率": "Resolution",
    "刚刚": "Just now",
    "创建音频捕获": "Create audio tap",
    "创建音频设备": "Create audio device",
    "删除": "Delete",
    "删除后不能恢复。": "Deleted history cannot be recovered.",
    "刷新间隔": "Refresh interval",
    "剪贴板": "Clipboard",
    "功耗": "Power",
    "占用": "Usage",
    "压力": "Pressure",
    "取消": "Cancel",
    "取消置顶": "Unpin",
    "可用": "Available",
    "启动音频": "Start audio",
    "启用": "Enabled",
    "固态硬盘": "SSD",
    "图片": "Images",
    "在系统设置中切换网络": "Switch networks in System Settings",
    "声音": "Sound",
    "备忘录": "Notes",
    "复制": "Copy",
    "外观": "Appearance",
    "大小": "Size",
    "始终使用所选的模式，不受 macOS 影响。": "Always use the selected appearance.",
    "安全性": "Security",
    "工具": "Tools",
    "已上传": "Uploaded",
    "已下载": "Downloaded",
    "已使用的交换": "Swap used",
    "已充电": "Charged",
    "已关闭": "Off",
    "已压缩": "Compressed",
    "已开启": "On",
    "已接电源": "Plugged in",
    "已连接": "Connected",
    "平均负载": "Load average",
    "开机时启动": "Launch at login",
    "循环次数": "Cycle count",
    "性能核心": "Performance cores",
    "总容量": "Capacity",
    "打开历史的快捷键": "History shortcut",
    "打开插件文件夹": "Open plugins folder",
    "打开系统设置": "Open System Settings",
    "打开隐私设置": "Open privacy settings",
    "找不到插件的动态库": "Plugin library not found",
    "拖动滑块开启软件音量": "Drag the slider to enable software volume",
    "按下快捷键…": "Press a shortcut…",
    "按住 ⌥⇧ 再按键，可以小幅调节。": "Hold ⌥⇧ for smaller adjustments.",
    "授权定位以显示网络名称": "Allow Location to show network name",
    "控制": "Controls",
    "插件与设置": "Plugins and settings",
    "插件与设置…": "Plugins and settings…",
    "搜索": "Search",
    "整机": "System",
    "文件": "Files",
    "文本": "Text",
    "断开": "Disconnect",
    "断开后可能无法再用它操作，确定？": "Disconnect this device? You may lose input control.",
    "无加密": "Unsecured",
    "无电池": "No battery",
    "时间": "Time",
    "昨天": "Yesterday",
    "显卡": "GPU",
    "显存": "GPU memory",
    "显示器": "Displays",
    "显示器音量方式": "Display volume control",
    "暂停记录": "Pause capture",
    "最多保留": "History limit",
    "有": "Yes",
    "未更改（已取消或没有权限）": "Unchanged (canceled or permission denied)",
    "未知": "Unknown",
    "未知设备": "Unknown device",
    "未知错误": "Unknown error",
    "未设置": "Not set",
    "未连接": "Disconnected",
    "权限": "Permissions",
    "来源": "Source",
    "标准": "Standard",
    "模式": "Appearance",
    "正在接收按键": "Receiving key events",
    "没有": "No",
    "没有找到匹配的内容。": "No matching items.",
    "没有检测到显示器": "No displays found",
    "没有输出设备": "No output device",
    "没有选中的内容": "No item selected",
    "注册音频回调": "Register audio callback",
    "浅色": "Light",
    "深色": "Dark",
    "清空剪贴板历史？": "Clear clipboard history?",
    "清空历史…": "Clear history…",
    "清空，保留置顶": "Clear unpinned items",
    "温度": "Temperature",
    "点击复制，再按 ⌘V 粘贴": "Click to copy, then press ⌘V to paste",
    "用户": "User",
    "电压": "Voltage",
    "电池": "Battery",
    "电池健康": "Battery health",
    "电池放电": "Battery output",
    "电脑开启时间": "Uptime",
    "电量": "Charge",
    "电量流向": "Power flow",
    "监控": "Monitoring",
    "知道了": "Dismiss",
    "磁盘": "Disks",
    "神经引擎": "Neural Engine",
    "移除": "Remove",
    "第三方插件": "Extensions",
    "系统": "System",
    "系统耗电": "System power",
    "累计": "Total",
    "结束": "End",
    "网络": "Network",
    "网络接口": "Interfaces",
    "网络速度": "Network speed",
    "置顶": "Pin",
    "联动内存": "Wired memory",
    "能效核心": "Efficiency cores",
    "自动": "Automatic",
    "自动切换": "Follow system appearance",
    "菜单栏": "Menu bar",
    "菜单栏读数": "Menu bar readings",
    "三合一状态图标": "Combined status icon",
    "蓝牙": "Bluetooth",
    "蓝牙已关闭": "Bluetooth is off",
    "蓝牙已开启": "Bluetooth is on",
    "访达": "Finder",
    "识别本进程音频对象": "Resolve process audio object",
    "语言": "Language",
    "请在系统弹窗中允许录制系统音频。": "Allow system audio capture in the macOS prompt.",
    "读取": "Read",
    "读取中…": "Loading…",
    "读取分页": "Page-ins",
    "路由器": "Router",
    "软件调暗": "Software dimming",
    "软件音量": "Software volume",
    "输入": "Input",
    "输入法": "Input source",
    "输出": "Output",
    "运行时间": "Uptime",
    "还没有安装": "No extensions installed",
    "还没有记录。复制点什么试试。": "No history yet. Copy something to get started.",
    "还没有辅助功能权限，打开后马上生效": "Enable Accessibility permission to activate key handling.",
    "这个快捷键被其他应用占用了，请换一个。": "This shortcut is already used by another app.",
    "这个设备不能调节音量（需要 macOS 14.2 或更高版本）": "Volume control requires macOS 14.2 or later.",
    "这台显示器不响应 DDC 音量命令，音量由软件调节。": "This display ignores DDC volume commands. Software volume is used instead.",
    "这台显示器不返回当前亮度，这里显示的是上次设定值。": "This display does not report its brightness. The last requested value is shown.",
    "进程": "Processes",
    "退出 MyStatus": "Quit MyStatus",
    "适配器输入": "Adapter input",
    "适配器额定": "Adapter rating",
    "选择": "Select",
    "选项": "Options",
    "通用": "General",
    "重新扫描": "Rescan",
    "重新检测显示器的 DDC 音量": "Recheck display DDC volume",
    "链接": "Links",
    "键盘亮度和音量键": "Brightness and volume keys",
    "键盘或鼠标可能随之断开，确定关闭蓝牙？": "Turn off Bluetooth? Your keyboard or mouse may disconnect.",
    "键盘按键": "Media keys",
    "闲置": "Idle",
    "需要 macOS 14.2 或更高版本": "Requires macOS 14.2 or later",
    "颜色": "Colors",
    "风扇": "Fan",
    "DDC 音量": "DDC volume",
    "plugin.json 无法读取": "Cannot read plugin.json",
    "动态库返回的不是 DeckPlugin": "Library did not return a DeckPlugin",
    "ID 与已有插件重复": "A plugin with this ID already exists",
    "所有插件都已关闭。点右上角的齿轮来开启。": "All plugins are off. Open settings to enable one.",
    "把 .deckplugin 文件夹放进插件文件夹，再点“重新扫描”。新插件默认关闭，启用前会先询问。": "Place .deckplugin folders in the plugins folder, then choose Rescan. New plugins start disabled.",
    "文件在你启用后发生了变化，需要重新确认才能运行。": "Plugin files changed after approval. Enable the plugin again to approve the new version.",
    "插件的代码会在 MyStatus 内运行，拥有和它相同的权限，包括读取剪贴板历史。只启用你信任的来源。": "Plugin code runs inside MyStatus with its permissions, including clipboard history access. Enable only trusted sources.",
    "跟随 macOS 的外观。macOS 切换浅色和深色时，这里也会跟着切换。": "Follow macOS when it switches between Light and Dark Mode.",
    "“自动”会先试 DDC。如果显示器没有响应，就改用软件音量。": "Automatic tries DDC first, then uses software volume if the display does not respond.",
    "基于 MonitorControl（MIT）与 Status Trio（Apache-2.0）": "Based on MonitorControl (MIT) and Status Trio (Apache-2.0)",
    "CPU、GPU、硬盘和电池温度，风扇转速和整机功耗。风扇只读取，不控制。": "CPU, GPU, drive and battery temperatures, fan speed, and system power. Fans are read-only.",
    "主音量、输出和输入设备切换。显示器音频可用 DDC 或软件音量控制。": "Master volume and input/output devices. Display audio supports DDC or software volume.",
    "F1、F2 调外接显示器亮度，F10、F11、F12 调显示器音量。内建屏和普通扬声器仍由系统处理，没有外接显示器时不受影响。": "F1/F2 control external display brightness; F10–F12 control display volume. macOS handles built-in displays and ordinary speakers.",
    "不记录密码管理器标记为保密的内容，也不记录屏蔽名单里的应用。": "Skips confidential clipboard contents and blocked apps.",
    "macOS 可能在读取剪贴板时询问是否允许，可以在“隐私与安全性”里设为始终允许。": "macOS may request clipboard access. You can allow it in Privacy & Security.",
    "macOS 已禁止 MyStatus 读取剪贴板，所以没有新记录。可以在隐私设置里更改。": "macOS denied clipboard access. Change permission in privacy settings to record new items.",
    "macOS 读取剪贴板时可能询问是否允许。要自动记录，请在隐私设置的“粘贴”项里把 MyStatus 设为始终允许。": "For automatic history, allow MyStatus to paste from other apps in privacy settings.",
    "一个菜单栏图标同时显示电池、Wi-Fi 和音量。在图标上滚动可以调音量。": "One icon shows battery, Wi-Fi, and volume. Scroll over it to adjust volume.",
    "上传和下载速度、累计流量、网络接口。": "Upload/download rates, total traffic, and network interfaces.",
    "内存压力、用量明细、分页、交换空间和占用最多的应用。": "Memory pressure, usage, paging, swap, and top memory consumers.",
    "各卷可用空间和实时读写速度。": "Available storage and live read/write rates.",
    "切换低电量模式时，每次都需要输入管理员密码。": "Changing Low Power Mode requires an administrator password.",
    "在菜单栏持续显示网络速度、CPU 和内存占用。": "Show network speed, CPU, and memory usage in the menu bar.",
    "在面板里切换已启用的输入法。": "Switch enabled input sources from the panel.",
    "处理器占用、每核负载、频率、功耗和占用最高的应用。": "Processor usage, core load, frequency, power, and top CPU consumers.",
    "外接显示器的亮度和对比度（DDC/CI），内建屏亮度，无 DDC 时用软件调暗。": "External display brightness/contrast through DDC, native display brightness, and software dimming.",
    "开关 Wi-Fi，查看信号、信道、速率和安全性。切换网络仍在系统设置里进行。": "Toggle Wi-Fi and view signal, channel, rate, and security. Switch networks in System Settings.",
    "开关蓝牙，连接或断开已配对设备，查看设备电量。": "Toggle Bluetooth, manage paired devices, and view battery levels.",
    "开启软件音量时需要“系统录音”权限：系统声音会经过本应用调整音量后再播放，不会录制或保存。": "Software volume requires system audio capture permission. Audio is adjusted and played immediately, never recorded or saved.",
    "拖动滑块即可调节。第一次会询问“系统录音”权限：声音只是经过 MyStatus 调整音量，不会被录制或保存。": "Drag to adjust. macOS requests system audio capture permission the first time. Audio is never recorded or saved.",
    "显示网络名称需要“定位”权限（macOS 的要求），只在你点击时才请求，应用不读取位置。": "macOS requires Location permission for Wi-Fi names. Requested only when you click; the app does not read your location.",
    "电量、健康度、循环次数、电量流向和低电量模式。": "Charge, battery health, cycle count, power flow, and Low Power Mode.",
    "第一次开关蓝牙或连接设备时，macOS 会询问蓝牙权限。查看列表和电量不需要权限。": "macOS requests Bluetooth permission when you first toggle Bluetooth or connect a device.",
    "要用 F1、F2 和 F10–F12 控制显示器，请在“辅助功能”里打开 MyStatus。打开后马上生效。": "Enable MyStatus in Accessibility to control displays with F1/F2 and F10–F12. Takes effect immediately.",
    "需要“辅助功能”权限才能接收按键。如果 MonitorControl 也在运行，请先退出它，否则一次按键会被处理两次。": "Requires Accessibility permission. Disable MonitorControl key handling to avoid duplicate adjustments.",
    "需要允许 MyStatus 录制系统音频才能调节这个设备的音量。声音不会被录制或保存。": "Allow system audio capture to adjust this device. Audio is never recorded or saved.",
    "插件 1 · 剪贴板侧边栏。记录复制过的文本、链接、颜色、图片和文件，可搜索、置顶，按快捷键随时调出。全部只保存在这台 Mac 上。": "Plugin 1 · Clipboard sidebar for text, links, colors, images, and files. Search, pin, and open with a shortcut. Stored only on this Mac."
]
    static func traditional(_ value: String) -> String {
        let terms = [
            ("剪贴板", "剪貼簿"), ("软件", "軟體"), ("硬件", "硬體"), ("鼠标", "滑鼠"),
            ("插件", "外掛"), ("设置", "設定"), ("应用程序", "應用程式"), ("应用", "App"),
            ("网络", "網路"), ("屏幕", "螢幕"), ("文件夹", "資料夾"), ("文件", "檔案"),
            ("默认", "預設"), ("内存", "記憶體"), ("磁盘", "磁碟"), ("视频", "影片"),
            ("信号", "訊號"), ("信道", "頻道"), ("代码", "程式碼"), ("访达", "Finder"),
            ("权限", "權限"), ("备忘录", "備忘錄"), ("蓝牙", "藍牙"), ("循环", "循環"),
            ("未连接", "未連線"), ("已连接", "已連線"), ("触控板", "觸控式軌跡板"),
            ("驱动器", "磁碟機"), ("全屏", "全螢幕"), ("日志", "記錄"), ("鼠标滚轮", "滑鼠滾輪")
        ]
        let adjusted = terms.reduce(value) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
        return adjusted.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? adjusted
    }

    static let fragments: [(String, String)] = [
        ("已暂停", "Paused"), ("已连接", "Connected"), ("未连接", "Disconnected"),
        ("已充电", "Charged"), ("充电中", "Charging"), ("可用", "available"),
        ("虚拟设备", "Virtual devices"), ("风扇", "Fan"), ("小时", "h "), ("分钟", "min"),
        (" 条", " items"), (" 台", " devices"), ("内置插件", "Built-in plugin")
    ]
}
