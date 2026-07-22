# CFFwelding Internal Interface Catalog

## 设计规则

- 所有标识符使用英文ASCII。
- 每个公开字段前使用独立行中文注释说明意义、单位或生命周期。
- 当前Phase 2只使用基础IEC类型；需要枚举的`UDINT`字段将在Phase 3创建显式赋值枚举后替换。
- PROGRAM之间不得访问彼此局部变量；后续通过GVL中的这些类型化契约交互。
- 算法输入由调用者完整赋值，输出由对应FB或PROGRAM唯一写入。
- 只有轴Adapter允许通过`VAR_IN_OUT AXIS_REF`访问轴；以下算法接口均不包含`AXIS_REF`。

## Force接口

### `ST_ZForceControlInput`

| 字段 | 类型 | 单位 | 语义 |
|---|---|---|---|
| `bEnable` | `BOOL` | - | 力控制使能请求 |
| `bReset` | `BOOL` | - | 清除算法内部状态 |
| `rForceSet_kN` | `LREAL` | kN | 当前步骤压向目标力 |
| `rForceActual_kN` | `LREAL` | kN | 低延迟压向实际力 |
| `rRelativePosition_mm` | `LREAL` | mm | Contact起累计S_rel，向下为正 |
| `rCycleTime_s` | `LREAL` | s | 实际算法调用周期 |

### `ST_ZForceControlOutput`

| 字段 | 类型 | 单位 | 语义 |
|---|---|---|---|
| `rVelocityCommand_mm_s` | `LREAL` | mm/s | 导纳控制Z速度命令，向下为正 |
| `rIntegralTerm_mm_s` | `LREAL` | mm/s | PI积分诊断值 |
| `bActive` | `BOOL` | - | 算法正在计算 |
| `bLimited` | `BOOL` | - | 速度、位移、加速度或硬边界限幅 |
| `bFault` | `BOOL` | - | 输入或算法诊断失败 |
| `nFaultId` | `UDINT` | - | 故障编号 |

## Z轴接口

### `ST_ZAxisCommand`

包含Enable、Reset、Stop、绝对定位、速度运行和External Setpoint选择；位置使用`mm`，速度使用`mm/s`，加减速度使用`mm/s2`，`nOwnerRequest`后续替换为`E_ZCommandOwner`。

### `ST_ZAxisStatus`

发布Ready、Enabled、Moving、Standstill、External Active、Error、ErrorId、ActiveOwner，以及Z轴实际位置`mm`和实际速度`mm/s`。Ready只表示内部轴接口条件，真实驱动未关联时不得转换为生产Ready。

### `ST_ZExtSetpointCommand`

提供Enable/Feed/Disable生命周期请求和P/V/A/Direction设定值。方向只允许`-1/0/1`，位置、速度、加速度分别使用`mm`、`mm/s`、`mm/s2`。

### `ST_ZExtSetpointStatus`

发布Enabled、Busy、Done、Error、ErrorId和生命周期状态。状态数值后续替换为`E_ZExtSetpointState`。

## R轴接口

### `ST_RAxisCommand`

提供Enable、Reset、Stop、速度运行、目标`rpm`和`rpm/s`加减速。首版不提供外部扭矩闭环命令。

### `ST_RAxisStatus`

发布Ready、Enabled、Moving、Standstill、Error、ErrorId、实际`rpm`和仅用于监控的实际转矩`Nm`。

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

发布AcceptedCommandId、Busy、Done、Aborted、Error、ErrorId、State、Step、SubPhase、EndCause，以及当前Force/RPM目标。状态数值将在Phase 3替换为显式枚举。

## Writer/Reader边界

| 接口 | 唯一写入者 | 主要读取者 |
|---|---|---|
| `ST_ZForceControlInput` | `PRG_FastAxisControl`调用准备区 | `FB_ZForceAdmittance` |
| `ST_ZForceControlOutput` | `FB_ZForceAdmittance` | `PRG_FastAxisControl`轴命令合成 |
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

## Phase 2状态

- 14个接口DUT已经加入PLC工程并由Phase 2验收脚本检查。
- 所有接口只定义数据契约，不读写硬件、不生成命令、不改变Ready。
- PROGRAM骨架没有跨PROGRAM局部变量访问。
