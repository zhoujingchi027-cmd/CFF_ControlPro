# Phase 8 Z轴导纳力控执行报告

## 执行结论

Phase 8 在不连接真实驱动、不激活配置、不下载工程和不登录 Runtime 的边界内，完成 Z 轴导纳 PI、力设定斜坡、Anti-windup、S_rel 制动限速、硬边界、Profile 无扰切换和 FastTask 唯一实例接线。源码提交为：

```text
2b9a470e215962d7696cae4036224284f36f66ce
feat(control): add Phase 8 force admittance
```

本阶段只把 `ST_ZForceControlOutput` 发布到 `GVL_Status.stFast.stZForceControl`，没有覆盖 Phase 7 External P/V/A/Direction。正式 Contact、步骤判据、CFF Sequence 和轨迹合成属于 Phase 9/10，当前默认状态不会使能力控。

## 实现范围

- `FB_BumplessProfileSwitch`根据切换前速度、速度前馈、比例项和目标/实际力计算积分预置；输入或中间值非有限时锁存错误，只有显式 Reset 清除。
- `FB_ZForceAdmittance`实现速度前馈、PI、Back-calculation Anti-windup、Profile/机器速度限幅、有效加速度、S_rel 制动包络、硬力/硬行程/Collision 边界和输出诊断。
- `PRG_FastAxisControl`唯一声明 `fbForceSetpointRamp`、`fbZProfileSwitch`和`fbZForceAdmittance`，使用 `ForceControl`而不是 `ForceDisplay`，并要求位移、Contact参考点和 Axis/Sensor 一致性全部有效。
- Force Profile、目标/硬 S_rel 和机器 Z/Force 限值在无扰提交时形成快照；相同 Revision 内容变化或未授权限值变化会锁存故障，Reset 后必须重新提交。
- Sequence `Error`或`Aborted`显式禁止力控；Sequence/轴 Reset 同步重置设定斜坡、控制器和 Revision 跟踪。
- 固定报警槽 8 使用 `ALARM_FORCE_CONTROL_FAULT`（2500）；Phase 7 External 报警继续独立使用槽 7。

## 算法和故障策略

算法顺序固定为：Profile 速度边界 → 机器速度边界 → Profile/机器较小有效加速度 → S_rel 制动包络 → 硬力/硬行程边界 → Collision 边界 → 加速度限幅 → 双向最终包络。

当 Rate Limit 后的速度无法满足当前双向包络时，控制器锁存 `16#0000800C`，同一扫描发布零速度、`bActive=FALSE`和`bFault=TRUE`。未饱和速度、制动速度、Rate Limit、积分导数和积分候选均逐级检查有限性；所有计算期故障出口保持零速度和 Inactive。切换速度必须位于候选 Profile 与机器共同允许的双向范围内。

## 测试驱动和审查

`scripts/Test-Phase8ForceAdmittance.ps1`先建立准确 RED，再验证对象、字段、唯一实例、编译清单、限幅顺序、故障锁存、机器限值快照、Reset 生命周期、External 写边界和报告闸门。离线数值向量覆盖 PI、Anti-windup、机器加速度小于 Profile、零剩余行程、Reset 后重提交、未授权限值放宽、同 Revision 内容变化、包络故障零输出、越界切换速度及非有限故障锁存。

这些 PowerShell 数值向量是对 ST 数学和状态契约的离线参考，不是 TwinCAT Runtime 单元测试，也不证明真实周期抖动或机械响应。两轮独立代码/安全复核发现的问题均已按 RED→GREEN 修复，最终复核为无 Critical、无 Important、无 Minor。

## 构建证据

```text
Starting TwinCAT XAE Shell build: TcXaeShell.DTE.15.0
Building project 'CFFwelding_System\CFFwelding_System.tsproj' with 'Release|TwinCAT RT (x64)'.
CFFwelding XAE build: PASSED
Configuration: Release|TwinCAT RT (x64)
LastBuildInfo: 0
```

构建环境为 TwinCAT `3.1.4024.64`、TcXaeShell DTE 15.0、`Release|TwinCAT RT (x64)`。两个 Phase 8 算法 FB 均不访问 `AXIS_REF`、MC、GVL 或其他 PROGRAM 局部变量。

## 最终复验

报告创建后再次执行的结果为：

```text
Phase 1 acceptance test: PASSED
Phase 2 architecture test: PASSED
Phase 3 data and binding test: PASSED
Phase 4 utility test: PASSED
Phase 5 sensor processing test: PASSED
Phase 6 motion adapter test: PASSED
Phase 7 external setpoint test: PASSED
Phase 8 force admittance test: PASSED
TwinCAT XAE Release Build: PASSED
LastBuildInfo: 0
Project XML parse: PASSED (143 files)
git diff --check: PASSED
```

## 未完成边界

以下事项不能由本阶段静态测试或 Build 替代：

- Phase 9 Contact、步骤判据和 CFF Sequence；
- Phase 10 将导纳速度合成为连续 External P/V/A/Direction；
- 真实 I/O/PDO、传感器标定、驱动关联和 External Setpoint POC；
- Runtime 多扫描测试、2 ms 周期抖动测量、真实轴受控停止和机械方向确认；
- 工艺参数整定、安全功能验证、过程能力和 Production Ready 资格。

本阶段未扫描设备、未激活配置、未下载、未登录 Runtime、未使能或移动物理轴。
