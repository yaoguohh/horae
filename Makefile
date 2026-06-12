BIN := $(HOME)/.local/bin/horae
PLIST := $(HOME)/Library/LaunchAgents/com.user.horae.plist
UID := $(shell id -u)

APP_DIR := app
APP_BUNDLE := $(APP_DIR)/Horae.app
APP_DEST := $(HOME)/Applications/Horae.app

.PHONY: build test vet fmt lint check install uninstall app install-app uninstall-app

build:
	go build -o horae .

test:
	go test ./...

vet:
	go vet ./...

fmt:
	golangci-lint fmt ./...

lint:
	golangci-lint run ./...

# Quality gate before commit / merge: static checks (incl. format) + tests.
check: vet lint test

install: build
	mkdir -p $(HOME)/.local/bin
	cp horae $(BIN)
	sed 's|__HOME__|$(HOME)|g' deploy/com.user.horae.plist > $(PLIST)
	launchctl bootout gui/$(UID)/com.user.horae 2>/dev/null || true
	launchctl bootstrap gui/$(UID) $(PLIST)
	@echo "Installed horae + LaunchAgent. Ensure ~/.config/horae/recipes.toml exists (see recipes.toml.example)."

uninstall:
	launchctl bootout gui/$(UID)/com.user.horae 2>/dev/null || true
	rm -f $(BIN) $(PLIST)
	@echo "Removed horae + LaunchAgent (config and logs under ~/.config and ~/Library/Logs kept)."

# Menu bar app: build SwiftUI executable, assemble .app bundle (Info.plist + icons),
# ad-hoc sign (personal use, no notarization). Engine must be installed separately (make install).
app:
	cd $(APP_DIR) && swift build -c release
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources/icons
	cp $(APP_DIR)/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp $(APP_DIR)/.build/release/Horae $(APP_BUNDLE)/Contents/MacOS/Horae
	cp $(APP_DIR)/Icons/*.png $(APP_BUNDLE)/Contents/Resources/icons/
	cp $(APP_DIR)/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	cp $(APP_DIR)/presets.json $(APP_BUNDLE)/Contents/Resources/presets.json
	codesign --force --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

install-app: app
	rm -rf $(APP_DEST)
	mkdir -p $(HOME)/Applications
	cp -R $(APP_BUNDLE) $(APP_DEST)
	@echo "Installed $(APP_DEST). Open it; enable 开机自启 in settings to keep it resident."

uninstall-app:
	rm -rf $(APP_DEST)
	@echo "Removed $(APP_DEST)."
