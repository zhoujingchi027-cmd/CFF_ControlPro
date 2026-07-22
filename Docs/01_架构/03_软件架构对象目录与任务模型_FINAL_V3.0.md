# 软件架构、对象目录与任务模型 V3.0

## 1. Task_CffFast

周期必须等于NC SAF周期。

调用顺序：

```text
1. PRG_FastInputs
2. PRG_CffSequence
3. PRG_FastAxisControl
4. PRG_FastMonitoring
```

### PRG_FastInputs

- Z/R `Axis.ReadStatus()`；
- 采集EP3174；
- 计算Force四通道；
- 采集外部位移；
- 计算SRelSensor/SRelAxis/Delta；
- 计算CollisionDelta；
- 传感器有效性。

### PRG_CffSequence

- Contact；
- Step1~4；
- Primary/Secondary；
- Force Decline；
- 目标Force/RPM/Profile；
- EndCause；
- NOK和退出请求。

不得调用MC。

### PRG_FastAxisControl

- Z Owner仲裁；
- Z标准NC Adapter；
- Z External Adapter；
- Z导纳控制；
- R轴Adapter。

### PRG_FastMonitoring

- Force统计；
- Torque/Power/Energy；
- Material Interface Monitor；
- Process Window；
- Curve Recorder；
- Alarm Request。

## 2. Task_CffMain

建议10 ms，最终以实际配置为准。

```text
1. PRG_ModeControl
2. PRG_RobotInterface
3. PRG_CommandDispatcher
4. PRG_ProgramManager
5. PRG_InitializeControl
6. PRG_ServiceCalibration
7. PRG_MaintenanceControl
8. PRG_ManualControl
9. PRG_AutoControl
10. PRG_FastenerControl
11. PRG_FeederControl
12. PRG_ClampControl
13. PRG_MachineMain
14. PRG_AlarmControl
15. PRG_TowerLightControl
```

### PRG_CommandDispatcher

- 读取HMI和Robot命令邮箱；
- 按优先级处理Stop/Reset/Init/Start；
- 验证模式、控制源、权限和状态；
- 转为内部单扫描Pulse；
- 写命令状态和拒绝原因。

### PRG_InitializeControl

执行初始化子状态机。

### PRG_MaintenanceControl

统一Test Mode替代功能：

- Motion；
- Feeding；
- Cylinder；
- Lamp；
- IO Diagnostic；
- Calibration选择。

### PRG_ServiceCalibration

只执行标定流程，不负责整个Maintenance菜单。

## 3. Task_CffSlow

建议20~50 ms，实际配置确认。

```text
1. PRG_HmiAdsInterface
2. PRG_ResultTraceability
3. PRG_Statistics
4. PRG_Persistence
```

### PRG_HmiAdsInterface

- ADS Contract；
- 把HMI请求写入MainTask邮箱；
- 发布状态快照；
- Program/Point传输；
- 报警/曲线分页；
- Heartbeat；
- Revision。

不得执行设备状态机。

## 4. PROGRAM对象

```text
PRG_FastInputs
PRG_CffSequence
PRG_FastAxisControl
PRG_FastMonitoring

PRG_ModeControl
PRG_RobotInterface
PRG_CommandDispatcher
PRG_ProgramManager
PRG_InitializeControl
PRG_ServiceCalibration
PRG_MaintenanceControl
PRG_ManualControl
PRG_AutoControl
PRG_FastenerControl
PRG_FeederControl
PRG_ClampControl
PRG_MachineMain
PRG_AlarmControl
PRG_TowerLightControl

PRG_HmiAdsInterface
PRG_ResultTraceability
PRG_Statistics
PRG_Persistence
```

## 5. FB对象

### Axis

```text
FB_AxisCommandArbiter
FB_ZAxisNcAdapter
FB_ZAxisExtSetpointAdapter
FB_RAxisNcAdapter
```

### Control

```text
FB_ZForceAdmittance
FB_SetpointRamp
FB_BumplessProfileSwitch
FB_ContactDetect
FB_StepProceedingCriterion
FB_ForceDeclineObserver
FB_EnergyCalculator
FB_ForceStepStatistics
FB_MaterialInterfaceObserver
FB_ForceTorqueFeedForward
```

### Utility/Sensor

```text
FB_LowPassFilter
FB_Debounce
FB_SignalValidity
FB_CommandHandshake
FB_AlarmLatch
```

### Calibration

```text
FB_CollisionReferenceTeach
FB_ForceMeasurementCalibration
FB_DisplacementCalibration
FB_ExtSetpointCommissioning
FB_RAxisCalibration
```

### Quality/Trace

```text
FB_ProcessWindowMonitor
FB_CurveRecorder
FB_ResultAnalyzer
```

## 6. FC对象

```text
FC_ClampLReal
FC_ScaleLinear
FC_LimitRate
FC_TrapezoidIntegrate
FC_RpmToRadPerSec
FC_CalcEnergyIncrement
FC_ConvertDirection
FC_IsFiniteLReal
FC_Interpolate1D
FC_ValidateCalibration
FC_ValidateJoinProgram
FC_GetPrimaryEndCause
FC_CalcStrokeVelocityLimit
FC_CheckModeSourceMatrix
```

## 7. 枚举

至少：

```text
E_OperationMode
E_ControlSource
E_MachineState
E_InitializeState
E_MaintenanceFunction
E_MaintenanceState
E_CffState
E_CffStep
E_StepSubPhase
E_StepPrimaryCriterion
E_SecondaryCriterionAction
E_StepEndCause
E_ZCommandOwner
E_ZExtSetpointState
E_AlarmLevel
E_AlarmCode
E_FastenerStatus
E_FeederState
E_ReturnMode
E_CalibrationState
E_CommandExecutionState
E_CommandRejectReason
E_HmiCommandCode
E_RobotCommandCode
E_ProgramState
E_InterfaceEventState
```

所有枚举显式赋值。

## 8. 结构

至少：

```text
ST_MachineConfig
ST_MachineLimits
ST_ForceCalibration
ST_DisplacementCalibration
ST_CollisionCalibration
ST_ZForceControlProfile
ST_RAxisProfile
ST_StepProceedingConfig
ST_CffStepProgram
ST_JoinProgramHeader
ST_ProcessMonitorProfile
ST_CffJoinProgram
ST_JoiningPointAssignment
ST_CycleSnapshot
ST_ProcessActual
ST_ProcessFeatures
ST_StepCriterionResult
ST_CycleResult
ST_AlarmRequest
ST_AlarmStatus
ST_CommandMailbox
ST_CommandPermission
ST_MaintenanceHoldRequest
ST_RobotCommand
ST_RobotStatus
ST_FeederInput
ST_FeederOutput
ST_CalibrationCommand
ST_CalibrationStatus
ST_FastCommand
ST_FastStatus
ST_CurveSample
```

## 9. GVL

```text
GVL_Const
GVL_IO
GVL_Config
GVL_Calibration
GVL_Program
GVL_Command
GVL_Status
GVL_Process
GVL_Alarm
GVL_HMI
GVL_Trace
GVL_Persistent
GVL_ProjectInfo
```

全部：

```pascal
{attribute 'qualified_only'}
```
