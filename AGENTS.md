# AGENTS.md — CFFwelding TwinCAT 3 全新工程最终规则 V3.3

## 1. 项目身份

本目录是一个全新的、独立的 Beckhoff TwinCAT 3 CFF 双轴摩擦元件焊接工程。

固定名称：

```text
工作目录：倍福CFF控制
Solution：CFFwelding.sln
TwinCAT System Project：CFFwelding_System
PLC Project：CFFwelding
```

严禁修改旧工程。以下目录仅可只读参考：

```text
../CFF_TwinCAT3_Pro
../CFF_TwinCAT3
../FDS_PLC
../SPR重庆发货
../GroupMDG
```

不得从旧工程整目录复制PLC对象。任何参考或复用必须记录在：

```text
Docs/报告/REFERENCE_REUSE_LOG.md
```

## 2. 已冻结的真实硬件

```text
Z轴：真实 AXIS_REF，压入/压力轴
R轴：真实 AXIS_REF，摩擦主轴

Z轴力测量：
Kistler 4574A
→ Kistler 4709A
→ 0~10 V
→ Beckhoff EP3174
→ PLC标定、滤波和诊断

工艺位移：
12 mm外部位移传感器
→ SRelSensor，作为工艺相对位移主值

机械参考：
独立Collision Reference Sensor
```

电机扭矩不能替代Kistler实际轴向力反馈。

## 3. 已冻结的正式控制架构

### Z轴

```text
ForceActual
→ 导纳型力PI
→ ZVelocityCmd
→ SRel/速度/加速度/硬边界限制
→ External Setpoint P/V/A/Direction
→ TwinCAT NC
→ AX5000
```

首版不使用纯扭矩力控。

可选TorqueOffset仅作为后续验证过的前馈扩展，默认关闭。

### R轴

```text
RPM设定
→ TwinCAT NC / AX5000内部速度与电流环
```

Torque用于：

- 功率与能量；
- 过程监控；
- 特征提取；
- 异常和质量判断；
- 后续材料界面观察。

首版不实现R轴外部扭矩闭环。

## 4. CFF步骤与推进准则

四个正式步骤：

```text
STEP1_PENETRATION
STEP2_CLEAN_ACTIVATE
STEP3_WELDING
STEP4_COMPRESSION
```

Step3与Step4之间必须经过：

```text
BRAKE_AND_COMPRESSION_RAMP
```

每一步只能配置一个第一准则：

```text
Relative Distance
Step Time
Decline of Force To
```

规则：

```text
Primary = Relative Distance
→ Secondary不用

Primary = Step Time或Decline of Force To
→ Secondary必须为从Contact开始累计的S_rel
```

S_rel在Contact接受时清零一次，步骤之间不得再次清零。

Torque和Energy在EJOT兼容模式中默认属于过程监控和质量评价，不是强制步骤推进条件。

## 5. Force Decline最终规则

```text
SetForce = 当前步骤控制目标
DeclineTo = 当前步骤结束阈值
```

在Decline确认前：

- 力PI继续跟随当前SetForce；
- 实际力下降时允许增加向下速度；
- 速度受Secondary S_rel、Hard S_rel、Collision及V/A限制；
- 不得为了让Decline容易触发而关闭PI。

Decline必须先武装：

```text
ForceCriterion >= ArmForce
```

再满足：

```text
ForceCriterion <= DeclineTo
AND dForce/dt为负
AND 有效RPM/S_rel窗口
AND Debounce
```

Decline确认后：

- 锁存Force、S_rel、Torque、Energy和时间；
- 结束当前步骤；
- 无扰切换下一Profile；
- 不再追当前步骤的旧力目标。

## 6. 模式、控制源与WPF命令

操作模式：

```text
Maintenance
Manual
Automatic
```

控制源：

```text
Local
Robot
```

唯一合法组合：

```text
Maintenance + Local
Manual + Local
Automatic + Robot
```

硬件模式和控制源开关是权威来源。WPF不得写实际模式或控制源。

EJOWELD Test Mode的功能全部合并到Maintenance：

- Calibration；
- Motion Test；
- Feeding Test；
- Cylinder Jog；
- Lamp Test；
- IO Diagnostic。

WPF的一次性命令必须使用：

```text
CommandId
CommandCode
AckCommandId
ExecutionState
RejectReason
```

不得使用“WPF写TRUE、PLC再清FALSE”的共享BOOL作为正式Start/Stop/Initialize/Reset接口。

PLC内部可以将已接受事务转换成一个扫描周期的：

```text
bStartPulse
bStopPulse
bInitializePulse
bResetPulse
```

维修点动和气缸点动属于Hold-to-Run，使用：

```text
Level BOOL + ClientSessionId + Heartbeat Timeout
```

PLC不清写入请求位，只在权限和心跳有效时采纳。

WPF Stop是应用层受控停止，不得使用ADS `WriteControl`停止PLC Runtime。

## 7. PROGRAM POU / FB / FC分工

本文中的“POU流程逻辑”专指PROGRAM类型POU（`PRG_xxx`）。

### PROGRAM POU

以下逻辑放PROGRAM，便于在线观察和调试：

- 实时工艺状态机；
- 设备主状态；
- 模式与命令仲裁；
- 初始化；
- Maintenance；
- 标定编排；
- Program/Joining Point管理；
- Manual/Auto；
- 侦钉、送料、机器人、夹具；
- 报警和三色灯；
- ADS映射；
- 结果、统计和持久化接口。

### FB

仅用于：

- 控制算法；
- 有内部状态的可复用模块；
- 轴与硬件适配；
- Ramp、去抖、窗口、统计、握手；
- 标定子模块。

### FC

仅用于：

- 无内部状态；
- 相同输入得到相同输出；
- 数学、缩放、限幅、积分、插值、转换、校验。

### 强制边界

- `PRG_CffSequence`不得调用MC功能块。
- `FB_ZForceAdmittance`不得访问AXIS_REF。
- 轴Adapter不得包含力PI。
- 任意物理输出、主状态和轴命令只有一个写入者。
- FastTask不得做字符串、文件、数据库或ADS大数组搬运。
- `MAIN`不得堆积业务逻辑；任务直接调用PROGRAM列表。

## 8. 内部实例接口与硬件绑定边界

### 内部实例接口

- 每个FB实例只能声明一次，并有唯一Owner。
- 默认在拥有该实例的PROGRAM `VAR`区声明。
- 跨PROGRAM共享实例仅在确有必要时放入`GVL_Instance`，并形成所有权报告。
- PROGRAM之间不得访问彼此的局部变量。
- FB之间通过明确的`VAR_INPUT / VAR_OUTPUT / VAR_IN_OUT`和类型化DUT接口交互。
- 只有轴Adapter可以使用`VAR_IN_OUT AXIS_REF`。
- 算法FB不得访问`AXIS_REF`、物理IO或其他FB内部变量。
- 每个实例声明前必须有中文块注释，说明用途、任务、Owner、输入、输出和Reset生命周期。

### 外部硬件不关联

本任务只创建PLC程序和内部接口，不执行外部硬件扫描和关联。

Codex不得：

- 执行Scan Devices、Scan Boxes、Scan Motors；
- 自动添加EP3174、IO-Link、AX5000或其他实际EtherCAT设备；
- 关联PLC变量与真实PDO；
- 关联NC轴与真实驱动、编码器或电机；
- 激活或下载真实硬件配置。

Codex应创建：

```text
Z_axis / R_axis : AXIS_REF
GVL_IO中的AT %I* / AT %Q*占位
必要时两个未关联实际驱动的NC轴对象
内部PROGRAM/FB实例和命令状态接口
人工硬件绑定清单
```

允许的内部关联：

```text
PLC AXIS_REF ↔ NC轴对象
```

禁止的外部关联：

```text
NC轴对象 ↔ AX5000/编码器
PLC变量 ↔ EtherCAT/IO-Link PDO
```

未完成硬件映射时，传感器、驱动和生产硬件有效状态必须保持FALSE，生产Start必须被禁止。不得写假值使设备进入Ready。

## 8. 中文注释与编码

标识符必须使用英文ASCII。

以下内容必须有独立行中文注释：

- GVL公开变量；
- DUT字段；
- IO意义；
- 工程单位；
- 状态Entry/Action/Success/Timeout/Fault；
- 关键算法；
- 标定、准则和结果原因。

正确：

```pascal
(* Z轴力闭环使用的低延迟实际力，单位kN。 *)
rForceActualControl_kN : LREAL;
```

禁止：

```pascal
rForceActualControl_kN : LREAL; // 中文行尾注释
```

保持TwinCAT XML原有UTF-8编码，不批量重写无关XML。

运行时文本使用：

```text
AlarmCode + AlarmTextId
```

FastTask不处理中文字符串。

## 9. 工程单位与方向

变量名体现单位：

```text
_kN
_mm
_mm_s
_mm_s2
_rpm
_Nm
_W
_Ws
_s
_ms
_us
_Hz
_pct
```

统一工艺坐标：

```text
Z向下为正
压向力为正
```

NC或传感器方向只允许在对应Adapter/Scale层转换一次。

## 10. 任务和实时性

```text
Task_CffFast周期 = 实际NC SAF周期
```

不得无证据固定为1 ms。

必须记录：

- 实际TwinCAT版本；
- Tc2_MC2版本；
- NC SAF周期；
- PLC FastTask周期；
- 周期抖动；
- EP3174与位移采样周期；
- External Setpoint Feed周期。

## 11. 禁止项

禁止创建：

- TwinSAFE；
- Safety PLC程序；
- Plant仿真；
- 虚拟轴生产配置；
- 虚拟力/位移；
- 假Ready、假许可、假IO；
- 模糊控制；
- 未验证MPC；
- 神经网络；
- WPF C#程序；
- 数据库；
- 机器人轨迹；
- 绕过NC直接写驱动PDO的生产控制；
- 编造API、PDO类型、地址、库版本或构建结果。

标准PLC报警不能替代人员安全系统。本项目不声明机器安全合格。

## 12. GitHub仓库和Commit规则

唯一远程仓库：

```text
https://github.com/zhoujingchi027-cmd/CFF_ControlPro.git
```

固定Remote：

```text
origin
```

默认实施分支：

```text
codex/cffwelding-greenfield-final-v3.3
```

Codex必须遵守：

- 第一次操作前验证Git身份、Remote和远程是否有历史。
- 不得在URL、文件或日志中嵌入PAT或密码。
- `origin`已指向其他仓库时立即停止，不得覆盖。
- 远程非空而本地不是Clone时停止，不得使用`--allow-unrelated-histories`。
- 除空仓库首次建立`main`外，不直接在默认分支实施。
- 每个Phase Build/静态检查成功后做一个或多个聚焦Commit。
- 默认每个Phase Commit后Push工作分支。
- Push失败时保留本地Commit并报告，不得Force Push。
- 禁止自动Merge、Tag、Release或删除远程分支。
- 禁止`reset --hard`、`clean -fdx`、`rebase`、`commit --amend`和任何Force Push，除非用户明确批准。
- 必须生成`Docs/报告/GIT_EXECUTION_REPORT.md`。

人工认证规则：

- 允许用户在`git push`时人工完成Git Credential Manager、浏览器或PAT认证。
- GitHub账户密码不能用于HTTPS Git；终端“Password”提示应输入PAT。
- Codex不得读取、记录、回显或保存认证秘密。
- 如果环境不能交互，保留本地Commit并输出手工Push命令。

完整规则见：

```text
Docs/06_Codex实施/15_GitHub仓库与提交推送策略_FINAL_V3.3.md
```

## 13. Git和交付

新目录使用独立Git。

每个Phase：

```text
Build
Review
Commit
```

最终必须生成：

```text
Docs/报告/IMPLEMENTATION_REPORT_CFFwelding_FINAL.md
Docs/报告/TWINCAT_BUILD_REPORT.md
Docs/报告/HARDWARE_TODO.md
Docs/报告/COMMISSIONING_CHECKLIST.md
Docs/报告/REFERENCE_REUSE_LOG.md
Docs/报告/ONE_WRITER_MATRIX.md
Docs/报告/ADS_STRUCT_LAYOUT.md
Docs/报告/IO_MAPPING_TODO.md
Docs/报告/NC_CONFIGURATION_CHECKLIST.md
```

无真实证据时不得声明：

```text
Production Ready
安全已验证
工艺等同EJOT
量产参数合格
```
