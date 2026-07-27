
# IO_Config、模块PROGRAM与Action骨架 FINAL V3.7

## 1. 结构

```text
GVL_IO
    力、位移、模式、控制源、灯、内部Z参考状态

GVL_ExternalIO
    固定Legacy外部接口：
    robot_to_plc / plc_to_robot
    bsensor / bactuaor
    SMCBOX_bullfOut / bullfIn / portDo
    gunBOX_bullIn / gunBOX_byteIn

PRG_IO_Config
    Legacy外部接口 ↔ GVL_ModuleInterface/GVL_IO

GVL_ModuleInterface
    Gun Head Feed / Magazine / Fastener Station / Robot

模块PROGRAM
    内部接口、Action、FB实例

PRG_FastenerTransportCoordinator
    路径与握手
```

## 2. PRG_IO_Config

Actions：

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

输入在所有模块PROGRAM之前执行。

输出在所有模块PROGRAM、报警和灯逻辑之后执行。

## 3. PRG_MainTask概念顺序

```text
IO_Config Input Actions

Mode
Robot
Command
Program
Initialize
Calibration
Maintenance
Manual/Auto
Fastener Transport Coordinator
Gun Head Feed Module
Magazine Module
Fastener Station Module
Machine Main
Alarm
Tower Light

IO_Config Output Actions
```

## 4. 核心握手

```text
bFastenerReadyToSend
bReadyToReceive
```

Magazine：

```text
Station → Magazine → Gun Head Feed
```

Direct Blow：

```text
Station → Gun Head Feed
```

Coordinator只路由握手和路径。

## 5. 模块Actions

每个模块：

```text
ACT_ResetTransient
ACT_EvaluateInputs
ACT_UpdateHandshake
ACT_Automatic_TODO
ACT_MaintenanceJog
ACT_ApplyInterlocks
ACT_UpdateStatus
ACT_RaiseAlarms
ACT_CommitOutputs
```

`ACT_Automatic_TODO`保持安全输出，由用户人工编写。

## 6. 执行器

所有气缸统一使用：

```text
FB_Actuator
```

通过：

```text
ST_ActuatorConfig.bDoubleSolenoid
```

切换单控/双控。

吹气使用：

```text
FB_TimedAirValve
```

详细接口见：

```text
Docs/01_架构/09_确定外部接口与通用FB_Actuator_FINAL_V3.7.md
```

## 7. 外部映射

所有实际对应关系由用户后期人工修改`PRG_IO_Config` Actions。

在人工确认前：

```text
MappingConfirmed = FALSE
Machine Ready = FALSE
Automatic Ready = FALSE
```
