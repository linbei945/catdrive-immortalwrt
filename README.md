# 猫盘（小猫盘）ImmortalWrt 23.05 单系统镜像 —— 编译工程

给 **小猫盘**（Marvell Armada 3720 / 2×A53 1.0GHz / 512MB DDR3 / 8GB eMMC / 单千兆口）
用的 ImmortalWrt 23.05 单系统镜像编译工程，产物直接写进 eMMC，不装群晖、不做双系统。

---

## 为什么不是现成镜像

- 官方 OpenWrt / ImmortalWrt **没有** catdrive 这个设备，需要自己加 DTS 和设备定义。
- 网上唯一的成品是 2020 年的 OpenWrt 18.06.8（snail 打包的双启动固件），内核 4.14，软件源早已停止维护。
- 你提到的 `lwfsnetwork/immortalwrt-catdrive` 工程**有严重缺陷**，直接跑出来的镜像在猫盘上起不来：
  1. 它只把 `armada-3720-catdrive.dts` 丢进内核目录，却**没有注册 catdrive 设备**；
  2. `.config` 里选的是 `DEVICE_marvell_armada-3720-db`，也就是 **Marvell 官方 DB 开发板**，
     编出来的 DTB 是 `armada-3720-db.dtb`。这块板子的 eMMC、SATA 供电、PHY 初始化、LED 全部和猫盘不同，
     猫盘上会卡在内核启动或找不到根分区；
  3. 没有任何分区大小、U-Boot 衔接的说明。

本工程把上面三点都修了：新增 `Device/catdrive` 设备定义、DTS 指向 catdrive、显式设置分区大小，
产物是不含 U-Boot 的 `sdcard.img.gz`（kernel ext4 分区 + squashfs rootfs 分区），沿用猫盘 SPI 里已有的 U-Boot。

---

## 目录结构

```
.github/workflows/build-catdrive.yml   # GitHub Actions 编译流程
dts/armada-3720-catdrive.dts           # 小猫盘设备树（512MB 内存 / eMMC / SATA / 88E1512 / 风扇 / AW2013 三色灯）
patches/cortexa53-catdrive.mk          # 追加到 target/linux/mvebu/image/cortexa53.mk 的设备定义
```

---

## 怎么用（4 步，不需要本地环境）

1. GitHub 上新建一个仓库（Public 即可，Actions 免费额度不限制）。
2. 把本目录**全部内容**（含 `.github` 隐藏目录）上传/推送上去：
   ```bash
   cd catdrive-immortalwrt
   git init && git add -A && git commit -m "catdrive immortalwrt build"
   git branch -M main
   git remote add origin https://github.com/<你的用户名>/<仓库名>.git
   git push -u origin main
   ```
   > 注意：Windows 资源管理器直接拖拽上传会丢掉 `.github` 目录，建议用 git 命令。
3. 仓库页面 → **Actions** → 左侧 `Build ImmortalWrt 23.05 for CatDrive (小猫盘)` → **Run workflow**
   （`rootfs_size` 默认 1024MB，可改成 2048/4096；eMMC 总共 8GB，剩余空间会留给 overlay 和数据）。
4. 等 1.5–3 小时。完成后：
   - **Releases** 里直接下载 `immortalwrt-23.05-...-catdrive-squashfs-sdcard.img.gz`
   - 或 Actions 运行页底部 **Artifacts** 下载同名压缩包

---

## 产物说明

**只刷 ext4 那个文件**：`immortalwrt-mvebu-cortexa53-catdrive-ext4-sdcard.img.gz`

首次编译同时产出了 squashfs 版本，但它**不可用**：这个 target 的 sdcard 镜像只建
kernel + rootfs 两个分区，没有独立的 rootfs_data 分区，squashfs 根分区是只读的，
`/overlay` 无处可挂，配置无法持久化。

（文件只有 42MB 是因为 squashfs 不会填满整个分区，属正常现象，不是文件损坏；已确认 p2 头是 `hsqs`。）
已在 workflow 里关掉 squashfs，后续只会出 ext4。

解压后是完整磁盘镜像（1,109,524,480 字节）：

| 分区 | 内容 | 大小 |
|---|---|---|
| p1 | ext4，含 `Image`、`armada-3720-catdrive.dtb`、`boot.scr` | 32MB @ 1MB |
| p2 | ext4 rootfs，整分区可写（overlay 直接用这个分区） | 1024MB @ 34MB |

镜像**不含 U-Boot**，因为猫盘从 SPI NOR 启动，U-Boot 已经在 SPI 里（你刷群晖时换过的那颗）。
eMMC 还剩约 7GB 未分区，可以之后 `fdisk` 加 p3 存数据。

### 已实测校验值（build catdrive-1）

```
文件：immortalwrt-mvebu-cortexa53-catdrive-ext4-sdcard.img.gz
大小：14,959,766 字节
crc32 ：72e5679d
sha256：f0ea56bb2c2441a39ce7c0b74e1d3d201300374a2039bc1783da172eec130c88
```


---

## 与原厂 snail 18.06.9 镜像的交叉验证

从 `flash-image-snail.bin`（U-Boot）里解析出的启动链：

```
bootcmd = gpio 读 GPIO23；等于 default_mode → bootcmd_button，否则 bootcmd_normal
bootcmd_normal = syno.scr（群晖）
bootcmd_button  = 按 boot_targets(usb mmc0 sata) 找 boot.scr
boot_a_script   = load ${iface} ${dev}:1 ${scriptaddr} ${prefix}${scriptname}; source
boot_prefixes   = / /boot/
env: kernel_addr=0x7000000  fdt_addr=0x6000000  scriptaddr=0x6d00000
```

| 项 | snail 18.06.9 | 本工程 23.05 |
|---|---|---|
| p1 | FAT32 128MB | ext4 32MB |
| p1 内容 | `zImage`、`dtb/armada-3720-ds120j.dtb`、`boot.scr`、`syno.scr` | `Image`、`armada-3720-catdrive.dtb`、`boot.scr` |
| 内核格式 | zImage（4.14） | Image（5.15，ARM64 头已校验） |
| p2 | 1919MB 声明，ext4 | 1024MB，ext4 完整写入 |
| 根分区定位 | `root=/dev/mmcblk0p2` | `root=PARTUUID=70ea2492-02`（与 MBR 签名一致） |
| DTB compatible | `marvell,catdrive` | `marvell,catdrive` |

关键点：U-Boot 的 `load` 走 fs-generic，镜像内同时有 FAT 和 ext4 读支持，所以 p1 用 ext4 可读；
`kernel_addr_r` / `fdt_addr_r` 在环境里没有定义，因此本镜像的 boot.scr 会沿用 env 的
`kernel_addr` / `fdt_addr`（0x7000000 / 0x6000000），地址不会为空。

**注意：本镜像没有 `syno.scr`。** 如果 `default_mode` 保持 0，`bootcmd_normal` 会去找
`syno.scr` 而失败，表现为停在 U-Boot 提示符（不是变砖）。所以刷完必须
`setenv default_mode '1'; saveenv`。

## 刷进 eMMC

前提：TTL 接好（115200 8N1，**不要接 VCC**），能中断启动进 U-Boot 命令行。
把 `img.gz` 放到电脑上跑 TFTP 服务（Tftpd64），猫盘和电脑同网段。

```text
setenv ipaddr 192.168.2.72        # 猫盘的临时 IP
setenv serverip 192.168.2.99      # 你电脑的 IP

tftp 0x6000000 immortalwrt-23.05-catdrive-squashfs-sdcard.img.gz
crc32 0x6000000 $filesize         # 记下结果，和电脑端算的 crc32 对比
gzwrite mmc 0 0x6000000 $filesize # 写入 eMMC，8GB 大概几分钟
reset
```

> `gzwrite` 是猫盘 U-Boot（snail 版）自带的解压写盘命令；如果你的 U-Boot 没有这个命令，
> 改用「U盘/硬盘临时系统 + `gzip -dc xxx.img.gz | dd of=/dev/mmcblk0 bs=4M`」。

如果 U-Boot 里还有 `default_mode` 变量，设成进 Linux 的那一项（snail 的 U-Boot 是 `1` = OpenWrt 优先）：

```text
setenv default_mode '1'
saveenv
reset
```

### 起不来的兜底手动启动

`boot.scr` 依赖 U-Boot 环境里的 `fdt_addr_r` / `kernel_addr_r`，老 U-Boot 可能没有。这时手动引导：

```text
mmc dev 0
ext4load mmc 0:1 0x1000000 Image
ext4load mmc 0:1 0x2000000 armada-3720-catdrive.dtb
setenv bootargs 'root=/dev/mmcblk0p2 rw rootwait console=ttyMV0,115200'
booti 0x1000000 - 0x2000000
```

能起来之后把这几条写进 `bootcmd` 并 `saveenv` 即可固化。

---

## 默认登录与旁路由配置

- 地址：进系统后 `ifconfig` 查看（DHCP 或 192.168.1.1），LuCI 用户名 `root`，密码为空（首次登录要设）。
- 旁路由：LAN 改成主路由同网段空闲 IP（如 192.168.1.2）、网关/DNS 指向主路由、
  DHCP 页勾「忽略此接口」，防火墙自定义规则加：
  ```
  iptables -t nat -I POSTROUTING -o eth0 -j MASQUERADE
  ```
  需要走旁路由的设备，把网关和 DNS 手动指到猫盘 IP。

---

## 风险提示

- 写 eMMC 会**清掉现有群晖/OpenWrt 数据**，不可恢复；先把重要文件拷出来。
- 动 U-Boot 前务必先备份 SPI（`sf read` 或编程器），这是唯一的救砖后路。
- 512MB 内存跑 23.05 的 LuCI + 代理插件会比较紧，建议只装必需插件，必要时加 512MB swap。
- 本工程产物未经实机验证（我这边没有猫盘，也无法在本机编译），第一次刷建议先确认 U-Boot 能正常手动
  `ext4load` 到内核再写盘；如果 `booti` 后卡住，接 TTL 看内核日志，把最后几行发我，按日志改 DTS。
