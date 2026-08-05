# CFFwelding Internal Interface Catalog

## 设计规则

- 所有标识符使用英文ASCII。
- 每个公开字段前使用独立行中文注释说明意义、单位或生命周期。
- Phase 3已将接口状态字段替换为显式赋值枚举；Phase 4通用对象继续只依赖类型化参数和返回值。
- PROGRAM之间不得访问彼此局部变量；后续通过GVL中的这些类型化契约交互。
- 算法输入由调用者完整赋值，输出由对应FB或PROGRAM唯一写入。
- 只有轴Adapter允许通过`VAR_IN_OUT AXIS_REF`访问轴；以下算法接口均不包含`AXIS_REF`。
- 本文保留Phase 3至Phase 9的阶段性说明；当前接口、Writer和握手状态以末尾“Phase 10最终接口核对”为准。
- Phase 10核对基线为源码提交`0d9f190b1d31f00a5d83069d5b4e122be17c5e61`。TMC字段只用于确认离线符号布局，不代表ADS在线读写、PLC Runtime或真实硬件验证。

## Force接口

### `ST_ZForceControlInput`

| 字段 | 类型 | 单位 | 语义 |
|---|---|---|---|
| `bEnable` | `BOOL` | - | 力控制使能请求 |
| `bReset` | `BOOL` | - | 清除算法内部状态 |
| `bOwnerGranted` | `BOOL` | - | Force Process Owner已授予 |
| `bExternalActive` | `BOOL` | - | Phase 7 External通道已确认Enabled |
| `bForceValid` | `BOOL` | - | ForceControl及目标斜坡有效 |
| `bRelativePositionValid` | `BOOL` | - | 位移、Contact参考点和Axis/Sensor一致性有效 |
| `bBumplessTransfer` | `BOOL` | - | 当前扫描要求无扰Profile提交 |
| `bHardForceActive` | `BOOL` | - | 上层硬力边界生效 |
| `bHardStrokeActive` | `BOOL` | - | 上层硬S_rel边界生效 |
| `bCollisionLimitActive` | `BOOL` | - | Collision边界生效 |
| `rForceSet_kN` | `LREAL` | kN | 当前步骤压向目标力 |
| `rForceActual_kN` | `LREAL` | kN | 低延迟压向实际力 |
| `rRelativePosition_mm` | `LREAL` | mm | Contact起累计S_rel，向下为正 |
| `rTargetRelativePosition_mm` | `LREAL` | mm | 当前Profile制动目标S_rel |
| `rHardMaximumRelativePosition_mm` | `LREAL` | mm | 当前Profile硬最大S_rel |
| `rTransferVelocity_mm_s` | `LREAL` | mm/s | Profile切换前的连续速度 |
| `rCycleTime_s` | `LREAL` | s | 实际算法调用周期 |

### `ST_ZForceControlOutput`

| 字段 | 类型 | 单位 | 语义 |
|---|---|---|---|
| `rVelocityCommand_mm_s` | `LREAL` | mm/s | 导纳控制Z速度命令，向下为正 |
| `rIntegralTerm_mm_s` | `LREAL` | mm/s | PI积分诊断值 |
| `rForceSetRamped_kN` | `LREAL` | kN | 通过有限性和范围检查的Ramp目标力 |
| `rForceError_kN` | `LREAL` | kN | Ramp目标与ForceControl之差 |
| `rUnsaturatedVelocity_mm_s` | `LREAL` | mm/s | 限幅前PI速度 |
| `rSaturatedVelocity_mm_s` | `LREAL` | mm/s | 速度、行程和加速度限幅后的诊断速度 |
| `rStrokeVelocityLimit_mm_s` | `LREAL` | mm/s | S_rel制动允许的最大向下速度 |
| `bActive` | `BOOL` | - | 算法正在计算 |
| `bLimited` | `BOOL` | - | 速度、位移、加速度或硬边界限幅 |
| `bAntiWindupFrozen` | `BOOL` | - | 当前扫描冻结积分 |
| `bHardLimitActive` | `BOOL` | - | 硬力、硬行程或Collision边界有效 |
| `bFault` | `BOOL` | - | 输入或算法诊断失败 |
| `nFaultId` | `UDINT` | - | 故障编号 |

## Z轴接口

### `ST_ZAxisCommand`

包含Enable、Reset、Stop、标准回零、绝对定位、速度运行和External Setpoint选择；位置使用`mm`，速度使用`mm/s`，加减速度使用`mm/s2`，Owner使用`E_ZCommandOwner`。

### `ST_ZAxisStatus`

发布Ready、Enabled、Homed、Moving、Standstill、Busy、Done、External Active、Error、ErrorId、AcceptedCommandId、ActiveOwner，以及Z轴实际位置`mm`和实际速度`mm/s`。真实驱动未关联时Ready、状态有效值和运动量保持无效/零，不得转换为生产Ready。

### `ST_ZExtSetpointCommand`

提供Reset/Enable/Feed/Disable生命周期请求和P/V/A/Direction设定值。方向只允许`-1/0/1`，位置、速度、加速度分别使用`mm`、`mm/s`、`mm/s2`。Phase 10增加`bPositiveMotionInhibit`；只有保持Adapter accepted位置和方向、同时把速度/加速度精确置零的硬安全包可使用该标志。直接`+1/-1`反向被拒绝并触发受控退出。

### `ST_ZExtSetpointStatus`

发布Enabled、Busy、Done、FeedAccepted、ReleaseOwner、Error、ErrorId、`E_ZExtSetpointState`生命周期状态和Feed周期计数。Phase 10增加`bAcceptedSetpointValid`及最后接受的`rAcceptedPosition_mm`、`rAcceptedVelocity_mm_s`、`rAcceptedAcceleration_mm_s2`、`nAcceptedDirection`。`ReleaseOwner`只在NC确认Disabled并完成附加Feed/Post-disable hold后成立。

### `ST_ZExtSetpointConfig`

发布配置有效位、Enable/Disable超时、静止速度阈值、位置连续性上限、速度步阶上限、Direction保持周期和Disable后保持周期。配置默认无效，必须由后续批准的调试流程写入经确认值；Phase 7没有伪造有效配置。

## R轴接口

### `ST_RAxisCommand`

提供Enable、Reset、Stop、速度运行、目标`rpm`和`rpm/s`加减速。首版不提供外部扭矩闭环命令。

### `ST_RAxisStatus`

发布Ready、Enabled、Moving、Standstill、Busy、Done、Error、ErrorId、AcceptedCommandId、实际`rpm`和仅用于监控的实际转矩`Nm`。

## Contact接口

### `ST_ContactDetectInput`

输入Enable/Reset、实际力与力阈值`kN`、Z位置`mm`、Z速度`mm/s`和信号有效性。

### `ST_ContactDetectOutput`

发布Contact确认、确认时Force/Position锁存值、唯一一次S_rel清零请求、Fault和FaultId。

## 步骤准则接口

### `ST_StepCriterionInput`

输入第一准则、S_rel与目标距离、步骤时间与目标时间、实际Force、DeclineTo、ArmForce、`dForce/dt`、Secondary S_rel硬限制和窗口有效性。第一准则数值后续替换为`E_StepPrimaryCriterion`。

### `ST_StepCriterionOutput`

发布Decline Armed、Primary Met、Secondary Limit、End Confirmed、EndCause，以及结束时Force/S_rel/StepTime锁存值。EndCause后续替换为`E_StepEndCause`。

## CFF流程接口

### `ST_CffSequenceCommand`

输入Start/Stop/Abort/Reset单扫描内部脉冲、事务编号、ProgramId、JoiningPointId和生产权限。该结构不直接暴露给WPF写共享BOOL；外部命令必须先经过命令邮箱仲裁。

### `ST_CffSequenceStatus`

发布AcceptedCommandId、Busy、Done、Aborted、Error、ErrorId、类型化State/Step/SubPhase/EndCause，以及当前Force/RPM目标。Phase 8增加力控Enable、Profile Transfer、切换速度、目标/硬S_rel和硬力/硬行程/Collision边界请求；Phase 9增加Contact、Force Decline和Step Criterion嵌套诊断。截至Phase 9，`PRG_CffSequence`仍为骨架，不会提前置位流程请求；Phase 10已由实际状态机取代该阶段性边界，并增加退出意图、步骤/合格保持时间、当前步骤力斜率、运动意图和同一Start事务的Fast冻结配置快照。

## Writer/Reader边界

| 接口 | 唯一写入者 | 主要读取者 |
|---|---|---|
| `ST_ZForceControlInput` | `PRG_FastAxisControl`调用准备区 | `FB_ZForceAdmittance` |
| `ST_ZForceControlOutput` | `FB_ZForceAdmittance` | `PRG_FastAxisControl`发布到`ST_FastStatus`；Phase 10轨迹合成读取 |
| `ST_ZExtSetpointCommand` | `PRG_FastAxisControl` | `FB_ZAxisExtSetpointAdapter` |
| `ST_ZExtSetpointStatus` | `FB_ZAxisExtSetpointAdapter` | `PRG_FastAxisControl`、状态发布层 |
| `ST_ZAxisCommand` | `FB_AxisCommandArbiter` | Z轴Adapter |
| `ST_ZAxisStatus` | Z轴Adapter | 流程、主状态和诊断发布层 |
| `ST_RAxisCommand` | `PRG_FastAxisControl`仲裁区 | `FB_RAxisNcAdapter` |
| `ST_RAxisStatus` | `FB_RAxisNcAdapter` | 流程、监控和诊断发布层 |
| `ST_ContactDetectInput` | `PRG_CffSequence`调用准备区 | `FB_ContactDetect` |
| `ST_ContactDetectOutput` | `FB_ContactDetect` | `PRG_CffSequence` |
| `ST_ForceDeclineInput` | `PRG_CffSequence`调用准备区 | `FB_ForceDeclineObserver` |
| `ST_ForceDeclineOutput` | `FB_ForceDeclineObserver` | `PRG_CffSequence` |
| `ST_StepCriterionInput` | `PRG_CffSequence`调用准备区 | `FB_StepProceedingCriterion` |
| `ST_StepCriterionOutput` | `FB_StepProceedingCriterion` | `PRG_CffSequence` |
| `ST_CffSequenceCommand` | 计划Writer为`PRG_CommandDispatcher`；当前该PROGRAM仍是骨架，尚无生产级Writer | `PRG_FastInputs`接受完整`ST_FastCommand`后由`PRG_CffSequence`读取 |
| `ST_CffSequenceStatus` | `PRG_CffSequence` | 同一扫描后执行的`PRG_FastAxisControl`、后续Main Task状态机和ADS快照层 |

## Phase 4纯计算FC

| FC | 输入/输出契约 | 无效或边界处理 |
|---|---|---|
| `FC_ClampLReal` | 数值与两个边界 → 限幅值 | 自动归一化传反的上下限 |
| `FC_ScaleLinear` | 原始/工程量程 → 线性换算值、`bValid` | 零跨度或非有限输入返回工程下端并撤销有效位 |
| `FC_LimitRate` | 当前值、目标、上下变化率、周期 → 连续值 | 非正周期、负速率或非有限输入保持当前值 |
| `FC_TrapezoidIntegrate` | 上次积分、相邻样本、周期 → 新积分 | 非正周期或非有限样本保持累计值 |
| `FC_RpmToRadPerSec` | rpm → rad/s | 保留方向符号 |
| `FC_CalcEnergyIncrement` | Torque、RPM、周期 → J增量、`bValid` | 工程值或周期无效时增量为零 |
| `FC_ConvertDirection` | 工程值、`+1/-1`方向 → 换向值、`bValid` | 非法方向返回零并撤销有效位 |
| `FC_IsFiniteLReal` | `LREAL` → `BOOL` | 拒绝NaN、无穷及超出工程有限上界的值 |
| `FC_Interpolate1D` | 两点与查询值 → 插值、`bValid` | 重合横坐标或非有限输入返回第一个纵坐标 |
| `FC_ValidateCalibration` | 有效位、Revision、Gain、Direction → `BOOL` | 任何必要条件缺失均拒绝 |
| `FC_ValidateJoinProgram` | 四步骤Program、Machine Limits → `BOOL` | 固定步骤顺序、判据、超时和机器硬限值逐项校验 |
| `FC_GetPrimaryEndCause` | Primary枚举 → EndCause枚举 | 未知枚举返回`STEP_END_NONE` |
| `FC_CalcStrokeVelocityLimit` | 剩余行程、裕量、减速度 → 制动速度上限 | 到达边界、负裕量或无效减速度返回零 |
| `FC_CheckModeSourceMatrix` | Mode、Source → `BOOL` | 只放行三种冻结合法组合 |

## Phase 4通用FB

| FB | 状态接口 | Reset/生命周期 |
|---|---|---|
| `FB_LowPassFilter` | Enable、输入有效位、周期、时间常数 → 滤波值/有效位 | Reset/Disable清历史；无效输入保持最后值并撤销有效位 |
| `FB_Debounce` | 输入、On/Off延时 → 稳定值和双边沿脉冲 | Reset/Disable清计时；负延时拒绝运行 |
| `FB_SignalValidity` | 原始有效位、值、范围、无效延时 → 正式有效位 | Reset清状态；负延时立即无效；范围传反自动归一化 |
| `FB_SetpointRamp` | 起始值、目标、双向速率、周期 → 连续输出 | Reset/Disable回到起始值；无效参数保持连续输出 |
| `FB_CommandHandshake` | RequestId → AcceptedId、新请求脉冲 | Reset将AcceptedId归零；相同编号标记重复 |
| `FB_AlarmLatch` | 置位、源状态、复位权限 → 锁存/拒绝 | 置位优先；源仍存在或权限不足时拒绝复位 |

这些对象不访问GVL、PROGRAM局部变量、`AXIS_REF`或`MC_*`；实际实例仍按实例所有权矩阵在对应后续Phase由唯一Owner声明。

## Phase 5传感器与参考点契约

### `ST_SensorProcessingConfig`

发布四路Force滤波时间常数、Force/Displacement有效范围与延时、Collision去抖时间和Axis/Sensor差值限值。`bValid=FALSE`时全部传感器处理实例撤销有效状态。

### `ST_ProcessReferenceCommand`

`PRG_CffSequence`后续通过`udiContactReferenceRequestId`事务请求锁存或清除Contact参考点；`PRG_FastInputs`只在编号变化时处理一次。Phase 9增加确认时Axis/Sensor候选位置字段，使用候选模式时先检查有限性和配置范围，再精确锁存Contact检测时的位置。步骤切换不得递增清除请求，因此四个CFF步骤共享同一Contact零点。

### `ST_ProcessActual`

同时发布：

- `ForceRaw / ForceCriterion / ForceControl / ForceDisplay`；
- 外部位移绝对值和主反馈`SRelSensor`；
- NC诊断`SRelAxis`及`AxisSensorDelta`；
- `CollisionDelta`和去抖后的参考传感器状态；
- 力、位移、Collision、Contact Reference及Axis/Sensor一致性有效位。

外部位移无效时不自动降级为`SRelAxis`。所有有效位同时依赖人工映射状态和标定Revision；本阶段没有代码写入任何`Mapped`字段或Production Ready。

## 分阶段状态

- 14个接口DUT已经加入PLC工程，并在Phase 3完成枚举类型化。
- Phase 4加入14个纯计算FC和6个通用FB；当前只定义可复用类型，不提前声明业务实例。
- Phase 5加入传感器处理与Contact参考点契约，并由`PRG_FastInputs`唯一写入快速过程实际值。
- Phase 6加入`FB_AxisCommandArbiter`、`FB_ZAxisNcAdapter`和`FB_RAxisNcAdapter`；Phase 7加入唯一`FB_ZAxisExtSetpointAdapter`。只有这三个轴Adapter持有`AXIS_REF`及MC实例；`PRG_FastAxisControl`只负责候选拆分、调用和状态发布。
- Phase 8加入纯算法`FB_BumplessProfileSwitch`和`FB_ZForceAdmittance`，并由`PRG_FastAxisControl`唯一实例化；Profile、S_rel目标和机器Z/Force限值以一次无扰提交形成快照。
- Phase 9加入纯算法`FB_ContactDetect`、`FB_ForceDeclineObserver`和`FB_StepProceedingCriterion`，并由`PRG_CffSequence`唯一实例化；截至Phase 9三者Enable保持FALSE，正式状态机接线保留给Phase 10。
- 标准运动以`ST_FastCommand.nRequestId`作为事务编号；Adapter只在编号变化时产生一次MC `Execute`上升沿，活动速度命令使用双实例交替以允许新事务按`MC_Aborting`替换。
- External命令在Force Process Owner授予后才允许Enable，ACTIVE每个2 ms周期Feed；Owner在完整Disable和后保持完成前不转交标准NC通道。
- Phase 8导纳输出只进入Fast状态，不覆盖External P/V/A/Direction；Sequence Error/Aborted、Owner/External/传感器有效性缺失、硬边界或算法故障均禁止可消费的活动输出。
- 数据DUT只定义契约；Phase 6/7 MC命令仅由三个轴Adapter生成，Phase 8算法不调用MC，真实驱动未关联时不生成执行沿且Ready保持FALSE。
- PROGRAM骨架没有跨PROGRAM局部变量访问。

## Phase 10最终接口核对

### 新增枚举

| 枚举 | 值 | 实际语义 |
|---|---|---|
| `E_CffExitIntent` | `CFF_EXIT_NONE=0`、`CFF_EXIT_NORMAL_RETURN=10`、`CFF_EXIT_NOK_RETURN=20`、`CFF_EXIT_ABORT_NO_RETURN=30`、`CFF_EXIT_FAULT_NO_RETURN=40` | 用单一互斥值选择正常返回、NOK返回、无返回中止或无返回故障；避免多个冲突BOOL |
| `E_ZExternalTrajectoryState` | `Z_TRAJ_IDLE=0`、`Z_TRAJ_SYNC=10`、`Z_TRAJ_TRACKING=20`、`Z_TRAJ_RAMP_TO_ZERO=30`、`Z_TRAJ_HOLD_OLD_DIRECTION=40`、`Z_TRAJ_DIRECTION_ZERO=50`、`Z_TRAJ_PRELOAD_NEW_DIRECTION=60`、`Z_TRAJ_FAULT=100` | 纯External轨迹及accepted-feed驱动的安全换向状态 |

### 机器配置与周期快照

#### `ST_CffSequenceConfig`

| 字段 | 类型 | 语义 |
|---|---|---|
| `tApproachTimeout` | `TIME` | Approach标准定位超时 |
| `tContactSearchTimeout` | `TIME` | Contact Search超时 |
| `tContactReferenceAckTimeout` | `TIME` | Contact Reset/Latch参考事务Ack超时 |
| `tControlledUnloadTimeout` | `TIME` | 受控卸载超时 |
| `tUnloadStandstillConfirm` | `TIME` | 卸载条件连续确认时间 |
| `tRAxisStopTimeout` | `TIME` | R轴停止Ack/实际静止超时 |
| `tReturnTimeout` | `TIME` | 标准NC返回超时 |
| `fStandardMoveAccelerationMmS2` | `LREAL` | Approach/Return标准NC加速度，`mm/s2` |
| `fStandardMoveDecelerationMmS2` | `LREAL` | Approach/Return标准NC减速度，`mm/s2` |
| `bValid` | `BOOL` | 机器配置已受控确认；`GVL_Config.stCffSequence`当前没有合格默认值 |

`FC_ValidateCffSequenceConfig`是纯函数，要求全部超时大于零、两个标准NC斜率有限且大于零，并且不超过有效机器Z轴最大加速度。`GVL_Config.stCffSequence`当前由未来配置管理流程负责写入；Sequence只在Start时复制并验证。

#### `ST_CffFastConfigSnapshot`

| 字段 | 类型 | Writer/相关性 |
|---|---|---|
| `nSequenceCommandId` | `UDINT` | 形成快照的Start事务号 |
| `stMachine` | `ST_MachineConfig` | Start时冻结的任务周期与机器Revision |
| `stLimits` | `ST_MachineLimits` | Start时冻结的运动/过程硬限值 |
| `stZExtSetpoint` | `ST_ZExtSetpointConfig` | Start时冻结的External生命周期配置 |
| `stZForceControl` | `ST_ZForceControlProfile` | Start时冻结的Force Profile |
| `bValid` | `BOOL` | 仅Precheck通过后由Sequence置真 |

`PRG_CffSequence`是该快照的唯一Writer，并把它发布为`GVL_Status.stFast.stSequence.stFastConfigSnapshot`。`PRG_FastAxisControl`只在`bValid=TRUE`且`nSequenceCommandId = stSequence.nAcceptedCommandId`时消费；失配会触发Fast安全停止并禁止自动复动。`GVL_FastInternal`不包含此快照。

### Sequence运动意图

#### `ST_CffMotionIntent`

| 字段 | 类型 | 语义 |
|---|---|---|
| `udiZCommandId` | `UDINT` | Sequence Z标准NC源事务号 |
| `stZCommand` | `ST_ZAxisCommand` | Approach、Force Process、Retract或Fault Stop候选 |
| `bExternalEnableRequest` | `BOOL` | 请求External进入Enable/Active生命周期 |
| `bExternalDisableRequest` | `BOOL` | 请求External完成安全Disable |
| `rExternalTargetVelocity_mm_s` | `LREAL` | Contact Search或非力控阶段的External目标速度 |
| `bRAxisProcessRequested` | `BOOL` | Sequence占用R命令源 |
| `udiRCommandId` | `UDINT` | Sequence R源事务号 |
| `stRCommand` | `ST_RAxisCommand` | 单次阶段MoveVelocity或Stop候选 |
| `bForceProcessExitComplete` | `BOOL` | Sequence侧允许退出Force Process；FastAxis仍要求Adapter已`bReleaseOwner` |

`PRG_CffSequence`每扫描完整重建并唯一写入该结构，嵌套发布在`ST_CffSequenceStatus`中；`PRG_FastAxisControl`读取后执行Owner仲裁、命令源转换、轨迹和Adapter调用。Sequence本身不访问`AXIS_REF`、不调用MC，也不直接写External P/V/A/Direction。

### External纯轨迹输入/输出

#### `ST_ZExternalTrajectoryInput`

| 字段 | 类型 | 单位/语义 |
|---|---|---|
| `bEnable`、`bReset` | `BOOL` | 算法生命周期控制 |
| `eExternalState` | `E_ZExtSetpointState` | Adapter实际生命周期状态 |
| `bAcceptedSetpointValid`、`bFeedAccepted` | `BOOL` | accepted基准和本扫描Feed确认 |
| `udiAcceptedFeedCycleCounter` | `UDINT` | accepted Feed计数；最大值后由Adapter回到1并跳过0 |
| `rAcceptedPosition_mm` | `LREAL` | accepted位置，`mm` |
| `rAcceptedVelocity_mm_s` | `LREAL` | accepted速度，`mm/s` |
| `rAcceptedAcceleration_mm_s2` | `LREAL` | accepted加速度，`mm/s2` |
| `nAcceptedDirection` | `DINT` | accepted方向，`-1/0/1` |
| `bInhibitPositiveMotion` | `BOOL` | Hard Force/Stroke/Collision禁止继续正向运动 |
| `rTargetVelocity_mm_s` | `LREAL` | Sequence搜索速度或导纳速度目标，`mm/s` |
| `rCycleTime_s` | `LREAL` | Fast周期，`s` |
| `rMinimumPosition_mm`、`rMaximumPosition_mm` | `LREAL` | 冻结Z位置范围，`mm` |
| `rMaximumVelocity_mm_s` | `LREAL` | 冻结最大速度，`mm/s` |
| `rMaximumAcceleration_mm_s2` | `LREAL` | 冻结最大加速度，`mm/s2` |
| `rStandstillVelocity_mm_s` | `LREAL` | External静止阈值，`mm/s` |
| `rMaximumPositionDeviation_mm` | `LREAL` | accepted/已发布位置连续性窗口，`mm` |
| `nDirectionHoldCycles` | `UINT` | 旧方向零速保持的accepted周期数 |

#### `ST_ZExternalTrajectoryOutput`

| 字段 | 类型 | 语义 |
|---|---|---|
| `rPosition_mm`、`rVelocity_mm_s`、`rAcceleration_mm_s2` | `LREAL` | 从最后accepted基准产生的P/V/A |
| `nDirection` | `DINT` | 本包方向 |
| `eState` | `E_ZExternalTrajectoryState` | 当前纯轨迹状态 |
| `bDirectionTransition` | `BOOL` | 正在执行零速换向握手 |
| `bZeroConfirmed` | `BOOL` | 最近发布的零速包已被Adapter接受 |
| `bPositiveMotionInhibited` | `BOOL` | 当前包是硬正向运动抑制包 |
| `bActive` | `BOOL` | 可由FastAxis送入Adapter的活动包 |
| `bFault`、`nFaultId` | `BOOL`、`UDINT` | 首故障锁存及确定性故障号 |

`FB_ZExternalTrajectory`只在`bFeedAccepted=TRUE`且Counter变化后从新accepted基准推进；没有新Ack时重复同一待接受包，不从期望输出空积分。安全换向顺序为`RAMP_TO_ZERO → HOLD_OLD_DIRECTION → DIRECTION_ZERO → PRELOAD_NEW_DIRECTION → TRACKING`。硬正向抑制包保持accepted位置/方向并立即输出`V=0、A=0`；轨迹Fault由FastAxis停止普通Feed并请求Adapter安全Disable。

### Phase 10扩展的既有契约

| 类型 | 新增/实际使用字段 | 当前用途 |
|---|---|---|
| `ST_JoinProgramHeader` | `fContactSearchStartPositionMm` | Approach目标；Validator要求有限且位于Z范围 |
| `ST_StepProceedingConfig` | `nQualifiedForceHoldMs`、`fForceBandToleranceN`、`fRpmStoppedThresholdRpm` | Step4有效保持、Force带宽和实际RPM停止门 |
| `ST_StepCriterionResult` | `bTooShort`、`bQualifiedForceHoldMet`、`rQualifiedForceHoldTime_s`、`rLatchedForce_kN`、`rLatchedRelativePosition_mm`、`rLatchedStepTime_s` | 四个步骤各自的唯一结果槽和Evaluate事实 |
| `ST_ZForceControlProfile` | `nProfileId` | 与Program Header匹配；`nRevision`和参数在Start时冻结 |
| `ST_RAxisProfile` | `nProfileId`、`nRevision` | 与Program Header匹配；R斜率和资格参数在Start时冻结 |
| `ST_ZExtSetpointCommand` | `bPositiveMotionInhibit` | 只标记精确held-P/V0/A0/same-direction硬安全包 |
| `ST_ZExtSetpointStatus` | accepted有效位及P/V/A/Direction | 轨迹下一包的唯一积分基准 |
| `ST_CffSequenceStatus` | `eExitIntent`、`bCycleNok`、`bRpmStopped`、`bForceInBand`、`rStepTime_s`、`rQualifiedForceHoldTime_s`、`rForceRamp_kN_s`、`stMotionIntent`、`stFastConfigSnapshot` | Sequence完整状态、步骤事实、运动意图和冻结配置发布 |
| `ST_FastStatus` | `stZExternalTrajectory`、两个Sequence Z/R接受号、R包络状态、Force Ramp状态 | FastAxis闭环Ack、算法状态和诊断发布 |

`ST_CffSequenceStatus`终态真值固定为：`COMPLETE_OK=(bDone=TRUE, bError=FALSE, bAborted=FALSE)`、`COMPLETE_NOK=(bDone=TRUE, bError=TRUE, bAborted=FALSE)`、`ABORT=(bDone=FALSE, bError=FALSE, bAborted=TRUE)`、`FAULT=(bDone=FALSE, bError=TRUE, bAborted=FALSE)`。Cycle NOK在健康卸载期间只作为诊断，不提前关闭Force/External退出链。

### 实际Writer/Reader和握手

| 合同/方向 | 实际Writer | Reader/Ack | Phase 10语义 |
|---|---|---|---|
| `GVL_Command.stFast` → `GVL_FastInternal.stAcceptedCommand` | 生产级Main Writer尚未实现；`PRG_FastInputs`是内部accepted副本唯一Writer | `PRG_CffSequence`、`PRG_FastAxisControl`；`GVL_Status.stFast.nAcceptedRequestId`为外层Ack | payload先写、外层`nRequestId`最后写并保持；FastInputs只接受半范围规则下更新且双读稳定的完整1280-bit包 |
| accepted `ST_CffSequenceCommand` → Sequence状态 | 未来`PRG_CommandDispatcher`应发布；当前仍为空骨架 | `PRG_CffSequence`以`nCommandId`单一高水位去重 | 每个更新ID最多一个Start/Stop/Abort/Reset pulse；重复、旧ID、零ID不产生动作 |
| `GVL_Program.stCycleSnapshot`和活配置 → 局部Start快照 | 未来`PRG_ProgramManager`及配置管理流程；当前Program Manager为空骨架 | `PRG_CffSequence` | Start接受时复核Revision/Profile身份并冻结；活动周期不以活配置放宽安全边界 |
| `GVL_Status.stFast.stSequence.stMotionIntent` | `PRG_CffSequence` | `PRG_FastAxisControl` | Sequence源Z/R ID经“源类型+源ID”映射为独立Adapter ID；源切换即使数值相同也只产生一个新事务 |
| `udiAcceptedSequenceZCommandId`、`udiAcceptedSequenceRCommandId` | `PRG_FastAxisControl` | `PRG_CffSequence` | 只有对应Adapter接受其内部事务后才确认Sequence源ID；Sequence在Approach、Return、R停止等等待精确Ack |
| `GVL_Command.stProcessReference` | `PRG_CffSequence` | `PRG_FastInputs` | Precheck先发Reset；Contact确认再发Latch；五个payload先写、RequestId最后写并保持 |
| `GVL_Process.stActual.udiContactReferenceAcceptedId`及Reference Valid | `PRG_FastInputs` | `PRG_CffSequence` | 精确Ack且Reference Valid后才无扰接管Force并进入Step1；Ack超时或Valid失败进入Fault退出 |
| External轨迹包 → Adapter accepted状态 | `PRG_FastAxisControl`准备命令，`FB_ZAxisExtSetpointAdapter`唯一执行和发布accepted | `FB_ZExternalTrajectory`由FastAxis传入下一扫描 | Adapter校验后发布FeedAccepted、P/V/A/Direction和Counter；完整Disable/Post-hold后才发布ReleaseOwner |
| `bForceProcessExitComplete` | Sequence发布意图，FastAxis与Adapter Release做AND | `FB_AxisCommandArbiter` | Sequence单方面声明不能释放Force Process Owner |
| 安全终态Reset | accepted Sequence Reset事件 | Sequence、FastAxis各自门控 | 活动Reset先按Abort退出；只有Z/R静止且External已释放才清状态/算法；事务计数不重用，Reset后普通源还需更新的accepted外层包 |

Fast任务调用顺序固定为`PRG_FastInputs → PRG_CffSequence → PRG_FastAxisControl → PRG_FastMonitoring`。因此FastInputs先形成accepted命令，Sequence在同一扫描发布意图/快照，FastAxis再消费并发布Adapter/轨迹/Force/R反馈；Sequence在下一Fast扫描读取这些反馈完成Ack和状态推进。

### 报警槽和TMC离线符号

| 槽/符号 | Writer或BitSize | 说明 |
|---|---|---|
| `GVL_Alarm.astRequests[7]` | `PRG_FastAxisControl` | External Adapter/轨迹故障，TextId 2200、SourceId 7 |
| `GVL_Alarm.astRequests[8]` | `PRG_FastAxisControl` | Force Admittance/Profile故障，TextId 2500、SourceId 8 |
| `GVL_Alarm.astRequests[9]` | `PRG_CffSequence` | Contact/Decline/Criterion故障，TextId 3000、SourceId 9 |
| `GVL_Alarm.astRequests[10]` | `PRG_CffSequence` | CFF Sequence首故障，TextId 3200、SourceId 10 |
| `GVL_Config.stCffSequence` | `448 bit` | 生成TMC中的`ST_CffSequenceConfig`符号 |
| `GVL_FastInternal.stAcceptedCommand` | `1280 bit` | 生成TMC中的内部accepted `ST_FastCommand`符号 |
| `GVL_Status.stFast` | `8768 bit` | 生成TMC中的完整`ST_FastStatus`符号 |

以上BitSize只确认当前生成TMC的离线布局。尚未执行ADS在线枚举/读写、PLC Runtime观察或外部客户端兼容性验证。

### 未闭合的生产边界

- `PRG_CommandDispatcher`仍为future-writer skeleton：没有产生Start/Stop/Abort/Reset脉冲，也没有实现`GVL_Command.stFast`的生产级payload/RequestId保持和Ack事务。
- `PRG_ProgramManager`仍为future-writer skeleton：没有创建或激活Program，也没有实现`GVL_Program.stCycleSnapshot`的生产级Revision保持事务。
- `GVL_Status.bProductionReady`在源码中初始化为`FALSE`，除该声明外没有任何赋值；`PRG_CffSequence` Precheck仍明确要求它为真。因此Phase 10是Fast侧消费者实现，不是端到端生产启动实现。
- Torque闭环/前馈、Power/Energy、Material Observer、Process Window、Curve Recorder和最终`FB_ResultAnalyzer`仍为未来接口/实例；Phase 10不写`GVL_Process.stFeatures`或`GVL_Process.stLastCycleResult`，也不伪造这些结果。
- 当前Collision安全事实是`bCollisionValid AND bCollisionSensorActive`的临时类型化路径。Phase 11B要求的Collision IO删除和最终外部位移/NC双位置碰撞逻辑尚未实施。
- 未执行Runtime、External POC、真实驱动、任务同步/抖动、硬件映射、标定或工艺资格验证；本目录中的源码、静态测试、Build和TMC均不能替代这些验证。
