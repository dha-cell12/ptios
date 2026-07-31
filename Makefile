# lipoplastic setup for armv6 + arm64 compilation
export ARCHS = arm64e arm64
#export THEOS_DEVICE_IP = 192.168.0.3
export TARGET = iphone:clang:latest:14.0

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

SUBPROJECTS = appdelegate tlinkauto-binary tlinkauto-jsd vpn-broker pccontrol

include $(THEOS)/makefiles/common.mk
include $(THEOS)/makefiles/aggregate.mk

after-install::
	install.exec "chown -R mobile:mobile /var/mobile/Library/TLinkauto && killall -9 SpringBoard;"

