# MyStatus

[English](README.md)

开发者：[rainydaylu](https://github.com/rainydaylu)

一个插件式的 macOS 菜单栏应用，把电脑监控和日常管理放进同一个面板。**每项功能都是一个插件**，可以单独开关；关掉的插件完全不运行，不占资源，也不会请求权限。以后的新功能也可以做成插件加进来。

部分系统控制功能使用以下项目的代码。

- [MonitorControl](https://github.com/MonitorControl/MonitorControl)（MIT）：通过 DDC/CI 控制外接显示器
- [Status Trio](https://github.com/lingyired/status-trio)（Apache-2.0）：电池、Wi-Fi、音量、蓝牙和输入法的状态与控制
- [Fanny](https://github.com/ShahzaibAli02/Fanny-MacOs-FanControl)（MIT）：风扇控制辅助程序的 SMC 后端

界面的内容和交互参考 iStat Menus：面板分成多栏，每栏是一张独立悬浮的玻璃卡片；鼠标停在某一栏上，就从面板左侧或右侧展开它的详情，哪边屏幕空间大就展开在哪边。材质和控件是 macOS 26 系统原生的 Liquid Glass，更早的系统显示渐变样式。iStat Menus 是闭源软件，这里所有界面都是独立绘制的，没有使用它的代码或素材。

显示器软件音量的思路参考了 [SoundBridge](https://github.com/chenjy16/SoundBridge)：同样是软件调整增益，但这里用 Core Audio Tap，不安装虚拟驱动。它的仓库没有许可证文件，所以没有使用它的代码。

## 内置插件

从菜单栏图标打开面板，点底部「编辑控制」即可调整栏目、开关和排序。首次运行按屏幕可用高度选择默认栏目。

| 分类 | 插件 | 默认 | 内容 |
| --- | --- | --- | --- |
| 控制 | 声音 | 开 | 主音量，切换输出和输入设备，显示器的 DDC 或软件音量 |
| 控制 | 显示器 | 开 | 外接显示器的亮度和对比度，内建屏亮度，无 DDC 时用软件调暗 |
| 控制 | Wi-Fi | 开 | 开关 Wi-Fi，查看信号、信道、速率和安全性 |
| 控制 | 蓝牙 | 开 | 开关蓝牙，连接或断开设备，查看设备电量 |
| 控制 | 输入法 | 开 | 切换输入法 |
| 控制 | 键盘亮度和音量键 | 开 | F1、F2 调外接显示器亮度，F10、F11、F12 调显示器音量（需要辅助功能权限） |
| 工具 | 剪贴板 | 开 | 复制历史，搜索、置顶，全局快捷键 |
| 监控 | CPU 与 GPU | 开 | 占用、每核负载、频率、功耗、占用最高的应用 |
| 监控 | 内存 | 开 | 内存压力、用量明细、交换空间、占用最多的应用 |
| 监控 | 磁盘 | 开 | 各卷可用空间、读写速度 |
| 监控 | 网络 | 开 | 上传和下载速度、累计流量、网络接口 |
| 监控 | 传感器 | 开 | 温度、风扇读数和转速控制、功耗 |
| 监控 | 电池 | 开 | 电量、健康度、循环次数、电量流向、低电量模式、已连接设备的电量 |
| 菜单栏 | 三合一状态图标 | 开 | 圆环是电池，中间是 Wi-Fi，底部圆点是音量；在图标上滚动可调音量 |
| 菜单栏 | 菜单栏读数 | 关 | 持续显示网络速度、CPU 和内存 |

如果所有菜单栏插件都关闭，会保留一个普通图标，确保始终能打开面板。

## 控制显示器的音频

macOS 不能调节 HDMI 和 DisplayPort 设备的音量。MyStatus 按这个顺序处理：

1. **DDC**：第一次发现显示器时，把音量改动几格、读回确认后再恢复，结果会记住。
2. **软件音量**：如果显示器不响应 DDC（比如 Dell U2723QX），直接拖动音量滑块就能调节。它用 macOS 14.2 起的 Core Audio Tap 捕获系统声音，调整增益后再送到显示器，不需要安装虚拟声卡。

第一次使用软件音量时，macOS 会询问“系统录音”权限。声音不会被录制或保存。应用退出或崩溃时，macOS 会立即恢复正常的声音路径，这时声音回到显示器自身的音量，可能比滑块设定的更响。显示器插拔或休眠唤醒后，音频路径会自动重建。

## 键盘按键

系统自己的亮度和音量键对外接显示器不起作用，所以由“键盘亮度和音量键”插件接管。它需要辅助功能权限，授权后马上生效，不用重启。

| 按键 | 什么时候由 MyStatus 处理 | 其他情况 |
| --- | --- | --- |
| F1、F2 | 鼠标所在的屏幕是外接显示器（Apple 显示器除外） | 交给系统：没有外接显示器，或鼠标在内建屏上时，电脑亮度照常调节 |
| F10、F11、F12 | 当前输出设备用 DDC 或软件音量 | 交给系统：内建扬声器、耳机等 macOS 能调的设备照常工作 |

按住 `⌥⇧` 再按键可以小幅调节。按键时音量和亮度滑块会同步移动；面板关着时，屏幕右上角会显示当前数值。

## 外观

在设置的“通用”页里切换。打开“自动切换”后跟随 macOS 的外观，macOS 变化时一起变；关闭后用“浅色”“深色”按钮固定一种。默认是自动切换。

在声音插件的设置里，可以手动指定优先用哪种方式，或重新检测显示器。

## 剪贴板

- 记录文本、代码、链接、颜色、图片和文件，并保留原始格式，再次粘贴时和当初复制的一样。
- 默认快捷键 `⌃⌥V` 打开历史窗口：`↑↓` 选择，`↩` 复制，`⌘P` 置顶，`⌘⌫` 删除。之后按 `⌘V` 粘贴。
- 按来源应用、内容和类型搜索或筛选。

隐私：

- **只保存在这台 Mac 上**，没有联网功能，也不进备份。文件夹只有当前用户能读，但**没有加密**。
- **不记录**密码管理器标记为保密或临时的内容（遵循 nspasteboard.org 的约定），这些内容的内容本身都不会被读取。
- **不记录**屏蔽名单里的应用。默认包含钥匙串、密码和常见的密码管理器，可以在设置里增减。
- 可以随时暂停记录、清空历史。

macOS 15.4 起，系统可能在应用读取剪贴板时询问是否允许。想要自动记录，请在隐私设置里把 MyStatus 设为始终允许。

## 构建和运行

当前可从源码构建 `MyStatus.app`。最低系统要求为 macOS 13，macOS 26 可使用原生液态玻璃。

从源码构建只需 Xcode Command Line Tools。

```bash
scripts/build-app.sh
```

```bash
open build/MyStatus.app
```

运行测试：

```bash
scripts/test.sh
```

调试参数（都从 `build/MyStatus.app/Contents/MacOS/mystatus` 运行）：

| 参数 | 作用 |
| --- | --- |
| `--snapshot <文件夹>` | 不打开界面，把面板和所有详情窗口渲染成 PNG（渐变样式，示例剪贴板数据） |
| `--diagnose-audio` | 打印每台显示器的 DDC 读数和每个音频设备的音量属性，加 `--write` 还会试写音量并恢复 |
| `--diagnose-softvolume` | 用当前输出实际运行软件音量几秒，并打印输入和输出电平 |
| `--verify-plugin <文件夹>` | 按应用的方式加载并激活一个插件 |
| `--diagnose-keys` | 打印辅助功能权限状态，并列出 20 秒内按下的媒体键，要从应用包启动 |
| `--open-panel`、`--open-clipboard`、`--open-settings` | 启动后直接打开面板、剪贴板窗口或设置 |
| `--open-flyout <栏目 id>` | 和 `--open-panel` 一起用，同时展开这一栏的详情窗口 |
| `--pin-panel` | 点击其他地方或切换应用时面板不关闭，用来检查界面 |
| `--sample-clipboard` | 用示例数据代替真实的剪贴板历史 |

## 开发插件

插件是一个 `.deckplugin` 文件夹，放进 `~/Library/Application Support/StatusDeck/Plugins/`，然后在设置里点“重新扫描”。完整示例见 [Examples/KeepAwakePlugin](Examples/KeepAwakePlugin)。

```
MyPlugin.deckplugin/
├── plugin.json          # 说明文件，不运行任何代码就能读取
└── libMyPlugin.dylib    # 插件代码
```

插件实现 `StatusDeckKit` 里的 `DeckPlugin` 协议，内置插件用的也是这个协议：

```swift
import StatusDeckKit
import SwiftUI

@MainActor
final class MyPlugin: DeckPlugin {
    let manifest = PluginManifest(
        id: "com.example.my", name: "我的插件", summary: "一句话说明",
        symbol: "star", category: .tools
    )

    func activate(host: any DeckHost) { /* 开始工作 */ }
    func deactivate() { /* 停止一切，释放资源 */ }

    var sections: [DeckSection] {
        [DeckSection(id: "my", title: "我的插件") {
            // 面板里的一栏，始终显示
            DeckTitleRow("我的插件", value: "正常")
        } detail: {
            // 鼠标停在这一栏上时，展开在面板旁边的窗口
            DeckCard { DeckInfoRow("状态", "正常") }
        }]
    }
}

@_cdecl("statusdeck_plugin_create")
public func statusdeckPluginCreate() -> UnsafeMutableRawPointer {
    DeckPluginExport.retained { MyPlugin() }
}
```

构建并检查：

```bash
scripts/build-plugin.sh Examples/KeepAwakePlugin
```

```bash
build/MyStatus.app/Contents/MacOS/mystatus --verify-plugin build/plugins/KeepAwakePlugin.deckplugin
```

`StatusDeckKit` 还提供了圆环、柱状图、镜像图、统计数字、滑块、开关、设备行、应用快捷图标等组件，用它们写的插件会自动适配浅色和深色外观。滑块、开关和按钮都是系统原生控件。插件还可以贡献设置页、菜单栏图标和全局快捷键。

插件接口的版本号是 `apiVersion`（现在是 2），版本不符的插件不会被加载。

### 安全模型

第三方插件的代码运行在应用内，权限和应用相同，**包括读取剪贴板历史**。所以：

- 新发现的插件一律关闭，启用前会明确询问。列出插件时不运行它的任何代码。
- 启用时会记录动态库的指纹。文件之后如果变化，插件会被关闭，需要重新确认。
- 如果启动时某个插件导致崩溃，下次启动会自动关闭它并提示。
- 插件要和应用使用同一版 `DeckPluginAPI.version`，否则拒绝加载。

关闭插件后代码仍留在内存里，直到应用退出（动态库无法安全卸载），但插件已停止工作。

## 权限

只在用到相关功能时才请求权限。“键盘亮度和音量键”默认开启，所以第一次启动时会询问辅助功能权限；不想要可以在设置里关掉这个插件。

| 权限 | 什么时候请求 | 不授权会怎样 |
| --- | --- | --- |
| 系统录音 | 开启软件音量 | 显示器音量无法用软件调节 |
| 粘贴（系统询问） | 剪贴板插件读取新内容时 | 剪贴板历史没有新记录 |
| 定位 | 点“授权定位以显示网络名称” | 只显示“已连接”，不显示 Wi-Fi 名称（macOS 的要求，应用不读取位置） |
| 蓝牙 | 第一次开关蓝牙或连接设备 | 设备列表和电量仍可查看，但无法操作 |
| 辅助功能 | “键盘亮度和音量键”插件启动时 | 按键不控制外接显示器，面板里会显示提示 |
| 管理员授权 | 首次调节风扇或切换低电量模式时申请，两项共用一次授权 | 风扇继续由 macOS 管理，低电量模式保持当前状态 |

## 已知限制

- **发行包面向 Apple 芯片**。外接显示器的 DDC 支持取决于机型、显示器和连接方式。
- **依赖私有接口**：DDC、温度（IOHID）、频率和功耗（IOReport）、风扇（SMC）、蓝牙开关和录音权限查询都用了未公开的系统接口。除 DDC 和 CoreDisplay 外都在运行时加载，系统更新移除时对应读数会显示 `--`。软件音量本身用的是公开接口。
- 预编译 App 使用临时签名，未使用 Developer ID 签名或 Apple 公证。
- 手动调速要求 Mac 报告有效的风扇转速范围。可在传感器面板恢复系统自动管理。
- **切换 Wi-Fi 网络要去系统设置**。macOS 没有用已保存密码连接的公开接口，本应用也不处理 Wi-Fi 密码。
- **不要同时运行 MonitorControl 的按键控制**，否则同一次按键会被处理两次。滑块本身可以共存。
- **剪贴板没有云同步**，也没有图片压缩、短链等联网动作。这些可以做成插件。
- 界面支持简体中文、繁體中文、English、Français、Deutsch、日本語和 한국어。

## 代码来源

并入的文件、原始提交和改动见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，许可证原文在 [LICENSES/](LICENSES/)。

随包的 Mos 适配器包含采用 [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/) 的代码，本发行包供非商业使用。
