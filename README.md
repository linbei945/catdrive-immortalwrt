# CatDrive（小猫盘）ImmortalWrt 固件

群晖 DS120j 硬件（Marvell Armada 3720 / Cortex-A53 / 8GB eMMC）的 ImmortalWrt 构建仓库。
从源码到可刷镜像全程可复现，产物发布在 [Releases](https://github.com/linbei945/catdrive-immortalwrt/releases/tag/catdrive-25122)。

---

## 一、当前版本一览

| 项目 | 值 |
|---|---|
| 系统 | ImmortalWrt **25.12.2**（官方 tag `v25.12.2`，commit `4fc16f2`） |
| 内核 | 6.12.103，vermagic `846049ff0684ff21c8cae8e6f2efc82e`（**与官方 kmods 完全一致**） |
| 机型 | `Device/catdrive`（DTS `armada-3720-catdrive.dts`，含 comphy 禁用修复） |
| rootfs | 2G ext4；eMMC 余量约 6G 未分配 |
| 已装包数 | **329**（apk 数据库实测） |
| 主镜像 | `immortalwrt-25.12.2-mvebu-cortexa53-catdrive-ext4-sdcard.img.gz`<br>53,104,671 字节（50.6MB）<br>sha256 `4f128b8492c010dbb3418939dcc5756018c6f835ce538959e2de26439c616f2a` |
| 编译来源 | GitHub Actions 云端构建（`.github/workflows/build-25122.yml`） |

### 开箱即有

```
后台/SSH      LuCI（bootstrap 主题）· uhttpd · dropbear · rpcd · ucode 全套
旧插件兼容    luci-compat + lua（OpenClash 等 Lua 应用装完菜单直接可见）
NAS 服务      samba4-server · luci-app-samba4 · vsftpd · ntfs-3g · cifsmount
内网工具      ddns-scripts · luci-app-ddns · luci-app-wol · nlbwmon
IPv6 旁路由   odhcp6c · odhcpd-ipv6only
磁盘健康      smartmontools · hdparm · lm-sensors · btrfs-progs · resize2fs
工具集        bash · curl · vim-full · unrar · unzip · xz · bzip2 · ip-full
              bind-dig · iperf3 · httping · iftop · tcpdump · git · screen · lsof · strace
证书/时区     ca-certificates · ca-bundle · openssl-util · zoneinfo-asia
```

### 方案 B 的运行时行为（与官方 OpenWrt 的差异点）

| 项目 | 行为 | 实现 |
|---|---|---|
| MAC | 首次开机从 U-Boot 环境 `ethaddr` 读取（只认 `4c:65:a8:` 前缀），写入配置后脚本自删 | `etc/uci-defaults/99-mac-from-uboot` |
| 网络 | DHCP 客户端优先（换网络环境自动适配）；60 秒无地址兜底 `192.168.1.1` 并开 DHCP 服务；下次开机自动重试 DHCP | `usr/bin/catdrive-netinit`（由 `etc/rc.local` 调用） |
| 主机名/时区 | `catdrive` / `Asia/Shanghai` | `etc/config/system` |
| root 密码 | 无（首次登录请自行设置） | — |

---

## 二、产物

[Releases → catdrive-25122](https://github.com/linbei945/catdrive-immortalwrt/releases/tag/catdrive-25122)：

| 文件 | 说明 |
|---|---|
| `immortalwrt-...-catdrive-ext4-sdcard.img.gz` | **主镜像**，刷这个 |
| `immortalwrt-...-catdrive-squashfs-sdcard.img.gz` | squashfs 变体（本项目不推荐） |
| `immortalwrt-...-catdrive-initramfs-kernel.bin` | 应急内核（内存系统，刷坏时的备选） |
| `flash-image-snail.bin` | snail 修改版 U-Boot；原厂 U-Boot 的机器**必须先刷它** |
| `sha256sums` | 构建期生成的校验清单（见下方说明） |

> **校验说明**：`sha256sums` 由 CI 在"剥离 sysupgrade 尾巴"**之前**生成，与最终上传的文件哈希会不一致。
> 以本 README 上方记录的 sha256（`4f128b84...`）或下载后自算为准。

---

## 三、编译过程（最终版：config.full 方案）

### 1. 设计原则

```
官方源码（零改动内核配置）  +  我们只加三样东西
                              ├─ 机型定义（DTS + bootscript + image 片段）
                              ├─ rootfs 定制文件（files/）
                              └─ 一份完整 config（config.full）
```

**为什么内核配置必须零改动**：vermagic 是内核 `.config` 中所有 `=y`/`=m` 行的 md5。
一旦多一行，哈希就变，官方源里 1010 个 kmod 全部装不上。只加 DTS（不进 config），哈希就能保持不变。

### 2. 目录结构

```
catdrive-25122/
├── config.full                      ★ 完整配置（2395 行，从验证过的构建树导出）
├── dts/armada-3720-catdrive.dts     机型设备树（含 comphy 禁用修复）
├── catdrive.bootscript              U-Boot 启动脚本
├── cortexa53-catdrive.append.mk     机型定义（镜像生成的 image 片段）
├── strip_trailer.py                 剥离 sysupgrade 元数据尾巴（gzwrite 需要纯 gzip 流）
├── official.buildinfo               官方 release 的构建配置（历史方法遗留，当前不用）
├── wget-any/Makefile                历史遗留：曾试图自造的元包，会造成 kconfig 递归环，未使用
└── files/                           rootfs 定制（会被原样拷进镜像）
    ├── etc/config/network           lan=br-lan + dhcp（方案 B 的 DHCP 优先）
    ├── etc/config/system            hostname=catdrive + 时区上海
    ├── etc/fw_env.config            /dev/mtd1 0x0 0x10000（让 fw_printenv 能读 U-Boot 环境）
    ├── etc/rc.local                 调用 netinit
    ├── etc/uci-defaults/99-mac-from-uboot   首启读 ethaddr 写配置，执行后自删
    ├── etc/uci-defaults/99-catdrive-share   首启设置（自删）
    └── usr/bin/catdrive-netinit     DHCP 60 秒兜底逻辑
```

### 3. 云端编译流程（8 步，全自动）

`.github/workflows/build-25122.yml`，push 到 main 或手动触发，**约 3 小时**（4 核 runner）。

| 步骤 | 动作 | 关键点 |
|---|---|---|
| 1 | `actions/checkout` | 取本仓库 |
| 2 | 释放磁盘 + 安装依赖 | build-essential/clang/flex/bison/gawk/gettext/libncurses/libssl/python3-pyelftools… |
| 3 | `git clone --depth 1 --branch v25.12.2 immortalwrt` | **基线锁死官方 tag**，不用 master/SNAPSHOT |
| 4 | 应用 catdrive 集成 | 拷 DTS → `target/linux/mvebu/files/.../marvell/`；拷 bootscript → `target/linux/mvebu/image/`；`cat *.append.mk >> cortexa53.mk`；`cp -a files/. openwrt/files/` |
| 5 | `feeds update -a && feeds install -a && feeds install <显式清单>` | 装 luci-app-samba4 / nlbwmon / wol / ddns / lm-sensors / unrar |
| 6 | `cp ../catdrive-25122/config.full .config && make defconfig` | ★ **直接用入库配置**，不现场拼装 |
| 7 | **29 项断言** | 见下；缺任何一项 5 分钟内失败，不进编译 |
| 8 | `make download -j` → `make -j` → 验证 → 剥尾巴 → 上传 | vermagic 断言 + gzip 校验 + sha256 + 上传 Release |

**第 7 步的断言清单**（任何一项缺失立即 `exit 1`）：

```
CONFIG_ALL_KMODS=y                      全 kmod 编译（官方 release 同款）
CONFIG_TARGET_ROOTFS_PARTSIZE=2048      2G 分区
CONFIG_TARGET_DEVICE_mvebu_cortexa53_DEVICE_catdrive=y   机型被选中
CONFIG_PACKAGE_luci / dropbear / ucode / luci-compat / lua
CONFIG_PACKAGE_samba4-server / luci-app-samba4 / vsftpd / ntfs-3g / unrar
CONFIG_PACKAGE_ddns-scripts / luci-app-ddns / luci-app-wol / nlbwmon
CONFIG_PACKAGE_odhcp6c / odhcpd-ipv6only
CONFIG_PACKAGE_bash / curl / ip-full / btrfs-progs / smartmontools
CONFIG_PACKAGE_lm-sensors / hdparm / uboot-envtools / block-mount
```

**编译后的三道验证**：

```
① vermagic 必须等于 846049ff0684ff21c8cae8e6f2efc82e
② gzip -t 通过（尾巴已被 strip_trailer.py 剥离，否则 gzwrite 会写坏）
③ 只收集 ext4-sdcard（squashfs/initramfs 仅作附带上传）
```

### 4. 本地等价编译（可选）

需要 Linux（Debian/Ubuntu）或任意 x86 Linux 环境；**本项目作者已不再维护本地构建树**，
因为云端产物即最终发布物，且本地环境会破坏"人人可复现"的前提。

```bash
# 依赖：build-essential clang flex bison g++ gawk gcc-multilib gettext \
#       git libncurses-dev libssl-dev python3-setuptools python3-pyelftools \
#       rsync swig unzip zlib1g-dev file wget libelf-dev
git clone --depth 1 --branch v25.12.2 https://github.com/immortalwrt/immortalwrt.git openwrt
cd openwrt

# 应用集成
mkdir -p target/linux/mvebu/files/arch/arm64/boot/dts/marvell
cp ../catdrive-25122/dts/armada-3720-catdrive.dts target/linux/mvebu/files/arch/arm64/boot/dts/marvell/
cp ../catdrive-25122/catdrive.bootscript target/linux/mvebu/image/
cat ../catdrive-25122/cortexa53-catdrive.append.mk >> target/linux/mvebu/image/cortexa53.mk
mkdir -p files && cp -a ../catdrive-25122/files/. files/

# feeds + 配置
./scripts/feeds update -a && ./scripts/feeds install -a
./scripts/feeds install luci-app-samba4 luci-app-nlbwmon luci-app-wol luci-app-ddns lm-sensors unrar
cp ../catdrive-25122/config.full .config
make defconfig

# 断言（与 CI 一致，任一失败就停）
for a in CONFIG_ALL_KMODS=y CONFIG_TARGET_ROOTFS_PARTSIZE=2048 \
         CONFIG_PACKAGE_luci=y CONFIG_PACKAGE_ucode=y CONFIG_PACKAGE_luci-compat=y \
         CONFIG_PACKAGE_samba4-server=y CONFIG_PACKAGE_ddns-scripts=y \
         CONFIG_PACKAGE_odhcp6c=y CONFIG_PACKAGE_bash=y CONFIG_PACKAGE_curl=y; do
  grep -q "^$a" .config || { echo "FAIL: $a"; exit 1; }
done

# 编译（root 用户必须带 FORCE_UNSAFE_CONFIGURE=1，否则 tools/tar 拒编）
export FORCE_UNSAFE_CONFIGURE=1
make -j$(nproc) download
make -j$(nproc)

# 剥尾巴 + 校验
cd bin/targets/mvebu/cortexa53
python3 ../../../../catdrive-25122/strip_trailer.py
gzip -t *catdrive*ext4-sdcard*.img.gz
sha256sum *catdrive*ext4-sdcard*.img.gz
cat ../../../../build_dir/target-*/linux-mvebu_cortexa53/linux-*/.vermagic
```

### 5. 复现性要点

1. **基线是官方 tag**（`v25.12.2`），不是滚动分支
2. **配置随仓库走**（`config.full`），不是现场拼装
3. **feeds 由 tag 自带锁定**（`feeds.conf.default` 里写死了 commit）
4. **断言是准入门槛**，配置被"规范化"掉任何一项都会在 5 分钟内暴露
5. 想换版本：改 workflow 里两处 `v25.12.2` → 重新导出 config.full → 跑一次断言全绿才算通过

---

## 四、首次刷机（需要 TTL 线，请完整阅读）

### 0. 风险说明（先读这个）

- 固件刷的是 **eMMC**，U-Boot 在 **SPI flash**，本教程全程不碰 SPI → **不会永久变砖**
- `gzwrite` 期间（3~5 分钟）**绝对不能断电**
- 真正会变砖的是刷 U-Boot 本身；原厂 U-Boot 转 snail U-Boot 请严格按原帖操作
- U-Boot 也进不去时，还有 Marvell UART 模式救砖（见"变砖自救"）

### 1. 需要准备

| 物品 | 说明 |
|---|---|
| 猫盘 + 电源（5V 3A） | |
| USB 转 TTL 线 | CH340/PL2303，几块钱，**必须有** |
| U 盘 | FAT32，放镜像 |
| 螺丝刀、网线 | |

### 2. 接 TTL 线（拆机）

```
猫盘 GND  ←→  TTL GND
猫盘 TX   ←→  TTL RX
猫盘 RX   ←→  TTL TX        ← 交叉接，千万不要接 VCC/3.3V
```

电脑设备管理器确认 COM 口（CH340 常见 COM9）。

### 3. 串口终端

PuTTY / MobaXterm 任选，参数 **115200 8N1 无流控**。

### 4. 校验镜像

```
certutil -hashfile immortalwrt-25.12.2-...-ext4-sdcard.img.gz SHA256
```

与上文记录的 `4f128b84...` 比对，不一致不要刷。

### 5. 制作 U 盘

FAT32 格式化，镜像放**根目录**，建议改短名 `FLASH.GZ`（U-Boot 命令好敲）。

### 6. 进 U-Boot 并刷写

1. U 盘插猫盘 USB 口，串口点"连接"
2. 猫盘**断电再上电**，立刻连按**空格**（窗口只有 2 秒）
3. 看到 `Marvell>>` 即成功；错过就断电重来
4. 确认是 snail U-Boot：`printenv bootcmd` 显示 `bootcmd=usbboot`；显示 `syno` 相关的是原厂 U-Boot，**停手**
5. 依次执行：

```
usb start
```
→ 看到 `1 Storage Device(s) found`

```
mmc dev 0
```

```
fatload usb 0:1 0x6000000 FLASH.GZ
```
→ 必须核对字节数：`53104671 bytes read`（与镜像大小一致才继续）

```
echo SIZE=$filesize
```

```
gzwrite mmc 0 0x6000000 $filesize
```
→ 进度滚动，**3~5 分钟，不能断电**；结束出现 `2183266304 bytes, crc 0x........`

```
reset
```

### 7. 首次启动验证

```
cat /sys/class/net/br-lan/address          → 应为你标签上的 MAC（4c:65:a8:xx）
grep DISTRIB_RELEASE /etc/openwrt_release  → 25.12.2
ls /etc/modules.d | wc -l                  → 约 73
apk update                                  → 源可达
apk add kmod-tun && modprobe tun            → 官方 kmod 在线安装验证
```

接主路由：约 1 分钟内在 DHCP 租约里找主机名 `catdrive`。
找不到也不怕：60 秒后自动兜底 `192.168.1.1`，电脑设 `192.168.1.x/24` 直连即可进后台。

---

## 五、重刷与升级

### 1. 日常升级（优先）

```sh
apk update && apk upgrade          # 用户态包在线升级，不需要重刷
apk add luci-theme-argon           # 装主题
apk add luci-app-openclash         # 装插件
```

**不要在线升级 `base-files` / `kernel` / `libc` 这类系统包**——它们是固件的一部分，
在线升级会覆盖方案 B 的配置模板（network/system 预设、uci-defaults）。要更新基础系统请整盘重刷。

> 附注：LuCI 里 base-files 的"升级"按钮在 apk3 下是空转（`apk upgrade base-files` 无操作），
> 点完仍显示旧版本属正常，不是失败。

### 2. 整盘重刷（网线传镜像，TTL 只敲命令）

```sh
# 电脑侧
scp 新镜像.img.gz root@设备IP:/root/new.img.gz
ssh root@设备IP md5sum /root/new.img.gz     # 与电脑侧比对
```

重启进 U-Boot（倒计时连按空格），三条命令：

```
ext4load mmc 0:2 0x6000000 new.img.gz
gzwrite mmc 0 0x6000000 $filesize
reset
```

`ext4load` 从设备自身 rootfs（`mmc 0:2`）读镜像，U-Boot 阶段不需要网络。

### 3. 免 TTL 刷写（systemd 内 dd 法，风险自负）

设备能 SSH 时，可直接覆盖 eMMC 两个分区（p1 内核 32.3M、p2 rootfs 2G）：

```sh
# 关键：源镜像必须放 tmpfs（/tmp），绝不能放在被写入的 p2 分区上
scp 镜像.img.gz root@设备IP:/tmp/new.img.gz
# 停服务 → rootfs 只读 → dd p1 → dd p2 → sync → reboot
```

**必须遵守两条铁律**（违反过一次，导致 p2 半写、SSH 认证失效）：

1. **源文件不能放在正在写入的分区上**（放 `/tmp` 这个 tmpfs）
2. **校验要在 `drop_caches` 之前完成**，否则动态链接程序无法执行（连 md5sum 都跑不起来）

出问题不会变砖（U-Boot 在 SPI 未动），插回 TTL 用第 2 节流程即可救。

---

## 六、应用安装与常见问题

### OpenClash（照抄就不会报错）

本镜像 lan 是 DHCP 模式（无静态 `ipaddr`），OpenClash 默认只读配置文件 → 读不到 LAN 网段会启动失败。

```sh
apk add luci-app-openclash

# 关键一步：明确指定 LAN 网卡（DHCP 模式必须；静态 IP 模式可省）
uci set openclash.config.interface_name=br-lan
uci commit openclash

uci set openclash.config.enable=1
/etc/init.d/openclash restart
grep -E "Start Successful|Error" /tmp/openclash.log | tail -3
```

看到 `[Tip] OpenClash Start Successful!` 即成功。图形界面等价位置：
OpenClash → 插件设置 → 常规设置 → **指定 LAN 接口 = br-lan**。

**订阅配置注意**：不少机场订阅是"仅节点"格式（只有 `proxies`，没有 `proxy-groups` / `rules` / DNS 上游），
直接导入会启动但在线不通。需要补：策略组（select + url-test）、分流规则（LAN/CN 直连，其余走代理）、
国内 DNS 上游（223.5.5.5 / 119.29.29.29，否则会默认用被墙的 Cloudflare DoH）。

**模式陷阱**：`openclash.config.proxy_mode` 若是 `global`，所有流量走 GLOBAL 组（默认 DIRECT）→ 什么都上不去，
且**重启后依旧**。保持 `rule`：

```sh
uci set openclash.config.proxy_mode=rule && uci commit openclash && /etc/init.d/openclash restart
```

### 装了 LuCI 应用但侧栏没菜单

```sh
apk add luci-compat
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
```

然后**退出 LuCI 重新登录**（菜单在登录会话时生成）。
本镜像已内置 luci-compat + lua，正常情况下不会遇到；只有应用自身依赖缺失时才会。

### 安装时报包冲突

```sh
apk add dnsmasq-full        # OpenClash 等需要完整版 dnsmasq
```

### 启动报缺内核模块

```sh
apk search kmod- | grep 关键词
apk add kmod-xxx            # vermagic 与官方一致，官方 kmod 直接可装
```

### 换软件源

源文件 `/etc/apk/repositories.d/distfeeds.list`，每行一个
`https://镜像站/immortalwrt/releases/25.12.2/.../packages.adb`，
含 `targets/mvebu/cortexa53/kmods/6.12.103-1-846049ff.../packages.adb` 一行（kmod 源）。

---

## 七、变砖自救

| 现象 | 级别 | 处理 |
|---|---|---|
| 能进 `Marvell>>`，系统起不来 | 轻 | 重新 `fatload` + `gzwrite` |
| 串口无输出 | 中 | 查 TTL 接线/波特率；换 USB 口 |
| U-Boot 也进不去 | 重 | **Marvell UART 模式**：上电即走 WTP 协议，用 [bl-armada-3720](https://github.com/Izumiko/bl-armada-3720) 的 `WtpDownload` / `mox-imager` 经 TTL 刷回 `flash-image.bin`（无需编程器） |
| 以上全失败 | 极端 | CH341A 编程器 + SOP8 夹子直写 SPI flash |

UART 模式是 Marvell 平台的官方机制，成功率接近 100%，所以"不碰 SPI"的刷机操作风险可控。

---

## 八、版本历史

详细编译史与失败复盘见 **[FAILURES.md](FAILURES.md)**（含每一版的构建方法、产物、踩过的坑）。

| 版本 | 基线 | 特征 | 产物 |
|---|---|---|---|
| V1–V5 | 25.12-SNAPSHOT | 全塞 1108 kmod、modules.d 167/boot.d 23、2G、argon、comphy 修复 | 本地编译，两次实机验证 |
| Plan B | 25.12-SNAPSHOT | 删 mkdata、MAC 改 uci-defaults 一次性读取 | `696d8f8b...` |
| 25.12.2 基础版 | 官方 v25.12.2 | 官方 buildinfo + printf 拼装、不预装 kmod、169~200 包 | 17.6MB，`c2d2703d...`（NJU 源修补版） |
| 25.12.2 全功能版 | 官方 v25.12.2 | **config.full 方案**、318 包、U 盘刷入验证 | 50.4MB |
| **25.12.2 终版** | 官方 v25.12.2 | + `luci-compat`/`lua`（旧插件菜单可见），329 包 | **50.6MB，`4f128b84...`** |

## 九、致谢

U-Boot（`flash-image-snail.bin`）来自矿渣社区用户 **ihotte（Snail）** 的
[猫盘 OpenWrt、Synology 双启动固件](http://bbs.nasdiyer.com/forum.php?mod=viewthread&tid=11988) 项目。
作者声明：仅供自娱自乐，严禁用于商业用途。本仓库非商业分享并注明出处，如作者有异议请联系移除。
