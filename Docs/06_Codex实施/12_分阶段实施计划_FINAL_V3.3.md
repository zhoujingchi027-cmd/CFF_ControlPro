# Codex分阶段实施计划 FINAL V3.3

每个Phase必须Build、审查、Commit；远程访问可用时随后Push规定工作分支。

## Phase 0：隔离与环境检测

- 输出唯一写入目录；
- 检查旧工程无修改；
- 初始化Git；
- 检测XAE、VS、Automation Interface；
- 检测Tc2_Standard/Tc2_MC2；
- 检测External API；
- 检测NC SAF；
- 生成环境报告。

### GitHub初始化与保护

- [ ] 固定Remote URL为`https://github.com/zhoujingchi027-cmd/CFF_ControlPro.git`。
- [ ] 检查`git user.name`和`git user.email`，不得编造。
- [ ] 检查本地`.git`和现有`origin`。
- [ ] 使用`git ls-remote --symref`检查远程访问和历史。
- [ ] 远程非空且本地不是Clone时停止，不做无关历史合并。
- [ ] 远程为空时建立首次`main`规范Commit。
- [ ] 创建工作分支`codex/cffwelding-greenfield-final-v3.3`。
- [ ] 生成`GIT_EXECUTION_REPORT.md`。

## Phase 1：创建工程

- CFFwelding.sln；
- CFFwelding_System；
- CFFwelding PLC；
- 最少库；
- 空Build。

XAE不可用：

- 完整SourceImport；
- 不伪造工程或Build。

## Phase 2：Task、PROGRAM骨架和实例接口

- 创建内部接口DUT：Axis/Force/Criterion/Sequence Command与Status。
- 明确每个FB实例Owner和声明位置。
- 所有实例声明增加中文块注释。
- 生成Instance Ownership Matrix和Internal Interface Catalog。



- Fast/Main/Slow；
- 所有PROGRAM；
- 调用顺序；
- 中文块注释；
- Build。

## Phase 3：DUT、GVL和无硬件绑定占位

- 不执行任何Scan。
- 不添加真实EtherCAT、AX5000、EP3174或IO-Link设备。
- 创建Z_axis/R_axis AXIS_REF。
- 环境允许时创建未绑定实际驱动的NC轴，并仅做PLC↔NC内部关联。
- GVL_IO使用AT %I* / AT %Q*或普通变量占位。
- 未映射的硬件有效位和Production Ready保持FALSE。
- 生成人工硬件绑定清单。



- 枚举；
- 结构；
- GVL；
- AXIS_REF；
- AT占位；
- One Writer；
- IO TODO；
- Build。

## Phase 4：FC与通用FB

- Math/Scale/Validation；
- Filter/Debounce/Ramp/Handshake；
- Reset与边界；
- Build。

## Phase 5：力、位移、Collision

- EP3174；
- Force四通道；
- 位移；
- S_rel；
- Collision；
- 标定结构；
- Build。

## Phase 6：标准NC Adapter与Owner

- Z标准命令；
- R速度命令；
- Owner；
- MC调用边界；
- Build。

## Phase 7：External Setpoint

- 核对实际签名；
- Enable/Feed/Disable；
- P/V/A/Direction；
- 完整退出；
- 报警；
- Build。

## Phase 8：导纳力控

- Ramp；
- PI；
- Anti-windup；
- SRel制动；
- Profile；
- 无扰；
- 硬保护；
- Build。

## Phase 9：Contact与Criterion

- Contact；
- ForceDecline；
- Primary/Secondary；
- StepMin/Max；
- EndCause；
- Program Validation；
- Build。

## Phase 10：CFF Sequence

- Step1并行Ramp；
- Step2；
- Step3；
- Brake+Compression；
- Step4 Valid Hold；
- Unload；
- Return；
- Evaluate；
- Build。

## Phase 11：R轴、能量、观察与曲线

- RPM；
- Torque；
- Energy；
- Interface Observer MonitorOnly；
- Process Window；
- Double Buffer；
- Build。

## Phase 12：模式、命令和主状态

- Mode/Source；
- HMI/Robot邮箱；
- Command Dispatcher；
- Initialize；
- Maintenance；
- Machine State；
- WPF权限；
- Build。

## Phase 13：Program和外围

- SaveStep/SaveProgram；
- Draft/Active/Snapshot；
- JoiningPoint；
- Fastener/Feeder；
- Robot/Clamp；
- Alarm/TowerLight；
- Build。

## Phase 14：ADS和追溯

- ADS DTO；
- GVL_HMI；
- Contract；
- Command/Ack；
- Status；
- Hold；
- Program/Point；
- Alarm/Result/Curve；
- Build。

## Phase 15：最终审查

- 全Build；
- Warning；
- Task顺序；
- One Writer；
- MC边界；
- UTF-8；
- 旧工程无修改；
- 内存；
- 所有报告；
- Final Commit。

## 每Phase报告

```text
目标
创建文件
修改文件
接口变化
Build证据
警告
TODO
Git Commit
下一风险
```
