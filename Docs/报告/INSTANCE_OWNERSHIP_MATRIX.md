# CFFwelding Instance Ownership Matrix

## 规则

- 每个FB实例只允许声明一次。
- 默认声明在唯一Owner PROGRAM的`VAR`区。
- Phase 4已创建通用FB类型，但业务实例仍只在对应后续Phase按本矩阵声明；当前PROGRAM中没有提前实例化对象。
- 下表是后续Phase必须遵守的唯一声明位置；实现对应FB时才能加入实例声明。
- 每个实际实例声明前必须使用中文块注释说明用途、任务、Owner、输入、输出和Reset/生命周期。
- 禁止PROGRAM读取其他PROGRAM的局部实例或内部变量。
- 当前不需要`GVL_Instance`；若未来确需跨PROGRAM共享，必须先更新本矩阵并说明原因。
- 本文保留Phase 4至Phase 9的阶段性核对记录；当前实现状态以末尾“Phase 10最终源码核对”为准。
- Phase 10核对基线为源码提交`0d9f190b1d31f00a5d83069d5b4e122be17c5e61`，只说明源码所有权和离线接口，不把Build、TMC、ADS符号或静态测试解释为Runtime、真实驱动或工艺资格证据。

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
| `fbZExtSetpoint`（Phase 7计划名）；`fbZAxisExtSetpointAdapter`（Phase 10源码名） | `FB_ZAxisExtSetpointAdapter` | `PRG_FastAxisControl` | `PRG_FastAxisControl.VAR` | `ST_ZExtSetpointCommand`、配置、Owner授予、Z轴`AXIS_REF` | `ST_ZExtSetpointStatus` | 完整Disable、附加Feed和Post-disable hold后才释放Owner；Reset按状态清错或重试Disable |
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

## Phase 10最终源码核对

本节覆盖上文“尚未声明”“保持FALSE”和“保留给Phase 10”等历史阶段性描述。`Task_CffFast`的实际调用顺序为`PRG_FastInputs`、`PRG_CffSequence`、`PRG_FastAxisControl`、`PRG_FastMonitoring`；前三者已经形成Fast侧消费者接线，`PRG_FastMonitoring`仍为未来监控骨架。

### 实际FB实例与生命周期

| 实际实例 | 唯一Owner/声明位置 | 实际输入与输出 | Phase 10生命周期 |
|---|---|---|---|
| `aFbForceChannelFilter`、`fbForceSignalValidity`、`fbDisplacementFilter`、`fbDisplacementSignalValidity`、`fbCollisionDebounce` | `PRG_FastInputs.VAR` | 读取类型化IO、绑定、标定和传感器配置；写`GVL_Process.stActual`及`GVL_Status.stFast.stProcess` | 未映射、标定或配置无效时Fail Closed复位；不伪造有效值 |
| `fbContactDetect` | `PRG_CffSequence.VAR` | `ST_ContactDetectInput` → `ST_ContactDetectOutput` | 仅`CFF_CONTACT_SEARCH`使能；安全终态Reset清除；确认时只生成一次参考点锁存事务 |
| `fbForceDecline` | `PRG_CffSequence.VAR` | `ST_ForceDeclineInput` → `ST_ForceDeclineOutput` | Step1至Step3过程态按Force Decline主判据使能；每步Entry复位 |
| `fbStepCriterion` | `PRG_CffSequence.VAR` | `ST_StepCriterionInput` → `ST_StepCriterionOutput` | Step1至Step3过程态及Step4 Brake/Hold使能；每步Entry复位；四个结果槽各最多写一次 |
| `fbZAxisArbiter` | `PRG_FastAxisControl.VAR` | Sequence/普通Z候选及Fault Stop → 唯一`ST_ZAxisCommand`和`E_ZCommandOwner` | Fault Stop最高优先级；Force Process Owner只有在Sequence退出意图和External Adapter的`bReleaseOwner`同时成立后才可转交 |
| `fbForceSetpointRamp` | `PRG_FastAxisControl.VAR` | 实际Force、Sequence目标、步骤斜率与冻结Profile上限 → 连续Force目标 | 只在相关Fast快照、Force请求和传感器链有效时运行；安全终态Reset清除 |
| `fbZProfileSwitch` | `PRG_FastAxisControl.VAR` | Sequence Profile Transfer、冻结Profile和切换速度 → 无扰积分预置 | Contact接受、步骤Entry或新冻结快照触发一次；错误锁存到安全终态Reset |
| `fbZForceAdmittance` | `PRG_FastAxisControl.VAR` | Force/S_rel、冻结Profile/限值和无扰预置 → Z速度目标与诊断 | 不访问轴或MC；健康受控卸载仍可运行，传感器/轴/External失效时Fail Closed |
| `fbZExternalTrajectory` | `PRG_FastAxisControl.VAR` | Adapter已接受P/V/A/Direction、Feed Counter、Sequence速度目标和冻结限值 → 连续轨迹包 | 只由新的accepted Feed推进；实现零速、旧方向保持、Direction=0、新方向预置和恢复；仅安全终态Reset |
| `fbRSpeedRamp` | `PRG_FastAxisControl.VAR` | 实际RPM和一次Adapter-facing R事务 → 软件诊断包络 | 每个新Adapter事务从实际RPM初始化；稳定扫描不生成新的MC事务；安全终态Reset |
| `fbZAxisNc` | `PRG_FastAxisControl.VAR` | Arbiter选出的标准Z命令和`GVL_IO.Z_axis` | 标准Z轴MC和`AXIS_REF`唯一边界；External占用时冻结标准命令事务 |
| `fbZAxisExtSetpointAdapter` | `PRG_FastAxisControl.VAR` | `ST_ZExtSetpointCommand`、冻结配置、Owner和`GVL_IO.Z_axis` | External Enable/Feed/Disable唯一API Owner；发布accepted P/V/A/Direction与Counter；Disabled确认、附加Feed和Post-disable hold完成后才发布`bReleaseOwner` |
| `fbRAxisNc` | `PRG_FastAxisControl.VAR` | 仲裁后的R命令和`GVL_IO.R_axis` | R轴MC和`AXIS_REF`唯一边界；接受独立Adapter事务号并发布实际RPM/状态 |

`FB_ZExternalTrajectory`、`FB_ZForceAdmittance`、`FB_BumplessProfileSwitch`、`FB_ContactDetect`、`FB_ForceDeclineObserver`和`FB_StepProceedingCriterion`均保持纯算法边界，不访问GVL、`AXIS_REF`或MC。全工程中只有`FB_ZAxisNcAdapter`、`FB_ZAxisExtSetpointAdapter`和`FB_RAxisNcAdapter`持有`AXIS_REF`并调用轴MC接口。

### PROGRAM/GVL唯一Writer与读取者

| 共享合同 | 唯一Writer | 主要Reader/确认者 | 实际握手 |
|---|---|---|---|
| `GVL_FastInternal.stAcceptedCommand` | `PRG_FastInputs` | `PRG_CffSequence`、`PRG_FastAxisControl` | 只在外层`ST_FastCommand.nRequestId`按半范围规则更新且复制前后ID稳定时接受完整包；FastAxis把接受号发布到`GVL_Status.stFast.nAcceptedRequestId` |
| `GVL_Status.stFast.stSequence`，含`stMotionIntent`和`stFastConfigSnapshot` | `PRG_CffSequence` | 同一扫描后执行的`PRG_FastAxisControl`、后续Main/ADS诊断层 | Start去重后形成局部周期快照；Precheck通过才发布相关`nSequenceCommandId`和`bValid=TRUE`；FastAxis只消费与`nAcceptedCommandId`一致的同一份快照 |
| `GVL_Status.stFast.stZAxis`、`stZExtSetpoint`、`stZExternalTrajectory`、`stZForceControl`、`stRAxis`、R/Force Ramp状态及Sequence Z/R接受号 | `PRG_FastAxisControl` | 下一扫描`PRG_CffSequence`、后续Main/ADS诊断层 | Sequence Z/R源ID经“命令源+源ID”转换为独立Adapter ID；Adapter接受后才回写`udiAcceptedSequenceZCommandId/udiAcceptedSequenceRCommandId` |
| `GVL_Command.stProcessReference` | `PRG_CffSequence` | `PRG_FastInputs` | 五个payload字段先写、`udiContactReferenceRequestId`最后写并保持；Precheck先做Reset事务，Contact确认再做Latch事务 |
| `GVL_Process.stActual.udiContactReferenceAcceptedId`及参考点有效状态 | `PRG_FastInputs` | `PRG_CffSequence` | FastInputs按新RequestId处理一次；Sequence要求精确Ack ID且`bContactReferenceValid=TRUE`后才进入Step1 |
| `GVL_Process.astStepCriterion[1..4]` | `PRG_CffSequence` | 当前Evaluate；未来`FB_ResultAnalyzer` | 每个步骤结束时构造完整结果后写唯一槽位，guard阻止后续Reset或步骤切换覆盖 |
| `GVL_Alarm.astRequests[7]` | `PRG_FastAxisControl` | 报警汇总层 | External Adapter或External轨迹故障；TextId 2200、SourceId 7 |
| `GVL_Alarm.astRequests[8]` | `PRG_FastAxisControl` | 报警汇总层 | Force Admittance或Profile Switch故障；TextId 2500、SourceId 8 |
| `GVL_Alarm.astRequests[9]` | `PRG_CffSequence` | 报警汇总层 | Contact、Force Decline或Step Criterion算法故障；TextId 3000、SourceId 9 |
| `GVL_Alarm.astRequests[10]` | `PRG_CffSequence` | 报警汇总层 | CFF Sequence首故障锁存；TextId 3200、SourceId 10 |

`GVL_FastInternal`当前只有`stAcceptedCommand`，不保存运动意图或冻结配置；这两类合同实际嵌套在`GVL_Status.stFast.stSequence`中，由`PRG_CffSequence`唯一写入。

### 仍为未来Owner的边界

- `PRG_CommandDispatcher`仍为空实现骨架，不产生Start/Stop/Abort/Reset脉冲，也没有实现`GVL_Command.stFast`的生产级payload/RequestId保持和Ack合同；它只是未来Writer归属。
- `PRG_ProgramManager`仍为空实现骨架，不创建/激活Program，也没有实现`GVL_Program.stCycleSnapshot`的生产级Revision保持合同；它只是未来Writer归属。
- `GVL_Status.bProductionReady`在GVL中初始化为`FALSE`，当前源码没有任何赋值语句把它置为`TRUE`；Sequence Precheck明确要求它为真。因此Phase 10只完成Fast侧消费者，未形成端到端生产启动链。
- `fbForceTorqueFeedForward`、`fbEnergy`、`fbForceStatistics`、`fbMaterialInterface`、`fbProcessWindow`、`fbCurveRecorder`和`fbResultAnalyzer`均没有实际实例；Torque闭环/前馈、Power/Energy、Material Observer、Process Window、Curve Recorder和最终Result Analyzer继续属于未来阶段。
- 当前Collision仅消费`bCollisionValid AND bCollisionSensorActive`的临时类型化路径。Phase 11B要求的Collision IO删除以及最终外部位移/NC双位置逻辑尚未实施，不能把当前路径描述为最终碰撞算法。
- 本矩阵未记录任何Runtime、ADS读写、真实驱动、任务同步/抖动、硬件映射、标定或工艺资格验证；这些仍须在后续受控环境完成。
