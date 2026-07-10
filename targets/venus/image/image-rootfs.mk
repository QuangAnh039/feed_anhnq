define Image/Prepare/Rootfs
	$(call Target/Rootfs/Customize)
	if [ -d $(PLATFORM_DIR)/rootfs-patch/. ]; then \
		$(RM) $(TARGET_DIR)/etc/env.d/*; \
		$(CP) $(PLATFORM_DIR)/rootfs-patch/* $(TARGET_DIR)/; \
	fi

	$(eval PROJECT_CUSTOMIZATION_PKG:=$(file <$(TMP_DIR)/.project_customization_pkg))
	$(eval $(if $(PROJECT_CUSTOMIZATION_PKG), $(eval include $(PROJECT_CUSTOMIZATION_PKG)/customize.mk),))

	$(call Project/Rootfs/Customize)
	if [ -d $(PROJECT_CUSTOMIZATION_PKG)/rootfs-patch/. ]; then \
		$(CP) $(PROJECT_CUSTOMIZATION_PKG)/rootfs-patch/* $(TARGET_DIR)/; \
	fi
	
ifdef CONFIG_DEVELOPMENT_RELEASE
	$(call Target/Rootfs/Customize/Debug)
	if [ -d $(PLATFORM_DIR)/rootfs-patch-dev/. ]; then \
		$(CP) $(PLATFORM_DIR)/rootfs-patch-dev/* $(TARGET_DIR)/; \
	fi

	$(call Project/Rootfs/Customize/Debug)
	if [ -d $(PROJECT_CUSTOMIZATION_PKG)/rootfs-patch-dev/. ]; then \
		$(CP) $(PROJECT_CUSTOMIZATION_PKG)/rootfs-patch-dev/* $(TARGET_DIR)/; \
	fi
endif

ifdef CONFIG_MANUFACTURING_RELEASE
	if [ -d $(PLATFORM_DIR)/rootfs-patch-manufacturing/. ]; then \
		$(CP) $(PLATFORM_DIR)/rootfs-patch-manufacturing/* $(TARGET_DIR)/; \
	fi

	if [ -d $(PROJECT_CUSTOMIZATION_PKG)/rootfs-patch-manufacturing/. ]; then \
		$(CP) $(PROJECT_CUSTOMIZATION_PKG)/rootfs-patch-manufacturing/* $(TARGET_DIR)/; \
	fi
endif

endef
