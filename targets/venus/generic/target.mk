ARCH:=aarch64
SUBTARGET:=generic
BOARDNAME:=generic
KERNELNAME:=Image
KERNEL_DTS = $(TOPDIR)/feeds/feed_anhnq/targets/venus/dts/ca8189v-kaon-pg6693g-rev00.dts
FEATURES+= nand ubifs

define Target/Description
	Build platform images for Cortina-Access Venus PG6693G board
endef

DEFAULT_PACKAGES += \
	kmod-fs-overlayfs firewall4


