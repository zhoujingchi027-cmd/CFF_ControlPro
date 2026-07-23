# Phase 4 纯计算FC与通用FB执行报告

## 目标

建立后续传感器、运动、过程判定和主状态模块共同使用的纯计算函数与通用有状态功能块；覆盖Reset、非正周期、负延时、零量程、上下限传反、非有限工程值和报警源未消失等边界，不提前访问硬件、轴或全局业务数据。

## 创建文件

### 纯计算FC（14个）

- 数学与缩放：`FC_ClampLReal`、`FC_ScaleLinear`、`FC_LimitRate`、`FC_TrapezoidIntegrate`、`FC_Interpolate1D`、`FC_IsFiniteLReal`。
- 单位与能量：`FC_RpmToRadPerSec`、`FC_CalcEnergyIncrement`、`FC_ConvertDirection`。
- 校验与判定：`FC_ValidateCalibration`、`FC_ValidateJoinProgram`、`FC_GetPrimaryEndCause`、`FC_CheckModeSourceMatrix`。
- 几何硬边界：`FC_CalcStrokeVelocityLimit`。

### 通用FB（6个）

- `FB_LowPassFilter`
- `FB_Debounce`
- `FB_SignalValidity`
- `FB_SetpointRamp`
- `FB_CommandHandshake`
- `FB_AlarmLatch`

全部20个对象均已加入`CFFwelding.plcproj`编译清单。公开接口与关键算法使用中文独立行注释，标识符保持英文ASCII。

## 修改文件

- `CFFwelding_System/CFFwelding/CFFwelding.plcproj`：登记20个POU和Functions/FunctionBlocks目录。
- `Docs/报告/INTERNAL_INTERFACE_CATALOG.md`：增加FC/FB输入输出与边界契约。
- `Docs/报告/INSTANCE_OWNERSHIP_MATRIX.md`：注明类型已创建，但业务实例仍由后续唯一Owner声明。
- `scripts/README.md`：增加Phase 4验收入口。
- `scripts/Build-Cffwelding.ps1`：补充Solution Configuration异步加载等待。

## 接口与分层变化

- FC只通过参数和函数返回值交互，不保存状态。
- FB只通过`VAR_INPUT`/`VAR_OUTPUT`交互，不访问GVL、PROGRAM局部变量或其他FB内部变量。
- 通用对象禁止出现`AXIS_REF`、`MC_*`和硬件地址。
- 本Phase不声明任何业务实例；实例所有权矩阵仍是后续声明位置的唯一依据。
- `FB_CommandHandshake`将变化的`RequestId`转为单扫描`bNewRequest`并发布`AcceptedId`，没有共享BOOL清零协议。
- `FB_AlarmLatch`实行置位优先，只有源消失且权限允许时才能复位。

## 边界与Reset

- 非正周期：斜坡、变化率和积分保持连续值或撤销有效位。
- 负延时：去抖与信号有效性FB拒绝运行，不向定时器传入非法参数。
- 零输入量程：线性缩放返回工程量程下端并置`bValid=FALSE`。
- 上下限传反：Clamp和Signal Validity先归一化边界。
- NaN/无穷或超工程有限范围：由`FC_IsFiniteLReal`拒绝。
- 行程边界已到、负制动裕量或减速度无效：制动速度上限为零。
- Reset/Disable：滤波、去抖、有效性、斜坡和握手撤销有效状态并按各自契约清理历史。

## TDD证据

### RED

实现前运行`Test-Phase4Utilities.ps1`，报告14个FC、6个FB和Phase 4执行报告全部缺失，共21项预期失败。

### 实现后报告闸门

20个对象和PLC编译清单完成后，测试只剩：

```text
Missing Phase 4 execution report
```

这证明测试没有因实现过程被放宽；报告补齐后进入GREEN。

### GREEN

```text
Phase 4 utility test: PASSED
Function count: 14
Utility FB count: 6
```

## Build证据

真实执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Cffwelding.ps1
```

最终结果：

```text
Starting TwinCAT XAE Shell build: TcXaeShell.DTE.15.0
Building project 'CFFwelding_System\CFFwelding_System.tsproj' with 'Release|TwinCAT RT (x64)'.
CFFwelding XAE build: PASSED
Configuration: Release|TwinCAT RT (x64)
LastBuildInfo: 0
```

首次Build尝试在工程加载后过早读取`SolutionBuild.SolutionConfigurations`，得到空列表，未进入编译。Solution文件本身存在完整配置；构建脚本随后增加独立的配置加载等待，再次执行真实Build通过。该加载失败没有被记录为编译通过。

## 审查证据

- Phase 1、Phase 2、Phase 3回归验收通过。
- 20个Phase 4 POU XML均可解析。
- 全部PowerShell脚本语法通过。
- Phase 4静态测试检查对象唯一性、PLC登记、中文注释和分层禁用项。
- 凭据模式检查为0项。
- `git diff --check`和暂存差异检查通过。
- 工程仍无真实I/O、驱动、编码器、PDO或Safety配置。

## 警告与TODO

1. 本Phase证明源码契约和XAE可编译，不等于运行时数值测试、硬件标定或工艺验证。
2. `FC_ValidateJoinProgram`基于当前Phase 3结构执行基础硬限制和判据校验；Phase 9扩充完整StepMin/StepMax、Decline Arm/Rate/Debounce字段后必须同步扩展。
3. 通用FB尚未实例化；后续Phase只能由实例所有权矩阵指定的PROGRAM声明一次。
4. Production Ready继续保持`FALSE`。

## Git状态

- Phase 4主Commit：`7be809a2284b67f42c931df15ad8ae52738f09cc`
- Commit消息：`feat(plc): add reusable functions and utility blocks`
- Push：GitHub网络不可达，当前保留本地Commit，待远程恢复后推送并复核。
- 本段证据由后续报告Commit补录，不改写主Commit。

## 下一风险

Phase 5将首次把通用滤波、缩放和有效性对象用于四通道Force、外部位移、累计S_rel与Collision接口；必须确保所有硬件输入仍是占位，未映射有效位保持`FALSE`，不得用假值旁路。
