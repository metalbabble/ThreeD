# ThreeD

A small standalone viewer for 3D-printing model files, available for
**Windows** and **macOS**. Made as a quick way of previewing 3MF, STL, and
glTF/GLB files without launching a full slicer.

| Platform | Directory | Stack | Docs |
|----------|-----------|-------|------|
| Windows  | [`windows/`](windows/) | WPF (.NET 10) + Helix Toolkit | [windows/README.md](windows/README.md) |
| macOS    | [`mac/`](mac/)         | SwiftUI + SceneKit            | [mac/README.md](mac/README.md) |

![ThreeD screenshot](windows/ThreeD-screenshot.png)

## Supported formats

Both apps read **3MF** (including build/component transforms and the
production extension's `p:path` part references used by Bambu Studio / Orca
project files), **STL**, and **glTF / GLB**. The Windows version additionally
reads OBJ, PLY, OFF, 3DS, and LWO via Helix Toolkit, and offers a headless
`--snapshot` mode.

## Layout

- [`windows/`](windows/) — the Windows app (`dotnet build ThreeD.csproj`)
- [`mac/`](mac/) — the macOS app (`make app`)
- [`samples/`](samples/) — tiny shared test files used by both apps
- `icon.png` — shared app icon source (`windows/icon.ico` and
  `mac/Resources/AppIcon.icns` are generated from it)

## Releases

Windows single-file builds are published automatically from `main` by
[release-windows.yml](.github/workflows/release-windows.yml) whenever the
Windows app changes. The macOS app is currently built locally with
`make app` (see [mac/README.md](mac/README.md)).
