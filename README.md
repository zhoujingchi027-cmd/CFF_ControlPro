# 倍福CFF控制 / CFFwelding — 最终实施规范 V3.7

本目录是交给Codex创建全新TwinCAT 3工程的最终任务包。

## 固定项目名称

```text
目录：倍福CFF控制
Solution：CFFwelding.sln
System Project：CFFwelding_System
PLC Project：CFFwelding
```

## 最终冻结控制原则

```text
Z轴：
Kistler实际力反馈
→ 导纳型力PI输出速度
→ External Setpoint P/V/A/Direction
→ SRelSensor几何约束

R轴：
RPM控制
→ Torque/Power/Energy监控

步骤：
Primary Criterion
+ 条件性Secondary累计S_rel
+ StepMin/StepMax
+ 独立过程质量评价

HMI命令：
CommandId/Ack
→ PLC内部单周期Pulse

维修点动：
Hold-to-Run + Heartbeat

ADS：
只暴露GVL_HMI
→ 版本、命令、状态、Program、Joining Point、报警、曲线和结果
```

## 阅读顺序

1. `AGENTS.md`
2. `FINAL_DECISION_REGISTER.md`
3. `Docs/00_总规范/01_最终项目总规范_FINAL_V3.0.md`
4. `Docs/00_总规范/02_事实依据与工程判断边界_FINAL_V3.0.md`
5. `Docs/01_架构/03_软件架构对象目录与任务模型_FINAL_V3.0.md`
6. `Docs/01_架构/04_数据所有权与命令邮箱_FINAL_V3.0.md`
7. `Docs/01_架构/05_内部实例接口与无外部硬件绑定规则_FINAL_V3.1.md`
8. `Docs/01_架构/06_硬接线IO与外部接口边界_FINAL_V3.7.md`
9. `Docs/01_架构/07_位移碰撞点标定与外围模块解耦_FINAL_V3.7.md`
10. `Docs/01_架构/08_IO_Config模块PROGRAM与Action骨架_FINAL_V3.7.md`
11. `Docs/01_架构/09_确定外部接口与通用FB_Actuator_FINAL_V3.7.md`
12. `Docs/02_核心工艺/05_CFF流程与推进准则_FINAL_V3.0.md`
13. `Docs/02_核心工艺/06_Z轴导纳力控与ExternalSetpoint_FINAL_V3.0.md`
14. `Docs/02_核心工艺/07_R轴扭矩能量与过程观察_FINAL_V3.0.md`
15. `Docs/03_主控与外围/08_主状态机模式按钮与维修_FINAL_V3.0.md`
16. `Docs/03_主控与外围/09_Program连接点送料机器人报警_FINAL_V3.0.md`
17. `Docs/04_标定与联调/10_整机标定联调与工艺资格_FINAL_V3.0.md`
18. `Docs/05_ADS与追溯/11_PLC_ADS契约与WPF预布置_FINAL_V3.0.md`
19. `Docs/06_Codex实施/12_分阶段实施计划_FINAL_V3.7.md`
20. `Docs/06_Codex实施/13_CODEX直接执行总任务_FINAL_V3.7.md`
21. `Docs/06_Codex实施/14_最终验收与代码审查_FINAL_V3.7.md`
22. `Docs/06_Codex实施/15_GitHub仓库与提交推送策略_FINAL_V3.7.md`

## 已验证GitHub仓库

```text
Web：https://github.com/zhoujingchi027-cmd/CFF_ControlPro
Clone：https://github.com/zhoujingchi027-cmd/CFF_ControlPro.git
Remote：origin
Default Branch：main
实施分支：codex/cffwelding-greenfield-final-v3.3
```

该仓库在任务包生成时已验证可访问且具备Push/Admin权限，并且当前为空仓库。

首次Push如出现认证窗口，可由用户人工完成。HTTPS Git不接受GitHub账户密码，应使用Git Credential Manager、浏览器登录或PAT。

## 最新硬件与通讯边界

```text
硬接线IO：
力Raw、位移Raw、Z Home/正负限位、
Manual/Auto/Maintenance、Local/Robot、三色灯

机器人：
Profinet

送钉系统阀岛：
EtherCAT

枪头模块：
EtherCAT
```

Codex只创建程序接口和未绑定过程映像。所有Profinet、EtherCAT、AX5000、EP3174及PDO由用户以后Scan并人工配置。

## 模块PROGRAM与IO_Config

```text
GVL_ExternalIO
→ PRG_IO_Config
→ GVL_ModuleInterface
→ 各模块PROGRAM
→ PRG_IO_Config
→ 外部输出
```

Codex创建模块POU、Actions、气缸FB、维修点动和握手接口，但不编写模块完整自动主逻辑。
