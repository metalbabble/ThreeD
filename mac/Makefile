APP        = ThreeD
BUNDLE     = $(APP).app
BINARY     = .build/release/$(APP)
UNIVERSAL  = .build/universal/$(APP)
INFO_PLIST = Resources/Info.plist
# Keep in sync with the platform deployment target in Package.swift.
MACOS_MIN  = 14.0

.PHONY: build app bundle universal app-universal run debug clean icon

## Build release binary for the host architecture
build:
	swift build -c release

## Assemble the .app bundle from $(BINARY) and ad-hoc sign it
bundle:
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@mkdir -p $(BUNDLE)/Contents/Resources
	@cp $(BINARY)     $(BUNDLE)/Contents/MacOS/$(APP)
	@cp $(INFO_PLIST) $(BUNDLE)/Contents/Info.plist
	@cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	@codesign -s - --force $(BUNDLE)
	@echo "Built $(BUNDLE) ($$(lipo -archs $(BUNDLE)/Contents/MacOS/$(APP)))"

## Build + assemble the .app bundle for the host architecture
app: build
	@$(MAKE) bundle

## Build both architectures and merge them into one universal binary.
## Uses per-arch --triple builds plus lipo rather than SwiftPM's --arch, which
## requires a full Xcode install (xcbuild); this works with Command Line Tools alone.
universal:
	swift build -c release --triple arm64-apple-macosx$(MACOS_MIN)
	swift build -c release --triple x86_64-apple-macosx$(MACOS_MIN)
	@mkdir -p $(dir $(UNIVERSAL))
	@lipo -create -output $(UNIVERSAL) \
		.build/arm64-apple-macosx/release/$(APP) \
		.build/x86_64-apple-macosx/release/$(APP)

## Universal (Apple silicon + Intel) .app bundle, for distribution
app-universal: universal
	@$(MAKE) bundle BINARY=$(UNIVERSAL)

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
