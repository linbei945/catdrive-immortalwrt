# CatDrive (小猫盘) ImmortalWrt

群晖 DS120j 硬件的小猫盘（Armada 3720 / 512MB / 8GB eMMC）专用 ImmortalWrt 构建仓库。

## 当前版本：25.12.2

- 基线：官方 `v25.12.2` tag + 官方 `config.buildinfo`（`ALL_KMODS=y`，vermagic 与官方 kmods 完全一致：`846049ff...`）
- 机型：`Device/catdrive`（DTS：`armada-3720-catdrive`，含 comphy 禁用修复）
- rootfs 分区：**2G**；内核模块**不预装**（官方 1010 个 kmod 包可直接 `apk add`）
- 方案 rootfs 定制（`catdrive-25122/files/`）：
  - MAC：首次开机从 U-Boot 环境 `ethaddr` 读取并写入配置（`99-mac-from-uboot`，一次性自删）
  - 网络：DHCP 客户端 + 60 秒无地址兜底 `192.168.1.1`（`catdrive-netinit`，下次开机自动重试 DHCP），旁路由专用
  - `fw_env.config`：`/dev/mtd1 0x0 0x10000`
- 主题：Argon；主机名：`catdrive`；root 无密码

## 刷机（需 snail 修改版 U-Boot）

U-Boot（`flash-image-snail.bin`）来自矿渣社区用户 [ihotte（Snail）的猫盘双启动固件项目](http://bbs.nasdiyer.com/forum.php?mod=viewthread&tid=11988)，仅供非商业使用，Release 页附有副本与校验值。

U-Boot 里（上电连按空格进入）：

```
usb start
fatload usb 0:1 0x6000000 catdrive.img.gz
gzwrite mmc 0 0x6000000 $filesize
reset
```

实测：78MB 一次 `fatload` 成功（25 MiB/s）；`gzwrite` 约 3~5 分钟；中途不可断电。

## 构建产物

Releases 见 [catdrive-25122 tag](https://github.com/linbei945/catdrive-immortalwrt/releases/tag/catdrive-25122)。

## 构建

GitHub Actions：`.github/workflows/build-25122.yml`（push 到 main 或手动触发）。

本地编译等价流程：`~/catdrive25122/openwrt`，config = `official.buildinfo` + `PARTSIZE=2048` + `argon` + `uboot-envtools` 等，`make defconfig && make -j`。
