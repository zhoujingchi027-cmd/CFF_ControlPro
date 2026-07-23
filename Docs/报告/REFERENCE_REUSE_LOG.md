# 旧工程只读参考与复用记录

## 记录原则

旧工程仅可用于核对工程约定和 TwinCAT 文件结构，不得整目录复制 PLC 对象，不得把旧硬件映射、业务逻辑、参数或地址带入新工程。所有新对象均在 `倍福CFF控制` 内独立创建，并以当前 V3.3 任务书和 Beckhoff 官方文档为准。

## Phase 0～2

未从旧工程复制 PLC 对象或业务逻辑。Phase 0 的只读文件摘要和边界证据见对应执行报告。

## Phase 3

| 只读来源 | 参考目的 | 实际采用的信息 | 明确未复用内容 |
|---|---|---|---|
| `../CFF_TwinCAT3/CFF_System.tsproj` | 在官方 `LinkVariables` 文档给出通用 API 后，核对本机 TwinCAT 3.1.4024 系统工程中 NC 整结构链接的序列化路径格式 | 仅确认映射使用 PLC 实例 `OwnerA`、NC 轴 `OwnerB`，以及相对端点 `Inputs^FromPlc`、`Outputs^ToPlc`；新工程随后通过自身 Automation Interface `TestItemPath` 验证实际完整路径 | 未复制旧轴名称、PLC 变量名、硬件配置、I/O、任务参数、轴参数、业务逻辑或任何真实 PDO 链接 |
| `../SPR重庆发货/.../*.tsproj`、`../FDS_PLC/.../*.tsproj` 等 `rg` 只读命中行 | 交叉确认 TwinCAT 的 `<Mappings>/<OwnerA>/<OwnerB>/<Link>` 是通用序列化结构 | 未直接采用文件内容；只用于排除自定义/偶然格式的可能性 | 未打开或复制其中 PLC 源、设备拓扑、地址、驱动参数和机器逻辑 |

Phase 3 新工程中的 `NC_Cff SAF`、`Z_Axis_NC`、`R_Axis_NC`、`GVL_IO.Z_axis/R_axis`、2 ms 周期同步及四条内部链接均由本仓库脚本独立创建和验证。没有创建旧工程中的 AX5000、EP3174、EtherCAT 或 Safety 配置。
