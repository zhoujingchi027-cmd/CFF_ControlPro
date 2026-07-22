# 最终验收与代码审查 V3.2

## 工程隔离

- [ ] 只修改新目录。
- [ ] 旧工程无变化。
- [ ] 独立Git。

## Build

- [ ] XAE/库版本记录。
- [ ] Build证据。
- [ ] Warning清单。
- [ ] 无伪造结果。

## 代码结构

- [ ] 流程PROGRAM。
- [ ] 算法/Adapter FB。
- [ ] 纯计算FC。
- [ ] MAIN无业务。
- [ ] CFF无MC。
- [ ] Force FB无AXIS_REF。
- [ ] 单一写入者。

## 任务

- [ ] Fast=SAF或明确阻塞。
- [ ] Fast无字符串/文件/ADS大块。
- [ ] Step3判定Fast。
- [ ] Slow不做控制。

## 力

- [ ] EP3174状态。
- [ ] 四力信号。
- [ ] 标定。
- [ ] Hard Force。
- [ ] Invalid禁止力控。

## 位移

- [ ] SRelSensor主。
- [ ] SRelAxis诊断。
- [ ] Delta。
- [ ] Contact动态。
- [ ] Collision独立。
- [ ] 无自动降级焊接。

## Criterion

- [ ] 单Primary。
- [ ] Time/Decline强制Secondary。
- [ ] S_rel累计。
- [ ] Decline Arm/Rate/Debounce。
- [ ] Decline前PI继续。
- [ ] Decline后无扰切换。
- [ ] StepMin不导致过冲。
- [ ] EndCause保存。
- [ ] Torque/Energy默认监控。

## External

- [ ] 初值连续。
- [ ] P/V/A一致。
- [ ] Feed每SAF。
- [ ] Direction正确。
- [ ] Disable完整。
- [ ] 无PTP冲突。
- [ ] 无循环重触发MoveVelocity。

## 主控

- [ ] Mode/Source硬件权威。
- [ ] 只有三种合法组合。
- [ ] Test合并Maintenance。
- [ ] MachineState完整。
- [ ] Initialize/Reset语义分开。
- [ ] Stop受控。
- [ ] CommandId/Ack。
- [ ] Hold+Heartbeat。
- [ ] PLC按钮权限。

## Program

- [ ] SaveStep/SaveProgram。
- [ ] Draft/Active/Snapshot。
- [ ] JoiningPoint唯一。
- [ ] Auto无Point拒绝。
- [ ] Revision。

## R与Step4

- [ ] RPM。
- [ ] Torque单位有效性。
- [ ] Gross/Qualified Energy。
- [ ] Step1并行。
- [ ] Brake/Force Ramp重叠。
- [ ] Step4有效Hold。

## 外围和报警

- [ ] Fastener/Feeder。
- [ ] Robot Sequence/Ack。
- [ ] Warning/NOK/Fault。
- [ ] Fault锁存。
- [ ] Reset源检查。
- [ ] TowerLight唯一写入。

## ADS

- [ ] 只公开GVL_HMI。
- [ ] Pack=1。
- [ ] Contract。
- [ ] Command Status。
- [ ] Snapshot Sequence。
- [ ] Hold。
- [ ] Program/Point。
- [ ] Alarm/Curve Page。
- [ ] Revision Notification。
- [ ] 无逐点通知。
- [ ] Stop不停止Runtime。

## 内部实例与硬件绑定

- [ ] 每个关键FB实例只有一个Owner。
- [ ] 实例声明有中文用途/任务/输入/输出/Reset注释。
- [ ] 所有关键FB有明确Input/Output类型化接口。
- [ ] PROGRAM之间不访问局部变量。
- [ ] 外部代码不访问FB内部变量。
- [ ] Codex没有执行Scan Devices/Boxes/Motors。
- [ ] 没有添加真实EtherCAT设备树。
- [ ] 没有链接EP3174、IO-Link、机器人或外围PDO。
- [ ] NC轴未链接实际驱动/编码器。
- [ ] 只允许PLC AXIS_REF与未绑定驱动的NC轴内部关联。
- [ ] GVL_IO使用占位接口。
- [ ] 未映射时生产Ready保持FALSE。
- [ ] 已生成实例所有权、内部接口和人工绑定清单。

## 注释

- [ ] 英文标识符。
- [ ] 中文独立行注释。
- [ ] UTF-8。
- [ ] 状态五要素注释。
- [ ] 无无关XML重写。

## GitHub和Commit

- [ ] Remote URL严格为`https://github.com/zhoujingchi027-cmd/CFF_ControlPro.git`。
- [ ] Remote名为`origin`。
- [ ] Git user.name/user.email来自现有配置，没有编造。
- [ ] 未将PAT、密码或Credential写入仓库/日志。
- [ ] 未覆盖其他Remote。
- [ ] 远程非空时从实际默认分支创建工作分支。
- [ ] 工作分支为`codex/cffwelding-greenfield-final-v3.3`。
- [ ] 除空仓库首次建立main外，没有直接在默认分支实施。
- [ ] 每个Phase有聚焦Commit和对应Build/检查。
- [ ] 没有Force Push。
- [ ] 没有`--allow-unrelated-histories`。
- [ ] 没有自动Merge、Tag、Release或删除分支。
- [ ] Push失败时保留本地Commit并有准确报告。
- [ ] 已生成`GIT_EXECUTION_REPORT.md`。
- [ ] 最终`git status`干净或明确列出未提交文件。

## 最终声明

- [ ] 不声明安全验证。
- [ ] 不声明EJOT等效。
- [ ] 不声明量产工艺合格。
