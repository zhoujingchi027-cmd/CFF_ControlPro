
# 位移碰撞点与外围模块解耦 FINAL V3.7

## 1. Collision最终规则

碰撞点参考不使用IO。

使用：

```text
外部位移实际值进入标定窗口
→ 锁存外部位移
→ 同步锁存Z轴NC位置
→ 多次重复验证
```

新增：

```text
FB_CollisionDisplacementTeach
ST_CollisionDisplacementTeachConfig
ST_CollisionDisplacementCalibration
```

运行时：

```text
CollisionDistanceSensor
CollisionDistanceAxis
CollisionDistanceMismatch
```

外部位移距离为主，NC距离为冗余。

## 2. 外围模块

```text
Gun Head Feed
Magazine
Fastener Station
Robot
```

通讯：

```text
Gun Head Feed：EtherCAT
Magazine：EtherCAT
Fastener Station：EtherCAT
Robot：Profinet
```

## 3. Gun Head Feed

输入：

```text
CylinderDetection1
CylinderDetection2
FastenerPassDetected
```

输出：

```text
DetectionCylinderExtend
DetectionCylinderRetract
```

## 4. Magazine

输入：

```text
ThreePositionCylinderExtended
ThreePositionCylinderRetracted
ThreePositionCylinderFastenerDetected
FullCheckCylinderAExtended
FullCheckCylinderARetracted
FullCheckCylinderBExtended
FullCheckCylinderBRetracted
MagazineDoorDetected
```

输出：

```text
ThreePositionCylinderExtend
ThreePositionCylinderRetract
FullCheckCylinderAValve
FullCheckCylinderBValve
FeedAirBlow
```

## 5. Fastener Station

输入：

```text
PullPinCylinderExtended
PullPinCylinderRetracted
TrackFastenerDetected
OutletFastenerDetected
TrayMaterialDetected
ColumnAFastenerPassDetected
ColumnBFastenerPassDetected
BinDoorCylinderExtended
BinDoorCylinderRetracted
BinDoorDockingDetected
```

输出：

```text
PullPinCylinderValve
ReducedPressureFeedAir
NormalPressureFeedAir
VibratoryBowlRun
TripleAirBlow
TrackHeadAirBlow
BinDoorCylinderValve
```

## 6. 两路核心握手

```text
bFastenerReadyToSend
bReadyToReceive
```

传送条件：

```text
bFastenerReadyToSend AND bReadyToReceive
```

只有上游模块可以启动自己的发送动作。

## 7. 路径

### Magazine

```text
Fastener Station
→ Magazine
→ Gun Head Feed
→ Gun Head
```

### Direct Blow

```text
Fastener Station
→ Gun Head Feed
→ Gun Head
```

## 8. 高内聚低耦合

每模块有：

```text
Physical Input/Output
Request/Status
Config
State
PROGRAM
Actions
Cylinder/Air FB instances
Alarm
```

Coordinator只路由路径和握手。

模块自动流程由用户后续人工编写。

## 9. IO_Config

外部接口只由`PRG_IO_Config`映射到内部模块接口。

模块不访问原始总线变量。

详细见：

```text
Docs/01_架构/08_IO_Config模块PROGRAM与Action骨架_FINAL_V3.7.md
```
