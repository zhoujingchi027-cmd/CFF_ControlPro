# CFFwelding V3.7 Phase 9 Contact与Criterion实施计划

> **执行要求：** 依次使用测试驱动、系统化调试、提交前验证和代码审查。每个行为变化先建立准确 RED 证据，再修改最小 PLC 对象；最终必须通过 Phase 1～9 静态回归和真实 TwinCAT XAE Release Build。

**目标：** 在 Phase 8 已推送的基线上，实现不访问 `AXIS_REF`、不调用 MC 的 Contact 检测、Force Decline Observer、Primary/Secondary、StepMin/StepMax、EndCause 和四步骤 Program Validation，并由 `PRG_CffSequence`分配唯一实例。Phase 9 不实现 CFF 状态转换、Contact参考点RequestId事务、导纳Enable、R轴命令或External P/V/A/Direction；这些接线留给 Phase 10。

**架构：** Contact、Decline和步骤判据是有内部状态的可复用FB；程序校验继续由纯计算`FC_ValidateJoinProgram`负责。判据只消费调用者完整赋值的类型化输入，输出锁存原因和动作请求，不直接写GVL。`PRG_CffSequence`在Phase 9只声明、调用并发布诊断，所有Enable显式保持FALSE，确保尚未实现状态机时不会产生流程动作。

**工具链：** PowerShell 5.1、TwinCAT XAE `3.1.4024.64`、TcXaeShell DTE 15.0、Tc2_MC2 `3.3.65.0`、Structured Text、TwinCAT XML、Git。

## Task 1：记录Phase 8 Push并提交Phase 9计划

**文件：**

- 修改：`Docs/报告/GIT_EXECUTION_REPORT.md`
- 创建：`Docs/plans/2026-07-26-cffwelding-v3.7-phase9-implementation-plan.md`

### Step 1：基线核对

确认本地与远端均为`2b73107c8e43ccc858fedcea9007b846ab4b1b0b`，工作区干净，分支和固定Remote未变化。

### Step 2：记录Phase 8最终Push

写入Phase 8源码/报告Commit、Push成功、远端SHA和凭据未记录；不得写入认证方式或秘密。

### Step 3：提交并Push计划

```powershell
git add -- Docs/报告/GIT_EXECUTION_REPORT.md Docs/plans/2026-07-26-cffwelding-v3.7-phase9-implementation-plan.md
git diff --cached --check
git commit -m "docs(plan): add V3.7 Phase 9 implementation plan"
git push origin codex/cffwelding-greenfield-v3.3
```

## Task 2：建立Phase 9 RED契约测试

**文件：**

- 创建：`scripts/Test-Phase9ContactAndCriterion.ps1`
- 修改：`scripts/README.md`

### Step 1：定义静态契约

测试至少验证：

1. `FB_ContactDetect`、`FB_ForceDeclineObserver`和`FB_StepProceedingCriterion`各只有一个对象并加入编译；
2. Contact输入包含Force On/Off、Axis/Sensor绝对位置、双窗口、捕获速度、Debounce、周期和有效性；输出包含候选、确认、双位置锁存、一次性参考点请求和故障；
3. Decline输入包含Arm、DeclineTo、Hysteresis、最小下降率、RPM/S_rel窗口、捕获速度、Debounce和周期；输出包含Armed、Candidate、Confirmed、导数、锁存值和故障；
4. 步骤判据输入包含唯一Primary、Secondary Action、目标、StepMin/Max、Decline状态、硬边界和有效性；输出包含TooShort、NOK、Advance/ControlledExit、DownwardInhibit、EndCause和锁存值；
5. `ST_StepProceedingConfig`和Program Header包含完整Phase 9字段；
6. `FC_ValidateJoinProgram`验证四步顺序、枚举、StepMin/Max、Time/Decline强制Secondary、Decline关系、累计S_rel单调、Profile/Monitor ID和机器硬限值；
7. 三个FB在`PRG_CffSequence`唯一声明，Phase 9 Enable显式FALSE；
8. 三个算法FB不包含`AXIS_REF`、MC、GVL、其他PROGRAM局部访问或字符串；
9. Phase 9不写Contact RequestId、Force Control Enable或External P/V/A/Direction；
10. Sequence/算法层不强制任何硬件、映射、Profile、Program或Production Ready有效；
11. 固定报警槽9和`ALARM_CFF_CRITERION_FAULT`与Phase 7/8槽位隔离；
12. Phase 9执行报告唯一存在。

### Step 2：增加离线确定性向量

PowerShell 参考状态机覆盖：

- Contact Force On候选、Force Off回差、连续Debounce、窗口外故障和单次确认脉冲；
- Decline未Arm不得确认，Arm后必须同时满足下降阈值、负下降率、RPM/S_rel窗口、捕获速度和Debounce；
- Relative Distance、Step Time、Force Decline三种Primary；
- Secondary优先禁止继续向下，并按Action区分AdvanceAndNok和ControlledExitNok；
- Primary过早立即结束并标记TooShort/NOK，不等待StepMin继续压入；
- Primary未到而StepMax到达时`STEP_END_MAX_TIME`；
- Stop/Axis/Sensor/Hard Force/Hard Stroke原因优先级和故障锁存；
- Program Validation接受一个最小合法四步程序，并拒绝每类边界破坏。

这些向量明确标记为离线契约，不冒充PLC Runtime测试。

### Step 3：运行并确认准确RED

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase9ContactAndCriterion.ps1
```

预期只因Phase 9对象、字段、集成和报告缺失失败；若因PowerShell 5.1编码、语法或路径失败，先修复测试。

## Task 3：扩展Contact、Decline和步骤契约

**文件：**

- 修改：`DUTs/Structures/ST_JoinProgramHeader.TcDUT`
- 修改：`DUTs/Structures/ST_StepProceedingConfig.TcDUT`
- 修改：`DUTs/Interfaces/ST_ContactDetectInput.TcDUT`
- 修改：`DUTs/Interfaces/ST_ContactDetectOutput.TcDUT`
- 创建：`DUTs/Interfaces/ST_ForceDeclineInput.TcDUT`
- 创建：`DUTs/Interfaces/ST_ForceDeclineOutput.TcDUT`
- 修改：`DUTs/Interfaces/ST_StepCriterionInput.TcDUT`
- 修改：`DUTs/Interfaces/ST_StepCriterionOutput.TcDUT`
- 修改：`DUTs/Interfaces/ST_CffSequenceStatus.TcDUT`
- 修改：`DUTs/Enums/E_AlarmCode.TcDUT`
- 修改：`CFFwelding.plcproj`

### Step 1：Contact Program参数

Program Header增加Contact Force On/Off、Debounce、Search Velocity和外部位移Expected Window。所有公开字段带独立中文注释和单位；默认零值保持Program无效，不伪造工艺参数。

### Step 2：完整步骤推进配置

`ST_StepProceedingConfig`明确区分：

- Relative Distance主目标；
- Primary Step Time；
- StepMin和StepMax；
- Secondary累计S_rel；
- DeclineTo、ArmForce、Hysteresis、MinimumDeclineRate和Debounce；
- Decline有效S_rel/RPM窗口与CaptureMaxVelocity；
- Secondary Action和有效位。

Program存储单位继续使用`N/mm/ms/rpm`，Fast算法接口显式转换为`kN/mm/s/rpm`。

### Step 3：类型化算法接口

Contact同时锁存Axis/Sensor候选和确认位置；Force Decline发布导数和确认锁存；步骤判据发布动作请求、NOK、TooShort、硬边界诊断和EndCause。所有故障编号使用确定性UDINT，不输出字符串。

## Task 4：实现`FB_ContactDetect`

**文件：**

- 创建：`POUs/FunctionBlocks/Control/FB_ContactDetect.TcPOU`
- 修改：`CFFwelding.plcproj`

### Step 1：Reset/Disable/故障生命周期

显式Reset清候选、确认、计时和故障；Disable取消未完成候选但不重复确认脉冲。Enable期间配置、周期、数值或信号无效时锁存故障并输出无动作状态。

### Step 2：On/Off回差和候选锁存

ForceCriterion首次达到Force On时只锁存一次候选Force、Axis位置和Sensor位置；跌破Force Off取消候选。Force On必须大于Force Off且两者非负。

### Step 3：窗口、速度与Debounce

候选Axis/Sensor位置必须在调用者给出的绝对窗口内，捕获速度绝对值不得超过配置；Force持续不低于Off并完成连续Debounce后确认Contact。确认只发一个扫描周期的参考点请求脉冲，`bDetected`保持到Reset。

## Task 5：实现`FB_ForceDeclineObserver`

**文件：**

- 创建：`POUs/FunctionBlocks/Control/FB_ForceDeclineObserver.TcPOU`
- 修改：`CFFwelding.plcproj`

### Step 1：导数和Arm

使用相邻有效ForceCriterion和实际周期计算`dForce/dt`。只有Force达到ArmForce后锁存Armed；Disable清动态观察状态，显式Reset清故障。

### Step 2：Decline候选与回差

Armed后必须同时满足Force不高于DeclineTo、导数不高于负的MinimumDeclineRate、RPM/S_rel窗口有效、捕获速度有效和信号有效。Hysteresis用于候选退出，禁止阈值附近抖动拼接非连续Debounce。

### Step 3：确认锁存

连续Debounce完成后单次确认并锁存Force、S_rel、RPM、导数和步骤时间。确认前不生成任何“关闭PI”请求；确认后只输出事实，Profile切换由Phase 10 Sequence执行。

## Task 6：实现步骤判据和Program Validation

**文件：**

- 创建：`POUs/FunctionBlocks/Control/FB_StepProceedingCriterion.TcPOU`
- 修改：`POUs/Functions/FC_ValidateJoinProgram.TcPOU`
- 修改：`CFFwelding.plcproj`

### Step 1：判据优先级

每扫描先验证输入，再按Stop/Axis/Sensor/Hard Force/Hard Stroke、Secondary、Primary、StepMax顺序处理。Secondary触发立即发布`bDownwardMotionInhibited=TRUE`，不得为了等待其他条件继续向下。

### Step 2：Primary和StepMin

Primary只能是Relative Distance、Step Time或已确认Force Decline。Primary一旦满足立即结束；若步骤时间小于StepMin，同时标记TooShort和NOK，不继续运行等待StepMin。

### Step 3：Secondary、StepMax和EndCause

Time/Decline必须有累计S_rel Secondary。Secondary Action决定AdvanceAndNok或ControlledExitNok；StepMax只在Primary未满足时产生`STEP_END_MAX_TIME`。所有结束输出一次锁存Force、S_rel和Step Time。

### Step 4：扩展Program Validation

逐项验证有限性、四步固定顺序、Primary枚举、StepMin≤StepMax、Time目标范围、Time/Decline Secondary、Decline关系及窗口、累计S_rel单调、Step4边界不小于Step3、Force/RPM/Profile/Monitor ID和机器硬限值。任何未知枚举或非有限值返回FALSE。

## Task 7：Phase 9骨架集成、回归、审查、Build和源码提交

**文件：**

- 修改：`POUs/Fast/PRG_CffSequence.TcPOU`
- 修改：`GVLs/GVL_ProjectInfo.TcGVL`
- 修改：`CFFwelding_System.tsproj`
- 修改：`CFFwelding.tmc`

### Step 1：唯一实例和默认禁止

在`PRG_CffSequence.VAR`中唯一声明三个FB，每个实例前写用途、任务、Owner、输入、输出和Reset生命周期中文块注释。调用使用类型化局部输入，并在Phase 9显式`bEnable := FALSE`；发布诊断但不写流程状态转换、Contact RequestId、Force Control Enable或External命令。

### Step 2：固定报警槽

槽9只聚合Contact/Decline/Criterion算法故障，代码`ALARM_CFF_CRITERION_FAULT`、TextId 3000、SourceId 9；槽7/8保持不变。

### Step 3：完整回归和真实Build

依次运行Phase 1～9测试。Phase 9在报告生成前只允许报告闸门失败。随后执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1
```

必须得到`LastBuildInfo: 0`，并解析全部TwinCAT XML、运行`git diff --check`、检查PowerShell 5.1 ASCII兼容和禁止边界。

### Step 4：独立审查

审查重点：Contact脉冲唯一性、回差/连续Debounce、Decline Arm和负导数、窗口与捕获速度、Secondary安全优先级、StepMin不过冲、StepMax、EndCause、Program Validation绕过、故障锁存、唯一实例和Phase 10边界。Critical/Important必须RED→GREEN关闭。

### Step 5：源码提交

只暂存Phase 9 PLC、测试、生成TMC/tsproj和脚本说明，不含执行报告：

```powershell
git commit -m "feat(process): add contact and proceeding criteria"
```

## Task 8：报告、最终复验、报告提交和Push

**文件：**

- 创建：`Docs/报告/PHASE_9_EXECUTION_REPORT.md`
- 修改：`Docs/报告/TWINCAT_BUILD_REPORT.md`
- 修改：`Docs/报告/INSTANCE_OWNERSHIP_MATRIX.md`
- 修改：`Docs/报告/INTERNAL_INTERFACE_CATALOG.md`
- 修改：`Docs/报告/GIT_EXECUTION_REPORT.md`

报告必须记录：

- Contact候选/回差/双位置锁存和一次性请求语义；
- Decline Arm、负下降率、窗口、Debounce和确认前PI继续跟随边界；
- 三种Primary、Secondary Action、StepMin/Max、EndCause和Program Validation；
- 离线参考向量不是PLC Runtime测试；
- 唯一实例、无MC/AXIS_REF/GVL算法边界；
- Phase 9默认禁止及Phase 10未实现范围；
- 源码Commit、XAE版本、配置和`LastBuildInfo=0`；
- 未扫描、激活、下载、登录Runtime或执行物理运动；
- 真实硬件、Runtime时序、工艺参数和Production Ready仍未验证。

完成报告后再次运行Phase 1～9、真实Build、XML和差异检查，再提交：

```powershell
git commit -m "docs(report): record Phase 9 contact and criterion verification"
git push origin codex/cffwelding-greenfield-v3.3
```

Push后通过`git ls-remote --heads`核对远端SHA；不得输出任何认证信息。
