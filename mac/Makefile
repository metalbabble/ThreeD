APP        = ThreeDViewer
BUNDLE     = $(APP).app
BINARY     = .build/release/$(APP)
INFO_PLIST = Resources/Info.plist

.PHONY: build app run debug clean icon

## Build release binary
build:
	swift build -c release

## Assemble .app bundle and ad-hoc sign it
app: build
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@mkdir -p $(BUNDLE)/Contents/Resources
	@cp $(BINARY)     $(BUNDLE)/Contents/MacOS/$(APP)
	@cp $(INFO_PLIST) $(BUNDLE)/Contents/Info.plist
	@cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	@codesign -s - --force $(BUNDLE)
	@echo "Built $(BUNDLE)"

## Build + open the app
run: app
	@open $(BUNDLE)

## Quick debug build (no bundle, runs in terminal)
debug:
	swift build
	.build/debug/$(APP)

## Remove build artifacts and bundle
clean:
	@rm -rf $(BUNDLE) .build
	@echo "Cleaned"

## Regenerate Resources/AppIcon.icns from the shared repo icon (../icon.png)
icon:
	@rm -rf AppIcon.iconset && mkdir AppIcon.iconset
	@for s in 16 32 128 256 512; do \
		sips -z $$s $$s ../icon.png --out AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
		d=$$((s*2)); sips -z $$d $$d ../icon.png --out AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	@iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
	@rm -rf AppIcon.iconset
	@echo "Regenerated Resources/AppIcon.icns"
