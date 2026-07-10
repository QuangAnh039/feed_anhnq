include $(TOPDIR)/rules.mk

ARCH:=aarch64
BOARD:=venus
BOARDNAME:=Cortina-Access Venus
CPU_TYPE:=cortex-a55
KERNELNAME:=Image dtbs

KERNEL_PATCHVER:=6.6
FEATURES += fpu usb pci pcie gpio nand squashfs ramdisk boot-part rootfs-part ubifs

include $(INCLUDE_DIR)/target.mk
include $(TOPDIR)/feeds/feed_ca/include/target-kernel.mk

DEFAULT_PACKAGES += ca-host-tools

define Kernel/Prepare
	$(call Kernel/Prepare/Default)
	$(if $(QUILT),rm -rf $(LINUX_DIR)/patches; mkdir -p $(LINUX_DIR)/patches)
	$(call PatchDir,$(LINUX_DIR),kernel-patch,kernel/)
endef


define Target/Rootfs/Customize
	@echo  "Target/Rootfs/Customize, see $(PLATFORM_DIR)/Makefile"
	@sed -i "/DISTRIB_TARGET/c DISTRIB_TARGET='$(BOARD)$(if $(CONFIG_EXTRA_BOARD_NAME),/$(CONFIG_EXTRA_BOARD_NAME))'" $(TARGET_DIR)/etc/openwrt_release
endef

$(eval $(call BuildTarget))

ifeq ($(TARGET_BUILD),1)
  $(eval $(CA/Kernel/Download))
endif