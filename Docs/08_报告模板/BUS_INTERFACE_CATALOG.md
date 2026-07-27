
# 总线接口目录

| 总线 | 外部接口GVL | 物理输入结构 | 物理输出结构 | Module PROGRAM | 内部接口 | 人工映射状态 |
|---|---|---|---|---|---|---|
| Profinet | GVL_ExternalIO.aRobotToPlc / aPlcToRobot | 20 BYTE | 20 BYTE | PRG_RobotInterface | ST_RobotModuleInterface | |
| EtherCAT | GVL_ExternalIO.stGunHeadFeedInput / Output | ST_GunHeadFeedPhysicalInput | ST_GunHeadFeedPhysicalOutput | PRG_GunHeadFeedModule | ST_GunHeadFeedModuleInterface | |
| EtherCAT | GVL_ExternalIO.stMagazineInput / Output | ST_MagazinePhysicalInput | ST_MagazinePhysicalOutput | PRG_MagazineModule | ST_MagazineModuleInterface | |
| EtherCAT | GVL_ExternalIO.stFastenerStationInput / Output | ST_FastenerStationPhysicalInput | ST_FastenerStationPhysicalOutput | PRG_FastenerStationModule | ST_FastenerStationModuleInterface | |
