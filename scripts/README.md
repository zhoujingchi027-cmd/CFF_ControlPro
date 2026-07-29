# scripts

只允许放置：

- 环境检测；
- 编码检查；
- XML格式检查；
- 构建调用；
- Git隔离检查；
- 对象目录审查。

不得生成仿真工艺、虚拟传感器或自动施力程序。

所有XAE Automation脚本必须保持非交互和可审查，不得扫描设备、
关联真实硬件、激活配置、下载工程或启动/重启TwinCAT Runtime。

## 已保留的验证工具

Phase 0～6已经形成真实Build和静态检查证据，因此保留对应的工程创建、
离线NC内部关联、任务同步、Build和回归测试脚本。V3.7升级不得删除这些
历史工具或用空模板覆盖已经生成的执行报告。

当前回归顺序：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase1Project.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase2Architecture.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase3DataAndBindings.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase4Utilities.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase5SensorProcessing.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase6MotionAdapters.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase7ExternalSetpoint.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase8ForceAdmittance.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase9ContactAndCriterion.ps1
```

Phase 7/8/9新增External Setpoint、导纳力控以及Contact/Criterion契约测试。每个Phase必须先运行
本Phase静态测试和全部既有回归测试，再运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1
```

所有真实硬件映射、驱动关联、External POC和Production Ready仍由用户后期
人工完成；任何脚本都不得把未确认状态强制为TRUE。
