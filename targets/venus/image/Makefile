# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2021-2022 KAON Media Co Ltd
#
ifneq ($(SIGNING_MODE),y)
include $(TOPDIR)/rules.mk

ifneq ($(CONFIG_EXTRA_DEVELOPMENT_IMAGE_NAME),)
  EXTRA_IMAGE_NAME := $(call qstrip,$(CONFIG_EXTRA_DEVELOPMENT_IMAGE_NAME))
endif

include $(INCLUDE_DIR)/image.mk
endif

define Build/copy-dtb
  $(if $(DEVICE_DTS),$(CP) $(KDIR)/image-$(DEVICE_DTS).dtb $(BIN_DIR)/$(IMG_PREFIX)-$(DEVICE_NAME).dtb)
endef

define Device/Default
  FILESYSTEMS := squashfs
  KERNEL_NAME := Image
  KERNEL := kernel-bin
  IMAGES :=
endef

include cortina.mk

define Device/PG6692x
  $(Device/PG249X/Defaults)
  DEVICE_TITLE:=Kaon $(1)$(if $(2),-$(2))
  DEVICE_DTS = $$(call tolower,$$(CA_SOC))-kaon-$(call tolower,$(1))$(if $(2),-$(2))
  DEVICE_DTS_DIR := ../dts
  IMAGE/mmc-raw.bin.gz := ca-mmc-img | gzip
  IMAGE/mmc-sysupgrade.bin := ca-mmc-upgrade-img | gzip
  $(if $(filter y,$(CONFIG_BUILD_SYSUPGRADE_UBOOT)), \
  IMAGE/mmc-sysupgrade-uboot.bin := ca-mmc-upgrade-uboot-img | gzip)
  $(if $(filter y,$(CONFIG_BUILD_SYSUPGRADE_UBOOT_ENV)), \
  IMAGE/mmc-sysupgrade-uboot-env.bin := ca-mmc-upgrade-uboot-env-img | gzip)
  ARTIFACTS := dtb
  ARTIFACT/dtb := copy-dtb
  ARTIFACT/mmc-u-boot-raw.bin := ca-mmc-boot-img
  ARTIFACT/mmc-u-boot-fip.bin := ca-mmc-u-boot
  ARTIFACT/mmc-u-boot-env.bin := ca-mmc-u-boot-env
  ARTIFACT/signing-tools := signing-tools-dir
  $(Device/$(1)/Defaults)
endef

define Device/PG6692G/Defaults
  CA_SOC := CA8189V
  CA_DDR_TYPE := DDR4
  CA_DDR_WIDTH := 16
  CA_DDR_DOUBLE_REFRESH := 0
  CA_DDR_SIZE := 8G
  CA_DDR_SPEED := DDR2133
  CA_MMC_UBOOT_PREFIX := kaon-pg6692g-mmc
  CA_MMC_LAST_USABLE_LBA := 0x64ffff
  ARTIFACTS += mmc-u-boot-env.bin # mmc-u-boot-raw.bin mmc-u-boot-fip.bin
  IMAGES := mmc-raw.bin.gz
  IMAGES += mmc-sysupgrade.bin
  $(if $(filter y,$(CONFIG_BUILD_SYSUPGRADE_UBOOT)), \
  IMAGES += mmc-sysupgrade-uboot.bin)
  $(if $(filter y,$(CONFIG_BUILD_SYSUPGRADE_UBOOT_ENV)), \
  IMAGES += mmc-sysupgrade-uboot-env.bin)
  DEVICE_PACKAGES += mkf2fs mmc-utils
endef


define Device/kaon-pg6692g-rev00
  $(call Device/PG6692x,PG6692G,rev00)
endef
TARGET_DEVICES += kaon-pg6692g-rev00

define Device/kaon-pg6692g-rev01
  $(call Device/PG6692x,PG6692G,rev01)
endef
TARGET_DEVICES += kaon-pg6692g-rev01

define Device/kaon-pg6692g-rev02
  $(call Device/PG6692x,PG6692G,rev02)
  ARTIFACTS += signing-tools
endef
TARGET_DEVICES += kaon-pg6692g-rev02


ifneq ($(SIGNING_MODE),y)
include image-rootfs.mk
endif

define Image/Prepare
  $(call Image/Prepare/Rootfs)
endef

$(eval $(call BuildImage))


