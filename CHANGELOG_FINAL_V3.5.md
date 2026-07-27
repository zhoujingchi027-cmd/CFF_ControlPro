> 历史版本记录，已被FINAL V3.7覆盖；不得作为Codex当前实施依据。


# FINAL V3.5更新说明

本版冻结两项最终修正。

## Collision

- 删除Collision IO和枪头Collision字段；
- 使用外部位移传感器实际值进入窗口进行Teach；
- 同时锁存外部位移和Z轴NC位置；
- 多次重复并验证极差；
- Runtime位移距离为主、NC距离为冗余。

## 外围模块

拆分为：

```text
Gun Head Feed
Magazine
Fastener Station
Robot
```

每个模块拥有独立：

```text
GVL
Adapter FB
PROGRAM
Request
Status
Config
State
Alarm
```

新增`PRG_FastenerSupplyCoordinator`，只通过模块Request/Status编排。

供钉站当前只提供10个输入，未提供输出。程序不得编造输出；在输出定义补充前，完整自动供钉和Production Ready保持FALSE。
