APP    := Diple
BUNDLE := com.chagas42.diple
BUILD  := .build/release
DEST   := build/$(APP).app

.PHONY: build app run stop clean

build:
	swift build -c release

app: build
	rm -rf $(DEST)
	mkdir -p $(DEST)/Contents/MacOS $(DEST)/Contents/Resources
	cp $(BUILD)/$(APP) $(DEST)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(DEST)/Contents/Info.plist
	cp Resources/Diple.icns $(DEST)/Contents/Resources/Diple.icns
	codesign --force --sign - --identifier $(BUNDLE) $(DEST)
	@codesign -dv $(DEST) 2>&1 | sed -n '1,4p'

run: app stop
	@# LaunchServices guarda o ícone em cache; sem isto o Dock mostra o antigo.
	-@touch $(DEST)
	-@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
		-f $(DEST) 2>/dev/null || true
	-@killall usernoted 2>/dev/null || true
	open $(DEST)

icone:
	swift Resources/icone-fonte/gerar-icns.swift
	iconutil -c icns /tmp/Diple.iconset -o Resources/Diple.icns

stop:
	-@pkill -x $(APP) 2>/dev/null || true

clean:
	rm -rf .build build
