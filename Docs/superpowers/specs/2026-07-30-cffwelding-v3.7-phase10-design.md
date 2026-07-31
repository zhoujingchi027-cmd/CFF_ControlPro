# CFFwelding V3.7 Phase 10 CFF流程设计

- 日期：2026-07-30
- 状态：用户已逐节批准
- 分支：`codex/cffwelding-greenfield-v3.3`
- 目标：实现Contact接管、四步CFF流程、R轴速度命令、Brake/Compression、Step4有效保持、受控卸载、External退出、返回与Phase 10结果判定

## 1. 依据与约束

本设计以以下文件为权威依据：

- `CODEX_START_PROMPT.txt`
- `Docs/06_Codex实施/12_分阶段实施计划_FINAL_V3.7.md`
- `Docs/06_Codex实施/13_CODEX直接执行总任务_FINAL_V3.7.md`
- `Docs/02_核心工艺/05_CFF流程与推进准则_FINAL_V3.0.md`
- `Docs/02_核心工艺/06_Z轴导纳力控与ExternalSetpoint_FINAL_V3.0.md`
- `FINAL_DECISION_REGISTER.md`

必须保持以下锁定决策：

- Step1的RPM、Force和Z响应并行启动；
- Step3结束后RpmTarget到零与ForceTarget到Step4 Force允许重叠Ramp；
- Step4有效保持时间只在`RpmStopped AND ForceInBand`时累计；
- Force Decline确认前PI继续跟随，确认后由下一目标通过Ramp/无扰机制接管；
- Contact Search至Controlled Unload使用External Setpoint；Approach和Return使用标准NC；
- 整个周期只发生一次`Standard NC -> External -> Standard NC`切换；
- `PRG_CffSequence`、算法FB和Force Controller不得访问`AXIS_REF`或调用MC；
- 未完成真实映射、标定、配置和资格确认前，不得把任何Ready/Valid/ProductionReady强制设为真。

## 2. Phase边界

### 2.1 Phase 10包含

- 完整`PRG_CffSequence`状态机；
- Contact RequestId/Ack参考点事务；
- Step1至Step4目标和Phase 9判据接线；
- 实际R轴RPM目标事务、MC加减速斜坡参数和状态反馈门控；
- 连续External P/V/A/Direction轨迹；
- Active External内的安全零速方向转换；
- Controlled Unload、External Disable、Owner Release、Return和Evaluate；
- Phase 10所需的数据契约、配置、验证、报警、测试和报告。

### 2.2 Phase 10不包含

- Torque闭环或Torque Feed Forward；
- Energy、Power、Material Observer、Process Window和Curve Recorder；
- 最终`FB_ResultAnalyzer`工艺特征汇总；
- Runtime实时测试、真实轴测试或工艺参数整定；
- Collision IO删除和外部位移/NC双参考重构。该工作按V3.7计划保留给Phase 11B。

Phase 10不得生成虚假的Torque、Energy、Observer或Curve结果。Evaluate只使用本阶段真实获得的步骤事实。

## 3. 推荐架构

采用“流程意图、轨迹算法、命令路由、MC适配器”四层结构。

### 3.1 `PRG_CffSequence`

职责：

- 接受去重后的Cycle事务；
- 执行Precheck和CFF状态转换；
- 唯一持有并调用`FB_ContactDetect`、`FB_ForceDeclineObserver`和`FB_StepProceedingCriterion`；
- 生成Z轴Owner、标准定位、External生命周期、Z速度目标和R轴阶段目标等类型化意图；
- 锁存步骤结果、退出意图、首故障和终态。

禁止：

- 访问`AXIS_REF`；
- 调用任何MC功能块；
- 直接写External P/V/A；
- 读取其他PROGRAM局部变量。

### 3.2 `FB_ZExternalTrajectory`

新增纯算法/状态型FB，唯一实例放在`PRG_FastAxisControl`。

职责：

- 从External Adapter最后接受的Feed精确同步；
- 将Contact Search速度或导纳速度变成连续P/V/A；
- 执行速度变化率限制和梯形位置积分；
- 在需要改变速度符号时执行零速、方向保持、Direction=0和新方向预置；
- 检查有限值、位置边界、连续性和非法换向；
- 输出零速确认和确定性故障。

禁止：

- 访问GVL、`AXIS_REF`或MC；
- 自行决定工艺状态；
- 绕过Adapter直接写NC。

### 3.3 `PRG_FastAxisControl`

职责：

- 唯一声明`FB_ZExternalTrajectory`和计划中的`fbRSpeedRamp`；
- 把Sequence意图转换为Z标准NC候选、Force Process候选、External命令和R轴命令；
- Contact Search时选择搜索速度，Force Process时选择导纳输出速度；
- 在Sequence占用R轴时覆盖普通R候选，退出后恢复普通命令通道；
- 保持现有Z轴Owner仲裁优先级；
- 把轨迹故障并入External报警，把R/Z Adapter状态发布到Fast状态。

### 3.4 轴Adapter

- `FB_ZAxisNcAdapter`继续是标准Z轴MC命令的唯一Owner；
- `FB_ZAxisExtSetpointAdapter`继续是External Enable/Feed/Disable和Z轴引用的唯一Owner；
- `FB_RAxisNcAdapter`继续是R轴MC命令和R轴引用的唯一Owner；
- Adapter只管理MC接口、生命周期、命令有效性和状态，不承担CFF步骤逻辑。

## 4. 数据契约

### 4.1 新增机器级`ST_CffSequenceConfig`

安全超时属于机器配置，不允许由工艺配方放宽：

- `tApproachTimeout`
- `tContactSearchTimeout`
- `tContactReferenceAckTimeout`
- `tControlledUnloadTimeout`
- `tUnloadStandstillConfirm`
- `tRAxisStopTimeout`
- `tReturnTimeout`
- `bValid`

全部时间必须大于零；`bValid`默认保持`FALSE`。该结构加入`GVL_Config`，但Phase 10不写入合格值。

### 4.2 扩展Program Header

新增：

- `fContactSearchStartPositionMm`

该位置必须为有限值并位于机器Z轴软范围内。现有Contact Search速度、Contact阈值、窗口和Return字段继续使用。

### 4.3 扩展Step Proceeding Config

新增：

- `nQualifiedForceHoldMs`
- `fForceBandToleranceN`
- `fRpmStoppedThresholdRpm`

Step4必须使用Step Time Primary，且：

- Qualified Hold大于零且不大于Primary Step Time；
- Force Band大于零并低于机器硬力范围；
- RPM停止阈值非负且低于R轴工艺速度范围；
- Step4 Secondary Action必须是Controlled Exit NOK；
- Step1至Step3不消费这些Step4专用字段。

### 4.4 新增`ST_CffMotionIntent`

Sequence通过嵌套意图发布动作，不直接写Adapter命令邮箱：

- Z标准NC命令事务号和`ST_ZAxisCommand`候选；
- External Enable/Disable请求；
- External目标速度；
- R轴过程占用标志、命令事务号和`ST_RAxisCommand`候选；
- Force Process退出完成标志。

该结构作为`ST_CffSequenceStatus`的成员发布。现有Force目标、RPM目标、步骤和算法诊断字段继续保留，便于ADS诊断。

### 4.5 扩展External Adapter状态

`ST_ZExtSetpointStatus`新增最后接受的：

- Position；
- Velocity；
- Acceleration；
- Direction。

这些值在Precheck取得NC初值后即发布，并在每次Feed接受后更新。轨迹FB只以这些已接受值作为下一周期积分基准，不以“期望已发送”代替“Adapter已接受”。

### 4.6 轨迹输入输出

新增类型化`ST_ZExternalTrajectoryInput/Output`，至少包含：

- Enable、Reset、External状态和Feed Accepted；
- 已接受P/V/A/Direction；
- 目标速度、周期、最大速度、最大加速度和位置范围；
- Standstill阈值和Direction Hold周期；
- 输出P/V/A/Direction、Direction Transition、Zero Confirmed、Active、Fault和FaultId。

### 4.7 退出意图

新增或等价实现单一枚举，禁止用多个可冲突BOOL表达退出路径：

- `NORMAL_RETURN`
- `NOK_RETURN`
- `ABORT_NO_RETURN`
- `FAULT_NO_RETURN`

## 5. 正常状态流

```text
IDLE
-> PRECHECK
-> APPROACH
-> EXTSETPOINT_PREPARE
-> CONTACT_SEARCH
-> CONTACT_ACCEPT
-> STEP1_ENTRY / STEP1_RAMP_PROCESS / STEP1_END_CHECK
-> STEP2_ENTRY / STEP2_RAMP_PROCESS / STEP2_END_CHECK
-> STEP3_ENTRY / STEP3_RAMP_PROCESS / STEP3_END_CHECK
-> BRAKE_AND_COMPRESSION_RAMP
-> STEP4_VALID_FORCE_HOLD
-> CONTROLLED_FORCE_UNLOAD
-> EXTSETPOINT_DISABLE
-> RETURN_LOCAL or RETURN_REFERENCE
-> EVALUATE
-> COMPLETE_OK or COMPLETE_NOK
```

每个状态最多在一个Fast扫描内迁移一次。Entry脉冲、事务号增加和算法Reset只在状态进入扫描产生。

## 6. Precheck与事务语义

只有新的Start CommandId才可启动。重复或旧CommandId不得重复产生任何动作。

Precheck至少要求：

- `bProductionPermission`和`GVL_Status.bProductionReady`均为真；
- Cycle Snapshot有效、ProgramId/JoiningPoint匹配且`FC_ValidateJoinProgram`通过；
- Machine、Limits、Sensor、Force、R Axis、External和Sequence Config有效；
- Tool/Anvil/Profile/Revision一致；
- Z/R真实绑定且Ready、Standstill、无错误；Z轴还必须Homed，R轴速度模式不虚构原点要求；
- Force/Displacement/Collision状态有效；
- External处于Idle/Released，Z Owner无冲突；
- Fast周期配置有效；
- Approach、Contact、Return和全部Step目标位于机器硬边界内。

任一失败均锁存确定性Precheck错误，不发布运动事务。Phase 10不得通过写TRUE绕过这些条件。

## 7. Approach、External与Contact

### 7.1 Approach

- 锁存Cycle开始时Z实际位置，供Local Return使用；
- 以`Z_OWNER_APPROACH`向`fContactSearchStartPositionMm`发出一次标准绝对定位事务；
- 等待Adapter接受和完成；
- Error或Timeout进入Fault，无External接管。

### 7.2 External Prepare

- 请求`Z_OWNER_FORCE_PROCESS`；
- Adapter从`NcToPlc.SetPos/SetVelo/SetAcc`取得真实接管初值；
- Trajectory从Adapter发布的接受值同步；
- Enable确认前不使能力控，不增加Contact参考事务。

### 7.3 Contact Search

- External目标速度为向下的`fContactSearchVelocityMmS`；
- 每个Fast周期生成连续P/V/A/Direction；
- `FB_ContactDetect`使用Force Criterion、Axis/Sensor绝对位置、速度窗口和Debounce；
- Contact确认脉冲只产生一次参考点RequestId，并携带候选扫描锁存的Axis/Sensor位置；
- 等待`udiContactReferenceAcceptedId`匹配且Contact Reference有效；
- Ack超时、窗口越界或信号失效进入Fault退出。

### 7.4 Contact Accept

- 以当前搜索速度作为Force Controller无扰预置速度；
- Force Set Ramp从当前Force Control值开始；
- 参考点Ack成功后才使能导纳和进入Step1；
- R轴在Contact Search期间保持零目标。

## 8. Step1至Step3

### 8.1 Step1并行Ramp

进入Step1的同一扫描：

- Force目标切换到Step1 SetForce；
- R轴发出Step1目标RPM的新事务；
- MC速度命令使用已验证的Acceleration/Deceleration；
- `fbRSpeedRamp`以相同斜率跟踪期望速度包络；
- Step Timer、Decline和Proceeding Criterion开始。

禁止每个2 ms扫描产生新的R轴MC事务。

### 8.2 Step2和Step3

- 每次Entry只重置本步骤Decline/Criterion和步骤时间；
- S_rel从Contact累计，不因步骤切换清零；
- Force/RPM目标按程序切换，R目标变化只产生一个新事务；
- Primary、Secondary、TooShort、StepMax和EndCause完全使用Phase 9算法输出；
- `AdvanceAndNok`继续下一步骤并锁存Cycle NOK；
- `ControlledExitNok`直接选择NOK受控退出；
- 每步锁存结果写入其唯一结果槽，不被下一步覆盖。

### 8.3 Step3结束

Step3正常或允许推进的结束扫描只设置后续意图，不直接跳过Brake状态。

## 9. Brake、Compression与Step4

进入`BRAKE_AND_COMPRESSION_RAMP`时：

- RpmTarget设置为零并发出一次带减速度的R轴停止/零速事务；
- ForceTarget同时设置为Step4 Force；
- Step4总步骤时间、Proceeding Criterion和Qualified Hold从本状态开始；
- 两个Ramp并行运行。

Ramp目标达到后进入`STEP4_VALID_FORCE_HOLD`，但不得重置Step4总时间或Qualified Hold。

每个有效Fast周期：

```text
IF ABS(ActualRpm) <= RpmStoppedThreshold
   AND ABS(ForceControl - Step4Force) <= ForceBandTolerance
THEN
    QualifiedForceHold := QualifiedForceHold + Ts
END_IF
```

条件为假时暂停累计，不清零。计数采用饱和累加，禁止溢出。

Step4 Primary Step Time达到时：

- Qualified Hold达到要求：选择Normal Return；
- Qualified Hold不足：锁存Cycle NOK并选择NOK Return；
- 两者都必须先完成受控卸载。

## 10. External内安全方向转换

受控卸载把ForceTarget向零Ramp。实际力高于目标时，导纳速度可能由正值变为负值，因此现有“Active期间禁止方向变化”的Adapter逻辑不足以完成规范要求。

Phase 10允许且只允许以下Active内方向转换：

```text
当前速度按最大加速度减至零
-> 以最后非零Direction静止Feed规定周期
-> Direction=0静止Feed至少一个周期
-> 新非零Direction静止预置至少一个周期
-> 按最大加速度向新方向恢复Feed
```

约束：

- 非零速度下改变Direction立即Fault；
- `+1 -> -1`或`-1 -> +1`直接跳变立即Fault；
- Direction=0期间Velocity和Acceleration必须在静止窗口；
- 转换期间轨迹始终从Adapter最后接受值同步，位置不得继续“空积分”；
- 转换不是Disable，不增加第二次Standard/External模式切换；
- Disable仍使用既有Ramp to Zero、Direction Hold、Direction Zero、Disable、Wait Disabled和Post Hold序列。

## 11. Controlled Unload与退出

### 11.1 正常/NOK卸载

- R目标保持零；
- ForceTarget受控Ramp到零；
- Force Sensor和External健康时允许导纳产生非正向卸载速度；
- 目标力到零、实际力降至Contact Off范围、接受速度进入Standstill窗口并持续确认后，才请求External Disable；
- Unload超时进入Fault退出；
- External发布`bReleaseOwner`前不得请求标准Return。

### 11.2 Stop/Abort

- 立即锁存`STOP_REQUEST`和`ABORT_NO_RETURN`；
- 禁止继续向下；
- R轴发出一次受控停止事务；
- Force和External健康时执行受控卸载，否则直接把Z目标速度归零并走Adapter安全退出；
- External释放后进入`CFF_ABORT`，不得自动Return。

### 11.3 Fault

- 第一故障原因锁存，后续派生错误不得覆盖；
- Hard Force、Hard Stroke或Collision立即禁止正向速度，R轴受控停止；
- 传感器失效时禁止继续使用导纳PI，目标速度归零并退出External；
- Z/R轴或External错误时停止发布新运动，保持Fault Stop Owner；
- Fault退出后不得自动Return；
- 未知状态、未知枚举、非有限值或任何算法Fault均Fail Closed。

### 11.4 Reset

- 活动周期中的Reset按Abort受控退出；
- 只有Z/R静止、External已释放并处于Idle或终态时才清除状态机、算法、轨迹和首故障锁存；
- Reset不得自动重启上一次CommandId。

## 12. Return与Evaluate

### 12.1 Return

- `RETURN_MODE_LOCAL`返回Start事务接受时锁存的Z位置；
- `RETURN_MODE_REFERENCE`返回Program Header的`fReturnOpeningMm`；
- 两者使用`fReturnVelocityMmS`；
- Return前必须确认External Released、Rpm Stopped、Z/R Ready且无错误；
- Return Error或Timeout转Fault，不得标记完成。

### 12.2 Evaluate

Phase 10只评价：

- 四步EndCause；
- TooShort、Secondary、StepMax；
- Step4 Qualified Hold；
- Stop/Abort/Fault；
- 状态机和退出是否完整。

`COMPLETE_OK`、`COMPLETE_NOK`、`ABORT`和`FAULT`互斥。Phase 11的Result Analyzer后续可消费这些已锁存事实，但不得由Phase 10伪造缺失特征。

终态发布语义固定为：

- `COMPLETE_OK`：`bDone=TRUE`、`bError=FALSE`、`bAborted=FALSE`；
- `COMPLETE_NOK`：`bDone=TRUE`、`bError=TRUE`、`bAborted=FALSE`；
- `ABORT`：`bDone=FALSE`、`bError=FALSE`、`bAborted=TRUE`，除非退出过程中另有真实故障；
- `FAULT`：`bDone=FALSE`、`bError=TRUE`、`bAborted=FALSE`。

## 13. R轴命令策略

每次阶段目标变化只发一个事务：

- Step1目标；
- Step2目标；
- Step3目标；
- Brake/Stop零目标；
- Stop/Abort/Fault停止目标。

实际NC速度Ramp由`MC_MoveVelocity`或`MC_Halt`的Acceleration/Deceleration完成。`fbRSpeedRamp`使用相同斜率生成期望包络、目标到达和诊断，不把每个Fast扫描变成新的MC Execute。

Step4的`RpmStopped`只使用实际R轴反馈，不使用软件目标或Ramp完成标志替代。

## 14. 报警和诊断

- 报警槽9继续只发布Phase 9 Contact/Decline/Criterion故障；
- 新增固定槽10发布CFF Sequence、Timeout和非法状态故障；
- External轨迹/方向故障并入`PRG_FastAxisControl`负责的External报警；
- R/Z轴错误继续使用对应轴报警；
- 每个错误使用确定性ErrorId，状态机只锁存第一原因；
- Status发布当前State、Step、SubPhase、EndCause、退出意图、步骤时间、Qualified Hold、Force/RPM目标和运动意图诊断。

## 15. Collision边界

当前仓库仍保留早期Collision数字输入占位，而V3.7把删除这些IO和双位置碰撞Teach明确安排在Phase 11B。

Phase 10规则：

- 不新增或恢复任何Collision IO依赖；
- 只消费现有类型化Collision Valid/Limit状态；
- 状态无效时Precheck拒绝或活动周期Fault；
- 不把Collision状态强制为真；
- Phase 11B再完成结构替换、IO删除和Sensor/Axis距离冗余判断。

## 16. 测试驱动策略

先新增失败的ASCII-only `scripts/Test-Phase10CffSequence.ps1`，再逐批实现。测试脚本是离线契约和参考向量，不冒充PLC Runtime测试。

### 16.1 结构和所有权

- 新DUT、FB和枚举唯一存在并加入PLC Project；
- `FB_ZExternalTrajectory`和`fbRSpeedRamp`只在`PRG_FastAxisControl`实例化；
- Sequence/Trajectory无`AXIS_REF`、MC、GVL或跨PROGRAM局部访问；
- 三个Adapter仍是MC和轴引用唯一Owner；
- 报警槽和GVL Writer不冲突。

### 16.2 Validation

- 接受最小合法四步程序和合法Sequence Config；
- 拒绝非法搜索起点、Step4非Time Primary、Qualified Hold越界、Force/RPM阈值非法和零/负Timeout；
- 拒绝非有限值、未知枚举、硬限值越界和Revision/Profile/Tool/Anvil不一致。

### 16.3 轨迹

- 从Adapter接受值无跳变同步；
- 速度Rate Limit、加速度和梯形位置积分正确；
- 相邻Feed连续；
- 正向到零、Direction Hold、Direction=0、新方向预置和负向恢复顺序正确；
- 直接换向、非有限值、越界、位置跳变和非法Direction锁存Fault；
- Unload零速确认和Disable前置条件正确。

### 16.4 状态机

- CommandId去重和Precheck Fail Closed；
- Approach、External Enable、Contact Request/Ack顺序；
- Contact接管无扰预置；
- Step1力/RPM同扫描启动；
- Step1至Step3全部Primary/Secondary/TooShort/StepMax/EndCause路径；
- Brake与Compression并行；
- Step4 Qualified Hold累计、暂停、不清零和不足NOK；
- Normal/NOK Unload、Disable、Owner Release和Return顺序；
- Local/Reference Return目标；
- Stop/Abort/Fault无自动Return；
- 每个等待状态Timeout和首故障锁存；
- 四种终态互斥。

### 16.5 R轴

- 每个目标变化只增加一次R CommandId；
- 稳定阶段不重复产生MC命令；
- Step1并行启动、Step2/3换速和Brake零目标；
- Stop/Abort/Fault均优先停R；
- Step4只以实际RPM判断Stopped。

### 16.6 回归和Build

- 运行Phase 1至Phase 9全部现有测试；
- 运行Phase 10测试；
- 执行`scripts/Build-Cffwelding.ps1 -Configuration 'Release|TwinCAT RT (x64)'`；
- 记录真实Build输出、错误数和警告数；
- 不执行Scan、Activate、Download、Login、Online Change或真实轴动作。

## 17. 提交策略

保持设计、计划、源码和报告分离：

1. `docs(design): define V3.7 Phase 10 CFF sequence`
2. `docs(plan): add V3.7 Phase 10 implementation plan`
3. `feat(process): implement Phase 10 CFF sequence`
4. `docs(report): record Phase 10 sequence verification`

每个聚焦提交完成后Push当前分支。不得修改全局Git身份，不得输出密码、PAT或其他认证信息。

## 18. 完成定义

Phase 10只有在以下条件全部满足时才可声明完成：

- 已批准设计和实施计划全部落实；
- Phase 1至Phase 10离线测试全部通过；
- TwinCAT XAE Release x64 Build通过；
- 规格符合性、代码质量和安全边界审查无阻塞问题；
- 源码与报告分别提交并Push；
- 工作树干净且本地分支与远端同步；
- 报告明确列出所有尚未执行的Runtime、硬件和工艺资格验证。
