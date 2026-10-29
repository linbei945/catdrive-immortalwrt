# CatDrive (小猫盘) device profile for mvebu/cortexa53
# 由 workflow 追加到 target/linux/mvebu/image/cortexa53.mk 末尾

define Device/catdrive
  $(call Device/Default-arm64)
  DEVICE_VENDOR := Catdrive
  DEVICE_MODEL := CatDrive
  DEVICE_DTS := armada-3720-catdrive
  SOC := armada-3720
  SUPPORTED_DEVICES := marvell,catdrive
  # 猫盘常见的 U-Boot（2018.03 精简版）只编译了 ext4load，
  # 其 boot_a_script 用 ext4load 取 boot.scr，脚本内也必须用 ext4load。
  BOOT_SCRIPT := catdrive
  DEVICE_PACKAGES := kmod-usb2 kmod-usb3 kmod-usb-storage kmod-fs-ext4 \
	kmod-fs-vfat kmod-hwmon-gpiofan block-mount e2fsprogs fdisk
endef
TARGET_DEVICES += catdrive
