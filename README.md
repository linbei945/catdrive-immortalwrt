# CatDrive (小猫盘) ImmortalWrt

群晖 DS120j 硬件的小猫盘（Armada 3720 / 512MB / 8GB eMMC）专用 ImmortalWrt 构建仓库。

## 当前版本：25.12.2

- 基线：官方 `v25.12.2` tag + 官方 `config.buildinfo`（`ALL_KMODS=y`，vermagic 与官方 kmods 完全一致：`846049ff...`）
- 机型：`Device/catdrive`（DTS：`armada-3720-catdrive`，含 comphy 禁用修复）
- rootfs 分区：**2G**；内核模块**不预装**（官方 1010 个 kmod 包可直接 `apk add`）
- rootfs 定制（`catdrive-25122/files/`）：
  - MAC：首次开机从 U-Boot 环境 `ethaddr` 读取并写入配置（`99-mac-from-uboot`，一次性自删）
  - 网络：DHCP 客户端 + 60 秒无地址兜底 `192.168.1.1`（`catdrive-netinit`，下次开机自动重试 DHCP）
  - `fw_env.config`：`/dev/mtd1 0x0 0x10000`
- 主题：Argon；主机名：`catdrive`；root 无密码

## 产物

[Releases → catdrive-25122](https://github.com/linbei945/catdrive-immortalwrt/releases/tag/catdrive-25122)：
`immortalwrt-25.12.2-mvebu-cortexa53-catdrive-ext4-sdcard.img.gz`（约 18MB）
及 snail 修改版 U-Boot（`flash-image-snail.bin`，原厂 U-Boot 的机器必须先刷它）。

镜像 sha256 见 Release 内 `checksums.txt`，下载后先校验再刷。

---

# 一、首次刷机（需要 TTL 线，请完整阅读）

## 0. 风险说明（先读这个）

- 固件刷写的是 **eMMC**，U-Boot 本身（SPI flash）不动——固件刷坏可通过 U-Boot 重刷恢复，**不会永久变砖**。
- `gzwrite` 进行中（约 3~5 分钟）**绝对不能断电**——中断会让 eMMC 处于半写状态。
- 真正的变砖风险是**刷 U-Boot 本身**（SPI flash），本教程不涉及；原厂 U-Boot 转 snail U-Boot 请严格按原帖教程操作。
- 极端情况（U-Boot 也无法进入）可用 Marvell UART 模式救砖（见"变砖自救"）。

## 1. 需要准备的东西

| 物品 | 说明 |
|---|---|
| 猫盘 + 电源（5V 3A） | |
| USB 转 TTL 线 | CH340 或 PL2303，几块钱，**必须有**（刷机与排障全靠它） |
| U 盘 | FAT32 格式，放固件镜像 |
| 螺丝刀 | 拆外壳 |
| 网线 | 刷完连主路由 |

## 2. 接 TTL 线（拆机）

1. 拆掉外壳，主板边缘找到 4 根排针（TTL 接口，丝印见原帖图）。
2. 接线（**与 TTL 线交叉**，**千万不要接 VCC/3.3V**）：

```
猫盘 GND  ←→  TTL GND
猫盘 TX   ←→  TTL RX
猫盘 RX   ←→  TTL TX
```

3. TTL 线插电脑，设备管理器确认出现 COM 口（CH340 常见为 COM9）。

## 3. 打开串口终端

- 工具：PuTTY / MobaXterm / SecureCRT 任选
- 参数：**115200, 8N1, 无流控**
- 选对 COM 口，先不连接。

## 4. 校验镜像

电脑上执行（或用在线工具）：

```
certutil -hashfile immortalwrt-25.12.2-...-ext4-sdcard.img.gz SHA256
```

与 Release `checksums.txt` 比对，**不一致就不要刷**。

## 5. 制作 U 盘

1. U 盘 FAT32 格式化。
2. 固件镜像放 U 盘**根目录**，建议改短名 `catdrive.img.gz`（命令好敲）。

## 6. 进 U-Boot 并刷写

1. U 盘插猫盘 USB 口。
2. 串口终端点"连接"。
3. 猫盘**断电再上电**，立刻在串口里**连按空格**（只有 2 秒窗口）。
4. 看到 `Marvell>>` 即成功停住；错过就断电重来。
5. 确认 U-Boot 是 snail 修改版：`printenv bootcmd` 看到 `bootcmd=usbboot` 即是；
   看到 `syno` 相关的是**原厂 U-Boot，先停手**，去原帖刷 snail U-Boot。
6. 依次执行（每条回车）：

```
usb start
```
→ 看到 `1 Storage Device(s) found` 说明 U 盘认到了。
```
mmc dev 0
```
```
fatload usb 0:1 0x6000000 catdrive.img.gz
```
→ 出现 `bytes read`（80775216 之类，约 78MB）且大小与镜像一致才继续。
**78MB 可一次加载，无需分片。**
```
echo SIZE=$filesize
```
→ 记下这个值。
```
gzwrite mmc 0 0x6000000 $filesize
```
→ 开始写 eMMC，进度会滚动，**3~5 分钟，此时绝对不能断电**。
→ 出现 `2183266304 bytes, crc 0x......` 即完成。
```
reset
```

7. 设备重启，拔掉 U 盘可选（不拔也不影响，插着设备会尝试从 U 盘启动失败后回落 eMMC）。

## 7. 首次启动验证

- 串口应看到 `kmodloader: done loading`（约 11 秒）和 `Link is Up`（约 35 秒）。
- 网线插主路由：等约 1 分钟，在主路由 DHCP 租约里找主机名 **catdrive**。
- 找不到也没关系：60 秒后设备自动切到 `192.168.1.1`，电脑设成
  `192.168.1.x/24` 直连即可进后台（root 无密码，**先改密码**）。
- 验证清单：

```
cat /sys/class/net/br-lan/address    → 应为你机器标签上的 MAC
grep DISTRIB_RELEASE /etc/openwrt_release
apk update                           → 确认软件源可达
apk add kmod-tun                     → 官方 kmod 在线安装验证
```

---

# 二、重刷 / 升级（网线刷机，免拆机传镜像）

前提：设备已运行本固件且能 SSH（任何网络状态均可）。

TTL 线此时**只用来敲命令，不传镜像**——镜像走网线（SSH）。

## 1. 小版本升级（优先尝试）

```
apk update && apk upgrade
```

官方源持续更新，用户态包直接升级，**不需要重刷**。

## 2. 整盘重刷（大版本/系统更换）

TTL 线此时**只用来敲命令，不传镜像**——镜像走网线（SSH）。

在电脑上把新镜像传到设备并校验：

```
scp 新镜像.img.gz root@设备IP:/root/new.img.gz
ssh root@设备IP md5sum /root/new.img.gz     # 与电脑端比对，一致才继续
```

然后重启进 U-Boot（倒计时连按空格），依次执行三条命令：

```
ext4load mmc 0:2 0x6000000 new.img.gz
gzwrite mmc 0 0x6000000 $filesize
reset
```

`ext4load` 直接从设备 rootfs（`mmc 0:2`）读取镜像——网线传完数据后，
U-Boot 阶段不再需要任何网络操作。`gzwrite` 期间（3~5 分钟）不能断电。

## 3. 完全没有 TTL 线时

TTL 是进 U-Boot 的唯一入口，没有 TTL 就无法触发 `gzwrite`。
因此：**刷过一次之后，TTL 线建议常备或在重刷时临时接上**（接线 2 分钟）。

---

# 三、变砖自救

| 现象 | 级别 | 处理 |
|---|---|---|
| 能进 `Marvell>>`，系统起不来 | 轻 | 重新 `fatload`+`gzwrite` 即可 |
| 串口无输出 | 中 | 检查 TTL 接线/波特率；换 USB 口 |
| U-Boot 也进不去 | 重 | **Marvell UART 模式救砖**：猫盘 SoC 支持 UART 烧写，
上电即跑 WTP 协议，用 [bl-armada-3720](https://github.com/Izumiko/bl-armada-3720)
Release 里的 `WtpDownload_linux` 或 `mox-imager` 经 TTL 线刷回 `flash-image.bin`
（命令见该仓库 README，无需编程器无需拆 flash） |
| 以上全部失败 | 极端 | CH341A 编程器 + SOP8 夹子直接夹 SPI flash 重写 |

UART 救砖是猫盘这类 Marvell 平台的官方机制，成功率接近 100%，
所以本教程的刷机操作（不碰 SPI）风险可控。

---

# 四、构建

GitHub Actions：`.github/workflows/build-25122.yml`（push 自动触发，约 3 小时）。

本地编译等价流程：ImmortalWrt `v25.12.2` + `catdrive-25122/` 集成 + `official.buildinfo` 差异
（`PARTSIZE=2048`、`argon`、`uboot-envtools` 等），`make defconfig && make -j`。
内核 vermagic 必须等于官方 kmods 的 `846049ff0684ff21c8cae8e6f2efc82e`（CI 已内置断言）。

## 常见问题（装应用后出问题先看这里）

### 装了 LuCI 应用，侧栏菜单里没有

旧式 Lua 应用（OpenClash 及大量第三方插件）在新版 ucode LuCI 上需要兼容层：

```sh
apk add luci-compat
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
```

然后**退出 LuCI 重新登录**（菜单在登录会话时生成）。

### 安装时报包冲突

多半是和 `dnsmasq` 冲突（OpenClash 等需要完整版）：

```sh
apk add dnsmasq-full
```

### 应用启动了但报缺内核模块（`.ko`）

在官方源找同名 kmod 安装即可，例如：

```sh
apk search kmod- | grep 关键词
apk add kmod-xxx
```

（本镜像的 vermagic 与官方 kmods 完全一致，官方源的内核模块可直接安装。）

### 换了软件源后 apk 报错

源文件：`/etc/apk/repositories.d/distfeeds.list`，格式为每行一个
`https://镜像站/immortalwrt/releases/25.12.2/.../packages.adb`。
