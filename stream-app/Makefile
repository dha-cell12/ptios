# stream-app aggregate build
#
# Builds streamd + clipboardd + StreamControl.app, embeds the services, and
# packages a TrollStore-compatible .tipa at packages/StreamControl.tipa.

APP_NAME := StreamControl
APP_BUNDLE := StreamControl.app
TIPA := packages/$(APP_NAME).tipa
PAYLOAD_DIR := _payload/Payload

.PHONY: all streamd clipboardd app privhelper embed package clean

all: package

streamd:
	$(MAKE) -C streamd stage FINALPACKAGE=1

clipboardd:
	$(MAKE) -C clipboardd stage FINALPACKAGE=1

app:
	$(MAKE) -C app stage FINALPACKAGE=1

privhelper:
	$(MAKE) -C privhelper stage FINALPACKAGE=1

embed: streamd clipboardd app privhelper
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
	PRIVHELPER="privhelper/.theos/_/usr/bin/privhelper"; \
	if [ ! -f "$$PRIVHELPER" ]; then \
	  PRIVHELPER=$$(find privhelper/.theos -maxdepth 8 -type f -name 'privhelper' ! -path '*/dSYM/*' | head -n1); \
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
	if [ ! -f "$$APP/Info.plist" ]; then \
	  cp app/Info.plist "$$APP/Info.plist"; \
	fi; \
	cp "$$STREAMD" "$$APP/streamd"; \
	chmod 755 "$$APP/streamd"; \
	cp "$$CLIPBOARDD" "$$APP/clipboardd"; \
	chmod 755 "$$APP/clipboardd"; \
	cp "$$PRIVHELPER" "$$APP/privhelper"; \
	chmod 755 "$$APP/privhelper"; \
	rm -rf "$$APP/CompatibilityExamples"; \
	cp -R app/CompatibilityExamples "$$APP/CompatibilityExamples"; \
	if command -v ldid >/dev/null 2>&1; then \
	  ldid -Sstreamd/entitlements.plist "$$APP/streamd"; \
	  ldid -Sclipboardd/entitlements.plist "$$APP/clipboardd"; \
	  ldid -Sapp/entitlements.plist "$$APP/privhelper"; \
	  ldid -Sapp/entitlements.plist "$$APP/$(APP_NAME)"; \
	fi; \
	test -f "$$APP/Info.plist"; \
	test -x "$$APP/$(APP_NAME)"; \
	test -x "$$APP/streamd"; \
	test -x "$$APP/clipboardd"; \
	test -x "$$APP/privhelper"; \
	test -f "$$APP/CompatibilityExamples/01 Runtime Storage.js"; \
	test -f "$$APP/CompatibilityExamples/06 App Process Shell.js"; \
	test -f "$$APP/CompatibilityExamples/07 File Handle.js"; \
	echo "Embedded streamd and clipboardd into $$APP"

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
	test -x "$(PAYLOAD_DIR)/$(APP_BUNDLE)/privhelper"; \
	test -f "$(PAYLOAD_DIR)/$(APP_BUNDLE)/CompatibilityExamples/01 Runtime Storage.js"; \
	test -f "$(PAYLOAD_DIR)/$(APP_BUNDLE)/CompatibilityExamples/07 File Handle.js"; \
	( cd _payload && zip -qr9 ../$(TIPA) Payload ); \
	echo "Created $(TIPA)"

clean:
	-$(MAKE) -C streamd clean
	-$(MAKE) -C clipboardd clean
	-$(MAKE) -C app clean
	-$(MAKE) -C privhelper clean
	rm -rf _payload packages
