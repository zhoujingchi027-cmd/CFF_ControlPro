# CFFwelding V3.7 增量续作设计

## 1. 背景与当前基线

当前仓库已经在 `codex/cffwelding-greenfield-v3.3` 分支完成 Phase 0–6，最近一次已验证基线包括：

- TwinCAT Solution、System Project 和 PLC Project；
- Fast/Main/Slow 三任务和 PROGRAM 骨架；
- Phase 3 DUT、GVL、离线 NC 轴及 PLC AXIS_REF 内部关联；
- Phase 4 纯函数和通用功能块；
- Phase 5 力、位移及旧版 Collision 接口；
- Phase 6 Z/R 标准 NC Adapter 和 Z 轴 Owner 仲裁。

V3.7 任务包在此基础上增加 Phase 11A–11D，并替换了部分规则、报告模板和外围接口定义。当前工作树还包含一份未提交的 Phase 7 External Setpoint 草稿；该草稿真实 XAE Build 的 `LastBuildInfo=2`，不得视为完成状态。

## 2. 目标

采用增量升级方式保留 Phase 0–6 的提交、测试脚本、Build 证据和执行报告，然后继续完成：

1. Phase 7 External Setpoint；
2. Phase 8–11 核心 CFF 控制；
3. V3.7 新增 Phase 11A–11D；
4. Phase 12–15 主控、外围、ADS、最终审查和交付。

每个 Phase 均执行测试、真实 XAE Build、审查、聚焦 Commit，并在远程访问可用且工作树干净时 Push。

## 3. 非目标与硬边界

本设计不授权以下操作：

- 修改任何旧工程；
- Scan Devices、Scan Boxes 或 Scan Motors；
- 添加或关联真实 EP3174、IO-Link、AX5000、机器人或外围 PDO；
- 关联 NC 轴与真实驱动、编码器或电机；
- 激活配置、下载工程或登录 Runtime；
- 创建 TwinSAFE、仿真、虚拟生产轴、假 IO 或假 Ready；
- 创建 WPF、数据库或机器人轨迹；
- 记录、读取、回显或保存 GitHub 密码、PAT 或其他认证信息。

## 4. 规则优先级与冲突处理

实施时使用以下优先级：

1. 用户在当前任务中的明确指令；
2. `FINAL_DECISION_REGISTER.md` V3.7；
3. V3.7 架构和 Codex 实施文档；
4. 未被 V3.7 覆盖的 V3.0/V3.1 规范；
5. 已有实现和旧工程经验。

已识别的冲突按以下方式处理：

- 当前工作分支保持用户此前明确指定的 `codex/cffwelding-greenfield-v3.3`。任务书中的 `codex/cffwelding-greenfield-final-v3.3` 不触发自动换支。
- Fastener Station 按 V3.7 决策登记和外部接口专篇保留 10 输入、7 输出；旧文档中的“无物理输出”属于被覆盖内容。
- Collision 不再使用独立硬接线或总线输入；Phase 11B 改为外部位移窗口 Teach，并同步锁存 NC 位置。
- 只有 `PRG_IO_Config` 可以访问固定 Legacy 外部过程映像。
- 所有气缸最终统一使用新版 `FB_Actuator`；旧的单双控独立 FB 方案不实施。

## 5. 版本升级与历史证据处理

V3.7 任务包当前把 Phase 0–6 报告及 Build/Test 脚本标记为删除。经用户批准，处理方式为：

- 从当前分支已提交历史恢复 Phase 0–6 报告和验证脚本；
- 保留 V3.7 新增及修改的规范、变更记录和报告模板；
- 不把已生成的执行报告替换为空模板；
- 后续测试在既有脚本基础上增量扩展；
- V3.7 规范迁移使用独立文档 Commit，不混入未通过 Build 的 Phase 7 源码。

## 6. Phase 7 External Setpoint 设计

### 6.1 职责边界

`FB_ZAxisExtSetpointAdapter` 是 External Setpoint API 的唯一 Owner：

- 只有该 Adapter 可调用 Tc2_MC2 External Setpoint Enable、Feed 和 Disable 接口；
- `PRG_FastAxisControl` 拥有该 FB 实例并负责连接命令、状态、轴引用和报警；
- `FB_AxisCommandArbiter` 在 External 完整退出前持续保留 Force Process Owner；
- `PRG_CffSequence` 不调用任何 MC 对象；
- 后续 `FB_ZForceAdmittance` 只产生速度/轨迹命令，不访问 AXIS_REF。

### 6.2 生命周期

正式生命周期为：

```text
IDLE
→ PRECHECK
→ PRELOAD_DIRECTION
→ PREFEED_INITIAL
→ ENABLE
→ WAIT_ENABLED
→ ACTIVE
→ RAMP_TO_ZERO
→ HOLD_DIRECTION
→ DIRECTION_ZERO
→ DISABLE
→ WAIT_DISABLED
→ POST_DISABLE_HOLD
→ DONE / ERROR
```

Enable 前从本机实际 `NCTOPLC_AXIS_REF` 字段取得当前位置、设定速度和设定加速度，保证初值连续。实际字段名和 Tc2_MC2 调用签名必须通过本机 `3.3.65.0` 库声明或真实编译确认，不允许猜测。

ACTIVE 状态每个 Fast/SAF 周期 Feed 一次 P/V/A/Direction。当前工程 FastTask 和离线 NC SAF 均为 2 ms；最终仍需在真实 NC 配置后复核。

Disable 顺序必须满足：

```text
速度受控归零
→ 保持最后非零 Direction 至少一个 SAF
→ Direction=0 并静止 Feed 至少一个 SAF
→ Disable
→ 确认 Disabled
→ 再保持至少一个 SAF
→ 释放 Owner
```

### 6.3 输入和硬门控

Enable 至少要求：

- External 配置有效；
- Z 轴真实驱动绑定状态由人工确认；
- 标准 NC Adapter 报告轴可接管且无错误；
- FastTask 周期有效；
- P/V/A 为有限数；
- 位置、速度和加速度处于机器硬限值内；
- Direction 只能为 -1、0 或 1，并与非零速度方向一致。

未绑定真实驱动、API 未确认、配置无效或任一硬门控失败时，不允许 Enable，Ready/Enabled 不得伪造为 TRUE。

### 6.4 错误处理

- Enable/Disable 超时或 MC 错误必须锁存错误码和 External 报警；
- ACTIVE 中命令丢失、非有限值、越界或轨迹不连续时进入受控退出；
- 活动状态中的 Reset 不直接清错，先完成归零和 Disable；
- 未确认 External Disabled 时不得发布 `bReleaseOwner=TRUE`；
- Disable 无法确认时保持错误锁存，由现场诊断处理，不转交标准运动命令。

## 7. V3.7 Phase 11A–11D 设计边界

### Phase 11A

- 收敛 `GVL_IO` 到冻结的直接 IO 和两个 AXIS_REF；
- 删除额外硬接线气缸、夹具、送料和 Collision 输入；
- 创建 Robot Profinet、外围 EtherCAT 的类型化契约和 Adapter；
- 不配置实际 GSDML、ESI、PDO 或总线设备。

### Phase 11B

- 使用 `FB_CollisionDisplacementTeach` 完成外部位移窗口 Teach；
- 同步采集外部位移与 NC 位置，支持多次样本、均值、极差和有效性；
- 运行时以外部位移剩余距离为主，NC 距离为冗余；
- 创建 Gun Head Feed、Magazine、Fastener Station 模块边界。

### Phase 11C

- 创建 `GVL_ExternalIO`、`GVL_ModuleInterface`、`PRG_IO_Config` 和 `PRG_MainTask`；
- 模块 PROGRAM 只访问内部 Request/Status/Physical Input/Output；
- `PRG_FastenerTransportCoordinator` 只路由 Magazine/Direct Blow 路径和两路握手；
- `ACT_Automatic_TODO` 保持全部安全输出，不编造自动流程。

### Phase 11D

- 创建并保留全部固定 Legacy 外部符号和拼写；
- 验证 `DUT_USINT` 和 `ST_USINT` 均为 1 字节；
- 输出每扫描先清零 Raw 结构，再写有效输出，并清零未使用 bit；
- 创建唯一新版 `FB_Actuator` 和 6 个规定实例；
- Maintenance Hold-to-Run 必须经过模块 PROGRAM、Owner 仲裁和 `FB_Actuator`；
- 映射未人工确认时 MappingValid、Automatic Ready 和 Production Ready 保持 FALSE。

## 8. 测试与验证策略

每项功能遵循测试先行：

1. 先新增或修订 PowerShell 静态契约测试并确认失败原因正确；
2. 再修改最小 PLC 对象使测试通过；
3. 运行所有已完成 Phase 的回归测试；
4. 执行 XML/UTF-8、对象清单、MC 调用边界和单一写入者检查；
5. 执行真实 TwinCAT XAE Build；
6. 检查 `git diff --check`、差异范围和报告；
7. 只有全部通过后才 Commit。

Phase 7 必须覆盖：

- 实际 External API 签名；
- 唯一 Adapter/实例/Owner；
- 每 SAF Feed；
- P/V/A/Direction 连续性和限值；
- Enable/Disable 超时；
- 完整退出和 Owner 释放；
- 未绑定硬件时保持不可运行；
- `PRG_CffSequence` 和算法 FB 不包含 MC 调用。

真实 XAE Build 只能证明源码在当前工具链下编译，不代表硬件映射、实时抖动、External POC、实机联调或工艺资格通过。

## 9. Git 与提交策略

- Remote 保持 `origin` 指向 `https://github.com/zhoujingchi027-cmd/CFF_ControlPro.git`；
- Git 身份只使用当前仓库 local 配置；
- 不使用 force push、rebase、amend、破坏性 reset/clean 或无关历史合并；
- 规范升级、每个 Phase 源码和每个 Phase 报告使用聚焦 Commit；
- Push 前要求工作树干净并复核远程状态；
- 认证不可用时保留本地 Commit，不循环重试，不记录任何秘密。

## 10. 完成判据

本设计完成实施后，只能基于证据声明：

- 源码对象已生成；
- 当前 XAE Build 通过或失败；
- 外部硬件仍未映射；
- 实机联调仍未完成；
- 工艺资格仍未完成。

不得声明 Production Ready、安全已验证、EJOT 工艺等同或量产参数合格。

## 11. 当前开放项

- Phase 7 草稿的精确 PLC 编译错误尚需从 XAE/最小编译探针中定位；
- 本机 Remote 复核曾发生网络超时，Push 前需重新执行一次有界检查；
- External Setpoint POC、真实 SAF 抖动及 AX5000 行为必须由用户后续现场验证；
- 所有 Legacy bit/byte 对应关系、Robot 20 字节布局和外围 PDO 均待人工确认。
