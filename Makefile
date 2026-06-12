BIN := $(HOME)/.local/bin/horae
PLIST := $(HOME)/Library/LaunchAgents/com.user.horae.plist
UID := $(shell id -u)

APP_DIR := app
APP_BUNDLE := $(APP_DIR)/Horae.app
APP_DEST := $(HOME)/Applications/Horae.app
DMG := dist/Horae.dmg

.PHONY: build test vet fmt lint check install uninstall app install-app uninstall-app dmg

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

# Menu bar app: assemble the .app bundle (release build + icons + embedded Sparkle.framework,
# ad-hoc signed with a stable designated requirement). See scripts/package-app.sh.
# Engine must be installed separately (make install).
app:
	bash scripts/package-app.sh

# Installable disk image: Horae.app + an /Applications symlink, compressed (UDZO).
dmg: app
	mkdir -p dist && rm -f $(DMG)
	$(eval STAGE := $(shell mktemp -d))
	cp -R $(APP_BUNDLE) $(STAGE)/
	ln -s /Applications $(STAGE)/Applications
	hdiutil create -volname Horae -srcfolder $(STAGE) -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov $(DMG)
	rm -rf $(STAGE)
	@echo "Built $(DMG)"

install-app: app
	rm -rf $(APP_DEST)
	mkdir -p $(HOME)/Applications
	cp -R $(APP_BUNDLE) $(APP_DEST)
	@echo "Installed $(APP_DEST). Open it; enable 开机自启 in settings to keep it resident."

uninstall-app:
	rm -rf $(APP_DEST)
	@echo "Removed $(APP_DEST)."
