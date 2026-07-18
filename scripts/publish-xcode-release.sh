#!/bin/sh
set -eu

usage() {
    echo "Usage: $0 --check | --build | --publish" >&2
    echo "  --check    Validate the local release credentials and tools without changing anything." >&2
    echo "  --build    Build, sign, notarize, and save release artifacts under dist/." >&2
    echo "  --publish  Build, sign, notarize, tag, push, and publish the release in VERSION." >&2
    exit 2
}

[ "$#" -eq 1 ] || usage
MODE=$1
case "$MODE" in
    --check|--build|--publish) ;;
    *) usage ;;
esac

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(tr -d '\n' < "$ROOT/VERSION")
TAG="v$VERSION"
TEMPLATE="$ROOT/release/SwiftpkgInstaller"
DIST="$ROOT/dist"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/swiftpkg-xcode-release.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

APP_SIGN_IDENTITY=${APP_SIGN_IDENTITY:?Set APP_SIGN_IDENTITY to a Developer ID Application identity.}
INSTALLER_SIGN_IDENTITY=${INSTALLER_SIGN_IDENTITY:?Set INSTALLER_SIGN_IDENTITY to a Developer ID Installer identity.}
NOTARY_PROFILE=${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile.}
GIT_REMOTE=${GIT_REMOTE:-origin}
RELEASE_BRANCH=${RELEASE_BRANCH:-main}

fail() {
    echo "release error: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found in PATH: $1"
}

for command in swiftpkg xcodebuild codesign lipo ditto git xcrun security plutil shasum; do
    require_command "$command"
done

case "$VERSION" in
    ''|*[!0-9.]*) fail "VERSION must contain a numeric semantic version" ;;
esac

grep -Fq "let swiftpkgVersion = \"$VERSION\"" "$ROOT/swiftpkg/Version.swift" ||
    fail "VERSION and swiftpkg/Version.swift disagree"
grep -Fq "MARKETING_VERSION = $VERSION;" "$ROOT/swiftpkg.xcodeproj/project.pbxproj" ||
    fail "VERSION and the Swiftpkgr MARKETING_VERSION disagree"

security find-identity -v | grep -Fq "\"$APP_SIGN_IDENTITY\"" ||
    fail "Developer ID Application identity is unavailable: $APP_SIGN_IDENTITY"
security find-identity -v | grep -Fq "\"$INSTALLER_SIGN_IDENTITY\"" ||
    fail "Developer ID Installer identity is unavailable: $INSTALLER_SIGN_IDENTITY"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null ||
    fail "notarytool keychain profile is unavailable: $NOTARY_PROFILE"

SWIFTPKG_BIN=$(command -v swiftpkg)
echo "Using Swiftpkg CLI: $SWIFTPKG_BIN"
"$SWIFTPKG_BIN" --version

if [ "$MODE" != "--build" ]; then
    require_command gh
    gh auth status >/dev/null ||
        fail "GitHub CLI is not authenticated"
fi

[ "$MODE" != "--check" ] || {
    echo "Release tools and credentials are ready."
    exit 0
}

if [ "$MODE" = "--publish" ]; then
    BRANCH=$(git -C "$ROOT" branch --show-current)
    [ "$BRANCH" = "$RELEASE_BRANCH" ] ||
        fail "releases must run from $RELEASE_BRANCH (current branch: ${BRANCH:-detached HEAD})"
    [ -z "$(git -C "$ROOT" status --porcelain)" ] ||
        fail "commit or discard all tracked and untracked changes before releasing"

    git -C "$ROOT" fetch "$GIT_REMOTE" "$RELEASE_BRANCH" --tags
    git -C "$ROOT" merge-base --is-ancestor "$GIT_REMOTE/$RELEASE_BRANCH" HEAD ||
        fail "local $RELEASE_BRANCH has diverged from $GIT_REMOTE/$RELEASE_BRANCH"

    if git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
        [ "$(git -C "$ROOT" rev-parse "$TAG^{}")" = "$(git -C "$ROOT" rev-parse HEAD)" ] ||
            fail "$TAG already exists at a different commit"
    fi
fi

cd "$ROOT"
swift test
./scripts/verify-loop.sh

BUILD_NUMBER=$(git rev-list --count HEAD)
CLI_PRODUCTS="$WORK/xcode-cli"
APP_PRODUCTS="$WORK/xcode-app"

xcodebuild \
    -project "$ROOT/swiftpkg.xcodeproj" \
    -scheme swiftpkg \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$WORK/derived-cli" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CONFIGURATION_BUILD_DIR="$CLI_PRODUCTS" \
    build

xcodebuild \
    -project "$ROOT/swiftpkg.xcodeproj" \
    -scheme Swiftpkgr \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$WORK/derived-app" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CONFIGURATION_BUILD_DIR="$APP_PRODUCTS" \
    build

CLI_PRODUCT="$CLI_PRODUCTS/swiftpkg"
APP_PRODUCT="$APP_PRODUCTS/Swiftpkgr.app"
APP_EXECUTABLE="$APP_PRODUCT/Contents/MacOS/Swiftpkgr"
[ -x "$CLI_PRODUCT" ] || fail "Xcode did not export the swiftpkg executable"
[ -x "$APP_EXECUTABLE" ] || fail "Xcode did not export Swiftpkgr.app"

for product in "$CLI_PRODUCT" "$APP_EXECUTABLE"; do
    PRODUCT_ARCHS=$(lipo -archs "$product")
    case " $PRODUCT_ARCHS " in
        *' arm64 '*x86_64*|*' x86_64 '*arm64*) ;;
        *) fail "$product is not Universal 2: $PRODUCT_ARCHS" ;;
    esac
done

[ "$(plutil -extract CFBundleShortVersionString raw "$APP_PRODUCT/Contents/Info.plist")" = "$VERSION" ] ||
    fail "exported app version does not match VERSION"
"$CLI_PRODUCT" --version | grep -Fxq "$VERSION" ||
    fail "exported CLI version does not match VERSION"

codesign --force --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$CLI_PRODUCT"
codesign --force --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$APP_PRODUCT"
codesign --verify --strict --verbose=2 "$CLI_PRODUCT"
codesign --verify --deep --strict --verbose=2 "$APP_PRODUCT"

CLI_ARCHIVE="$WORK/swiftpkg-$VERSION.zip"
ditto -c -k --keepParent "$CLI_PRODUCT" "$CLI_ARCHIVE"
xcrun notarytool submit "$CLI_ARCHIVE" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --timeout 30m

APP_ARCHIVE="$WORK/Swiftpkgr-$VERSION.zip"
ditto -c -k --keepParent "$APP_PRODUCT" "$APP_ARCHIVE"
xcrun notarytool submit "$APP_ARCHIVE" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --timeout 30m
xcrun stapler staple "$APP_PRODUCT"
xcrun stapler validate "$APP_PRODUCT"
spctl --assess --type execute --verbose=4 "$APP_PRODUCT"

INSTALLER_PROJECT="$WORK/SwiftpkgInstaller"
ditto "$TEMPLATE" "$INSTALLER_PROJECT"
rm -f "$INSTALLER_PROJECT/payload/.gitkeep"
/usr/libexec/PlistBuddy -c "Set :version $VERSION" "$INSTALLER_PROJECT/build-info.plist"
/usr/libexec/PlistBuddy -c "Set :signing_info:identity $INSTALLER_SIGN_IDENTITY" "$INSTALLER_PROJECT/build-info.plist"
/usr/libexec/PlistBuddy -c "Set :notarization_info:keychain_profile $NOTARY_PROFILE" "$INSTALLER_PROJECT/build-info.plist"

mkdir -p "$INSTALLER_PROJECT/payload/Applications"
mkdir -p "$INSTALLER_PROJECT/payload/usr/local/bin"
ditto "$APP_PRODUCT" "$INSTALLER_PROJECT/payload/Applications/Swiftpkgr.app"
install -m 755 "$CLI_PRODUCT" "$INSTALLER_PROJECT/payload/usr/local/bin/swiftpkg"

"$SWIFTPKG_BIN" "$INSTALLER_PROJECT"

PACKAGE_NAME="swiftpkg-$VERSION-universal.pkg"
BUILT_PACKAGE="$INSTALLER_PROJECT/build/$PACKAGE_NAME"
[ -f "$BUILT_PACKAGE" ] || fail "Swiftpkg did not create $PACKAGE_NAME"

pkgutil --check-signature "$BUILT_PACKAGE"
xcrun stapler validate "$BUILT_PACKAGE"
spctl --assess --type install --verbose=4 "$BUILT_PACKAGE"

mkdir -p "$DIST"
rm -f "$DIST/$PACKAGE_NAME" "$DIST/SHA256SUMS"
ditto "$BUILT_PACKAGE" "$DIST/$PACKAGE_NAME"
(
    cd "$DIST"
    shasum -a 256 "$PACKAGE_NAME" > SHA256SUMS
)

[ "$MODE" != "--build" ] || {
    echo "Release artifacts: $DIST"
    exit 0
}

if ! git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    git -C "$ROOT" tag -a "$TAG" -m "swiftpkg $VERSION"
fi

git -C "$ROOT" push "$GIT_REMOTE" "$RELEASE_BRANCH"
git -C "$ROOT" push "$GIT_REMOTE" "refs/tags/$TAG"

GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}
if gh release view "$TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
    gh release upload "$TAG" "$DIST/$PACKAGE_NAME" "$DIST/SHA256SUMS" \
        --clobber \
        --repo "$GITHUB_REPOSITORY"
else
    gh release create "$TAG" "$DIST/$PACKAGE_NAME" "$DIST/SHA256SUMS" \
        --repo "$GITHUB_REPOSITORY" \
        --title "swiftpkg $VERSION" \
        --verify-tag \
        --generate-notes
fi

echo "Published $TAG to $GITHUB_REPOSITORY"
echo "Release artifacts: $DIST"
