# Phase 6 标准NC Adapter与Owner执行报告

## 目标

在两个离线NC轴已完成PLC内部`AXIS_REF`映射、但没有真实驱动/编码器关联的边界内，实现Z轴标准命令、R轴RPM命令、Z轴唯一Owner和严格MC调用封装。任何`DriveLinked`条件缺失时，Adapter必须保持`Ready=FALSE`并禁止Power及运动命令执行沿。

## 创建内容

- `FB_AxisCommandArbiter`：不访问`AXIS_REF`或MC，执行Fault Stop、力过程受控退出和Home/Retract/Approach/Manual唯一Owner选择。
- `FB_ZAxisNcAdapter`：唯一封装Z轴`MC_Power/Reset/Home/MoveAbsolute/MoveVelocity/Halt`，并发布位置、速度、回零和命令状态。
- `FB_RAxisNcAdapter`：唯一封装R轴`MC_Power/Reset/MoveVelocity/Halt`，发布RPM和只读实际Torque；没有扭矩闭环。
- `Test-Phase6MotionAdapters.ps1`：MC边界、命令事务、唯一实例、未绑定策略和硬件边界验收。

## 命令与Owner规则

Z轴候选命令由`PRG_FastAxisControl`按`E_ZCommandOwner`拆分，仲裁结果只有一个：

```text
FAULT_STOP
→ 活动力过程在受控退出完成前保持Owner
→ FORCE_PROCESS
→ HOME
→ RETRACT
→ APPROACH
→ MANUAL
→ NONE
```

Fault请求立即生成受控Stop。力过程使用External Setpoint期间不得直接转交普通Owner；External生命周期将在Phase 7完成。

标准运动使用`ST_FastCommand.nRequestId`作为事务编号。Adapter仅在编号变化时产生一次`Execute`上升沿，不会在每个2 ms Fast扫描重复触发。Z/R速度命令各使用两套`MC_MoveVelocity`实例交替，使后续新事务可以按`MC_Aborting`替换活动速度命令。

## MC边界与官方接口核对

- `Axis.ReadStatus()`在各Adapter每扫描调用一次；状态通过`Axis.Status`读取。
- 实际位置、速度和Torque来自`Axis.NcToPlc.ActPos/ActVelo/ActTorque`。
- `MC_MoveAbsolute`、`MC_MoveVelocity`、`MC_Home`和`MC_Halt`的输入按Beckhoff `Tc2_MC2`官方签名连接，未使用未验证的自定义封装。
- `PRG_FastAxisControl`、`PRG_CffSequence`和`FB_AxisCommandArbiter`不包含MC调用。

官方核对页：

- https://infosys.beckhoff.com/content/1033/tcplclib_tc2_mc2/70049419.html
- https://infosys.beckhoff.com/content/1033/tcplclib_tc2_mc2/70094731.html
- https://infosys.beckhoff.com/content/1033/tcplclib_tc2_mc2/70102411.html
- https://infosys.beckhoff.com/content/1033/tcplclib_tc2_mc2/70117515.html
- https://infosys.beckhoff.com/content/1033/tcplclib_tc2_mc2/70132363.html

## TDD证据

初始RED准确报告3个Phase 6 FB、Fast轴实例、MC边界和执行报告缺失。实现后测试只剩报告闸门失败；补齐本报告后应输出：

```text
Phase 6 motion adapter test: PASSED
MC boundary: Z/R NC adapters only
Unbound drive policy: Ready FALSE and motion gated
```

最终提交前同时执行Phase 1～5回归测试。

## Build证据

真实TwinCAT XAE构建结果：

```text
Starting TwinCAT XAE Shell build: TcXaeShell.DTE.15.0
Building project 'CFFwelding_System\CFFwelding_System.tsproj' with 'Release|TwinCAT RT (x64)'.
CFFwelding XAE build: PASSED
Configuration: Release|TwinCAT RT (x64)
LastBuildInfo: 0
```

## 硬件与安全边界

- 真实I/O配置子节点：0。
- 两个NC轴仍未关联AX5000、编码器、电机或仿真驱动。
- `bZAxisDriveLinked`、`bRAxisDriveLinked`没有代码写为`TRUE`。
- `Ready`依赖`DriveLinked AND MC_Power.Status AND Axis.Status.Operational`。
- 未执行Scan、Activate、Download、Runtime登录或任何轴动作。
- 普通PLC停止逻辑不替代人员安全系统。

## Git状态

- Phase 6主Commit：提交后回填。
- Commit消息：`feat(motion): add Phase 6 NC adapters and owner arbitration`
- Push：先完成本地Commit；GitHub网络恢复后推送累计提交。

## 下一风险

Phase 7必须核对本机`Tc2_MC2 3.3.65.0`实际External Setpoint API并实现严格Enable/Feed/Disable生命周期。任何API不确定项必须保持禁用，不得用未经编译验证的接口或绕过NC直接写驱动PDO。
