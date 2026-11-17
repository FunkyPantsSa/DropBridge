# 改用 RTL8811CU 的可行性评估（蓝牙保持独立）

日期：2026-11-17
状态：**评估完成；未改代码、未换硬件、未碰驱动**。本文回答“能不能把现在的
RTL8821CU 换成 RTL8811CU、蓝牙单独实现”，并列出要改的点、验证顺序和风险。

## 1. 结论

**能，没有架构性障碍。** 三条依据：

1. 8811CU 与 8821CU 是同一颗 Wi-Fi 硅片（8821C / Jaguar2 / 1T1R）。devourer
   的 `C8821C` 后端同时覆盖两者，而且上游做硬件验证用的就是 8811CU
   （CF-811AC / `0bda:c811`），见 `docs/PHASE0_AUDIT.md:14-17` 和上游
   `src/jaguar2/ChipVariant.h`（锁定提交 `34a9e6f`）。
2. 本项目对这张卡只用 Wi-Fi 接口。蓝牙 beacon 一直走 Windows 的 BLE API
   （`Windows.Devices.Bluetooth.Advertisement`），与网卡无关；当前实机用的是
   Intel AX211。8811CU 没有蓝牙，正好把“蓝牙独立”变成硬隔离，蓝牙代码零改动。
3. 代码里没有依赖 8821CU 专有的寄存器、固件或初始化路径；需要改的是**设备身份
   假设**（USB PID、`MI_02`、INF、检测脚本）和文档。

代价也要说清楚：这不是一行改名。

- 驱动 INF 改完，`airbridge-winusb.cat` 必须在 Windows 上重建并重签（原私钥不在
  可新建证书），否则首启自动安装驱动会失效；在这台 Mac 上只能改源码，出不了可用
  的安装包。测试本身不必等签名，见第 6 节。
- 本机 AWDL 全链路只在 `0bda:c820` 上跑通过；换 8811CU 后初始化、149 信道、
  TX/RX、AirDrop、真实文件都要重测。
- 已知的“接收方向没有硬件 BlockAck”缺口和约 1.1 MB/s 的上限**不会**因为换卡
  改善；8811CU 同为 1T1R。

## 2. 硬件与上游依据

- `docs/PHASE0_AUDIT.md:14-17`：devourer `src/WiFiDriver.cpp:94` 的记录对象是
  CF-811AC / RTL8811CU / `0bda:c811`；`ChipVariant.h` 把 8811CU 与 8821CU 归入
  `C8821C`；demo 默认 PID 同时含 `c811`、`c820`。
- 上游 `ChipVariant.h` 的注释：`C8821C — RTL8811CU / RTL8821CU: 1T1R AC600，
  SYS_CFG2 chip-id 0x09，hardware-verified on a CF-811AC`。
- 本机实跑 `adapter.caps`：`"names":"RTL8811CU/RTL8821CU"`、`"chip":"RTL8821C"`、
  `tx_chains=1`、`rx_chains=1`（例如 `evidence/rx-repeat-1.log:24`）。
- 两者关系：8821CU = 8811CU + BT 4.2，Wi-Fi 部分共用同一套驱动/固件；PID 分别
  是 `0bda:c811`（8811CU）与 `0bda:c820`（8821CU）。这是芯片厂商/驱动社区的
  公开资料，不是本项目实测。

## 3. 本仓库现状：蓝牙其实已经是“独立实现”

- `airbridge_radio.exe` 只打开 Wi-Fi 接口：`src/radio_usb/main.cpp:307` 调
  devourer 的 `find_wifi_interface()`；上游 `src/UsbOpen.cpp` 按描述符找
  vendor class（`ff/ff/ff`）且带 bulk IN/OUT 的接口，不写死接口号，所以
  8811CU 的单接口（通常是 interface 0）也能找到。
- beacon：`src/beacon/airdrop-beacon.ps1:23-25` 用
  `Windows.Devices.Bluetooth.Advertisement`；`docs/SEND_PATH.md:81-83` 记录
  实际走的是 Intel AX211；`docs/STATUS.md:117` 明确 Realtek MI_00 坏了也不影响。
- 结论：蓝牙侧不需要改一行代码。但换 8811CU 后机器上**必须另有蓝牙适配器**
  （当前是 Intel AX211）；没有蓝牙时 beacon 只能退避重试，接收仍可用，只是
  发现更慢。

## 4. 必须改的点

功能性的（不改就会指错设备 / 装不上驱动）：

| 位置 | 现状 | 8811CU 下要改成 |
| --- | --- | --- |
| `src/radio_usb/main.cpp:289` | 默认 PID `0xc820` | 支持 `0xc811`（建议按“优先 c811、回退 c820”或从 INF 列表选择） |
| `src/radio_usb/main.cpp:292` | 报错文案写死 `MI_02` | 改成“Wi-Fi 接口是否已绑 WinUSB” |
| `src/supervisor/Program.cs:1071` | PnP 匹配 `USB\\VID_0BDA&PID_C820&MI_02` | 增加 `USB\\VID_0BDA&PID_C811`（整设备，无 `MI_02`） |
| `src/supervisor/Program.cs:1137,1196` | 日志/判断写死 `MI_02` | 按实际匹配到的接口输出 |
| `src/supervisor/Program.cs:2391,2424` | 气泡/弹窗写死“RTL8821CU” | 改成“8811CU / 8821CU 网卡” |
| `packaging/driver/airbridge-winusb.inf:21` | 只匹配 `VID_0BDA&PID_C820&MI_02` | 增加 `USB\VID_0BDA&PID_C811` 的 Model（同一 Install 段） |
| `packaging/driver/airbridge-winusb.cat` | 对当前 INF 的签名目录 | **必须在 Windows 重建并重签**（可复用原证书，也可新建；见第 5 节） |
| `packaging/setup/Check-Binding.ps1:11` | 只找 `C820&MI_02` | 找 c811 整设备或 c820 的 MI_02 |
| `tools/Check-Binding.ps1:15,31` | 只找 `C820&MI_02`，还单独检查 MI_00 蓝牙 | 两种设备都认；MI_00 检查改成“有则报告、无则跳过” |
| `tools/usb_probe/usb_probe.c:31` | 默认 PID `0xc820` | 默认 `0xc811`，或允许自动识别两者 |
| `packaging/setup/Bind-WinUSB.cmd:14,40` | 文案写死 `RTL8821CU / C820 / MI_02` | 改成“8811CU（整设备）或 8821CU 的 MI_02” |
| `packaging/setup/README.txt:18-31,41` | “三个接口，只换 MI_02” | 8811CU 没有 MI_02，绑定对象是整设备；复合设备才选 Wi-Fi 接口 |
| `packaging/README.txt:11`、`packaging/setup/licenses/ZADIG.txt:15` | 写死 8821CU/c820 | 同步 |
| `tools/Package-Distributable.ps1:123` | 注释写死 `C820&MI_02` | 同步 |
| `tools/esp32_witness/README.md:29` | 示例 `DEVOURER_PID='0xc820'` | 改成 c811 或说明两者 |
| `README.md:15,25,34,36,42,124` 等文档 | 全仓把 8821CU/c820 写成唯一硬件 | 文档整体更新；以 8811CU 为主，保留 8821CU 兼容说明 |

接口差异是这次改动里最容易被忽略的一点：8821CU 是复合设备，Wi-Fi 在 `MI_02`；
8811CU 通常是单功能设备，硬件 ID 是 `USB\VID_0BDA&PID_C811`，**没有** `MI_02`。
到底是不是复合设备，必须以实物 `tools/Inspect-Hardware.ps1` + `usb_probe.exe`
枚举为准，不能照抄。`find_wifi_interface()` 本身能处理 interface 0，但
INF、托盘检测和两个 `Check-Binding.ps1` 的 `MI_02` 假设都要改。

## 5. 驱动与签名（硬门槛，但不是“必须有原私钥”）

`tools/Build-DriverPackage.ps1` 用 `makecat` + `signtool` 生成
`airbridge-winusb.cat`。INF 一改，`.cat` 里的文件哈希就失效，
`pnputil /add-driver ... /install` 会拒绝或装不上，所以 **INF 和 .cat 必须在
同一次 Windows 操作里重建**。

“硬”的是环境，不是某一把钥匙：

- 需要 Windows + Windows SDK（`makecat`、`signtool`），和构建本身的要求一样。
- 原证书私钥在 `CurrentUser\My` 里时，脚本直接复用
  （`packaging/driver/signing-thumbprint.txt` 只存指纹）。
- 私钥不在也能做：`Build-DriverPackage.ps1 -Force` 会新建一张自签证书，导出新的
  `dropbridge-driver.cer` 并重签 `.cat`；运行时安装器导入的是**随包的 .cer**，
  所以新证书同样可用。代价只是旧机器上会多一张旧根证书。
- Mac 上不能产出 `.cat`（没有 `makecat`/`signtool`），所以 **不要在 Mac 上改
  INF**：保持 INF/.cat 成对一致，把这一步整体留到 Windows。

## 6. 不等待签名的测试路径

测试 8811CU 不需要先过签名这一关：Zadig/libwdi 会自己生成并安装驱动包，
完全不使用仓库里的 `airbridge-winusb.inf/.cat`。而且**连代码都不用先改**：
`airbridge_radio` 已支持 `AIRBRIDGE_PID` / `AIRBRIDGE_VID` 环境变量
（`src/radio_usb/main.cpp:288-289`），用现有构建把 PID 指到 `0xc811` 就能打开
8811CU。建议这样走：

0. **零代码冒烟（不签名、不改代码）**：Windows 上编译现有源码 → Zadig 把
   `0bda:c811` 绑到 WinUSB → `build\usb_probe\Release\usb_probe.exe 0bda c811
   --read8 00FC` 确认 chip-id `0x09` → `set AIRBRIDGE_PID=0xc811` →
   `build\radio_usb\Release\airbridge_radio.exe 149 20`。托盘仍按 c820 检测，
   会弹一次“没找到网卡”，但不挡后端启动；先单独跑 radio 可避开它。
1. **Mac：只改不用签名的部分。** 放开 c811 的设备识别、托盘/脚本匹配、文档；
   INF/.cat 不动，仓库始终是可打包状态。提交后用 `git format-patch`（或 bundle）
   同步到 Windows。
2. **Windows：用改后的代码跑完整链路（仍不需要签名）。** 编译 radio/托盘；
   用 Zadig 绑 c811；跑初始化、149/20 RX、TX 空口见证、AWDL/iPhone、真实文件。
   这一步就能回答“8811CU 在这台机器上到底行不行”。
3. **Windows：最后再做自动安装。** 改 INF 增加 c811，重跑
   `Build-DriverPackage.ps1`，用 `pnputil /add-driver ... /install` 验证，再在
   干净机器上确认首次运行能自动绑定；INF/.cat/.cer 三个文件一起提交。

只有第 3 步依赖签名；第 0/2 步失败就没必要做第 3 步。Mac 上改的源码在 Windows
编译、上机之前都应视为“未验证源码”，不能写进证据表。

## 7. 风险与未验证项

1. **板级差异**：EFUSE 的 `rfe_type`、天线、TX 功率表、5 GHz 149 信道都要在真实
   8811CU 上重测。上游验证的是 CF-811AC 这一块板，不等于用户手上的 8811CU。
2. **ZeroCD**：部分 Realtek 网卡会先以 `0bda:1a2b` 出现。devourer 在 USB reset
   后按“同一 bus/port + 原 VID:PID”等待回来（上游 `src/UsbOpen.cpp`），若落进
   `1a2b` 会打不开。`docs/BINDING_RUNBOOK.md:92` 已记录该风险，需实测；必要时先设
   `AIRBRIDGE_SKIP_RESET=1` 跳过复位再试，但连续 TX 的稳定性会下降。
3. **蓝牙**：8811CU 不带蓝牙；没有第二个蓝牙适配器时 beacon 不可用。当前 Intel
   AX211 已验证可用，但换机器要重新确认（要支持 BLE 广播）。
4. **性能**：同为 1T1R、同样没有接收方向硬件 BlockAck，不要期待提速；不同板子的
   天线/功率甚至可能更差。接收上限仍由 AWDL 调度和单 MPDU 决定。
5. **授权**：换卡、重绑驱动都要按 `AGENTS.md` 单独授权并写明恢复办法；不要自动
   替换驱动，也不要拿 8852CE 的经验推断 8811CU。

## 8. 建议顺序

0. **实物只读确认**：`tools/Inspect-Hardware.ps1` 记录 PID/接口/驱动；
   `usb_probe.exe 0bda c811 --read8 00FC` 确认 chip-id `0x09`，不改驱动、不初始化。
1. **Mac：源码同时支持 c811 / c820**：运行时按“实际存在的那张卡”选择，文档把
   8811CU 写成推荐硬件。先保留 c820，方便 A/B 和回归；INF/.cat 不动。
2. **Windows：Zadig 绑定 + Wi‑Fi 全链路验证**（不需要签名）：初始化/固件 →
   149/20 RX → TX 空口见证 → AWDL/iPhone → 真实文件。每步留证据。
3. **Windows：自动安装收尾**（需要签名）：改 INF → `Build-DriverPackage.ps1`
   → `pnputil` 安装 → 干净机器首次运行验证。
4. 8811CU 全绿后，再决定是否**只**保留 8811CU，并更新 README/安装说明/发布清单。

## 9. 工作量估计

| 项 | 估计 | 前提 |
| --- | --- | --- |
| 源码 + 脚本 + 文档（双 PID 支持） | 0.5–1 天 | 不需要硬件的部分 |
| 驱动包重签 + 自动安装验证 | 0.5 天 | Windows + Windows SDK（可新建证书） |
| 真机复测（初始化/149/TX/RX/AirDrop/文件） | 1–2 天 | 真实 8811CU、驱动授权 |
| 蓝牙 | 0 | 已有独立实现；机器需有 BLE 适配器 |

## 10. 明确不改的部分

- devourer 的 `C8821C` 后端、固件 blob、PHY/RF 表、1T1R 能力声明。
- `radio_link` v3 线格式、AWDL/OWL 进程、`awdl_netd`、receiver。
- 蓝牙 beacon 脚本、托盘 beacon 开关与退避逻辑。

这些都与“换成 8811CU”无关，改了只会扩大回归面。
