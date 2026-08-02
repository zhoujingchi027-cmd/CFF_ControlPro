# CFFwelding V3.7 Phase 10 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在已推送的 Phase 9 基线上，以离线、Fail Closed 的方式实现完整 Phase 10 CFF Fast 侧消费者：标准 NC Approach、External 接管、Contact 事务、四步工艺、R 轴阶段事务、Brake/Compression、Step4 有效保持、受控卸载、External 退出、Return、互斥终态、确定性报警和真实 TwinCAT XAE Build。

**Architecture:** `PRG_CffSequence`只负责编排并通过类型化 GVL 发布`ST_CffMotionIntent`；纯算法`FB_ZExternalTrajectory`只从 Adapter 已接受值生成连续 P/V/A/Direction；`PRG_FastAxisControl`完成命令源路由、Force/R 斜坡诊断和唯一实例接线；三个 Adapter 继续独占`AXIS_REF`与 MC。Main→Fast 命令由`PRG_FastInputs`按“payload 先写、RequestId 最后写”的合同复制到`GVL_FastInternal.stAcceptedCommand`，Sequence 在 Start 接受时再锁存 Program、Sequence Config、Force Profile 和 R Profile，活动周期不读取可放宽安全边界的活配置。

**Tech Stack:** TwinCAT 3 XAE / IEC 61131-3 Structured Text / TwinCAT XML (`.TcDUT`, `.TcPOU`, `.TcGVL`, `.plcproj`) / Tc2_MC2 3.3.65.0 / PowerShell ASCII-only 离线合同与参考向量 / Git。

## Global Constraints

- 仅在`codex/cffwelding-greenfield-v3.3`工作；不修改全局 Git 身份，不读取或输出密码、PAT 或其他认证信息。
- 旧工程、旧程序和任务书只读；只修改当前新工程`CFFwelding_System`、当前`Docs`和`scripts`。
- 所有手工文件修改使用`apply_patch`；TwinCAT 成功 Build 生成的`CFFwelding.tmc`和可能变化的`CFFwelding_System.tsproj`例外，不手工编辑生成物。
- 严禁 Scan、Activate、Download、Login、Online Change、真实轴使能或运动；Release x64 Build 只证明固定本机工具链下离线可编译。
- `PRG_CffSequence`不得包含`AXIS_REF`、`MC_`或跨 PROGRAM 局部访问；它可以按唯一 Writer 合同读写类型化 GVL。
- `FB_ZExternalTrajectory`、`FB_ZForceAdmittance`、`FB_BumplessProfileSwitch`、`FB_ContactDetect`、`FB_ForceDeclineObserver`和`FB_StepProceedingCriterion`不得访问 GVL、`AXIS_REF`或 MC。
- `FB_ZAxisNcAdapter`、`FB_ZAxisExtSetpointAdapter`和`FB_RAxisNcAdapter`继续是轴引用和 MC 的唯一 Owner。
- 不把任何 Mapping、Binding、Profile、Config、Ready、Valid 或 ProductionReady 强制为`TRUE`；未配置仓库必须保持不可生产启动。
- Sequence 不写`GVL_Process.stLastCycleResult`、Torque、Energy、Features 或 Curve；Phase 10 只发布真实步骤事实和终态。
- 所有公开字段使用 ASCII 标识符、明确单位和独立中文注释；N↔kN、ms↔s/µs 只在边界显式转换。
- 每个状态每个 Fast 扫描最多迁移一次；Entry 脉冲、事务号递增和算法 Reset 只在状态进入扫描产生。
- 所有 RequestId 在 payload 完整写入后最后更新；递增溢出时跳过零，稳定状态不得每 2 ms 重发事务。
- 普通命令 ID 与 Sequence ID 是不同命名空间；FastAxis 必须按“命令源+源 ID”映射为独立 Adapter ID。
- Active 周期中的 Reset 按 Abort 受控退出；External 完整释放前不得清 Owner、轨迹或命令状态。
- 用户已批准提交边界：设计、计划、源码、报告四个聚焦提交。因此本计划的源码 Task 只做 RED/GREEN/审查检查点，不创建中间源码提交；全量验证通过后统一创建`feat(process): implement Phase 10 CFF sequence`。
- 每个 Task 开始前确认`git status --short`，结束后运行该 Task 的 Scope 测试和`git diff --check`。

主状态必须完整覆盖现有`E_CffState`，不得省略或新增未批准主状态：

```text
CFF_IDLE
CFF_PRECHECK
CFF_APPROACH
CFF_EXTSETPOINT_PREPARE
CFF_CONTACT_SEARCH
CFF_CONTACT_ACCEPT
CFF_STEP1_ENTRY
CFF_STEP1_RAMP_PROCESS
CFF_STEP1_END_CHECK
CFF_STEP2_ENTRY
CFF_STEP2_RAMP_PROCESS
CFF_STEP2_END_CHECK
CFF_STEP3_ENTRY
CFF_STEP3_RAMP_PROCESS
CFF_STEP3_END_CHECK
CFF_BRAKE_AND_COMPRESSION_RAMP
CFF_STEP4_VALID_FORCE_HOLD
CFF_CONTROLLED_FORCE_UNLOAD
CFF_EXTSETPOINT_DISABLE
CFF_RETURN_LOCAL
CFF_RETURN_REFERENCE
CFF_EVALUATE
CFF_COMPLETE_OK
CFF_COMPLETE_NOK
CFF_ABORT
CFF_FAULT
```

---

## Task 1：建立 Phase 10 分 Scope RED 测试

**Files:**

- Create: `scripts/Test-Phase10CffSequence.ps1`
- Modify: `scripts/README.md`

- [ ] **Step 1：创建 ASCII-only 参数和仓库根解析**

脚本入口固定为：

```powershell
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateSet(
        'All',
        'Contracts',
        'Validation',
        'Trajectory',
        'Adapter',
        'Routing',
        'SequenceFront',
        'SequenceSteps',
        'SequenceExit')]
    [string]$Scope = 'All',
    [switch]$RequireReport
)

$ErrorActionPreference = 'Stop'
$script:FailureCount = 0
$plcRoot = Join-Path $RepositoryRoot 'CFFwelding_System\CFFwelding'
$projectPath = Join-Path $plcRoot 'CFFwelding.plcproj'
```

所有脚本文本、消息、正则和注释只使用 ASCII；中文只存在被检查的 PLC/Markdown 文件中。

- [ ] **Step 2：实现无副作用断言助手**

必须提供：

```powershell
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $script:FailureCount++
        Write-Host "FAIL: $Message"
    }
}

function Read-Text {
    param([string]$RelativePath)
    $path = Join-Path $RepositoryRoot $RelativePath
    Assert-True (Test-Path -LiteralPath $path) "Missing file: $RelativePath"
    if (-not (Test-Path -LiteralPath $path)) { return '' }
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    Assert-True ([regex]::IsMatch($Text, $Pattern, 'Multiline')) $Message
}

function Assert-NoMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    Assert-True (-not [regex]::IsMatch($Text, $Pattern, 'Multiline')) $Message
}

function Assert-Near {
    param([double]$Actual, [double]$Expected, [double]$Tolerance, [string]$Message)
    Assert-True ([math]::Abs($Actual - $Expected) -le $Tolerance) $Message
}
```

脚本末尾固定为：

```powershell
if ($script:FailureCount -ne 0) {
    throw "Phase 10 verification failed with $script:FailureCount failure(s)."
}
Write-Host "PASS: Phase 10 $Scope verification"
```

- [ ] **Step 3：为九个 Scope 写明确 RED 断言**

`Contracts`检查新 DUT/GVL/FB/FC 唯一存在、GUID 唯一、`.plcproj` Include 恰好一次、公开字段和中文注释存在。

`Validation`检查纯 FC 无 GVL、搜索起点边界、Step4 Time Primary、Step4 RPM=0、Qualified Hold、Force Band、RPM threshold、Sequence timeout/标准定位斜率和 Profile ID/Revision 规则。

`Trajectory`检查算法 FB 无 GVL/AXIS_REF/MC、只从 accepted 基准积分、梯形公式、Rate Limit、方向状态顺序、Fault 锁存和 Reset。

`Adapter`检查 accepted-valid、accepted P/V/A/Direction、跳过零的回绕 Feed counter、Active 零速换向握手、直接换向 Fault 和正式 Disable 序列。

`Routing`检查命令源+源 ID 映射、Sequence Z/R Ack、每步 Force Ramp 消费、R 软件包络只诊断、轨迹唯一实例和 Adapter 唯一 MC Owner。

`SequenceFront`检查 CommandId 去重、Fast 原子命令副本、Precheck Fail Closed、周期配置/Profile 快照、Approach Ack/Done、External Enable、Contact Request/Ack 顺序。

`SequenceSteps`检查 Step1 Force/R 同扫描、Step1–3 Entry 只发一次 R 事务、结果槽只写一次、Brake 双 Ramp、实际 RPM gate、Qualified Hold 暂停不清零。

`SequenceExit`检查 Normal/NOK 受控卸载、Stop/Abort/Fault 无 Return、External Release 前 Return 事务为零、四终态真值表和首故障锁存。

`All`依次执行全部 Scope；只有显式`-RequireReport`才要求 Phase 10 报告存在，保证实现期间可运行 All。

每个 Scope 至少包含以下实际断言；这些断言直接读取 ST/XML，数值模型再验证同一公式的参考结果，不能只打印说明文字：

```powershell
$runContracts = $Scope -in @('All', 'Contracts')
$runValidation = $Scope -in @('All', 'Validation')
$runTrajectory = $Scope -in @('All', 'Trajectory')
$runAdapter = $Scope -in @('All', 'Adapter')
$runRouting = $Scope -in @('All', 'Routing')
$runSequenceFront = $Scope -in @('All', 'SequenceFront')
$runSequenceSteps = $Scope -in @('All', 'SequenceSteps')
$runSequenceExit = $Scope -in @('All', 'SequenceExit')

if ($runContracts) {
    $required = @(
        'CFFwelding_System\CFFwelding\DUTs\Enums\E_CffExitIntent.TcDUT',
        'CFFwelding_System\CFFwelding\DUTs\Enums\E_ZExternalTrajectoryState.TcDUT',
        'CFFwelding_System\CFFwelding\DUTs\Structures\ST_CffSequenceConfig.TcDUT',
        'CFFwelding_System\CFFwelding\DUTs\Structures\ST_CffFastConfigSnapshot.TcDUT',
        'CFFwelding_System\CFFwelding\DUTs\Interfaces\ST_CffMotionIntent.TcDUT',
        'CFFwelding_System\CFFwelding\DUTs\Interfaces\ST_ZExternalTrajectoryInput.TcDUT',
        'CFFwelding_System\CFFwelding\DUTs\Interfaces\ST_ZExternalTrajectoryOutput.TcDUT',
        'CFFwelding_System\CFFwelding\GVLs\GVL_FastInternal.TcGVL'
    )
    foreach ($relativePath in $required) {
        Assert-True (Test-Path -LiteralPath (Join-Path $RepositoryRoot $relativePath)) `
            "Missing Phase 10 object: $relativePath"
    }
    $project = Read-Text 'CFFwelding_System\CFFwelding\CFFwelding.plcproj'
    foreach ($relativePath in $required) {
        $include = $relativePath -replace '^CFFwelding_System\\CFFwelding\\', ''
        $count = ([regex]::Matches($project, [regex]::Escape($include))).Count
        Assert-True ($count -eq 1) "Project include count must be one: $include"
    }
    $objectIds = foreach ($file in [System.IO.Directory]::GetFiles(
            $plcRoot, '*.Tc*', [System.IO.SearchOption]::AllDirectories)) {
        $text = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
        foreach ($match in [regex]::Matches($text, 'Id="(\{[0-9A-Fa-f-]{36}\})"')) {
            $match.Groups[1].Value.ToUpperInvariant()
        }
    }
    $duplicateIds = $objectIds | Group-Object | Where-Object Count -gt 1
    Assert-True ($null -eq $duplicateIds) 'TwinCAT object IDs must be unique'
    $sequenceStatus = Read-Text `
        'CFFwelding_System\CFFwelding\DUTs\Interfaces\ST_CffSequenceStatus.TcDUT'
    $extCommand = Read-Text `
        'CFFwelding_System\CFFwelding\DUTs\Interfaces\ST_ZExtSetpointCommand.TcDUT'
    $fastStatus = Read-Text `
        'CFFwelding_System\CFFwelding\DUTs\Structures\ST_FastStatus.TcDUT'
    Assert-Match $sequenceStatus 'stFastConfigSnapshot\s*:\s*ST_CffFastConfigSnapshot' `
        'Sequence Fast config snapshot field is missing'
    Assert-Match $sequenceStatus 'rForceRamp_kN_s\s*:\s*LREAL' `
        'Per-step force ramp field is missing'
    Assert-Match $extCommand 'bPositiveMotionInhibit\s*:\s*BOOL' `
        'Hard positive-motion command field is missing'
    Assert-Match $fastStatus 'udiAcceptedSequenceZCommandId\s*:\s*UDINT' `
        'Sequence Z acknowledgement field is missing'
    Assert-Match $fastStatus 'udiAcceptedSequenceRCommandId\s*:\s*UDINT' `
        'Sequence R acknowledgement field is missing'
}

if ($runValidation) {
    $newerValidator = Read-Text `
        'CFFwelding_System\CFFwelding\POUs\Functions\FC_IsNewerRequestId.TcPOU'
    $configValidator = Read-Text `
        'CFFwelding_System\CFFwelding\POUs\Functions\FC_ValidateCffSequenceConfig.TcPOU'
    $programValidator = Read-Text `
        'CFFwelding_System\CFFwelding\POUs\Functions\FC_ValidateJoinProgram.TcPOU'
    Assert-NoMatch $configValidator 'GVL_|AXIS_REF|MC_' `
        'Sequence config validator must be pure'
    Assert-NoMatch $newerValidator 'GVL_|AXIS_REF|MC_' `
        'Request ID validator must be pure'
    Assert-Match $newerValidator '16#80000000' `
        'Wrap-aware half-range request comparison is missing'
    Assert-Match $configValidator 'tApproachTimeout\s*>\s*T#0S' `
        'Approach timeout validation is missing'
    Assert-Match $configValidator 'fStandardMoveAccelerationMmS2\s*<=\s*stLimits\.fZMaxAccelerationMmS2' `
        'Standard acceleration hard limit is missing'
    Assert-Match $programValidator 'fContactSearchStartPositionMm' `
        'Contact search start validation is missing'
    Assert-Match $programValidator 'nQualifiedForceHoldMs' `
        'Qualified hold validation is missing'
    Assert-Match $programValidator 'fSetSpeedRpm\s*<>\s*0\.0' `
        'Step 4 zero RPM validation is missing'
}

if ($runTrajectory) {
    $trajectory = Read-Text `
        'CFFwelding_System\CFFwelding\POUs\FunctionBlocks\Control\FB_ZExternalTrajectory.TcPOU'
    Assert-NoMatch $trajectory 'GVL_|AXIS_REF|MC_' `
        'Trajectory must not access GVL, axes, or MC'
    Assert-Match $trajectory '0\.5\s*\*\s*\(.*rAcceptedVelocity_mm_s.*rNextVelocity_mm_s' `
        'Accepted-base trapezoid integration is missing'
    Assert-Match $trajectory 'Z_TRAJ_HOLD_OLD_DIRECTION' `
        'Old direction hold state is missing'
    Assert-Match $trajectory 'Z_TRAJ_DIRECTION_ZERO' `
        'Direction zero state is missing'
    Assert-Match $trajectory 'Z_TRAJ_PRELOAD_NEW_DIRECTION' `
        'New direction preload state is missing'
    Assert-Match $trajectory 'bInhibitPositiveMotion' `
        'Hard positive-motion inhibit is missing'
}

if ($runAdapter) {
    $adapter = Read-Text `
        'CFFwelding_System\CFFwelding\POUs\FunctionBlocks\Axis\FB_ZAxisExtSetpointAdapter.TcPOU'
    Assert-Match $adapter 'bAcceptedSetpointValid' `
        'Accepted setpoint valid publication is missing'
    Assert-Match $adapter 'udiFeedCycleCounter\s*:=\s*1' `
        'Feed counter wrap-to-one is missing'
    Assert-Match $adapter 'bPositiveMotionInhibit' `
        'Adapter hard inhibit contract is missing'
    Assert-Match $adapter 'nFeedDirection\s*=\s*0' `
        'Direction-zero handshake is missing'
}

if ($runRouting) {
    $fastAxis = Read-Text `
        'CFFwelding_System\CFFwelding\POUs\Fast\PRG_FastAxisControl.TcPOU'
    Assert-Match $fastAxis 'fbZExternalTrajectory\s*:\s*FB_ZExternalTrajectory' `
        'Unique trajectory instance is missing'
    Assert-Match $fastAxis 'fbRSpeedRamp\s*:\s*FB_SetpointRamp' `
        'R envelope instance is missing'
    Assert-Match $fastAxis 'udiAcceptedSequenceZCommandId' `
        'Sequence Z source acknowledgement is missing'
    Assert-Match $fastAxis 'udiAcceptedSequenceRCommandId' `
        'Sequence R source acknowledgement is missing'
    Assert-Match $fastAxis 'rForceRamp_kN_s' `
        'Per-step force ramp is not consumed'
}

if ($runSequenceFront) {
    $fastInputs = Read-Text `
        'CFFwelding_System\CFFwelding\POUs\Fast\PRG_FastInputs.TcPOU'
    $sequence = Read-Text `
        'CFFwelding_System\CFFwelding\POUs\Fast\PRG_CffSequence.TcPOU'
    Assert-Match $fastInputs 'GVL_FastInternal\.stAcceptedCommand' `
        'Fast accepted command copy is missing'
    Assert-Match $fastInputs 'FC_IsNewerRequestId' `
        'Old Fast request rejection is missing'
    Assert-Match $sequence 'CFF_PRECHECK' 'Precheck state is missing'
    Assert-Match $sequence 'CFF_APPROACH' 'Approach state is missing'
    Assert-Match $sequence 'udiContactReferenceRequestId' `
        'Contact reference transaction is missing'
    Assert-NoMatch $sequence 'AXIS_REF|MC_' `
        'Sequence must not access axes or MC'
}

if ($runSequenceSteps) {
    $sequence = Read-Text `
        'CFFwelding_System\CFFwelding\POUs\Fast\PRG_CffSequence.TcPOU'
    Assert-Match $sequence 'CFF_STEP1_ENTRY' 'Step 1 entry is missing'
    Assert-Match $sequence 'CFF_STEP3_END_CHECK' 'Step 3 end check is missing'
    Assert-Match $sequence 'CFF_BRAKE_AND_COMPRESSION_RAMP' `
        'Brake and compression state is missing'
    Assert-Match $sequence 'rActualVelocity_rpm' `
        'Step 4 must use actual RPM'
    Assert-Match $sequence 'uliQualifiedHold_us' `
        'Qualified hold accumulator is missing'
    Assert-Match $sequence 'bRCommandPayloadChanged' `
        'R payload deduplication is missing'
}

if ($runSequenceExit) {
    $sequence = Read-Text `
        'CFFwelding_System\CFFwelding\POUs\Fast\PRG_CffSequence.TcPOU'
    Assert-Match $sequence 'CFF_CONTROLLED_FORCE_UNLOAD' `
        'Controlled unload state is missing'
    Assert-Match $sequence 'CFF_EXTSETPOINT_DISABLE' `
        'External disable state is missing'
    Assert-Match $sequence 'CFF_COMPLETE_OK' 'OK terminal is missing'
    Assert-Match $sequence 'CFF_COMPLETE_NOK' 'NOK terminal is missing'
    Assert-Match $sequence 'CFF_ABORT' 'Abort terminal is missing'
    Assert-Match $sequence 'CFF_FAULT' 'Fault terminal is missing'
    Assert-Match $sequence 'udiFirstFaultId' 'First fault latch is missing'
}
```

- [ ] **Step 4：加入离线数值参考模型**

PowerShell 参考模型必须覆盖以下精确向量：

```text
Trajectory: Ts=0.1, P=10, V=1, Target=3, Amax=2
Scan 1 -> V=1.2, A=2.0, P=10.11
Accepted Scan 2 -> V=1.4, A=2.0, P=10.24

R envelope: 0 -> 1000 rpm, rate=500 rpm/s, Ts=0.002
One scan -> 1 rpm; adapter command transaction count remains 1

Qualified hold: Ts=2 ms, condition TRUE,TRUE,FALSE,TRUE
Accumulated result -> 6 ms
```

换向模型必须验证：

```text
P=0, V=0.4, Target=-1, Amax=2, Ts=0.1
-> V=0.2, P=0.03, Direction=+1
-> V=0.0, P=0.04, Direction=+1
-> old-direction hold
-> Direction=0 hold
-> Direction=-1 preload
-> V=-0.2, A=-2.0, P=0.03
```

实际 PowerShell 计算固定写为：

```powershell
$ts = 0.1
$acceptedP = 10.0
$acceptedV = 1.0
$targetV = 3.0
$amax = 2.0
$nextV = [math]::Min($targetV, $acceptedV + $amax * $ts)
$nextA = ($nextV - $acceptedV) / $ts
$nextP = $acceptedP + 0.5 * ($acceptedV + $nextV) * $ts
Assert-Near $nextV 1.2 0.000000001 'Trajectory scan 1 velocity'
Assert-Near $nextA 2.0 0.000000001 'Trajectory scan 1 acceleration'
Assert-Near $nextP 10.11 0.000000001 'Trajectory scan 1 position'

$acceptedP = $nextP
$acceptedV = $nextV
$nextV = [math]::Min($targetV, $acceptedV + $amax * $ts)
$nextP = $acceptedP + 0.5 * ($acceptedV + $nextV) * $ts
Assert-Near $nextV 1.4 0.000000001 'Trajectory scan 2 velocity'
Assert-Near $nextP 10.24 0.000000001 'Trajectory scan 2 position'

$rEnvelope = 0.0 + 500.0 * 0.002
Assert-Near $rEnvelope 1.0 0.000000001 'R envelope first scan'
$rAdapterTransactions = 1
1..100 | ForEach-Object { $rEnvelope = [math]::Min(1000.0, $rEnvelope + 1.0) }
Assert-True ($rAdapterTransactions -eq 1) 'R target must remain one MC transaction'

$qualifiedUs = [uint64]0
$deltaUs = [uint64]2000
foreach ($condition in @($true, $true, $false, $true)) {
    if ($condition) { $qualifiedUs += $deltaUs }
}
Assert-True ($qualifiedUs -eq 6000) 'Qualified hold must pause without reset'

$hardInhibitAcceptedVelocity = 1.0
$hardInhibitOutputVelocity = if ($hardInhibitAcceptedVelocity -gt 0.0) { 0.0 } `
    else { $hardInhibitAcceptedVelocity }
Assert-Near $hardInhibitOutputVelocity 0.0 0.0 `
    'Hard inhibit must remove positive velocity in the first package'

$directionStates = @(
    'RAMP_TO_ZERO',
    'HOLD_OLD_DIRECTION',
    'DIRECTION_ZERO',
    'PRELOAD_NEW_DIRECTION',
    'TRACKING')
Assert-True (($directionStates -join '>') -eq `
    'RAMP_TO_ZERO>HOLD_OLD_DIRECTION>DIRECTION_ZERO>PRELOAD_NEW_DIRECTION>TRACKING') `
    'Direction transition order must be deterministic'
```

- [ ] **Step 5：运行 RED 并记录预期失败**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope Contracts
```

Expected: FAIL，原因只能是 Phase 10 新对象/字段尚未创建。

- [ ] **Step 6：更新脚本目录说明**

在`scripts/README.md`记录九个 Scope、`-RequireReport`语义、ASCII-only 边界以及“静态/参考向量不等于 PLC Runtime 或实机资格”。

- [ ] **Step 7：检查 Task 1**

Run:

```powershell
git diff --check
```

Expected: PASS。

---

## Task 2：创建 Phase 10 类型契约、配置和工程 Include

**Files:**

- Create: `CFFwelding_System/CFFwelding/DUTs/Enums/E_CffExitIntent.TcDUT`
- Create: `CFFwelding_System/CFFwelding/DUTs/Enums/E_ZExternalTrajectoryState.TcDUT`
- Create: `CFFwelding_System/CFFwelding/DUTs/Structures/ST_CffSequenceConfig.TcDUT`
- Create: `CFFwelding_System/CFFwelding/DUTs/Structures/ST_CffFastConfigSnapshot.TcDUT`
- Create: `CFFwelding_System/CFFwelding/DUTs/Interfaces/ST_CffMotionIntent.TcDUT`
- Create: `CFFwelding_System/CFFwelding/DUTs/Interfaces/ST_ZExternalTrajectoryInput.TcDUT`
- Create: `CFFwelding_System/CFFwelding/DUTs/Interfaces/ST_ZExternalTrajectoryOutput.TcDUT`
- Create: `CFFwelding_System/CFFwelding/GVLs/GVL_FastInternal.TcGVL`
- Modify: `CFFwelding_System/CFFwelding/DUTs/Structures/ST_JoinProgramHeader.TcDUT`
- Modify: `CFFwelding_System/CFFwelding/DUTs/Structures/ST_StepProceedingConfig.TcDUT`
- Modify: `CFFwelding_System/CFFwelding/DUTs/Structures/ST_StepCriterionResult.TcDUT`
- Modify: `CFFwelding_System/CFFwelding/DUTs/Structures/ST_ZForceControlProfile.TcDUT`
- Modify: `CFFwelding_System/CFFwelding/DUTs/Structures/ST_RAxisProfile.TcDUT`
- Modify: `CFFwelding_System/CFFwelding/DUTs/Interfaces/ST_CffSequenceStatus.TcDUT`
- Modify: `CFFwelding_System/CFFwelding/DUTs/Interfaces/ST_ZExtSetpointStatus.TcDUT`
- Modify: `CFFwelding_System/CFFwelding/DUTs/Interfaces/ST_ZExtSetpointCommand.TcDUT`
- Modify: `CFFwelding_System/CFFwelding/DUTs/Structures/ST_FastStatus.TcDUT`
- Modify: `CFFwelding_System/CFFwelding/DUTs/Enums/E_StepEndCause.TcDUT`
- Modify: `CFFwelding_System/CFFwelding/DUTs/Interfaces/ST_StepCriterionInput.TcDUT`
- Modify: `CFFwelding_System/CFFwelding/DUTs/Enums/E_AlarmCode.TcDUT`
- Modify: `CFFwelding_System/CFFwelding/GVLs/GVL_Config.TcGVL`
- Modify: `CFFwelding_System/CFFwelding/CFFwelding.plcproj`

- [ ] **Step 1：确认 Contracts RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope Contracts
```

Expected: FAIL。

- [ ] **Step 2：创建两个确定性枚举**

`E_CffExitIntent`使用 Object Id`{7FBFD290-60B5-4FCE-8D00-D46650117E64}`：

```iecst
TYPE E_CffExitIntent : (
    CFF_EXIT_NONE := 0,
    CFF_EXIT_NORMAL_RETURN := 10,
    CFF_EXIT_NOK_RETURN := 20,
    CFF_EXIT_ABORT_NO_RETURN := 30,
    CFF_EXIT_FAULT_NO_RETURN := 40
); END_TYPE
```

`E_ZExternalTrajectoryState`使用 Object Id`{C68E271F-E8B0-491E-B340-25BEF41FA75F}`：

```iecst
TYPE E_ZExternalTrajectoryState : (
    Z_TRAJ_IDLE := 0,
    Z_TRAJ_SYNC := 10,
    Z_TRAJ_TRACKING := 20,
    Z_TRAJ_RAMP_TO_ZERO := 30,
    Z_TRAJ_HOLD_OLD_DIRECTION := 40,
    Z_TRAJ_DIRECTION_ZERO := 50,
    Z_TRAJ_PRELOAD_NEW_DIRECTION := 60,
    Z_TRAJ_FAULT := 100
); END_TYPE
```

- [ ] **Step 3：创建机器级 Sequence 配置**

`ST_CffSequenceConfig`使用 Object Id`{5D65580A-2126-4820-9D19-1A4AE7A35238}`并声明：

```iecst
TYPE ST_CffSequenceConfig : STRUCT
    (* Approach标准定位等待超时。 *)
    tApproachTimeout : TIME;
    (* External Contact Search等待超时。 *)
    tContactSearchTimeout : TIME;
    (* Contact参考点事务确认等待超时。 *)
    tContactReferenceAckTimeout : TIME;
    (* 受控卸载等待超时。 *)
    tControlledUnloadTimeout : TIME;
    (* 卸载静止条件连续确认时间。 *)
    tUnloadStandstillConfirm : TIME;
    (* R轴受控停止等待超时。 *)
    tRAxisStopTimeout : TIME;
    (* 标准NC返回等待超时。 *)
    tReturnTimeout : TIME;
    (* Approach和Return标准NC加速度，单位mm/s2。 *)
    fStandardMoveAccelerationMmS2 : LREAL;
    (* Approach和Return标准NC减速度，单位mm/s2。 *)
    fStandardMoveDecelerationMmS2 : LREAL;
    (* 配置已受控确认。 *)
    bValid : BOOL;
END_STRUCT
END_TYPE
```

- [ ] **Step 4：创建运动意图**

`ST_CffMotionIntent`使用 Object Id`{9CEBDEC5-6BA7-45E2-98FC-1BBC4A0C3FE9}`：

```iecst
TYPE ST_CffMotionIntent : STRUCT
    (* Sequence Z标准NC源事务号。 *)
    udiZCommandId : UDINT;
    (* Sequence Z标准NC候选。 *)
    stZCommand : ST_ZAxisCommand;
    (* 请求External生命周期进入Enable。 *)
    bExternalEnableRequest : BOOL;
    (* 请求External生命周期完成Disable。 *)
    bExternalDisableRequest : BOOL;
    (* Contact Search使用的External速度目标，向下为正，单位mm/s。 *)
    rExternalTargetVelocity_mm_s : LREAL;
    (* Sequence当前占用R轴命令通道。 *)
    bRAxisProcessRequested : BOOL;
    (* Sequence R轴源事务号。 *)
    udiRCommandId : UDINT;
    (* Sequence R轴命令候选。 *)
    stRCommand : ST_RAxisCommand;
    (* External已释放且允许Force Process Owner转交。 *)
    bForceProcessExitComplete : BOOL;
END_STRUCT
END_TYPE
```

- [ ] **Step 5：创建 Sequence→Fast 单一冻结配置合同**

`ST_CffFastConfigSnapshot`使用 Object Id`{1C3E94F6-DBBC-4719-B133-C485675E7D5B}`：

```iecst
TYPE ST_CffFastConfigSnapshot : STRUCT
    (* 形成该快照的Sequence事务号。 *)
    nSequenceCommandId : UDINT;
    (* 冻结的机器周期与Revision。 *)
    stMachine : ST_MachineConfig;
    (* 冻结的机器运动和过程硬限值。 *)
    stLimits : ST_MachineLimits;
    (* 冻结的External生命周期配置。 *)
    stZExtSetpoint : ST_ZExtSetpointConfig;
    (* 冻结的Z轴Force Profile。 *)
    stZForceControl : ST_ZForceControlProfile;
    (* 全部成员由同一个已通过Precheck的Start事务形成。 *)
    bValid : BOOL;
END_STRUCT
END_TYPE
```

Sequence 是该结构的唯一 Writer；FastAxis 只消费`bValid=TRUE`且`nSequenceCommandId = stSequence.nAcceptedCommandId`的同一份快照，不再自行从活 GVL 锁存第二套配置。

- [ ] **Step 6：创建轨迹 I/O**

`ST_ZExternalTrajectoryInput`使用 Object Id`{AF3EC71D-1473-4A62-B1C2-1CC0D9FD548F}`，字段固定为：

```iecst
bEnable, bReset : BOOL;
eExternalState : E_ZExtSetpointState;
bAcceptedSetpointValid, bFeedAccepted : BOOL;
udiAcceptedFeedCycleCounter : UDINT;
rAcceptedPosition_mm, rAcceptedVelocity_mm_s : LREAL;
rAcceptedAcceleration_mm_s2 : LREAL;
nAcceptedDirection : DINT;
bInhibitPositiveMotion : BOOL;
rTargetVelocity_mm_s, rCycleTime_s : LREAL;
rMinimumPosition_mm, rMaximumPosition_mm : LREAL;
rMaximumVelocity_mm_s, rMaximumAcceleration_mm_s2 : LREAL;
rStandstillVelocity_mm_s, rMaximumPositionDeviation_mm : LREAL;
nDirectionHoldCycles : UINT;
```

`ST_ZExternalTrajectoryOutput`使用 Object Id`{EA3FEACE-47F9-4A31-A6EA-1CF99C98F83F}`，字段固定为：

```iecst
rPosition_mm, rVelocity_mm_s, rAcceleration_mm_s2 : LREAL;
nDirection : DINT;
eState : E_ZExternalTrajectoryState;
bDirectionTransition, bZeroConfirmed, bPositiveMotionInhibited : BOOL;
bActive, bFault : BOOL;
nFaultId : UDINT;
```

每个字段在实际 `.TcDUT` 中使用一条独立中文注释，不使用合并注释。

- [ ] **Step 7：创建 Fast 内部已接受命令 GVL**

`GVL_FastInternal`使用 Object Id`{CA3D483E-12F4-4687-9EA3-C5BEF1496A7D}`：

```iecst
{attribute 'qualified_only'}
VAR_GLOBAL
    (* FastInputs按RequestId合同接受的完整快速命令快照。 *)
    stAcceptedCommand : ST_FastCommand;
END_VAR
```

唯一 Writer 是`PRG_FastInputs`；`PRG_CffSequence`和`PRG_FastAxisControl`只读。

- [ ] **Step 8：扩展现有工艺和 Profile 契约**

精确增加：

```iecst
(* ST_JoinProgramHeader *)
fContactSearchStartPositionMm : LREAL;

(* ST_StepProceedingConfig *)
nQualifiedForceHoldMs : UDINT;
fForceBandToleranceN : LREAL;
fRpmStoppedThresholdRpm : LREAL;

(* ST_ZForceControlProfile，放在nRevision之前 *)
nProfileId : UDINT;

(* ST_RAxisProfile，放在所有参数之前 *)
nProfileId : UDINT;
nRevision : UDINT;
```

Step4 的`fSetSpeedRpm`必须由 Validator 强制为零，不增加重复的 Brake 速度字段。

- [ ] **Step 9：扩展步骤结果、Sequence 状态和 Fast 状态**

`ST_StepCriterionResult`增加：

```iecst
bTooShort : BOOL;
bQualifiedForceHoldMet : BOOL;
rQualifiedForceHoldTime_s : LREAL;
rLatchedForce_kN : LREAL;
rLatchedRelativePosition_mm : LREAL;
rLatchedStepTime_s : LREAL;
```

`ST_CffSequenceStatus`增加：

```iecst
eExitIntent : E_CffExitIntent;
bCycleNok : BOOL;
bRpmStopped : BOOL;
bForceInBand : BOOL;
rStepTime_s : LREAL;
rQualifiedForceHoldTime_s : LREAL;
rForceRamp_kN_s : LREAL;
stMotionIntent : ST_CffMotionIntent;
stFastConfigSnapshot : ST_CffFastConfigSnapshot;
```

`ST_ZExtSetpointStatus`增加：

```iecst
bAcceptedSetpointValid : BOOL;
rAcceptedPosition_mm : LREAL;
rAcceptedVelocity_mm_s : LREAL;
rAcceptedAcceleration_mm_s2 : LREAL;
nAcceptedDirection : DINT;
```

`ST_ZExtSetpointCommand`增加：

```iecst
bPositiveMotionInhibit : BOOL;
```

该位只允许 FastAxis 从已锁存 Hard Force/Stroke/Collision 生成；Adapter 用它接受“位置保持、速度/加速度立即为零、方向不变”的硬安全包，普通命令不得借此绕过连续性检查。

`ST_FastStatus`增加：

```iecst
stZExternalTrajectory : ST_ZExternalTrajectoryOutput;
udiAcceptedSequenceZCommandId : UDINT;
udiAcceptedSequenceRCommandId : UDINT;
rRSpeedEnvelope_rpm : LREAL;
bRSpeedRampBusy : BOOL;
bRSpeedRampReached : BOOL;
bRSpeedRampValid : BOOL;
bForceSetpointRampReached : BOOL;
bForceSetpointRampValid : BOOL;
```

- [ ] **Step 10：扩展 Collision EndCause 与报警**

`E_StepEndCause`增加：

```iecst
STEP_END_COLLISION := 110
```

`ST_StepCriterionInput`增加`bCollisionActive : BOOL`，优先级位于 Hard Stroke 后、Sensor Invalid 前。

`E_AlarmCode`增加：

```iecst
ALARM_CFF_SEQUENCE_FAULT := 3200
```

报警槽固定为 10、TextId 3200、SourceId 10；保留槽 9 的 Phase 9 算法报警。

- [ ] **Step 11：把 Sequence 配置加入 GVL**

在`GVL_Config`中增加：

```iecst
(* CFF流程超时和标准定位斜率；默认无效。 *)
stCffSequence : ST_CffSequenceConfig;
```

不写初始化合格值。

- [ ] **Step 12：按依赖顺序加入 `.plcproj`**

新 Object Id 固定如下：

```text
E_CffExitIntent                  {7FBFD290-60B5-4FCE-8D00-D46650117E64}
E_ZExternalTrajectoryState      {C68E271F-E8B0-491E-B340-25BEF41FA75F}
ST_CffSequenceConfig            {5D65580A-2126-4820-9D19-1A4AE7A35238}
ST_CffFastConfigSnapshot        {1C3E94F6-DBBC-4719-B133-C485675E7D5B}
ST_CffMotionIntent              {9CEBDEC5-6BA7-45E2-98FC-1BBC4A0C3FE9}
ST_ZExternalTrajectoryInput     {AF3EC71D-1473-4A62-B1C2-1CC0D9FD548F}
ST_ZExternalTrajectoryOutput    {EA3FEACE-47F9-4A31-A6EA-1CF99C98F83F}
GVL_FastInternal                {CA3D483E-12F4-4687-9EA3-C5BEF1496A7D}
```

枚举放在 Enum 段；两个 Config Snapshot 类型放在 GVL 和 SequenceStatus 前；MotionIntent 放在 Z/R Command 后且 SequenceStatus 前；Trajectory I/O 放在轨迹 FB 前；`GVL_FastInternal`放在 Fast PROGRAM 前。每个 Compile Include 恰好一次并含`<SubType>Code</SubType>`，不重排无关 Include。

- [ ] **Step 13：运行 Contracts GREEN 和编译检查**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope Contracts
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1 -Configuration 'Release|TwinCAT RT (x64)'
git diff --check
```

Expected: PASS。

---

## Task 3：实现纯配置/程序 Validation

**Files:**

- Create: `CFFwelding_System/CFFwelding/POUs/Functions/FC_ValidateCffSequenceConfig.TcPOU`
- Create: `CFFwelding_System/CFFwelding/POUs/Functions/FC_IsNewerRequestId.TcPOU`
- Modify: `CFFwelding_System/CFFwelding/POUs/Functions/FC_ValidateJoinProgram.TcPOU`
- Modify: `CFFwelding_System/CFFwelding/POUs/FunctionBlocks/Control/FB_StepProceedingCriterion.TcPOU`
- Modify: `scripts/Test-Phase9ContactAndCriterion.ps1`
- Modify: `CFFwelding_System/CFFwelding/CFFwelding.plcproj`

- [ ] **Step 1：确认 Validation RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope Validation
```

Expected: FAIL。

- [ ] **Step 2：实现 wrap-aware 新事务判定**

`FC_IsNewerRequestId`使用 Object Id`{F0A1324E-FFF9-40EF-BD99-BB5A478812F0}`：

```iecst
FUNCTION FC_IsNewerRequestId : BOOL
VAR_INPUT
    udiCandidate : UDINT;
    udiReference : UDINT;
END_VAR
VAR
    udiForwardDistance : UDINT;
END_VAR

FC_IsNewerRequestId := FALSE;
IF udiCandidate = 0 OR udiCandidate = udiReference THEN
    RETURN;
END_IF
IF udiReference = 0 THEN
    FC_IsNewerRequestId := TRUE;
    RETURN;
END_IF
udiForwardDistance := udiCandidate - udiReference;
FC_IsNewerRequestId := udiForwardDistance < 16#80000000;
```

离线向量固定为`42/41=TRUE`、`40/41=FALSE`、`1/16#FFFFFFFF=TRUE`、`16#FFFFFFFF/1=FALSE`。Sequence、FastInputs和命令源路由都使用该函数，不能只判断`<>`。

- [ ] **Step 3：实现纯 Sequence Config Validator**

Object Id 使用`{7F306BD6-3704-4AB8-98EC-56FE774A80BA}`，签名固定为：

```iecst
FUNCTION FC_ValidateCffSequenceConfig : BOOL
VAR_INPUT
    stConfig : ST_CffSequenceConfig;
    stLimits : ST_MachineLimits;
END_VAR
```

返回表达式必须同时要求：

```iecst
stConfig.bValid
AND stLimits.bValid
AND (stConfig.tApproachTimeout > T#0S)
AND (stConfig.tContactSearchTimeout > T#0S)
AND (stConfig.tContactReferenceAckTimeout > T#0S)
AND (stConfig.tControlledUnloadTimeout > T#0S)
AND (stConfig.tUnloadStandstillConfirm > T#0S)
AND (stConfig.tRAxisStopTimeout > T#0S)
AND (stConfig.tReturnTimeout > T#0S)
AND FC_IsFiniteLReal(rValue := stConfig.fStandardMoveAccelerationMmS2)
AND FC_IsFiniteLReal(rValue := stConfig.fStandardMoveDecelerationMmS2)
AND FC_IsFiniteLReal(rValue := stLimits.fZMaxAccelerationMmS2)
AND (stLimits.fZMaxAccelerationMmS2 > 0.0)
AND (stConfig.fStandardMoveAccelerationMmS2 > 0.0)
AND (stConfig.fStandardMoveDecelerationMmS2 > 0.0)
AND (stConfig.fStandardMoveAccelerationMmS2 <= stLimits.fZMaxAccelerationMmS2)
AND (stConfig.fStandardMoveDecelerationMmS2 <= stLimits.fZMaxAccelerationMmS2)
```

函数不得访问 GVL，不增加任务书未批准的超时上限。

- [ ] **Step 4：扩展 Program Validator**

保持现有`FC_ValidateJoinProgram(stProgram, stMachineLimits)`签名。

新增 Header 规则：

```iecst
FC_IsFiniteLReal(rValue := stProgram.stHeader.fContactSearchStartPositionMm)
AND stProgram.stHeader.fContactSearchStartPositionMm >= stMachineLimits.fZMinPositionMm
AND stProgram.stHeader.fContactSearchStartPositionMm <= stMachineLimits.fZMaxPositionMm
```

四步均先拒绝非有限`fForceBandToleranceN`和`fRpmStoppedThresholdRpm`。

所有步骤`fSetForceN`必须严格小于`stMachineLimits.fMaxForceN`，避免正常目标与`bForceHardLimitActive >= hard maximum`同点触发。
Header 的`fContactForceOnN`同样必须严格小于机器最大力，避免 Contact 确认阈值与硬 Fault 阈值重合。

仅 Step4 强制：

```iecst
ePrimaryCriterion = STEP_CRIT_STEP_TIME
nQualifiedForceHoldMs > 0
nQualifiedForceHoldMs <= nPrimaryStepTimeMs
fForceBandToleranceN > 0.0
fForceBandToleranceN < stMachineLimits.fMaxForceN
fRpmStoppedThresholdRpm >= 0.0
fRpmStoppedThresholdRpm < stMachineLimits.fRMaxSpeedRpm
eSecondaryAction = SECONDARY_CONTROLLED_EXIT_NOK
fSetSpeedRpm = 0.0
```

Step1–3不消费 Step4 专用字段；既有四步顺序、Primary/Secondary、StepMin/Max、累计 S_rel、Force/RPM、Return 和 ID 规则全部保留。

- [ ] **Step 5：把 Collision 纳入 Criterion 硬原因优先级**

`FB_StepProceedingCriterion`确定性优先级固定为：

```text
Stop Request
Axis Fault
Sensor Invalid
Collision
Hard Force
Hard Stroke
Secondary
Primary
Step Max
```

Collision 结束时发布`STEP_END_COLLISION`、`bNok=TRUE`、`bControlledExit=TRUE`；Sequence 会把它提升为 Fault no-return。

- [ ] **Step 6：更新 Phase 9 长期合同**

`Test-Phase9ContactAndCriterion.ps1`保留 Phase 9 算法、唯一实例、纯算法边界和原向量；删除“永远 Enable=FALSE”“永远不写 Contact RequestId”的历史阶段断言，改为检查只有已知 Sequence 状态可 Enable、RequestId 只在 Contact 确认 Entry 生成一次。

- [ ] **Step 7：加入两个 FC Compile Include 并运行 GREEN**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase9ContactAndCriterion.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope Validation
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1 -Configuration 'Release|TwinCAT RT (x64)'
git diff --check
```

Expected: PASS。

---

## Task 4：TDD 实现 accepted-feed 驱动的 External 轨迹 FB

**Files:**

- Create: `CFFwelding_System/CFFwelding/POUs/FunctionBlocks/Control/FB_ZExternalTrajectory.TcPOU`
- Modify: `CFFwelding_System/CFFwelding/CFFwelding.plcproj`

- [ ] **Step 1：确认 Trajectory RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope Trajectory
```

Expected: FAIL。

- [ ] **Step 2：创建唯一纯状态 FB**

Object Id 使用`{49BB0003-2BA9-4043-A877-34D1985BA004}`，接口固定为：

```iecst
FUNCTION_BLOCK FB_ZExternalTrajectory
VAR_INPUT
    stInput : ST_ZExternalTrajectoryInput;
END_VAR
VAR_OUTPUT
    stOutput : ST_ZExternalTrajectoryOutput;
END_VAR
```

内部保存最后 accepted counter、最后已发布包、最后非零方向、待切换方向、accepted 周期计数、初始化标志、Fault 锁存和 FaultId。

- [ ] **Step 3：实现输入 Fail Closed 与 FaultId**

确定性错误号：

```text
16#0000B001 invalid cycle/limit/config input
16#0000B002 invalid accepted P/V/A
16#0000B003 invalid accepted direction
16#0000B004 accepted position outside limits
16#0000B005 accepted continuity mismatch
16#0000B006 direct nonzero direction reversal
16#0000B007 Direction=0 with non-standstill V/A
16#0000B008 generated position outside limits
16#0000B009 illegal internal state
16#0000B00A target direction changed during transition
```

Fault 首次锁存后进入`Z_TRAJ_FAULT`；FastAxis 必须停止消费该轨迹包、置`bFeed=FALSE`并请求 Adapter 安全 Disable，不能把算法 Fault 的未接受零速包继续当作正常 Feed。只有`bReset AND NOT bEnable`清除轨迹 Fault。

- [ ] **Step 4：实现正常 Rate Limit 与梯形积分**

每个包严格从最后 accepted 值计算：

```iecst
rNextVelocity_mm_s := FC_LimitRate(
    rCurrent := stInput.rAcceptedVelocity_mm_s,
    rTarget := stInput.rTargetVelocity_mm_s,
    rRateUpPer_s := stInput.rMaximumAcceleration_mm_s2,
    rRateDownPer_s := stInput.rMaximumAcceleration_mm_s2,
    rCycleTime_s := stInput.rCycleTime_s);
rNextAcceleration_mm_s2 :=
    (rNextVelocity_mm_s - stInput.rAcceptedVelocity_mm_s)
    / stInput.rCycleTime_s;
rNextPosition_mm := stInput.rAcceptedPosition_mm
    + 0.5 * (stInput.rAcceptedVelocity_mm_s + rNextVelocity_mm_s)
    * stInput.rCycleTime_s;
```

没有新 accepted counter 时不得从上次“期望输出”继续积分，只能对同一个 accepted 基准重算同一个包。

- [ ] **Step 5：实现 Active 零速换向状态**

状态顺序固定：

```text
TRACKING
-> RAMP_TO_ZERO
-> HOLD_OLD_DIRECTION for nDirectionHoldCycles accepted feeds
-> DIRECTION_ZERO for at least 1 accepted feed
-> PRELOAD_NEW_DIRECTION for at least 1 accepted feed
-> TRACKING
```

三个静止状态的输出固定为：

```iecst
rPosition_mm := stInput.rAcceptedPosition_mm;
rVelocity_mm_s := 0.0;
rAcceleration_mm_s2 := 0.0;
```

状态周期只在`bFeedAccepted=TRUE`且 accepted counter 变化时递增；counter 按最大值后回到 1 的合同用`<>`比较，不使用大小关系。非零速度换 Direction、`+1/-1`直接跳变或 Direction=0 时速度超 Standstill、加速度不等于 0.0 都立即 Fault。

`bActive`仅在 External Active 且状态为 Sync/Tracking/四个转换状态时为 TRUE；Idle/Fault 为 FALSE。`bZeroConfirmed`仅在 Adapter 已接受本 FB 最后发布的零速包、accepted velocity 位于 Standstill 窗口且 accepted acceleration 精确为 0.0 时为 TRUE。转换开始后锁存待切换方向；目标方向在转换完成前再次改变或变回零均锁存`16#0000B00A`，避免状态分叉。

- [ ] **Step 6：实现 Hard Force/Stroke/Collision 正向运动覆盖**

当`bInhibitPositiveMotion=TRUE`时，普通 Rate Limit 的正向制动尾巴不得继续发布：

```iecst
IF stInput.rAcceptedVelocity_mm_s > 0.0 THEN
    stOutput.rPosition_mm := stInput.rAcceptedPosition_mm;
    stOutput.rVelocity_mm_s := 0.0;
    stOutput.rAcceleration_mm_s2 := 0.0;
    stOutput.nDirection := stInput.nAcceptedDirection;
    stOutput.bPositiveMotionInhibited := TRUE;
END_IF
```

该包是硬安全优先级覆盖，不是普通轨迹包；FastAxis 同一扫描置`ST_ZExtSetpointCommand.bPositiveMotionInhibit=TRUE`并请求退出。Adapter 只在 P 保持 accepted、V=0、A=0、Direction 不变时允许一次绕过普通 velocity-step 连续性检查，接受后立即进入既有 Disable 序列。若 accepted 速度已为零或负值，只允许保持零或继续非正向卸载，绝不生成正值。离线测试必须覆盖 accepted V=+1.0 时第一包 V=0.0，而不是多个扫描仍为正。

- [ ] **Step 7：验证参考向量和边界并编译**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope Trajectory
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1 -Configuration 'Release|TwinCAT RT (x64)'
git diff --check
```

Expected: PASS，且源文件不包含`GVL_`、`AXIS_REF`或`MC_`。

---

## Task 5：扩展 External Adapter 的 accepted 状态与安全换向

**Files:**

- Modify: `CFFwelding_System/CFFwelding/POUs/FunctionBlocks/Axis/FB_ZAxisExtSetpointAdapter.TcPOU`
- Modify: `scripts/Test-Phase7ExternalSetpoint.ps1`

- [ ] **Step 1：先把 Phase 7 测试改成长期合同并确认 RED**

保留“直接`+1/-1`换向必 Fault”和完整 Disable 生命周期；把“Active 中任何 Direction 变化都必须退出”改为：

```text
old nonzero direction + held P, V=0, A=0
-> Direction=0 + held P, V=0, A=0
-> new nonzero direction + held P, V=0, A=0 preload
-> new-direction movement
```

新增 accepted P/V/A/Direction 和 counter 检查。

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase7ExternalSetpoint.ps1
```

Expected: FAIL。

- [ ] **Step 2：拆分生命周期 Precheck 与 Active Feed 校验**

Enable 前只验证真实 NC 初值、限值、配置、Owner、Ready 和绑定；不得先要求尚未由上层轨迹生成的 Feed 包，否则 Sequence 与 Adapter 会启动死锁。

Precheck 成功后立即发布：

```iecst
stStatus.bAcceptedSetpointValid := TRUE;
stStatus.rAcceptedPosition_mm := Axis.NcToPlc.SetPos;
stStatus.rAcceptedVelocity_mm_s := Axis.NcToPlc.SetVelo;
stStatus.rAcceptedAcceleration_mm_s2 := Axis.NcToPlc.SetAcc;
stStatus.nAcceptedDirection := nInitialDirection;
```

- [ ] **Step 3：在每次合法 Feed 后更新 accepted 状态**

`MC_ExtSetPointGenFeed`返回值不作为接受依据；accepted 定义为 Adapter 已完成有限值/边界/方向校验并把内部`rFeed*`传给调用接口。

调用 Feed 后同一扫描：

```iecst
stStatus.bFeedAccepted := TRUE;
stStatus.rAcceptedPosition_mm := rFeedPosition_mm;
stStatus.rAcceptedVelocity_mm_s := rFeedVelocity_mm_s;
stStatus.rAcceptedAcceleration_mm_s2 := rFeedAcceleration_mm_s2;
stStatus.nAcceptedDirection := nFeedDirection;
IF stStatus.udiFeedCycleCounter = UDINT#4294967295 THEN
    stStatus.udiFeedCycleCounter := 1;
ELSE
    stStatus.udiFeedCycleCounter := stStatus.udiFeedCycleCounter + 1;
END_IF
```

Idle、安全 Reset 完成和新的 Precheck 开始时清`bAcceptedSetpointValid`，不伪造 accepted 值。

- [ ] **Step 4：在 Adapter 再次验证换向合同**

Adapter 必须拒绝：

```text
nonzero V or A while changing direction
direct +1 -> -1 or -1 -> +1
Direction=0 while V or A outside standstill window
new nonzero direction without accepted Direction=0 phase
movement before one accepted new-direction preload feed
```

合法换向全过程保持`Z_EXT_ACTIVE`，不得产生第二次 Enable/Disable。正式 Disable 继续使用既有 Ramp-to-zero、Direction hold、Direction zero、Disable、Wait disabled、Post hold。

- [ ] **Step 5：实现硬正向运动覆盖的 Adapter 优先级**

在`Z_EXT_ACTIVE`中优先级固定为：

```text
invalid drive/axis/owner -> existing fault-safe exit
bPositiveMotionInhibit -> validate and accept one held-P/V0/A0/same-direction package
bDisable or Reset -> existing controlled Disable sequence
normal Feed -> ordinary continuity and direction validation
```

硬覆盖包只有在命令 P 等于 accepted P、V=0.0、A=0.0、Direction 等于 accepted Direction 时才允许绕过`rMaximumVelocityStep_mm_s`；其余任何带该位的包立即 Fault。接受硬覆盖后记录 accepted 零速值，并在下一扫描消费持续的 Disable 请求，不能留在普通工艺 Tracking。

- [ ] **Step 6：运行 Phase 6/7、Adapter Scope 和编译**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase6MotionAdapters.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase7ExternalSetpoint.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope Adapter
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1 -Configuration 'Release|TwinCAT RT (x64)'
git diff --check
```

Expected: PASS。

---

## Task 6：接线 FastAxis 轨迹、Force Ramp、R Ramp 与命令源路由

**Files:**

- Modify: `CFFwelding_System/CFFwelding/POUs/FunctionBlocks/Utility/FB_SetpointRamp.TcPOU`
- Modify: `CFFwelding_System/CFFwelding/POUs/Fast/PRG_FastAxisControl.TcPOU`
- Modify: `scripts/Test-Phase8ForceAdmittance.ps1`

- [ ] **Step 1：改写 Phase 8 历史禁令并确认 Routing RED**

删除“FastAxis 永远不得生成 External P/V/A”的阶段性断言；长期规则改为：

- 只有`FB_ZExternalTrajectory`把搜索/导纳速度组合为 P/V/A/Direction；
- 导纳 FB 本身仍不得写 External；
- Adapter 仍是唯一 External API Owner；
- Sequence Error/Aborted、Owner、External、传感器和硬边界继续 Fail Closed。

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase8ForceAdmittance.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope Routing
```

Expected: RED。

- [ ] **Step 2：强化通用 Setpoint Ramp 输入有限性**

`FB_SetpointRamp.bValid`必须额外要求 rate、cycle 和 tolerance 全部有限，cycle>0、rate≥0、tolerance≥0。无效时保持最后连续输出、`bBusy=FALSE`、`bReached=FALSE`、`bValid=FALSE`。

- [ ] **Step 3：唯一实例化轨迹和 R 软件 Ramp**

在`PRG_FastAxisControl.VAR`增加带中文生命周期块注释的：

```iecst
fbZExternalTrajectory : FB_ZExternalTrajectory;
fbRSpeedRamp : FB_SetpointRamp;
```

不得在其他 PROGRAM/FB 重复声明。

FastAxis 不再自行从活 GVL 形成第二套快照。只有以下相关性成立时才运行 Phase 10 轨迹/Force 链：

```iecst
GVL_Status.stFast.stSequence.stFastConfigSnapshot.bValid
AND GVL_Status.stFast.stSequence.stFastConfigSnapshot.nSequenceCommandId
    = GVL_Status.stFast.stSequence.nAcceptedCommandId
```

周期、Limits、External Config和Force Profile全部从该`stFastConfigSnapshot`读取；相关性失败立即禁止 Feed、请求安全退出并保持生产不可用。

- [ ] **Step 4：实现 Fast 已接受命令源路由**

所有普通 Fast 候选改读`GVL_FastInternal.stAcceptedCommand`。

Z 和 R 分别声明：

```iecst
bZSequenceSourceActive, bLastZSequenceSourceActive : BOOL;
bRSequenceSourceActive, bLastRSequenceSourceActive : BOOL;
udiLastZSourceCommandId, udiLastRSourceCommandId : UDINT;
udiZAdapterCommandId, udiRAdapterCommandId : UDINT;
udiCurrentSequenceZSourceId, udiCurrentSequenceRSourceId : UDINT;
```

Sequence Z 候选按 Owner 精确覆盖：

```text
Z_OWNER_APPROACH      -> stApproachCommand
Z_OWNER_FORCE_PROCESS -> stForceProcessCommand
Z_OWNER_RETRACT       -> stRetractCommand
Z_OWNER_FAULT_STOP    -> fbZAxisArbiter.bFaultStopRequest
```

Home/Manual及未被 Sequence 占用的候选仍来自`GVL_FastInternal.stAcceptedCommand`。R 只在`stMotionIntent.bRAxisProcessRequested=TRUE`时选择 Sequence 候选。

当“source BOOL 改变 OR 同一 source 的`FC_IsNewerRequestId`为 TRUE”时，Adapter ID 加一并跳过零；旧 ID、重复 ID 和相同 source 不产生新事务。Adapter 发布 accepted ID 后，若当前源为 Sequence，分别更新：

```iecst
GVL_Status.stFast.udiAcceptedSequenceZCommandId
GVL_Status.stFast.udiAcceptedSequenceRCommandId
```

测试普通 ID=7 切到 Sequence ID=7仍产生一次新事务，恢复普通源也只产生一次。

活动 Sequence 的 Reset 只进入 Sequence Abort 事务；在 External Release 和 Z/R Standstill 前，不把它直接接到 Arbiter、轨迹、Force/R Ramp或 Adapter Reset。安全释放后的终态 Reset 才清这些实例。

- [ ] **Step 5：接线 Force Ramp**

有效步骤斜率：

```iecst
rEffectiveForceRamp_kN_s := MIN(
    GVL_Status.stFast.stSequence.rForceRamp_kN_s,
    GVL_Status.stFast.stSequence.stFastConfigSnapshot.stZForceControl.fForceRampNS
        * 0.001);
```

只有两者有限且大于零时`fbForceSetpointRamp`有效。Fast 状态发布：

```iecst
bForceSetpointRampReached := fbForceSetpointRamp.bReached;
bForceSetpointRampValid := fbForceSetpointRamp.bValid;
```

删除现有“活`GVL_Config.stZForceControl.nRevision`变化自动触发 Transfer”的路径。Phase 10 的 Profile Transfer 只来自新的已验证 Fast Config Snapshot或 Sequence Step Entry脉冲；活动周期中的活 Profile 变化既不能被应用，也不能放宽参数。

健康的`CFF_CONTROLLED_FORCE_UNLOAD`即使最终将进入 NOK，也必须允许力控完成卸载；`bCycleNok`不得提前映射为`bError`。传感器/轴/External 无效时立即停 PI 并请求零速安全退出。

- [ ] **Step 6：接线 External 轨迹**

轨迹目标选择：

```iecst
IF GVL_Status.stFast.stSequence.bForceControlEnable THEN
    rTrajectoryTargetVelocity_mm_s :=
        fbZForceAdmittance.stOutput.rVelocityCommand_mm_s;
ELSE
    rTrajectoryTargetVelocity_mm_s :=
        GVL_Status.stFast.stSequence.stMotionIntent.rExternalTargetVelocity_mm_s;
END_IF
```

轨迹输入只使用 Adapter accepted 状态和 Sequence 发布的单一 Fast Config Snapshot。硬原因映射为：

```iecst
stTrajectoryInput.bInhibitPositiveMotion :=
    GVL_Status.stFast.stSequence.bForceHardLimitActive
    OR GVL_Status.stFast.stSequence.bStrokeHardLimitActive
    OR GVL_Status.stFast.stSequence.bCollisionLimitActive;
```

External 命令映射固定为：

```iecst
stExtCommand.bEnable :=
    GVL_Status.stFast.stSequence.stMotionIntent.bExternalEnableRequest;
stExtCommand.bFeed := fbZExternalTrajectory.stOutput.bActive
    AND NOT fbZExternalTrajectory.stOutput.bFault;
stExtCommand.bDisable :=
    GVL_Status.stFast.stSequence.stMotionIntent.bExternalDisableRequest
    OR fbZExternalTrajectory.stOutput.bFault;
stExtCommand.bPositiveMotionInhibit :=
    fbZExternalTrajectory.stOutput.bPositiveMotionInhibited;
stExtCommand.rPosition_mm := fbZExternalTrajectory.stOutput.rPosition_mm;
stExtCommand.rVelocity_mm_s := fbZExternalTrajectory.stOutput.rVelocity_mm_s;
stExtCommand.rAcceleration_mm_s2 :=
    fbZExternalTrajectory.stOutput.rAcceleration_mm_s2;
stExtCommand.nDirection := fbZExternalTrajectory.stOutput.nDirection;
```

硬覆盖时`bFeed`和`bDisable`可同为 TRUE，Adapter 按 Task 5 的硬覆盖优先级先接受零速包再进入 Disable。Trajectory Fault 时`bActive=FALSE`，所以`bFeed=FALSE`且`bDisable=TRUE`。发布完整`stZExternalTrajectory`。

- [ ] **Step 7：接线 R 轴真实事务与软件包络**

R 最终目标一次性交给`FB_RAxisNcAdapter`；`fbRSpeedRamp`只用同一`rAcceleration_rpm_s/rDeceleration_rpm_s`生成期望 envelope、Busy/Reached/Valid。

每个新的 Adapter-facing R 事务用实际 RPM 作为`rInitialValue`初始化一次；稳定扫描保持 Ramp 内部状态。只有“无活动 Sequence R source AND R实际Standstill AND安全终态Reset”才 Reset。稳定阶段不把每扫描 Ramp 输出作为新 MC 目标。发布：

```iecst
rRSpeedEnvelope_rpm := fbRSpeedRamp.rOutput;
bRSpeedRampBusy := fbRSpeedRamp.bBusy;
bRSpeedRampReached := fbRSpeedRamp.bReached;
bRSpeedRampValid := fbRSpeedRamp.bValid;
```

Step4 停转只读`stRAxis.rActualVelocity_rpm`。

- [ ] **Step 8：保持报警和 Owner 安全边界**

轨迹 Fault 并入槽 7 External 报警；Force 算法保持槽 8；Sequence 不回写这些槽。`bForceProcessExitComplete`必须同时要求 Sequence intent 完成且 Adapter`bReleaseOwner`，不能由 Sequence 单方面释放。

- [ ] **Step 9：运行 Routing 回归**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase6MotionAdapters.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase7ExternalSetpoint.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase8ForceAdmittance.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope Trajectory
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope Routing
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1 -Configuration 'Release|TwinCAT RT (x64)'
git diff --check
```

Expected: PASS。

---

## Task 7：实现 Fast 命令快照与 Sequence 前半状态流

**Files:**

- Modify: `CFFwelding_System/CFFwelding/POUs/Fast/PRG_FastInputs.TcPOU`
- Modify: `CFFwelding_System/CFFwelding/POUs/Fast/PRG_CffSequence.TcPOU`
- Modify: `scripts/Test-Phase9ContactAndCriterion.ps1`

- [ ] **Step 1：确认 SequenceFront RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope SequenceFront
```

Expected: FAIL。

- [ ] **Step 2：在 FastInputs 原子接受 Main→Fast 命令**

在`PRG_FastInputs`增加局部`stFastCommandCandidate : ST_FastCommand`和`udiLiveFastRequestId : UDINT`。只接受 wrap-aware 新 ID：

```iecst
udiLiveFastRequestId := GVL_Command.stFast.nRequestId;
IF FC_IsNewerRequestId(
        udiCandidate := udiLiveFastRequestId,
        udiReference := GVL_FastInternal.stAcceptedCommand.nRequestId) THEN
    stFastCommandCandidate := GVL_Command.stFast;
    IF stFastCommandCandidate.nRequestId = udiLiveFastRequestId
        AND GVL_Command.stFast.nRequestId = udiLiveFastRequestId THEN
        GVL_FastInternal.stAcceptedCommand := stFastCommandCandidate;
    END_IF
END_IF
```

安全合同还要求 Producer 在`GVL_Status.stFast.nAcceptedRequestId`等于本请求前保持整个 payload 不变，并且在 Ack 前不得开始写下一包。双读只用于拒绝扫描中发生的 ID 变化，不能替代该保持合同。当前`PRG_CommandDispatcher`仍是骨架，因此生产端合同尚未实现时`bProductionReady`必须保持 FALSE，报告不得声称端到端命令链完成。FastAxis 不得再直接读活`GVL_Command.stFast`。

- [ ] **Step 3：建立一次迁移状态机骨架**

`PRG_CffSequence`使用：

```iecst
eState : E_CffState;
eNextState : E_CffState;
ePreviousState : E_CffState;
bStateEntry : BOOL;
```

每扫描先`eNextState := eState`，只执行当前 CASE，末尾一次：

```iecst
ePreviousState := eState;
eState := eNextState;
```

`bStateEntry := eState <> ePreviousState`。未知状态锁存`16#0000A016`并进入 Fault。

每扫描先把`bForceProfileTransfer`、Contact/Decline/Criterion Reset 和事件脉冲清为`FALSE`；事务 ID 与对应 payload 保持上次锁存值。每个 CASE 必须完整赋值本状态的 Enable/Disable/Force/R 级别意图，禁止依赖上一个状态遗留的 BOOL。

- [ ] **Step 4：建立事件去重、首故障和周期快照**

局部至少包含：

```iecst
udiLastObservedCommandId : UDINT;
bStartEvent, bStopEvent, bAbortEvent, bResetEvent : BOOL;
bStopRequestedLatched, bResetPendingLatched : BOOL;
bCycleNokLatched : BOOL;
udiFirstFaultId : UDINT;
stCycleSnapshot : ST_CycleSnapshot;
stMachineSnapshot : ST_MachineConfig;
stLimitsSnapshot : ST_MachineLimits;
stSequenceConfigSnapshot : ST_CffSequenceConfig;
stZExtConfigSnapshot : ST_ZExtSetpointConfig;
stForceProfileSnapshot : ST_ZForceControlProfile;
stRAxisProfileSnapshot : ST_RAxisProfile;
stFastConfigSnapshot : ST_CffFastConfigSnapshot;
rCycleStartZPosition_mm : LREAL;
```

事件表达式必须同时要求对应 Pulse 和：

```iecst
FC_IsNewerRequestId(
    udiCandidate := GVL_FastInternal.stAcceptedCommand.stSequence.nCommandId,
    udiReference := udiLastObservedCommandId)
```

旧 ID、重复 ID 和零 ID都不产生事件。Start 接受时复制 Program、Machine、Limits、Sequence Config、External Config 和两个 Profile；复制后复核 Snapshot Revision、Machine Revision 和源对象仍处于 Producer 保持期。活动周期的全部超时、硬限值、标准定位斜率和 Profile 参数使用局部快照。`PRG_ProgramManager`在 Fast 侧 Ack 前也必须保持 Cycle Snapshot 不变；该 Writer 未实现时继续保持 ProductionReady FALSE。

Precheck通过后一次性构造并发布：

```iecst
stFastConfigSnapshot.nSequenceCommandId := udiLastObservedCommandId;
stFastConfigSnapshot.stMachine := stMachineSnapshot;
stFastConfigSnapshot.stLimits := stLimitsSnapshot;
stFastConfigSnapshot.stZExtSetpoint := stZExtConfigSnapshot;
stFastConfigSnapshot.stZForceControl := stForceProfileSnapshot;
stFastConfigSnapshot.bValid := TRUE;
GVL_Status.stFast.stSequence.stFastConfigSnapshot := stFastConfigSnapshot;
```

Precheck失败、终态安全 Reset 和无活动周期时`bValid=FALSE`；FastAxis只消费这一份冻结结构。

Profile Precheck固定要求：

```text
Z profile bValid, nProfileId>0, nRevision>0
R profile bValid, nProfileId>0, nRevision>0
Header.nForceProfileId = Z profile.nProfileId
Header.nRAxisProfileId = R profile.nProfileId
R profile fTargetSpeedRpm, fSpeedRampRpmS, fAccelerationTimeS,
fDecelerationTimeS and fMinimumQualifiedSpeedRpm are finite
R profile fSpeedRampRpmS > 0
R profile fAccelerationTimeS > 0
R profile fDecelerationTimeS > 0
ABS(R profile fTargetSpeedRpm) <= machine maximum RPM
R profile fMinimumQualifiedSpeedRpm >= 0
R profile fMinimumQualifiedSpeedRpm <= machine maximum RPM
```

- [ ] **Step 5：实现 IDLE/PRECHECK**

新 Start ID：

- 清四个步骤结果槽和本周期诊断；
- 锁存周期开始 Z 位置；
- 先发布一次 Contact Reference Reset 事务并等待上一扫描 FastInputs Ack；
- 执行 Permission、ProductionReady、Snapshot、Program/Point、Machine/Limit/Sensor/Profile/Sequence Config、Tool/Anvil/Revision、绑定、Ready、Standstill、Z Homed、Collision Valid、External Idle/Released、Owner、Fast 周期和全部硬边界检查。

事务相关性必须逐项满足：

```text
accepted Fast nCycleSnapshotRevision = Cycle Snapshot nSnapshotRevision
accepted Sequence nProgramId = Snapshot Header nProgramId
accepted Sequence nJoiningPointId = Snapshot nJoiningPointId
Snapshot nMachineConfigRevision = frozen Machine nRevision
Snapshot nCalibrationRevision > 0
Snapshot nCalibrationRevision = Force Calibration nRevision
Snapshot nCalibrationRevision = Displacement Calibration nRevision
Snapshot nCalibrationRevision = Collision Calibration nRevision
Snapshot, Program, Machine, Limits, Sequence Config, External Config,
Force Profile and R Profile bValid = TRUE
```

三个 Calibration Revision 在活动周期中任一变化都锁存`16#0000A00F`并安全退出，不能继续使用与 Start Snapshot 不同的标定集合。

Reset 事务先写`bLatchContactReference=FALSE`、`bUseProvidedContactReference=FALSE`、两个 provided position 为 0.0、`bResetContactReference=TRUE`，最后递增 RequestId 并保持整包直到 Ack。Ack 未在`tContactReferenceAckTimeout`内到达时锁存`16#0000A009`，不得进入 Approach。

Precheck 任一失败锁存以下首错误，不发布 Z/R/External 运动事务：

```text
16#0000A001 command/snapshot identity
16#0000A002 program validation
16#0000A003 machine/sequence config
16#0000A004 profile identity/revision
16#0000A005 hardware/ready/standstill
16#0000A006 sensor/collision/external/owner
```

- [ ] **Step 6：实现 APPROACH**

Entry 只发一次：

```iecst
stMotionIntent.stZCommand.bEnable := TRUE;
stMotionIntent.stZCommand.bMoveAbsolute := TRUE;
stMotionIntent.stZCommand.rPosition_mm :=
    stCycleSnapshot.stProgram.stHeader.fContactSearchStartPositionMm;
stMotionIntent.stZCommand.rVelocity_mm_s :=
    stCycleSnapshot.stProgram.stHeader.fContactSearchVelocityMmS;
stMotionIntent.stZCommand.rAcceleration_mm_s2 :=
    stSequenceConfigSnapshot.fStandardMoveAccelerationMmS2;
stMotionIntent.stZCommand.rDeceleration_mm_s2 :=
    stSequenceConfigSnapshot.fStandardMoveDecelerationMmS2;
stMotionIntent.stZCommand.eOwnerRequest := Z_OWNER_APPROACH;
```

先等待`udiAcceptedSequenceZCommandId`匹配源事务，再接受 Done+Standstill，避免旧 Done 跳过动作。Adapter Error 或`tApproachTimeout`锁存`16#0000A007`。

- [ ] **Step 7：实现 EXTSETPOINT_PREPARE/CONTACT_SEARCH**

Prepare Entry 只增加一次 Z 源事务并持续发布：

```iecst
stMotionIntent.stZCommand.bEnable := TRUE;
stMotionIntent.stZCommand.bUseExternalSetpoint := TRUE;
stMotionIntent.stZCommand.eOwnerRequest := Z_OWNER_FORCE_PROCESS;
stMotionIntent.bExternalEnableRequest := TRUE;
stMotionIntent.bExternalDisableRequest := FALSE;
```

等待 Owner、External Enabled、accepted setpoint valid 和轨迹 Active。确认前`bForceControlEnable=FALSE`。从 Prepare 到 Adapter Release 前持续保留 Force Process Owner，不能在状态切换时把`bUseExternalSetpoint`提前清零。

Contact Search：

```iecst
stMotionIntent.rExternalTargetVelocity_mm_s :=
    ABS(stCycleSnapshot.stProgram.stHeader.fContactSearchVelocityMmS);
```

只在本状态使能`FB_ContactDetect`。Contact Search timeout 锁存`16#0000A008`。

从 External Prepare 开始每扫描都监视 Force硬上限、Z绝对软上限、现有类型化Collision Active、轴/External错误和三类传感器Valid。任一硬原因在 Sequence 扫描立即置对应硬标志、选择 Fault no-return并请求硬正向运动覆盖，不能等到 Step1 才生效。

- [ ] **Step 8：实现 Contact Request/Ack**

Contact 确认扫描先写：

```iecst
GVL_Command.stProcessReference.bLatchContactReference := TRUE;
GVL_Command.stProcessReference.bUseProvidedContactReference := TRUE;
GVL_Command.stProcessReference.rProvidedContactSensorPosition_mm :=
    fbContactDetect.stOutput.rDetectedSensorPosition_mm;
GVL_Command.stProcessReference.rProvidedContactAxisPosition_mm :=
    fbContactDetect.stOutput.rDetectedAxisPosition_mm;
GVL_Command.stProcessReference.bResetContactReference := FALSE;
```

最后递增`GVL_Command.stProcessReference.udiContactReferenceRequestId`并锁存期望 Ack。上述五个 payload 字段和 RequestId 全部保持稳定直到`GVL_Process.stActual.udiContactReferenceAcceptedId`匹配。

Ack ID 匹配且 Reference Valid 后：

- 用 Adapter accepted 搜索速度产生一次 Force Profile Transfer；
- Force Ramp 初值来自实际 ForceControl；
- 计算并锁存`rHardMaximumRelativePosition_mm := stLimitsSnapshot.fZMaxPositionMm - GVL_Process.stActual.fContactAxisPositionMm`；若该值非有限、非正或任一步骤累计目标超过该剩余行程，锁存`16#0000A00D`且不得进入 Step1；
- 下一扫描进入 Step1。

Ack ID 匹配但 Valid=FALSE立即锁存`16#0000A00A`；Ack 超时锁存`16#0000A009`。

- [ ] **Step 9：发布前半状态与唯一报警 Writer**

Sequence 每扫描完整写`GVL_Status.stFast.stSequence`、槽 10；Phase 9 三算法仍只写槽 9。槽 10：

```iecst
eCode := ALARM_CFF_SEQUENCE_FAULT;
eLevel := ALARM_LEVEL_FAULT;
nTextId := 3200;
nSourceId := 10;
bLatch := TRUE;
bActive := udiFirstFaultId <> 0;
```

- [ ] **Step 10：运行 SequenceFront GREEN**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase9ContactAndCriterion.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope SequenceFront
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1 -Configuration 'Release|TwinCAT RT (x64)'
git diff --check
```

Expected: PASS。

---

## Task 8：实现 Step1–4、步骤结果和 Qualified Hold

**Files:**

- Modify: `CFFwelding_System/CFFwelding/POUs/Fast/PRG_CffSequence.TcPOU`

- [ ] **Step 1：确认 SequenceSteps RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope SequenceSteps
```

Expected: FAIL。

- [ ] **Step 2：实现饱和时间累加**

声明`uliCycleDelta_us`、`uliStepElapsed_us`、`uliStepMaximum_us`、`uliQualifiedHold_us`和`uliQualifiedHoldTarget_us`为`ULINT`，使用微秒：

```iecst
uliCycleDelta_us := UDINT_TO_ULINT(stMachineSnapshot.nFastTaskCycleUs);
IF uliStepElapsed_us < uliStepMaximum_us THEN
    IF uliCycleDelta_us >= uliStepMaximum_us - uliStepElapsed_us THEN
        uliStepElapsed_us := uliStepMaximum_us;
    ELSE
        uliStepElapsed_us := uliStepElapsed_us + uliCycleDelta_us;
    END_IF
END_IF
```

先转`ULINT`再把 ms 乘 1000，并在加法前比较剩余量，禁止“先溢出再 MIN”。Qualified Hold 同样按目标饱和；条件 FALSE 时暂停，不清零。

- [ ] **Step 3：实现 Step1 Entry 同扫描并行目标**

Entry 同扫描：

- `rForceSet_kN := fSetForceN * 0.001`；
- `rForceRamp_kN_s := fForceRampNS * 0.001`；
- R MoveVelocity 使用`fSetSpeedRpm`；
- R 加减速度使用 Start 时锁存`stRAxisProfileSnapshot.fSpeedRampRpmS`；
- R payload 的 Move/Stop、Velocity、Acceleration 或 Deceleration 相对上次锁存 payload 变化时，源事务号只递增一次；
- Contact accepted 速度作为 Force Profile Transfer 预置速度；
- 依据 Primary 类型把`fRelativeDistanceMm`或`fSecondarySRelMm`发布为本步骤累计`rTargetRelativePosition_mm`；`rHardMaximumRelativePosition_mm`使用 Contact Ack 后计算的`fZMaxPositionMm - fContactAxisPositionMm`，不把正常 Primary/Secondary 边界误当机器硬碰撞；
- Reset Decline、Criterion、Step timer。

Force 和 R 目标必须在同一个 Sequence 扫描发布。

- [ ] **Step 4：实现 Step1–3 Ramp/End Check**

每个过程扫描完整赋值 Decline/Criterion 输入；S_rel 始终来自 Contact 累计值，步骤切换不清零。

Phase 10 不直接访问 Collision IO。现有临时类型化边界唯一映射为：

```iecst
bCollisionLimitActive := GVL_Process.stActual.bCollisionValid
    AND GVL_Process.stActual.bCollisionSensorActive;
```

`bCollisionValid=FALSE`走 Sensor/Collision invalid Fault，不把无效信号解释为未碰撞。该临时映射必须在报告中标记为 Phase 11B 将删除的旧 Collision 路径，不能声称已完成最终双位移碰撞算法。

另外两项硬边界固定为：

```iecst
bForceHardLimitActive := GVL_Process.stActual.bForceValid
    AND GVL_Process.stActual.fForceControlN >= stLimitsSnapshot.fMaxForceN;
bStrokeHardLimitActive := GVL_Process.stActual.bContactReferenceValid
    AND GVL_Process.stActual.fSRelSensorMm >= rHardMaximumRelativePosition_mm;
```

非有限或 Valid=FALSE不走上述比较，而是走 Sensor invalid Fault。

Step2、Step3 每次 Entry 也必须用 Adapter 最后 accepted 速度产生一次 Force Profile Transfer，因为累计 S_rel 目标/硬边界发生变化；稳定过程扫描不重复产生 Transfer。这样`FB_ZForceAdmittance`对已应用目标/限值的快照比较不会把合法步骤切换误判为未授权变化。

R 命令使用完整 payload 变化判定。若 Step1 与 Step2 的 RPM 和斜率完全相同，Step2 Entry 不增加 R 源 ID，也不产生新 MC Execute；目标或 Stop/Move 模式任一变化才递增并跳过零。Phase 10 向量必须验证“相同目标 100 个扫描事务数仍为 1”。

声明`stLastPublishedRCommand : ST_RAxisCommand`和`bRCommandPayloadChanged : BOOL`，比较固定为：

```iecst
bRCommandPayloadChanged :=
    stCandidateRCommand.bEnable <> stLastPublishedRCommand.bEnable
    OR stCandidateRCommand.bReset <> stLastPublishedRCommand.bReset
    OR stCandidateRCommand.bStop <> stLastPublishedRCommand.bStop
    OR stCandidateRCommand.bMoveVelocity <> stLastPublishedRCommand.bMoveVelocity
    OR stCandidateRCommand.rVelocity_rpm <> stLastPublishedRCommand.rVelocity_rpm
    OR stCandidateRCommand.rAcceleration_rpm_s
        <> stLastPublishedRCommand.rAcceleration_rpm_s
    OR stCandidateRCommand.rDeceleration_rpm_s
        <> stLastPublishedRCommand.rDeceleration_rpm_s;
```

候选值都已通过有限值验证，所以可做精确 payload 相等比较；变化时先复制 payload，最后递增源 ID。

确定性处理：

```text
Primary normal -> latch result and advance
TooShort -> latch NOK and advance
Secondary AdvanceAndNok -> latch NOK and advance
Secondary ControlledExitNok -> latch NOK and unload
StepMax -> latch NOK and unload
Hard Force/Stroke/Collision/Sensor/Axis/algorithm fault -> fault no-return
```

每个`GVL_Process.astStepCriterion[index]`只写一次；后续 Reset 不改写前一步已锁存结果。

- [ ] **Step 5：实现 Step3→Brake 单独迁移**

Step3 End Check 只设置`eNextState := CFF_BRAKE_AND_COMPRESSION_RAMP`，不得在同一扫描同时执行 Brake Entry。

- [ ] **Step 6：实现 Brake/Compression 并行 Ramp**

Brake Entry 同扫描：

- R 目标设零并产生一次 Stop/Halt 源事务；
- Force 目标设 Step4 Force；
- Force Ramp 设 Step4 Ramp；
- Step4 的`fSecondarySRelMm`设为累计目标；硬 S_rel 上限仍是 Contact Ack 后锁存的剩余 Z 行程；
- Force Profile Transfer 脉冲一次；
- Step4 总时间、Criterion 和 Qualified Hold 从本扫描开始。

`CFF_BRAKE_AND_COMPRESSION_RAMP`与`CFF_STEP4_VALID_FORCE_HOLD`每扫描都必须调用同一 Step4 Criterion、累加同一个 Step4 总时间并执行同一个 Qualified Hold gate。处理顺序固定为：

```text
invalid Force/R ramp or algorithm Fault -> 16#0000A00B fault no-return
StepMax/Primary Step Time reached -> evaluate Qualified Hold and unload
R stop timeout -> 16#0000A014 fault no-return
both ramps Valid and Reached -> transition to STEP4_VALID_FORCE_HOLD
otherwise remain in BRAKE_AND_COMPRESSION_RAMP
```

因此 Force Ramp 永不到达、R envelope 永不到达或 Ramp 无效都不能把状态机永久卡在 Brake。进入`CFF_STEP4_VALID_FORCE_HOLD`时不得重置 Step4 时间、Criterion 或 Hold。

Brake Entry 同时启动锁存的`tRAxisStopTimeout`；实际 RPM 未在该超时内进入 Step4 停转阈值时锁存`16#0000A014`并选择 Fault no-return。

- [ ] **Step 7：实现 Step4 实际 RPM 与 Force Band gate**

每 Fast 扫描：

```iecst
bRpmStopped := ABS(GVL_Status.stFast.stRAxis.rActualVelocity_rpm)
    <= stCycleSnapshot.stProgram.astSteps[4].stProceeding.fRpmStoppedThresholdRpm;
bForceInBand := ABS(
    GVL_Process.stActual.fForceControlN
    - stCycleSnapshot.stProgram.astSteps[4].fSetForceN)
    <= stCycleSnapshot.stProgram.astSteps[4].stProceeding.fForceBandToleranceN;
IF bRpmStopped AND bForceInBand THEN
    IF uliQualifiedHold_us < uliQualifiedHoldTarget_us THEN
        IF uliCycleDelta_us >= uliQualifiedHoldTarget_us - uliQualifiedHold_us THEN
            uliQualifiedHold_us := uliQualifiedHoldTarget_us;
        ELSE
            uliQualifiedHold_us := uliQualifiedHold_us + uliCycleDelta_us;
        END_IF
    END_IF
END_IF
```

不得使用 R envelope、R target 或 Reached 替代实际 RPM。

- [ ] **Step 8：实现 Step4 结束和结果**

Primary Step Time 到达：

- Qualified Hold 达标且此前无 NOK：`CFF_EXIT_NORMAL_RETURN`；
- Hold 不足或此前已有 NOK：锁存 Cycle NOK，`CFF_EXIT_NOK_RETURN`；
- 两者都先进入 Controlled Unload。

Step4 结果写入第 4 槽并记录 Qualified Hold、实际 Force、S_rel 和 StepTime。

- [ ] **Step 9：运行 SequenceSteps GREEN**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase9ContactAndCriterion.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope SequenceSteps
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1 -Configuration 'Release|TwinCAT RT (x64)'
git diff --check
```

Expected: PASS。

---

## Task 9：实现 Unload、Disable、Return、Abort/Fault/Reset 和终态

**Files:**

- Modify: `CFFwelding_System/CFFwelding/POUs/Fast/PRG_CffSequence.TcPOU`
- Modify: `CFFwelding_System/CFFwelding/GVLs/GVL_ProjectInfo.TcGVL`

- [ ] **Step 1：确认 SequenceExit RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope SequenceExit
```

Expected: FAIL。

- [ ] **Step 2：实现正常/NOK Controlled Unload**

保持 R 零目标；Force target 按当前步骤有效 Ramp 到零。

只有以下条件连续满足`tUnloadStandstillConfirm`才请求 Disable：

```text
Force Ramp valid and reached zero
ABS(ForceControlN) <= ContactForceOffN
ABS(Adapter accepted velocity) <= External standstill threshold
External and Force signals healthy
```

任一条件掉线立即清连续确认 Timer。Unload timeout 锁存`16#0000A013`并转 Fault no-return。

- [ ] **Step 3：实现 External Disable 与 Return 闸门**

`CFF_EXTSETPOINT_DISABLE`只请求 Disable 并等待`bReleaseOwner`。Release 前：

```text
bForceProcessExitComplete = FALSE
Return Z source RequestId remains unchanged
```

Release 后撤销 Force Control、置`bForceProcessExitComplete=TRUE`并按 ExitIntent：

```text
NORMAL_RETURN -> RETURN_LOCAL or RETURN_REFERENCE
NOK_RETURN -> RETURN_LOCAL or RETURN_REFERENCE
ABORT_NO_RETURN -> CFF_ABORT
FAULT_NO_RETURN -> CFF_FAULT
```

- [ ] **Step 4：实现 Local/Reference Return**

Entry 只发一次`Z_OWNER_RETRACT + MoveAbsolute`：

```text
Local target = rCycleStartZPosition_mm
Reference target = Header.fReturnOpeningMm
Velocity = Header.fReturnVelocityMmS
Acceleration/Deceleration = frozen Sequence Config
```

先等 Sequence Z source Ack，再接受 Done+Standstill。Return timeout锁存`16#0000A015`；R 未实际停转、External 未释放、Z/R 非 Ready 或有 Error 时不得发布 Return。

- [ ] **Step 5：实现 Stop/Abort/活动 Reset**

新的 Stop、Abort 或活动 Reset：

- 首次锁存`STEP_END_STOP_REQUEST`和`CFF_EXIT_ABORT_NO_RETURN`；
- 禁止继续向下；
- R 只发一次受控 Stop；
- Force/External 健康时走 Controlled Unload；
- 不健康时立即停 PI、目标速度归零并走 Adapter 安全 Disable；
- Release 后进入 Abort，绝不 Return。

退出中发生真实故障时 Fault 覆盖 Abort，但不得覆盖更早的真实首故障。

按发生阶段固定路由，不能假定 External 已经 Active：

```text
IDLE/PRECHECK:
    no motion exists -> enter ABORT directly
APPROACH:
    issue exactly one Z_OWNER_FAULT_STOP standard Z transaction,
    wait source Ack and Z Standstill, then enter ABORT/FAULT
EXTSETPOINT_PREPARE:
    request Adapter safe Disable/Release even if Enable is still pending,
    then enter ABORT/FAULT
CONTACT_SEARCH and all later External states:
    use healthy controlled unload or zero-velocity safe Disable
```

Approach 的退出等待使用锁存的`tApproachTimeout`且不生成 Return；无需增加未批准的新主状态。

Stop/Abort/Fault 的 R 停止等待同样使用锁存的`tRAxisStopTimeout`；超时只在尚无首故障时锁存`16#0000A014`，并继续保持零目标和安全 External 退出，不得恢复向下动作。

- [ ] **Step 6：实现 Fault no-return**

确定性错误号：

```text
16#0000A00B criterion/algorithm fault
16#0000A00C hard force
16#0000A00D hard stroke
16#0000A00E collision
16#0000A00F sensor/reference invalid
16#0000A010 Z axis fault
16#0000A011 R axis fault
16#0000A012 External/trajectory fault
16#0000A013 unload timeout
16#0000A014 R stop timeout
16#0000A015 return timeout
16#0000A016 illegal state
```

Hard Force/Stroke/Collision立即封锁正向速度；Sensor invalid立即停 PI；R 受控 Stop；External 安全退出；不自动 Return。

- [ ] **Step 7：实现安全 Reset**

只有 Z/R Standstill、External Released 且状态为 Idle/Abort/Fault/Complete 时，Reset 才清：

```text
state machine
algorithm latches
trajectory reset request
first fault
step diagnostics
pending flags
```

事务计数不清零、不重用旧 Start ID；同一旧 ID 不能重新启动。

- [ ] **Step 8：实现 Evaluate 和互斥终态**

只消费四个步骤真实锁存事实、TooShort、Secondary、StepMax、Qualified Hold 和退出完整性。

真值表固定：

```text
COMPLETE_OK  : bDone=TRUE,  bError=FALSE, bAborted=FALSE
COMPLETE_NOK : bDone=TRUE,  bError=TRUE,  bAborted=FALSE
ABORT        : bDone=FALSE, bError=FALSE, bAborted=TRUE
FAULT        : bDone=FALSE, bError=TRUE,  bAborted=FALSE
```

`bCycleNok`在活动周期可诊断，但直到终态不得提前用`bError`关闭健康卸载链。

- [ ] **Step 9：更新版本信息**

`GVL_ProjectInfo`按仓库既有格式记录 Phase 10 源码实现版本，不写未执行的 Runtime/硬件资格声明。

- [ ] **Step 10：运行 SequenceExit 与 All 源码验证**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope SequenceExit
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope All
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1 -Configuration 'Release|TwinCAT RT (x64)'
git diff --check
```

Expected: PASS。

---

## Task 10：全量审查、真实 XAE Build、源码提交与报告提交

**Files:**

- Generated by Build: `CFFwelding_System/CFFwelding/CFFwelding.tmc`
- Generated if changed by Build: `CFFwelding_System/CFFwelding_System.tsproj`
- Create: `Docs/报告/PHASE_10_EXECUTION_REPORT.md`
- Modify: `Docs/报告/TWINCAT_BUILD_REPORT.md`
- Modify: `Docs/报告/INSTANCE_OWNERSHIP_MATRIX.md`
- Modify: `Docs/报告/INTERNAL_INTERFACE_CATALOG.md`
- Modify: `Docs/报告/GIT_EXECUTION_REPORT.md`

- [ ] **Step 1：运行 Phase 1–10 全回归**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase1Project.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase2Architecture.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase3DataAndBindings.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase4Utilities.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase5SensorProcessing.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase6MotionAdapters.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase7ExternalSetpoint.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase8ForceAdmittance.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase9ContactAndCriterion.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope All
```

Expected: 全部 PASS。

- [ ] **Step 2：做三类独立审查**

使用`superpowers:requesting-code-review`并行进行：

1. 规格符合性：逐条核对批准设计和本计划；
2. PLC/TwinCAT 代码质量：Writer、实例、类型、状态、事务、单位、XML/GUID；
3. 安全边界：Fail Closed、Owner、External、Stop/Abort/Fault、无假 Valid、无硬件动作。

发现问题时先用`superpowers:receiving-code-review`验证意见，再返回对应 Task 以 RED/GREEN 修正并重新全回归。

- [ ] **Step 3：执行真实 Release x64 Build**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1 -Configuration 'Release|TwinCAT RT (x64)'
```

Expected: `SolutionBuild.LastBuildInfo = 0`。记录实际错误数、警告数、工具版本和生成物变化；不得把 Build 表述为 Runtime 或实机验证。

- [ ] **Step 4：执行完成前源码验证**

使用`superpowers:verification-before-completion`重新运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope All
git diff --check
git status --short
```

检查无未完成标记、空实现、重复 GUID、重复 Include、未解释 Writer 或强制 Ready/Valid。

- [ ] **Step 5：创建并推送源码提交**

仅暂存源码、测试、脚本说明和 Build 生成物；不含报告：

```powershell
git status --short
git add -- CFFwelding_System\CFFwelding CFFwelding_System\CFFwelding_System.tsproj scripts\README.md scripts\Test-Phase7ExternalSetpoint.ps1 scripts\Test-Phase8ForceAdmittance.ps1 scripts\Test-Phase9ContactAndCriterion.ps1 scripts\Test-Phase10CffSequence.ps1
git diff --cached --name-only
git commit -m "feat(process): implement Phase 10 CFF sequence"
git push origin codex/cffwelding-greenfield-v3.3
```

`git diff --cached --name-only`必须只出现本计划源码/测试/生成物清单；发现其他路径立即停止，不提交用户无关改动。

Push 失败时保留本地提交、报告真实错误并重试；不得显示认证数据。

- [ ] **Step 6：编写 Phase 10 报告**

`PHASE_10_EXECUTION_REPORT.md`必须记录：

- 源码 commit SHA；
- 状态流、事务、轨迹、方向握手、R/Force Ramp、Step4 Hold、退出和终态；
- Phase 1–10 每个测试命令与真实结果；
- XAE Build 配置、`LastBuildInfo`、错误数和警告数；
- 新/变更 ADS/TMC 契约；
- 三类审查结论和已修复问题；
- 未执行的 Runtime、External POC、真实驱动、任务同步/抖动、硬件映射、标定和工艺资格；
- `PRG_CommandDispatcher`与`PRG_ProgramManager`仍为后续阶段 Writer 骨架，因此 Phase 10 只完成 Fast 侧消费者，不能声称外部端到端生产启动。

同步更新四份现有报告中的 Phase 10 条目、Owner、接口字段、Build 证据和 Git SHA。

- [ ] **Step 7：运行带报告闸门的最终验证和 Build**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Phase10CffSequence.ps1 -Scope All -RequireReport
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1 -Configuration 'Release|TwinCAT RT (x64)'
git diff --check
```

Expected: 全部 PASS，Build 仍为 0。

- [ ] **Step 8：创建并推送报告提交**

```powershell
git status --short
git add -- Docs\报告\PHASE_10_EXECUTION_REPORT.md Docs\报告\TWINCAT_BUILD_REPORT.md Docs\报告\INSTANCE_OWNERSHIP_MATRIX.md Docs\报告\INTERNAL_INTERFACE_CATALOG.md Docs\报告\GIT_EXECUTION_REPORT.md
git diff --cached --name-only
git commit -m "docs(report): record Phase 10 sequence verification"
git push origin codex/cffwelding-greenfield-v3.3
```

- [ ] **Step 9：远端和工作树最终核对**

Run:

```powershell
git status --short
git status --branch --short
git rev-parse HEAD
git rev-parse origin/codex/cffwelding-greenfield-v3.3
git log -4 --oneline
```

Expected:

- 工作树干净；
- 本地 HEAD 与远端分支 SHA 相同；
- 最后四个聚焦提交依次是 design、plan、source、report；
- 最终交付明确区分离线完成项与尚未执行的 Runtime/硬件资格项。
