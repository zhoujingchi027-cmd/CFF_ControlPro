# 数据所有权、单一写入者与命令邮箱 V3.0

## 1. 单一写入者

| 资源 | 唯一写入者 |
|---|---|
| Z轴MC功能块 | `FB_ZAxisNcAdapter` / `FB_ZAxisExtSetpointAdapter`受Arbiter控制 |
| R轴MC功能块 | `FB_RAxisNcAdapter` |
| Z轴Owner | `FB_AxisCommandArbiter` |
| CffState | `PRG_CffSequence` |
| MachineState | `PRG_MachineMain` |
| OperationMode/ControlSource | `PRG_ModeControl` |
| Active Program/Snapshot | `PRG_ProgramManager` |
| InitializeState | `PRG_InitializeControl` |
| MaintenanceState | `PRG_MaintenanceControl` |
| 报警锁存 | `PRG_AlarmControl` |
| 三色灯输出 | `PRG_TowerLightControl` |
| 送料输出 | `PRG_FeederControl` |
| 夹具输出 | `PRG_ClampControl` |
| GVL_HMI公开结构 | `PRG_HmiAdsInterface` |
| 结果记录 | `PRG_ResultTraceability` |

## 2. Main→Fast邮箱

```text
ST_FastCommand
RequestId
AcceptedId
CycleSnapshotRevision
```

MainTask：

- 完整填写命令；
- 最后递增RequestId。

FastTask：

- 发现RequestId变化；
- 原子复制完整命令到本地；
- 校验Revision；
- 更新AcceptedId。

不得跨任务零散读取多个会变化的字段。

## 3. HMI→Main邮箱

SlowTask `PRG_HmiAdsInterface`：

```text
ADS Request
→ 检查Contract/Session
→ 复制到ST_CommandMailbox
→ MailboxRequestId++
```

MainTask `PRG_CommandDispatcher`：

```text
MailboxRequestId变化
→ 复制
→ 验证
→ 内部Pulse
→ 更新Ack/ExecutionState/RejectReason
```

## 4. Robot→Main邮箱

`PRG_RobotInterface`将机器人输入转换为：

```text
RobotCommandId
RobotCommandCode
JoiningPointNo
Sequence
```

再交给`PRG_CommandDispatcher`。

HMI和Robot不直接写MachineState。

## 5. 命令优先级

```text
FaultStop
> Stop
> Reset
> Initialize
> Start
> Program/Configuration
> Maintenance selection
```

Stop命令必须能中断：

- 初始化；
- Maintenance测试；
- Manual Cycle；
- Auto Cycle。

Stop不是安全急停。

## 6. 正式一次性命令

外部接口：

```text
CommandId/Ack
```

PLC内部：

```text
bStartPulse
bStopPulse
bInitializePulse
bResetPulse
```

每个MainTask扫描开头清FALSE。

不得让WPF和PLC同时写一个BOOL。

## 7. Hold-to-Run

适用：

- Z Jog+/Jog-；
- R低速点动；
- 气缸伸出/缩回；
- 手动送料保持。

请求结构包含：

```text
ClientSessionId
Heartbeat
TargetType
TargetId
ActionCode
Enable
Setpoint
```

PLC采纳条件：

```text
Maintenance
AND Local
AND 无Cycle
AND 权限允许
AND Heartbeat新鲜
AND Enable
```

任一条件失效立即撤销输出。

## 8. 任务间时间戳

高速事件记录：

```text
FastTaskCycleCounter
DcTimestamp（若实际系统可用）
```

Main/Slow只复制，不自行伪造Fast时间。
