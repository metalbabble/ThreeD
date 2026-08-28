# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project intent

ThreeD is a small standalone viewer for 3D-printing model files (3MF, STL,
glTF/GLB) — a quick way to preview these formats without launching a full
slicer. It ships as two independent native apps that should stay in feature
parity:

| Platform | Directory | Stack |
|----------|-----------|-------|
| Windows  | [windows/](windows/) | WPF (.NET 10) + Helix Toolkit |
| macOS    | [mac/](mac/) | SwiftUI + SceneKit |

**Any new feature (a new file format, a viewer interaction, an importer
fix that affects parsing behavior, etc.) should be implemented on both
platforms**, not just one, unless the user says otherwise. The two codebases
share no code — parity means re-implementing the same behavior twice, once
per stack.

`samples/` holds tiny model files (`cube.stl`, `cube.3mf`, `triangle.gltf`)
shared by both apps for manual testing.

## Versioning

**Any change should bump the app's version number.**

- macOS: `CFBundleShortVersionString` / `CFBundleVersion` in
  [mac/Resources/Info.plist](mac/Resources/Info.plist) are maintained by
  hand — bump these on any change to `mac/`.
- Windows: `windows/ThreeD.csproj` currently declares no explicit
  `<Version>`/`<AssemblyVersion>`; the published release is tagged with the
  CI run number instead (see Releases below). If a manual version property
  is added there in the future, bump it the same way.

## Build & run

### Windows (`windows/`)

```sh
dotnet build ThreeD.csproj
```

Standalone single-file exe (matches what CI publishes):

```sh
dotnet publish ThreeD.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true
```

Run directly: `ThreeD.exe <file>`. Headless snapshot mode (renders a model to
PNG without a window):

```sh
ThreeD.exe --snapshot <model> <output.png> [width height]
```

There is no test suite for either platform.

### macOS (`mac/`)

A `Makefile` wraps SwiftPM:

```sh
make debug          # quick debug build, runs directly in terminal (no .app bundle)
make build           # release build only -> .build/release/ThreeD
make app             # build + assemble signed ThreeD.app bundle
make run              # build app and launch it
make app-universal   # Apple silicon + Intel universal bundle, as shipped in releases
make icon            # regenerate Resources/AppIcon.icns from ../icon.png
make clean            # remove ThreeD.app and .build
```

`make app-universal` builds each architecture separately with per-arch
`--triple` (not SwiftPM's `--arch`, which needs a full Xcode install) and
merges them with `lipo`, so it works with Command Line Tools alone.

## Architecture

### Format support asymmetry

Both apps read **3MF** (core spec, build/component transforms, base-material
colors, and the production extension's `p:path` part references used by
Bambu Studio / Orca project files), **STL**, and **glTF/GLB**. 3MF and STL
are hand-rolled parsers on both platforms — there is no shared or
third-party 3MF reader. Windows additionally reads OBJ, PLY, OFF, 3DS, and
LWO via Helix Toolkit's built-in importers, and has a headless
`--snapshot` mode; macOS has neither. Keep this asymmetry in mind when a
"support format X" request comes in — it may only need to land on one
platform, but always check both READMEs to confirm current parity before
assuming.

### macOS (`mac/Sources/ThreeD/`)

- `ViewerModel` (`ViewerModel.swift`) is the single piece of shared state
  (`ObservableObject`, `@MainActor`) for the one viewer window. It exists
  outside the view specifically so that files arriving via three different
  entry points — the Open panel, a window drop, and Finder's open-URLs
  Apple event (double-click / drag onto the app icon) — all funnel into the
  same `load(url:)` call.
- Parsing runs off the main actor (`Task.detached`) since a large mesh parse
  is slow enough to block the redraw that shows the loading state. A
  monotonic `loadToken` guards against a slow, superseded load overwriting a
  newer one when it finishes late.
- `loadScene(from:)` dispatches by file extension to `ThreeMFParser`,
  `STLParser` (both in `Parsers/`), or SceneKit's native glTF/GLB loader.
- `AppDelegate.application(_:open:)` in `ThreeDApp.swift` is what Finder
  calls for double-click/drag-onto-icon; it forwards straight to
  `ViewerModel.shared.load(url:)`.

### Windows (`windows/`)

- `MainWindow.xaml.cs` owns UI state directly (no MVVM layer) — file
  loading, camera reset, the ground grid, and drag-and-drop all live here.
  `OpenFileAsync` is the single load path used by the Open dialog, drag-drop,
  and command-line file args (`OpenFileWhenLoaded`).
- `ModelLoader` (`Importers/ModelLoader.cs`) dispatches by extension to
  `ThreeMfImporter`, `GltfImporter`, or Helix Toolkit's `ModelImporter` for
  everything else, then freezes the resulting `Model3DGroup`.
- `PositionGrid` computes a ground grid sized/stepped relative to the
  loaded model's bounds (powers-of-ten step, snapped to a "nice" multiple)
  rather than a fixed size.
- `Snapshot.cs` implements `--snapshot` for headless PNG rendering, invoked
  from `App.xaml.cs` before any window is shown.

## Releases

Both platforms publish automatically from `main`, each triggered only when
its own platform directory (or the shared `icon.png`) changes — see
[release-windows.yml](.github/workflows/release-windows.yml) and
[release-mac.yml](.github/workflows/release-mac.yml). Windows tags
`win-v{run_number}`; macOS tags `mac-v{run_number}`. The macOS bundle is ad-hoc
signed (no paid Developer ID), so a downloaded copy needs
`xattr -dr com.apple.quarantine /Applications/ThreeD.app` before Gatekeeper
will let it run.

`icon.png` at the repo root is the shared source icon; `windows/icon.ico`
and `mac/Resources/AppIcon.icns` are generated from it (`make icon` on the
macOS side).
