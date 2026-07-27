
# 外围模块接口目录

| 模块 | Bus GVL | Adapter | PROGRAM | Request | Status | 输出Owner | 输出定义完整 |
|---|---|---|---|---|---|---|---|
| Gun Head Feed | GVL_GunHeadFeedEtherCAT | FB_GunHeadFeedEtherCATAdapter | PRG_GunHeadFeedModule | ST_GunHeadFeedRequest | ST_GunHeadFeedStatus | PRG_GunHeadFeedModule | 是 |
| Magazine | GVL_MagazineEtherCAT | FB_MagazineEtherCATAdapter | PRG_MagazineModule | ST_MagazineRequest | ST_MagazineStatus | PRG_MagazineModule | 是 |
| Fastener Station | GVL_FastenerStationEtherCAT | FB_FastenerStationEtherCATAdapter | PRG_FastenerStationModule | ST_FastenerStationRequest | ST_FastenerStationStatus | 暂无物理输出 | 否 |
| Robot | GVL_RobotProfinet | FB_RobotProfinetAdapter | PRG_RobotInterface | Robot Command | Robot Status | PRG_RobotInterface | 是 |
