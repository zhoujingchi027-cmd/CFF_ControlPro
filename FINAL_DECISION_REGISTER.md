# CFFwelding 最终设计决策登记表 V3.3

本文件是冲突规则的最高优先级裁决表。

| 编号 | 决策 | 最终结论 |
|---|---|---|
| D-001 | 新建还是改旧工程 | 新建`倍福CFF控制/CFFwelding`；旧工程只读 |
| D-002 | 安全程序 | 不创建TwinSAFE；标准PLC不声明安全功能 |
| D-003 | 仿真 | 不创建Plant、虚拟轴或虚拟传感器 |
| D-004 | Z轴实际力 | Kistler 4574A→4709A→EP3174 |
| D-005 | 工艺位移 | 12 mm外部位移传感器为`SRelSensor`主值 |
| D-006 | NC位置 | 用于运动、软限位、Collision和冗余诊断 |
| D-007 | Z轴正式力控 | 导纳PI输出动态速度 |
| D-008 | Z轴动态执行 | Tc2_MC2 External Setpoint；实际API必须现场确认 |
| D-009 | 纯扭矩控制 | 首版禁止 |
| D-010 | TorqueOffset | 可选前馈扩展，默认关闭，需实机验证 |
| D-011 | R轴 | RPM控制；Torque/Energy监控 |
| D-012 | S_rel零点 | 每周期Contact接受时清零一次；步骤间不清零 |
| D-013 | Primary Criterion | Relative Distance / Step Time / Decline of Force To |
| D-014 | Secondary | Time或Decline时必须为累计S_rel |
| D-015 | Secondary精确原厂语义 | 公开资料未明确；本项目配置触发动作并记录EndCause |
| D-016 | Force Decline期间PI | 确认前继续跟随；确认后无扰切换下一Profile |
| D-017 | StepMin | 质量下限，不允许继续突破几何边界 |
| D-018 | Torque/Energy推进 | EJOT兼容模式默认不作为强制Primary |
| D-019 | Step1启动 | RPM、Force和Z压入并行Ramp |
| D-020 | Step3→Step4 | 制动和Compression Force Ramp允许重叠 |
| D-021 | Step4有效保持 | 仅在RpmStopped且ForceInBand时累计 |
| D-022 | 操作模式 | Maintenance / Manual / Automatic |
| D-023 | 控制源 | Local / Robot |
| D-024 | 合法组合 | Maintenance+Local；Manual+Local；Automatic+Robot |
| D-025 | Test Mode | 不单独创建；合并到Maintenance |
| D-026 | 模式来源 | 硬件开关权威；WPF只读 |
| D-027 | Start/Stop/Init/Reset | ADS CommandId/Ack，不用共享BOOL清零 |
| D-028 | PLC内部命令 | 已接受事务转为单扫描Pulse |
| D-029 | 维修点动 | Hold-to-Run BOOL + Session + Heartbeat |
| D-030 | WPF Stop | 应用层受控停止，不调用ADS WriteControl停止Runtime |
| D-031 | Program保存 | Save Step与Save Program分开 |
| D-032 | 运行配方 | Draft / Active / Cycle Snapshot分开 |
| D-033 | Robot选程序 | JoiningPointNo唯一映射Program |
| D-034 | ADS入口 | WPF只访问`GVL_HMI` |
| D-035 | ADS曲线 | PLC双缓冲，完成后分页读取，不逐点通知 |
| D-036 | 源码结构 | 流程PROGRAM；算法/Adapter FB；纯计算FC |
| D-037 | 注释 | 英文标识符，关键内容中文独立行注释，UTF-8 |
| D-038 | Build声明 | 必须有真实XAE证据 |
| D-039 | 中文注释范围 | GVL/DUT/FB接口、实例声明、状态五要素、关键算法和硬边界必须中文独立行注释 |
| D-040 | 内部实例接口 | 每个FB实例唯一Owner；通过类型化Input/Output结构交互；禁止访问其他实例内部变量 |
| D-041 | 外部硬件扫描 | Codex不得Scan或添加真实EtherCAT/IO-Link/AX5000设备 |
| D-042 | 轴关联边界 | 允许PLC AXIS_REF↔未绑定驱动的NC轴内部关联；禁止NC轴↔真实驱动/编码器关联 |
| D-043 | IO绑定 | GVL_IO仅AT通配或普通变量占位；用户后续扫描后人工映射 |
| D-044 | 未绑定状态 | 未完成硬件映射时生产Ready、轴/传感器有效性保持FALSE，禁止假值旁路 |
| D-045 | GitHub仓库 | 唯一Remote为`https://github.com/zhoujingchi027-cmd/CFF_ControlPro.git`，Remote名`origin` |
| D-046 | Git工作分支 | `codex/cffwelding-greenfield-final-v3.3` |
| D-047 | 默认分支保护 | 除空仓库首次建立main外，不直接在默认分支实施，不自动Merge |
| D-048 | Commit频率 | 每个Phase Build/静态检查后做聚焦Commit，默认随后Push工作分支 |
| D-049 | Git历史保护 | 禁止Force Push、rebase、amend已Push提交、allow-unrelated-histories和破坏性clean/reset |
| D-050 | Git认证 | 不在URL、文件或日志中写PAT；远程不可访问时保留本地Commit并报告 |
| D-051 | 最终GitHub仓库 | `https://github.com/zhoujingchi027-cmd/CFF_ControlPro.git` |
| D-052 | 仓库验证 | 任务包生成时已验证Public、空仓库、默认main、当前账户具备Admin/Push |
| D-053 | Git工作分支 | `codex/cffwelding-greenfield-final-v3.3` |
| D-054 | 人工认证 | Push可暂停让用户通过GCM/浏览器/PAT认证；不得保存凭据 |
| D-055 | HTTPS密码 | GitHub账户密码不可用于Git Push；Password提示输入PAT |
