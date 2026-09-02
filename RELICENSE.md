# 0.4.0 relicensing record

This record documents the rights and provenance review for the 0.4.0 release.
It records repository evidence and is not legal advice.

## Effective scope

Beginning with version 0.4.0, the project-owned source code, documentation,
website, and assets in this repository are licensed under the Apache License,
Version 2.0. The license text is in [`LICENSE`](LICENSE), and third-party
attributions are in [`NOTICE`](NOTICE).

Previously published releases, including 0.3.1, remain under the license under
which they were distributed.

## Rights review

The `next` branch history and GitHub contributor data identify these human
contributors for the project material in scope:

- Jordan Calhoun (`jordancalhoun`) authored the original implementation,
  release automation, website, and app work. Jordan opened issue [#59](https://github.com/codecarton/swiftpkg/issues/59)
  and is the only repository administrator listed by GitHub.
- Rod Christiansen (`rodchristiansen`) authored 34 commits covering shared
  source, tests, CI templates, and documentation. Rod recorded in [issue #59's
  consent comment](https://github.com/codecarton/swiftpkg/issues/59#issuecomment-5511680426)
  (2026-09-02) that he is a copyright holder in swiftpkg and consents to
  relicensing his contributions from GPL-3.0-or-later to Apache-2.0 for
  version 0.4.0 and later; he also stated that previously published releases
  remain under their original distribution license.

The GitHub contributor list shows no other human contributors. One commit is
authored by `coderabbitai[bot]` and committed by Jordan; this record does not
infer an independent copyright holder from automated output.

## Third-party material

- [munki-pkg](https://github.com/munki/munki-pkg) is the upstream project whose
  workflow and compatibility behavior informed swiftpkg. Its source is
  Apache-2.0 licensed. The swiftpkg tree contains a Swift implementation
  rather than a vendored munki-pkg checkout; its attribution and license link
  remain in the README and NOTICE.
- [Swift Argument Parser](https://github.com/apple/swift-argument-parser) is
  pinned to 1.8.2 in `Package.resolved`. It is Apache-2.0 licensed with the
  Runtime Library Exception; its upstream license and exception remain
  applicable through Swift Package Manager.
- [Yams](https://github.com/jpsim/Yams) is pinned to 6.2.2 in
  `Package.resolved`. Yams and its bundled libYAML are MIT licensed. The
  copyright and license notice are recorded in NOTICE.
- Apple frameworks and command-line tools used by the macOS build are platform
  components, not source material redistributed by this repository.

## NOTICE decision

The pinned Munki-pkg, Swift Argument Parser, and Yams repository trees do not
provide a separate NOTICE file. A consolidated NOTICE file is nevertheless
included to make the dependency and upstream attributions available with
source and release artifacts.
