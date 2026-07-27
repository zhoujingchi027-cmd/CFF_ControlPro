# Codex分阶段实施计划 FINAL V3.7

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

## Phase 11A：硬接线IO和总线通讯契约

- [ ] GVL_IO仅创建冻结的13个应用接口和2个AXIS_REF。
- [ ] 创建Robot Profinet DUT/GVL/Adapter。
- [ ] 创建Feeder EtherCAT DUT/GVL/Adapter。
- [ ] 创建Gun Head EtherCAT DUT/GVL/Adapter。
- [ ] 删除/不创建PRG_ClampControl。
- [ ] Fastener流程只通过Request/Status协调Feeder与GunHead。
- [ ] Collision不作为硬接线输入。
- [ ] 不扫描或关联实际总线设备。
- [ ] 生成Direct IO Catalog、Bus Interface Catalog和Manual Mapping Checklist。
- [ ] Build。
- [ ] Commit：`feat(io): add hardwired and bus communication contracts`

## Phase 11B：位移碰撞点和模块化供钉

- [ ] 删除所有Collision IO/总线字段。
- [ ] 创建FB_CollisionDisplacementTeach。
- [ ] 创建碰撞位移窗口Config和Calibration结构。
- [ ] 多次Teach、位移/NC双锁存、极差评价。
- [ ] Runtime计算Sensor/Axis两套碰撞距离和Mismatch。
- [ ] 创建Gun Head Feed模块全部DUT/GVL/Adapter/PROGRAM。
- [ ] 创建Magazine模块全部DUT/GVL/Adapter/PROGRAM。
- [ ] 创建Fastener Station输入DUT/GVL/Adapter/PROGRAM骨架。
- [ ] 不创建Fastener Station物理输出。
- [ ] 创建PRG_FastenerSupplyCoordinator。
- [ ] 模块只通过Request/Status交互。
- [ ] 更新One Writer和Module Interface报告。
- [ ] Build。
- [ ] Commit：`feat(peripheral): modularize gun head magazine and fastener station`

## Phase 11C：IO_Config、模块PROGRAM和Action骨架

- [ ] 创建GVL_ExternalIO。
- [ ] 创建GVL_ModuleInterface。
- [ ] 创建PRG_IO_Config及输入/输出映射Actions。
- [ ] 创建PRG_MainTask或编译验证的等效调度。
- [ ] 创建Gun Head Feed、Magazine、Fastener Station模块PROGRAM Actions。
- [ ] 创建PRG_FastenerTransportCoordinator。
- [ ] 实现Magazine/Direct Blow握手路由。
- [ ] 创建双电控气缸、单电控气缸和定时吹气FB。
- [ ] 创建Maintenance Hold-to-Run接口。
- [ ] ACT_Automatic_TODO保持安全默认。
- [ ] Robot Codec布局保持TODO。
- [ ] 生成IO Config、Action、Cylinder和Handshake报告。
- [ ] Build。
- [ ] Commit：`feat(peripheral): add IO config module actions and cylinder interfaces`

## Phase 11D：确定外部接口和通用FB_Actuator

- [ ] 创建固定Legacy外部变量和类型。
- [ ] 检查ST_USINT/DUT_USINT为1字节。
- [ ] 创建IO_Config Raw Input/Output Actions。
- [ ] 创建Mapping Confirmation状态。
- [ ] Z Home/Limit改为gunBOX_bullIn映射。
- [ ] 创建FC_GetBitFromByte。
- [ ] 创建新版FB_Actuator和配置/状态/故障枚举。
- [ ] 不复制旧FB的全局依赖和HMI逻辑。
- [ ] 实例化全部6个气缸。
- [ ] Maintenance点动接入全部实例。
- [ ] 创建Actuator Instance和Raw Interface报告。
- [ ] Build。
- [ ] Commit：`feat(io): add legacy interface mapping and unified actuator block`

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
