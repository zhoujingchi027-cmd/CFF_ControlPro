
# IO与总线映射待确认

## 直接IO

| PLC变量 | 类型 | 物理意义 | 实际设备/PDO | 状态 |
|---|---|---|---|---|
| GVL_IO.nZForceRaw | DINT | Kistler/EP3174原始值 | | |
| GVL_IO.nZDisplacementRaw | DINT | 12 mm位移原始值 | | |
| GVL_IO.bZHomeSwitch | BOOL | Z Home | | |
| GVL_IO.bZLimitPositiveSwitch | BOOL | Z正限位 | | |
| GVL_IO.bZLimitNegativeSwitch | BOOL | Z负限位 | | |
| GVL_IO.bModeManualSwitch | BOOL | 手动模式 | | |
| GVL_IO.bModeAutomaticSwitch | BOOL | 自动模式 | | |
| GVL_IO.bModeMaintenanceSwitch | BOOL | 维修模式 | | |
| GVL_IO.bControlLocalSwitch | BOOL | 本地控制 | | |
| GVL_IO.bControlRobotSwitch | BOOL | 机器人控制 | | |
| GVL_IO.qLampRed | BOOL | 红灯 | | |
| GVL_IO.qLampYellow | BOOL | 黄灯 | | |
| GVL_IO.qLampGreen | BOOL | 绿灯 | | |

## 外部模块

| 模块 | 外部接口变量 | 输入/输出结构或长度 | 实际设备/PDO | 状态 |
|---|---|---|---|---|
| Robot | aRobotToPlc / aPlcToRobot | 20 BYTE / 20 BYTE | Profinet | |
| Gun Head Feed | stGunHeadFeedInput / Output | 3 DI / 2 DO | EtherCAT | |
| Magazine | stMagazineInput / Output | 8 DI / 5 DO | EtherCAT | |
| Fastener Station | stFastenerStationInput / Output | 10 DI / 7 DO | EtherCAT | |
