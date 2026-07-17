![swiftpkg — Build better macOS installer packages](site/assets/og.png)

# swiftpkg

[![CI](https://github.com/codecarton/swiftpkg/actions/workflows/ci.yml/badge.svg)](https://github.com/codecarton/swiftpkg/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/codecarton/swiftpkg?display_name=release&sort=semver)](https://github.com/codecarton/swiftpkg/releases)
[![License](https://img.shields.io/github/license/codecarton/swiftpkg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)](https://support.apple.com/macos)

`swiftpkg` is a native toolkit for building Apple installer packages from
version-control-friendly project directories. Use the command-line tool for
automation today; Swiftpkgr, its macOS desktop companion, brings a visual
workflow in the 0.3.0 release. Both are powered by the same Swift
implementation of [`munki-pkg`](https://github.com/munki/munki-pkg).

## Install for Mac administrators

Download `swiftpkg-<version>-universal.pkg` and `SHA256SUMS` from the matching
GitHub Release. The installer is Universal 2 (Apple silicon and Intel),
currently unsigned; it supports macOS 13 and later. This is temporary while
Apple signing and notarization are being set up. Verify the published checksum
before deployment and expect macOS to require an administrator override.

Verify the download before installation:

```sh
shasum -a 256 -c SHA256SUMS
sudo installer -pkg swiftpkg-<version>-universal.pkg -target /
swiftpkg --version
```

The installer places the executable at `/usr/local/bin/swiftpkg`. Deploy that
same installer through Munki, Jamf Pro, or another management system; do not
repackage the executable. Upgrades replace that path. To uninstall, remove
`/usr/local/bin/swiftpkg` and, if desired, the `org.swiftpkg.cli` installer
receipt after confirming it is not needed for inventory.

`swiftpkg` requires macOS, Xcode Command Line Tools, and Apple's `pkgbuild`,
`productbuild`, `pkgutil`, `ditto`, and `lsbom` tools. Package signing and
notarization additionally require the appropriate Apple credentials on the
build host.

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

## Swiftpkgr graphical app

Swiftpkgr is the native macOS 15+ frontend included alongside the macOS 13+
`swiftpkg` command-line tool. It opens the same project directories and uses
the same configuration, import, build, and BOM implementation.

Use Swiftpkgr to create, open, or convert package projects; import existing
installer packages; edit package, distribution, signing, and notarization
values; and build packages while viewing operation progress. It can import
plist or JSON settings to prefill the editor and export CLI-compatible plist
or JSON without losing `${version}` placeholders.

Swiftpkgr also opens existing YAML projects. Standalone settings import and
export are intentionally limited to plist and JSON.

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
provides YAML support. The CLI target also builds with:

```sh
xcodebuild -project swiftpkg.xcodeproj -scheme swiftpkg -configuration Release CODE_SIGNING_ALLOWED=NO build
xcodebuild -project swiftpkg.xcodeproj -scheme Swiftpkgr -configuration Release CODE_SIGNING_ALLOWED=NO build
```

## Maintainer releases

`VERSION` and `swiftpkg/Version.swift` are the release-version source of truth
and must match before a `v<version>` tag is created. On a clean, trusted macOS
release machine with the certificates and notary profile installed:

```sh
APP_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)' \
INSTALLER_SIGN_IDENTITY='Developer ID Installer: Example (TEAMID)' \
NOTARY_PROFILE='swiftpkg-notary' \
./scripts/release.sh
```

The script runs tests, builds a Universal 2 executable, signs it, creates,
notarizes, staples, and validates the installer, then writes artifacts and
`SHA256SUMS` to `dist/`. To publish a GitHub Release after creating and pushing
the matching tag, add `GH_PUBLISH=1 GITHUB_REPOSITORY=owner/repo`; this requires
the GitHub CLI to be authenticated on the release Mac.

Until Apple credentials are available, pushing a matching `v<version>` tag runs
the GitHub **Release** workflow. It builds an unsigned installer and publishes
it with `SHA256SUMS` to that GitHub Release. The same temporary behavior can be
run locally with `UNSIGNED=1 ./scripts/release.sh`. Unsigned packages must not
be treated as notarized or Gatekeeper-validated.

GitHub Actions validates pull requests and tags and publishes unsigned tagged
releases; it intentionally has no Apple signing credentials. See [VERIFICATION.md](VERIFICATION.md),
[CONTRIBUTING.md](CONTRIBUTING.md), and [SECURITY.md](SECURITY.md) for project
processes.

## Marketing site

The static marketing site lives in [`site/`](site/) and publishes to
`https://codecarton.github.io/swiftpkg/`. Enable **GitHub Actions** as the
Pages source in repository Settings → Pages, then run the **Deploy marketing
site** workflow once. Future changes to `site/` on `main` deploy automatically.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
