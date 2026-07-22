# CFF四阶段流程与推进准则 V3.0

## 1. 完整状态

```text
IDLE
PRECHECK
APPROACH
EXTSETPOINT_PREPARE
CONTACT_SEARCH
CONTACT_ACCEPT

STEP1_ENTRY
STEP1_RAMP_PROCESS
STEP1_END_CHECK

STEP2_ENTRY
STEP2_RAMP_PROCESS
STEP2_END_CHECK

STEP3_ENTRY
STEP3_RAMP_PROCESS
STEP3_END_CHECK

BRAKE_AND_COMPRESSION_RAMP
STEP4_VALID_FORCE_HOLD

CONTROLLED_FORCE_UNLOAD
EXTSETPOINT_DISABLE
RETURN_LOCAL
RETURN_REFERENCE
EVALUATE
COMPLETE_OK
COMPLETE_NOK
ABORT
FAULT
```

## 2. PRECHECK

必须检查：

- 模式/控制源合法；
- MachineInitialized；
- Z/R Ready；
- Z Home；
- Calibration全部有效；
- 力/位移/Collision有效；
- External Setpoint POC有效；
- Tool/Anvil/Element匹配；
- Active Program和Joining Point有效；
- 机器人位置允许或Local权限；
- 侦钉与送料状态；
- 无Fault；
- 任务周期与SAF一致。

## 3. Contact Search

```text
标准NC到搜索起点
→ Enable External
→ 低速向下
→ ForceCriterion跨过ContactForceOn
→ 锁存候选NC位置和外部位移
→ Force高于ContactForceOff持续Debounce
→ 检查Contact绝对窗口
→ 接受候选
```

接受时：

```text
ContactAxisPosition = 当前候选NC位置
ContactSensorPosition = 当前候选位移
SRelSensor = 0
SRelAxis = 0
```

力PI从当前搜索速度和当前力无扰接管。

## 4. S_rel

```text
SRelSensor =
DirectionScale(
    CurrentExternalDisplacement
    - ContactExternalDisplacement
)
```

```text
SRelAxis =
DirectionScale(
    CurrentNcPosition
    - ContactNcPosition
)
```

阶段步骤共用同一Contact零点。

## 5. Primary Criterion

```pascal
TYPE E_StepPrimaryCriterion :
(
    STEP_CRIT_RELATIVE_DISTANCE := 0,
    STEP_CRIT_STEP_TIME := 10,
    STEP_CRIT_FORCE_DECLINE_TO := 20
);
END_TYPE
```

每步仅一个。

## 6. Secondary Criterion

当Primary不是Relative Distance时：

```text
Secondary必须是累计SRelSensor
```

公开资料未说明精确AND/OR语义，本项目明确配置：

```pascal
TYPE E_SecondaryCriterionAction :
(
    SECONDARY_ADVANCE_AND_NOK := 0,
    SECONDARY_CONTROLLED_EXIT_NOK := 10
);
END_TYPE
```

默认：

- Step1~3：AdvanceAndNok；
- Step4：ControlledExitNok。

Secondary到达后：

- 允许向下速度立刻变0；
- 锁存EndCause；
- 不能继续追力突破边界。

## 7. StepMin/StepMax

### StepMin

质量下限。

Primary已经到达时立即结束，若时间过短：

```text
bTooShort = TRUE
→ Warning或NOK
```

不得继续压入等待StepMin。

### StepMax

Primary等待看门狗。

到时Primary未满足：

```text
EndCause=STEP_END_MAX_TIME
→ NOK或受控退出
```

## 8. Force Decline Observer

### 8.1 参数

```text
SetForce_kN
DeclineTo_kN
ArmForce_kN
Hysteresis_kN
MinimumDeclineRate_kN_s
DebounceTime
CriterionSRelMin/Max
CriterionRpmMin
CaptureMaxVelocity
SecondarySRel
```

### 8.2 流程

```text
步骤进入
→ 等待ForceCriterion达到ArmForce
→ Armed
→ 监视向下跨越DeclineTo
→ dForce/dt负
→ RPM/S_rel窗口有效
→ Debounce
→ Primary成立
```

### 8.3 PI行为

Decline确认前：

- PI继续保持SetForce；
- 可在接近Decline阈值时降低最大追力速度；
- 仍受所有位移和硬边界限制。

确认后：

- 立即结束当前步骤；
- 不追回旧SetForce；
- 使用下一Profile无扰切换。

## 9. Step1

Contact接受后并行：

```text
RPM Ramp
Force Ramp
Z导纳下压
StepTime
```

记录：

- ForceReachTime；
- RpmReachTime；
- 初始TorquePeak；
- SRel；
- EndCause。

## 10. Step2

典型：

```text
RPM平台
Force平台
S_rel缓慢推进
Torque清理平台
```

Torque/Energy作为质量监控。

## 11. Step3

所有判定在FastTask。

记录：

- TorquePeak；
- dTorque/dt；
- ForceMin/Max；
- SRelRate；
- Step3Energy；
- EndCause。

## 12. Brake与Step4

Step3结束：

```text
RpmTarget → 0
ForceTarget → Step4Force
```

允许Ramp重叠。

Step4有效保持时间：

```text
IF RpmStopped AND ForceInBand THEN
    QualifiedForceHold += Ts
END_IF
```

步骤时间和有效保持时间分别记录。

Primary StepTime满足但有效保持不足：

```text
完成卸力
→ Cycle NOK
```

## 13. EndCause

```text
PRIMARY_RELATIVE_DISTANCE
PRIMARY_STEP_TIME
PRIMARY_FORCE_DECLINE
SECONDARY_RELATIVE_DISTANCE
MAX_TIME
HARD_FORCE
HARD_STROKE
SENSOR_INVALID
AXIS_FAULT
STOP_REQUEST
```

每个步骤结果必须保存EndCause。

## 14. Program校验

- Primary枚举有效；
- Time/Decline必须有Secondary；
- DeclineTo < SetForce；
- ArmForce > DeclineTo + Hysteresis；
- Debounce > 0；
- 累计S_rel单调；
- StepMin <= StepMax；
- Step4 Secondary >= Step3结束边界；
- 力/RPM/Profile/Monitor ID有效；
- 所有值低于机器硬限值。
