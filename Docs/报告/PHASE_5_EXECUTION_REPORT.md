# Phase 5 Force、位移、S_rel与Collision执行报告

## 目标

在不扫描、不配置和不映射真实硬件的前提下，建立EP3174力输入、外部位移、Collision Reference Sensor、四路Force以及Contact后累计相对位移的可编译处理链。任何人工映射、标定或轴驱动条件缺失时，相应有效位和Production Ready必须保持`FALSE`。

## 创建文件

- `ST_SensorProcessingConfig.TcDUT`：Force四路滤波、范围/延时、位移滤波、Collision去抖和Axis/Sensor差值限值。
- `ST_ProcessReferenceCommand.TcDUT`：Contact参考点`RequestId/Ack`式锁存/清除事务。
- `Test-Phase5SensorProcessing.ps1`：Phase 5结构、语义和硬件边界验收。

## 修改文件

- `GVL_IO`：增加EP3174与位移Error/Overrange/Underrange、Collision Reference Sensor占位，全部仍为`AT %I*`。
- `GVL_Config`：增加`stSensorProcessing`。
- `GVL_Command`：增加`stProcessReference`。
- `ST_ProcessActual`：增加外部位移、`SRelSensor`、`SRelAxis`、`AxisSensorDelta`、`CollisionDelta`、Contact锁存值及独立有效位。
- `PRG_FastInputs`：实现唯一输入处理写入者及5类通用FB实例。
- 人工绑定、I/O TODO、实例所有权和内部接口报告同步更新。

## 处理链

### Force

```text
EP3174 Raw + Error/Overrange/Underrange
→ 人工Mapped状态
→ 标定Revision/Gain/Direction校验
→ 工程力
→ ForceRaw / ForceCriterion / ForceControl / ForceDisplay
```

四路Force来自同一实际力，仅滤波时间常数不同。`ForceDisplay`不用于控制或动态判据。

### 位移与S_rel

外部位移经人工映射、诊断和标定后成为正式工艺主反馈。Contact参考点只在`udiContactReferenceRequestId`变化时锁存一次：

```text
SRelSensor = ExternalDisplacement - ContactSensorPosition
SRelAxis   = NcPosition - ContactAxisPosition
AxisSensorDelta = SRelAxis - SRelSensor
```

四个CFF步骤不重置参考点。外部位移无效时不自动降级为NC位置。

### Collision

Collision有效状态同时依赖人工输入映射、至少3个标定样本、有效Revision和真实Z轴位置。当前`bZAxisDriveLinked=FALSE`，因此Collision和整条过程链有效位保持`FALSE`。

## TDD证据

初始RED报告2个DUT、5个I/O诊断、12个Process字段、11项FastInputs行为、2个GVL契约和报告全部缺失。实现后测试只剩报告闸门失败；补齐本报告后结果为：

```text
Phase 5 sensor processing test: PASSED
Force channels: Raw / Criterion / Control / Display
Relative channels: Sensor / Axis / Delta / Collision
```

Phase 1–4回归测试全部通过。

## Build证据

最终真实XAE结果：

```text
Starting TwinCAT XAE Shell build: TcXaeShell.DTE.15.0
Building project 'CFFwelding_System\CFFwelding_System.tsproj' with 'Release|TwinCAT RT (x64)'.
CFFwelding XAE build: PASSED
Configuration: Release|TwinCAT RT (x64)
LastBuildInfo: 0
```

第一次编译返回4个`';' expected instead of end of POU`。通过同一XAE实例的Error List可访问性树确认位置为首次被Phase 5实际引用的通用POU和`PRG_FastInputs`末尾；统一补齐末语句分号，并在Phase 4/5测试中增加终止符检查后Build通过。没有放宽编译或伪造成功。

## 审查

- 真实I/O配置子节点数量：0。
- NC轴仍未连接AX5000、编码器或仿真驱动。
- 没有Safety配置、Scan、Activate、Download或Runtime登录。
- 代码不写`bForceInputMapped`、`bDisplacementInputMapped`、`bCollisionInputMapped`或`bProductionReady=TRUE`。
- `PRG_FastInputs`是过程实际值唯一写入者；实例均有中文Owner/输入/输出/Reset块注释。
- 凭据模式检查：0。

## 警告与TODO

1. 当前所有传感器输入仍是未映射占位，Build不证明任何物理测量有效。
2. 用户后续必须映射实际PDO并完成Force、Displacement和Collision标定后才可更新Mapped状态。
3. 真实Z轴Adapter尚未实现，`SRelAxis`仅保留接口且不会被当作位移降级源。
4. `ST_SensorProcessingConfig`没有量产默认参数，必须由受控标定/配置流程写入。

## Git状态

- Phase 5主Commit：`5aa37a6f2394f899f4115aebd7f5e25e9b013f22`
- Commit消息：`feat(sensor): add force displacement and collision interfaces`
- Push：GitHub网络不可达，主Commit与本报告Commit保留本地待推送。

## 下一风险

Phase 6将首次实现标准NC Adapter与Z轴Owner。必须保证只有Adapter持有`VAR_IN_OUT AXIS_REF`和MC实例，`PRG_CffSequence`与算法FB不得调用MC。
