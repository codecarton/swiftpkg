# swiftpkg CLI release installer project

This reusable project builds the signed, notarized CLI-only installer. The
release script copies it to a temporary directory and stages the Universal 2
executable at:

```text
/usr/local/bin/swiftpkg
```

The checked-in payload is intentionally empty. Certificate identity and
notarytool profile placeholders are replaced only in the temporary copy by
`scripts/publish-xcode-release.sh`.
