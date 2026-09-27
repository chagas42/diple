APP    := Diple
BUNDLE := com.chagas42.diple
BUILD  := .build/release
DEST   := build/$(APP).app

.PHONY: build app run install stop clean

build:
	@swift build -c release 2>&1 | grep -vE "^\\[|warning:|^ *[0-9]+ \\||^ *\\||^$$" || true

app: build
	@rm -rf $(DEST)
	@mkdir -p $(DEST)/Contents/MacOS $(DEST)/Contents/Resources
	@cp $(BUILD)/$(APP) $(DEST)/Contents/MacOS/$(APP)
	@cp Resources/Info.plist $(DEST)/Contents/Info.plist
	@cp Resources/Diple.icns $(DEST)/Contents/Resources/Diple.icns
	@cp -R Resources/plugin $(DEST)/Contents/Resources/plugin
	@codesign --force --sign - --identifier $(BUNDLE) $(DEST) 2>/dev/null
	@echo "bundled  $(DEST)"

run: app stop
	@# LaunchServices guarda o ícone em cache; sem isto o Dock mostra o antigo.
	-@touch $(DEST)
	-@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
		-f $(DEST) 2>/dev/null || true
	-@killall usernoted 2>/dev/null || true
	open $(DEST)

install: app
	@rm -rf /Applications/$(APP).app
	@cp -R $(DEST) /Applications/$(APP).app
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
		-f /Applications/$(APP).app 2>/dev/null || true
	@killall usernoted 2>/dev/null || true
	@killall Dock 2>/dev/null || true
	@echo "installed  /Applications/$(APP).app"
	@echo
	@./.build/release/$(APP) --tools

icone:
	swift Resources/icone-fonte/gerar-icns.swift
	iconutil -c icns /tmp/Diple.iconset -o Resources/Diple.icns

stop:
	-@pkill -x $(APP) 2>/dev/null || true

clean:
	rm -rf .build build

gifmaker:
	@swiftc -O tools/gifmaker.swift -o build/gifmaker
	@echo "  build/gifmaker in.mp4 out.gif <fps> <width> [cropX cropY cropW cropH]"

film:
	@rm -rf build/film && mkdir -p build/film
	@./build/Diple.app/Contents/MacOS/Diple --demo --film build/film | tail -1
	@echo "  python3 tools/seq2gif.py build/film out.gif <from> <to> [width] [step]"

demo-reset:
	@pkill -x Diple 2>/dev/null || true
	@sleep 1
	@if [ -f "$$HOME/Library/Application Support/Diple/state.json" ]; then \
		mv "$$HOME/Library/Application Support/Diple/state.json" \
		   "$$HOME/Library/Application Support/Diple/state.before-demo.json"; \
		echo "  state.json set aside as state.before-demo.json"; \
	fi
	@rm -f "$$HOME/Library/Application Support/Diple/state-unreadable-"*.json
	@rm -f "$$HOME/Library/Application Support/Diple/map-timings.json"
	@if [ -d "$$HOME/.diple/worktrees" ]; then \
		for w in "$$HOME/.diple/worktrees/"*; do \
			[ -d "$$w" ] && rm -rf "$$w"; \
		done; \
		echo "  review worktrees cleared"; \
	fi
	@killall usernoted 2>/dev/null || true
	@killall Dock 2>/dev/null || true
	@echo "  clean. now: open /Applications/Diple.app --args --demo"

demo-restore:
	@pkill -x Diple 2>/dev/null || true
	@if [ -f "$$HOME/Library/Application Support/Diple/state.before-demo.json" ]; then \
		mv "$$HOME/Library/Application Support/Diple/state.before-demo.json" \
		   "$$HOME/Library/Application Support/Diple/state.json"; \
		echo "  your real state is back"; \
	else \
		echo "  nothing set aside to restore"; \
	fi
