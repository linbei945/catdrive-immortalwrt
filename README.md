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

`immortalwrt-...-catdrive-squashfs-sdcard.img.gz` 解压后是一个完整磁盘镜像：

| 分区 | 内容 | 大小 |
|---|---|---|
| p1 | ext4，含 `Image`、`armada-3720-catdrive.dtb`、`boot.scr` | 32MB |
| p2 | squashfs rootfs（overlay 自动用分区剩余空间） | 你设的 rootfs_size |

镜像**不含 U-Boot**，因为猫盘从 SPI NOR 启动，U-Boot 已经在 SPI 里（你刷群晖时换过的那颗）。

---

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
