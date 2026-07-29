# CFFwelding Instance Ownership Matrix

## 规则

- 每个FB实例只允许声明一次。
- 默认声明在唯一Owner PROGRAM的`VAR`区。
- Phase 4已创建通用FB类型，但业务实例仍只在对应后续Phase按本矩阵声明；当前PROGRAM中没有提前实例化对象。
- 下表是后续Phase必须遵守的唯一声明位置；实现对应FB时才能加入实例声明。
- 每个实际实例声明前必须使用中文块注释说明用途、任务、Owner、输入、输出和Reset/生命周期。
- 禁止PROGRAM读取其他PROGRAM的局部实例或内部变量。
- 当前不需要`GVL_Instance`；若未来确需跨PROGRAM共享，必须先更新本矩阵并说明原因。

## Fast Task实例

| 计划实例名 | FB类型 | 唯一Owner | 声明位置 | 输入来源 | 输出去向 | Reset/生命周期 |
|---|---|---|---|---|---|---|
| `aFbForceChannelFilter` | `ARRAY[1..4] OF FB_LowPassFilter` | `PRG_FastInputs` | `PRG_FastInputs.VAR` | 四通道力原始值、实际周期 | 四通道滤波值 | Reset或标定切换时复位 |
| `fbDisplacementFilter` | `FB_LowPassFilter` | `PRG_FastInputs` | `PRG_FastInputs.VAR` | 外部位移原始值、实际周期 | 工艺位移滤波值 | Reset或标定切换时复位 |
| `fbForceSignalValidity` | `FB_SignalValidity` | `PRG_FastInputs` | `PRG_FastInputs.VAR` | 四通道工程量与诊断 | 力测量有效状态 | Reset或诊断恢复后重建窗口 |
| `fbDisplacementSignalValidity` | `FB_SignalValidity` | `PRG_FastInputs` | `PRG_FastInputs.VAR` | 位移工程量与诊断 | 位移有效状态 | Reset或诊断恢复后重建窗口 |
| `fbCollisionDebounce` | `FB_Debounce` | `PRG_FastInputs` | `PRG_FastInputs.VAR` | Collision Reference Sensor占位输入与人工映射状态 | 稳定Collision传感器诊断 | 输入未映射或Reset时复位 |
| `fbContactDetect` | `FB_ContactDetect` | `PRG_CffSequence` | `PRG_CffSequence.VAR` | `ST_ContactDetectInput` | `ST_ContactDetectOutput` | 新循环或Reset复位；Contact只确认一次 |
| `fbStepCriterion` | `FB_StepProceedingCriterion` | `PRG_CffSequence` | `PRG_CffSequence.VAR` | `ST_StepCriterionInput` | `ST_StepCriterionOutput` | 每步骤进入时复位 |
| `fbForceDecline` | `FB_ForceDeclineObserver` | `PRG_CffSequence` | `PRG_CffSequence.VAR` | Force、dForce/dt、RPM、S_rel窗口 | Decline Arm/Confirm和锁存结果 | 每个Decline步骤进入时复位 |
| `fbZAxisArbiter` | `FB_AxisCommandArbiter` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | 初始化、维护、手动、自动和流程命令 | 唯一Z轴Owner与`ST_ZAxisCommand` | Owner释放、Stop或Reset时复位 |
| `fbZAxisNc` | `FB_ZAxisNcAdapter` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | 标准Z轴命令、Z轴`AXIS_REF` | `ST_ZAxisStatus` | 轴Reset或Owner释放时复位 |
| `fbZExtSetpoint` | `FB_ZAxisExtSetpointAdapter` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | `ST_ZExtSetpointCommand`、配置、Owner授予、Z轴`AXIS_REF` | `ST_ZExtSetpointStatus` | 完整Disable、附加Feed和Post-disable hold后才释放Owner；Reset按状态清错或重试Disable |
| `fbRAxisNc` | `FB_RAxisNcAdapter` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | `ST_RAxisCommand`、R轴`AXIS_REF` | `ST_RAxisStatus` | 轴Reset或Owner释放时复位 |
| `fbZForceAdmittance` | `FB_ZForceAdmittance` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | 类型化输入、Profile/机器限值、Ramp目标和积分预置 | `ST_ZForceControlOutput`并发布到Fast状态 | Disable清动态状态；显式轴/Sequence Reset清故障；重新使能必须重提Profile |
| `fbForceSetpointRamp` | `FB_SetpointRamp` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | ForceControl实际值、Sequence目标和Profile斜率 | 连续目标力 | 力控禁止、Sequence Reset或轴Reset时重置到实际力 |
| `fbRSpeedRamp` | `FB_SetpointRamp` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | 当前和下一R轴Profile | 无扰RPM目标 | 新循环或硬Fault时复位 |
| `fbZProfileSwitch` | `FB_BumplessProfileSwitch` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | Sequence切换脉冲/Revision变化、切换速度和候选Profile | 单扫描积分预置及Accepted | 错误锁存；显式Sequence/轴Reset清除 |
| `fbForceTorqueFeedForward` | `FB_ForceTorqueFeedForward` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | 通过验证的材料/过程输入 | 可选前馈项 | 默认关闭；Reset时清零 |
| `fbEnergy` | `FB_EnergyCalculator` | `PRG_FastMonitoring` | `PRG_FastMonitoring.VAR` | RPM、Torque、实际周期 | Power和Energy | Contact或新循环时复位 |
| `fbForceStatistics` | `FB_ForceStepStatistics` | `PRG_FastMonitoring` | `PRG_FastMonitoring.VAR` | Force与步骤窗口 | Min/Max/Mean等步骤统计 | 每步骤进入时复位 |
| `fbMaterialInterface` | `FB_MaterialInterfaceObserver` | `PRG_FastMonitoring` | `PRG_FastMonitoring.VAR` | Force/Torque/S_rel特征 | 观察量和诊断 | 新循环时复位 |
| `fbProcessWindow` | `FB_ProcessWindowMonitor` | `PRG_FastMonitoring` | `PRG_FastMonitoring.VAR` | 当前过程量与Profile窗口 | 窗口NOK请求 | 新循环或步骤进入时复位 |
| `fbCurveRecorder` | `FB_CurveRecorder` | `PRG_FastMonitoring` | `PRG_FastMonitoring.VAR` | 快速采样快照 | 双缓冲曲线块 | 新循环开始时切换缓冲 |
| `fbResultAnalyzer` | `FB_ResultAnalyzer` | `PRG_FastMonitoring` | `PRG_FastMonitoring.VAR` | 步骤锁存值和过程特征 | 类型化Cycle Result | 新循环开始时复位 |

## Main Task实例

| 计划实例名 | FB类型 | 唯一Owner | 声明位置 | 输入来源 | 输出去向 | Reset/生命周期 |
|---|---|---|---|---|---|---|
| `fbHmiCommandHandshake` | `FB_CommandHandshake` | `PRG_CommandDispatcher` | `PRG_CommandDispatcher.VAR` | HMI命令邮箱 | Ack、ExecutionState、RejectReason | Session或CommandId变化时推进 |
| `fbRobotCommandHandshake` | `FB_CommandHandshake` | `PRG_CommandDispatcher` | `PRG_CommandDispatcher.VAR` | Robot命令邮箱 | Ack、ExecutionState、RejectReason | Robot事务结束或Reset时推进 |
| `fbCollisionReferenceTeach` | `FB_CollisionReferenceTeach` | `PRG_ServiceCalibration` | `PRG_ServiceCalibration.VAR` | Maintenance标定命令与有效传感器 | Collision参考结果 | 每次Teach事务进入时复位 |
| `fbForceCalibration` | `FB_ForceMeasurementCalibration` | `PRG_ServiceCalibration` | `PRG_ServiceCalibration.VAR` | 四通道原始量和人工参考点 | 力标定候选值 | 每次标定事务进入时复位 |
| `fbDisplacementCalibration` | `FB_DisplacementCalibration` | `PRG_ServiceCalibration` | `PRG_ServiceCalibration.VAR` | 位移原始量和人工参考点 | 位移标定候选值 | 每次标定事务进入时复位 |
| `fbExtSetpointCommissioning` | `FB_ExtSetpointCommissioning` | `PRG_ServiceCalibration` | `PRG_ServiceCalibration.VAR` | Maintenance命令与轴状态 | 调试结果，不提供生产Ready | 每次调试事务进入时复位 |
| `fbRAxisCalibration` | `FB_RAxisCalibration` | `PRG_ServiceCalibration` | `PRG_ServiceCalibration.VAR` | R轴人工调试命令与状态 | R轴标定结果 | 每次标定事务进入时复位 |
| `fbMaintenanceHeartbeat` | `FB_Debounce` | `PRG_MaintenanceControl` | `PRG_MaintenanceControl.VAR` | ClientSessionId和Heartbeat | Hold-to-Run有效状态 | 超时、Session变化或模式退出时复位 |
| `fbAlarmLatch` | `FB_AlarmLatch` | `PRG_AlarmControl` | `PRG_AlarmControl.VAR` | 类型化报警请求 | 当前报警状态 | 仅在允许复位时清除 |

## 慢任务实例策略

`PRG_HmiAdsInterface`、`PRG_ResultTraceability`、`PRG_Statistics`和`PRG_Persistence`在Phase 2不声明FB实例。后续若引入队列、握手或持久化FB，必须先在本矩阵中分配唯一Owner，且不得把字符串、文件、数据库或ADS大数组搬运放入`Task_CffFast`。

## Phase 7核对

- `PRG_FastInputs`已按本矩阵唯一声明力滤波数组、力/位移有效性、位移滤波和Collision去抖实例；其他PROGRAM没有重复声明。
- `PRG_FastAxisControl`已唯一声明`fbZAxisArbiter`、`fbZAxisNc`、`fbZExtSetpoint`和`fbRAxisNc`；每个实例均有用途、任务、Owner、输入、输出和Reset/生命周期中文块注释。
- 当前不存在`GVL_Instance`。
- 除上述Phase 5/6实例外，其余计划实例仍处于“已分配Owner、尚未声明”状态。
- 只有`FB_ZAxisNcAdapter`、`FB_ZAxisExtSetpointAdapter`和`FB_RAxisNcAdapter`使用`VAR_IN_OUT AXIS_REF`；Owner仲裁、流程PROGRAM和算法FB均不访问轴引用。
- `fbZExtSetpoint`是External Enable/Feed/Disable API的唯一调用者；Force Process Owner在Adapter发布`bReleaseOwner`前保持占用，标准Z轴Adapter不会并发执行运动命令。

## Phase 8核对

- `PRG_FastAxisControl`新增并唯一声明`fbForceSetpointRamp`、`fbZProfileSwitch`和`fbZForceAdmittance`；其他PROGRAM没有重复实例。
- 两个Control算法FB不包含`AXIS_REF`、MC、GVL或跨PROGRAM局部访问；三个轴Adapter仍是轴引用和MC实例的唯一边界。
- Phase 8只发布`ST_ZForceControlOutput`，不写`ST_ZExtSetpointCommand`的P/V/A/Direction；轨迹合成保留给Phase 10。
- Profile、目标/硬S_rel和机器Z/Force限值只在成功无扰预置时提交；未授权变化、非有限值、越界切换速度或最终包络冲突均锁存故障并输出零。
- `PRG_CffSequence`尚未实现正式力控使能，且Sequence Error/Aborted会显式禁止控制链，因此Phase 8默认Inactive。

## Phase 9核对

- `PRG_CffSequence`新增并唯一声明`fbContactDetect`、`fbForceDecline`和`fbStepCriterion`；其他PROGRAM没有重复实例。
- Contact去抖和Force Decline去抖是对应算法FB的内部确定性状态，不再额外声明`fbContactDebounce`实例。
- 三个算法FB不包含`AXIS_REF`、MC、GVL、字符串或跨PROGRAM局部访问。
- Phase 9全部算法Enable显式为`FALSE`，只发布类型化诊断和固定报警槽9；不写Contact RequestId、Force Control Enable或External P/V/A/Direction。
- Contact候选时锁存的Axis/Sensor位置通过类型化参考点命令传递；事务编号和正式状态机接线保留给Phase 10。
