
# FINAL V3.3补充说明

本版在V3.1基础上增加确定的GitHub仓库与Codex Git执行规则。

固定仓库：

```text
https://github.com/zhoujingchi027-cmd/CFF_ControlPro.git
```

新增：

1. 固定Remote名`origin`。
2. 固定实施分支`codex/cffwelding-greenfield-final-v3.3`。
3. 远程访问、Git身份和历史检查。
4. 空仓库与非空仓库分别处理。
5. 禁止覆盖错误Remote。
6. 禁止`allow-unrelated-histories`、Force Push、rebase和破坏性reset/clean。
7. 每个Phase Build后聚焦Commit，并在访问可用时Push。
8. Push失败时保留本地Commit，不伪造成功。
9. 不自动Merge、Tag或Release。
10. 新增`.gitattributes`和`GIT_EXECUTION_REPORT.md`模板。
