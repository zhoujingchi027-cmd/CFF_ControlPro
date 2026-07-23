# Phase 3 NC 配置检查表

## 1. 当前离线配置基线

| 项目 | 当前值 | 结论 |
|---|---:|---|
| NC 任务 | `NC_Cff SAF` | 已创建，离线工程对象 |
| SAF 优先级 | `4` | XAE 创建时的离线默认值；上线前需做实时性评审 |
| SAF 周期 | `20000 × 100 ns = 2 ms` | 已作为 Fast 任务周期唯一来源 |
| SVB 周期 | `100000 × 100 ns = 10 ms` | XAE 创建时的离线默认值；上线前需评审 |
| PLC `Task_CffFast` | 优先级 `10`，周期 `2000 us` | 已与 SAF 周期同步 |
| NC 轴 | `Z_Axis_NC`、`R_Axis_NC` | 已创建，均未绑定真实驱动/编码器 |
| I/O 配置 | 无设备节点 | 未扫描、未创建；仅可能存在 XAE 自动序列化的空 `<Io/>` 容器 |
| Safety 配置 | 无 | 未创建 TwinSAFE 项目 |

## 2. PLC↔NC 内部循环接口

- [x] `Task_CffFast Inputs^GVL_IO.Z_axis.NcToPlc` ↔ `Z_Axis_NC^Outputs^ToPlc`
- [x] `Task_CffFast Outputs^GVL_IO.Z_axis.PlcToNc` ↔ `Z_Axis_NC^Inputs^FromPlc`
- [x] `Task_CffFast Inputs^GVL_IO.R_axis.NcToPlc` ↔ `R_Axis_NC^Outputs^ToPlc`
- [x] `Task_CffFast Outputs^GVL_IO.R_axis.PlcToNc` ↔ `R_Axis_NC^Inputs^FromPlc`

内部链接使用 Beckhoff `AXIS_REF` 的整结构过程映像，未逐字段拼接。轴的默认 Encoder/Drive 对象没有映射到任何物理设备，也没有添加仿真驱动。

## 3. Phase 3 自动检查

- [x] 轴名称集合严格为 `Z_Axis_NC`、`R_Axis_NC`。
- [x] PLC Fast 任务、系统 Fast 任务和 PLC 实例上下文均与 SAF 周期一致。
- [x] 四条 AXIS_REF 内部链接位于 `Task_CffFast` 过程映像。
- [x] 系统工程没有 I/O 设备节点或 `<Safety>` 配置段。
- [x] 系统工程没有 AX5000、EP3174、TwinSAFE 或仿真驱动配置。
- [x] XAE `Release|TwinCAT RT (x64)` 构建可通过；最终证据以 Phase 3 执行报告为准。

## 4. 真实 Z 轴上线 TODO

- [ ] 确认轴类型、控制器、驱动和编码器类型与批准硬件完全一致。
- [ ] 设置编码器缩放、机械传动、工程单位和位置方向。
- [ ] 设置位置、速度、加速度、减速度、跃度及软限位。
- [ ] 配置参考点、硬限位、原点和必要的触发输入。
- [ ] 配置驱动使能、制动器、故障复位和状态字映射。
- [ ] 验证 `FromPlc/ToPlc` 整结构链接仍唯一且处于 Fast 任务上下文。
- [ ] 低速验证反馈方向、停止距离和外部设定值异常退出。

## 5. 真实 R 轴上线 TODO

- [ ] 确认轴类型、驱动、编码器、传动比和工程单位。
- [ ] 设置速度/加减速/扭矩限制和必要的模数参数。
- [ ] 配置驱动使能、故障复位、实际转速和实际扭矩映射。
- [ ] 验证 `FromPlc/ToPlc` 整结构链接仍唯一且处于 Fast 任务上下文。
- [ ] 低速空载验证方向、转速、扭矩和停止行为。

## 6. 实时性与发布 TODO

- [ ] 根据目标 IPC/CX、CPU 核分配和最终 I/O 更新时序评审 SAF/SVB/PLC 优先级。
- [ ] 记录 Fast 任务最大执行时间、抖动和超时裕量；禁止仅凭默认值发布。
- [ ] 验证 I/O 更新发生在正确任务边界，NC 与 PLC 周期计数连续。
- [ ] 在更改 SAF 周期时先运行 `Sync-CffweldingPhase3FastTask.ps1`，然后重新构建并复查映射。
- [ ] 任何真实驱动/编码器链接必须经过双人复核、低能量测试和变更记录。
- [ ] 激活、下载和运行时登录不属于 Phase 3，必须在单独授权的上线步骤中执行。
