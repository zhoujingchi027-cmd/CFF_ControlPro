# Phase 3 数据模型与离线NC绑定执行报告

## 目标

建立可编译、可审查的数据模型和全局变量契约；在不扫描、不连接真实硬件、不启用仿真驱动的前提下创建两个离线NC轴，并让PLC Fast Task严格跟随新工程实际NC SAF周期。

## 创建内容

### 数据模型

- 26个显式数值枚举，均位于`DUTs/Enums`。
- 33个共享结构体，均位于`DUTs/Structures`。
- 13个带`{attribute 'qualified_only'}`的GVL。
- 将Phase 2接口中的状态占位字段替换为显式枚举类型。
- 公开字段继续使用独立行中文注释；物理量字段继续使用单位后缀。

关键安全默认值：

- `GVL_Status.bProductionReady := FALSE`。
- `ST_HardwareBindingStatus`的9个硬件绑定状态字段全部默认`FALSE`。
- I/O占位符只使用`%I*`和`%Q*`，不存在硬编码真实地址或假Ready。

### 离线NC与内部映射

- NC Task：`NC_Cff SAF`。
- 离线NC轴：`Z_Axis_NC`、`R_Axis_NC`。
- PLC引用：`GVL_IO.Z_axis : AXIS_REF`、`GVL_IO.R_axis : AXIS_REF`。
- `GVL_IO`使用`{attribute 'TcContextName' := 'Task_CffFast'}`。
- NC SAF实测周期：`20000 × 100 ns = 2 ms`。
- `Task_CffFast`的PLC周期、System Task周期与NC SAF同步为2 ms。

内部映射共4条：

```text
Task_CffFast Inputs^GVL_IO.Z_axis.NcToPlc  <-> Z_Axis_NC^Outputs^ToPlc
Task_CffFast Outputs^GVL_IO.Z_axis.PlcToNc <-> Z_Axis_NC^Inputs^FromPlc
Task_CffFast Inputs^GVL_IO.R_axis.NcToPlc  <-> R_Axis_NC^Outputs^ToPlc
Task_CffFast Outputs^GVL_IO.R_axis.PlcToNc <-> R_Axis_NC^Inputs^FromPlc
```

两个轴的Drive/Encoder对象未连接真实驱动、编码器或仿真驱动。工程没有I/O设备、端子、PDO或Safety节点；XAE为内部映射基础设施自动序列化的空`<Io/>`容器不包含任何子节点。

## 自动化脚本

- `scripts/Configure-CffweldingPhase3OfflineNc.ps1`
- `scripts/Sync-CffweldingPhase3FastTask.ps1`
- `scripts/Link-CffweldingPhase3AxisRefs.ps1`
- `scripts/Test-Phase3DataAndBindings.ps1`

三个配置脚本均已重复执行验证幂等性。重复执行时识别现有NC Task、轴、周期和4条映射，不产生重复对象或链接。

## TDD证据

### RED

在实现前运行`Test-Phase3DataAndBindings.ps1`，测试报告枚举、结构体、GVL、离线NC配置、Fast周期同步、轴引用和Phase 3报告全部缺失。

实现数据模型和映射后，测试仅保留执行报告缺失这一预期失败；报告补齐后进入GREEN。

### GREEN

```text
Phase 3 data and binding test: PASSED
Enum count: 26
Structure count: 33
GVL count: 13
```

Phase 1与Phase 2回归验收同时通过：

```text
Phase 1 acceptance test: PASSED
Phase 2 architecture test: PASSED
PROGRAM count: 23
Interface DUT count: 14
Task count: 3
```

## Build证据

实际执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1
```

最终结果：

```text
Starting TwinCAT XAE Shell build: TcXaeShell.DTE.15.0
Building project 'CFFwelding_System\CFFwelding_System.tsproj' with 'Release|TwinCAT RT (x64)'.
CFFwelding XAE build: PASSED
Configuration: Release|TwinCAT RT (x64)
LastBuildInfo: 0
```

调试过程中确认：只修改PLC Task而未同步System Task时，XAE Build返回`LastBuildInfo = 2`。最终同步脚本通过XAE Automation同时更新System `Task_CffFast`为2 ms，随后真实Build通过；没有放宽测试或把静态解析冒充Build。

## 静态审查

- 所有PowerShell脚本语法检查通过。
- Phase 1、Phase 2、Phase 3验收脚本全部通过。
- XML解析、中文字段注释、显式枚举值、`qualified_only`、安全默认值全部通过。
- NC SAF、PLC Fast和System Fast三处周期一致为2 ms。
- 4条PLC↔NC内部映射完整且无重复。
- 凭据模式检查为0项。
- 暂存差异检查通过。
- 没有Scan、Activate、Download、Login、Runtime Start/Restart调用。

## 参考复用与边界

旧工程只用于只读核对System Manager内部映射XML结构，具体检索范围与结论记录在`Docs/报告/REFERENCE_REUSE_LOG.md`。没有复制旧工程业务逻辑、设备配置、真实I/O映射、驱动参数或硬件地址。

新增人工接线与配置清单位于：

- `Docs/报告/HARDWARE_MANUAL_BINDING_CHECKLIST.md`
- `Docs/报告/IO_MAPPING_TODO.md`
- `Docs/报告/NC_CONFIGURATION_CHECKLIST.md`

## 警告与TODO

1. 当前两个轴只能证明离线工程结构、类型和内部映射可编译，不能证明真实驱动、编码器、限位或运动方向正确。
2. 当前I/O均为占位，Production Ready保持`FALSE`；在人工硬件映射、逐项验证和现场安全验收前不得用于生产。
3. 2 ms来自本次新工程NC SAF实际配置；如后续人工修改NC SAF，必须重新同步Fast Task并重新Build。
4. External Setpoint、运动功能块和工艺逻辑尚未在本Phase实现。

## Git状态

- Phase 3主Commit：`d5667d7e13238828e7bd3db65801724e5ae5b29e`
- Commit消息：`feat(data): add Phase 3 model and offline NC bindings`
- Push：由本报告Commit后执行并复核。
- 本段Git证据由后续报告Commit补录，不改写主Commit。
