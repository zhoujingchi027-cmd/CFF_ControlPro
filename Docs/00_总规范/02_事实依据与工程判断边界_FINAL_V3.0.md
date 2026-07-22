# 事实依据与工程判断边界 V3.0

本文件用于防止Codex把公开资料没有说明的内容写成“EJOT原厂算法”。

## 1. 可作为事实的内容

### EJOWELD Program

公开培训资料明确：

- Program和Step分别保存；
- Program Header包含ID、名称、板厚/公差、元件类型、步骤数、进给速度、开始力、返回模式和返回速度；
- 阶段由第一准则结束；
- 当第一准则为阶段时间或力相关准则时，第二准则必须选择相对位移；
- Joining Point唯一映射Program，并可由机器人选择；
- CFF有四个阶段；
- Test Mode包含灯、运动和送料等功能。

### Kistler 4574A

数据表明确：

- 压缩力测量；
- 力通过内外承载带传入；
- 安装基面需要高硬度、平整和平行；
- 侧向力会影响结果；
- 灵敏度存在实际偏差；
- 有非线性、滞后和重复性指标。

### Beckhoff External Setpoint

参考资料明确：

- External Setpoint可实时给定轨迹；
- Enable时初值不连续可能造成震动或失控；
- 速度曲线必须平滑；
- 切回标准位置控制需要正确停止和模式切换时序；
- 实际API和驱动模式必须以安装版本为准。

### ADS

资料明确：

- ADS.NET V4与V6 API存在差异；
- V6使用`AdsClient`、`uint`句柄和`NotificationSettings`；
- Symbolic Mapping必须启用；
- ADS Notification适合通知变量变化；
- 高速采集可使用PLC交替缓存后批量传输；
- 大量通知需考虑Router Memory和上位机回调负载。

## 2. 本项目的工程选择，不应声称为EJOT内部事实

以下属于本项目设计：

- Z轴使用导纳型力PI输出速度；
- External Setpoint使用P/V/A一致轨迹；
- Secondary触发动作可配置；
- Force Decline需要Arm、负变化率和Debounce；
- StepMin作为质量条件；
- Brake与Compression Force Ramp重叠；
- Step4有效保持按RpmStopped+ForceInBand累计；
- MaterialInterfaceObserver只监控；
- TorqueOffset默认关闭；
- CommandId/Ack作为正式WPF命令；
- 曲线采用4096样点双缓冲和分页；
- 三任务架构。

## 3. 必须保留为开放项

- EJOT内部力控制器类型和参数；
- 原厂Secondary精确布尔语义；
- 原厂是否使用TorqueOffset或模型控制；
- 实际AX5000的Torque缩放；
- 实际External Setpoint函数签名；
- 位移传感器型号和PDO；
- 送料与机器人最终接口；
- 量产Program参数。

## 4. 资料冲突处理顺序

```text
实际安装版本的Beckhoff官方文档和库声明
> 原厂硬件数据表
> EJOT培训资料
> 本任务包最终决策
> 历史项目
> 第三方总结和推测
```

如果实际库声明与任务包示例不同：

- 停止相应模块；
- 记录差异；
- 按实际API修订；
- 不编造签名。
