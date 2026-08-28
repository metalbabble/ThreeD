# ThreeD for macOS

A native macOS viewer for 3D-printing model files. SwiftUI + SceneKit.

## Supported formats

- **3MF** — custom parser: core spec, build/component transforms, and the
  production extension's `p:path` part references (used by Bambu Studio / Orca project files)
- **STL** — binary and ASCII
- **glTF / GLB** — via SceneKit's native loader

## Usage

- `Open…` (⌘O), drag a file onto the window or the app icon, or double-click
  an associated file in Finder
- Rotate / zoom / pan with the standard SceneKit camera controls

## Requirements

- macOS 14 or later
- Xcode / Swift 5.9+ toolchain (`swift --version`)

## Build

The project uses the Swift Package Manager. A `Makefile` wraps the common commands.

```sh
# Quick debug build, runs directly in the terminal (no .app bundle)
make debug

# Release build only (produces .build/release/ThreeD)
make build

# Build and assemble a signed ThreeD.app bundle
make app

# Build the .app bundle and launch it
make run

# Universal (Apple silicon + Intel) bundle, as shipped in releases
make app-universal

# Regenerate Resources/AppIcon.icns from the shared repo icon (../icon.png)
make icon
```

`make app` copies the release binary, `Resources/Info.plist`, and
`Resources/AppIcon.icns` into `ThreeD.app/Contents`, then ad-hoc
code-signs the bundle with `codesign`.

`make app-universal` builds both architectures and merges them with `lipo`
before assembling the same bundle. It deliberately uses per-architecture
`--triple` builds instead of SwiftPM's `--arch` flag, which needs a full Xcode
install; the `lipo` route works with Command Line Tools alone.

The Info.plist declares the app as a viewer for 3MF, STL, and glTF/GLB files,
so once the app has been launched (or registered with `lsregister`), those
files can be opened from Finder by double-click or by dragging onto the app icon.

## Releases

Pushes to `main` that touch `mac/` publish a universal `ThreeD-macos.zip`
via [release-mac.yml](../.github/workflows/release-mac.yml). Because the bundle is
ad-hoc signed rather than signed with a paid Developer ID, Gatekeeper blocks a
downloaded copy until it is de-quarantined:

```sh
xattr -dr com.apple.quarantine /Applications/ThreeD.app
```

## Samples

Shared test files live in [`../samples`](../samples): `cube.stl`, `cube.3mf`
(two cubes exercising components, transforms, and material colors), `triangle.gltf`.

## Clean

```sh
make clean
```

Removes `ThreeD.app` and the `.build` directory.
