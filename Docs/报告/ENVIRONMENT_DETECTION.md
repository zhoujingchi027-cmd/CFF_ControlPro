# CFFwelding 环境检测报告

## 检测范围

- 检测日期：2026-07-22
- 当前工作目录：`E:\新工艺程序资料`
- 唯一写入目录：`E:\新工艺程序资料\倍福CFF控制`
- 只读参考目录：
  - `E:\新工艺程序资料\CFF_TwinCAT3_Pro`
  - `E:\新工艺程序资料\CFF_TwinCAT3`
  - `E:\新工艺程序资料\FDS_PLC`
  - `E:\新工艺程序资料\SPR重庆发货`
  - `E:\新工艺程序资料\GroupMDG`
- 固定输出冲突：`CFFwelding.sln`、`CFFwelding_System`和`CFFwelding`均不存在。

## TwinCAT 与开发环境

- TwinCAT版本：`3.1.4024.64`
- TwinCAT Build：`4024`
- TwinCAT安装目录：`C:\TwinCAT\3.1\`
- TwinCAT XAE Shell：`15.0.0.0`
- XAE Shell路径：`C:\Program Files (x86)\Beckhoff\TcXaeShell\Common7\IDE\TcXaeShell.exe`
- Visual Studio 2019：`16.11.35826.135`
- Visual Studio 2022：`17.12.35527.113`
- 已检测到VS2019的TwinCAT XAE扩展目录。
- Phase 1首选构建入口：TwinCAT XAE Shell 15，通过Automation Interface创建工程并调用Solution Build。

## Automation Interface

- `TcXaeShell.DTE.15.0`：已注册。
- `TCatSysManager.tlb` 3.1：存在。
- `Standard PLC Template.plcproj`：存在。
- Phase 0只验证注册和文件，不启动工程创建、不登录Runtime、不下载或激活配置。

## PLC库

| 库 | 已安装版本 | Phase 1候选版本 |
|---|---|---|
| `Tc2_Standard` | `3.3.3.0`, `3.4.5.0` | `3.4.5.0` |
| `Tc2_MC2` | `3.3.45.0`, `3.3.65.0` | `3.3.65.0` |

候选版本只表示本机存在。实际工程引用版本必须在Phase 1创建工程后由XAE解析和Build证据确认。

## External Setpoint API

本机`Tc2_MC2 3.3.65.0`的库浏览缓存确认存在：

- `MC_ExtSetPointGenEnable`
- `MC_ExtSetPointGenFeed`
- `MC_ExtSetPointGenDisable`

已核对的公开接口边界：

- Enable输入包含`Execute`、`Position`、`PositionType`和`Options`，并通过`VAR_IN_OUT Axis : AXIS_REF`访问轴。
- Feed输入包含`Position : LREAL`、`Velocity : LREAL`、`Acceleration : LREAL`和`Direction : DINT`，并通过`VAR_IN_OUT Axis : AXIS_REF`访问轴。
- Disable输入包含`Execute`，并通过`VAR_IN_OUT Axis : AXIS_REF`访问轴。
- `Direction`只允许`-1`、`0`、`1`；最终生命周期和调用签名仍须以新工程实际库声明及Build为准。

## NC SAF周期

- Phase 0实测状态：不可取得。
- 原因：新工程尚无`CFFwelding.sln`、System Project、NC轴或NC SAF任务。
- 禁止处理：不得把FastTask周期预设为`1 ms`，不得从旧工程周期推定新工程周期。
- 后续验证：创建未绑定真实驱动的NC轴对象后，只读获取新工程实际NC SAF周期，并将`Task_CffFast`配置为相同周期。

## 隔离与硬件边界

- 未执行`Scan Devices`、`Scan Boxes`或`Scan Motors`。
- 未添加EP3174、IO-Link、AX5000、编码器、机器人、送料或其他实际硬件。
- 未建立PLC变量到真实PDO的链接。
- 未建立NC轴到真实驱动或编码器的链接。
- Phase 0未创建TwinSAFE、仿真、虚拟轴、假IO、WPF或数据库。

## Phase 0构建状态

- Build：不适用。
- 原因：Phase 0只完成隔离和环境检测；TwinCAT Solution将在Phase 1创建。
- 不声明编译通过。

## 阻塞项与下一步

1. 新工程的实际NC SAF周期尚未产生。
2. `Tc2_MC2`和`Tc2_Standard`候选版本尚未由新工程Build确认。
3. External Setpoint接口尚未在新PLC工程中完成编译验证。
4. 所有外部硬件映射和生产Ready保持后续人工任务；Phase 0不提供任何旁路。
