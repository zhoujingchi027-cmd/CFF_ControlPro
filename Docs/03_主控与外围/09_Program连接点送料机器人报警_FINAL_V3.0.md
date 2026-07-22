# Program、Joining Point、送料、机器人和报警 V3.0

## 1. Program Header

至少：

```text
ProgramId
ProgramName
UpperThickness / Tolerance
LowerThickness / Tolerance
SupportPlateThickness
ElementType
StepCount=4
PreStrokeSpeed
Contact/StartingForce
ReturnMode
ReferenceReturnSpeed
LocalReturnSpeed
OpeningSize
ForceProfileId
RAxisProfileId
MonitorProfileId
ToolId
AnvilId
Revision
```

## 2. Step Program

每步：

```text
SetForce
SetRPM
RampTime
PrimaryCriterion
PrimarySRel
PrimaryStepTime
ForceDeclineTo
ForceDeclineArm
ForceDeclineHysteresis
MinimumDeclineRate
DeclineDebounce
SecondarySRel
SecondaryAction
StepMin
StepMax
Force/RPM/Torque/Energy监控窗口
```

## 3. Save语义

```text
Edit Step
→ Validate Step
→ Save Step到Program Draft

Edit Header
→ Save Program Header

Validate Program
→ Draft Valid

Activate Program
→ Active Revision
```

Save Step和Save Program必须分开。

## 4. Joining Point

```text
JoiningPointNo
→ ProgramId
→ ProgramRevision
```

规则：

- JoiningPoint唯一；
- Program必须存在；
- 新建/覆盖需要权限；
- Robot发送JoiningPoint；
- PLC锁存AcceptedPoint；
- Cycle Snapshot保存Point和Program。

## 5. Program存储

PLC阶段使用固定容量结构。

建议常量：

```text
MAX_PROGRAMS = 128
MAX_JOINING_POINTS = 256
MAX_CFF_STEPS = 4
```

实际容量由内存和需求确认。

不实现PLC文件数据库。

`PRG_Persistence`只负责：

- PERSISTENT/RETAIN接口；
- Save/Load请求；
- 版本检查；
- 冷启动完整性。

## 6. Cycle Start

```text
解析命令来源
→ JoiningPoint/Program
→ Validate Active Revision
→ Copy Cycle Snapshot
→ Snapshot CRC/Revision
→ PRECHECK
```

Auto无有效Point拒绝启动。

Manual无选定Program时，只能经人工确认使用Default，并记录。

## 7. 侦钉与送料

```text
首次侦钉
→ 单钉且类型匹配：Ready
→ 无钉：按Mode送料
→ 再次侦钉
→ 多钉：Fault
→ 无钉/卡钉/超时：Fault
```

送料模式：

```text
CASSETTE
DIRECT_BLOW
```

## 8. Robot接口

命令：

```text
RobotReady
PositionOK
StartSequence
StopSequence
InitializeSequence
ResetSequence
JoiningPointNo
Abort
Heartbeat
```

状态：

```text
MachineReady
Busy
Complete
OK
NOK
Fault
AcceptedJoiningPoint
AcceptedProgram
WeldId
RejectReason
```

必须使用Sequence/Ack防重复。

## 9. Clamp接口

结构化：

```text
ST_ClampInput
ST_ClampOutput
ST_ClampStatus
```

实际PDO未确认时保留TODO，不填假值。

## 10. 报警分级

```text
Warning
NOK
Fault
```

### Warning

轻微偏差，可继续。

### NOK

焊点质量无效，但设备可受控完成/退出。

### Fault

轴、传感器、硬边界、通信或设备故障，必须停止或受控退出。

## 11. 报警范围

```text
1000 系统
1100 模式/命令
1200 Program/Point
2000 Z轴
2100 R轴
2200 External
2300 Force
2400 Displacement/Collision
3000 Contact/CFF
3100 Criterion
4000 Fastener/Feeder
5000 Robot/Clamp/IO-Link
6000 ADS/Trace
```

## 12. Fault恢复

可受控：

```text
禁止继续向下
→ R轴停止
→ Z卸力
→ External退出
→ Fault锁存
```

不可受控：

```text
标准MC Stop/Halt
→ Fault锁存
```

Reset前检查源故障消失。

上次断电时CycleActive：

```text
结果=Abort
禁止自动续焊
```
