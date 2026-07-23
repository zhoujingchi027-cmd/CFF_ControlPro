# scripts

只允许放置：

- 环境检测；
- 按分阶段任务书执行的XAE Automation工程与对象创建；
- 编码检查；
- XML格式检查；
- 构建调用；
- Git隔离检查；
- 对象目录审查。

不得生成仿真工艺、虚拟传感器或自动施力程序。

所有XAE Automation脚本必须保持非交互和可审查，不得扫描设备、关联真实硬件、激活配置、下载工程或启动/重启TwinCAT Runtime。

## Phase 3 离线 NC 执行顺序

以下脚本只操作新工程内部对象，不创建或扫描真实设备：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Configure-CffweldingPhase3OfflineNc.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Sync-CffweldingPhase3FastTask.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Link-CffweldingPhase3AxisRefs.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase3DataAndBindings.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1
```

- `Configure-CffweldingPhase3OfflineNc.ps1`：幂等创建 `NC_Cff SAF`、`Z_Axis_NC` 和 `R_Axis_NC`，拒绝已有真实 I/O 节点或 Safety 配置。
- `Sync-CffweldingPhase3FastTask.ps1`：读取实际 SAF 周期，并验证/同步系统与 PLC Fast 任务周期。
- `Link-CffweldingPhase3AxisRefs.ps1`：仅建立 `GVL_IO.Z_axis/R_axis` 与两个离线 NC 轴的四条内部整结构链接。
- `Test-Phase3DataAndBindings.ps1`：检查数据对象、任务周期、内部映射、空硬件边界和人工交付清单。

链接脚本依赖最新 TMC 过程映像，因此第一次执行应先 Build；最终必须在链接后再次 Build。所有三个配置/同步/链接脚本均支持幂等复跑。

## Phase 4 通用算法验收

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase4Utilities.ps1
```

该脚本检查14个纯计算FC和6个通用FB的唯一性、PLC编译清单、中文接口/算法注释、复位与边界接口，并拒绝这些通用对象访问`GVL`、`AXIS_REF`或任何`MC_*`对象。

## Phase 5 传感器处理验收

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase5SensorProcessing.ps1
```

该脚本检查EP3174/位移/Collision占位及诊断、四路Force、Contact参考点事务、累计`SRelSensor/SRelAxis`和差值契约，并确认未创建真实I/O配置、未强制任何映射或Production Ready为真。
