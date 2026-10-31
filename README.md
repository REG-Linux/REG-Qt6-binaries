# REG-Qt6-binaries

Prebuilt Qt 6 libraries used as build input for [REG-Linux](https://github.com/REG-Linux/REG-Linux).
Releases are named after the Qt version (for example `6.10.3`); each contains one
`reglinux-qt6-<version>-<cpu>.tar.xz` per supported CPU target.

The Qt libraries in these tarballs are **shared libraries** (`libQt6*.so`) built from the
**unmodified upstream Qt source**. You can rebuild them yourself and replace them (see
[Rebuilding](#rebuilding)).

**Exact source per release:** new releases also carry `reglinux-qt6-<version>-sources.tar`
(the upstream Qt archives and every patch applied, as built) and, per tarball,
`reglinux-qt6-<version>-<cpu>-legal-info.tar.xz` (full Buildroot configuration, package
recipes, licence texts, manifest, and the commits and CI run it came from). Releases made
before this was added carry only the tarballs; rerunning the workflow rebuilds any CPU whose
`-legal-info` archive is missing.

## Corresponding source for release 6.10.3

Download the exact upstream source from Qt and check the SHA-256:

| Module | Source | SHA-256 |
|---|---|---|
| qtbase | https://download.qt.io/archive/qt/6.10/6.10.3/submodules/qtbase-everywhere-src-6.10.3.tar.xz | `383dc907816338f0cba72088a524c07458dfc69ce684ca9132fcc4fe91c24b0b` |
| qtdeclarative | https://download.qt.io/archive/qt/6.10/6.10.3/submodules/qtdeclarative-everywhere-src-6.10.3.tar.xz | `dadf80d43b8e08ca63aa65d46859a42b920a7777cf7e0ecfcb4c4537f9e65c76` |
| qtmultimedia | https://download.qt.io/archive/qt/6.10/6.10.3/submodules/qtmultimedia-everywhere-src-6.10.3.tar.xz | `dd228fe54051e8834ca53e558794742c8814f217849f9dfa8f9a9df80441903a` |
| qtshadertools | https://download.qt.io/archive/qt/6.10/6.10.3/submodules/qtshadertools-everywhere-src-6.10.3.tar.xz | `c75837e2ea493ec0b9747b227c455d4a12cafe90068abf607992da9a403616c6` |
| qtsvg | https://download.qt.io/archive/qt/6.10/6.10.3/submodules/qtsvg-everywhere-src-6.10.3.tar.xz | `b3223fe005f6a4c7f21f34e4ee6ce0094737cff9503ba15bbb171ac18794f76d` |
| qttools | https://download.qt.io/archive/qt/6.10/6.10.3/submodules/qttools-everywhere-src-6.10.3.tar.xz | `8f00b9e3d1f80973d81cff67684972b89993183ef19924404d5b8ff0f89675b6` |
| qtwayland | https://download.qt.io/archive/qt/6.10/6.10.3/submodules/qtwayland-everywhere-src-6.10.3.tar.xz | `2e93322a86b562113cfa3a5f0aa8b1e4e185d6284af49b529578d27d52ca85d3` |
| qtwebsockets | https://download.qt.io/archive/qt/6.10/6.10.3/submodules/qtwebsockets-everywhere-src-6.10.3.tar.xz | `6ed8196002af15ca930b4ad111f1c19ed2941f4020759dbefb23e655ef6a33a1` |

For other releases, the source is the same module set at that version, at
`https://download.qt.io/archive/qt/<major.minor>/<version>/submodules/`.

## What REG-Linux changes

Nothing in the Qt source code. REG-Linux only changes how Qt is **built**: Buildroot package
definitions (enabled features, dependencies, version and hash bumps). These changes are
published as patches in [`recipe/`](recipe/), together with the build script
(`recipe/scripts/linux/prebuild/prebuild-qt6.sh`) and the Buildroot package that consumes the
tarballs (`recipe/package/libraries/reglinux-qt6/`).

## Licences

Qt is available under several licences, and each module is used under the terms below, as recorded in the
Buildroot package metadata for the version above:

| Module | Licence(s) |
|---|---|
| qtbase | GPL-2.0-or-later or LGPL-3.0 for the libraries; GPL-3.0 with exception for tools; also Apache-2.0, BSD-3-Clause, BSL-1.0, MIT (third-party parts) |
| qtdeclarative | LGPL-3.0 or GPL-3.0 or GPL-2.0 |
| qtmultimedia | LGPL-3.0 or GPL-3.0 |
| qtshadertools | GPL-2.0 or LGPL-3.0 or GPL-3.0; Apache-2.0 or MIT (SPIRV-Cross) |
| qtsvg | GPL-2.0-or-later or LGPL-3.0; GPL-3.0 with exception for tools |
| qttools | LGPL-3.0 or GPL-3.0 or GPL-2.0; GPL-3.0 with Qt exception for tools |
| qtwayland | LGPL-3.0 or GPL-2.0 or GPL-3.0 (client only; the GPL-3.0-only Wayland Compositor is not built) |
| qtwebsockets | LGPL-3.0 or GPL-2.0 or GPL-3.0 |

Where Qt offers a library under the LGPL, it is distributed here under the LGPL. The Qt Wayland
Compositor module, which Qt offers only under GPL-3.0, is built with `FEATURE_wayland_server=OFF`
and is not in these tarballs. The host tools (moc, rcc, uic and others) are under GPL-3.0 with
the [Qt GPL Exception 1.0](LICENSES/Qt-GPL-exception-1.0.txt). Full licence texts are in
[`LICENSES/`](LICENSES/); [`LICENSE`](LICENSE) at the top level is the plain LGPL-3.0 text, so
GitHub can classify the repository. The complete per-file notices are inside the upstream source
archives above. This repository's own workflows, scripts and `recipe/` are GPL-2.0-or-later, like
REG-Linux ([`LICENSES/REG-Linux-COPYING.txt`](LICENSES/REG-Linux-COPYING.txt)).

Because the libraries are shared, you may replace them with your own build of Qt, as the
LGPL-3.0 requires. The tarballs contain Qt's own FFmpeg media plugin (`libffmpegmediaplugin.so`, part of Qt Multimedia), which
links dynamically against the FFmpeg libraries supplied by the REG-Linux image. FFmpeg itself and the other
system libraries are not in these tarballs; their sources are in the REG-Linux repository.

## Rebuilding

The tarballs are produced by the workflows in `.github/workflows/`, which build the Buildroot
tree of REG-Linux ([REG-Linux/REG-Linux](https://github.com/REG-Linux/REG-Linux) plus the
[REG-Linux/buildroot](https://github.com/REG-Linux/buildroot) fork) with the patches in
[`recipe/`](recipe/) merged by `recipe/scripts/buildroot/mergeToBR.sh`. To rebuild one CPU
target locally, from the root of that tree:

```
./scripts/linux/prebuild/prebuild-qt6.sh <cpu>
```

## Source requests

If you cannot get a source you need from the links above, open an issue on this repository or
use the contact on https://reglinux.org/legal/ and we will provide it.

Qt is a trademark of The Qt Company Ltd. REG-Linux is not affiliated with or endorsed by it.
