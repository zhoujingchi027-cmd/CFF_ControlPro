# CFFwelding TwinCAT 3 最终项目总规范 V3.0

## 1. 建设目标

建立一套从零开发、可维护、可在线调试的CFF双轴摩擦元件焊接控制程序。

系统由以下五层组成：

```text
设备主控层
→ Program/模式/命令/外围/报警

工艺状态层
→ Contact、Step1~4、制动、卸力、Return

实时控制层
→ Z导纳力控、External Setpoint、R轴RPM

过程判定与质量层
→ Primary/Secondary、Force/Torque/Energy/Window/Curve

ADS与追溯层
→ GVL_HMI、命令、Program、Alarm、Result、Curve
```

## 2. 控制与质量分离

### 控制层

负责：

- Force跟踪；
- RPM跟踪；
- V/A限幅；
- S_rel边界；
- Hard Force/Stroke；
- External Setpoint生命周期。

### 推进判定层

负责：

- Primary Criterion；
- 条件性Secondary S_rel；
- StepMax；
- EndCause。

### 质量层

负责：

- StepMin；
- ForceReached；
- ForceTimeInBand；
- ForceErrorRMS；
- Torque/Energy窗口；
- Contact位置；
- 过程包络；
- Warning/NOK/Fault；
- 曲线和特征。

禁止把三层合成固定的“大AND条件”。

## 3. 工艺信号

```text
ForceRaw
ForceCriterion
ForceControl
ForceDisplay

SRelSensor
SRelAxis
AxisSensorDelta
CollisionDelta

RpmSet / RpmActual
TorqueActual
Power
GrossEnergy
QualifiedEnergy
```

## 4. 工艺阶段

```text
PRECHECK
APPROACH
EXTSETPOINT_PREPARE
CONTACT_SEARCH
CONTACT_ACCEPT

STEP1_PENETRATION
STEP2_CLEAN_ACTIVATE
STEP3_WELDING
BRAKE_AND_COMPRESSION_RAMP
STEP4_VALID_FORCE_HOLD

CONTROLLED_FORCE_UNLOAD
EXTSETPOINT_DISABLE
RETURN
EVALUATE
```

## 5. 程序运行不可变性

```text
Edit Buffer
→ Save Step
→ Save Program
→ Validate
→ Draft
→ Activate
→ Active Program
→ Cycle Start复制Snapshot
```

运行Cycle只读Snapshot。

## 6. 工程成熟度分级

### M0：源码骨架

- DUT/GVL/PROGRAM/FB/FC；
- 编译；
- 无硬件映射。

### M1：硬件映射

- EtherCAT；
- NC轴；
- EP3174；
- 位移、Collision、IO-Link；
- 机器人和送料IO。

### M2：标定

- 轴；
- 力；
- 位移；
- Collision；
- External Setpoint；
- R轴Torque/Energy。

### M3：受控工艺试验

- 刚性标准块；
- 模拟材料刚度变化的非生产工装；
- 单步骤低能量验证；
- 完整Cycle空载禁止。

### M4：工艺资格

- 真实材料；
- 破坏性/非破坏性试验；
- Program窗口；
- OK/NOK统计；
- 量产资格。

Codex最多能完成M0及部分M1接口，不能声明M4。
