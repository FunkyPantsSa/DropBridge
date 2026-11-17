# 绑定运行手册：把 Wi-Fi 接口换成 WinUSB（Zadig）

状态：**RTL8821CU（`0bda:c820`，MI_02）已于 2026-10-27 执行成功**；RTL8811CU
（`0bda:c811`）的源码支持已加入，但**尚未在真机上执行绑定**。本页最初为 8821CU
编写，8811CU 的差异在下面单独标出；AI 不会自动改驱动。

## 0. 目的与绑定对象

devourer 通过 libusb 直接访问网卡的 bulk 端点。Windows 默认把 Wi-Fi 接口交给
Realtek 的 `netrtwlanu` 网络驱动，用户态程序拿不到这些端点。绑定后：

- libusb 可以 `open` / `claim_interface` / 读写端点；
- 这张网卡不再作为普通 Wi-Fi 使用（符合预期）；
- 有线网卡继续上网。

绑定对象因型号而异：

| 型号 | USB ID | 绑定对象 | 蓝牙 |
| --- | --- | --- | --- |
| RTL8811CU | `0bda:c811` | **整台设备**（单功能，通常只有 interface 0） | 无；beacon 用电脑自己的 BLE 适配器 |
| RTL8821CU | `0bda:c820` | **只绑 MI_02**（Wi-Fi） | MI_00 不动 |

## 1. 先确认实物

只读枚举：

```powershell
.\tools\Inspect-Hardware.ps1
```

- `0bda:c811`：8811CU，单功能设备；
- `0bda:c820`：8821CU，复合设备（MI_00 蓝牙、MI_02 Wi-Fi）；
- `0bda:1a2b`：ZeroCD 形态，**不要自动 eject 或切模式**，先记录再决定。

VID/PID 不能证明硅片；芯片 ID 要等授权后的只读 `usb_probe --read8 00FC`
（8811CU 与 8821CU 都应为 `0x09`）。

## 2. 8821CU 历史基线（2026-10-27，已执行）

| 项 | 值 |
| --- | --- |
| 设备 | `USB\VID_0BDA&PID_C820`，复合设备，`usbccgp` |
| 接口 | MI_00 蓝牙；MI_02 Wi-Fi（class `ff/ff/ff`） |
| MI_02 驱动 | `netrtwlanu.inf`，1030.38.712.2019，服务 `RtlWlanu` |
| 绑定后 | `oem155.inf`，服务 `WinUSB`，`WLAN 2` 适配器消失 |
| 蓝牙 MI_00 | `oem154.inf`，1.5.1012.3，服务 `BTHUSB` |

## 3. 操作步骤（需要管理员）

1. 确认有线网络正常；绑定后这张 USB 网卡不能上网。
2. 关闭可能占用网卡的程序（Realtek 控制面板、Wi-Fi 工具）。
3. 从官网下载 Zadig：<https://zadig.akeo.ie/>（开源项目 libwdi 的图形前端）。
   不要从第三方下载站取；发布包里也带了一份 `setup\zadig-2.9.exe`。
4. 右键 `zadig.exe` → **以管理员身份运行**。
5. 菜单 `Options` → 勾选 **List All Devices**。
6. 顶部下拉框按型号选择：
   - **RTL8811CU**：选 `RTL8811CU` / `802.11ac NIC`（`0BDA C811`，整个设备）；
   - **RTL8821CU**：选 `0BDA C820` 的 **Interface 2**；
   - **不要选** `USB Composite Device`（复合父设备）；
   - **不要选**任何带 `Bluetooth` 的项。
7. 确认右侧当前驱动是 `RtlWlanu` 或类似 Realtek 驱动，目标驱动选 **WinUSB**
   （不要选 libusbK / libusb-win32；libusb 1.0 用 WinUSB 后端）。
8. 点击 **Replace Driver**，等待完成。
9. 如果弹出驱动签名/安全启动警告：**不要关闭 Secure Boot、不要关闭驱动签名强制**。
   先取消，把完整错误记下来，回到本项目讨论替代方案。

## 4. 绑定后验证（只读）

```powershell
.\tools\Check-Binding.ps1
```

脚本现在同时识别两种设备：

- 8811CU：`RTL8811CU Wi-Fi (whole device)`，service 应为 `WinUSB`；
- 8821CU：`RTL8821CU Wi-Fi (MI_02)`，service 应为 `WinUSB`；
- 8821CU 会额外报告 MI_00 蓝牙状态；8811CU 显示“not applicable”；
- `WLAN` 网络适配器消失或不再由 Realtek 驱动管理；
- 退出码 0。

再补充记录：

```powershell
Get-PnpDevice -PresentOnly | Where-Object InstanceId -like '*VID_0BDA&PID_C8*' |
    Select-Object Class,FriendlyName,InstanceId,Status
```

**本步骤不做**：不初始化芯片、不下载固件、不发帧。那些需要单独授权。

## 5. 回滚（恢复到 Realtek 驱动）

1. 设备管理器 → 找到绑定后的设备（可能在“通用串行总线设备”下，名称类似
   `WinUSB Device` 或原 Wi-Fi 名称）。
2. 右键 → **卸载设备**；**不要**勾选“删除此设备的驱动程序软件”。
3. 菜单 `操作` → **扫描检测硬件改动**。
4. Windows 应从驱动库重新安装 `netrtwlanu.inf`；`WLAN` 适配器恢复。
5. 如果没恢复：拔插网卡，或重启；仍不行时用管理员 PowerShell：

   ```powershell
   pnputil /scan-devices
   ```

6. 再次运行 `tools/Check-Binding.ps1`，确认回到 `RtlWlanu`。

回滚不需要删除驱动包，也不需要改注册表。8811CU 的整设备绑定同样按这套步骤
卸载；重新插拔后 Windows 会装回 Realtek 驱动。

## 6. 可能失败的情况

| 现象 | 含义 | 处理 |
| --- | --- | --- |
| Zadig 报签名/证书错误 | 系统策略拒绝 libwdi 的驱动包 | 不要关 Secure Boot；记录错误，改用 INF + 测试签名等方案前先讨论 |
| 8821CU 选错到 MI_00 | 蓝牙失效 | 按第 5 节卸载并扫描，蓝牙会恢复 |
| 8811CU 误选了复合父设备 | 网卡仍由 Realtek 管理，libusb 打不开 | 重新选整设备；必要时卸载后扫描 |
| 绑定后设备变成未知设备 | INF 未匹配 | 卸载 → 扫描；必要时拔插 |
| 网卡枚举成 `0bda:1a2b` | ZeroCD 形态 | 不要自动 eject/切模式；先记录再决定 |
| 绑定成功但 libusb 打不开 | 接口/端点或权限问题 | 先跑只读打开探针，不要直接 Init |

## 7. 需要记录的证据

写入 `evidence/binding.local.json`（已被 `*.local.json` 忽略，不提交）：

```text
UTC 时间：
Zadig 版本：
型号 / VID:PID / 接口：
绑定前驱动：
绑定目标（硬件 ID）：
绑定后驱动/服务：
蓝牙状态（8821CU 的 MI_00；8811CU 无）：
网络适配器状态：
是否回滚测试：
回滚后驱动：
失败时的完整错误文本：
```

之后把不含实例路径的摘要整理进 `evidence/hardware-identity.json` 或新的提交证据。

## 8. 边界

- 本步骤只换驱动，不初始化芯片、不加载固件、不发无线帧。
- 不改网络、防火墙、注册表或 Secure Boot。
- 所有操作可回滚；回滚以第 5 节为准。
