# swiftpkg

Swift implementation of [`munki-pkg`](https://github.com/munki/munki-pkg), a macOS command-line tool for building Apple installer packages from version-control-friendly project directories.

The tool builds standard flat packages with Apple's `pkgbuild` and can create distribution-style packages with `productbuild`.

## Requirements

- macOS
- Xcode and the macOS Command Line Tools
- Swift 6 toolchain
- Apple's `pkgbuild`, `productbuild`, `pkgutil`, `ditto`, and `lsbom` tools

YAML support is provided by the Swift Package Manager dependency [Yams](https://github.com/jpsim/Yams).

## Build

Using Swift Package Manager:

```sh
swift build -c release
```

The binary is created at:

```text
.build/release/swiftpkg
```

The Xcode project can also be built with:

```sh
xcodebuild -project swiftpkg.xcodeproj -scheme swiftpkg -configuration Release build
```

## Usage

Build a project:

```sh
.build/release/swiftpkg path/to/project
```

Create a project template:

```sh
.build/release/swiftpkg --create path/to/project
```

Import an existing package:

```sh
.build/release/swiftpkg --import path/to/existing.pkg path/to/project
```

Apply tracked BOM metadata without building:

```sh
.build/release/swiftpkg --sync path/to/project
```

Useful options include:

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

## Project Layout

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

If `payload/` is absent, a payload-free package is created. An empty `payload/` creates a package that installs no files but still leaves an installer receipt.

Supported build-info formats are plist, JSON, and YAML. Common settings include `name`, `identifier`, `version`, `install_location`, `ownership`, `postinstall_action`, `distribution_style`, `title`, `signing_info`, and `notarization_info`.

## Verification

Run the unit tests:

```sh
swift test
```

Run the repeatable integration loop:

```sh
./scripts/verify-loop.sh
```

The integration loop builds the release binary and verifies nested payloads, BOM export, package import, installer script handling, JSON and YAML projects, payload-free packages, empty payloads, and distribution-style packages. It uses a temporary workspace and removes it on exit.

Additional verification details are in [`VERIFICATION.md`](VERIFICATION.md).

## Compatibility

This implementation follows the command-line behavior and package project model of the upstream Python `munki-pkg` implementation. Apple package creation, signing, notarization, and stapling remain dependent on the macOS tools and credentials available on the host.
