#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(tr -d '\n' < "$ROOT/VERSION")
DIST="$ROOT/dist"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/swiftpkg-release.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

APP_SIGN_IDENTITY=${APP_SIGN_IDENTITY:?Set APP_SIGN_IDENTITY to a Developer ID Application identity.}
INSTALLER_SIGN_IDENTITY=${INSTALLER_SIGN_IDENTITY:?Set INSTALLER_SIGN_IDENTITY to a Developer ID Installer identity.}
NOTARY_PROFILE=${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile.}
GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-}
GH_PUBLISH=${GH_PUBLISH:-0}

case "$VERSION" in
    ''|*[!0-9.]*) echo "VERSION must contain a numeric semantic version" >&2; exit 2 ;;
esac
grep -Fq "let swiftpkgVersion = \"$VERSION\"" "$ROOT/swiftpkg/Version.swift" || {
    echo "VERSION and swiftpkg/Version.swift disagree" >&2
    exit 2
}
git -C "$ROOT" diff --quiet || { echo "Refusing to release from a dirty worktree" >&2; exit 2; }
git -C "$ROOT" diff --cached --quiet || { echo "Refusing to release from a dirty index" >&2; exit 2; }
command -v xcodebuild >/dev/null
command -v lipo >/dev/null
command -v gh >/dev/null || [ "$GH_PUBLISH" = 0 ]

cd "$ROOT"
swift test
./scripts/verify-loop.sh

xcodebuild -project swiftpkg.xcodeproj -scheme swiftpkg -configuration Release \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CONFIGURATION_BUILD_DIR="$WORK/products" build
BIN="$WORK/products/swiftpkg"
test -x "$BIN"
ARCHS=$(lipo -archs "$BIN")
case " $ARCHS " in
    *' arm64 '*x86_64*|*' x86_64 '*arm64*) ;;
    *)
    echo "Release executable is not Universal 2: $ARCHS" >&2
    exit 1
    ;;
esac

/usr/bin/codesign --force --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$BIN"
/usr/bin/codesign --verify --strict --verbose=2 "$BIN"
"$BIN" --version | grep -Fx "$VERSION"

rm -rf "$DIST"
mkdir -p "$DIST/pkgroot/usr/local/bin"
install -m 755 "$BIN" "$DIST/pkgroot/usr/local/bin/swiftpkg"
PKG="$DIST/swiftpkg-$VERSION-universal.pkg"
/usr/bin/pkgbuild --root "$DIST/pkgroot" --identifier org.swiftpkg.cli --version "$VERSION" \
    --install-location / --sign "$INSTALLER_SIGN_IDENTITY" "$PKG"
/usr/bin/xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$PKG"
/usr/bin/xcrun stapler validate "$PKG"
/usr/sbin/pkgutil --check-signature "$PKG"
/usr/sbin/spctl --assess --type install --verbose=4 "$PKG"
(cd "$DIST" && shasum -a 256 "$(basename "$PKG")" > SHA256SUMS)

if [ "$GH_PUBLISH" = 1 ]; then
    : "${GITHUB_REPOSITORY:?Set GITHUB_REPOSITORY to owner/repo when publishing.}"
    gh release create "v$VERSION" "$PKG" "$DIST/SHA256SUMS" \
        --repo "$GITHUB_REPOSITORY" --title "swiftpkg $VERSION" --generate-notes
fi

printf '%s\n' "release artifacts are in $DIST"
