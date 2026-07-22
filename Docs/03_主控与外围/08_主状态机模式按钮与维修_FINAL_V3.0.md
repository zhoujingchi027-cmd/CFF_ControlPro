# 主状态机、模式、WPF按钮和Maintenance V3.0

## 1. Operation Mode与Control Source

```pascal
E_OperationMode:
INVALID
MAINTENANCE
MANUAL
AUTOMATIC
```

```pascal
E_ControlSource:
INVALID
LOCAL
ROBOT
```

合法组合：

| Mode | Source | 用途 |
|---|---|---|
| Maintenance | Local | 标定和测试 |
| Manual | Local | 本地单循环 |
| Automatic | Robot | 机器人自动 |

硬件开关权威。

运行中切换模式：

```text
Controlled Stop
→ MODE_CHANGED_DURING_OPERATION
→ 停止后重新评价
```

## 2. Machine State

```text
BOOT
STOPPED
INITIALIZING
READY
STARTING
RUNNING
MAINTENANCE_ACTIVE
CONTROLLED_STOPPING
CYCLE_COMPLETE
RESETTING
FAULT
```

Mode与MachineState正交。

## 3. WPF正式命令

```text
START
STOP
INITIALIZE
RESET
ACKNOWLEDGE_CYCLE_RESULT
SELECT_MAINTENANCE_FUNCTION
EXECUTE_MAINTENANCE
CANCEL_MAINTENANCE
```

使用：

```text
CommandId
ClientSessionId
CommandCode
SubCommand
ObjectId
PayloadRevision
AckCommandId
ActiveCommandId
CompletedCommandId
ExecutionState
RejectReason
```

## 4. Start

### Manual + Local

启动一个完整单循环。

### Automatic + Robot

WPF Start拒绝；Robot新Sequence Start有效。

### Maintenance + Local

执行当前已选择Maintenance功能。

## 5. Stop

Stop是应用层受控停止。

运行中：

```text
禁止继续向下
→ R轴停止
→ ForceTarget下降
→ Z速度归零
→ External退出
→ Cycle结果Abort/NOK
```

Maintenance中：

- 停止点动；
- 停止送料；
- 停止标定；
- 输出归安全的应用位置。

Stop不是急停或功能安全。

## 6. Initialize

初始化子状态：

```text
INIT_IDLE
INIT_CLEAR_TRANSIENTS
INIT_VALIDATE_MODE_SOURCE
INIT_VALIDATE_COMMUNICATION
INIT_VALIDATE_SENSORS
INIT_RESET_AXIS_ERRORS
INIT_HOME_Z_IF_REQUIRED
INIT_HOME_R_IF_REQUIRED
INIT_STOP_R
INIT_RETURN_Z_REFERENCE
INIT_RETURN_CYLINDERS
INIT_RESET_FEEDER
INIT_VALIDATE_CALIBRATIONS
INIT_VALIDATE_ACTIVE_PROGRAM
INIT_FINAL_READY_CHECK
INIT_COMPLETE
INIT_FAILED
```

Initialize不是Reset，也不是Start。

## 7. Reset

Reset：

- 清允许清除的锁存报警；
- 轴Reset；
- 外围状态机复位；
- 检查故障源已消失；
- 不重启上一个Cycle；
- 不自动Start；
- 不清历史结果。

## 8. 命令权限

| 命令 | Maint+Local | Manual+Local | Auto+Robot |
|---|---:|---:|---:|
| WPF Start | 维修功能 | 单循环 | 拒绝 |
| Robot Start | 拒绝 | 拒绝 | 允许 |
| WPF Stop | 允许 | 允许 | 允许受控停止 |
| Robot Stop | 可拒绝 | 可拒绝 | 允许 |
| WPF Initialize | 允许 | 允许 | 默认拒绝 |
| Robot Initialize | 拒绝 | 拒绝 | 可配置 |
| WPF Reset | 允许 | 允许 | 允许 |
| Robot Reset | 拒绝 | 拒绝 | 允许 |
| Jog/Cylinder | 允许 | 禁止 | 禁止 |

## 9. Maintenance功能

```text
CALIBRATION
MOTION_TEST
FEEDING_TEST
CYLINDER_JOG
LAMP_TEST
IO_DIAGNOSTIC
```

### Calibration

- Home；
- Collision；
- Force；
- Displacement；
- External POC；
- R axis。

### Motion Test

- Z Jog/Home/定位；
- R低速/停止。

### Feeding Test

- 弹夹；
- 直吹；
- 侦钉；
- 多钉。

### Cylinder Jog

- 侦钉气缸；
- 夹具；
- 其他电磁阀。

### Lamp Test

- 红/黄/绿；
- 闪烁。

### IO Diagnostic

- DI/DO；
- 模拟量Raw；
- IO-Link；
- 传感器状态。

## 10. Hold-to-Run

Maintenance Hold Request字段：

```text
ClientSessionId
Heartbeat
TargetType
TargetId
ActionCode
Enable
Setpoint
```

失去心跳、释放按钮、切换模式或出现Fault时立即撤销。

## 11. 按钮权限

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

WPF按钮IsEnabled绑定PLC权限，不自行推断。

## 12. 三色灯

优先级：

```text
Fault → 红闪1s
Stopped → 红常亮
Initializing/Home → 黄闪
Maintenance → 黄常亮
Auto Running → 绿闪1s
Ready → 绿常亮
```
