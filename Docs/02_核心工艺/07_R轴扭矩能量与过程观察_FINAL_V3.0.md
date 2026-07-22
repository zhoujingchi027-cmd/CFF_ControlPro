# R轴RPM、Torque、Energy与过程观察 V3.0

## 1. 正式执行

R轴首版使用标准NC速度命令。

只在：

- Cycle开始；
- Step切换；
- Brake；
- Stop/Fault；

发布新运动命令。

不得每FastTask扫描重触发`MC_MoveVelocity`。

## 2. RPM Ramp

配方给出：

```text
SetRPM
RampTime
```

R轴Adapter将其转换为实际NC工程单位和Acceleration/Deceleration。

必须确认：

- 轴单位；
- rpm→轴单位转换；
- 方向；
- 最大速度；
- 最大加减速度。

## 3. Torque

必须确认实际Torque反馈单位和缩放。

未确认前：

```text
bTorqueEngineeringValid = FALSE
```

不得计算正式能量或判定质量。

## 4. Power与Energy

```text
Omega_rad_s = 2 * PI * RPM / 60
Power_W = Torque_Nm * Omega_rad_s
```

### GrossEnergy

从Contact或R轴启动开始全程积分。

### QualifiedEnergy

仅在：

```text
ContactValid
AND RPM >= MinimumQualifiedRpm
AND Force >= MinimumQualifiedForce
AND NOT Braking
AND TorqueValid
```

时积分。

## 5. Step1

允许RPM、Force和Z压入并行建立。

记录：

- RPM达到时间；
- Force达到时间；
- Initial Torque Peak；
- Acceleration Energy。

## 6. Step2

记录：

- Mean Torque；
- Torque RMS；
- Qualified Energy；
- Force RMS；
- SRel Rate。

## 7. Step3

FastTask记录：

- Torque Peak；
- Torque Slope Peak；
- Force Min/Max；
- SRel Rate Peak；
- Step3 Energy；
- RPM drop；
- EndCause。

## 8. Brake

```text
RpmTarget→0
ForceTarget→Step4
```

记录：

- BrakeTime；
- Torque reversal/peak；
- RpmStopped timestamp；
- Force ramp timestamp。

## 9. Material Interface Observer

`FB_MaterialInterfaceObserver`默认：

```text
MonitorOnly
```

输入：

- Force；
- ForceError；
- Torque；
- TorqueResidual；
- dTorque/dt；
- SRel；
- dSRel/dt；
- RPM；
- ZVelocity。

只在理论界面窗口内观察。

输出：

- Candidate；
- Confirmed；
- Confidence；
- EventSRel；
- EventForce；
- EventTorque；
- Timestamp。

不参与正式Step切换，直到完成工艺验证。

## 10. 特征保存

每步骤：

```text
ForceMean/Min/Max/RMS
ForceErrorRMS
ForceTimeInBandRatio
TorqueMean/Min/Max
TorqueRatePeak
RpmMean/Min/Max
SRelStart/End/RatePeak
GrossEnergy
QualifiedEnergy
StepElapsed
QualifiedHold
EndCause
```
