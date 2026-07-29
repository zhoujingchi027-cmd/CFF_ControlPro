# Phase 9 Contact与步骤判据执行报告

## 执行结论

Phase 9 在不连接真实驱动、不激活配置、不下载工程和不登录 Runtime 的边界内，完成 Contact 检测、Force Decline Observer、Primary/Secondary、StepMin/StepMax、EndCause 和四步骤 Program Validation。源码提交为：

```text
35d564de70170579e5e718ac5a69caa088ba74cc
feat(process): add contact and proceeding criteria
```

本阶段由 `PRG_CffSequence` 唯一声明并调用三个算法 FB，但全部 `bEnable` 显式保持 `FALSE`。Phase 10 才实现 CFF 状态转换、Contact RequestId 事务、导纳使能和 External P/V/A/Direction 轨迹合成，因此 Phase 9 不会产生流程动作或物理运动命令。

## 实现范围

- `FB_ContactDetect` 实现 Force On/Off 回差、绝对 Axis/Sensor 窗口、捕获速度、连续 Debounce、候选/确认双位置锁存和单扫描参考点请求。
- `FB_ForceDeclineObserver` 实现 Arm、DeclineTo、Force 回差、负下降率、RPM/S_rel/轴速度窗口、连续 Debounce，以及确认时 Force、S_rel、RPM、Step Time 和导数冻结。
- `FB_StepProceedingCriterion` 按 Hard Cause → Secondary → Primary → StepMax 的顺序生成 EndCause、TooShort、NOK、Advance、Controlled Exit 和 Downward Inhibit。
- `FC_ValidateJoinProgram` 校验固定四步顺序、Primary/Secondary 枚举、StepMin/Max、Time/Decline 参数关系、累计 S_rel 单调、Program/Profile/Tool/Anvil ID、Return 参数和机器硬限值。
- `ST_ProcessReferenceCommand` 增加 Contact 确认时 Axis/Sensor 候选位置；`PRG_FastInputs` 在请求到达时校验并精确采用候选值，避免把 Debounce 后的当前值误作 Contact 零点。
- `ST_CffSequenceStatus` 发布三个算法的类型化诊断；固定报警槽 9 使用 `ALARM_CFF_CRITERION_FAULT`（3000），不与 Phase 7/8 报警槽混用。

## 故障与安全策略

三个算法拒绝非有限值和非法配置并锁存确定性故障编号。步骤判据的配置、数值或未知枚举故障统一锁存 `EndConfirmed=TRUE`、`NOK=TRUE`、`AdvanceRequested=FALSE`、`ControlledExitRequested=TRUE` 和 `DownwardMotionInhibited=TRUE`，避免 Phase 10 使能后出现 fail-open。

Force Decline 候选只能由 `DeclineTo + Hysteresis` 释放；任何下降率、RPM、S_rel 或捕获速度连续条件中断都会清零 Debounce，但不会错误绕过 Force 回差。确认后外层 `NOT bConfirmed` 守卫冻结所有导数、候选、Debounce 和锁存值。

Program Validation 只接受 `RETURN_MODE_LOCAL/REFERENCE` 和 `PROGRAM_VALID/ACTIVE`，拒绝缺失关键 ID、非有限或越界回程速度/开口，以及任何未知 Primary/Secondary 枚举。

## 测试驱动和审查

`scripts/Test-Phase9ContactAndCriterion.ps1` 先建立 RED，再验证对象唯一性、接口字段、编译清单、算法边界、故障安全出口、候选回差、确认冻结、Program Validation、Phase 10 禁区和报告闸门。离线参考向量覆盖 Contact 回差/去抖/单脉冲、Decline Arm/负下降率/去抖、StepMin、Secondary 向下抑制、StepMax 和 Program 单调边界。

代码与安全审查发现的故障 fail-open、Contact 候选位置传递、Return 参数校验、Decline 导数冻结、Force 回差和未知枚举问题均已按 RED→GREEN 修复。针对修复后的安全控制流再次复核，未保留 Critical、Important 或 Minor 安全问题。

这些 PowerShell 向量是 Structured Text 契约的离线参考，不是 TwinCAT Runtime 单元测试，也不证明真实 2 ms 周期、传感器噪声或机械响应。

## 构建证据

```text
Starting TwinCAT XAE Shell build: TcXaeShell.DTE.15.0
Building project 'CFFwelding_System\CFFwelding_System.tsproj' with 'Release|TwinCAT RT (x64)'.
CFFwelding XAE build: PASSED
Configuration: Release|TwinCAT RT (x64)
LastBuildInfo: 0
```

构建环境为 TwinCAT `3.1.4024.64`、TcXaeShell DTE 15.0、`Release|TwinCAT RT (x64)`。三个 Phase 9 算法 FB 均不访问 `AXIS_REF`、MC、GVL、字符串或其他 PROGRAM 局部变量。

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
Phase 9 contact and criterion test: PASSED
TwinCAT XAE Release Build: PASSED
LastBuildInfo: 0
TwinCAT XML parse: PASSED (145 files)
Phase 9 PowerShell ASCII check: PASSED
git diff --check: PASSED
```

## 未完成边界

以下事项保留给 Phase 10 或现场调试：

- CFF 正式状态转换、每步骤进入/退出和 Reset 生命周期接线；
- Contact RequestId 写事务与导纳 Enable/Profile Transfer；
- 连续 External P/V/A/Direction 轨迹合成及退出序列；
- Runtime 多扫描测试、真实 I/O/PDO、传感器标定和驱动关联；
- 2 ms 周期抖动、真实轴受控停止、机械方向和工艺参数验证；
- Safety 功能、过程能力和 Production Ready 资格。

本阶段未扫描设备、未激活配置、未下载、未登录 Runtime、未使能或移动物理轴。
