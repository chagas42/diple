APP    := Diple
BUNDLE := com.chagas42.diple
BUILD  := .build/release
DEST   := build/$(APP).app

.PHONY: build app run install stop clean test tools probe bench bench-review bench-compare

LABEL       ?= current
BASE        ?= baseline
BENCH_OUT   := bench/results/$(LABEL)
BENCH_STATE := $(CURDIR)/build/bench-state
BENCH_ENV   := DIPLE_STATE_DIR=$(BENCH_STATE) DIPLE_BENCH_COMMIT=$$(git rev-parse --short HEAD)
BENCH_BIN   := $(DEST)/Contents/MacOS/$(APP)

test:
	swift test

tools: build
	@$(BUILD)/$(APP) --tools

probe: build
	@$(BUILD)/$(APP) --probe

bench: app
	@rm -rf $(BENCH_STATE) && mkdir -p $(BENCH_STATE) $(BENCH_OUT)
	@echo "  refresh (real GitHub, 10 cycles)"
	@$(BENCH_ENV) $(BENCH_BIN) --bench refresh --runs 10 --out $(BENCH_OUT)/refresh.json > /dev/null
	@echo "  launch (5 cold starts over a primed state)"
	@$(BENCH_ENV) $(BENCH_BIN) --bench launch --runs 5 --out $(BENCH_OUT)/launch.json > /dev/null
	@echo "  notch-idle (--demo, synthetic pointer at 30 Hz, 20 s)"
	@$(BENCH_ENV) $(BENCH_BIN) --demo --bench notch-idle --seconds 20 --runs 1 --out $(BENCH_OUT)/notch-idle.json > /dev/null
	@echo "  results in $(BENCH_OUT)"

bench-review: app
	@test -n "$(PR)" || (echo "  pass PR=owner/repo#number" && exit 1)
	@mkdir -p $(BENCH_OUT)
	@$(BENCH_ENV) $(BENCH_BIN) --bench review-start --pr "$(PR)" --runs 5 --out $(BENCH_OUT)/review-start.json > /dev/null
	@echo "  results in $(BENCH_OUT)/review-start.json"

bench-compare:
	@python3 tools/bench-compare.py bench/results/$(BASE) bench/results/$(LABEL)

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
