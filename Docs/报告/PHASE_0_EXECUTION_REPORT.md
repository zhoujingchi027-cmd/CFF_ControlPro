# Phase 0 隔离与环境检测执行报告

## 目标

建立独立Git边界，验证固定远端，检测TwinCAT/XAE、Automation Interface、PLC库、External Setpoint接口和NC SAF可检测性，并确认旧工程保持只读。

## 创建文件

- `Docs/报告/ENVIRONMENT_DETECTION.md`
- `Docs/报告/GIT_EXECUTION_REPORT.md`
- `Docs/报告/PHASE_0_EXECUTION_REPORT.md`

## 修改文件

- 无。

## 接口变化

- 无PLC接口变化。
- 未创建TwinCAT Solution、System Project、PLC Project、NC轴或I/O对象。
- 工作分支按用户最新指令使用`codex/cffwelding-greenfield-v3.3`。

## Build证据

- Build不适用：Phase 0尚无可构建的TwinCAT Solution。
- 已执行环境和Git静态检查。
- 不声明编译通过。

## 审查结果

- 唯一Git根目录为`E:\新工艺程序资料\倍福CFF控制`。
- 固定输出文件尚不存在，无文件冲突。
- Remote URL与固定仓库完全一致。
- `main`远端Hash与首次规范Commit一致。
- 工作分支已建立远端跟踪。
- 本机存在TwinCAT `3.1.4024.64`、XAE Shell、Automation Interface、PLC标准模板及所需PLC库。
- 本机库缓存存在External Setpoint Enable/Feed/Disable对象。
- 新工程尚未创建，NC SAF实际周期不可取得，未伪造周期。
- 未执行任何硬件扫描、关联、下载或激活。

## 旧工程只读基线

对指定只读目录中的工程、源码和文档类文件计算SHA-256聚合摘要：

| 目录 | 文件数 | 聚合SHA-256 |
|---|---:|---|
| `CFF_TwinCAT3_Pro` | 142 | `6AC4CAB0DBBB47583E3C698347E2152D5AB9490D65751A24096B27F5162868B8` |
| `CFF_TwinCAT3` | 58 | `D729FAD4B24B7BBDA0791DD9E2B06AC5AA57B33A5B81EDE56EFB7280756C93C9` |
| `FDS_PLC` | 137 | `14EF6B90C8C3DBCA57A7B617A7185042297F82B02B18F09C2A3A8A117472E305` |
| `SPR重庆发货` | 826 | `A796EFE7E0AF057C345F51DD98998AD10D9EC03A78D0CEC9626B6C9F6120FCE8` |
| `GroupMDG` | 1377 | `222DB470C64FAA37527F9BE20F43EF9E599ECA967596F395BF3239027F150B95` |

Phase 0结束前将重复计算并要求摘要完全一致。

## 警告

1. 新工程实际NC SAF周期尚不可检测。
2. 候选库版本尚未经过新工程Build确认。
3. External Setpoint实际工程调用尚未编译验证。
4. 真实硬件未映射，后续生产Ready必须保持`FALSE`。

## TODO

1. Phase 1使用XAE Automation Interface创建空工程并执行真实Build。
2. 后续创建未绑定驱动的NC轴后读取实际NC SAF周期。
3. Phase 7以实际`Tc2_MC2`声明和Build验证External Setpoint调用。

## Git Commit

- Commit：`1cf77561cc09d95e28dabeb531cebee61763b9df`
- Commit消息：`chore(repo): initialize CFFwelding greenfield repository`
- Push：已成功推送至`origin/codex/cffwelding-greenfield-v3.3`。
- 远端复核：远端Hash与上述Commit完全一致。

## 下一风险

Phase 1的主要风险是XAE Automation Interface工程模板、PLC库解析和非交互Build；如XAE自动创建失败，必须转入完整SourceImport分支且不得伪造工程或Build结果。
