# Phase 1 空工程创建执行报告

## 目标

使用本机TwinCAT XAE Automation Interface创建全新的`CFFwelding`空工程，加入最小PLC库集合，并完成一次真实的空Build。若XAE不可用才允许转入SourceImport；本阶段XAE可用，因此未使用SourceImport回退。

## 创建内容

- Solution：`CFFwelding.sln`
- TwinCAT System Project：`CFFwelding_System/CFFwelding_System.tsproj`
- PLC Project：`CFFwelding_System/CFFwelding/CFFwelding.plcproj`
- 默认PLC任务：`PlcTask`
- 空PROGRAM：`MAIN`
- XAE创建脚本：`scripts/New-CffweldingPhase1.ps1`
- XAE构建脚本：`scripts/Build-Cffwelding.ps1`
- Phase 1验收脚本：`scripts/Test-Phase1Project.ps1`

## TDD证据

### RED

工程创建前执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase1Project.ps1
```

预期失败已实际发生，报告缺少：

- `CFFwelding.sln`
- `CFFwelding_System/CFFwelding_System.tsproj`
- `CFFwelding.plcproj`

### GREEN

工程创建后重新执行同一命令，结果为：

```text
Phase 1 acceptance test: PASSED
```

验收覆盖Solution/System/PLC固定命名、XML可解析、UTF-8、必需库引用和禁止硬件标识检查。

## XAE Automation实现

- COM入口：`TcXaeShell.DTE.15.0`
- TwinCAT模板：`C:\TwinCAT\3.1\Components\Base\PrjTemplate\TwinCAT Project.tsproj`
- PLC模板：`Standard PLC Template`
- Silent Mode：启用
- IDE UI：隐藏
- 对IDE忙碌的`RPC_E_CALL_REJECTED`/`RPC_E_SERVERCALL_RETRYLATER`使用有界重试。
- 对被中断后留下的“空Solution”“System Project已创建”“标准PLC已创建”三种精确中间态提供非覆盖式恢复；发现任何非预期工程则拒绝继续。

创建脚本中不存在设备扫描、真实硬件关联、配置激活、工程下载或Runtime启动/重启调用。

## PLC库

标准PLC模板提供三个默认Placeholder：

| 引用 | XAE实际归档版本 |
|---|---|
| `Tc2_Standard` | `3.4.5.0` |
| `Tc2_System` | `3.6.4.0` |
| `Tc3_Module` | `3.4.5.0` |

本阶段只直接增加一个库：

| 引用 | 固定版本 |
|---|---|
| `Tc2_MC2` | `3.3.65.0` |

`Tc2_Math 3.4.4.0`由XAE作为依赖归档，不是额外的直接工程引用。归档库随工程保存，用于后续可复现构建。

## Build证据

执行命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1
```

实际XAE调用：

```text
SolutionBuild.BuildProject(
  "Release|TwinCAT RT (x64)",
  "CFFwelding_System\CFFwelding_System.tsproj",
  true
)
```

实际结果：

```text
Phase 1 XAE build: PASSED
Configuration: Release|TwinCAT RT (x64)
LastBuildInfo: 0
```

`CFFwelding.tmc`由本次真实Build生成。没有把脚本语法检查、XML解析或文件存在检查冒充为TwinCAT Build。

## 静态审查

- `CFFwelding_System.tsproj`顶层工程内容只有`System`和`Plc`。
- I/O节点：无。
- NC节点/NC轴：无。
- XTI设备文件：0。
- EP3174、AX5000、EtherCAT、IO-Link、TwinSAFE对象：无。
- PLC变量到真实PDO的链接：无。
- NC轴到驱动或编码器的链接：无。
- `MAIN`只有空声明区和空实现，没有业务逻辑、仿真逻辑、假IO或假Ready。
- 未执行Scan Devices、Scan Boxes或Scan Motors。
- 未激活、未下载、未登录Runtime。

## 旧工程与复用

- 五个旧工程仍为只读参考目录。
- Phase 1未从旧工程复制Solution、System Project、PLC对象、POU、GVL、DUT或配置XML。
- 本阶段不存在参考代码复用项。

## 警告与TODO

1. 当前`PlcTask`是标准模板默认任务，周期为`10000 us`；它不是尚待创建的`Task_CffFast`，也不代表NC SAF实际周期。
2. 当前没有NC配置，因此NC SAF实际周期仍不可取得，未作任何猜测。
3. `Tc2_MC2`库解析和空工程Build已验证，但External Setpoint对象的项目内调用要到对应实现Phase再通过编译确认。
4. 真实硬件未映射；项目不具备Production Ready条件，后续生产Start必须继续受硬件有效状态约束。
5. Phase 2应创建Task、PROGRAM骨架和内部实例接口，并在修改后再次执行真实Build。

## Git状态

- Phase 1主Commit：`717737001cd31e960c9f6e618458830fafd722d1`
- Commit消息：`feat(project): create empty CFFwelding TwinCAT solution`
- Push：已成功推送至`origin/codex/cffwelding-greenfield-v3.3`。
- 远端复核：`refs/heads/codex/cffwelding-greenfield-v3.3`与上述主Commit完全一致。
- 本段Git证据由后续报告Commit补录，不改写主Commit。
