
# 硬接线IO与外部接口边界 FINAL V3.7

## 1. GVL_IO直接变量

```text
Z_axis
R_axis
nZForceRaw AT %I*
nZDisplacementRaw AT %I*
bModeManualSwitch AT %I*
bModeAutomaticSwitch AT %I*
bModeMaintenanceSwitch AT %I*
bControlLocalSwitch AT %I*
bControlRobotSwitch AT %I*
qLampRed AT %Q*
qLampYellow AT %Q*
qLampGreen AT %Q*
```

以下为内部干净信号，不再直接带AT：

```text
bZHomeSwitch
bZLimitPositiveSwitch
bZLimitNegativeSwitch
```

由`gunBOX_bullIn`经`PRG_IO_Config`赋值。

## 2. 固定Legacy外部接口

```text
robot_to_plc AT %I* : ARRAY[1..20] OF BYTE
plc_to_robot AT %Q* : ARRAY[1..20] OF BYTE

bsensor AT %I* : ST_sensor
bactuaor AT %Q* : ST_actuaor

SMCBOX_bullfOut AT %Q* : ST_USINT
SMCBOX_bullfIn AT %I* : ST_USINT
SMCBOX_portDo AT %Q* : ST_USINT

gunBOX_bullIn AT %I* : ST_USINT
gunBOX_byteIn AT %I* : stGunbox_byteIN
```

## 3. 唯一映射层

```text
PRG_IO_Config
```

模块不得直接访问Legacy外部变量。

## 4. 实际硬件

Codex不执行：

- Profinet配置；
- EtherCAT Scan；
- IO-Link端口配置；
- PDO链接；
- AX5000链接；
- 固定地址配置。

用户后期人工完成。
