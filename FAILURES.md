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

## 五、官方符号 vs 自定义清单（argon 五连败总复盘）

| # | 症状 | 根因 | 防复发措施 |
|---|---|---|---|
| O1 | argon 在 CI 的 defconfig 后反复被剔（5 轮） | argon 的 `LUCI_DEPENDS:=+wget-any`，而主线提供的是 **`PROVIDES:=@wget-any`（带 @ 的虚拟包语法）**——符号不匹配，kconfig 判依赖不满足 | **以官方源实证为准**：设备 `apk search` 查官方源有没有该包，有 = 官方设计就是在线安装，**不进构建** |
| O2 | 自造 wget-any 元包引发 kconfig 递归环 | 元包 DEPENDS uclient-fetch，与主线 uclient-fetch 的 PROVIDES @wget-any 撞环 | 同上：官方源已有的东西不自造 |
| O3 | feeds"漂移"误判 | 官方源（apk）里有包 ≠ git feeds 分支 HEAD 里有包定义——**两者是不同层面**（release 产物 vs 滚动源码） | 查包存在性：① 设备 apk search（官方 release 源实证）② 本地 `tmp/.config-package.in`（构建树依赖表实证），**不要用 feeds git 分支的 index 文件判断** |
| O4 | feeds 钉死旧 commit 是错误方向 | 上游更新后钉死旧版 = 用过时状态，违背通用性 | **以官方最新为准**：官方删了什么就从清单去掉什么，官方源里有的走在线安装 |

**主题策略定稿**：镜像用默认 bootstrap；argon/material 等主题 = 设备 `apk add luci-theme-xxx` 在线装（官方源验证存在且一键装成功）。

---
*2026-11-01 补：argon 五连败复盘（O1-O4）+ 官方源实证方法论*

## 六、脚本批量修改导致配置项丢失

| # | 症状 | 根因 | 防复发措施 |
|---|---|---|---|
| P1 | CI 断言 FAIL: wrong PARTSIZE（buildinfo 300 覆盖了 2048） | 用 python 重建 workflow 的 printf 块时，`keep_lines` 变量计算后**忘了使用**——PARTSIZE=2048/ALL_KMODS 等非 PACKAGE 行被整块替换掉 | **改完配置必须 diff 验证**：`git diff` 确认只改了预期行；PARTSIZE 类"非包配置"不进 printf 块，用 sed 在 cp buildinfo 后立即修正（单条无歧义条目） |
| P2 | 本地 config 被多次 make 重算弄丢功能包（bash/curl/samba4 变 is not set） | buildinfo 的 PARTSIZE=300 与 printf 的 2048 并存时，defconfig 解析结果不确定；且多次 build 之间 .config 被意外覆盖 | .config 是易失品：**每次编译前跑完整断言清单**（本地 22 项 / 云端 8 项），断言失败立即重建，不带病编译 |

**流程定稿**：buildinfo cp 后第一行就是 `sed PARTSIZE 300->2048`；断言清单是编译的唯一准入门槛。

---
*2026-11-01 补：P1-P2 配置丢失复盘*
