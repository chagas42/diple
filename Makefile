APP    := Diple
BUNDLE := com.chagas42.diple
BUILD  := .build/release
DEST   := build/$(APP).app

.PHONY: build app run install stop clean

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

install: app
	@# O Notification Center resolve o ícone por bundle id e guarda o caminho.
	@# Em build/ o bundle é apagado e recriado a cada compilação, então o
	@# registro aponta para um inode morto e o banner vem sem ícone.
	rm -rf /Applications/$(APP).app
	cp -R $(DEST) /Applications/$(APP).app
	-@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
		-f /Applications/$(APP).app 2>/dev/null || true
	-@killall usernoted 2>/dev/null || true
	-@killall Dock 2>/dev/null || true
	@echo "instalado em /Applications/$(APP).app"

icone:
	swift Resources/icone-fonte/gerar-icns.swift
	iconutil -c icns /tmp/Diple.iconset -o Resources/Diple.icns

stop:
	-@pkill -x $(APP) 2>/dev/null || true

clean:
	rm -rf .build build
