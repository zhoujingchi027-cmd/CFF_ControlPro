# PLC ADS契约与WPF预布置 V3.0

## 1. 唯一外部入口

```text
GVL_HMI
```

WPF不得访问：

- FB内部变量；
- AXIS_REF；
- MC实例；
- 物理输出；
- Active Program可写内存；
- 控制器积分内部值。

## 2. Symbol

- `GVL_HMI`使用`qualified_only`；
- PLC Setting启用Symbolic Mapping；
- 公开DTO使用`pack_mode=1`；
- C#未来使用`Pack=1`；
- 内部非ADS对象可按需`TcNoSymbol`；
- 不盲目隐藏Persistent变量。

## 3. ADS Contract

```text
Magic
InterfaceMajor
InterfaceMinor
SchemaCrc
PlcBuild
BootId
AdsPort
TaskPeriods
```

WPF连接后先验证Contract。

## 4. 一次性命令

`ST_AdsCommandRequest`：

```text
CommandId
ClientSessionId
CommandCode
SubCommand
ObjectId
PayloadRevision
LRealParameters
DintParameters
```

`ST_AdsCommandStatus`：

```text
AckCommandId
ActiveCommandId
CompletedCommandId
ExecutionState
RejectReason
MachineState
ResultRevision
```

PLC不清WPF请求字段。

## 5. 应用命令

```text
START
STOP
INITIALIZE
RESET
ACK_RESULT
SELECT_MAINTENANCE
EXECUTE_MAINTENANCE
CANCEL_MAINTENANCE
VALIDATE_STEP
SAVE_STEP
VALIDATE_PROGRAM
SAVE_PROGRAM
ACTIVATE_PROGRAM
SAVE_JOINING_POINT
REQUEST_ALARM_PAGE
REQUEST_CURVE_PAGE
```

## 6. Maintenance Hold

```text
ClientSessionId
Heartbeat
TargetType
TargetId
ActionCode
Enable
Setpoint
```

WPF释放、掉线或Heartbeat超时，PLC撤销动作。

## 7. Command Permission

PLC发布：

```text
CanStart
CanStop
CanInitialize
CanReset
CanSelectMaintenance
CanExecuteMaintenance
CanUseMaintenanceHold
StartInhibitReason
InitializeInhibitReason
ResetInhibitReason
```

## 8. Status Snapshot

至少：

```text
SequenceStart/End
Heartbeat
MachineState
OperationMode
ControlSource
InitializeState
MaintenanceFunction/State
CffState/Step/SubPhase
Ready/Busy/CycleActive/Fault/Nok
ActiveProgram/Revision
JoiningPoint
WeldId
Z Position/Velocity
Force Set/Raw/Criterion/Control
SRelSensor/SRelAxis/Delta
CollisionDelta
RPM Set/Actual
Torque/Power/GrossEnergy/QualifiedEnergy
StepEndCause
Calibration/Sensor validity
Alarm summary
Permissions
```

## 9. Program Transfer

WPF只写Edit Buffer。

```text
RequestId/Ack
ProgramId
ExpectedRevision
ActualRevision
TransferResult
EditProgram
```

Active Program只能由`PRG_ProgramManager`写。

## 10. Joining Point Transfer

固定分页或单对象传输：

```text
JoiningPointNo
ProgramId
ProgramRevision
RequestId/Ack
ValidationResult
```

## 11. Alarm Page

每页最多32条。

```text
RequestId
StartIndex
RequestedCount
Ack
ReturnedCount
TotalCount
Records
```

## 12. Result Snapshot

```text
WeldId
JoiningPoint
Program/Revision
PointNo
Result
PrimaryReason
StepEndCauses
MaxForce
MaxTorque
Gross/QualifiedEnergy
FinalSRel
CycleTime
CurveBufferId
SampleCount
SamplePeriod
```

## 13. Curve Double Buffer

固定：

```text
2 x 4096 samples
```

实际内存占用必须在报告中计算。

FastTask：

- 写当前活动Buffer；
- 不复制给ADS。

Cycle结束：

- 冻结Buffer；
- 生成BufferId；
- 更新CurveReadyRevision。

SlowTask：

- 按页最多256样点复制到`GVL_HMI.stCurvePage`。

禁止1ms逐点ADS Notification。

## 14. Notification策略

只订阅：

```text
StatusRevision
CommandAckId
AlarmRevision
ResultRevision
CurveReadyRevision
PlcHeartbeat
```

收到通知后读取完整结构或页面。

## 15. V4旧代码参考边界

旧`TcAdsClient`、句柄缓存、重连恢复思想可参考。

不得直接复制：

- Pack混用；
- 二维数组；
- 业务模型=二进制DTO；
- Start/Stop共享BOOL；
- 大数组高频通知；
- 通过当前字符串长度写PLC STRING。

未来WPF使用现代`AdsClient`，但本任务不创建WPF代码。

## 16. Stop语义

WPF设备Stop：

```text
CommandId + HMI_CMD_STOP
```

禁止调用：

```text
AdsClient.WriteControl(AdsState.Stop)
```

后者会停止PLC Runtime，导致无法执行受控卸力和状态保存。
