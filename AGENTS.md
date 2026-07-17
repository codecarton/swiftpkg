# swiftpkg Agent Guide

## Repository purpose

`swiftpkg` is a macOS 13+ command-line tool that creates, imports, and
maintains Apple installer-package projects. It is a Swift implementation of
Munki's `munki-pkg`. `Swiftpkgr` is its macOS 15+ SwiftUI frontend. Both use
the `SwiftPkgCore` static library; the app supplements rather than replaces
the CLI.

The primary development environment is macOS. The integration suite requires
Apple tools such as `pkgbuild`, `productbuild`, `pkgutil`, `ditto`, and
`lsbom`.

## Architecture

- `swiftpkgCLI/CLI.swift` parses command-line options and resolves them into one
  `CLICommand` (`create`, `import`, `synchronize`, or `build`). Preserve the
  documented option spelling and current exit behavior.
- `swiftpkg/BuildInfo.swift` owns the configuration boundary. Use
  `PackageConfiguration` and its typed enums/models internally; use
  `BuildInfoStore` for plist, JSON, and YAML I/O.
- `swiftpkg/ProjectOperations.swift` contains focused project-creation and BOM
  metadata services.
- `swiftpkg/PackageImporter.swift` imports flat and bundle packages and cleans
  up a partially-created project when import fails.
- `swiftpkg/PackageBuilder.swift` coordinates component building,
  distribution-package creation, script preparation, and notarization.
- `swiftpkg/Support.swift` contains errors, console output, filesystem helpers,
  and `ProcessRunning`. Route subprocess calls through `ProcessRunning` so
  behavior is testable with `RecordingRunner`.
- `swiftpkg/PackageSettingsDraft.swift` is the editable configuration boundary;
  keep template loading distinct from build-time version substitution.
- `Swiftpkgr/` contains the macOS 15 SwiftUI app. Keep `SwiftpkgrApp.swift` at
  the app root and organize the remaining app files by role:
  - `Screens/` contains user-facing navigation destinations and other base
    views rendered as complete screens.
  - `Components/` contains composable UI and command elements used by screens,
    the app entry point, or other components.
  - `Services/` contains API, panel, and other service-layer integrations.
  - `Models/` contains app-specific value and domain types.
  - `Extensions/` contains extensions of existing types. Name each file
    `<TypeName>+Ext.swift` and keep extensions for different base types in
    separate files.
  - `State/` contains state retained for the app lifecycle. Observable types,
    including types marked with `@Observable`, generally belong here.
  Views use the observable `ProjectEditorModel` and call
  `PackageOperationService` rather than invoking package tools directly.

Prefer fluent, role-based Swift names and concise documentation comments for
new nontrivial types and entry points. Keep side effects explicit in method
names and parameter labels.

## Compatibility rules

The CLI and on-disk `build-info` schema are public compatibility surfaces.
Do not rename flags or wire keys as part of internal cleanup. In particular,
the legacy keys `product id`, `min-os-version`, `large-payload`, and the
underscore-form settings (for example `signing_info`) must remain supported.

`PackageConfiguration` is intentionally typed, but `BuildInfoStore` preserves
the external keys and supports `build-info.plist`, `.json`, `.yaml`, and
`.yml`. Defaults, version substitution in `name`/`title`, payload-free
packages, BOM synchronization, script permission normalization, and importer
rollback are established behavior; do not change them without targeted tests
and a compatibility decision.

Build projects have this conventional shape:

```text
project/
  build-info.plist  # or .json/.yaml
  payload/
  scripts/
  build/            # generated
  Bom.txt           # optional tracked metadata
```

## Development and verification

Run these from the repository root:

```sh
swift test
./scripts/verify-loop.sh
swift build -c release
xcodebuild -project swiftpkg.xcodeproj -scheme Swiftpkgr -configuration Release CODE_SIGNING_ALLOWED=NO build
```

The unit tests use Swift Testing. Keep tests hermetic: use `TemporaryDirectory`
and `RecordingRunner` from `swiftpkgTests/TestSupport.swift` rather than real
subprocesses when a unit test only needs to inspect command construction.

`./scripts/verify-loop.sh` is the required macOS integration check. It builds
and exercises package creation, import, BOM export, script handling,
payload-free/empty-payload projects, multiple formats, and distribution
packages. It uses an isolated temporary workspace.

Do not commit generated `.build/` or `dist/` contents. Check `git diff --check`
before handing off changes.

## CI, branches, and releases

- Pull requests and pushes to `main` run `.github/workflows/ci.yml` on
  `macos-15`: `swift test`, `./scripts/verify-loop.sh`, and a Swiftpkgr build.
- Pushing a `v*` tag also validates that the tag exactly matches both `VERSION`
  and `swiftpkg/Version.swift`.
- `.github/workflows/release.yml` runs on a version tag and invokes
  `scripts/release.sh` with `UNSIGNED=1` and `GH_PUBLISH=1`. It publishes an
  unsigned Universal installer plus `SHA256SUMS` to the GitHub Release.
- For a signed/notarized release, run `scripts/release.sh` on a trusted macOS
  release machine with the required Apple signing identities and notary profile;
  never add those credentials to the repository or GitHub workflow.

Before release, update `VERSION` and `swiftpkg/Version.swift` together, merge
the release commit to `main`, and tag that merged commit as `v<version>`. If a
branch and tag share a name, push the tag explicitly with
`git push origin refs/tags/v<version>`.

## Other areas

- `site/` is the static marketing site. Its Pages workflow deploys changes to
  `site/` from `main`.
- Keep `swiftpkg.xcodeproj` and `Package.swift` aligned when changing target
  membership or dependencies. Avoid unrelated Xcode project-file reordering.
