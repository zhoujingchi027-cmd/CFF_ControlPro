# Phase 2 Task、PROGRAM骨架和实例接口执行报告

## 目标

建立Fast/Main/Slow三任务、完整PROGRAM对象目录、类型化内部命令/状态接口，并在不创建FB实现、不绑定外部硬件的前提下冻结后续实例Owner和PROGRAM间契约。

## 创建内容

### PLC任务

| PLC Task | Priority | Phase 2周期 | PROGRAM数量 | 状态 |
|---|---:|---:|---:|---|
| `Task_CffFast` | 10 | `10000 us` | 4 | 临时占位，待NC SAF实测后校正 |
| `Task_CffMain` | 20 | `10000 us` | 15 | 架构建议值，后续按负载和抖动复核 |
| `Task_CffSlow` | 30 | `50000 us` | 4 | 架构建议范围内，后续按负载复核 |

`Task_CffFast`文件包含`TODO_NC_SAF`，明确当前10 ms不得解释为已经匹配NC SAF。Phase 3若能在无驱动条件下创建NC轴，必须读取新工程实际NC SAF周期并立即同步Fast Task。

### PROGRAM骨架

Fast Task调用顺序：

1. `PRG_FastInputs`
2. `PRG_CffSequence`
3. `PRG_FastAxisControl`
4. `PRG_FastMonitoring`

Main Task调用顺序：

1. `PRG_ModeControl`
2. `PRG_RobotInterface`
3. `PRG_CommandDispatcher`
4. `PRG_ProgramManager`
5. `PRG_InitializeControl`
6. `PRG_ServiceCalibration`
7. `PRG_MaintenanceControl`
8. `PRG_ManualControl`
9. `PRG_AutoControl`
10. `PRG_FastenerControl`
11. `PRG_FeederControl`
12. `PRG_ClampControl`
13. `PRG_MachineMain`
14. `PRG_AlarmControl`
15. `PRG_TowerLightControl`

Slow Task调用顺序：

1. `PRG_HmiAdsInterface`
2. `PRG_ResultTraceability`
3. `PRG_Statistics`
4. `PRG_Persistence`

全部23个对象均为`PROGRAM`，`VAR`区为空，Implementation只有中文程序骨架块注释，不包含业务逻辑、设备命令、仿真或假Ready。

### 内部接口DUT

创建14个关键类型化接口：

- `ST_ZForceControlInput` / `ST_ZForceControlOutput`
- `ST_ZExtSetpointCommand` / `ST_ZExtSetpointStatus`
- `ST_ZAxisCommand` / `ST_ZAxisStatus`
- `ST_RAxisCommand` / `ST_RAxisStatus`
- `ST_ContactDetectInput` / `ST_ContactDetectOutput`
- `ST_StepCriterionInput` / `ST_StepCriterionOutput`
- `ST_CffSequenceCommand` / `ST_CffSequenceStatus`

每个公开字段前都有独立行中文注释；物理量字段名包含单位后缀。Phase 3才创建的枚举当前使用`UDINT`占位，并已在接口目录中标记替换任务。

### 报告与脚本

- `Docs/报告/INSTANCE_OWNERSHIP_MATRIX.md`
- `Docs/报告/INTERNAL_INTERFACE_CATALOG.md`
- `Docs/报告/PHASE_2_EXECUTION_REPORT.md`
- `scripts/Test-Phase2Architecture.ps1`
- `scripts/Sync-CffweldingPhase2Tasks.ps1`

## 删除/替换内容

- 删除标准模板空对象`POUs/MAIN.TcPOU`。
- 删除标准模板任务`PlcTask.TcTTO`。
- 使用完整Task/PROGRAM架构替代上述模板对象。
- XAE将原System Task `PlcTask`与PLC Context `Task_CffMain`自动关联；同步脚本只在验证Priority 20和10 ms后将该System节点重命名为`Task_CffMain`。

## TDD证据

### 初始RED

`Test-Phase2Architecture.ps1`在实现前报告23个PROGRAM、14个DUT、3个Task和2个报告全部缺失，同时报告模板`MAIN/PlcTask`仍存在。

### System Task RED

首次Build后新增检查发现System层名称仍为`PlcTask`，而PLC Context已经是`Task_CffMain`。这项失败促使增加受约束的XAE同步脚本；没有通过放宽测试掩盖问题。

### GREEN

```text
Phase 2 architecture test: PASSED
PROGRAM count: 23
Interface DUT count: 14
Task count: 3
```

## Build证据

命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1
```

实际结果：

```text
CFFwelding XAE build: PASSED
Configuration: Release|TwinCAT RT (x64)
LastBuildInfo: 0
```

Build后`CFFwelding.tmc`和System Project上下文由XAE更新。没有把XML解析、PowerShell语法或文件计数冒充为Build。

## 静态审查

- 41个PLC项目XML文件可解析。
- 14个DUT的全部字段具有独立行中文注释。
- 23个PROGRAM均为ASCII标识符并包含中文骨架块注释。
- PROGRAM `VAR`区为空，不存在FB实例重复声明。
- 实例矩阵已经为后续FB分配唯一Owner和声明位置；当前无`GVL_Instance`。
- `PRG_CffSequence`不调用MC。
- System Project顶层仍只有`System`和`Plc`。
- I/O、NC、Safety节点：无。
- XTI设备文件、真实PDO映射、实际驱动关联：无。
- 同步与构建脚本不存在Scan、Activate、Download、Runtime Start/Restart调用。

## 警告与TODO

1. `Task_CffFast = 10 ms`只是Phase 2可编译占位；不代表NC SAF，也不允许据此进行控制器整定。
2. Phase 3必须创建显式枚举、完整结构/GVL、`AXIS_REF`和无硬件绑定占位，并把本Phase的`UDINT`状态字段替换为枚举。
3. 任何实际FB实例加入PROGRAM时，必须严格使用实例所有权矩阵，并在声明前加入中文用途/任务/Owner/输入/输出/Reset块注释。
4. 当前没有硬件有效状态或生产Ready逻辑，不能运行生产流程。

## Git状态

- Phase 2主Commit：`8780363b820c4a14da16664ad4b043d2307deebd`
- Commit消息：`feat(architecture): add Phase 2 task and program skeletons`
- Push：已成功推送至`origin/codex/cffwelding-greenfield-v3.3`。
- 远端复核：`refs/heads/codex/cffwelding-greenfield-v3.3`与上述主Commit完全一致。
- 本段Git证据由后续报告Commit补录，不改写主Commit。
