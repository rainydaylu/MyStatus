## 更新内容

- **设置更好找**：权限区域移到液态玻璃控制下方；打开设置时显示 MyStatus Dock 图标，支持从 Dock 找回设置窗口，关闭设置后恢复菜单栏模式。
- **更通透的液态玻璃**：背景模糊与玻璃边缘独立处理，透明度 100% 时移除额外灰白底色；高透明度下使用浅色文字。
- **修复调光显示不一致**：解决软件调光时输入法候选窗显得特别亮的问题。
- **历史图表更清楚**：修复电量历史误判采样缺口；网络和磁盘活动使用柱状图，保留上传/下载、读/写的独立量程。
- **减少重复工作**：缓存菜单栏绘图及静态传感器信息，减少标志灯光的重复合盖和电源查询。
- **精简电池说明**：保留电量记录入口，校准等待提示改为“可能需要一天”。

## Changes

- Move permissions below Liquid Glass controls and give settings a Dock entry while open.
- Separate native backdrop blur from clear glass, remove the extra fill at 100% translucency, and improve label contrast.
- Fix bright input-method candidate windows during software display dimming.
- Fix false gaps in battery history and use bars for network and disk activity with independent scales.
- Cache menu bar rendering and redundant sensor and logo-light queries.
- Simplify battery guidance while keeping battery records accessible.

## Validation

260 app tests passed. The installed app and packaged executable match; the app's ad-hoc signature was verified.

## Downloads

- `MyStatus-1.3.15.zip`：安装包 / App archive（build 75）。
- `MyStatus-1.3.15-source.zip`：完整源码 / Source archive。
- `MyStatus-1.3.15-SHA256SUMS.txt`：SHA-256 校验值 / Checksums。

Apple silicon · macOS 13 or later. Liquid Glass requires macOS 26 or later; CodeIsland requires macOS 14 or later. The app is signed ad hoc and is not notarized by Apple.
