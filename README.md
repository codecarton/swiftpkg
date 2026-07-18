![swiftpkg — Build better macOS installer packages](site/assets/og.png)

# swiftpkg

[![CI](https://github.com/codecarton/swiftpkg/actions/workflows/ci.yml/badge.svg)](https://github.com/codecarton/swiftpkg/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/codecarton/swiftpkg?display_name=release&sort=semver)](https://github.com/codecarton/swiftpkg/releases)
[![License](https://img.shields.io/github/license/codecarton/swiftpkg)](LICENSE)
[![CLI macOS 13+](https://img.shields.io/badge/CLI-macOS%2013%2B-000000?logo=apple&logoColor=white)](https://support.apple.com/macos)
[![Swiftpkgr macOS 15+](https://img.shields.io/badge/Swiftpkgr-macOS%2015%2B-000000?logo=apple&logoColor=white)](https://support.apple.com/macos)

`swiftpkg` is a macOS command-line tool for building Apple installer packages
from version-control-friendly project directories. It is a Swift implementation
of [`munki-pkg`](https://github.com/munki/munki-pkg). `Swiftpkgr` is its native
macOS desktop app. Both frontends use the same `SwiftPkgCore` package engine and
open the same portable projects.

## Install swiftpkg and Swiftpkgr

Download `swiftpkg-<version>-universal.pkg` and `SHA256SUMS` from the matching
GitHub Release. Starting with 0.3.0, the signed and notarized Universal 2
installer includes both the CLI and Swiftpkgr. The combined installer requires
macOS 15 or later; the CLI itself continues to support macOS 13 and later.

Verify the download before installation:

```sh
shasum -a 256 -c SHA256SUMS
pkgutil --check-signature swiftpkg-<version>-universal.pkg
xcrun stapler validate swiftpkg-<version>-universal.pkg
sudo installer -pkg swiftpkg-<version>-universal.pkg -target /
swiftpkg --version
```

The installer places the executable at `/usr/local/bin/swiftpkg` and the app at
`/Applications/Swiftpkgr.app`. Deploy that same installer through Munki, Jamf
Pro, or another management system; do not repackage its contents. Subsequent
releases replace the CLI and atomically upgrade the app bundle.

To uninstall, remove `/usr/local/bin/swiftpkg` and
`/Applications/Swiftpkgr.app`, then optionally forget the
`com.codecarton.swiftpkg.installer` receipt after confirming it is not needed
for inventory.

`swiftpkg` requires macOS, Xcode Command Line Tools, and Apple's `pkgbuild`,
`productbuild`, `pkgutil`, `ditto`, and `lsbom` tools. Package signing and
notarization additionally require the appropriate Apple credentials on the
build host.

## Swiftpkgr desktop app

Swiftpkgr provides a focused visual workspace for creating, importing, editing,
building, signing, and notarizing package projects. Open the same
`build-info.plist`, `.json`, `.yaml`, or `.yml` projects in either Swiftpkgr or
the CLI without conversion.

Swiftpkgr can create a new project, convert an existing folder, import a flat or
supported bundle-style installer package, synchronize metadata from `Bom.txt`,
and build the final package. Build progress and output stay visible in the app,
and Finder selects the generated package when the build completes.

## Use

Build a project:

```sh
swiftpkg path/to/project
```

Create a project template, import an existing package, or apply tracked BOM
metadata:

```sh
swiftpkg --create path/to/project
swiftpkg --import path/to/existing.pkg path/to/project
swiftpkg --sync path/to/project
```

Useful options:

```text
--json                 Use JSON build-info
--yaml                 Use YAML build-info
--export-bom-info      Export package BOM metadata to Bom.txt
--quiet                Suppress normal status output
--force                Allow project creation in an existing directory
--skip-signing         Skip configured package signing
--skip-notarization    Skip configured notarization
--skip-stapling        Skip notarization stapling
--help                 Show command help
--version              Show the tool version
```

## Project layout

```text
project/
    build-info.plist    # or build-info.json or build-info.yaml
    payload/            # files arranged at their target filesystem paths
    scripts/
        preinstall      # optional installer script
        postinstall     # optional installer script
    build/              # generated package output
    Bom.txt             # optional tracked ownership and mode metadata
```

If `payload/` is absent, a payload-free package is created. An empty
`payload/` creates a package that installs no files but still leaves an
installer receipt. Supported build-info settings include `name`, `identifier`,
`version`, `install_location`, `ownership`, `postinstall_action`,
`distribution_style`, `title`, `signing_info`, and `notarization_info`.

## Build from source

```sh
swift build -c release
.build/release/swiftpkg --version
swift test
./scripts/verify-loop.sh
```

The Swift Package Manager dependency [Yams](https://github.com/jpsim/Yams)
provides YAML support. Both products also build through Xcode:

```sh
xcodebuild -project swiftpkg.xcodeproj -scheme swiftpkg -configuration Release build
xcodebuild -project swiftpkg.xcodeproj -scheme Swiftpkgr -configuration Release build
```

## Maintainer releases

`VERSION`, `swiftpkg/Version.swift`, and the Swiftpkgr Xcode marketing version
must match before a release. On a trusted Mac, export the public Developer ID
identity names and notarytool keychain-profile label:

```sh
export APP_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
export INSTALLER_SIGN_IDENTITY='Developer ID Installer: Example (TEAMID)'
export NOTARY_PROFILE='swiftpkg-notary'
```

Validate the release environment without changing anything:

```sh
./scripts/publish-xcode-release.sh --check
```

Build, sign, notarize, staple, and validate the combined installer locally:

```sh
./scripts/publish-xcode-release.sh --build
```

After the release commit is merged to a clean `main` checkout, publish it:

```sh
./scripts/publish-xcode-release.sh --publish
```

The publish workflow runs the test and integration suites, exports Universal 2
CLI and app products from Xcode, signs and notarizes them, builds the installer
with the `swiftpkg` in `PATH`, writes the package and `SHA256SUMS` to `dist/`,
pushes `main` and the explicit `v<version>` tag, and creates or updates the
GitHub Release.

The tag workflow retains an unsigned CI fallback for environments without Apple
credentials, but it publishes only when no signed release exists and never
overwrites signed assets. See [VERIFICATION.md](VERIFICATION.md),
[CONTRIBUTING.md](CONTRIBUTING.md), and [SECURITY.md](SECURITY.md) for project
processes.

## Marketing site

The static marketing site lives in [`site/`](site/) and publishes to
`https://codecarton.github.io/swiftpkg/`. Enable **GitHub Actions** as the
Pages source in repository Settings → Pages, then run the **Deploy marketing
site** workflow once. Future changes to `site/` on `main` deploy automatically.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
