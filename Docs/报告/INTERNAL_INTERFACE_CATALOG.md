# CFFwelding Internal Interface Catalog

## 设计规则

- 所有标识符使用英文ASCII。
- 每个公开字段前使用独立行中文注释说明意义、单位或生命周期。
- Phase 3已将接口状态字段替换为显式赋值枚举；Phase 4通用对象继续只依赖类型化参数和返回值。
- PROGRAM之间不得访问彼此局部变量；后续通过GVL中的这些类型化契约交互。
- 算法输入由调用者完整赋值，输出由对应FB或PROGRAM唯一写入。
- 只有轴Adapter允许通过`VAR_IN_OUT AXIS_REF`访问轴；以下算法接口均不包含`AXIS_REF`。

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

提供Reset/Enable/Feed/Disable生命周期请求和P/V/A/Direction设定值。方向只允许`-1/0/1`，位置、速度、加速度分别使用`mm`、`mm/s`、`mm/s2`。直接`+1/-1`反向被拒绝并触发受控退出。

### `ST_ZExtSetpointStatus`

发布Enabled、Busy、Done、FeedAccepted、ReleaseOwner、Error、ErrorId、`E_ZExtSetpointState`生命周期状态和Feed周期计数。`ReleaseOwner`只在NC确认Disabled并完成附加Feed/Post-disable hold后成立。

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

发布AcceptedCommandId、Busy、Done、Aborted、Error、ErrorId、类型化State/Step/SubPhase/EndCause，以及当前Force/RPM目标。Phase 8增加力控Enable、Profile Transfer、切换速度、目标/硬S_rel和硬力/硬行程/Collision边界请求；`PRG_CffSequence`仍为骨架，不会提前置位这些请求。

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
| `ST_StepCriterionInput` | `PRG_CffSequence`调用准备区 | `FB_StepProceedingCriterion` |
| `ST_StepCriterionOutput` | `FB_StepProceedingCriterion` | `PRG_CffSequence` |
| `ST_CffSequenceCommand` | `PRG_CommandDispatcher`/跨任务发布契约 | `PRG_CffSequence` |
| `ST_CffSequenceStatus` | `PRG_CffSequence` | Main Task状态机和ADS快照层 |

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

`PRG_CffSequence`后续通过`udiContactReferenceRequestId`事务请求锁存或清除Contact参考点；`PRG_FastInputs`只在编号变化时处理一次。步骤切换不得递增清除请求，因此四个CFF步骤共享同一Contact零点。

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
- 标准运动以`ST_FastCommand.nRequestId`作为事务编号；Adapter只在编号变化时产生一次MC `Execute`上升沿，活动速度命令使用双实例交替以允许新事务按`MC_Aborting`替换。
- External命令在Force Process Owner授予后才允许Enable，ACTIVE每个2 ms周期Feed；Owner在完整Disable和后保持完成前不转交标准NC通道。
- Phase 8导纳输出只进入Fast状态，不覆盖External P/V/A/Direction；Sequence Error/Aborted、Owner/External/传感器有效性缺失、硬边界或算法故障均禁止可消费的活动输出。
- 数据DUT只定义契约；Phase 6/7 MC命令仅由三个轴Adapter生成，Phase 8算法不调用MC，真实驱动未关联时不生成执行沿且Ready保持FALSE。
- PROGRAM骨架没有跨PROGRAM局部变量访问。
