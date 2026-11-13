# Rootful remains the default. Rootless uses the standard /var/jb scheme;
# Roothide uses RootHide's separate bootstrap scheme and Debian architecture.
TLINK_PACKAGE_RUNTIME ?= rootfull
ifeq ($(TLINK_PACKAGE_RUNTIME),roothide)
export THEOS_PACKAGE_SCHEME = roothide
export DEB_ARCH = iphoneos-arm64e
export ARCHS = arm64
export TARGET = iphone:clang:latest:15.0
export IPHONEOS_DEPLOYMENT_TARGET = 15.0
TLINK_ROOTHIDE_RUNTIME := 1
TLINK_ROOTLESS_RUNTIME := 0
else ifeq ($(TLINK_PACKAGE_RUNTIME),rootless)
export THEOS_PACKAGE_SCHEME = rootless
export DEB_ARCH = iphoneos-arm64
export ARCHS = arm64
export TARGET = iphone:clang:latest:15.0
export IPHONEOS_DEPLOYMENT_TARGET = 15.0
TLINK_ROOTHIDE_RUNTIME := 0
TLINK_ROOTLESS_RUNTIME := 1
else ifeq ($(TLINK_PACKAGE_RUNTIME),rootfull)
export ARCHS = arm64e arm64
export TARGET = iphone:clang:latest:14.0
TLINK_ROOTHIDE_RUNTIME := 0
TLINK_ROOTLESS_RUNTIME := 0
else
$(error TLINK_PACKAGE_RUNTIME must be rootfull, roothide or rootless)
endif
export TLINK_PACKAGE_RUNTIME
export TLINK_ROOTHIDE_RUNTIME
export TLINK_ROOTLESS_RUNTIME

TLINK_LICENSE_MODE ?= observe
ifeq ($(TLINK_LICENSE_MODE),enforced)
TLINK_LICENSE_FORCE_ENFORCEMENT := 1
else ifeq ($(TLINK_LICENSE_MODE),observe)
TLINK_LICENSE_FORCE_ENFORCEMENT := 0
else
$(error TLINK_LICENSE_MODE must be observe or enforced)
endif
export TLINK_LICENSE_MODE
export TLINK_LICENSE_FORCE_ENFORCEMENT

SUBPROJECTS = appdelegate license-authority tlinkauto-binary tlinkauto-jsd vpn-broker pccontrol

include $(THEOS)/makefiles/common.mk
include $(THEOS)/makefiles/aggregate.mk

before-package::
ifeq ($(TLINK_PACKAGE_RUNTIME),roothide)
	node "$(THEOS_PROJECT_DIR)/scripts/prepare-roothide-stage.mjs" --rootfs "$(THEOS_STAGING_DIR)"
else ifeq ($(TLINK_PACKAGE_RUNTIME),rootless)
	node "$(THEOS_PROJECT_DIR)/scripts/prepare-rootless-stage.mjs" --rootfs "$(THEOS_STAGING_DIR)"
endif

after-install::
	install.exec "TLINK_DATA_ROOT=/var/mobile/Library/TLinkauto; if [ -d /rootfs/var/mobile ]; then TLINK_DATA_ROOT=/rootfs/var/mobile/Library/TLinkauto; fi; chown -R mobile:mobile \$$TLINK_DATA_ROOT; killall -9 SpringBoard;"

