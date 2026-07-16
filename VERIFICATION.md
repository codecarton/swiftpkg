# Verification

Run the fast unit tests with Swift Testing:

```sh
swift test
```

Run the repeatable macOS integration loop:

```sh
./scripts/verify-loop.sh
```

The integration loop creates isolated temporary projects and verifies nested
payloads, BOM export, installer script permissions, `.DS_Store` cleanup,
payload-free packages, and empty-payload packages using Apple's `pkgbuild` and
`pkgutil` tools. It removes its temporary workspace when it exits.
