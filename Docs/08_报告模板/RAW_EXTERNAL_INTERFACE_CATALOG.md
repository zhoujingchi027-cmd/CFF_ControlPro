
# Legacy外部接口目录

| 外部符号 | 类型 | 方向 | 注释/信号范围 | PRG_IO_Config Action | 人工确认 |
|---|---|---|---|---|---|
| robot_to_plc | ARRAY[1..20] OF BYTE | Input | Robot Profinet | ACT_ReadRobotRaw | |
| plc_to_robot | ARRAY[1..20] OF BYTE | Output | Robot Profinet | ACT_WriteRobotRaw | |
| bsensor | ST_sensor | Input | 供钉站基础输入 | ACT_ReadStationSensorStruct | |
| bactuaor | ST_actuaor | Output | 枪头/弹夹/供钉站集中输出 | ACT_WriteActuatorStruct | |
| SMCBOX_bullfOut | ST_USINT | Output | 仓门气缸 | ACT_WriteSmcBoxOutputs | |
| SMCBOX_bullfIn | ST_USINT | Input | 立柱/仓门反馈 | ACT_ReadSmcBoxBits | |
| SMCBOX_portDo | ST_USINT | Output | 振动盘 | ACT_WriteSmcBoxOutputs | |
| gunBOX_bullIn | ST_USINT | Input | Z限位/Home及待确认bit | ACT_ReadGunBoxBoolBits | |
| gunBOX_byteIn | stGunbox_byteIN | Input | 枪头/弹夹字节输入 | ACT_ReadGunBoxByteInputs | |
