
# 通讯与硬件人工映射清单

## Robot Profinet

- [ ] 确认PLC为Controller还是Device
- [ ] 导入/选择正确GSDML
- [ ] 确认过程数据长度
- [ ] 确认BOOL/UINT/UDINT布局和字节序
- [ ] 映射ST_RobotProfinetInput
- [ ] 映射ST_RobotProfinetOutput
- [ ] 验证CommandSequence/Ack
- [ ] 验证Heartbeat
- [ ] 验证JoiningPoint
- [ ] 验证Start/Stop/Init/Reset

## Feeder EtherCAT

- [ ] Scan阀岛
- [ ] 确认ESI/PDO
- [ ] 确认实际为高层子系统PDO还是底层阀位PDO
- [ ] 映射ST_FeederEtherCATInput
- [ ] 映射ST_FeederEtherCATOutput
- [ ] 验证弹夹送料
- [ ] 验证直吹送料
- [ ] 验证FeedComplete/Jam/Fault
- [ ] 验证CommandSequence

## Gun Head EtherCAT

- [ ] Scan枪头模块
- [ ] 确认ESI/PDO
- [ ] 映射ST_GunHeadEtherCATInput
- [ ] 映射ST_GunHeadEtherCATOutput
- [ ] 验证侦钉气缸伸出/缩回
- [ ] 验证无钉/单钉/多钉
- [ ] 确认Collision Reference是否存在
- [ ] 验证Fault/Ready/Sequence

## Direct IO

- [ ] 力Raw
- [ ] 位移Raw
- [ ] Z Home
- [ ] Z正限位
- [ ] Z负限位
- [ ] Manual/Auto/Maintenance
- [ ] Local/Robot
- [ ] Red/Yellow/Green Lamp
