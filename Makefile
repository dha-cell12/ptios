# lipoplastic setup for armv6 + arm64 compilation
export ARCHS = arm64e arm64
#export THEOS_DEVICE_IP = 192.168.0.3
export TARGET = iphone:clang:latest:14.0

SUBPROJECTS = appdelegate tlinkauto-binary tlinkauto-jsd pccontrol

include $(THEOS)/makefiles/common.mk
include $(THEOS)/makefiles/aggregate.mk

after-install::
	install.exec "chown -R mobile:mobile /var/mobile/Library/TLinkauto && killall -9 SpringBoard;"

