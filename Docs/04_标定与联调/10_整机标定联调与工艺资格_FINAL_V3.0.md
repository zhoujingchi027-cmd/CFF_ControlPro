# 整机标定、联调和工艺资格 V3.0

## 1. 标定层级

```text
机器轴标定
传感器标定
工具/砧座/元件配置
External Setpoint POC
控制Profile整定
工艺Program资格
```

## 2. Z轴NC

- mm缩放；
- 向下正负；
- Home重复性；
- 正负极限；
- 软限位；
- Approach；
- Return；
- Following Error；
- External缩放；
- Collision范围。

## 3. R轴NC

- 方向；
- RPM缩放；
- 最大RPM；
- Acc/Dec；
- Torque单位；
- Stop阈值；
- BrakeTime。

## 4. 位移窗口碰撞点标定

本项目没有Collision IO传感器。

标定使用：

```text
外部位移传感器实际值
+
Z轴NC实际位置
```

流程：

```text
Maintenance+Local
→ Z Home
→ 外部位移有效
→ 移动到安全接近位置
→ 确认位移在碰撞窗口外
→ 固定方向低速接近
→ 位移进入[WindowMin, WindowMax]
→ 速度/方向合格并持续Debounce
→ 锁存位移和NC位置
→ 退回
→ 重复N次
→ 评估位移/轴位置极差
→ 保存Calibration Revision
```

运行时：

```text
CollisionDistanceSensor =
ReferenceDisplacement - CurrentDisplacement

CollisionDistanceAxis =
ReferenceAxisPosition - CurrentAxisPosition
```

方向由配置统一转换。

位移距离为主，NC距离为冗余。

不得使用Home、Limit、Force Contact或固定理论值替代碰撞参考。

## 5. 力测量链



```text
4574A→4709A→EP3174
```

### 5.1 机械检查

- 受力经过传感器内外承载带；
- 承压面硬度/平面/平行；
- 无轴向旁路；
- 避免侧向力；
- 电缆不受拉弯；
- 精确型号、量程、序列号和灵敏度记录。

### 5.2 EP3174电压验证

标准源：

```text
0 / 1 / 2 / 5 / 8 / 10 V
```

确认：

- 通道类型；
- Extended/Legacy Range；
- RawAt10V；
- Error/Over/Under；
- Filter。

### 5.3 整机参考力验证

首台样机建议：

```text
0 / 1 / 3 / 5 / 7 / 9 kN
上升与下降
```

例行简化：

```text
0 / 3 / 6 / 9 kN
```

加载方法：

- Z低速微位移逐渐施力；
- 独立参考力传感器决定真实力；
- Torque Limit仅保护，不作为精确力设定。

### 5.4 结果

```text
RawZero
Gain
Offset
Direction
Residual
Hysteresis
Repeatability
ZeroReturn
Noise
Delay
CalibrationValid
```

## 6. 外部位移

参考标准：

- 千分表；
- 激光位移；
- 精密位移台。

点位：

```text
0 / 2 / 4 / 6 / 8 / 10 mm
上升与下降
```

验证：

- Raw→mm；
- 方向；
- 线性；
- 滞后；
- 重复性；
- 有效范围；
- 动态延迟；
- Contact后剩余量程。

## 7. Contact不是维修标定

Contact Point每个Cycle动态检测。

仅标定：

- ContactForceOn/Off；
- Debounce；
- Search Velocity；
- Expected Window；
- Repeatability。

## 8. External Setpoint POC

刚性工装、低速、低行程：

```text
Enable
+0.1 mm/s
0
-0.1 mm/s
0
+0.5 mm/s
Ramp to zero
Disable
Standard Return
```

验证：

- 无位置跳变；
- 方向；
- P/V/A一致；
- 速度比例；
- Disable；
- Owner冲突；
- SAF周期。

## 9. Force Controller整定

顺序：

```text
1. Ki=0
2. 低力刚性工装
3. 增Kp
4. 加Ki
5. 加Kaw/积分限幅
6. 加V/A/SRel制动
7. 软硬刚度工装
8. 每阶段独立Profile
9. Force Decline捕获
10. Step4
```

## 10. Force↔Motor能力

在参考加载中记录：

```text
ReferenceForce
ActTorque
MotorCurrent
ZPosition
```

用于：

- Torque Limit；
- 力达不到；
- 卡滞；
- 后续TorqueFeedForward。

不替代Force Sensor。

## 11. 试运行门槛

```text
ZCalValid
RCalValid
ForceCalValid
DisplacementCalValid
CollisionCalValid
ExtPocValid
ProfileValid
ProgramValid
ToolElementMatch
SensorsValid
```

## 12. 工艺资格

PLC曲线OK不等于焊点机械性能OK。

量产Program需结合：

- 外观；
- 截面；
- 剥离；
- 剪切；
- 统计；
- 材料批次；
- 工具磨损；

建立窗口。

不得自动把示例参数视为量产参数。
