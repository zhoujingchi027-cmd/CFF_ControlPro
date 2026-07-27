# CFFwelding V3.7 规范迁移与 Phase 7 实施计划

> **执行要求：** 实施本计划时依次使用 `superpowers:test-driven-development`、`superpowers:systematic-debugging` 和 `superpowers:verification-before-completion`。不得跳过 RED 测试、真实 XAE Build 或提交前证据检查。

**目标：** 保留 Phase 0–6 的验证证据与工具，提交 V3.7 任务包升级，并把当前未完成的 Z 轴 External Setpoint 草稿修正为通过静态测试和真实 TwinCAT XAE Build 的 Phase 7 实现。

**架构：** `PRG_FastAxisControl` 唯一拥有 `FB_ZAxisExtSetpointAdapter`；该 Adapter 是 Tc2_MC2 External Setpoint API 的唯一调用者。`FB_AxisCommandArbiter` 在 External 完整 Disable 前保持 Force Process Owner。未绑定真实驱动、配置无效或 API 未确认时不得进入 Enabled/Ready。

**工具链：** PowerShell 5.1、TwinCAT XAE 3.1.4024.64、TcXaeShell DTE 15.0、Tc2_MC2 3.3.65.0、Structured Text、TwinCAT XML、Git。

---

## Task 1：恢复历史证据并提交 V3.7 规范迁移

**文件：**

- 恢复：`scripts/Build-Cffwelding.ps1`
- 恢复：`scripts/Configure-CffweldingPhase3OfflineNc.ps1`
- 恢复：`scripts/Link-CffweldingPhase3AxisRefs.ps1`
- 恢复：`scripts/New-CffweldingPhase1.ps1`
- 恢复：`scripts/Sync-CffweldingPhase2Tasks.ps1`
- 恢复：`scripts/Sync-CffweldingPhase3FastTask.ps1`
- 恢复：`scripts/Test-Phase1Project.ps1`
- 恢复：`scripts/Test-Phase2Architecture.ps1`
- 恢复：`scripts/Test-Phase3DataAndBindings.ps1`
- 恢复：`scripts/Test-Phase4Utilities.ps1`
- 恢复：`scripts/Test-Phase5SensorProcessing.ps1`
- 恢复：`scripts/Test-Phase6MotionAdapters.ps1`
- 恢复：`Docs/报告/ENVIRONMENT_DETECTION.md`
- 恢复：`Docs/报告/GIT_EXECUTION_REPORT.md`
- 恢复：`Docs/报告/HARDWARE_MANUAL_BINDING_CHECKLIST.md`
- 恢复：`Docs/报告/INSTANCE_OWNERSHIP_MATRIX.md`
- 恢复：`Docs/报告/INTERNAL_INTERFACE_CATALOG.md`
- 恢复：`Docs/报告/IO_MAPPING_TODO.md`
- 恢复：`Docs/报告/NC_CONFIGURATION_CHECKLIST.md`
- 恢复：`Docs/报告/PHASE_0_EXECUTION_REPORT.md` 至 `PHASE_6_EXECUTION_REPORT.md`
- 恢复：`Docs/报告/REFERENCE_REUSE_LOG.md`
- 恢复：`Docs/报告/TWINCAT_BUILD_REPORT.md`
- 修改：`scripts/README.md`
- 提交：V3.7 根文档、架构文档、实施文档、变更记录及报告模板

### Step 1：再次确认恢复范围

运行：

```powershell
git status --short
git diff --name-status
```

预期：上述脚本和 `Docs/报告` 文件均显示 `D`；Phase 7 PLC 草稿仍显示修改/未跟踪，不能加入本 Task 暂存区。

### Step 2：按用户授权精确恢复历史文件

只对上面明确列出的脚本和 `Docs/报告` 文件执行带路径的：

```powershell
git restore --source=HEAD -- <exact-paths>
```

不得使用 `git restore .`、`git checkout .`、`reset` 或 `clean`。

### Step 3：合并 scripts 说明

保留 V3.7 对脚本用途和禁止仿真的约束，并补回：

- XAE Automation 脚本不得 Scan、Activate、Download 或控制 Runtime；
- Phase 1–6 回归测试用途；
- Phase 7 测试和 Build 顺序；
- 所有硬件映射、驱动和生产 Ready 继续保持人工确认。

使用 `apply_patch` 修改 `scripts/README.md`。

### Step 4：核对 V3.7 规范暂存范围

只暂存：

- `.gitignore`；
- `AGENTS.md`、`README.md`、`CODEX_START_PROMPT.txt`、`FINAL_DECISION_REGISTER.md`；
- `CHANGELOG_FINAL_V3.4.md` 至 `CHANGELOG_FINAL_V3.7.md`；
- V3.7 新增/修改的 `Docs/01_架构`、`Docs/03_主控与外围`、`Docs/04_标定与联调`；
- 删除的 V3.3 实施文档和新增的 V3.7 实施文档；
- V3.7 报告模板；
- `scripts/README.md`。

明确排除：

- 所有 Phase 7 PLC 草稿；
- `ST_ZExtSetpointConfig.TcDUT`；
- `FB_ZAxisExtSetpointAdapter.TcPOU`；
- 任何构建缓存或认证信息。

运行：

```powershell
git diff --cached --check
git diff --cached --name-status
git diff --cached --stat
```

### Step 5：提交规范迁移

```powershell
git commit -m "docs(spec): adopt CFFwelding V3.7 task package"
```

暂不 Push，因为 Phase 7 草稿仍使工作树不干净。

---

## Task 2：建立 Phase 7 RED 测试

**文件：**

- 修改：`scripts/Test-Phase6MotionAdapters.ps1`
- 创建：`scripts/Test-Phase7ExternalSetpoint.ps1`

### Step 1：扩展 Phase 6 AXIS_REF 白名单

将 Phase 6 的 AXIS_REF Adapter 白名单从：

```powershell
@('FB_ZAxisNcAdapter', 'FB_RAxisNcAdapter')
```

改为：

```powershell
@('FB_ZAxisNcAdapter', 'FB_ZAxisExtSetpointAdapter', 'FB_RAxisNcAdapter')
```

仍必须拒绝其他 PROGRAM/FB 使用 `VAR_IN_OUT AXIS_REF`。

### Step 2：创建 Phase 7 契约测试

`Test-Phase7ExternalSetpoint.ps1` 至少检查：

1. 下列对象各存在且只有一份，并列入 `CFFwelding.plcproj`：
   - `ST_ZExtSetpointConfig`
   - `FB_ZAxisExtSetpointAdapter`
2. `ST_ZExtSetpointCommand/Status` 已接入 `ST_FastCommand/Status`。
3. Adapter 是唯一包含以下接口的对象：
   - `MC_ExtSetPointGenEnable`
   - `MC_ExtSetPointGenFeed`
   - `MC_ExtSetPointGenDisable`
4. Enable 使用本机/官方签名：
   - `Position`
   - `PositionType := POSITIONTYPE_ABSOLUTE`
   - `Options := stEnableOptions`
   - `stEnableOptions.UseTorqueOffset := FALSE`
5. 初值来自：
   - `Axis.NcToPlc.SetPos`
   - `Axis.NcToPlc.SetVelo`
   - `Axis.NcToPlc.SetAcc`
6. 状态确认使用 `Axis.Status.ExtSetPointGenEnabled` 或 FB 的 `Enabled` 输出。
7. 生命周期包含全部 V3.7 状态和退出顺序。
8. ACTIVE 每周期 Feed P/V/A/Direction，并验证 Direction 范围。
9. Enable、Feed 和 Disable 均受 `bDriveLinked`、配置和 Owner 硬门控。
10. 只有确认 Disabled 后才允许 `bReleaseOwner`。
11. `PRG_FastAxisControl` 唯一实例化 Adapter 并发布报警。
12. `PRG_CffSequence` 和算法 FB 不含 MC/AXIS_REF。
13. 未强制 `bDriveLinked`、Ready、MappingValid 或 Production Ready 为 TRUE。
14. `Docs/报告/PHASE_7_EXECUTION_REPORT.md` 最终必须存在。

### Step 3：运行 RED 测试

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase6MotionAdapters.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase7ExternalSetpoint.ps1
```

预期：

- Phase 6 在白名单调整后通过；
- Phase 7 至少因缺少显式 `ST_ExtSetPointEnableOptions.UseTorqueOffset := FALSE` 和 Phase 7 报告失败；
- 如果失败原因与目标行为无关，先修正测试，不修改生产代码。

---

## Task 3：系统定位当前 XAE Build 失败根因

**文件：**

- 修改：`scripts/Build-Cffwelding.ps1`（仅在需要增加诊断输出时）
- 检查：`CFFwelding_System/CFFwelding/CFFwelding.plcproj`
- 检查：Phase 7 DUT、GVL、PROGRAM 和 Adapter 草稿

### Step 1：建立已知证据

记录：

- 最近提交的 Phase 6 XAE Build 为 `LastBuildInfo=0`；
- 当前 Phase 7 草稿为 `LastBuildInfo=2`；
- 变更范围只包含 Phase 7 DUT、GVL、PROGRAM、Adapter 和项目编译清单。

### Step 2：先做无修改诊断

```powershell
git diff --check
Get-ChildItem CFFwelding_System\CFFwelding -Recurse -Include *.TcPOU,*.TcDUT,*.TcGVL | ForEach-Object {
    [void][xml](Get-Content -Raw -Encoding UTF8 -LiteralPath $_.FullName)
}
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1
```

从 XAE Build 输出、Error List、Automation Interface 消息或最小编译探针取得第一条具体编译诊断。不得仅根据 `LastBuildInfo=2` 猜修复。

### Step 3：核对实际 API

本机编译必须与以下签名一致：

```pascal
fbEnable(
    Axis := Axis,
    Execute := bEnablePulse,
    Position := rFeedPosition_mm,
    PositionType := POSITIONTYPE_ABSOLUTE,
    Options := stEnableOptions);

fbDisable(
    Axis := Axis,
    Execute := bDisablePulse);

bUnused := MC_ExtSetPointGenFeed(
    Axis := Axis,
    Position := rFeedPosition_mm,
    Velocity := rFeedVelocity_mm_s,
    Acceleration := rFeedAcceleration_mm_s2,
    Direction := nFeedDirection);
```

`stEnableOptions.UseTorqueOffset` 必须保持 `FALSE`。

### Step 4：一次只验证一个根因假设

优先顺序：

1. 类型/字段/枚举名称；
2. Enable/Disable/Feed 参数签名；
3. `AXIS_REF.Status` 的 BIT/BOOL 使用；
4. Structured Text 表达式或赋值类型；
5. PLC 项目编译顺序和重复 GUID。

每次只做一个最小更改并重跑 Build，记录假设和结果。

---

## Task 4：完成 External Setpoint 类型和 Adapter

**文件：**

- 修改：`CFFwelding_System/CFFwelding/DUTs/Interfaces/ST_ZExtSetpointCommand.TcDUT`
- 修改：`CFFwelding_System/CFFwelding/DUTs/Interfaces/ST_ZExtSetpointStatus.TcDUT`
- 修改：`CFFwelding_System/CFFwelding/DUTs/Structures/ST_FastCommand.TcDUT`
- 修改：`CFFwelding_System/CFFwelding/DUTs/Structures/ST_FastStatus.TcDUT`
- 创建/修改：`CFFwelding_System/CFFwelding/DUTs/Structures/ST_ZExtSetpointConfig.TcDUT`
- 创建/修改：`CFFwelding_System/CFFwelding/POUs/FunctionBlocks/Axis/FB_ZAxisExtSetpointAdapter.TcPOU`
- 修改：`CFFwelding_System/CFFwelding/GVLs/GVL_Config.TcGVL`
- 修改：`CFFwelding_System/CFFwelding/CFFwelding.plcproj`

### Step 1：完成类型契约

保留：

- Reset、Enable、Feed、Disable；
- P/V/A/Direction；
- Enabled、Busy、Done、FeedAccepted、ReleaseOwner、Error、ErrorId、State、FeedCycleCounter；
- Enable/Disable timeout；
- Standstill、位置连续性、速度步阶、Direction hold 和 Post-disable hold 配置。

所有字段使用英文 ASCII 标识符、单位后缀和中文独立行注释。

### Step 2：增加明确 Owner 门控

Adapter 增加：

```pascal
(* Z轴Owner已经由仲裁器授予Force Process。 *)
bOwnerGranted : BOOL;
```

规则：

- 未活动时没有 Owner 不允许 Enable；
- 活动时 Owner 请求撤销或 Fault Stop 触发受控退出；
- Owner 只能在 Disabled 确认和后保持完成后释放。

### Step 3：显式禁用 TorqueOffset

声明：

```pascal
stEnableOptions : ST_ExtSetPointEnableOptions;
```

每扫描明确执行：

```pascal
stEnableOptions.UseTorqueOffset := FALSE;
```

Enable 调用传入 `Options := stEnableOptions`。Phase 7 不调用 `MC_ExtSetPointGenFeedWithTorque`。

### Step 4：完成生命周期和安全退出

实现并注释：

- PRECHECK：配置、Owner、驱动、轴、周期和硬限值；
- PRELOAD/PREFEED：用 `SetPos/SetVelo/SetAcc` 建立连续初值；
- ENABLE/WAIT_ENABLED：Execute 上升沿和 timeout；
- ACTIVE：连续性检查并每 Fast/SAF Feed；
- RAMP_TO_ZERO：按最大加速度限速并梯形积分位置；
- HOLD_DIRECTION：保持最后非零方向；
- DIRECTION_ZERO：零速零加速度、方向归零并 Feed；
- DISABLE/WAIT_DISABLED：Disable 上升沿、至少一个附加 Feed 周期和 timeout；
- POST_DISABLE_HOLD：至少一个 SAF；
- DONE/ERROR：正确的 Reset 和 ReleaseOwner。

### Step 5：运行局部测试和 Build

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase6MotionAdapters.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase7ExternalSetpoint.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1
```

预期：Phase 7 测试只允许因执行报告尚未创建而失败；XAE Build 必须为 `LastBuildInfo=0`。

---

## Task 5：接入 PRG_FastAxisControl、Owner 和报警

**文件：**

- 修改：`CFFwelding_System/CFFwelding/POUs/Fast/PRG_FastAxisControl.TcPOU`
- 检查：`CFFwelding_System/CFFwelding/POUs/FunctionBlocks/Axis/FB_AxisCommandArbiter.TcPOU`
- 检查：`CFFwelding_System/CFFwelding/DUTs/Enums/E_AlarmCode.TcDUT`

### Step 1：唯一实例和调用顺序

`PRG_FastAxisControl` 中只声明一个：

```pascal
fbZExtSetpoint : FB_ZAxisExtSetpointAdapter;
```

实例前中文块注释必须说明任务、Owner、输入、输出和 Reset 生命周期。

调用顺序：

```text
构造候选命令
→ AxisCommandArbiter
→ 标准 Z NC Adapter
→ External Setpoint Adapter
→ R NC Adapter
→ 发布状态和报警
```

### Step 2：Owner 连接

`bOwnerGranted` 仅在：

```pascal
fbZAxisArbiter.eActiveOwner = E_ZCommandOwner.Z_OWNER_FORCE_PROCESS
```

时为 TRUE。

Arbiter 的 `bForceProcessExitComplete` 只能在：

- 本次不使用 External；或
- Adapter 明确发布 `bReleaseOwner`；

时成立。

### Step 3：状态和报警

- 发布 `GVL_Status.stFast.stZExtSetpoint`；
- `stZAxis.bExternalSetpointActive` 来自真实 Enabled 状态；
- Adapter 错误合并到 Z 轴状态；
- External 报警使用唯一槽位和 `ALARM_EXTERNAL_SETPOINT_FAULT`；
- FastTask 不处理中文字符串。

### Step 4：重跑测试和 Build

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase6MotionAdapters.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase7ExternalSetpoint.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1
```

---

## Task 6：Phase 1–7 全回归和源码 Commit

**文件：**

- 测试：`scripts/Test-Phase1Project.ps1` 至 `scripts/Test-Phase7ExternalSetpoint.ps1`
- Build：`scripts/Build-Cffwelding.ps1`

### Step 1：运行完整静态回归

依次运行 Phase 1–7 测试。任何失败必须先定位根因，不得放宽与 V3.7 冲突无关的安全检查。

### Step 2：执行最终真实 XAE Build

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1
```

必须看到：

```text
CFFwelding XAE build: PASSED
LastBuildInfo: 0
```

### Step 3：审查边界

检查：

```powershell
git diff --check
git diff --stat
rg -n "MC_ExtSetPointGen" CFFwelding_System\CFFwelding
rg -n "bDriveLinked\s*:=\s*TRUE|Production.*:=\s*TRUE|Ready\s*:=\s*TRUE" CFFwelding_System\CFFwelding
```

预期：

- External API 只出现在 Adapter；
- 没有新真实 I/O、驱动或 Safety 配置；
- 没有伪造绑定、Ready 或 Production Ready。

### Step 4：提交 Phase 7 源码

只暂存 Phase 7 DUT、GVL、Adapter、PROGRAM、PLC project 和测试脚本：

```powershell
git commit -m "feat(motion): add external setpoint lifecycle"
```

记录 Commit Hash，供执行报告使用。

---

## Task 7：生成 Phase 7 报告并提交

**文件：**

- 创建：`Docs/报告/PHASE_7_EXECUTION_REPORT.md`
- 修改：`Docs/报告/TWINCAT_BUILD_REPORT.md`
- 修改：`Docs/报告/INSTANCE_OWNERSHIP_MATRIX.md`
- 修改：`Docs/报告/INTERNAL_INTERFACE_CATALOG.md`
- 修改：`Docs/报告/NC_CONFIGURATION_CHECKLIST.md`
- 修改：`Docs/报告/GIT_EXECUTION_REPORT.md`

### Step 1：填写证据

报告必须记录：

- 本机 XAE 和 Tc2_MC2 版本；
- 官方/本机签名核对结果；
- 2 ms Fast/离线 SAF 周期；
- Enable/Feed/Disable 和完整退出；
- Owner、唯一实例和 MC 边界；
- 静态测试输出；
- XAE Build `LastBuildInfo`；
- 源码 Commit Hash；
- 未执行任何硬件操作；
- External POC、真实驱动、抖动、硬件映射和工艺资格仍未完成。

### Step 2：关闭报告闸门并复验

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase7ExternalSetpoint.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1
git diff --check
```

### Step 3：提交报告

```powershell
git commit -m "docs(report): record Phase 7 external setpoint verification"
```

---

## Task 8：Push 检查与 Phase 8 交接

### Step 1：确认工作树

```powershell
git status --short --branch
git log --oneline --decorate -n 20
```

工作树必须干净；如仍有文件，不得 Push，先准确分类并处理。

### Step 2：有界远程复核

```powershell
git ls-remote --symref origin HEAD
git fetch --prune origin
```

如果网络或认证失败：

- 不循环重试；
- 不修改 Remote；
- 不读取或记录认证信息；
- 保留本地 Commit 并记录精确错误。

### Step 3：Push 当前用户指定分支

```powershell
git push origin codex/cffwelding-greenfield-v3.3
```

不得 Push 到任务书中冲突的 `...final-v3.3` 分支，除非用户另行明确要求。

### Step 4：进入下一子项目

基于已批准的 V3.7 总设计，创建 Phase 8 导纳力控的详细实施计划，继续使用测试先行、真实 Build、审查、Commit 和 Push 流程。
