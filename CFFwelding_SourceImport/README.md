# XAE不可用时的源码导入目录

Codex在没有TwinCAT XAE时，将完整对象生成到：

```text
DUT/
GVL/
POU/
FB/
FC/
```

并创建：

```text
XAE_CREATE_AND_IMPORT_CHECKLIST.md
```

不得伪造`.tsproj`、`.plcproj` GUID或构建结果。
