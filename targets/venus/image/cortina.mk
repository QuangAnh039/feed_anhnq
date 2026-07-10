# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2021-2022 KAON Media Co Ltd
#

CA_ROOTFS_KEYFILE:=keys/rootfs.key
PP_KEYFILE:=keys/pp-key.bin
CA_ROOTFS_CERTFILE:=keys/fit-signature-key.crt
CA_ROOTFS_CERTKEY:=keys/fit-signature-key.key

define is_key_exist
	@if ! test -f $(1); then echo "[ERROR]: $(1) is missing"; exit 1; fi
endef

define ca-dmcrypt-gen-xts
	$(call is_key_exist,$(CA_ROOTFS_KEYFILE))
	$(STAGING_DIR_HOSTPKG)/bin/dmcrypt_gen_xts $(1) \
		$$(hexdump -v -e '1/1 "%02X"' $(CA_ROOTFS_KEYFILE))
endef

# Generate rootfs signature using CA_ROOTFS_CERTFILE
# This function expects three arguments
#   $(1) - path to tmpdir
#   $(2) - path to initrd.cpio archive
#   $(3) - path to rootfs image
define ca-sign-rootfs
	$(eval CA_SIGN_ROOTFS_TMPDIR:=$(abspath $(1)))
	$(eval CA_SIGN_ROOTFS_INITRD_CPIO:=$(abspath $(2)))
	$(eval CA_SIGN_ROOTFS_ROOTFS_IMAGE:=$(abspath $(3)))

	if [ ! -d $(CA_SIGN_ROOTFS_TMPDIR) ] || \
			[ ! -f $(CA_SIGN_ROOTFS_INITRD_CPIO) ] || \
			[ ! -f $(CA_SIGN_ROOTFS_ROOTFS_IMAGE) ] ; then \
		echo "BUG: ca-sign-rootfs was called with invalid arguments"; \
		exit 1; \
	fi

	mkdir $(CA_SIGN_ROOTFS_TMPDIR)/rootfs_sign

	$(CP) $(CA_ROOTFS_CERTFILE) \
		$(CA_SIGN_ROOTFS_TMPDIR)/rootfs_sign/rootfs.crt

	LANG=C wc -c $(CA_SIGN_ROOTFS_ROOTFS_IMAGE) | \
		cut -d' ' -f1 > $(CA_SIGN_ROOTFS_TMPDIR)/rootfs_sign/rootfs.sz
	if [ ! -f $(CA_SIGN_ROOTFS_TMPDIR)/rootfs_sign/rootfs.sz ] || \
			[ "`cat $(CA_SIGN_ROOTFS_TMPDIR)/rootfs_sign/rootfs.sz`" -eq 0 ] ; then \
		echo "BUG: ca-sign-rootfs was called with path to empty rootfs image"; \
		exit 1; \
	fi

	openssl dgst \
			-sha256 \
			-sign $(CA_ROOTFS_CERTKEY) \
			-out $(CA_SIGN_ROOTFS_TMPDIR)/rootfs_sign/rootfs.sgn \
			$(CA_SIGN_ROOTFS_ROOTFS_IMAGE) || { \
		echo "Cannot sign rootfs image"; \
		exit 1; \
	}

	(cd $(CA_SIGN_ROOTFS_TMPDIR)/rootfs_sign; \
		find . | \
		cpio -o -H newc -R 0:0 -AO $(CA_SIGN_ROOTFS_INITRD_CPIO))
endef

define ca_build_ctrl
  rm -f $(1); \
  touch $(1); \
  echo "BOARD=\"$(if $(BOARD_NAME),$(BOARD_NAME),$(DEVICE_NAME))\"" >> $(1); \
  echo "VERSION=\"$(VERSION_NUMBER)\"" >> $(1); \
  echo "UBOOT_BUNDLED=$(2)" >> $(1);
endef

ca_upgrade_tar_options:=-cv --sort=name --owner=0 --group=0 --numeric-owner
ca_upgrade_tar_options+=$(if $(SOURCE_DATE_EPOCH),--mtime=@$(SOURCE_DATE_EPOCH))

define Build/ca-mmc-upgrade-img
	rm -rf $@.ca-upgrade

	mkdir -p $@.ca-upgrade/sysupgrade-venus
	$(call ca_build_ctrl,$@.ca-upgrade/sysupgrade-venus/CONTROL,0)

	mkdir -p $@.ca-upgrade/sysupgrade-venus/mmc

	dd if=$(call param_get_default,rootfs,$(1),$(IMAGE_ROOTFS)) \
		of=$@.ca-upgrade/sysupgrade-venus/mmc/rootfs.bin bs=512 conv=sync

	$(if $(CONFIG_VENUS_IMAGE_ENCRYPT_ROOTFS), \
		$(call ca-dmcrypt-gen-xts,$@.ca-upgrade/sysupgrade-venus/mmc/rootfs.bin) \
	)

	$(call ca_mmc_boot_part,$@.ca-upgrade/sysupgrade-venus/mmc/boot.bin,$@.ca-boot,$@.ca-upgrade/sysupgrade-venus/mmc/rootfs.bin,$@.dtb)

	tar -C $@.ca-upgrade $(ca_upgrade_tar_options) -f $@ sysupgrade-venus

	rm -rf $@.ca-upgrade
endef

define Build/ca-mmc-upgrade-uboot-img
	rm -rf $@.ca-upgrade-uboot

	mkdir -p $@.ca-upgrade-uboot/sysupgrade-venus
	$(call ca_build_ctrl,$@.ca-upgrade-uboot/sysupgrade-venus/CONTROL,1)

	mkdir -p $@.ca-upgrade-uboot/sysupgrade-venus/mmc

	dd if=$(call param_get_default,rootfs,$(1),$(IMAGE_ROOTFS)) \
		of=$@.ca-upgrade-uboot/sysupgrade-venus/mmc/rootfs.bin bs=512 conv=sync

	$(if $(CONFIG_VENUS_IMAGE_ENCRYPT_ROOTFS), \
		$(call ca-dmcrypt-gen-xts,$@.ca-upgrade-uboot/sysupgrade-venus/mmc/rootfs.bin) \
	)

	$(call ca_mmc_boot_part,$@.ca-upgrade-uboot/sysupgrade-venus/mmc/boot.bin,$@.ca-boot,$@.ca-upgrade-uboot/sysupgrade-venus/mmc/rootfs.bin,$@.dtb)

	$(call ca-fip,$@.ca-upgrade-uboot/sysupgrade-venus/mmc/fip.bin,$(CA_MMC_UBOOT_PREFIX),$@.dtb)

	$(CP) $(STAGING_DIR_IMAGE)/$(CA_MMC_UBOOT_PREFIX)-u-boot-env.bin $@.ca-upgrade-uboot/sysupgrade-venus/mmc/u-boot-env.bin

	tar -C $@.ca-upgrade-uboot $(ca_upgrade_tar_options) -f $@ sysupgrade-venus

	rm -rf $@.ca-upgrade-uboot
endef

define Build/ca-mmc-upgrade-uboot-env-img
	rm -rf $@.ca-upgrade-uboot-env

	mkdir -p $@.ca-upgrade-uboot-env/sysupgrade-venus
	$(call ca_build_ctrl,$@.ca-upgrade-uboot-env/sysupgrade-venus/CONTROL,2)

	mkdir -p $@.ca-upgrade-uboot-env/sysupgrade-venus/mmc

	dd if=$(call param_get_default,rootfs,$(1),$(IMAGE_ROOTFS)) \
		of=$@.ca-upgrade-uboot-env/sysupgrade-venus/mmc/rootfs.bin bs=512 conv=sync

	$(if $(CONFIG_VENUS_IMAGE_ENCRYPT_ROOTFS), \
		$(call ca-dmcrypt-gen-xts,$@.ca-upgrade-uboot-env/sysupgrade-venus/mmc/rootfs.bin) \
	)

	$(call ca_mmc_boot_part,$@.ca-upgrade-uboot-env/sysupgrade-venus/mmc/boot.bin,$@.ca-boot,$@.ca-upgrade-uboot-env/sysupgrade-venus/mmc/rootfs.bin,$@.dtb)

	$(CP) $(STAGING_DIR_IMAGE)/$(CA_MMC_UBOOT_PREFIX)-u-boot-env.bin $@.ca-upgrade-uboot-env/sysupgrade-venus/mmc/u-boot-env.bin

	tar -C $@.ca-upgrade-uboot-env $(ca_upgrade_tar_options) -f $@ sysupgrade-venus

	rm -rf $@.ca-upgrade-uboot-env
endef

define Build/ca-nand-upgrade-img
	rm -rf $@.ca-upgrade

	mkdir -p $@.ca-upgrade/sysupgrade-venus
	$(call ca_build_ctrl,$@.ca-upgrade/sysupgrade-venus/CONTROL,0)

	mkdir -p $@.ca-upgrade/sysupgrade-venus/nand
	cp $@ $@.ca-upgrade/sysupgrade-venus/nand/rootfs.bin

	tar -C $@.ca-upgrade $(ca_upgrade_tar_options) -f $@ sysupgrade-venus

	rm -rf $@.ca-upgrade
endef

CA_FIP_GUID:=ca777000-f190-b69b-8136-dea2835d4178

CA_GPT_ATTR_DDR_TYPE_DDR3:=49:0
CA_GPT_ATTR_DDR_TYPE_DDR4:=49:1
CA_GPT_ATTR_DDR_WIDTH_16:=50:1
CA_GPT_ATTR_DDR_WIDTH_32:=50:0
CA_GPT_ATTR_DDR_DOUBLE_REFRESH_1:=51:0
CA_GPT_ATTR_DDR_DOUBLE_REFRESH_0:=51:1
CA_GPT_ATTR_DDR_SIZE_1G:=52:0 53:0
CA_GPT_ATTR_DDR_SIZE_2G:=52:1 53:0
CA_GPT_ATTR_DDR_SIZE_4G:=52:0 53:1
CA_GPT_ATTR_DDR_SIZE_8G:=52:1 53:1
CA_GPT_ATTR_DDR_SPEED_DDR1600:=54:0 55:0
CA_GPT_ATTR_DDR_SPEED_DDR1866:=54:1 55:0
CA_GPT_ATTR_DDR_SPEED_DDR2133:=54:0 55:1
CA_GPT_ATTR_DDR_SPEED_DDR800:=54:1 55:1

ca_gpt_attr_ddr=$(CA_GPT_ATTR_DDR_$(1)_$(CA_DDR_$(1)))

define ca_ptgen_fip_attr_ddr
  $(foreach param,TYPE WIDTH DOUBLE_REFRESH SIZE SPEED,$(strip \
    $(patsubst %, -A %,$(call ca_gpt_attr_ddr,$(param))) \
   ))
endef

ca_ptgen_fip_attr_encrypt += -A 60:$(if $(CONFIG_VENUS_IMAGE_ENCRYPT_BL2),1,0)
ca_ptgen_fip_attr_encrypt += -A 61:$(if $(CONFIG_VENUS_IMAGE_ENCRYPT_BL31_BL33),1,0)
ca_ptgen_fip_attr_encrypt += -A 62:$(if $(CONFIG_VENUS_IMAGE_ENCRYPT_BL31_BL33),1,0)
ca_ptgen_fip_attr_encrypt += -A 63:$(if $(CONFIG_VENUS_IMAGE_ENCRYPT_BL31_BL33),1,0)

define ca_ptgen_fip_attr
	$(ca_ptgen_fip_attr_ddr) $(ca_ptgen_fip_attr_encrypt)
endef

ca_part_size=$(strip $(CA_$(strip $(1))_PART_SIZE))
ca_part_offset=$(strip $(CA_$(strip $(1))_PART_OFFSET))

# ca_ptgen_partdef - assembles a partition definition for ptgen
# $(1): <part_name> for the given partition from the
#       "CA_<part_name>_PART_{SIZE,OFFSET}" device variables
# $(2): name of the partition in GPT
# $(3): additional ptgen options
define ca_ptgen_partdef
  $(eval part_size=$(call ca_part_size,$(1))) \
  $(eval part_offset=$(call ca_part_offset,$(1))) \
  $(if $(part_size), $(strip \
    -N $(2) $(3) -p $(part_size)$(if $(part_offset),@$(part_offset)) \
  ))
endef

# ca_img_insert - inserts a file into the image
# $(1): destination image file to insert data to
# $(2): source file containing the data to be inserted
# $(3): size of the data read from the source file (optional)
#       if specified, exactly this amount of bytes gets read from the
#       source file, if the size of the source file is less than this,
#       the remaining bytes will be filled with zero bytes
# $(4): offset in the destination file where to insert data to (optional)
#       if not specified, the data is appended to the destination image
define ca_img_insert
  dd if="$(strip $(2))" \
    $(if $(strip $(3)), \
        bs=$(strip $(3)) count=1 conv=sync$(comma)notrunc \
    , \
        bs=1024 conv=notrunc \
    ) \
    $(if $(strip $(4)), \
        of="$(strip $(1))" oflag=seek_bytes seek=$(strip $(4)) \
    , \
        >> "$(strip $(1))" \
    )
endef

# ca_insert_partdata - inserts a file into the MMC image
# $(1): destination image file to insert data to
# $(2): source file containing the data to be inserted
# $(3): <part_name> for the given partition from the
#       "CA_<part_name>_PART_{SIZE,OFFSET}" device variables
define ca_insert_partdata
  $(call ca_img_insert,$(1),$(2),$(call ca_part_size,$(3)),$(call ca_part_offset,$(3)))
endef

ca-package-files=$(call opkg_package_files,$(foreach pkg,$(1),$(pkg)$(call GetABISuffix,$(pkg))))

# NOTE: the 'libc' and 'kernel' packages are filtered out by the
# 'ipkg-make-index.sh' script from the Packages list, so those
# must be specified explicitly.
ca-initrd-packages := libc kernel
ca-initrd-packages += venus-initrd

define ca-initrd
	$(eval INITRD_TMP_DIR:=$(1).initrd.tmp)
	$(eval INITRD_ROOT_DIR:=$(INITRD_TMP_DIR)/root)
	$(eval INITRD_CPIO:=$(INITRD_TMP_DIR)/initrd.cpio)
	$(eval OPKG_CONF:=$(INITRD_TMP_DIR)/opkg.conf)

	-rm -rf $(INITRD_TMP_DIR)

	mkdir -p $(INITRD_TMP_DIR)/packages
	mkdir -p $(INITRD_ROOT_DIR)/tmp

	$(if $(SIGNING_MODE), \
		@echo "Signing mode is set. Do not generate initrd" \
	,\
		# build package index
		( \
			cd $(INITRD_TMP_DIR)/packages; \
			for pkg in $(PACKAGE_DIR_ALL)/*.ipk; do \
				ln -sf $$pkg $$(basename $$pkg); \
			done; \
			$(SCRIPT_DIR)/ipkg-make-index.sh . > Packages; \
		)

		echo 'src default file://$(INITRD_TMP_DIR)/packages' > $(OPKG_CONF)
		$(call opkg,$(INITRD_ROOT_DIR)) -f $(OPKG_CONF) update
		$(call opkg,$(INITRD_ROOT_DIR)) -f $(OPKG_CONF) install \
			$(call ca-package-files,$(ca-initrd-packages))
		$(call prepare_rootfs,$(INITRD_ROOT_DIR),$(TOPDIR)/files)

		$(if $(CONFIG_VENUS_IMAGE_ENCRYPT_ROOTFS), \
			$(CP) $(CA_ROOTFS_KEYFILE) $(PP_KEYFILE) $(INITRD_ROOT_DIR)/ \
		)

		( \
			cd $(INITRD_ROOT_DIR); \
			find . | $(STAGING_DIR_HOST)/bin/cpio -o -H newc -R 0:0 > $(1); \
		)
	)

	rm -rf $(OPKG_CONF)
endef

CA_FIT_HASH_ALGO := sha256
CA_FIT_SIGN_ALGO := sha256,rsa2048
CA_FIT_SIGN_KEY_NAME := fit-signature-key
CA_FIT_CIPHER_ALGO := aes256
CA_FIT_CIPHER_KEY_NAME := fit-cipher-key
CA_FIT_CIPHER_IV_NAME := fit-cipher-iv
ITS_DATA_DIR_PREFIX:=data = /incbin/\(\"
$(eval SIGNING_TOOL_VERSION:=$(file <signing-tools/signing-tools-version))
SIGNING_TOOLS_NAME:=$(IMG_PREFIX)-signing-tools-$(SIGNING_TOOL_VERSION)
SIGNING_TOOLS_ROOT:=$(BIN_DIR)/$(SIGNING_TOOLS_NAME)

CA/fdtoverlay = LD_LIBRARY_PATH=$(STAGING_DIR_HOSTPKG)/lib:/$(LD_LIBRARY_PATH)  \
       $(STAGING_DIR_HOSTPKG)/bin/fdtoverlay --verbose --input $2 --output $1 $3
CA/MergeDTB = $(if $3,$(call CA/fdtoverlay,$1,$2,$3),$(LN) $2 $1)

# ca-its - creates an image tree source by preprocessing a template file
# $(1): its template
# $(2): target its file
# $(3): additional arguments for cpp
define ca-its
	$(call is_key_exist,keys/$(CA_FIT_CIPHER_KEY_NAME).bin)
	$(call is_key_exist,keys/$(CA_FIT_CIPHER_IV_NAME).bin)
	$(call is_key_exist,keys/$(CA_FIT_SIGN_KEY_NAME).key)
	$(call is_key_exist,keys/$(CA_FIT_SIGN_KEY_NAME).crt)

	$(if $(SIGNING_MODE), \
		$(eval KERNEL_DATA=$(call param_get,KERNEL_DATA,$(3))) \
		$(eval FDT_DATA=$(call param_get,FDT_DATA,$(3))) \
		$(eval INITRD_DATA=$(call param_get,INITRD_DATA,$(3))) \
		( \
			$(CP) image/fit/kernel.its $(2); \
			sed -i 's~data.*kernel.bin.gz~$(ITS_DATA_DIR_PREFIX)$(PWD)/$(KERNEL_DATA)~g' $(2); \
			sed -i 's~data.*initrd.cpio.gz~$(ITS_DATA_DIR_PREFIX)$(PWD)/$(INITRD_DATA)~g' $(2); \
			sed -i 's~data.*image-.*\.dtb~$(ITS_DATA_DIR_PREFIX)$(PWD)/$(FDT_DATA)~g' $(2); \
		)
	,
		$(TARGET_CROSS)cpp -nostdinc -x assembler-with-cpp -undef -P $(3) \
			-D HASH_ALGO=$(CA_FIT_HASH_ALGO) \
			$(if $(CONFIG_VENUS_IMAGE_FIT_SIGNATURE),\
				-D SIGNATURE_ALGO=$(CA_FIT_SIGN_ALGO) \
				-D SIGNATURE_KEY_NAME=$(CA_FIT_SIGN_KEY_NAME) \
			) \
			$(if $(CONFIG_VENUS_IMAGE_FIT_CIPHER),\
				-D CIPHER_ALGO=$(CA_FIT_CIPHER_ALGO) \
				-D CIPHER_KEY_NAME=$(CA_FIT_CIPHER_KEY_NAME) \
				-D CIPHER_IV_NAME=$(CA_FIT_CIPHER_IV_NAME) \
			) \
			-o $(2) $(1)
	)
endef

# ca_mmc_boot_part - builds an image for the MMC devices boot partions
# $(1): target image
# $(2): temporary directory used to store the files of the boot image
# $(3): path to rootfs image
# $(4): path to u-boot dtb
define ca_mmc_boot_part
	$(eval tmpdir=$(2))
	rm -rf $(tmpdir)
	mkdir -p $(tmpdir)/boot
	$(call is_key_exist,keys/fit-pre-load.crt)
	$(call is_key_exist,keys/fit-pre-load.key)

	$(eval FIT_BIN_DIR=$(SIGNING_TOOLS_ROOT)/image/fit)
	cp $(IMAGE_KERNEL) $(tmpdir)/boot/kernel.bin
	cp $(KDIR)/image-$(DEVICE_DTS).dtb $(tmpdir)/boot/dtb.bin
	gzip -9nc $(IMAGE_KERNEL) > $(tmpdir)/kernel.bin.gz

	$(if $(CONFIG_VENUS_IMAGE_ENCRYPT_ROOTFS), \
		$(call ca-initrd,$(tmpdir)/initrd.cpio)
		$(if $(SIGNING_MODE), \
			$(CP) image/fit/initrd.cpio $(tmpdir)/initrd.cpio \
		, \
			mkdir -p $(FIT_BIN_DIR); \
			$(CP) $(tmpdir)/initrd.cpio $(FIT_BIN_DIR) \
		)
		$(if $(CONFIG_VENUS_IMAGE_SIGN_ROOTFS),
			$(call ca-sign-rootfs,$(tmpdir),$(tmpdir)/initrd.cpio,$(3))
		)
		gzip -9nc $(tmpdir)/initrd.cpio > $(tmpdir)/initrd.cpio.gz
	)

	$(call ca-its,$(DEVICE_ITS_TEMPLATE),$(tmpdir)/kernel.its, \
		-D KERNEL_DATA=$(tmpdir)/kernel.bin.gz \
		-D KERNEL_COMPRESSION=gzip \
		-D KERNEL_LOADADDR=$(KERNEL_LOADADDR) \
		-D FDT_DATA=$(KDIR)/image-$(DEVICE_DTS).dtb \
		-D FDT_LOADADDR=$(DEVICE_DTS_LOADADDR) \
		$(if $(CONFIG_VENUS_IMAGE_ENCRYPT_ROOTFS), \
			-D INITRD_DATA=$(tmpdir)/initrd.cpio.gz \
		) \
	)
	$(if $(SIGNING_MODE), \
	, \
		mkdir -p $(FIT_BIN_DIR); \
		mkdir -p $(FIP_BIN_DIR)/boot/overlay/u-boot; \
		$(CP) $(IMAGE_KERNEL) $(FIT_BIN_DIR); \
		$(CP) $(KDIR)/image-$(DEVICE_DTS).dtb $(FIT_BIN_DIR); \
		$(CP) $(tmpdir)/kernel.its $(FIT_BIN_DIR); \
		$(CP) $(STAGING_DIR)/boot/overlay/u-boot/fit-pre-load.dtbo $(FIP_BIN_DIR)/boot/overlay/u-boot \
	)
	$(if $(filter "pg6692g" ,$(CONFIG_EXTRA_BOARD_NAME)), \
		mkdir -p $(4); \
		$(call CA/MergeDTB,$(4)/$(CA_MMC_UBOOT_PREFIX)-u-boot-with-keys.dtb, \
			$(STAGING_DIR_IMAGE)/$(CA_MMC_UBOOT_PREFIX)-u-boot.dtb, \
			$(STAGING_DIR)/boot/overlay/u-boot/fit-pre-load.dtbo); \
		$(eval fit_itb=$(tmpdir)/boot/kernel.fit) \
		PATH=$(LINUX_DIR)/scripts/dtc:$(PATH) \
			mkimage -k keys -K $(4)/$(CA_MMC_UBOOT_PREFIX)-u-boot-with-keys.dtb -f $(tmpdir)/kernel.its -r $(fit_itb); \
		cat $(fit_itb) | openssl dgst -sha256 -sign keys/fit-pre-load.key -out $(fit_itb).signature; \
		$(PYTHON) files/fit-pre-load.py $(fit_itb) $(fit_itb).signature $(fit_itb).header; \
		cat $(fit_itb).header | openssl dgst -sha256 -sign keys/fit-pre-load.key -out $(fit_itb).header.signature; \
		cat $(fit_itb).header $(fit_itb).header.signature $(fit_itb).signature $(fit_itb) > $(fit_itb).tmp; \
		mv $(fit_itb).tmp $(1) \
	, \
		PATH=$(LINUX_DIR)/scripts/dtc:$(PATH) \
			mkimage -k keys -f $(tmpdir)/kernel.its $(tmpdir)/boot/kernel.fit; \
		rm $(tmpdir)/boot/kernel.bin; \
		rm $(tmpdir)/boot/dtb.bin; \
		make_ext4fs -J -L boot -l "$(call ca_part_size,MMC_BOOT)" "$(1)" "$(tmpdir)/boot" \
	)
	rm -rf $(tmpdir)
endef

define ca-mmc-boot-img
	# build GPT
	ptgen -v -g -o $(1) \
		$(call ca_ptgen_partdef,MMC_FIP0,fip0, \
			-T $(CA_FIP_GUID) -A 48:1 $(ca_ptgen_fip_attr)) \
		$(call ca_ptgen_partdef,MMC_FIP1,fip1, \
			-T $(CA_FIP_GUID) $(ca_ptgen_fip_attr)) \
		$(call ca_ptgen_partdef,MMC_UBOOTENV,u-boot-env0) \
		$(call ca_ptgen_partdef,MMC_UBOOTENV,u-boot-env1) \
		$(call ca_ptgen_partdef,MMC_ART,art) \
		$(call ca_ptgen_partdef,MMC_FACTORY,factory) \
		$(call ca_ptgen_partdef,MMC_BOOT0,boot0) \
		$(call ca_ptgen_partdef,MMC_ROOTFS,rootfs0) \
		$(call ca_ptgen_partdef,MMC_BOOT1,boot1) \
		$(call ca_ptgen_partdef,MMC_ROOTFS,rootfs1) \
		$(call ca_ptgen_partdef,MMC_ROOTFS_DATA,rootfs_data0) \
		$(call ca_ptgen_partdef,MMC_ROOTFS_DATA,rootfs_data1) \
		$(call ca_ptgen_partdef,MMC_LOG,log) \
		$(call ca_ptgen_partdef,MMC_PSTORE,pstore) \
		$(if $(CA_MMC_LAST_USABLE_LBA), \
			-L $(CA_MMC_LAST_USABLE_LBA) \
		)

	# insert fip0 data
	$(call ca_insert_partdata,$(1),$(2),MMC_FIP0)

	# insert fip1 data
	$(call ca_insert_partdata,$(1),$(2),MMC_FIP1)

	# insert u-boot-env0 data
	$(call ca_insert_partdata,$(1),$(3),MMC_UBOOTENV)

	# insert u-boot-env1 data
	$(call ca_insert_partdata,$(1),$(3),MMC_UBOOTENV)
endef

$(eval CA_FW_ENC_KEY:=$(file <keys/fip.key))
# NOTE: nonce is not used for now as Cortina say
CA_FW_ENC_NONCE := 000000000000000000000000

define ca-encrypt-fw/copy
	$(CP) $(1) $(2)
endef

define ca-encrypt-fw/crypt
	$(call is_key_exist,keys/fip.key)
	$(STAGING_DIR_HOSTPKG)/bin/encrypt_fw -f 0 \
		-k $(CA_FW_ENC_KEY) -n $(CA_FW_ENC_NONCE) \
		-i $(1) -o $(2)
endef

# ca-fip - builds a fip image from BL2, BL31 and U-boot binaries
# $(1): target fip image
# $(2): board specific prefix for u-boot binaries in $(STAGING_DIR_IMAGE)
# $(3): path to u-boot dtb
define ca-fip
	$(eval FIP_TMP_DIR=$(1).fip_tmp)
	$(eval FIP_BIN_DIR=$(SIGNING_TOOLS_ROOT)/image/fip)
	mkdir -p $(FIP_TMP_DIR)
	mkdir -p $(3)

	cat $(STAGING_DIR_IMAGE)/$(2)-u-boot-nodtb.bin \
		$(3)/$(CA_MMC_UBOOT_PREFIX)-u-boot-with-keys.dtb > $(FIP_TMP_DIR)/u-boot.bin

	$(if $(SIGNING_MODE), \
	, \
		mkdir -p $(FIP_BIN_DIR); \
		$(CP) $(STAGING_DIR_IMAGE)/$(2)-u-boot.dtb $(FIP_BIN_DIR); \
		$(CP) $(STAGING_DIR_IMAGE)/$(2)-u-boot-nodtb.bin $(FIP_BIN_DIR); \
		$(CP) $(STAGING_DIR)/bl2.bin $(FIP_BIN_DIR); \
		$(CP) $(STAGING_DIR)/bl31.bin $(FIP_BIN_DIR); \
		$(if $(CONFIG_OPTEE_BOOTLOADER),$(CP) $(STAGING_DIR)/tee-pager_v2.bin $(FIP_BIN_DIR);) \
	)
	$(call ca-encrypt-fw/$(if $(CONFIG_VENUS_IMAGE_ENCRYPT_BL2),crypt,copy),\
		$(STAGING_DIR)/bl2.bin,$(FIP_TMP_DIR)/bl2.bin)
	$(call ca-encrypt-fw/$(if $(CONFIG_VENUS_IMAGE_ENCRYPT_BL31_BL33),crypt,copy),\
		$(STAGING_DIR)/bl31.bin,$(FIP_TMP_DIR)/bl31.bin)
	$(call ca-encrypt-fw/$(if $(CONFIG_VENUS_IMAGE_ENCRYPT_BL31_BL33),crypt,copy),\
		$(FIP_TMP_DIR)/u-boot.bin,$(FIP_TMP_DIR)/bl33.bin)
	$(if $(CONFIG_OPTEE_BOOTLOADER), \
		$(call ca-encrypt-fw/$(if $(CONFIG_VENUS_IMAGE_ENCRYPT_BL31_BL33),crypt,copy), \
			$(STAGING_DIR)/tee-pager_v2.bin,$(FIP_TMP_DIR)/tee-pager_v2.bin)
	)

	$(call is_key_exist,keys/rotprivk_rsa.pem)

	$(STAGING_DIR_HOSTPKG)/bin/cert_create -n \
		--tfw-nvctr 0  \
		--ntfw-nvctr 0  \
		--key-alg rsa \
		--rot-key keys/rotprivk_rsa.pem \
		--trusted-key-cert $(FIP_TMP_DIR)/rotpk.cert \
		--tb-fw $(FIP_TMP_DIR)/bl2.bin \
		--tb-fw-cert $(FIP_TMP_DIR)/tbfw.cert \
		--soc-fw $(FIP_TMP_DIR)/bl31.bin \
		--soc-fw-cert $(FIP_TMP_DIR)/socfw.cert \
		--soc-fw-key-cert $(FIP_TMP_DIR)/socfw_key.cert \
		--nt-fw-cert $(FIP_TMP_DIR)/ntfw.cert \
		--nt-fw-key-cert $(FIP_TMP_DIR)/ntfw_key.cert \
		$(if $(CONFIG_OPTEE_BOOTLOADER), \
			--tos-fw $(FIP_TMP_DIR)/tee-pager_v2.bin \
			--tos-fw-cert $(FIP_TMP_DIR)/tos_fw_content.crt \
			--tos-fw-key-cert $(FIP_TMP_DIR)/tos_fw_key.crt) \
		--nt-fw $(FIP_TMP_DIR)/bl33.bin

	$(STAGING_DIR_HOSTPKG)/bin/fiptool create \
		--trusted-key-cert $(FIP_TMP_DIR)/rotpk.cert \
		--tb-fw $(FIP_TMP_DIR)/bl2.bin \
		--tb-fw-cert $(FIP_TMP_DIR)/tbfw.cert \
		--soc-fw $(FIP_TMP_DIR)/bl31.bin \
		--soc-fw-cert $(FIP_TMP_DIR)/socfw.cert \
		--soc-fw-key-cert $(FIP_TMP_DIR)/socfw_key.cert \
		--nt-fw-cert $(FIP_TMP_DIR)/ntfw.cert \
		--nt-fw-key-cert $(FIP_TMP_DIR)/ntfw_key.cert \
		--nt-fw $(FIP_TMP_DIR)/bl33.bin \
		$(if $(CONFIG_OPTEE_BOOTLOADER), \
			--tos-fw-cert $(FIP_TMP_DIR)/tos_fw_content.crt \
			--tos-fw-key-cert $(FIP_TMP_DIR)/tos_fw_key.crt \
			--tos-fw $(FIP_TMP_DIR)/tee-pager_v2.bin) \
		$(1)
	rm -rf $(FIP_TMP_DIR)
endef

define Build/ca-mmc-boot-img
	# build boot partititon image. It is needed to add key into u-boot.dtb
	$(call ca_mmc_boot_part,$@.ca-boot.img,$@.ca-boot,$@.dtb)

	$(call ca-fip,$@.fip,$(CA_MMC_UBOOT_PREFIX),$@.dtb)

	$(call ca-mmc-boot-img,$@,$@.fip,\
		$(STAGING_DIR_IMAGE)/$(CA_MMC_UBOOT_PREFIX)-u-boot-env.bin)

	rm -f $@.fip $@.ca-boot.img
endef

define Build/ca-mmc-img
	# pad rootfs image to sector size
	dd if=$(IMAGE_ROOTFS) of=$@.rootfs bs=512 conv=sync

	# Generate rootfs before calling ca_mmc_boot_part
	$(if $(CONFIG_VENUS_IMAGE_ENCRYPT_ROOTFS), \
		$(call ca-dmcrypt-gen-xts,$@.rootfs) \
	)

	# build boot partititon image
	$(call ca_mmc_boot_part,$@.ca-boot.img,$@.ca-boot,$@.rootfs,$@.dtb)

	$(call ca-fip,$@.fip,$(CA_MMC_UBOOT_PREFIX),$@.dtb)

	$(call ca-mmc-boot-img,$@,$@.fip,\
		$(STAGING_DIR_IMAGE)/$(CA_MMC_UBOOT_PREFIX)-u-boot-env.bin)

	# insert boot0 image
	$(call ca_insert_partdata,$@,$@.ca-boot.img,MMC_BOOT0)

	$(if $(SIGNING_MODE),
		# "Signing mode is set. Do nothing
	,
		$(eval ROOTFS_BIN_DIR=$(SIGNING_TOOLS_ROOT)/image/rootfs)
		$(eval FIP_BIN_DIR=$(SIGNING_TOOLS_ROOT)/image/fip)
		mkdir -p $(ROOTFS_BIN_DIR)
		mkdir -p $(FIP_BIN_DIR)
		$(CP) $(IMAGE_ROOTFS) $(ROOTFS_BIN_DIR)
		$(CP) $(STAGING_DIR_IMAGE)/$(CA_MMC_UBOOT_PREFIX)-u-boot-env.bin $(FIP_BIN_DIR)
	)

	# append rootfs image
	$(call ca_insert_partdata,$@,$@.rootfs)

	rm -rf $@.fip $@.ca-boot.img $@.rootfs
endef

define Build/ca-mmc-u-boot
	$(call ca-fip,$@,$(CA_MMC_UBOOT_PREFIX),$@.dtb)
endef

define Build/ca-mmc-u-boot-env
	$(CP) $(STAGING_DIR_IMAGE)/$(CA_MMC_UBOOT_PREFIX)-u-boot-env.bin $@
endef

define Build/ca-nand-u-boot
	$(call ca-fip,$@.fip,$(CA_NAND_UBOOT_PREFIX),$@.dtb)

	# build GPT
	ptgen -v -g -o $@ \
		$(call ca_ptgen_partdef,NAND_FIP0,fip0, \
			-T $(CA_FIP_GUID) -A 48:1 $(ca_ptgen_fip_attr)) \
		$(call ca_ptgen_partdef,NAND_FIP1,fip1, \
			-T $(CA_FIP_GUID) $(ca_ptgen_fip_attr))

	# insert fip0 data
	$(call ca_insert_partdata,$@,$@.fip,NAND_FIP0)

	# insert fip1 data
	$(call ca_insert_partdata,$@,$@.fip,NAND_FIP1)

	rm -rf $@.fip
endef

define Build/ca-nand-u-boot-env
	$(CP) $(STAGING_DIR_IMAGE)/$(CA_NAND_UBOOT_PREFIX)-u-boot-env.bin $@
endef

define Build/ca-nand-info
	$(STAGING_DIR_HOSTPKG)/bin/gen_nand_info \
		$(CA_NAND_ECC_TYPE) $(CA_NAND_OOB_SIZE) \
		$(CA_NAND_PAGE_SIZE) $(CA_NAND_BLOCK_SIZE) $(CA_NAND_ADDR_LEN) \
		$@.nandinfo
	dd bs=512 conv=notrunc of=$@ if=$@.nandinfo
	rm -f $@.nandinfo
endef

define signing-tools-dir
	mkdir -p $(SIGNING_TOOLS_ROOT)
	mkdir -p $(SIGNING_TOOLS_ROOT)/include
	$(CP) $(TOPDIR)/.config $(SIGNING_TOOLS_ROOT)
	$(CP) signing-tools/signing-tools.mk $(SIGNING_TOOLS_ROOT)/include
	$(CP) signing-tools/Makefile $(SIGNING_TOOLS_ROOT)
	$(CP) signing-tools/README $(SIGNING_TOOLS_ROOT)
	$(CP) cortina.mk $(SIGNING_TOOLS_ROOT)
	$(CP) Makefile $(SIGNING_TOOLS_ROOT)/include
	$(file >$(SIGNING_TOOLS_ROOT)/image-prefix,$(IMG_PREFIX))

	$(eval SIGNING_TOOLS_HOST=$(SIGNING_TOOLS_ROOT)/host/bin)
	mkdir -p $(SIGNING_TOOLS_HOST)
	$(CP) $(STAGING_DIR_HOST)/bin/mkimage $(SIGNING_TOOLS_HOST)
	$(CP) $(STAGING_DIR_HOST)/bin/ptgen $(SIGNING_TOOLS_HOST)

	$(eval SIGNING_TOOLS_HOSTPKG=$(SIGNING_TOOLS_ROOT)/hostpkg/bin)
	mkdir -p $(SIGNING_TOOLS_HOSTPKG)
	$(CP) $(STAGING_DIR_HOSTPKG)/bin/cert_create $(SIGNING_TOOLS_HOSTPKG)
	$(CP) $(STAGING_DIR_HOSTPKG)/bin/dmcrypt_gen_xts $(SIGNING_TOOLS_HOSTPKG)
	$(CP) $(STAGING_DIR_HOSTPKG)/bin/encrypt_fw $(SIGNING_TOOLS_HOSTPKG)
	$(CP) $(STAGING_DIR_HOSTPKG)/bin/fiptool $(SIGNING_TOOLS_HOSTPKG)
	$(CP) $(STAGING_DIR_HOSTPKG)/bin/fdtoverlay $(SIGNING_TOOLS_HOSTPKG)

	mkdir -p $(SIGNING_TOOLS_ROOT)/scripts
	$(CP) $(LINUX_DIR)/scripts/dtc/dtc $(SIGNING_TOOLS_ROOT)/scripts

	mkdir -p $(SIGNING_TOOLS_ROOT)/files
	$(CP) files/fit-pre-load.py $(SIGNING_TOOLS_ROOT)/files

	# do not copy keys. This should be done by customer
	mkdir -p $(SIGNING_TOOLS_ROOT)/keys
endef

define Build/signing-tools-dir
	$(call signing-tools-dir)
	tar -cvzf $(BIN_DIR)/$(SIGNING_TOOLS_NAME).tar.gz -C $(BIN_DIR) $(SIGNING_TOOLS_NAME)
	#rm -rf $(BIN_DIR)/$(IMG_PREFIX)-signing-tools-$(SIGNING_TOOL_VERSION)
endef
