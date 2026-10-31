# CatDrive device profile for mvebu/cortexa53 (appended by CI)

define Device/catdrive
  $(call Device/Default-arm64)
  DEVICE_VENDOR := Catdrive
  DEVICE_MODEL := CatDrive
  DEVICE_DTS := armada-3720-catdrive
  SOC := armada-3720
  SUPPORTED_DEVICES := marvell,catdrive
  BOOT_SCRIPT := catdrive
  DEVICE_PACKAGES := kmod-usb2 kmod-usb3 kmod-usb-storage kmod-fs-ext4 \
	kmod-fs-vfat kmod-hwmon-gpiofan block-mount e2fsprogs fdisk
endef
TARGET_DEVICES += catdrive
