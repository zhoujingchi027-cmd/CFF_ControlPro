# CFFwelding TwinCAT Build报告

## 构建环境

- 记录更新至：2026-08-04
- TwinCAT：TwinCAT 3.1 Build 4024，DisplayVersion `3.1.4024.64`
- TwinCAT XAE Shell产品DisplayVersion：`1.15.0.0`
- `TcXaeShell.exe`文件版本：`15.0.0.0`
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
| Phase 5 | `Release\|TwinCAT RT (x64)` | 已执行 | Force/Displacement/S_rel/Collision处理加入后 `SolutionBuild.LastBuildInfo = 0` | PASS |
| Phase 6 | `Release\|TwinCAT RT (x64)` | 已执行 | Z/R标准NC Adapter与Owner仲裁加入后 `SolutionBuild.LastBuildInfo = 0` | PASS |
| Phase 7 | `Release\|TwinCAT RT (x64)` | 已执行 | External Setpoint完整生命周期加入后 `SolutionBuild.LastBuildInfo = 0` | PASS |
| Phase 8 | `Release\|TwinCAT RT (x64)` | 已执行 | 导纳PI、无扰切换、S_rel制动和机器限值快照加入后 `SolutionBuild.LastBuildInfo = 0` | PASS |
| Phase 9 | `Release\|TwinCAT RT (x64)` | 已执行 | Contact/Decline/Step Criterion加入后 `SolutionBuild.LastBuildInfo = 0` | PASS |
| Phase 10 | `Release\|TwinCAT RT (x64)` | 已执行 | 完整Fast侧CFF顺序控制加入后，进程exit 0且 `SolutionBuild.LastBuildInfo = 0` | PASS |

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
- 真实轴External Setpoint POC或时序已验证；
- 导纳力控在真实Runtime、真实传感器和真实机械上的响应已验证；
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

## Phase 5执行记录

Phase 5实现未绑定EP3174/位移/Collision占位的诊断处理、四路Force、Contact参考点事务和累计`SRelSensor/SRelAxis`。首次实际引用通用POU时，XAE报告4处末语句缺少分号；根据XAE Error List精确修复并增加回归测试后，最终`LastBuildInfo=0`。

本阶段Build不证明物理PDO、传感器标定、轴位置或Collision功能有效；对应Mapped、DriveLinked和Production Ready状态保持`FALSE`。

## Phase 6执行记录

Phase 6实现Z轴Owner仲裁、Z轴标准回零/绝对定位/速度/停止/复位Adapter，以及R轴RPM/停止/复位Adapter。MC接口按本机`Tc2_MC2 3.3.65.0`和Beckhoff官方文档核对，真实XAE构建证据为：

```text
Starting TwinCAT XAE Shell build: TcXaeShell.DTE.15.0
Building project 'CFFwelding_System\CFFwelding_System.tsproj' with 'Release|TwinCAT RT (x64)'.
CFFwelding XAE build: PASSED
Configuration: Release|TwinCAT RT (x64)
LastBuildInfo: 0
```

该Build只证明标准运动对象与当前库版本可编译。`bZAxisDriveLinked`和`bRAxisDriveLinked`仍为`FALSE`，因此Adapter的Power、运动Execute和Ready均被硬门控；没有进行配置激活、下载、Runtime登录或物理轴动作。

## Phase 7执行记录

Phase 7加入Z轴External Setpoint命令/状态/配置契约、唯一`FB_ZAxisExtSetpointAdapter`实例、Owner保持和固定报警槽。生命周期覆盖初值预装、Enable确认、每2 ms Feed、降速归零、Direction保持与清零、Disable确认、附加Feed周期和Post-disable hold。

本机PLC工程固定使用`Tc2_MC2 3.3.65.0`。本机类型库和最小编译探针证明`MC_ExtSetPointGenEnable`使用四参数旧签名，不包含当前在线文档中的`Options`或`ST_ExtSetPointEnableOptions`。工程因此按本机签名构建，并禁止`MC_ExtSetPointGenFeedWithTorque`，不提供Torque Offset。

最终控制台证据：

```text
Phase 7 external setpoint test: PASSED
Starting TwinCAT XAE Shell build: TcXaeShell.DTE.15.0
Building project 'CFFwelding_System\CFFwelding_System.tsproj' with 'Release|TwinCAT RT (x64)'.
CFFwelding XAE build: PASSED
Configuration: Release|TwinCAT RT (x64)
LastBuildInfo: 0
```

源码Commit：`4f1bfa8de7a3117558993ce07f655d59ccddcd74`。

该Build只证明固定本机库版本下的离线编译结果。未扫描设备、未激活配置、未下载、未登录Runtime、未使能物理轴；External POC、真实驱动关联、抖动测量、硬件映射和工艺资格均未完成。

## Phase 8执行记录

Phase 8加入纯算法`FB_BumplessProfileSwitch`和`FB_ZForceAdmittance`，由`PRG_FastAxisControl`唯一实例化。实现覆盖力设定斜坡、速度前馈、PI、Back-calculation Anti-windup、Profile/机器双向速度与有效加速度、S_rel制动、硬力/行程/Collision边界、Profile及机器限值快照和故障锁存。

最终控制台证据：

```text
Phase 8 force admittance test: PASSED
Starting TwinCAT XAE Shell build: TcXaeShell.DTE.15.0
Building project 'CFFwelding_System\CFFwelding_System.tsproj' with 'Release|TwinCAT RT (x64)'.
CFFwelding XAE build: PASSED
Configuration: Release|TwinCAT RT (x64)
LastBuildInfo: 0
```

源码Commit：`2b9a470e215962d7696cae4036224284f36f66ce`。

该Build只证明本机固定库版本下离线工程可编译。Phase 8默认不使能，不写External P/V/A/Direction；未进行Runtime算法执行、设备扫描、配置激活、下载、物理轴动作、周期抖动测量或工艺资格验证。

## Phase 9执行记录

Phase 9加入纯算法`FB_ContactDetect`、`FB_ForceDeclineObserver`和`FB_StepProceedingCriterion`，由`PRG_CffSequence`唯一实例化并保持全部Enable为`FALSE`。实现覆盖Contact回差/去抖/候选位置锁存、Decline Arm/负下降率/窗口/回差、Primary/Secondary、StepMin/Max、EndCause和完整四步骤Program Validation。

最终控制台证据：

```text
Phase 9 contact and criterion test: PASSED
Starting TwinCAT XAE Shell build: TcXaeShell.DTE.15.0
Building project 'CFFwelding_System\CFFwelding_System.tsproj' with 'Release|TwinCAT RT (x64)'.
CFFwelding XAE build: PASSED
Configuration: Release|TwinCAT RT (x64)
LastBuildInfo: 0
```

源码Commit：`35d564de70170579e5e718ac5a69caa088ba74cc`。

该Build只证明本机固定库版本下离线工程可编译。Phase 9不写Contact RequestId、Force Control Enable或External P/V/A/Direction；未进行Runtime算法执行、设备扫描、配置激活、下载、物理轴动作、周期抖动测量或工艺资格验证。

## Phase 10最终构建记录

Phase 10完成Fast侧CFF顺序控制、Contact事务、Step 1–4、R轴RPM事务、External P/V/A/Direction连续输出、有效Direction切换、Force控制、受控退出与终态判定。对应源码Commit为`0d9f190b1d31f00a5d83069d5b4e122be17c5e61`。

最终验证中，Phase 1–9全部PASS；`Test-Phase10CffSequence.ps1 -Scope All`为PASS且exit 0。随后使用仓库标准脚本执行离线XAE Build：

```text
Configuration: Release|TwinCAT RT (x64)
Process exit code: 0
SolutionBuild.LastBuildInfo: 0
```

本次DTE未暴露`ToolWindows.ErrorList`接口，因此Error和Warning的分项计数不可得，不能写成0。`LastBuildInfo = 0`只表示Solution Build没有失败项目。

构建前后关键生成物保持一致：

| 文件 | 构建前SHA-256 | 构建后SHA-256 | 结果 |
|---|---|---|---|
| `CFFwelding.tmc` | `F4D33032F40D23F412091248DB7AF09666075DC62E517FD51679EA8942D31098` | `F4D33032F40D23F412091248DB7AF09666075DC62E517FD51679EA8942D31098` | 一致 |
| `CFFwelding_System.tsproj` | `3D212C8908206C8A1696932C3B0251C01B5DF7C6D2738E2A02AB28B906499905` | `3D212C8908206C8A1696932C3B0251C01B5DF7C6D2738E2A02AB28B906499905` | 一致 |

Phase 10构建生成的关键TMC/ADS契约如下：

| 对象 | BitSize | 字段数/类型 |
|---|---:|---|
| `ST_ZExternalTrajectoryInput` | 960 bit | 20 fields |
| `ST_ZExternalTrajectoryOutput` | 320 bit | 11 fields |
| `ST_CffSequenceStatus` | 5312 bit | 32 fields |
| `ST_FastStatus` | 8768 bit | 18 fields |
| `GVL_Config.stCffSequence` | 448 bit | `ST_CffSequenceConfig` |
| `GVL_FastInternal.stAcceptedCommand` | 1280 bit | `ST_FastCommand` |

`GVL_Status.bProductionReady`保持`FALSE`。本次仅为离线静态/生成物/构建验证；没有执行Runtime或实时测试、External POC、真实驱动、任务抖动测量、I/O映射、标定、工艺资格、Scan、Activate Configuration、Download、Login、Online Change或真实运动。

临时typed Collision路径仍保留，等待Phase 11B删除/替换与双位移参考冗余设计，不能将当前结果称为最终双位移碰撞算法。Torque闭环/前馈、Energy、Power、Material Observer、Process Window、Curve Recorder和最终Result Analyzer也不在本次构建完成范围内。
