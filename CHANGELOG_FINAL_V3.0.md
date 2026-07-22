# FINAL V3.0更新摘要

相对前一版，最终版新增并冻结：

1. WPF Start/Stop/Initialize/Reset正式采用CommandId/Ack。
2. PLC内部保留单扫描命令Pulse，外部不使用共享BOOL清零。
3. Maintenance Hold-to-Run采用Level BOOL + Heartbeat。
4. 增加`PRG_CommandDispatcher`、`PRG_InitializeControl`和`PRG_MaintenanceControl`。
5. 主设备状态机增加BOOT、INITIALIZING、CONTROLLED_STOPPING、RESETTING等状态。
6. Test Mode全部并入Maintenance。
7. 模式与控制源由硬件开关决定，WPF只读。
8. WPF Stop明确为应用层受控停止，禁止停止PLC Runtime。
9. 增加按钮权限和命令拒绝原因接口。
10. 把公开事实与工程推断分开，避免把未公开的EJOT内部算法当成事实。
11. 统一Primary/Secondary、Force Decline和StepMin/StepMax语义。
12. 统一Program、Joining Point、Save Step、Save Program、Draft/Active/Snapshot。
13. 完整合并ADS契约、曲线双缓冲和分页。
14. 形成最终Codex阶段实施、Build和验收闭环。
