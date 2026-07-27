> 历史版本记录，已被FINAL V3.7覆盖；不得作为Codex当前实施依据。


# FINAL V3.4更新说明

本版依据最终网络拓扑重新冻结IO和通讯边界。

## 硬接线IO

只保留：

- Z/R AXIS_REF；
- 力Raw；
- 位移Raw；
- Z Home/正负限位；
- Manual/Automatic/Maintenance；
- Local/Robot；
- Red/Yellow/Green Lamp。

## 总线

- Robot：Profinet；
- Feeder Valve Island：EtherCAT；
- Gun Head Module：EtherCAT。

## 架构变化

- 新增GVL_RobotProfinet、GVL_FeederEtherCAT、GVL_GunHeadEtherCAT；
- 新增三个总线Adapter FB；
- 新增PRG_GunHeadControl；
- PRG_FastenerControl只编排；
- 不再要求PRG_ClampControl；
- Collision不再作为硬接线IO，只允许作为枪头EtherCAT可选信号；
- 所有实际GSDML、ESI、PDO和设备Scan仍由用户后期人工配置。
