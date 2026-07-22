# Z轴导纳力控与External Setpoint V3.0

## 1. 力信号

```text
ForceRaw
    硬过力、高速曲线

ForceCriterion
    极轻滤波，Contact和Force Decline

ForceControl
    低延迟滤波，导纳PI

ForceDisplay
    慢滤波，HMI
```

禁止使用ForceDisplay做控制或动态判据。

## 2. 导纳控制

```text
eF = ForceSetRamped - ForceControl

Vunsat =
Vff
+ Kp * eF
+ Integral
```

```text
IntegralDot =
Ki * eF
+ Kaw * (Vsat - Vunsat)
```

## 3. 输出限制顺序

```text
PI未饱和输出
→ Profile速度限幅
→ 上抬速度限幅
→ S_rel制动限速
→ Secondary/Hard边界
→ Collision边界
→ 速度变化率/加速度限幅
→ External轨迹
```

## 4. S_rel制动

```text
SRemain = TargetSRel - SRelSensor
```

```text
Vstroke =
sqrt(
    2 * MaxDeceleration
    * max(SRemain - BrakeMargin, 0)
)
```

向下速度上限取所有限制最小值。

到达边界：

```text
MaxDownVelocity = 0
```

## 5. Anti-windup冻结条件

- Sensor invalid；
- Axis owner不是ForceProcess；
- External未Active；
- Hard Force；
- Hard S_rel；
- 向下边界到达且误差要求继续向下；
- Fault/Stop退出。

## 6. Contact无扰接管

Contact接受时：

```text
ForceSetRampedStart = 当前ForceControl
```

积分初始化使：

```text
PI输出 ≈ 当前Contact Search速度
```

## 7. Profile无扰切换

新Profile积分：

```text
Inew =
PreviousVelocityCmd
- NewVff
- NewKp * (NewForceSetStart - ForceActual)
```

所有Kp/Ki、ForceSet、V/A、Filter、TorqueOffset切换均使用Ramp或无扰初始化。

## 8. Standard NC与External分工

### Standard NC

- Home；
- Manual Jog；
- Approach；
- Return；
- Maintenance定位；
- Reset/Stop。

### External

- Contact Search；
- Step1；
- Step2；
- Step3；
- Brake/Compression Ramp；
- Step4；
- Controlled Unload。

整个Cycle只切换：

```text
Standard NC → External → Standard NC
```

## 9. External状态机

```text
IDLE
PRECHECK
PRELOAD_DIRECTION
PREFEED_INITIAL
ENABLE
WAIT_ENABLED
ACTIVE
RAMP_TO_ZERO
HOLD_DIRECTION
DIRECTION_ZERO
DISABLE
WAIT_DISABLED
POST_DISABLE_HOLD
DONE
ERROR
```

### Enable前

从当前NC设定轨迹预置：

```text
Pext = Current NC SetPos
Vext = Current NC SetVelo
Aext = Current NC SetAcc
Direction = Planned Direction
```

Codex必须读取实际NCTOPLC字段，不能假设字段名。

### Active

```text
Vext = RateLimited(Vcmd)
Aext = (Vext - Vprev) / Ts
Pext = Pprev + 0.5 * (Vprev + Vext) * Ts
```

每个SAF同步周期调用Feed。

### Disable

```text
ForceTarget受控下降
→ Vcmd归零
→ 轴进入Standstill窗口
→ 保持最后非零Direction至少1个SAF
→ Direction=0并静止Feed至少1个SAF
→ Disable
→ 等待Disabled
→ 再等至少1个SAF
→ 释放Owner
→ Standard Return
```

## 10. AxisCommandArbiter

Owner：

```text
NONE
HOME
MANUAL
APPROACH
FORCE_PROCESS
RETRACT
FAULT_STOP
```

优先级：

```text
FAULT_STOP
> FORCE_PROCESS受控退出
> HOME/SERVICE
> RETRACT
> APPROACH
> MANUAL
> NONE
```

## 11. TorqueOffset可选扩展

首版：

```text
Disabled
```

启用前必须确认：

- 实际Tc2_MC2存在WithTorque接口；
- AX5000和NC支持；
- Torque单位；
- Mapping；
- Limit/Rate；
- 实机A/B测试。

第一版扩展只允许：

```text
ForceSet→TorqueFeedForward
```

不加入独立Torque积分。

导纳速度和S_rel边界仍保留。

## 12. 关键诊断

- Enable/Disable timeout；
- P/V/A不连续；
- Direction invalid；
- External与标准NC冲突；
- Task/SAF mismatch；
- Following error；
- Force sensor invalid；
- SRel sensor invalid；
- AxisSensorDelta超限；
- Hard force/stroke；
- Collision margin。
