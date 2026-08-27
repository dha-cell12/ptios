# stream-app aggregate build
#
# Builds streamd + clipboardd + TLinkUIService.app + StreamControl.app + WidgetKit extension, embeds them, and
# packages a TrollStore-compatible .tipa at packages/StreamControl.tipa.

APP_NAME := StreamControl
APP_BUNDLE := StreamControl.app
TIPA := packages/$(APP_NAME).tipa
PAYLOAD_DIR := _payload/Payload
TLINK_SWIFT_COMPILER := $(shell command -v swift 2>/dev/null)
TLINK_SWIFT_SUPPORT_DIR := $(THEOS)/vendor/swift-support
TLINK_SWIFT_OUTPUT_MAP_TOOL := $(TLINK_SWIFT_SUPPORT_DIR)/.theos_build/release/generate-output-file-map

.PHONY: all streamd clipboardd uiservice vpnagent app privhelper swift-support widget embed package clean

all: package

streamd:
	$(MAKE) -C streamd stage FINALPACKAGE=1

clipboardd:
	$(MAKE) -C clipboardd stage FINALPACKAGE=1

uiservice:
	$(MAKE) -C uiservice stage FINALPACKAGE=1

vpnagent:
	$(MAKE) -C vpnagent stage FINALPACKAGE=1

app:
	$(MAKE) -C app stage FINALPACKAGE=1

privhelper:
	$(MAKE) -C privhelper stage FINALPACKAGE=1

swift-support:
	@test -n "$(TLINK_SWIFT_COMPILER)" || { echo "ERROR: Swift compiler not found in PATH"; exit 1; }
	@test -x "$(THEOS)/bin/swift-bootstrapper.pl" || { echo "ERROR: Theos swift-bootstrapper.pl not found"; exit 1; }
	@test -f "$(TLINK_SWIFT_SUPPORT_DIR)/Package.swift" || { echo "ERROR: Theos swift-support submodule is missing; clone Theos recursively"; exit 1; }
	@if [ ! -x "$(TLINK_SWIFT_OUTPUT_MAP_TOOL)" ]; then \
	  echo "Bootstrapping Theos Swift support"; \
	  THEOS_NO_SWIFT_CACHE=2 "$(THEOS)/bin/swift-bootstrapper.pl" \
	    "$(TLINK_SWIFT_COMPILER)" "$(TLINK_SWIFT_SUPPORT_DIR)" \
	    'echo "Building Theos Swift support tools"'; \
	fi
	@test -x "$(TLINK_SWIFT_OUTPUT_MAP_TOOL)" || { echo "ERROR: generate-output-file-map was not built"; exit 1; }

widget: swift-support
	$(MAKE) -C widget stage FINALPACKAGE=1 THEOS_USE_PARALLEL_BUILDING=0

embed: streamd clipboardd uiservice vpnagent app privhelper widget
	@set -e; \
	APP="app/.theos/_/Applications/$(APP_BUNDLE)"; \
	if [ ! -d "$$APP" ]; then \
	  APP=$$(find app/.theos/_ -maxdepth 8 -name '$(APP_BUNDLE)' -type d | head -n1); \
	fi; \
	STREAMD="streamd/.theos/_/usr/bin/streamd"; \
	if [ ! -f "$$STREAMD" ]; then \
	  STREAMD=$$(find streamd/.theos -maxdepth 8 -type f -name 'streamd' ! -path '*/dSYM/*' | head -n1); \
	fi; \
	CLIPBOARDD="clipboardd/.theos/_/usr/bin/clipboardd"; \
	if [ ! -f "$$CLIPBOARDD" ]; then \
	  CLIPBOARDD=$$(find clipboardd/.theos -maxdepth 8 -type f -name 'clipboardd' ! -path '*/dSYM/*' | head -n1); \
	fi; \
	UISERVICE="uiservice/.theos/_/usr/bin/TLinkUIService"; \
	if [ ! -f "$$UISERVICE" ]; then \
	  UISERVICE=$$(find uiservice/.theos -maxdepth 8 -type f -name 'TLinkUIService' ! -path '*/dSYM/*' | head -n1); \
	fi; \
	VPNAGENT="vpnagent/.theos/_/usr/bin/vpnagent"; \
	if [ ! -f "$$VPNAGENT" ]; then \
	  VPNAGENT=$$(find vpnagent/.theos -maxdepth 8 -type f -name 'vpnagent' ! -path '*/dSYM/*' | head -n1); \
	fi; \
	PRIVHELPER="privhelper/.theos/_/usr/bin/privhelper"; \
	if [ ! -f "$$PRIVHELPER" ]; then \
	  PRIVHELPER=$$(find privhelper/.theos -maxdepth 8 -type f -name 'privhelper' ! -path '*/dSYM/*' | head -n1); \
	fi; \
	WIDGET="widget/.theos/_/Applications/$(APP_BUNDLE)/PlugIns/TLinkBootWidget.appex"; \
	if [ ! -d "$$WIDGET" ]; then \
	  WIDGET=$$(find widget/.theos/_ -maxdepth 10 -name 'TLinkBootWidget.appex' -type d | head -n1); \
	fi; \
	if [ -z "$$APP" ] || [ ! -d "$$APP" ]; then \
	  echo "ERROR: $(APP_BUNDLE) not found"; exit 1; \
	fi; \
	if [ -z "$$STREAMD" ] || [ ! -f "$$STREAMD" ]; then \
	  echo "ERROR: streamd executable not found"; exit 1; \
	fi; \
	if [ -z "$$PRIVHELPER" ] || [ ! -f "$$PRIVHELPER" ]; then \
	  echo "ERROR: privhelper executable not found"; exit 1; \
	fi; \
	if [ -z "$$CLIPBOARDD" ] || [ ! -f "$$CLIPBOARDD" ]; then \
	  echo "ERROR: clipboardd executable not found"; exit 1; \
	fi; \
	if [ -z "$$UISERVICE" ] || [ ! -f "$$UISERVICE" ]; then \
	  echo "ERROR: TLinkUIService executable not found"; exit 1; \
	fi; \
	if [ -z "$$VPNAGENT" ] || [ ! -f "$$VPNAGENT" ]; then \
	  echo "ERROR: vpnagent executable not found"; exit 1; \
	fi; \
	if [ -z "$$WIDGET" ] || [ ! -d "$$WIDGET" ] || [ ! -x "$$WIDGET/TLinkBootWidget" ]; then \
	  echo "ERROR: TLinkBootWidget.appex not found"; exit 1; \
	fi; \
	if [ ! -f "$$APP/Info.plist" ]; then \
	  cp app/Info.plist "$$APP/Info.plist"; \
	fi; \
	cp "$$STREAMD" "$$APP/streamd"; \
	chmod 755 "$$APP/streamd"; \
	cp "$$CLIPBOARDD" "$$APP/clipboardd"; \
	chmod 755 "$$APP/clipboardd"; \
	rm -rf "$$APP/TLinkUIService.app"; \
	mkdir -p "$$APP/TLinkUIService.app"; \
	cp "$$UISERVICE" "$$APP/TLinkUIService.app/TLinkUIService"; \
	cp uiservice/Info.plist "$$APP/TLinkUIService.app/Info.plist"; \
	chmod 755 "$$APP/TLinkUIService.app/TLinkUIService"; \
	cp "$$VPNAGENT" "$$APP/vpnagent"; \
	chmod 755 "$$APP/vpnagent"; \
	cp "$$PRIVHELPER" "$$APP/privhelper"; \
	chmod 755 "$$APP/privhelper"; \
	mkdir -p "$$APP/PlugIns"; \
	rm -rf "$$APP/PlugIns/TLinkBootWidget.appex"; \
	cp -R "$$WIDGET" "$$APP/PlugIns/TLinkBootWidget.appex"; \
	rm -rf "$$APP/CompatibilityExamples"; \
	cp -R app/CompatibilityExamples "$$APP/CompatibilityExamples"; \
	if command -v ldid >/dev/null 2>&1; then \
	  ldid -Sstreamd/entitlements.plist "$$APP/streamd"; \
	  ldid -Sclipboardd/entitlements.plist "$$APP/clipboardd"; \
	  ldid -Suiservice/entitlements.plist "$$APP/TLinkUIService.app/TLinkUIService"; \
	  ldid -Svpnagent/entitlements.plist "$$APP/vpnagent"; \
	  ldid -Sapp/entitlements.plist "$$APP/privhelper"; \
	  ldid -Swidget/entitlements.plist "$$APP/PlugIns/TLinkBootWidget.appex/TLinkBootWidget"; \
	  ldid -Sapp/entitlements.plist "$$APP/$(APP_NAME)"; \
	fi; \
	test -f "$$APP/Info.plist"; \
	test -x "$$APP/$(APP_NAME)"; \
	test -x "$$APP/streamd"; \
	test -x "$$APP/clipboardd"; \
	test -f "$$APP/TLinkUIService.app/Info.plist"; \
	test -x "$$APP/TLinkUIService.app/TLinkUIService"; \
	test -x "$$APP/vpnagent"; \
	test -x "$$APP/privhelper"; \
	test -f "$$APP/PlugIns/TLinkBootWidget.appex/Info.plist"; \
	test -x "$$APP/PlugIns/TLinkBootWidget.appex/TLinkBootWidget"; \
	test -f "$$APP/LicenseConfig.plist"; \
	test -f "$$APP/CompatibilityExamples/01 Runtime Storage.js"; \
	test -f "$$APP/CompatibilityExamples/06 App Process Shell.js"; \
	test -f "$$APP/CompatibilityExamples/07 File Handle.js"; \
	test -f "$$APP/CompatibilityExamples/09 Smart Wait.js"; \
	test -f "$$APP/CompatibilityExamples/10 Failure Evidence.js"; \
	echo "Embedded streamd, clipboardd, TLinkUIService.app, vpnagent, and TLinkBootWidget into $$APP"

package: embed
	@set -e; \
	APP="app/.theos/_/Applications/$(APP_BUNDLE)"; \
	if [ ! -d "$$APP" ]; then \
	  APP=$$(find app/.theos/_ -maxdepth 8 -name '$(APP_BUNDLE)' -type d | head -n1); \
	fi; \
	rm -rf _payload packages; \
	mkdir -p "$(PAYLOAD_DIR)" packages; \
	cp -R "$$APP" "$(PAYLOAD_DIR)/$(APP_BUNDLE)"; \
	test -f "$(PAYLOAD_DIR)/$(APP_BUNDLE)/Info.plist"; \
	test -x "$(PAYLOAD_DIR)/$(APP_BUNDLE)/$(APP_NAME)"; \
	test -x "$(PAYLOAD_DIR)/$(APP_BUNDLE)/streamd"; \
	test -x "$(PAYLOAD_DIR)/$(APP_BUNDLE)/clipboardd"; \
	test -f "$(PAYLOAD_DIR)/$(APP_BUNDLE)/TLinkUIService.app/Info.plist"; \
	test -x "$(PAYLOAD_DIR)/$(APP_BUNDLE)/TLinkUIService.app/TLinkUIService"; \
	test -x "$(PAYLOAD_DIR)/$(APP_BUNDLE)/vpnagent"; \
	test -x "$(PAYLOAD_DIR)/$(APP_BUNDLE)/privhelper"; \
	test -f "$(PAYLOAD_DIR)/$(APP_BUNDLE)/PlugIns/TLinkBootWidget.appex/Info.plist"; \
	test -x "$(PAYLOAD_DIR)/$(APP_BUNDLE)/PlugIns/TLinkBootWidget.appex/TLinkBootWidget"; \
	test -f "$(PAYLOAD_DIR)/$(APP_BUNDLE)/LicenseConfig.plist"; \
	test -f "$(PAYLOAD_DIR)/$(APP_BUNDLE)/CompatibilityExamples/01 Runtime Storage.js"; \
	test -f "$(PAYLOAD_DIR)/$(APP_BUNDLE)/CompatibilityExamples/07 File Handle.js"; \
	test -f "$(PAYLOAD_DIR)/$(APP_BUNDLE)/CompatibilityExamples/09 Smart Wait.js"; \
	test -f "$(PAYLOAD_DIR)/$(APP_BUNDLE)/CompatibilityExamples/10 Failure Evidence.js"; \
	( cd _payload && zip -qr9 ../$(TIPA) Payload ); \
	echo "Created $(TIPA)"

clean:
	-$(MAKE) -C streamd clean
	-$(MAKE) -C clipboardd clean
	-$(MAKE) -C uiservice clean
	-$(MAKE) -C vpnagent clean
	-$(MAKE) -C app clean
	-$(MAKE) -C privhelper clean
	-$(MAKE) -C widget clean
	rm -rf _payload packages
