
# GitHub仓库、分支、Commit和Push策略 FINAL V3.7

## 1. 固定GitHub仓库

本项目唯一允许使用的远程仓库：

```text
Repository Web:
https://github.com/zhoujingchi027-cmd/CFF_ControlPro

Repository Clone URL:
https://github.com/zhoujingchi027-cmd/CFF_ControlPro.git

Repository Full Name:
zhoujingchi027-cmd/CFF_ControlPro

Remote Name:
origin
```

截至任务包生成时，该仓库已经通过当前连接的GitHub账户验证：

```text
可访问：是
可Push：是
Admin权限：是
Visibility：Public
Default Branch：main
Repository Size：0
状态：空仓库
```

Codex仍必须在本机执行`git ls-remote`复核，因为本机Git认证状态与ChatGPT连接器认证状态可能不同。

## 2. 本地目录与仓库名

本地目录保持：

```text
倍福CFF控制
```

远程仓库名为：

```text
CFF_ControlPro
```

两者名称不同是正常的。

禁止在`倍福CFF控制`内部再创建一层`CFF_ControlPro`目录。

## 3. 本机访问检查

第一次Commit或Push前执行：

```bash
git --version
git config --get user.name
git config --get user.email
git remote -v
git ls-remote https://github.com/zhoujingchi027-cmd/CFF_ControlPro.git
```

当前仓库为空时：

```text
git ls-remote执行成功
但无分支/Tag输出
```

属于正常情况。

如果`user.name`或`user.email`为空：

```text
暂停Commit
向用户请求Git提交身份
不得编造姓名或邮箱
```

## 4. HTTPS认证与人工输入

允许用户在Push时人工完成认证。

推荐顺序：

```text
1. Git Credential Manager浏览器登录
2. GitHub CLI: gh auth login
3. HTTPS命令行用户名 + Personal Access Token
```

注意：

```text
GitHub账户登录密码不能用于HTTPS Git Push。
```

如果终端显示“Password”：

```text
应输入Personal Access Token
而不是GitHub账户密码
```

Codex必须：

- 暂停并提示用户完成人工认证；
- 不读取、不记录、不回显用户凭据；
- 不把PAT写入Remote URL；
- 不把凭据写入脚本、文档、环境文件或Git历史；
- 认证完成后再继续执行原Push命令。

如果当前执行环境不支持交互式认证：

```text
停止Push
保留本地Commit
输出用户需要手工执行的命令
不得伪造Push成功
```

## 5. 空仓库初始化流程

由于该仓库当前为空，在`倍福CFF控制`目录执行：

```bash
git init -b main
git remote add origin https://github.com/zhoujingchi027-cmd/CFF_ControlPro.git
git add .
git commit -m "docs: add final CFFwelding project specification"
git push -u origin main
```

Push首次`main`成功后，创建实施分支：

```bash
git switch -c codex/cffwelding-greenfield-final-v3.3
git push -u origin codex/cffwelding-greenfield-final-v3.3
```

后续所有TwinCAT实施代码都提交到：

```text
codex/cffwelding-greenfield-final-v3.3
```

除首次建立空仓库`main`外，不直接在`main`上实施PLC代码。

## 6. 已有本地Git仓库时

检查：

```bash
git rev-parse --show-toplevel
git remote -v
git branch --show-current
```

要求：

```text
Git根目录 = 当前“倍福CFF控制”
origin = https://github.com/zhoujingchi027-cmd/CFF_ControlPro.git
```

### origin不存在

```bash
git remote add origin https://github.com/zhoujingchi027-cmd/CFF_ControlPro.git
```

### origin指向其他仓库

立即停止。

禁止自动执行：

```bash
git remote set-url origin ...
```

除非用户明确授权替换现有Remote。

## 7. 当前仓库为空的复核规则

在首次Push前再次执行：

```bash
git ls-remote origin
```

如果命令成功且没有输出：

```text
远程仍为空，可以执行首次main Push
```

如果已经出现远程引用：

```text
停止首次空仓库流程
git fetch --prune origin
检测实际默认分支和历史
不得Force Push
```

## 8. 工作分支

固定实施分支：

```text
codex/cffwelding-greenfield-final-v3.3
```

Codex不得改用其他仓库或其他实施分支，除非用户明确要求。

## 9. 每Phase Commit

每个Phase必须：

```text
Build或静态检查
→ git status --short
→ git diff --check
→ git diff --stat
→ Commit
→ Push工作分支
```

建议Commit消息：

| Phase | Commit消息 |
|---|---|
| 0 | `chore(repo): initialize CFFwelding greenfield repository` |
| 1 | `build(twincat): create empty CFFwelding solution` |
| 2 | `feat(plc): add task model and program skeletons` |
| 3 | `feat(plc): add DUT GVL and internal interfaces` |
| 4 | `feat(plc): add reusable functions and utility blocks` |
| 5 | `feat(sensor): add force displacement and collision interfaces` |
| 6 | `feat(motion): add NC axis adapters and command ownership` |
| 7 | `feat(motion): add external setpoint lifecycle` |
| 8 | `feat(control): add Z force admittance controller` |
| 9 | `feat(process): add contact and proceeding criteria` |
| 10 | `feat(process): add CFF four-stage sequence` |
| 11 | `feat(trace): add torque energy monitoring and curve buffers` |
| 12 | `feat(main): add machine modes commands and maintenance` |
| 13 | `feat(peripheral): add program feeder robot and alarms` |
| 14 | `feat(ads): add versioned HMI ADS contract` |
| 15 | `docs: finalize build commissioning and handoff reports` |

## 10. Push命令

首次推送工作分支：

```bash
git push -u origin codex/cffwelding-greenfield-final-v3.3
```

后续：

```bash
git push origin codex/cffwelding-greenfield-final-v3.3
```

Push前：

```bash
git fetch --prune origin
git status --short
git log --oneline --decorate -n 10
```

工作树必须干净。

## 11. 保护规则

禁止：

```bash
git push --force
git push --force-with-lease
git reset --hard
git clean -fdx
git rebase
git commit --amend
git checkout .
git restore .
git pull --rebase
```

除非用户在当前会话中明确批准具体命令。

不得：

- 自动Merge；
- 自动删除分支；
- 自动Tag；
- 自动Release；
- 重写已Push历史；
- 提交PAT、密码或Credential；
- 提交TwinCAT缓存、构建目录或无关大文件。

## 12. Push失败

如果Push因认证或网络失败：

```text
保留本地Commit
不循环重试
不修改Remote URL
不切换其他仓库
记录精确错误
输出手工Push命令
```

用户完成认证后可以继续：

```bash
git push -u origin codex/cffwelding-greenfield-final-v3.3
```

## 13. Git报告

必须创建：

```text
Docs/报告/GIT_EXECUTION_REPORT.md
```

记录：

- Repository URL；
- 可访问性；
- Git身份；
- 默认分支；
- 工作分支；
- 各Phase Commit Hash；
- Build状态；
- Push状态；
- 人工认证发生时间；
- 未Push Commit；
- 最终工作树；
- 旧工程无修改证据。

不得记录任何凭据内容。

## 14. 完成条件

- [ ] Remote严格等于`https://github.com/zhoujingchi027-cmd/CFF_ControlPro.git`。
- [ ] 首次规范已Push到`main`，或有准确失败报告。
- [ ] 实施分支为`codex/cffwelding-greenfield-final-v3.3`。
- [ ] 每个Phase有Build/检查和Commit。
- [ ] 远程可用时每个Phase已Push。
- [ ] 未使用Force Push。
- [ ] 未记录任何认证秘密。
- [ ] 已生成Git执行报告。
