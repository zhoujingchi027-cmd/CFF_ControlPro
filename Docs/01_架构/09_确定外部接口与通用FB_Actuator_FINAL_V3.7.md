
# 确定外部接口、IO_Config映射与通用FB_Actuator FINAL V3.7

## 1. 本文件优先级

本文件冻结：

1. 外部模块过程映像的变量名和类型；
2. `PRG_IO_Config`的职责和映射边界；
3. `ST_USINT / DUT_USINT / stGunbox_byteIN`原始接口；
4. 新版通用`FB_Actuator`；
5. 各模块气缸实例；
6. Maintenance点动的执行路径。

若旧规范使用了泛化外部变量名、两个独立气缸FB或不一致的原始总线接口，以本文件为准。

---

# 2. 外部过程映像变量必须按图保留

新增：

```text
GVL_ExternalIO
```

以下外部符号名和Legacy类型名必须保留，方便后期人工映射。

```pascal
{attribute 'qualified_only'}
VAR_GLOBAL
    (* ---------------------------------------------------------
       Robot到PLC的Profinet输入，共20字节。
       字节定义由用户后期人工确认。
       --------------------------------------------------------- *)
    robot_to_plc AT %I* : ARRAY[1..20] OF BYTE;

    (* ---------------------------------------------------------
       PLC到Robot的Profinet输出，共20字节。
       字节定义由用户后期人工确认。
       --------------------------------------------------------- *)
    plc_to_robot AT %Q* : ARRAY[1..20] OF BYTE;

    (* ---------------------------------------------------------
       供钉站基础输入：
       拉钉伸出、拉钉缩回、轨道检测、出料检测、料盘检测。
       --------------------------------------------------------- *)
    bsensor AT %I* : ST_sensor;

    (* ---------------------------------------------------------
       集中输出结构：
       枪头馈送：侦测气缸伸出、侦测气缸缩回；
       弹夹：三位气缸伸出、三位气缸缩回、测满气缸1、
             测满气缸2、馈送吹气；
       供钉站：拉钉气缸、减压馈送吹气、正常馈送吹气、
               三吹气、轨道头吹气。
       Legacy拼写bactuaor/ST_actuaor必须保留。
       --------------------------------------------------------- *)
    bactuaor AT %Q* : ST_actuaor;

    (* Balluff/IO-Link联合字节输出：仓门气缸。 *)
    SMCBOX_bullfOut AT %Q* : ST_USINT;

    (* ---------------------------------------------------------
       Balluff/IO-Link联合字节输入：
       立柱A过料、立柱B过料、仓门伸出、仓门缩回、仓门对接。
       --------------------------------------------------------- *)
    SMCBOX_bullfIn AT %I* : ST_USINT;

    (* SMC端口数字输出：振动盘。 *)
    SMCBOX_portDo AT %Q* : ST_USINT;

    (* ---------------------------------------------------------
       枪头Balluff 2-pin数字输入联合字节。
       当前注释确定包含Z正限位、Z负限位和Z原点；
       其他位的对应关系由用户人工确认。
       --------------------------------------------------------- *)
    gunBOX_bullIn AT %I* : ST_USINT;

    (* ---------------------------------------------------------
       枪头Balluff 4-pin/IO-Link字节输入。
       保存气缸和过料相关原始字节，具体bit含义人工确认。
       --------------------------------------------------------- *)
    gunBOX_byteIn AT %I* : stGunbox_byteIN;
END_VAR
```

如果当前XAE不允许结构使用`AT %I* / AT %Q*`，使用普通变量并保留完全相同的符号名，同时加：

```pascal
(* TODO_HW_MAP：用户扫描硬件后人工链接。 *)
```

不得替换为固定地址。

---

# 3. Legacy原始类型

## 3.1 供钉站基础输入

```pascal
{attribute 'pack_mode' := '1'}
TYPE ST_sensor :
STRUCT
    (* 拉钉气缸伸出反馈。 *)
    bPullPinCylinderExtended : BOOL;

    (* 拉钉气缸缩回反馈。 *)
    bPullPinCylinderRetracted : BOOL;

    (* 轨道CFF元件检测。 *)
    bTrackFastenerDetected : BOOL;

    (* 出料位置CFF元件检测。 *)
    bOutletFastenerDetected : BOOL;

    (* 料盘/物料存在检测。 *)
    bTrayMaterialDetected : BOOL;
END_STRUCT
END_TYPE
```

## 3.2 集中输出结构

Legacy类型名`ST_actuaor`拼写必须保留。

```pascal
{attribute 'pack_mode' := '1'}
TYPE ST_actuaor :
STRUCT
    (* 枪头侦测气缸伸出。 *)
    bGunDetectionCylinderExtend : BOOL;

    (* 枪头侦测气缸缩回。 *)
    bGunDetectionCylinderRetract : BOOL;

    (* 弹夹三位气缸伸出。 *)
    bMagazineThreePositionCylinderExtend : BOOL;

    (* 弹夹三位气缸缩回。 *)
    bMagazineThreePositionCylinderRetract : BOOL;

    (* 弹夹测满气缸A阀。 *)
    bMagazineFullCheckCylinderAValve : BOOL;

    (* 弹夹测满气缸B阀。 *)
    bMagazineFullCheckCylinderBValve : BOOL;

    (* 弹夹向枪头馈送吹气。 *)
    bMagazineFeedAirBlow : BOOL;

    (* 供钉站拉钉气缸阀。 *)
    bStationPullPinCylinderValve : BOOL;

    (* 供钉站减压馈送吹气。 *)
    bStationReducedPressureFeedAir : BOOL;

    (* 供钉站正常馈送吹气。 *)
    bStationNormalPressureFeedAir : BOOL;

    (* 供钉站三吹气。 *)
    bStationTripleAirBlow : BOOL;

    (* 供钉站轨道头吹气。 *)
    bStationTrackHeadAirBlow : BOOL;
END_STRUCT
END_TYPE
```

## 3.3 联合字节

按图保留：

```pascal
TYPE DUT_USINT :
STRUCT
    BIT0 : BIT;
    BIT1 : BIT;
    BIT2 : BIT;
    BIT3 : BIT;
    BIT4 : BIT;
    BIT5 : BIT;
    BIT6 : BIT;
    BIT7 : BIT;
END_STRUCT
END_TYPE
```

```pascal
TYPE ST_USINT :
UNION
    Ousint : USINT;
    OUT_BOOL_TO_USINT : DUT_USINT;
END_UNION
END_TYPE
```

要求：

```text
SIZEOF(DUT_USINT) = 1
SIZEOF(ST_USINT) = 1
```

Codex应在`PRG_IO_Config.ACT_ValidateMappings`中做运行时尺寸检查并写诊断，不得让模块业务程序直接使用该Union。

## 3.4 枪头字节输入

按图保留Legacy字段名：

```pascal
{attribute 'pack_mode' := '1'}
TYPE stGunbox_byteIN :
STRUCT
    Acylindback : BYTE;
    Bcylindback : BYTE;
    Threecylind_to_A : BYTE;
    Threecylind_to_Mid : BYTE;
    revitcilindout : BYTE;
    revitcilindback : BYTE;
    passsingal : BYTE;
END_STRUCT
END_TYPE
```

这些字段是外部原始接口，不要求内部模块沿用Legacy命名。

---

# 4. GVL_IO与外部接口边界

以下信号仍可直接保留在`GVL_IO`中：

```text
Z_axis / R_axis
nZForceRaw
nZDisplacementRaw
Manual / Automatic / Maintenance
Local / Robot
Red / Yellow / Green Lamp
```

Z轴：

```text
bZHomeSwitch
bZLimitPositiveSwitch
bZLimitNegativeSwitch
```

改为内部干净BOOL，不再带`AT %I*`，由：

```text
gunBOX_bullIn
→ PRG_IO_Config
→ GVL_IO
```

赋值。

---

# 5. IO_Config强制映射方式

`PRG_IO_Config`是以下原始外部变量的唯一读写者：

```text
robot_to_plc
plc_to_robot
bsensor
bactuaor
SMCBOX_bullfOut
SMCBOX_bullfIn
SMCBOX_portDo
gunBOX_bullIn
gunBOX_byteIn
```

模块PROGRAM不得访问这些变量。

## 5.1 Actions

```text
ACT_ClearInputSnapshots
ACT_ReadRobotRaw
ACT_ReadStationSensorStruct
ACT_ReadSmcBoxBits
ACT_ReadGunBoxBoolBits
ACT_ReadGunBoxByteInputs

ACT_ClearRawOutputs
ACT_WriteActuatorStruct
ACT_WriteSmcBoxOutputs
ACT_WriteRobotRaw

ACT_ValidateRawLayouts
ACT_UpdateMappingValidity
```

## 5.2 输入映射

### 供钉站基础输入

```pascal
GVL_ModuleInterface.stFastenerStation.stPhysicalInput.bPullPinCylinderExtended :=
    GVL_ExternalIO.bsensor.bPullPinCylinderExtended;
```

其余四项同样直接赋值。

### SMCBOX输入位

建议当前默认顺序：

```text
BIT0 → Column A Pass
BIT1 → Column B Pass
BIT2 → Bin Door Extended
BIT3 → Bin Door Retracted
BIT4 → Bin Door Docking
```

每行前加：

```pascal
(* TODO_HW_MAP：当前按注释顺序映射，用户现场核对后确认。 *)
```

并由：

```text
bSmcBoxInputMappingConfirmed
```

决定信号是否有效。

### gunBOX_bullIn

建议当前默认：

```text
BIT0 → Z Positive Limit
BIT1 → Z Negative Limit
BIT2 → Z Home
```

其他位保持未使用或由用户后期配置。

未确认时：

```text
bGunBoxBoolMappingConfirmed = FALSE
Z参考输入有效性 = FALSE
```

### gunBOX_byteIn

通过：

```text
FC_GetBitFromByte
```

和显式的`TODO_HW_MAP`常量解码。

当前可按Legacy字段名称建立候选：

```text
revitcilindout
revitcilindback
passsingal
Threecylind_to_A
Threecylind_to_Mid
Acylindback
Bcylindback
```

但每个bit和语义必须保留人工调整入口。

Codex不得将未确认的bit映射标记为有效。

## 5.3 输出映射

内部模块输出映射到`bactuaor`：

```text
Gun detection extend/retract
Magazine three-position extend/retract
Full-check A/B valves
Magazine feed air
Station pull-pin valve
Station reduced/normal feed air
Station triple air
Station track-head air
```

额外：

```text
SMCBOX_bullfOut.BIT0 → Bin Door Cylinder Valve
SMCBOX_portDo.BIT0   → Vibratory Bowl Run
```

每个扫描周期必须：

1. 先清零所有Raw Output；
2. 再按内部模块最终输出赋值；
3. 清零所有未使用bit；
4. 映射未确认、Module Fault或Stop时保持安全FALSE。

---

# 6. Mapping确认状态

新增：

```pascal
TYPE ST_IoMappingStatus :
STRUCT
    bRobotByteLayoutConfirmed : BOOL;
    bStationSensorStructConfirmed : BOOL;
    bActuatorStructConfirmed : BOOL;
    bSmcBoxInputMappingConfirmed : BOOL;
    bSmcBoxOutputMappingConfirmed : BOOL;
    bGunBoxBoolMappingConfirmed : BOOL;
    bGunBoxByteMappingConfirmed : BOOL;
    bRawTypeSizeValid : BOOL;
    bAllRequiredMappingsConfirmed : BOOL;
END_STRUCT
END_TYPE
```

这些字段不能由Codex强制为TRUE。

用户人工核对后才允许置位。

生产Ready必须要求：

```text
bAllRequiredMappingsConfirmed = TRUE
```

---

# 7. 原FB_Actuator只作为概念参考

用户提供的旧`FB_Actuator.TcPOU`可参考以下概念：

- Enable；
- Work/Basic两方向；
- Work/Basic反馈；
- 输入滤波；
- 超时；
- Reset；
- Error ID；
- 单独的Work/Basic输出；
- 手动和自动都可请求动作。

不得直接复制以下实现：

- 在FB内部修改`VAR_INPUT`；
- 依赖`MainSysState`；
- 依赖全局`status_Restdone`；
- 依赖旧`alarmstring`；
- 把HMI按钮直接放在执行器FB；
- 使用WSTRING名称参与控制；
- 用时间模拟到位作为生产默认；
- 让FB自己决定Manual/Automatic Owner；
- 在FB内部做跨模块模式仲裁。

新版`FB_Actuator`必须是独立、可复用、无全局依赖的执行器内核。

---

# 8. 新版通用FB_Actuator

## 8.1 单控/双控切换

使用配置变量：

```pascal
TYPE ST_ActuatorConfig :
STRUCT
    (* FALSE=单电控，TRUE=双电控。 *)
    bDoubleSolenoid : BOOL;

    (* 单电控时，通电是否对应工作位。 *)
    bSingleSolenoidOnForWork : BOOL;

    (* 双电控时，到位后是否继续保持当前方向输出。 *)
    bHoldDoubleOutputAfterArrival : BOOL;

    (* 工作位反馈是否必须存在。 *)
    bRequireWorkFeedback : BOOL;

    (* 基本位反馈是否必须存在。 *)
    bRequireBasicFeedback : BOOL;

    tFilterWork : TIME;
    tFilterBasic : TIME;
    tTimeoutWork : TIME;
    tTimeoutBasic : TIME;
    tDirectionChangeDeadTime : TIME;
END_STRUCT
END_TYPE
```

## 8.2 命令

```pascal
TYPE E_ActuatorCommand :
(
    ACTUATOR_CMD_NONE := 0,
    ACTUATOR_CMD_MOVE_WORK := 10,
    ACTUATOR_CMD_MOVE_BASIC := 20,
    ACTUATOR_CMD_STOP := 30
);
END_TYPE
```

## 8.3 状态

```pascal
TYPE E_ActuatorState :
(
    ACTUATOR_STATE_DISABLED := 0,
    ACTUATOR_STATE_IDLE := 10,
    ACTUATOR_STATE_CHANGEOVER_DELAY := 20,
    ACTUATOR_STATE_MOVING_WORK := 30,
    ACTUATOR_STATE_MOVING_BASIC := 40,
    ACTUATOR_STATE_AT_WORK := 50,
    ACTUATOR_STATE_AT_BASIC := 60,
    ACTUATOR_STATE_FAULT := 100
);
END_TYPE
```

## 8.4 FB接口

```pascal
FUNCTION_BLOCK FB_Actuator
VAR_INPUT
    (* 执行器使能。 *)
    bEnable : BOOL;

    (* 故障复位。 *)
    bReset : BOOL;

    (* 已由模块PROGRAM仲裁后的唯一最终命令。 *)
    eCommand : E_ActuatorCommand;

    (* 工作位反馈。 *)
    bInWork : BOOL;

    (* 基本位反馈。 *)
    bInBasic : BOOL;

    (* 执行器配置。 *)
    stConfig : ST_ActuatorConfig;
END_VAR

VAR_OUTPUT
    (* 双电控工作位阀输出。 *)
    bOutWorkValve : BOOL;

    (* 双电控基本位阀输出。 *)
    bOutBasicValve : BOOL;

    (* 单电控阀输出。 *)
    bOutSingleValve : BOOL;

    bIsWork : BOOL;
    bIsBasic : BOOL;
    bBusy : BOOL;

    (* 达到本次目标时产生一个扫描周期脉冲。 *)
    bDone : BOOL;

    bFault : BOOL;
    uiFaultCode : UINT;
    eState : E_ActuatorState;
    tMoveElapsed : TIME;
END_VAR
```

## 8.5 单电控输出

如果：

```text
bDoubleSolenoid = FALSE
bSingleSolenoidOnForWork = TRUE
```

则：

```text
Move Work  → bOutSingleValve=TRUE
Move Basic → bOutSingleValve=FALSE
```

如果`bSingleSolenoidOnForWork=FALSE`，逻辑反转。

双电控输出必须始终满足：

```text
NOT (bOutWorkValve AND bOutBasicValve)
```

单电控模式下：

```text
bOutWorkValve = FALSE
bOutBasicValve = FALSE
```

双电控模式下：

```text
bOutSingleValve = FALSE
```

## 8.6 功能

必须实现：

- Work/Basic反馈滤波；
- 双反馈同时TRUE故障；
- 方向切换死区；
- Work/Basic超时；
- Disable/Stop/Fault安全输出；
- Done单扫描脉冲；
- Reset；
- 可在线观察State和Elapsed；
- 无全局变量依赖；
- 不修改输入参数。

不实现：

- HMI按钮；
- Machine Mode判断；
- 自动/维修Owner；
- 工艺步骤；
- 跨模块请求；
- 无反馈时间模拟。

---

# 9. 气缸实例

## 9.1 枪头馈送

```text
fbDetectionCylinder : FB_Actuator
Control = Double Solenoid
```

反馈：

```text
CylinderDetection1
CylinderDetection2
```

Work/Basic对应关系由IO_Config后期人工确认。

输出：

```text
GunDetectionCylinderExtend
GunDetectionCylinderRetract
```

## 9.2 弹夹

```text
fbThreePositionCylinder : FB_Actuator
Control = Double Solenoid

fbFullCheckCylinderA : FB_Actuator
Control = Single Solenoid

fbFullCheckCylinderB : FB_Actuator
Control = Single Solenoid
```

第三个“拉钉检测”属于工艺传感器，不作为第三个阀方向。

## 9.3 供钉站

```text
fbPullPinCylinder : FB_Actuator
Control = Single Solenoid

fbBinDoorCylinder : FB_Actuator
Control = Single Solenoid
```

单电控通电方向由模块Config决定。

## 9.4 吹气和振动盘

继续使用：

```text
FB_TimedAirValve
```

实例：

- Magazine Feed Air；
- Reduced Pressure Feed Air；
- Normal Pressure Feed Air；
- Triple Air Blow；
- Track Head Air Blow。

振动盘由模块PROGRAM统一Owner，至少具备：

- Enable；
- Maintenance Hold；
- 最大连续运行时间；
- Stop/Fault强制关闭。

不得用`FB_Actuator`控制振动盘。

---

# 10. 模块Owner与命令仲裁

`FB_Actuator`只接收一个最终`eCommand`。

模块PROGRAM负责：

```text
AutomaticOwner
MaintenanceOwner
Stop/Fault
```

优先级：

```text
Fault/Stop
> Maintenance Hold-to-Run
> Automatic Module Logic
> Safe Idle
```

当前`ACT_Automatic_TODO`不产生动作，因此只有Maintenance点动可驱动执行器。

---

# 11. Maintenance点动

正式路径：

```text
WPF Hold Request
→ PRG_MaintenanceControl
→ 模块Maintenance Request
→ 模块ACT_MaintenanceJog
→ 生成E_ActuatorCommand
→ FB_Actuator
→ 模块PhysicalOutput
→ PRG_IO_Config
→ Legacy外部接口
```

按钮释放、Heartbeat超时、模式变化、Fault或映射无效：

```text
eCommand := ACTUATOR_CMD_STOP
```

Maintenance不得直接赋值：

```text
bactuaor
SMCBOX_bullfOut
SMCBOX_portDo
```

---

# 12. Codex必须创建的实例报告

新增：

```text
Docs/报告/ACTUATOR_INSTANCE_MATRIX.md
Docs/报告/RAW_EXTERNAL_INTERFACE_CATALOG.md
Docs/报告/IO_CONFIG_ASSIGNMENT_REVIEW.md
```

实例报告至少记录：

```text
实例名
所属模块
单控/双控
Work/Basic反馈
物理输出
单电控通电方向
Timeout
Maintenance Actuator ID
唯一Owner
映射确认状态
```

---

# 13. 验收

- [ ] Legacy外部变量名全部存在。
- [ ] ST_USINT和DUT_USINT尺寸为1字节。
- [ ] stGunbox_byteIN字段名按图保留。
- [ ] 模块PROGRAM不访问Legacy外部变量。
- [ ] 只有PRG_IO_Config访问Legacy外部变量。
- [ ] 输出每周期先清零再赋值。
- [ ] 未使用bit保持FALSE。
- [ ] 映射未确认时Production Ready为FALSE。
- [ ] 只有一个FB_Actuator类型。
- [ ] 单控/双控通过配置变量切换。
- [ ] 新FB无旧项目全局依赖。
- [ ] 新FB不修改VAR_INPUT。
- [ ] 所有气缸已经实例化。
- [ ] Maintenance点动经过模块和FB。
- [ ] 自动Action仍保持安全TODO。
