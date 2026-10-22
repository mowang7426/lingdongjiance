# Included by the root aggregate, not the child aggregate: operate on final stage.
after-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/usr/libexec" "$(THEOS_STAGING_DIR)/usr/share/doc/sbcpufloating"$(ECHO_END)
	$(ECHO_NOTHING)cp "$(THEOS_PROJECT_DIR)/hello120hz/install-filter.sh" "$(THEOS_STAGING_DIR)/usr/libexec/hello120hz-install"$(ECHO_END)
	$(ECHO_NOTHING)chmod 0755 "$(THEOS_STAGING_DIR)/usr/libexec/hello120hz-install"$(ECHO_END)
	$(ECHO_NOTHING)cp "$(THEOS_PROJECT_DIR)/hello120hz/SOURCE.md" "$(THEOS_PROJECT_DIR)/hello120hz/CAPABILITIES.md" "$(THEOS_STAGING_DIR)/usr/share/doc/sbcpufloating/"$(ECHO_END)
