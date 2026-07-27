# CFFwelding V3.7 Phase 8 导纳力控实施计划

> **执行要求：** 实施本计划时依次使用测试驱动、系统化调试、提交前验证和代码审查。每个行为变化先建立准确的 RED 证据，再修改最小 PLC 对象；最终必须通过 Phase 1～8 静态回归和真实 TwinCAT XAE Release Build。

**目标：** 在 Phase 7 External Setpoint 已通过并推送的基线上，实现不访问 `AXIS_REF`、不调用 MC 的 Z 轴导纳 PI、Force Setpoint Ramp、Anti-windup、S_rel 制动限速、硬边界和无扰 Profile 切换，并由 `PRG_FastAxisControl` 唯一实例化。Phase 8 不实现 Contact、步骤判据或 CFF Sequence，不得伪造流程使能、Profile 有效、硬件映射或 Production Ready。

**架构边界：**

- `FB_ZForceAdmittance` 只计算速度命令和诊断，不持有轴引用，不生成 P/V/A，不调用 External API；
- `FB_BumplessProfileSwitch` 只按新 Profile 计算积分预置，不访问 GVL；
- `FB_SetpointRamp` 复用 Phase 4 实现，对目标力执行斜坡；
- `PRG_FastAxisControl` 是三个实例的唯一 Owner，只连接类型化契约和发布状态；
- `FB_ZAxisExtSetpointAdapter` 继续是 Enable/Feed/Disable 和 `AXIS_REF` 的唯一 External Owner；
- Phase 10 才根据正式 CFF Sequence 把导纳速度合成为连续 External P/V/A/Direction，Phase 8 不提前打开该命令通道。

**工具链：** PowerShell 5.1、TwinCAT XAE `3.1.4024.64`、TcXaeShell DTE 15.0、Tc2_MC2 `3.3.65.0`、Structured Text、TwinCAT XML、Git。

---

## Task 1：记录 Phase 7 Push 并提交 Phase 8 计划

**文件：**

- 修改：`Docs/报告/GIT_EXECUTION_REPORT.md`
- 创建：`Docs/plans/2026-07-26-cffwelding-v3.7-phase8-implementation-plan.md`

### Step 1：记录已验证事实

记录：

```text
Phase 7 source: 4f1bfa8de7a3117558993ce07f655d59ccddcd74
Phase 7 report: 962b3303e0ab0ff5109fc606cb5f638a891d2e37
Remote branch: codex/cffwelding-greenfield-v3.3
Remote verified SHA: 962b3303e0ab0ff5109fc606cb5f638a891d2e37
```

不得记录认证方式、密码、PAT 或 Credential 内容。

### Step 2：提交计划

```powershell
git diff --check
git add -- Docs/报告/GIT_EXECUTION_REPORT.md Docs/plans/2026-07-26-cffwelding-v3.7-phase8-implementation-plan.md
git diff --cached --check
git commit -m "docs(plan): add V3.7 Phase 8 implementation plan"
git push origin codex/cffwelding-greenfield-v3.3
```

---

## Task 2：建立 Phase 8 RED 契约测试

**文件：**

- 创建：`scripts/Test-Phase8ForceAdmittance.ps1`
- 修改：`scripts/README.md`

### Step 1：定义对象和边界检查

测试至少检查：

1. `FB_ZForceAdmittance` 和 `FB_BumplessProfileSwitch` 各存在一份并列入 `CFFwelding.plcproj`；
2. `ST_ZForceControlInput`、`ST_ZForceControlOutput`、`ST_ZForceControlProfile` 和 `ST_CffSequenceStatus` 包含 Phase 8 必需字段；
3. 导纳公式包含 `Vff + Kp * eF + Integral`；
4. Anti-windup 包含 `Ki * eF + Kaw * (Vsat - Vunsat)` 和积分绝对限幅；
5. 输出限制顺序覆盖 Profile速度、上抬速度、S_rel制动、硬边界、Collision边界和加速度限幅；
6. S_rel制动复用 `FC_CalcStrokeVelocityLimit`；
7. Profile切换按下式产生积分预置：

   ```text
   Inew = PreviousVelocity - NewVff - NewKp * (NewForceSet - ForceActual)
   ```

8. Force setpoint 从当前 `ForceControl` 连续起步并使用 `FB_SetpointRamp`；
9. Anti-windup 在传感器无效、Owner错误、External未Active、硬力/硬位移、向下边界和 Stop/Fault 时冻结；
10. `PRG_FastAxisControl` 唯一声明 `fbForceSetpointRamp`、`fbZProfileSwitch` 和 `fbZForceAdmittance`；
11. 力算法只使用 `ForceControl`，不得使用 `ForceDisplay`；
12. 力算法和 Profile FB 不含 `AXIS_REF`、`MC_`、GVL 或跨 PROGRAM 局部访问；
13. Phase 8 不写 `bDriveLinked=TRUE`、MappingValid、ProfileValid 或 Production Ready；
14. `Docs/报告/PHASE_8_EXECUTION_REPORT.md` 最终必须且只能存在一份。

### Step 2：运行 RED

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase8ForceAdmittance.ps1
```

预期至少因两个 FB、扩展契约、FastTask 实例和 Phase 8 报告缺失而失败。若测试因无关语法或路径错误失败，先修复测试本身，不修改生产对象。

---

## Task 3：扩展导纳契约并实现无扰 Profile 切换

**文件：**

- 修改：`CFFwelding_System/CFFwelding/DUTs/Interfaces/ST_ZForceControlInput.TcDUT`
- 修改：`CFFwelding_System/CFFwelding/DUTs/Interfaces/ST_ZForceControlOutput.TcDUT`
- 修改：`CFFwelding_System/CFFwelding/DUTs/Structures/ST_ZForceControlProfile.TcDUT`
- 修改：`CFFwelding_System/CFFwelding/DUTs/Interfaces/ST_CffSequenceStatus.TcDUT`
- 创建：`CFFwelding_System/CFFwelding/POUs/FunctionBlocks/Control/FB_BumplessProfileSwitch.TcPOU`
- 修改：`CFFwelding_System/CFFwelding/CFFwelding.plcproj`

### Step 1：扩展输入契约

`ST_ZForceControlInput` 至少明确：

- Enable、Reset；
- Force Process Owner已授予；
- External已Active；
- Force和S_rel有效；
- Profile切换脉冲和切换前速度；
- Force Set/Actual，单位统一为`kN`；
- 当前/目标/硬最大S_rel，单位`mm`；
- Collision或Secondary硬边界状态；
- 实际调用周期，单位`s`。

`ST_CffSequenceStatus` 增加上述流程侧请求字段，但 `PRG_CffSequence` 在 Phase 8 继续保持骨架，因此默认值必须禁止导纳使能。

### Step 2：扩展 Profile 和输出诊断

`ST_ZForceControlProfile` 增加显式 Revision 和速度前馈；现有 `fForceRampNS` 在调用边界转换为 `kN/s`。所有增益和限值注释必须写明单位和合法范围。

`ST_ZForceControlOutput` 至少发布：

- 最终速度、积分项；
- Ramped Force Set、Force Error；
- 未饱和/饱和速度；
- S_rel制动速度上限；
- Active、Limited、Anti-windup Frozen、Hard Limit、Fault和FaultId。

### Step 3：实现 Profile 无扰积分预置

`FB_BumplessProfileSwitch`：

- 只接收显式标量输入；
- 校验全部输入有限、积分限值非负、增益合法；
- 只在切换脉冲上计算一次积分预置；
- 将结果限幅到新 Profile 的积分绝对限值；
- Reset/Disable清除接受状态；
- 不访问 GVL、轴或 MC。

### Step 4：局部验证

运行 Phase 4 和 Phase 8 测试。此时 Phase 8 可继续因导纳 FB、FastTask 接线和报告缺失而失败。

---

## Task 4：以 TDD 实现 `FB_ZForceAdmittance`

**文件：**

- 创建：`CFFwelding_System/CFFwelding/POUs/FunctionBlocks/Control/FB_ZForceAdmittance.TcPOU`
- 修改：`CFFwelding_System/CFFwelding/CFFwelding.plcproj`

### Step 1：输入和配置预检

Enable前检查：

- Profile和Machine Limits有效；
- 周期大于0且所有计算量有限；
- `Kp/Ki/Kaw`、积分限值、斜坡、速度、加速度和制动裕量非负且符合工程要求；
- Force/S_rel有效；
- Owner已授予且External已Active；
- 当前S_rel没有超出硬最大边界。

未Enable时输出零且不报假Ready。Enable请求下的无效传感器、配置或数值必须输出确定故障码和零速度。

### Step 2：实现 PI 与 Anti-windup

每个有效周期：

```text
eF = ForceSetRamped - ForceControl
Vunsat = Vff + Kp * eF + Integral
Vsat = ordered_limits(Vunsat)
IntegralDot = Ki * eF + Kaw * (Vsat - Vunsat)
```

积分使用梯形或明确的一阶离散积分并执行绝对限幅。Profile/Contact切换脉冲优先应用 `FB_BumplessProfileSwitch` 给出的积分预置，不在同一扫描额外积分。

### Step 3：实现固定限幅顺序

顺序不得交换：

```text
PI未饱和输出
→ Profile上下速度限幅
→ 机器最大上抬/下压速度限幅
→ S_rel制动限速
→ Secondary/Hard S_rel边界
→ Collision边界
→ 速度变化率/最大加速度限幅
```

`FC_CalcStrokeVelocityLimit` 计算：

```text
sqrt(2 * MaxDeceleration * max(TargetSRel - CurrentSRel - BrakeMargin, 0))
```

到达任何向下硬边界时最大向下速度为0；边界不阻止受控上抬退出。禁止以 NC `SRelAxis` 自动替代无效的 `SRelSensor`。

### Step 4：冻结和故障规则

以下条件冻结积分：

- Force或S_rel无效；
- Owner不是Force Process；
- External未Active；
- Stop/Reset/Fault；
- Hard Force或Hard S_rel；
- Collision边界；
- 向下速度已封顶且误差仍要求继续向下。

算法故障只发布状态和零速度；External受控 Disable 由已有 Adapter 和后续正式 Sequence 协调，算法 FB 不调用 MC。

### Step 5：局部测试和真实 Build

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase4Utilities.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase8ForceAdmittance.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1
```

Build必须为`LastBuildInfo=0`。测试只允许继续因 FastTask 接线或报告尚未完成而失败。

---

## Task 5：接入 `PRG_FastAxisControl` 并保持默认禁用

**文件：**

- 修改：`CFFwelding_System/CFFwelding/POUs/Fast/PRG_FastAxisControl.TcPOU`
- 修改：`CFFwelding_System/CFFwelding/DUTs/Structures/ST_FastStatus.TcDUT`
- 修改：`CFFwelding_System/CFFwelding/GVLs/GVL_ProjectInfo.TcGVL`
- 修改：`Docs/报告/INSTANCE_OWNERSHIP_MATRIX.md`（报告提交阶段完成最终状态）
- 修改：`Docs/报告/INTERNAL_INTERFACE_CATALOG.md`（报告提交阶段完成最终状态）

### Step 1：唯一实例

仅在 `PRG_FastAxisControl.VAR` 声明：

```pascal
fbForceSetpointRamp : FB_SetpointRamp;
fbZProfileSwitch : FB_BumplessProfileSwitch;
fbZForceAdmittance : FB_ZForceAdmittance;
```

每个实例前使用中文块注释说明任务、Owner、输入、输出、Reset和生命周期。

### Step 2：调用顺序

调用顺序为：

```text
轴Owner仲裁
→ Force Setpoint Ramp
→ Profile无扰积分预置
→ Z Force Admittance
→ 标准Z NC Adapter
→ External Adapter
→ R NC Adapter
→ 状态和报警发布
```

Force输入必须来自`GVL_Process.stActual.fForceControlN`并显式换算为`kN`；S_rel必须来自`fSRelSensorMm`且依赖位移和Contact参考有效性。不得读取`fForceDisplayN`。

### Step 3：默认禁用和阶段边界

导纳Enable只来自 `ST_CffSequenceStatus.bForceControlEnable`。Phase 8 的 `PRG_CffSequence` 仍不写该字段，因此默认FALSE；Profile、Machine Limits、硬件和传感器有效条件缺失时同样禁止Active。

Phase 8 只把 `ST_ZForceControlOutput` 发布到 `ST_FastStatus`，不覆盖 Phase 7 External P/V/A/Direction命令。正式轨迹合成和流程Enable由 Phase 10完成。

### Step 4：报警

为导纳故障使用唯一固定报警槽和类型化报警码；不得覆盖 Phase 7 的槽7。活动条件来自 `fbZForceAdmittance.stOutput.bFault`，FastTask不处理中文字符串。

---

## Task 6：完整回归、审查、Build 与源码提交

### Step 1：运行 Phase 1～8 静态测试

依次运行 `Test-Phase1Project.ps1` 至 `Test-Phase8ForceAdmittance.ps1`。Phase 8 在报告创建前只允许报告闸门失败。

### Step 2：真实 XAE Build

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1
```

必须看到：

```text
CFFwelding XAE build: PASSED
LastBuildInfo: 0
```

### Step 3：边界审查

检查：

- 两个 Phase 8 FB 无 `AXIS_REF`、`MC_` 或 GVL；
- 只有 Phase 7 Adapter 调用 External API；
- ForceControl而非ForceDisplay用于算法；
- 未伪造Sequence enable、配置有效、映射或Production Ready；
- 实例唯一且无跨PROGRAM局部访问；
- 所有TwinCAT XML可解析；
- `git diff --check`通过。

### Step 4：提交源码

```powershell
git commit -m "feat(control): add Phase 8 force admittance"
```

报告文档不混入源码提交。

---

## Task 7：生成报告、复验并 Push

**文件：**

- 创建：`Docs/报告/PHASE_8_EXECUTION_REPORT.md`
- 修改：`Docs/报告/TWINCAT_BUILD_REPORT.md`
- 修改：`Docs/报告/INSTANCE_OWNERSHIP_MATRIX.md`
- 修改：`Docs/报告/INTERNAL_INTERFACE_CATALOG.md`
- 修改：`Docs/报告/GIT_EXECUTION_REPORT.md`

### Step 1：报告证据

记录：

- Ramp、PI、Anti-windup、S_rel制动和固定限幅顺序；
- Profile无扰公式和积分限幅；
- Owner、External Active、Force/S_rel有效门控；
- Phase 8 默认不使能的阶段边界；
- 唯一实例和无MC/AXIS_REF边界；
- Phase 1～8测试输出；
- XAE版本、构建配置和`LastBuildInfo`；
- 源码Commit Hash；
- 未执行任何硬件、Runtime或轴操作；
- Contact/Sequence、External P/V/A轨迹合成、真实硬件、抖动和工艺资格仍未完成。

### Step 2：关闭报告闸门并复验

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase8ForceAdmittance.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1
git diff --check
```

### Step 3：报告提交和有界 Push

```powershell
git commit -m "docs(report): record Phase 8 force control verification"
git status --short --branch
git ls-remote --symref origin HEAD
git fetch --prune origin
git push origin codex/cffwelding-greenfield-v3.3
```

网络或认证失败时不循环重试、不修改 Remote、不读取或记录认证信息。
