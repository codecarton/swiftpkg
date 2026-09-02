# Contributing

## Track the work

Use one originating GitHub issue as the development issue for each substantial
change, and link it from the pull request with `Closes #<number>`. This keeps
the proposed behavior, implementation, and discussion together.

For this project, a change is substantial when it could alter a public
compatibility surface or the behavior of a packaged product. Representative
examples include changes to:

- CLI commands, flags, exit statuses, output, or JSON manifests.
- `build-info` keys, defaults, version substitution, or plist, JSON, and YAML
  formats.
- Package creation, import, build, verification, scripts, BOM metadata,
  signing, or notarization.
- GitHub Actions, Azure DevOps integrations, release automation, or published
  installer and application artifacts.

An issue is not required for a typo-only, comment-only, formatting-only, or
similarly mechanical change that does not affect behavior or a public
compatibility surface. If a substantial change has no issue, document the
reason in the pull request and link the maintainer's written approval for that
exception before requesting review. When the scope is unclear, open an issue
or ask a maintainer.

Keep pull requests focused, include tests for behavior changes, and run both
checks locally on macOS:

```sh
swift test
./scripts/verify-loop.sh
```

By contributing to the project for inclusion in version 0.4.0 or later, you
agree that your contribution is licensed under the Apache License 2.0. See
[LICENSE](LICENSE) and [NOTICE](NOTICE). Previously published releases remain
under the license under which they were distributed.
