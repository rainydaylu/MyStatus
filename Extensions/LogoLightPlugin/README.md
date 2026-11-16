# MyStatus 标志灯光

在 MyStatus → 设置 → 插件 → 标志灯光中启用和调整。没有独立窗口、
菜单栏图标或主面板卡片；开机启动沿用 MyStatus 的偏好设置。

- 常亮和亮度调节。
- 呼吸灯：3–10 秒周期，可设最低亮度。
- 电池：拔电后跟随电量，正在充电时脉冲，充满/暂停充电时常亮。
- 音乐：系统播放音频、灵敏度、响应时间和节拍间熄灭；不录音。
- 编程状态：直接跟随 MyStatus CodeIsland 的工作/等待/需要注意状态，
  只在进程内传递状态和数量，不增加或改写第三方 Hook。
- 触控板接触和打字互动；输入权限仅从设置页按需申请，不读取文字。
- 可选灯光快捷键和限时合盖续亮（需电源，最长 30 分钟）。

## 实现与来源

本插件没有采用 Backlit 的源文件、资源或界面。灯光模式、MyStatus 生命周期、
配置、设置页、CodeIsland 信号桥和恢复辅助程序为本项目实现。
底层硬件访问及硬件渐变算法使用 **Ark0N/LogoLight 的 MIT LogoLightCore**，
版本固定在 upstream.json，许可见 LICENSE。修改点：CoreBrightness 方法 ABI 校验。

硬件接口是 macOS 私有 API，只支持带独立发光 Apple 标志的兼容 Mac。
灯光输出仍受系统环境光控制的基础亮度影响，不覆盖系统亮度上限。
没有复制独立应用的 sudoers 安装器或自动更新器到产品流程。

无界面的 logo-light-helper 在灯光接管前确认就绪，监视当前会话租约，
在关闭插件、MyStatus 退出或异常结束后恢复原先的标志开关及正常渐变。
恢复失败时保留会话记录，不宣称恢复成功；设置页提供重新恢复操作。
合盖续亮限时运行，低电量模式、断电或过热时停止；内置屏幕可能继续亮着。

构建：`scripts/build-plugin.sh Extensions/LogoLightPlugin`

测试：`scripts/test.sh --logo-light`。MIT 控制库的原有模拟测试位于
Tests/LogoLightVendorChecks；它们通过假硬件验证渐变、键盘回写和取消行为。

原控制库测试中仅独立 LogoLight 应用的 Info.plist 断言不适用于插件，明确跳过；
其余硬件模拟、渐变、取消与键盘回写测试保留。
