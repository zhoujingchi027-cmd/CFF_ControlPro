# Phase 7 Z轴 External Setpoint 生命周期执行报告

## 1. 目标与结论

Phase 7 在不连接真实驱动、不激活配置和不登录 Runtime 的边界内，完成 Z 轴 External Setpoint 的 PLC 契约、唯一适配器、Owner 保持、固定报警槽和受控退出生命周期。源码提交为：

```text
4f1bfa8de7a3117558993ce07f655d59ccddcd74 feat(motion): add external setpoint lifecycle
```

最终结论：静态契约和本机 TwinCAT XAE Release 构建通过；这只证明离线工程在固定库版本下可编译，不构成真实轴 External Setpoint POC、硬件验收或生产资格。

## 2. 构建与库基线

| 项目 | 已核对值 |
|---|---|
| TwinCAT XAE | `3.1.4024.64` |
| XAE Shell / Automation | `15.0.0.0` / `TcXaeShell.DTE.15.0` |
| PLC Motion库 | `Tc2_MC2 3.3.65.0` |
| 构建配置 | `Release\|TwinCAT RT (x64)` |
| NC SAF周期 | `20000 × 100 ns = 2 ms` |
| PLC Fast周期 | `2000 us = 2 ms` |

本机 PLC 工程和生成的 TMC 是本次构建的版本权威。已确认本机 `MC_ExtSetPointGenEnable` 只有 `Axis`、`Execute`、`Position`、`PositionType` 四个输入，不包含新版文档中的 `Options`，本机也不存在 `ST_ExtSetPointEnableOptions`。最小编译探针证明传入 `Options` 会失败，而四参数调用通过。因此实现使用本机四参数签名，并明确禁止 `MC_ExtSetPointGenFeedWithTorque`；Phase 7 不提供 Torque Offset。

签名核对参考：

- 当前 `MC_ExtSetPointGenEnable`：https://infosys.beckhoff.com/content/1033/tcplclib_tc2_mc2/70076683.html
- 与本机签名一致的旧版 Enable：https://infosys.beckhoff.com/content/1033/tcplclibmc2/458391563.html
- `MC_ExtSetPointGenFeed`：https://infosys.beckhoff.com/content/1033/tcplclib_tc2_mc2/70079755.html
- `MC_ExtSetPointGenDisable`：https://infosys.beckhoff.com/content/1033/tcplclib_tc2_mc2/70078219.html
- External Setpoint 时序和退出后附加周期：https://infosys.beckhoff.com/content/1033/tf50x0_tc3_nc_ptp/12186882955.html

## 3. 契约、唯一实例与 MC 边界

- `ST_ZExtSetpointCommand` 定义 Reset、Enable、Feed、Disable 和 P/V/A/Direction；Direction 只允许 `-1/0/1`。
- `ST_ZExtSetpointStatus` 发布 Enabled、Busy、Done、FeedAccepted、ReleaseOwner、Error、ErrorId、状态和 Feed 周期计数。
- `ST_ZExtSetpointConfig` 对 Enable/Disable 超时、静止阈值、位置连续性、速度步阶、Direction 保持和 Disable 后保持周期进行显式配置；`bValid` 默认保持 `FALSE`。
- `PRG_FastAxisControl` 只声明一个 `fbZExtSetpoint : FB_ZAxisExtSetpointAdapter`。
- 只有该 Adapter 调用 `MC_ExtSetPointGenEnable`、`MC_ExtSetPointGenFeed` 和 `MC_ExtSetPointGenDisable`；流程 PROGRAM、算法 FB 和 Owner 仲裁器不接触 MC 或 `AXIS_REF`。
- Adapter 只有在 `bDriveLinked`、配置有效、数值有限、轴状态有效且 Force Process Owner 已授予时才允许进入 Enable。

## 4. 生命周期与受控退出

实现状态顺序为：

```text
IDLE → PRECHECK → PRELOAD_DIRECTION → PREFEED_INITIAL
→ ENABLE → WAIT_ENABLED → ACTIVE
→ RAMP_TO_ZERO → HOLD_DIRECTION → DIRECTION_ZERO
→ DISABLE → WAIT_DISABLED → POST_DISABLE_HOLD → DONE
```

错误进入 `Z_EXT_ERROR`。如果 Disable 尚未被 NC 确认，Adapter 保持 Owner，Reset 且驱动仍链接时重试 Disable；只有轴、Enable FB 和 Disable FB 均确认未启用并完成至少一个附加 Feed 周期，再完成配置的 Post-disable hold，才发布 `bReleaseOwner=TRUE`。

ACTIVE 每个 Fast/SAF 周期发送 P/V/A/Direction。初始 P/V/A 来自 `Axis.NcToPlc.SetPos/SetVelo/SetAcc` 并经过有限值及工程限值检查。直接 `+1/-1` 反向被拒绝并进入受控退出；非零方向归零时先降速、保持最后非零方向，再发送零方向。Fault Stop 和 Owner 撤销同样先完成 External 退出，标准 NC Stop/Reset 命令在 Owner 释放后再交付，避免两个命令通道同时控制 Z 轴。

## 5. 状态与报警

- `GVL_Status.stFast.stZExtSetpoint` 发布 Adapter 状态。
- `stZAxis.bExternalSetpointActive` 来自真实 External Enabled 状态。
- 固定报警槽为 `GVL_Alarm.astRequests[7]`。
- 报警码为 `ALARM_EXTERNAL_SETPOINT_FAULT`，等级为 Fault，`TextId=2200`，`SourceId=7`，锁存为 TRUE。
- 报警活动条件来自 Adapter 的实际错误状态，不由占位 Ready 或人工常量伪造。

## 6. TDD、审查与构建证据

RED 阶段先验证类型、唯一实例、MC 边界、生命周期、Owner 释放、硬件门控和报告闸门。实现和审查修复后，Phase 1～6 回归通过，Phase 7 在本报告生成前只因缺少本报告而失败。审查中特别修复了 Fault Stop 与标准 MC 命令并发、直接方向反转、Disable 超时后过早释放 Owner、Disable 完成条件过宽以及非有限/越界输入问题。

报告生成后的最终复验实际输出：

```text
Phase 1 acceptance test: PASSED
Phase 2 architecture test: PASSED
Phase 3 data and binding test: PASSED
Phase 4 utility test: PASSED
Phase 5 sensor processing test: PASSED
Phase 6 motion adapter test: PASSED
Phase 7 external setpoint test: PASSED
CFFwelding XAE build: PASSED
Configuration: Release|TwinCAT RT (x64)
LastBuildInfo: 0
```

## 7. 硬件与安全边界

本阶段未执行设备扫描、I/O/PDO 或 Safety 配置、配置激活、工程下载、Runtime 登录、轴使能或任何物理动作。`bZAxisDriveLinked`、硬件映射完成状态和 Production Ready 均未被代码强制为 `TRUE`。

以下事项仍未完成，不能由本次 Build 替代：

- 在批准硬件和隔离条件下完成 External Setpoint POC；
- 关联并验证真实驱动、编码器、制动器和轴方向；
- 测量 PLC/SAF 周期同步、最大执行时间和抖动；
- 完成 I/O、PDO、Safety、限位和异常退出的现场验收；
- 冻结经工艺验证的速度、加速度、连续性和超时参数；
- 完成低能量、故障注入、双人复核和工艺生产资格签署。
