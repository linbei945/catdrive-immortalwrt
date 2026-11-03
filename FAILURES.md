# CatDrive ImmortalWrt 编译史与失败复盘

> 本文档记录**每一版镜像的编译方法**与**所有踩过的坑**。
> 规则：每次构建失败 → 先查本文档 → 修完把新坑补进来。下次动手前通读一遍。

---

# 第一部分：版本编年史

## 总览

| 版本 | 时间 | 基线 | 编译方式 | 产物 | 结果 |
|---|---|---|---|---|---|
| V1–V5 | 10-29 ~ 10-31 | 25.12-SNAPSHOT（master 快照 `3682a14`） | 本地 WSL 全量编译 | 78MB img.gz | 两次实机刷写通过 |
| Plan B | 10-31 | 25.12-SNAPSHOT | 镜像 patch（挂载改文件） | 78MB，`696d8f8b...` | 未实机刷（被后续版本取代） |
| 25.12.2 基础版 | 11-01 | 官方 `v25.12.2` | 云端 CI（官方 buildinfo + printf 拼装） | 17.6MB，`c2d2703d...` | 实机刷入 + `apk add kmod-tun` 通过 |
| 25.12.2 全功能版 | 11-01 | 官方 `v25.12.2` | 云端 CI（**config.full** 方案） | 50.4MB，318 包 | U 盘刷入，`crc 0xb938828b` |
| **25.12.2 终版** | 11-02 | 官方 `v25.12.2` | 云端 CI（config.full + luci-compat） | 50.6MB，329 包，`4f128b84...` | 当前发布版 |

---

## V1–V5：SNAPSHOT 基线 + 全塞 kmod（本地编译）

**目标**：先让猫盘跑起 ImmortalWrt，功能尽可能全。

**方法**

```
基线：immortalwrt master 快照（25.12-SNAPSHOT r0-3682a14）
配置：CONFIG_ALL_KMODS=y + 把 1108 个 kmod 全部 sed 成 =y（"全塞"）
分区：CONFIG_TARGET_ROOTFS_PARTSIZE=2048（2G）
定制：catdrive.dts（含 comphy 禁用）+ argon 主题 + 若干 rootfs 文件
产物：78MB ext4-sdcard img.gz（本地 WSL 编译，make -j6）
```

**关键修复（版本存在的意义）**

| 问题 | 现象 | 处置 |
|---|---|---|
| `dme1737` panic | 开机加载 hwmon 驱动立即崩溃 | `modules.d` 从 986 条裁到 **167** 条；`modules-boot.d` 从 138 条裁到 **23** 条 |
| 网口不通 | PHY 时序不对 | DTS 里禁用 comphy（`status = "disabled"`） |
| 分区只有 1G | 装不下应用 | PARTSIZE=2048 |

**验证**：两次实机刷写（`ext4load` 与 U 盘 `fatload` 两种路径），启动约 29 秒，MAC 正确。

**遗留问题**：SNAPSHOT 基线的软件源会滚动失效（`releases/25.12-SNAPSHOT/` 目录不存在），
装插件只能手工传包 → 引出后面"对齐官方 release"的整条路线。

---

## Plan B：同一基线的"干净版"（镜像 patch）

**目标**：分享给他人时，系统里不留常驻脚本。

**方法**：不做全量重编，**挂载现有 img.gz → 改文件 → 重新压缩**（40 秒级）。

```
删除：/usr/bin/catdrive-mkdata（一键挂盘脚本）
删除：/etc/init.d/macfromuboot（常驻 MAC 服务）
新增：/etc/uci-defaults/99-mac-from-uboot（首启读 U-Boot ethaddr，执行后自删）
保留：catdrive-netinit（DHCP 兜底）
```

**产物**：`696d8f8b...`，78MB。

**结论**：方案 B 的运行时形态在这一版定型（MAC 一次性写入 + DHCP 兜底 + 无常驻脚本），
但基线仍是 SNAPSHOT，源不可用的问题未解决。

---

## 25.12.2 基础版：切官方 release 基线（云端 CI 首战）

**目标**：版本号可查、软件源永久可用、官方 kmod 可直接装。

**方法（第一版 workflow）**

```
1. CI 里 git clone --depth 1 --branch v25.12.2
2. 拷 DTS/bootscript/机型片段 + files/
3. cp 官方 config.buildinfo → .config，再 sed PARTSIZE 300→2048
4. 追加约 80 行 printf 装包清单
5. make defconfig → 断言 → make download → make -j → 上传
```

**这一版的失败与修复（6 轮）**

| 轮次 | 失败点 | 根因 | 修复 |
|---|---|---|---|
| 1 | Verify 步骤 `gzip -t` 退出码 2 | 官方 image 生成器在 .img.gz 后附加 sysupgrade 元数据尾巴，`gzip -t` 报 `trailing garbage ignored`，被 `bash -e` 判死（**编译本身 3h08m 是成功的**） | 新增 `strip_trailer.py` 剥尾巴；Verify 改为剥后复验 |
| 2 | `FAIL: argon theme missing` | argon 依赖 `wget-any`，25.12.2 feeds 无此包 → defconfig 静默剔除 | 先试"自造 wget-any 元包" |
| 3 | `recursive dependency detected` | 自造元包 DEPENDS uclient-fetch，而主线 uclient-fetch `PROVIDES @wget-any` → kconfig 成环 | 删掉自造元包（主线本来就提供） |
| 4 | 仍 `argon missing` | 经实证：argon 在**官方 apk 源里现成**，官方设计就是在线安装，不该进构建 | 从构建移除 argon，改设备 `apk add luci-theme-argon`（实测成功 2.4.7） |
| 5 | `FAIL: samba4 missing` / `lm-sensors missing` | 一度误判为"feeds 漂移"、钉死 commit，方向错误 | 用 `tmp/.config-package.in`（构建树依赖表）与设备 `apk search`（官方源）双实证，确认包存在 |
| 6 | `FAIL: wrong PARTSIZE` | python 重建 printf 块时把"非包配置行"（PARTSIZE=2048）整块替换掉了 | 非包配置不进 printf 块，改用 `sed` 在 cp buildinfo 后立即修正 |

**成果**：17.6MB 镜像（不预装 kmod，modules.d 仅 49 条），vermagic 断言通过，
实机刷入后 `apk add kmod-tun && modprobe tun` 成功 → **"不预装 + 官方源在线安装"路线打通**。

**遗留**：基础版功能太少（只有 LuCI + SSH），且 `apk add` 时 apk3 的孤儿清理会删掉 ucode → LuCI 403。

---

## 25.12.2 全功能版：config.full 方案（6~8 轮失败后的转折）

**目标**：开箱即有软路由 + NAS 全套功能（对齐 snail 镜像的功能面）。

**失败历程（这是最黑暗的一段）**

| 轮次 | 失败点 | 根因 |
|---|---|---|
| 1-2 | `luci` / `material` 主题 missing | workflow 现场拼装清单，CI 环境 defconfig 行为与本地不一致 |
| 3-4 | `samba4 missing` / `lm-sensors missing` | 同上；清单里有的包在 CI 的 kconfig 符号表里找不到 |
| 5 | `FAIL: wrong PARTSIZE` | 脚本批量替换时误删非包配置 |
| 6 | 断言全过但本地 config 被多次 make 重算弄丢功能包（bash/curl/samba4 变 `is not set`） | `.config` 是易失品，多次构建之间被覆盖 |

**转折点**：放弃"CI 现场拼装配置"，改为 **把本地已验证的完整 config 入库**。

```
# 关键改动（commit a099b21）
- 删除 workflow 里 78 行 printf 拼装 + buildinfo cp + sed
+ cp ../catdrive-25122/config.full .config
+ make defconfig
+ 25 项断言
```

**结果**：CI 首次一次通过（run a099b21），产物 50.4MB / 318 包，
U 盘刷入设备：`fatload 52861452 字节精确匹配` → `gzwrite 2183266304 字节, crc 0xb938828b` → 启动正常。

**为什么这个方案是对的**：

```
本地验证过的 config = 一份 2395 行的确定性文件
CI 只是"照着这份文件编"，不再参与"决定装什么"
→ 复现性从"依赖 CI 环境"变成"依赖仓库里的文件"
```

---

## 25.12.2 终版：内置 luci-compat + lua

**目标**：任何旧式 Lua 插件（OpenClash 等）装完菜单直接可见，别人不用再问"为什么没菜单"。

**方法**：本地增量编译（不重编内核与全部包）

```
1. config 追加 CONFIG_PACKAGE_luci-compat=y / CONFIG_PACKAGE_lua=y
2. make defconfig + 断言（22 项本地断言全绿）
3. make -j6  → 31 分钟（只编新增的两个包及其依赖 + 重打包镜像）
4. strip_trailer.py 剥尾巴 → gzip -t → sha256
5. 上传 Release（删旧 asset → POST uploads）
```

**验证**：vermagic 仍为 `846049ff...`（新增包不影响内核配置）；apk db 329 包；
`luci-compat` / `lua` / `ucode` / `samba4-server` 等 28 项逐项确认。

**随后云端同配置重编一次（commit aa03e90）**，产物 50.6MB / 53104671 字节 /
sha256 `4f128b84...` — 这是当前 Release 上的文件（云端产物为准，符合"通用性优先"原则）。

**产物哈希对照**

| 来源 | 大小 | sha256 |
|---|---|---|
| 本地增量编译 | 53,100,128 | `163591147e0e0afe0e84230dab5192ce563b77188b8e4191e9ffc5425c0aa8b4` |
| 云端重编（现行） | 53,104,671 | `4f128b8492c010dbb3418939dcc5756018c6f835ce538959e2de26439c616f2a` |

---

# 第二部分：失败模式索引

## L — 本地（Linux/WSL）构建

| # | 症状 | 根因 | 防复发 |
|---|---|---|---|
| L1 | `tools/tar` 失败：`you should not run configure as root` | root 下 GNU tar configure 拒绝 | 必须 `export FORCE_UNSAFE_CONFIGURE=1` |
| L2 | `tools/dwarves` 卡死 1 小时 | 源码在 `fedorapeople.org`（国内不可达），下载子进程挂死 | 预下载 `dwarves-1.31.tar.xz` 放 `dl/`（Windows 侧可达），哈希需与 Makefile `PKG_HASH` 一致 |
| L3 | 后台编译任务静默消失 | `pkill -f "make -j"` 误杀 | 杀进程用精确 PID |
| L4 | 产物/脚本跨调用消失 | WSL `/tmp` 是 tmpfs，会话结束即清空 | 持久文件放 `~/`、`/mnt/d/` 或 GitHub |
| L5 | 后台日志管道挂起 | `wsl.exe ...` 接 `tail` 时的缓冲问题 | make 输出重定向到文件，不走管道 |
| L6 | 本地 config 少了一大半功能包 | 多次 make 之间 `.config` 被重算覆盖 | 每次编译前跑完整断言（本地 22 项），失败即重建 |

## C — 云端（GitHub Actions）

| # | 症状 | 根因 | 防复发 |
|---|---|---|---|
| C1 | 断言 `xxx missing` | CI 现场拼装配置，与本地环境行为不一致 | **配置随仓库走**（config.full），不在 CI 拼装 |
| C2 | `recursive dependency detected` | 自造元包与主线 `PROVIDES` 撞环 | 官方已有的东西不自造 |
| C3 | defconfig 后包静默消失 | 依赖不满足被 kconfig 静默剔除（无报错） | defconfig 后必须断言关键包，失败即停 |
| C4 | `gzip -t` 退出码 2 判死整个 run | 官方 image 尾部有 sysupgrade 元数据 | `strip_trailer.py` 先剥再验 |
| C5 | 编译 3 小时后才失败 | 没有早期断言 | 断言放在 defconfig 之后、编译之前 |
| C6 | `sha256sums` 与实际文件不符 | CI 的校验清单在"剥尾巴之前"生成 | 文档里固定记录实际哈希；或剥完重算 |

## P — 脚本批量修改配置

| # | 症状 | 根因 | 防复发 |
|---|---|---|---|
| P1 | `FAIL: wrong PARTSIZE` | python 重建 printf 块时把非包配置行整块替换掉 | 改完 `git diff` 核对；非包配置用 `sed` 单独处理 |
| P2 | 配置里功能包消失 | 同一符号两处定义（buildinfo 300 vs printf 2048），defconfig 结果不确定 | 单一来源：一处定义，不叠加 |

## O — 官方符号与清单的关系

| # | 症状 | 根因 | 防复发 |
|---|---|---|---|
| O1 | argon 连续 5 轮被剔 | argon 依赖 `wget-any`，主线只提供 `PROVIDES @wget-any`（带 @ 虚拟包语法） | 官方源有的包走**在线安装**，不进构建 |
| O2 | 自造元包引发 kconfig 环 | 元包 DEPENDS 与主线 PROVIDES 成环 | 同上 |
| O3 | 把"官方源有包"误判成"feeds 有包定义" | apk 源（release 产物）与 git feeds（滚动源码）是两个层面 | 查存在性用：设备 `apk search` 或本地 `tmp/.config-package.in` |
| O4 | 钉死旧 commit 反而错 | 上游更新后钉死 = 用过期状态 | 以官方最新为准；官方删了什么就从清单去掉什么 |

## N — 网络与 Git

| # | 症状 | 根因 | 防复发 |
|---|---|---|---|
| N1 | Windows 侧 push/curl 挂起或 SSL 失败 | GitHub TLS 间歇阻断 | 换另一侧（Windows/WSL）执行；`uploads.github.com` 常只有一侧可达 |
| N2 | push 显示成功但远程未更新 | `git push` 接 `tail -1` 的退出码误判（tail 成功 ≠ push 成功） | push 后必须 `git fetch` 比对远程 HEAD |
| N3 | git 全挂但要改远程文件 | push 不可达 | 走 API `PUT /contents/<file>`（token + sha） |
| N4 | `sed` 多行插入破坏 YAML | sed 的 `\n` 被展开成真换行 | 改 YAML 用编辑器/python，禁 sed 多行 |
| N5 | 会话临时目录被清理 | 平台有生命周期管理 | 仓库与交付物只放持久目录 + GitHub |

## S — 刷机

| # | 症状 | 根因 | 防复发 |
|---|---|---|---|
| S1 | 系统内 dd 刷机后 p2 残缺、SSH 认证失效 | **源镜像放在被写入的 p2 分区上**，gunzip 读到半新半旧数据 | 源文件放 `/tmp`（tmpfs）或从外部流式写入 |
| S2 | 校验工具报 `No error information` | `drop_caches` 后程序要从被覆写的 rootfs 加载动态库 | 校验在 drop_caches 之前完成，或用静态二进制/外部管道 |
| S3 | `fatload` 字节数与镜像不符却继续刷 | 未核对字节数 | `fatload` 后必须比对 `bytes read` 与镜像大小 |
| S4 | 串口传二进制失败（收到空文件） | 控制字符（0x03）触发行规程信号，打断接收 | 别用串口传二进制；走 U 盘/SSH/HTTP |
| S5 | 设备拿到被污染 DNS 答案 | 旧缓存或客户端自带 DoH | 清客户端 DNS 缓存；确认解析返回 198.18.x.x（fake-ip） |

## R — 运行期（镜像装完之后的坑）

| # | 症状 | 根因 | 防复发 |
|---|---|---|---|
| R1 | LuCI 403，后台进不去 | apk3 **孤儿清理**：`apk add` 会删掉依赖声明外的包（ucode 事件） | 运行时必需包显式进 world（已内置 ucode/luci-compat/lua） |
| R2 | 装了应用但菜单没有 | 旧式 Lua 应用需 `luci-compat`；菜单在登录会话时生成 | 镜像已内置；必要时 `apk add luci-compat` + 重启 rpcd/uhttpd + 重登 |
| R3 | OpenClash 启动即停，日志 `LAN IP Address Get Error` | DHCP 模式下配置里无 `network.lan.ipaddr`，OpenClash 只读配置 | 指定 `interface_name=br-lan`（已写入 FAQ） |
| R4 | 一切正常但代理不通 | `proxy_mode=global`，流量走 GLOBAL 组（默认 DIRECT） | 保持 `proxy_mode=rule` |
| R5 | 订阅导入后启动成功但没网 | 订阅是"仅节点"格式：无策略组/规则/DNS 上游 | 补齐 `proxy-groups` + `rules` + 国内 nameserver |
| R6 | base-files "升级"按钮点了没反应 | apk3 的 `apk upgrade <pkg>` 对该包空转，需 `apk add -u` | 不要在线升 base-files（会覆盖方案 B 配置）；要更新整盘重刷 |

---

# 第三部分：方法论（比具体条目更重要）

1. **失败先取证，再动手**：拉 CI 日志 → 找失败步骤 → 读日志尾部，禁止"猜一个改一个"
2. **配置是准入门槛**：断言不通过不许编译；新增包必须同步加断言
3. **单一事实来源**：同一配置只在一处定义（config.full），不叠 buildinfo + printf
4. **以官方为准**：官方源里有的包走在线安装；官方删的包从清单去掉；不钉死旧 commit
5. **批量修改必 diff**：脚本改配置后 `git diff` 逐行核对，非包配置单独处理
6. **双线并行**：本地起编的瞬间推云端，互不等待；**冲突以云端为准**（云端 = 人人可复现）
7. **哈希与字节数必须核对**：镜像上传前后、fatload 后、gzwrite 后，三个环节都有值可比
8. **刷机不做即兴操作**：只用验证过的脚本，源数据不放在目标分区上
9. **网络两侧互补**：Windows 与 WSL 的 GitHub 可达性不同，一个不通立刻换另一个
10. **踩过的坑写下来**：本文档存在的唯一意义是让同一个人不踩第二次、让其他人一次成功

---

# 附录：环境类事故（非镜像编译，但影响工具链）

## A1. WSL / Docker 卸载（2026-11-03）

用户要让 MuMu 模拟器可用，需彻底移除 WSL2/Docker 的虚拟化占用。

| 步骤 | 命令/动作 | 结果 |
|---|---|---|
| 停进程 | 结束 docker 相关进程 + `wsl --shutdown` | — |
| 卸 Docker | `Docker Desktop Installer.exe uninstall --quiet` | 退出码 0 |
| 注销发行版 | `wsl --unregister ubuntu-build` / `docker-desktop` | 列表为空 |
| 删数据 | `D:\WSL`（122.5GB）、`%LOCALAPPDATA%\Docker`（5.5GB） | D 盘 77→200GB 可用 |
| 卸组件 | `msiexec /X{2D92E6AF-...}`（WSL MSI） | 需管理员 |
| 关功能 | dism 关 Hyper-V-All / VirtualMachinePlatform / HypervisorPlatform / Subsystem-Linux；`bcdedit /set hypervisorlaunchtype off` | 重启后 `HypervisorPresent=False` |

**教训**

- 批处理脚本必须 **纯 ASCII + CRLF**；含中文会被 cmd 按 GBK 解析拆行，报一堆"不是内部或外部命令"
- 删除 >5GB 的目录可能被安全删除机制拦下，需先停进程或逐文件删
- 关闭虚拟化后 **WSL/Docker 永久不可用**，本项目因此改为纯云端编译

## A2. MuMu 安装报错码 10（2026-11-03）

**根因**：旧版 MuMu 12 的 VMM 关系记录文件

```
C:\Program Files\MuMuVMMVbox\Relationships\*.json
  { "SourcePath": "...MuMuVMMVbox\\...\\VAddressDevice.dll",
    "TargetPath": "D:\\Program Files (x86)\\Netease\\MuMu Player 12\\nx_device\\12.0\\device\\VaddressDevice.dll" }
```

新版安装器启动时"回滚旧引擎"，按这条记录解析路径 → 与期望路径不符 → `PrepareEngineUninstallRollbackBoundary failed, error=10`。

**定位方法**（可复用）：读安装日志
`%LOCALAPPDATA%\Temp\MuMuPlayer\mumu15\mumu15-engine-setup-install_prepare.log`，
里面会写明"候选路径 vs 期望路径"，按提示清理对应残留即可。

**解法**：清 `MuMuVMMVbox` + 服务 `MuMuVMMDrv`/`MuMuNxSup` + 驱动 `MuMuVMMNetLwf.sys` + 旧 AppData/注册表 → 重启 → 重装成功（3.5GB）。

**注意**：这不是虚拟化问题。判断依据是 `HypervisorPresent` 与 `VirtualizationFirmwareEnabled` 均为正常值。

---

*最后更新：2026-11-03（按版本编年史重写 + 补 S/R 类失败模式 + 环境类附录）*
