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

## License

For the 0.4.0 release and later, project-owned swiftpkg material is licensed
under the Apache License 2.0. Previously published releases remain under the
license under which they were distributed. See the repository root's
[`LICENSE`](../../LICENSE), [`NOTICE`](../../NOTICE), and
[`RELICENSE.md`](../../RELICENSE.md).

The installer places these documents at
`/usr/local/share/doc/swiftpkg/` alongside the installed CLI.
