
# FINAL V3.7更新说明

1. 按用户截图冻结Legacy外部变量名和AT占位。
2. 新增ST_sensor、ST_actuaor、DUT_USINT、ST_USINT、stGunbox_byteIN。
3. PRG_IO_Config成为Legacy外部过程映像唯一读写者。
4. Z Home/正负限位改由gunBOX_bullIn经IO_Config赋值。
5. bit/byte映射未确认前Ready保持FALSE。
6. 统一使用新版FB_Actuator。
7. 单控/双控通过ST_ActuatorConfig.bDoubleSolenoid切换。
8. 不复制旧FB_Actuator的全局依赖、HMI按钮、输入自修改和时间模拟。
9. 实例化枪头1个、弹夹3个、供钉站2个气缸。
10. Maintenance点动统一经过模块PROGRAM和FB_Actuator。
