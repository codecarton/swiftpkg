# Swiftpkg combined release installer project

This is the reusable Swiftpkg project for the combined macOS release
installer. The release script copies this project to a temporary directory and
stages these Xcode Release products into its payload:

```text
/Applications/Swiftpkgr.app
/usr/local/bin/swiftpkg
```

The checked-in payload is intentionally empty. Do not place exported binaries
in this directory or commit generated `build/` contents.

`build-info.plist` contains placeholder certificate and keychain-profile
references. The release script replaces them only in its temporary copy using
the required environment variables. The signing private key and notarization
credentials remain in the login keychain.

Configure the public identity and profile labels before running the workflow:

```sh
APP_SIGN_IDENTITY='Developer ID Application: Organization (TEAMID)'
INSTALLER_SIGN_IDENTITY='Developer ID Installer: Organization (TEAMID)'
NOTARY_PROFILE='notarytool-profile'
export APP_SIGN_IDENTITY INSTALLER_SIGN_IDENTITY NOTARY_PROFILE
```

Run the complete release workflow from the repository root:

```sh
./scripts/publish-xcode-release.sh --check
./scripts/publish-xcode-release.sh --build
./scripts/publish-xcode-release.sh --publish
```

`--check` is read-only. `--build` can run on a working branch and saves the
signed, notarized combined installer, CLI installer, app archive, CLI archive,
and `SHA256SUMS` under `dist/` without making Git or GitHub changes. `--publish`
requires a clean `main` checkout and performs the external Apple, Git, and
GitHub operations.

The script reads the release number from `VERSION`, validates it against the
Swift and Xcode version sources, exports Universal 2 Release products from
Xcode, signs them with Developer ID Application, notarizes and staples the app,
and invokes the `swiftpkg` command found in `PATH`. Swiftpkg signs, notarizes,
and staples the final installer using this project's settings.

After validation, the script pushes `main`, explicitly pushes the
`v<version>` tag, and creates or updates the corresponding GitHub Release with
all installer and Homebrew artifacts plus `SHA256SUMS`.
