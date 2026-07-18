# Verification

Run the fast unit tests with Swift Testing:

```sh
swift test
```

Run the repeatable macOS integration loop:

```sh
./scripts/verify-loop.sh
```

Build both frontends with Xcode:

```sh
xcodebuild -project swiftpkg.xcodeproj -scheme swiftpkg -configuration Release CODE_SIGNING_ALLOWED=NO build
xcodebuild -project swiftpkg.xcodeproj -scheme Swiftpkgr -configuration Release CODE_SIGNING_ALLOWED=NO build
```

The integration loop creates isolated temporary projects and verifies nested
payloads, BOM export, installer script permissions, `.DS_Store` cleanup,
payload-free packages, and empty-payload packages using Apple's `pkgbuild` and
`pkgutil` tools. It removes its temporary workspace when it exits.

Core tests also verify editable settings, legacy wire keys, lossless plist/JSON
round trips, and the distinction between `${version}` templates and resolved
build values.
