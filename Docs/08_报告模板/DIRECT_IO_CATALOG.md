
# 硬接线IO目录

| PLC变量 | 类型 | 方向 | 物理意义 | 后期映射设备/PDO | 映射状态 |
|---|---|---|---|---|---|
| GVL_IO.nZForceRaw | DINT | Input | Kistler/EP3174原始值 | | |
| GVL_IO.nZDisplacementRaw | DINT | Input | 12mm位移原始值 | | |
| GVL_IO.bZHomeSwitch | BOOL | Input | Z Home | | |
| GVL_IO.bZLimitPositiveSwitch | BOOL | Input | Z正限位 | | |
| GVL_IO.bZLimitNegativeSwitch | BOOL | Input | Z负限位 | | |
| GVL_IO.bModeManualSwitch | BOOL | Input | 手动模式 | | |
| GVL_IO.bModeAutomaticSwitch | BOOL | Input | 自动模式 | | |
| GVL_IO.bModeMaintenanceSwitch | BOOL | Input | 维修模式 | | |
| GVL_IO.bControlLocalSwitch | BOOL | Input | 本地控制 | | |
| GVL_IO.bControlRobotSwitch | BOOL | Input | 机器人控制 | | |
| GVL_IO.qLampRed | BOOL | Output | 红灯 | | |
| GVL_IO.qLampYellow | BOOL | Output | 黄灯 | | |
| GVL_IO.qLampGreen | BOOL | Output | 绿灯 | | |
