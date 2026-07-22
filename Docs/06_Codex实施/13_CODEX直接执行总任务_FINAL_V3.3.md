# CODEX直接执行总任务 FINAL V3.3

## Task ID

```text
CFFWELDING-GREENFIELD-FINAL-V3
```

## 1. 目标

在`倍福CFF控制`内从零创建：

```text
CFFwelding.sln
CFFwelding_System
CFFwelding PLC Project
```

旧工程只读。

## 2. 实施前

完整读取全部最终文档。

输出：

- 当前目录；
- 写入目录；
- 参考目录；
- 冲突；
- XAE版本；
- 库版本；
- SAF检测；
- API检测；
- Phase计划；
- 阻塞项。

## 3. XAE分支

### 可用

自动创建工程、对象、任务、库并Build。

### 不可用

创建：

```text
CFFwelding_SourceImport/
DUT/
GVL/
POU/
FB/
FC/
XAE_CREATE_AND_IMPORT_CHECKLIST.md
```

不得声称Build Passed。

## 4. 必须实现

### 实时硬件

- Z_axis / R_axis AXIS_REF；
- EP3174；
- 外部位移；
- Collision；
- IO占位。

### Z控制

- Force四通道；
- Contact；
- 导纳PI；
- Anti-windup；
- SRel制动；
- External生命周期；
- Owner。

### R控制

- RPM；
- Torque；
- Power；
- Gross/Qualified Energy。

### CFF

- 四阶段；
- Primary/Secondary；
- Force Decline；
- StepMin/Max；
- Brake+Compression；
- Step4 Valid Hold；
- EndCause。

### 主控

- Mode/Source；
- CommandId/Ack；
- Initialize；
- Maintenance；
- Manual/Auto；
- Stop/Reset；
- MachineState；
- 权限。

### Program与外围

- Program Header/Steps；
- SaveStep/SaveProgram；
- Draft/Active/Snapshot；
- JoiningPoint；
- Fastener/Feeder；
- Robot/Clamp；
- Alarm/TowerLight。

### ADS

- Contract；
- GVL_HMI；
- Command/Status；
- Hold；
- Program/Point；
- Alarm/Result/Curve分页；
- 双缓冲。

## 5. 禁止

- 修改旧工程；
- TwinSAFE；
- Simulation；
- Virtual Axis；
- Fake IO；
- 纯扭矩力控；
- TorqueOffset默认启用；
- Torque/Energy默认强制推进；
- 步骤重置S_rel；
- 共享BOOL命令；
- WPF写Mode；
- WPF WriteControl停止Runtime；
- CffSequence调用MC；
- ForceController访问AXIS_REF；
- FastTask ADS大数组；
- 编造API和Build。

## 5A. 内部实例接口与无硬件绑定要求

### 实例和接口

- 每个FB实例只能声明一次，必须有唯一Owner。
- 每个关键实例前写中文块注释，说明任务、用途、输入、输出、Owner和Reset。
- FB必须通过显式`VAR_INPUT / VAR_OUTPUT / VAR_IN_OUT`和类型化DUT结构调用。
- PROGRAM不得访问其他PROGRAM局部变量。
- 外部对象不得访问FB内部变量。
- 轴Adapter可使用`VAR_IN_OUT AXIS_REF`；算法FB禁止使用AXIS_REF。
- 创建`INSTANCE_OWNERSHIP_MATRIX.md`和`INTERNAL_INTERFACE_CATALOG.md`。

### 外部硬件

本任务不进行任何硬件Scan、PDO Mapping和Drive Linking。

禁止：

```text
Scan Devices
Scan Boxes
Scan Motors
添加真实EtherCAT设备树
添加实际EP3174/IO-Link/AX5000
NC轴关联真实驱动、编码器、电机
PLC变量关联真实PDO
下载/激活真实硬件配置
```

必须保留：

```text
Z_axis / R_axis : AXIS_REF
GVL_IO AT %I* / AT %Q*占位
未绑定驱动的NC轴对象（环境允许时）
完整人工绑定清单
```

允许：

```text
PLC AXIS_REF ↔ NC轴对象
```

禁止：

```text
NC轴对象 ↔ 实际AX5000/编码器
GVL_IO变量 ↔ 实际PDO
```

未绑定硬件时，所有生产硬件有效位和生产Ready必须保持FALSE。

## GitHub和Commit执行要求

唯一仓库：

```text
https://github.com/zhoujingchi027-cmd/CFF_ControlPro.git
```

固定：

```text
Remote: origin
Work Branch: codex/cffwelding-greenfield-final-v3.3
```

开始实施前：

```bash
git config --get user.name
git config --get user.email
git remote -v
git ls-remote --symref https://github.com/zhoujingchi027-cmd/CFF_ControlPro.git HEAD
```

必须遵守：

- 不在任何位置记录Token或密码。
- 不覆盖指向其他仓库的`origin`。
- 远程非空且本地无该仓库历史时停止。
- 不使用`--allow-unrelated-histories`。
- 除空仓库首次建立main外，不直接在默认分支实施。
- 每个Phase Build/检查后做聚焦Commit。
- 默认每个Phase Commit后Push工作分支。
- 禁止Force Push、rebase、amend已Push提交和破坏性reset/clean。
- 不自动Merge、Tag、Release或删除分支。
- Push不可用时继续本地Commit，并在Git报告中记录待推送Commit。
- 最终生成`Docs/报告/GIT_EXECUTION_REPORT.md`。

## 6. 编译策略

每Phase后Build。

不得一次生成全部对象后再集中修复。

## 7. 报告

创建所有`Docs/报告`文件。

实现报告必须包含：

- 环境；
- 文件；
- Task；
- 对象；
- One Writer；
- Z Owner；
- External；
- Force；
- Criterion；
- Main State；
- Command；
- Program；
- R/Energy；
- Alarm；
- ADS；
- Build；
- Hardware TODO；
- Commissioning；
- Process Qualification TODO。

## 8. 最终回复限制

只允许基于证据说明：

```text
源码生成状态
Build状态
硬件映射状态
联调状态
工艺资格状态
```


## 人工完成Git认证

Push触发Git Credential Manager、浏览器登录或命令行凭据提示时：

1. Codex暂停。
2. 用户人工完成认证。
3. Codex不读取或记录输入内容。
4. 认证完成后继续原Push命令。

命令行`Password`字段应输入PAT，不是GitHub账户密码。

如果无法交互：

```bash
git push -u origin codex/cffwelding-greenfield-final-v3.3
```

由用户在本机终端手工执行。
