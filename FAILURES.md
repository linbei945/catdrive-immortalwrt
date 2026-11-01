# 构建失败经验清单（防复发）

> 本文件记录 CatDrive ImmortalWrt 构建过程中遇到过的全部失败模式。
> **每次构建失败后必须更新此文件，并在下次构建前通读一遍。**

## 一、本地（WSL）构建

| # | 症状 | 根因 | 防复发措施 |
|---|---|---|---|
| L1 | `tools/tar` 构建失败：`you should not run configure as root` | WSL 以 root 运行，GNU tar 的 configure 拒绝 root | 启动编译**必须** `export FORCE_UNSAFE_CONFIGURE=1` |
| L2 | `tools/dwarves` 卡死 1 小时后失败 | 源码在 `fedorapeople.org`（国内不可达），下载子进程挂死 | 预下载 `dwarves-1.31.tar.xz` 放入 `dl/`（Windows 侧 curl 可达），或挂代理 |
| L3 | 后台编译任务静默消失 | `pkill -f "make -j"` 误杀全部后台 make | 杀进程用精确 PID，不用 pkill 模式匹配 |
| L4 | 编译产物/脚本跨调用消失 | WSL `/tmp` 是 tmpfs，wsl.exe 会话结束即清空 | 持久文件一律放 `~/v25122/`、`/mnt/d/` 或 GitHub |
| L5 | 编译日志管道挂起 | 后台 wsl.exe 的 stdout 管道（`| tail`）缓冲问题 | make 输出重定向到文件（`> build.log 2>&1`），不要走管道 |

## 二、云端（GitHub Actions）构建

| # | 症状 | 根因 | 防复发措施 |
|---|---|---|---|
| C1 | 断言 `FAIL: xxx missing` | **feeds 漂移**：`openwrt-25.12` 分支被上游 force-push/大改，包被删（samba4-server/lm-sensors/argon 依赖 wget-any 等） | update 后立即 `git -C feeds/xxx checkout <已验证commit>`（luci=d6167ea0, packages=84bd863），**先 pin 再 install** |
| C2 | `recursive dependency detected!` | 自造元包（wget-any）与主线 uclient-fetch 的 `PROVIDES wget-any` 撞成 kconfig 环 | 加包前先查主线是否已 `PROVIDES`；**不要造重复元包** |
| C3 | defconfig 后部分包静默消失 | 依赖不满足的包被 kconfig 静默剔除（无报错） | defconfig 后**必须断言**关键包（现 8 项），断言失败立即失败，不进编译 |
| C4 | `wget: exited with error 8`（apk 安装失败） | 公共源里没有 ucode 包（官方只内置发布） | 构建时 `CONFIG_PACKAGE_ucode=y` 显式进 world（防 apk3 孤儿清理） |
| C5 | apk 装包后 LuCI 403 | **apk3 孤儿清理**：`apk add` 会删掉依赖声明外的包（ucode 事件） | 所有运行时必需的包都要显式进 world，不留"构建时拖入"的暗包 |
| C6 | `Makefile 'xxx' has a dependency on 'yyy', which does not exist` WARNING | feeds 收集阶段的依赖缺失提示 | 出现时对照清单：**在 25.12.2 feeds 确认存在的包才能进 config**（已验证缺失：gotty/zip/wrtbwmon/luci-app-wrtbwmon/wget-any 元包/lm-sensors*/luci-app-samba4*——*经 pin 后已恢复） |

## 三、网络与 Git 操作

| # | 症状 | 根因 | 防复发措施 |
|---|---|---|---|
| N1 | Windows git push/curl 挂起或 SSL 失败 | 直连 GitHub 的 TLS 间歇性阻断 | 立即切 WSL 侧执行（NAT 路径），反之亦然；fedorapeople 则只有 Windows 通 |
| N2 | `git push` 显示成功但远程未更新 | `timeout 60 git push | tail -1` 的退出码误判（tail 成功≠push 成功） | push 后必须 `git fetch` 比对远程 HEAD 确认 |
| N3 | GitHub 全挂但需要更新远程文件 | git push 不可达 | 走 API：`PUT /repos/../contents/<file>`（token + 文件 sha），自动触发 CI |
| N4 | `sed` 插入含 `\n` 的多行文本破坏 YAML | sed 的 a/append 会把 `\n` 展开为真换行 | 改 YAML 用 Edit 工具或 python，禁止 sed 多行插入 |
| N5 | 会话临时目录被清理 | `C:/Users/PC/WorkBuddy/<会话ID>/` 有生命周期管理 | 仓库与交付物只放 `D:/WorkBuddy/automation-*/` 和 GitHub |

## 四、流程性教训

1. **每次失败先取 CI 日志定位**（jobs API → 失败步骤 → 日志尾部），不猜
2. **config 断言是护栏**：任何新包进清单，必须同步加断言，5 分钟内暴露问题
3. **feeds pin 是复现性的基石**：不 pin 的每次构建都可能在不同的上游状态上
4. **本地与云端配置必须逐字节一致**：修改走同一份脚本/文件，不同步手工改两边
5. **WSL 与 Windows 的网络可达性互补**：一个域不通就换另一侧试，不要死磕

---
*最后更新：2026-11-01（云端 5 轮失败 + 本地 2 轮失败的全量复盘）*
