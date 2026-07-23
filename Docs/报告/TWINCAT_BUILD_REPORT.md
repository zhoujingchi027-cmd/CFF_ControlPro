# CFFwelding TwinCAT Build报告

## 构建环境

- 日期：2026-07-22
- TwinCAT：`3.1.4024.64`
- XAE Shell：`15.0.0.0`
- Automation COM：`TcXaeShell.DTE.15.0`
- Solution：`CFFwelding.sln`

## 分阶段结果

| Phase | 配置 | 真实XAE Build | 证据 | 结果 |
|---|---|---|---|---|
| Phase 0 | 不适用 | 未执行 | 当时尚无Solution | N/A |
| Phase 1 | `Release\|TwinCAT RT (x64)` | 已执行 | `SolutionBuild.LastBuildInfo = 0` | PASS |
| Phase 2 | `Release\|TwinCAT RT (x64)` | 已执行 | `SolutionBuild.LastBuildInfo = 0` | PASS |
| Phase 3 | `Release\|TwinCAT RT (x64)` | 已执行 | 轴映射后 `SolutionBuild.LastBuildInfo = 0` | PASS |
| Phase 4 | `Release\|TwinCAT RT (x64)` | 已执行 | 14个FC和6个通用FB加入后 `SolutionBuild.LastBuildInfo = 0` | PASS |

## Phase 1执行记录

构建入口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1
```

XAE Automation构建调用：

```text
BuildProject("Release|TwinCAT RT (x64)", "CFFwelding_System\CFFwelding_System.tsproj", true)
```

控制台证据：

```text
Starting TwinCAT XAE Shell build: TcXaeShell.DTE.15.0
Building project 'CFFwelding_System\CFFwelding_System.tsproj' with 'Release|TwinCAT RT (x64)'.
Phase 1 XAE build: PASSED
Configuration: Release|TwinCAT RT (x64)
LastBuildInfo: 0
```

构建生成`CFFwelding_System/CFFwelding/CFFwelding.tmc`，PLC工程归档并解析了标准模板库、`Tc2_MC2 3.3.65.0`及其依赖。

## 构建边界

当前 Build 证明本机 XAE 可以编译 PLC 数据架构、两个离线 NC 轴、Fast/SAF 周期同步和 PLC↔NC 内部映射。它不证明：

- 真实I/O或PDO映射有效；
- 真实驱动、编码器或物理轴配置有效；
- External Setpoint调用已验证；
- 安全功能、工艺参数或Production Ready状态已验证。

构建脚本不激活配置、不下载工程、不启动或重启TwinCAT Runtime。

## Phase 2执行记录

Phase 2加入3个PLC Task、23个PROGRAM骨架和14个内部接口DUT，并将模板`MAIN/PlcTask`替换为完整调用架构。

控制台证据：

```text
Phase 2 architecture test: PASSED
PROGRAM count: 23
Interface DUT count: 14
Task count: 3
Starting TwinCAT XAE Shell build: TcXaeShell.DTE.15.0
Building project 'CFFwelding_System\CFFwelding_System.tsproj' with 'Release|TwinCAT RT (x64)'.
CFFwelding XAE build: PASSED
Configuration: Release|TwinCAT RT (x64)
LastBuildInfo: 0
```

Phase 2构建仍不证明NC SAF周期已确认。`Task_CffFast`的10 ms为明确标记的临时占位，必须在后续取得新工程实际NC SAF周期后校正。

## Phase 3执行记录

Phase 3加入26个显式数值枚举、33个共享结构体、13个`qualified_only` GVL，以及两个未绑定真实驱动的离线NC轴。XAE创建的`NC_Cff SAF`实际周期为`20000 × 100 ns = 2 ms`，因此PLC和系统`Task_CffFast`均同步为2 ms。

内部映射严格为：

```text
Task_CffFast Inputs^GVL_IO.Z_axis.NcToPlc  <-> Z_Axis_NC^Outputs^ToPlc
Task_CffFast Outputs^GVL_IO.Z_axis.PlcToNc <-> Z_Axis_NC^Inputs^FromPlc
Task_CffFast Inputs^GVL_IO.R_axis.NcToPlc  <-> R_Axis_NC^Outputs^ToPlc
Task_CffFast Outputs^GVL_IO.R_axis.PlcToNc <-> R_Axis_NC^Inputs^FromPlc
```

最终控制台证据：

```text
PowerShell syntax: PASSED
Phase 1 acceptance test: PASSED
Phase 2 architecture test: PASSED
Phase 3 data and binding test: PASSED
Enum count: 26
Structure count: 33
GVL count: 13
Starting TwinCAT XAE Shell build: TcXaeShell.DTE.15.0
Building project 'CFFwelding_System\CFFwelding_System.tsproj' with 'Release|TwinCAT RT (x64)'.
CFFwelding XAE build: PASSED
Configuration: Release|TwinCAT RT (x64)
LastBuildInfo: 0
```

工程没有 I/O 设备节点或 Safety 配置。XAE为映射基础设施自动序列化的空`<Io/>`容器不包含主站、设备、端子或PDO链接。两个NC轴的默认Drive/Encoder对象未与任何真实硬件或仿真驱动关联。

## Phase 4执行记录

Phase 4加入14个纯计算FC和6个通用FB，覆盖缩放、限幅、积分、插值、单位换算、能量增量、标定/Program校验、制动速度边界、滤波、去抖、信号有效性、斜坡、命令握手和报警锁存。

第一次调用构建脚本时，XAE已经暴露System Project对象，但`SolutionBuild.SolutionConfigurations`尚未完成异步加载，因此脚本在Build前报告配置列表为空。脚本增加第二加载边界等待后，最终证据为：

```text
Phase 4 utility test: PASSED
Function count: 14
Utility FB count: 6
Starting TwinCAT XAE Shell build: TcXaeShell.DTE.15.0
Building project 'CFFwelding_System\CFFwelding_System.tsproj' with 'Release|TwinCAT RT (x64)'.
CFFwelding XAE build: PASSED
Configuration: Release|TwinCAT RT (x64)
LastBuildInfo: 0
```

Phase 4对象没有`AXIS_REF`、`MC_*`或GVL依赖，也没有创建或修改硬件配置。Build只证明PLC对象可编译。
