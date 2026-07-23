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
| `fbContactDebounce` | `FB_Debounce` | `PRG_CffSequence` | `PRG_CffSequence.VAR` | Contact候选条件 | Contact确认条件 | 新循环或Reset复位 |
| `fbStepCriterion` | `FB_StepProceedingCriterion` | `PRG_CffSequence` | `PRG_CffSequence.VAR` | `ST_StepCriterionInput` | `ST_StepCriterionOutput` | 每步骤进入时复位 |
| `fbForceDecline` | `FB_ForceDeclineObserver` | `PRG_CffSequence` | `PRG_CffSequence.VAR` | Force、dForce/dt、RPM、S_rel窗口 | Decline Arm/Confirm和锁存结果 | 每个Decline步骤进入时复位 |
| `fbZAxisArbiter` | `FB_AxisCommandArbiter` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | 初始化、维护、手动、自动和流程命令 | 唯一Z轴Owner与`ST_ZAxisCommand` | Owner释放、Stop或Reset时复位 |
| `fbZAxisNc` | `FB_ZAxisNcAdapter` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | 标准Z轴命令、Z轴`AXIS_REF` | `ST_ZAxisStatus` | 轴Reset或Owner释放时复位 |
| `fbZExtSetpoint` | `FB_ZAxisExtSetpointAdapter` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | `ST_ZExtSetpointCommand`、Z轴`AXIS_REF` | `ST_ZExtSetpointStatus` | Disable完成、轴Reset或Owner释放时复位 |
| `fbRAxisNc` | `FB_RAxisNcAdapter` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | `ST_RAxisCommand`、R轴`AXIS_REF` | `ST_RAxisStatus` | 轴Reset或Owner释放时复位 |
| `fbZForceAdmittance` | `FB_ZForceAdmittance` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | `ST_ZForceControlInput` | `ST_ZForceControlOutput` | Contact前、步骤结束、Stop或Reset时复位积分项 |
| `fbForceSetpointRamp` | `FB_SetpointRamp` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | 当前和下一Force Profile | 无扰力目标 | 新循环或硬Fault时复位 |
| `fbRSpeedRamp` | `FB_SetpointRamp` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | 当前和下一R轴Profile | 无扰RPM目标 | 新循环或硬Fault时复位 |
| `fbZProfileSwitch` | `FB_BumplessProfileSwitch` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | 步骤切换和Profile | 连续的控制参数 | 新循环或Reset时复位 |
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

## Phase 5核对

- `PRG_FastInputs`已按本矩阵唯一声明力滤波数组、力/位移有效性、位移滤波和Collision去抖实例；其他PROGRAM没有重复声明。
- 当前不存在`GVL_Instance`。
- 其余计划实例仍处于“已分配Owner、尚未声明”状态。
- 轴Adapter是未来唯一允许使用`VAR_IN_OUT AXIS_REF`的FB；算法FB不得访问`AXIS_REF`。
