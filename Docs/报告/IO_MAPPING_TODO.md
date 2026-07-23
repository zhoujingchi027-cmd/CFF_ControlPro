# Phase 3 I/O 映射 TODO

## 1. 状态说明

`GVL_IO` 中除 PLC↔NC 内部 `AXIS_REF` 外，全部变量仍为未映射占位符。`AT %I*`/`AT %Q*` 只让 TwinCAT 分配过程映像位置，不表示已经连接到物理端子。Phase 3 没有创建或扫描任何 I/O 设备，也没有把变量链接到旧工程硬件。XAE 为映射基础设施自动序列化的空 `<Io/>` 容器不含任何设备或通道。

## 2. 运动控制内部映射

| PLC 变量 | NC 端点 | 当前状态 | 生产硬件状态 |
|---|---|---|---|
| `GVL_IO.Z_axis.PlcToNc` | `Z_Axis_NC / Inputs / FromPlc` | 已完成内部链接 | 驱动未绑定 |
| `GVL_IO.Z_axis.NcToPlc` | `Z_Axis_NC / Outputs / ToPlc` | 已完成内部链接 | 编码器未绑定 |
| `GVL_IO.R_axis.PlcToNc` | `R_Axis_NC / Inputs / FromPlc` | 已完成内部链接 | 驱动未绑定 |
| `GVL_IO.R_axis.NcToPlc` | `R_Axis_NC / Outputs / ToPlc` | 已完成内部链接 | 编码器未绑定 |

这四条链接只是 PLC 与离线 NC 的内部循环接口。它们不能用于证明轴能够运动，也不能让 `bZAxisDriveLinked`、`bRAxisDriveLinked` 或生产就绪状态变为 `TRUE`。

## 3. 输入占位符

| 变量 | 类型 | 预期信号 | 当前状态 | 人工映射与验证 TODO |
|---|---|---|---|---|
| `nForceChannelRaw` | `INT AT %I*` | 力传感器原始量 | 未映射 | 核对模块/通道、量程、符号、断线和过量程；完成多点标定 |
| `bForceChannelError/Overrange/Underrange` | `BOOL AT %I*` | EP3174通道诊断 | 未映射 | 按实际PDO逐项映射，验证断线、上溢、下溢和滤波配置 |
| `nDisplacementChannelRaw` | `INT AT %I*` | 位移传感器原始量 | 未映射 | 核对模块/通道、方向、量程和诊断；完成位移标定 |
| `bDisplacementChannelError/Overrange/Underrange` | `BOOL AT %I*` | 位移通道诊断 | 未映射 | 按实际传感器接口映射并验证边界与断线行为 |
| `bCollisionReferenceSensor` | `BOOL AT %I*` | Collision Reference Sensor | 未映射 | 核对常态电平、断线行为、机械触发点和去抖时间；用于标定与运行诊断 |
| `bCollisionDetected` | `BOOL AT %I*` | 早期保留占位 | 未映射/不使用 | 后续电气接口冻结时删除或重新定义，不得替代Collision Reference Sensor |
| `bFastenerPresent` | `BOOL AT %I*` | 紧固件在位 | 未映射 | 核对传感器极性、抖动、卡料和空料场景 |
| `bFeederReady` | `BOOL AT %I*` | 供料器就绪 | 未映射 | 核对通信/电气接口、故障时状态和超时行为 |
| `bClampClosed` | `BOOL AT %I*` | 夹紧到位 | 未映射 | 核对两位置信号一致性、失压和机械不到位场景 |
| `bRobotPermit` | `BOOL AT %I*` | 机器人许可 | 未映射 | 核对握手协议、控制源和许可撤销时序 |

## 4. 输出占位符

| 变量 | 类型 | 预期信号 | 当前状态 | 人工映射与验证 TODO |
|---|---|---|---|---|
| `bFeedRequest` | `BOOL AT %Q*` | 供料请求 | 未映射/默认假 | 执行机构隔离后核对通道、极性、脉冲/保持协议和取消时序 |
| `bClampRequest` | `BOOL AT %Q*` | 夹紧请求 | 未映射/默认假 | 核对阀岛通道、失电状态、互锁和超时反应 |
| `bRobotReady` | `BOOL AT %Q*` | 机器人就绪 | 未映射/默认假 | 核对握手版本、允许条件和故障撤销时序 |
| `bTowerRed` | `BOOL AT %Q*` | 红色塔灯 | 未映射/默认假 | 核对通道和报警优先级显示 |
| `bTowerYellow` | `BOOL AT %Q*` | 黄色塔灯 | 未映射/默认假 | 核对通道和维护/等待状态显示 |
| `bTowerGreen` | `BOOL AT %Q*` | 绿色塔灯 | 未映射/默认假 | 核对通道；生产就绪未成立时不得误亮 |

## 5. 映射实施规则

1. 仅依据已批准的电气图纸和 I/O 清单人工创建配置，不执行设备扫描。
2. 每个过程变量必须有唯一物理来源或目标；禁止复用旧工程的未知映射。
3. 映射前核对数据类型、位宽、端序、比例、工程单位、方向和故障默认值。
4. 输出第一次测试前隔离执行机构；禁止用强制输出跨越安全链。
5. 每完成一个通道，记录端子、通道、变量、图纸页码、测试方法、结果、人员和时间。
6. 未完成证据复核前，对应 `ST_HardwareBindingStatus` 字段保持 `FALSE`。
7. 最终映射必须导出并与 Git 提交及硬件配置基线一起归档。
