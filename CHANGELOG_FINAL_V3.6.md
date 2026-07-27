> 历史版本记录，已被FINAL V3.7覆盖；不得作为Codex当前实施依据。


# FINAL V3.6更新说明

新增：

1. GVL_ExternalIO与GVL_ModuleInterface分层；
2. PRG_IO_Config统一映射外部接口和内部模块变量；
3. PRG_MainTask或等效输入前置/输出后置调度；
4. 固定两路核心握手：
   - bFastenerReadyToSend
   - bReadyToReceive
5. Magazine和Direct Blow路径；
6. PRG_FastenerTransportCoordinator；
7. 双电控、单电控、吹气通用FB；
8. 各模块PROGRAM Actions骨架；
9. Maintenance Hold-to-Run；
10. 模块自动Action由用户人工编写，Codex不得编造；
11. 供钉站7个输出变量命名正式冻结；
12. Robot 20字节布局未知时不解码。
