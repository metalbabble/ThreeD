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

Both platforms publish automatically from `main`, each only when its own
platform directory changes:

| Workflow | Tags | Artifact |
|----------|------|----------|
| [release-windows.yml](.github/workflows/release-windows.yml) | `win-v{n}` | `ThreeD.exe` (self-contained, win-x64) |
| [release-mac.yml](.github/workflows/release-mac.yml) | `mac-v{n}` | `ThreeD-macos.zip` (universal, macOS 14+) |

The macOS bundle is ad-hoc signed rather than signed with a paid Developer ID,
so Gatekeeper blocks a downloaded copy until it is de-quarantined — see
[mac/README.md](mac/README.md) for the one-liner.
