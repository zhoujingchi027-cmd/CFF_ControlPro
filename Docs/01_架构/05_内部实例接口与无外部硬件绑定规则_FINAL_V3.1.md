
# 内部实例接口与无外部硬件绑定规则 FINAL V3.1

## 1. 本轮交付边界

本轮Codex任务必须完成：

```text
PLC程序对象
DUT/GVL
PROGRAM/FB/FC
FB实例
内部命令和状态接口
NC轴程序接口
ADS接口
编译或可导入源码
```

本轮Codex任务不得完成：

```text
扫描EtherCAT设备
扫描Box/Terminal
扫描AX5000电机或编码器
关联真实驱动
关联真实PDO
关联IO-Link设备
写入真实I/O地址
下载或激活真实硬件配置
```

外部硬件由用户以后在TwinCAT XAE中执行Scan，并人工完成关联。

## 2. 内部关联与外部关联的边界

### 允许的内部关联

如果XAE环境支持且无需扫描硬件，可以创建：

```text
NC轴对象：Z_Axis_NC
NC轴对象：R_Axis_NC

PLC变量：
GVL_IO.Z_axis : AXIS_REF
GVL_IO.R_axis : AXIS_REF
```

允许建立：

```text
PLC AXIS_REF
↔ 对应NC轴对象
```

这是PLC与NC之间的内部程序关联。

### 禁止的外部关联

不得建立：

```text
Z_Axis_NC ↔ AX5000驱动/电机/编码器
R_Axis_NC ↔ AX5000驱动/电机/编码器
PLC变量 ↔ EP3174 PDO
PLC变量 ↔ IO-Link PDO
PLC变量 ↔ 机器人/送料/夹具物理PDO
PLC变量 ↔ 任意EtherCAT Terminal/Box
```

如果环境不允许无驱动创建NC轴，则只创建`AXIS_REF`、轴Adapter和人工配置清单，不得创建虚拟驱动。

## 3. PLC侧硬件占位接口

`GVL_IO`必须保留真实接口语义，但不绑定外部设备。

优先使用：

```pascal
AT %I*
AT %Q*
```

作为PLC过程映像占位。

如果当前TwinCAT版本或对象格式不允许某类通配地址，则使用普通PLC变量，并在变量前写：

```pascal
(* TODO_HW_MAP：用户扫描硬件后，将该变量链接到实际PDO。 *)
```

禁止为了让程序进入Ready而写入模拟值。

未绑定时：

```text
力传感器有效 = FALSE
位移传感器有效 = FALSE
硬件绑定完成 = FALSE
轴驱动可用 = FALSE
生产Start权限 = FALSE
```

程序可以编译，但不得假装设备可运行。

## 4. 硬件绑定状态

增加：

```pascal
TYPE ST_HardwareBindingStatus :
STRUCT
    (* Z轴PLC引用已与NC轴对象建立内部关联。 *)
    bZAxisNcAssigned : BOOL;

    (* R轴PLC引用已与NC轴对象建立内部关联。 *)
    bRAxisNcAssigned : BOOL;

    (* Z轴NC轴尚未关联实际驱动时保持FALSE。 *)
    bZAxisDriveLinked : BOOL;

    (* R轴NC轴尚未关联实际驱动时保持FALSE。 *)
    bRAxisDriveLinked : BOOL;

    (* EP3174力通道已经由用户人工映射。 *)
    bForceInputMapped : BOOL;

    (* 外部位移传感器已经由用户人工映射。 *)
    bDisplacementInputMapped : BOOL;

    (* Collision Reference Sensor已经由用户人工映射。 *)
    bCollisionInputMapped : BOOL;

    (* 外围数字量和IO-Link映射已经完成。 *)
    bPeripheralIoMapped : BOOL;

    (* 全部生产所需硬件映射已经人工确认。 *)
    bProductionHardwareBindingComplete : BOOL;
END_STRUCT
END_TYPE
```

这些状态不得由Codex强制为TRUE。

`PRECHECK`和按钮权限必须将：

```text
bProductionHardwareBindingComplete
```

作为生产运行条件之一。

Maintenance中的纯软件诊断页面可以在未绑定硬件时打开，但实际运动、标定和输出测试必须被禁止。

## 5. FB实例规则

每个FB实例必须且只能声明一次。

默认声明位置：

```text
实例由哪个PROGRAM拥有
→ 就声明在该PROGRAM的VAR区
```

只有确需跨PROGRAM共享的服务实例才允许放在专用：

```text
GVL_Instance
```

使用`GVL_Instance`时必须在`INSTANCE_OWNERSHIP_MATRIX.md`中说明原因。

禁止：

- 多个PROGRAM分别实例化同一个轴Adapter；
- 其他PROGRAM直接访问FB内部局部变量；
- 通过隐式全局变量绕过FB接口；
- 同一功能同时存在PROGRAM状态机和FB状态机两个写入者。

## 6. FB公开接口

每个关键FB必须使用清晰的：

```text
VAR_INPUT
VAR_OUTPUT
VAR_IN_OUT
```

关键算法FB建议采用类型化结构：

```text
ST_ZForceControlInput
ST_ZForceControlOutput
ST_ZExtSetpointCommand
ST_ZExtSetpointStatus
ST_ZAxisCommand
ST_ZAxisStatus
ST_RAxisCommand
ST_RAxisStatus
ST_ContactDetectInput
ST_ContactDetectOutput
ST_StepCriterionInput
ST_StepCriterionOutput
ST_CffSequenceCommand
ST_CffSequenceStatus
```

原则：

- 输入由调用者完整赋值；
- 输出由FB唯一写入；
- `VAR_IN_OUT AXIS_REF`只允许在轴Adapter中使用；
- 算法FB不得使用`AXIS_REF`；
- 外部PROGRAM不得访问FB内部变量；
- 状态机结果通过输出结构发布。

## 7. PROGRAM之间的接口

PROGRAM之间不得直接访问彼此的局部变量。

通过以下契约交互：

```text
GVL_Command
GVL_Status
GVL_Process
GVL_Program
GVL_Alarm
ST_FastCommand / ST_FastStatus
ST_CommandMailbox
```

跨任务数据必须使用RequestId/AcceptedId或SequenceStart/End保护。

## 8. Instance中文注释

每个实例声明前必须说明：

```text
实例用途
所属任务
唯一Owner
输入来源
输出去向
Reset/生命周期
```

示例：

```pascal
(* ---------------------------------------------------------
   Z轴External Setpoint执行实例。
   所属任务：Task_CffFast。
   唯一Owner：PRG_FastAxisControl。
   输入：导纳力控最终速度和Z轴命令仲裁结果。
   输出：External生命周期、Busy/Done/Error和轴诊断。
   复位：设备Reset或轴Owner释放时执行。
   --------------------------------------------------------- *)
fbZExtSetpoint : FB_ZAxisExtSetpointAdapter;
```

## 9. 关键步骤中文注释

所有PROGRAM状态和核心FB算法块必须说明：

```text
目的
进入条件
周期动作
正常出口
超时
NOK/Fault反应
```

所有公开变量至少说明：

```text
物理/工艺意义
单位
方向
有效性
写入者
```

不要求对每一条简单赋值重复注释，但接口、状态转换、算法、限幅、报警和硬边界必须解释清楚。

## 10. Codex必须生成的报告

```text
Docs/报告/INSTANCE_OWNERSHIP_MATRIX.md
Docs/报告/INTERNAL_INTERFACE_CATALOG.md
Docs/报告/HARDWARE_MANUAL_BINDING_CHECKLIST.md
```

其中人工绑定清单至少包含：

1. 扫描EtherCAT Master；
2. 扫描AX5000；
3. 创建/确认Z、R实际驱动；
4. 关联NC轴与驱动；
5. 关联PLC `AXIS_REF`与NC轴；
6. 映射EP3174；
7. 映射外部位移；
8. 映射Collision Sensor；
9. 映射模式/控制源开关；
10. 映射三色灯；
11. 映射送料、侦钉、夹具和机器人；
12. 检查过程映像类型和单位；
13. 更新硬件绑定状态；
14. 完成实机标定后才允许生产Ready。

## 11. 验收条件

- [ ] 所有关键变量有中文独立行注释。
- [ ] 所有状态和算法关键步骤有中文块注释。
- [ ] 每个关键FB实例只有一个Owner。
- [ ] 所有FB通过显式Input/Output接口调用。
- [ ] PROGRAM不读取其他PROGRAM局部变量。
- [ ] `GVL_IO`只有占位，不关联真实PDO。
- [ ] Codex未运行任何Scan命令。
- [ ] 未添加实际EtherCAT设备树。
- [ ] NC轴最多只完成PLC↔NC内部关联。
- [ ] NC轴未关联实际驱动/编码器。
- [ ] 未绑定时生产Ready保持FALSE。
- [ ] 已生成完整人工绑定清单。
