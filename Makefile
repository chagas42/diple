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
	codesign --force --sign - --identifier $(BUNDLE) $(DEST)
	@codesign -dv $(DEST) 2>&1 | sed -n '1,4p'

run: app stop
	open $(DEST)

stop:
	-@pkill -x $(APP) 2>/dev/null || true

clean:
	rm -rf .build build
