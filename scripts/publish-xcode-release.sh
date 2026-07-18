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
COMBINED_TEMPLATE="$ROOT/release/SwiftpkgInstaller"
CLI_TEMPLATE="$ROOT/release/SwiftpkgCLIInstaller"
DIST="$ROOT/dist"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/swiftpkg-xcode-release.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

COMBINED_PACKAGE_NAME="swiftpkg-$VERSION-combined.pkg"
CLI_PACKAGE_NAME="swiftpkg-$VERSION-cli.pkg"
APP_ARCHIVE_NAME="Swiftpkgr-$VERSION.zip"
TARBALL_NAME="swiftpkg-$VERSION-universal.tar.gz"

APP_SIGN_IDENTITY=${APP_SIGN_IDENTITY:?Set APP_SIGN_IDENTITY to a Developer ID Application identity.}
INSTALLER_SIGN_IDENTITY=${INSTALLER_SIGN_IDENTITY:?Set INSTALLER_SIGN_IDENTITY to a Developer ID Installer identity.}
NOTARY_PROFILE=${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile.}
GIT_REMOTE=${GIT_REMOTE:-origin}
RELEASE_BRANCH=${RELEASE_BRANCH:-main}
HOMEBREW_TAP_REPOSITORY=${HOMEBREW_TAP_REPOSITORY:-codecarton/homebrew-tap}

fail() {
    echo "release error: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found in PATH: $1"
}

for command in swiftpkg xcodebuild codesign lipo ditto git xcrun security plutil shasum tar awk pkgutil spctl; do
    require_command "$command"
done

prepare_installer_project() {
    template=$1
    project=$2

    ditto "$template" "$project"
    rm -f "$project/payload/.gitkeep"
    /usr/libexec/PlistBuddy -c "Set :version $VERSION" "$project/build-info.plist"
    /usr/libexec/PlistBuddy -c "Set :signing_info:identity $INSTALLER_SIGN_IDENTITY" "$project/build-info.plist"
    /usr/libexec/PlistBuddy -c "Set :notarization_info:keychain_profile $NOTARY_PROFILE" "$project/build-info.plist"
}

validate_installer() {
    package=$1

    pkgutil --check-signature "$package"
    xcrun stapler validate "$package"
    spctl --assess --type install --verbose=4 "$package"
}

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
if [ "$MODE" = "--publish" ]; then
    HOMEBREW_TAP_DISPATCH_TOKEN=${HOMEBREW_TAP_DISPATCH_TOKEN:?Set HOMEBREW_TAP_DISPATCH_TOKEN to a token that can dispatch to the Homebrew tap.}
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
    GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}
    if gh release view "$TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
        fail "$TAG already has a GitHub Release; release assets are immutable"
    fi

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

APP_NOTARIZATION_ARCHIVE="$WORK/Swiftpkgr-$VERSION-notarization.zip"
ditto -c -k --keepParent "$APP_PRODUCT" "$APP_NOTARIZATION_ARCHIVE"
xcrun notarytool submit "$APP_NOTARIZATION_ARCHIVE" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --timeout 30m
xcrun stapler staple "$APP_PRODUCT"
xcrun stapler validate "$APP_PRODUCT"
spctl --assess --type execute --verbose=4 "$APP_PRODUCT"

COMBINED_PROJECT="$WORK/SwiftpkgInstaller"
prepare_installer_project "$COMBINED_TEMPLATE" "$COMBINED_PROJECT"
mkdir -p "$COMBINED_PROJECT/payload/Applications"
mkdir -p "$COMBINED_PROJECT/payload/usr/local/bin"
ditto "$APP_PRODUCT" "$COMBINED_PROJECT/payload/Applications/Swiftpkgr.app"
install -m 755 "$CLI_PRODUCT" "$COMBINED_PROJECT/payload/usr/local/bin/swiftpkg"
"$SWIFTPKG_BIN" "$COMBINED_PROJECT"

COMBINED_PACKAGE="$COMBINED_PROJECT/build/$COMBINED_PACKAGE_NAME"
[ -f "$COMBINED_PACKAGE" ] ||
    fail "Swiftpkg did not create $COMBINED_PACKAGE_NAME"
validate_installer "$COMBINED_PACKAGE"

CLI_INSTALLER_PROJECT="$WORK/SwiftpkgCLIInstaller"
prepare_installer_project "$CLI_TEMPLATE" "$CLI_INSTALLER_PROJECT"
mkdir -p "$CLI_INSTALLER_PROJECT/payload/usr/local/bin"
install -m 755 "$CLI_PRODUCT" "$CLI_INSTALLER_PROJECT/payload/usr/local/bin/swiftpkg"
"$SWIFTPKG_BIN" "$CLI_INSTALLER_PROJECT"

CLI_PACKAGE="$CLI_INSTALLER_PROJECT/build/$CLI_PACKAGE_NAME"
[ -f "$CLI_PACKAGE" ] ||
    fail "Swiftpkg did not create $CLI_PACKAGE_NAME"
validate_installer "$CLI_PACKAGE"

COMBINED_PAYLOAD="$WORK/combined-payload.txt"
CLI_PAYLOAD="$WORK/cli-payload.txt"
pkgutil --payload-files "$COMBINED_PACKAGE" | sed 's|^\./||' > "$COMBINED_PAYLOAD"
pkgutil --payload-files "$CLI_PACKAGE" | sed 's|^\./||' > "$CLI_PAYLOAD"
grep -Fxq "usr/local/bin/swiftpkg" "$COMBINED_PAYLOAD" ||
    fail "combined installer does not contain the CLI"
grep -Fq "Applications/Swiftpkgr.app/Contents/MacOS/Swiftpkgr" "$COMBINED_PAYLOAD" ||
    fail "combined installer does not contain Swiftpkgr.app"
grep -Fxq "usr/local/bin/swiftpkg" "$CLI_PAYLOAD" ||
    fail "CLI installer does not contain the CLI"
if grep -Fq "Applications/Swiftpkgr.app" "$CLI_PAYLOAD"; then
    fail "CLI installer unexpectedly contains Swiftpkgr.app"
fi

mkdir -p "$DIST"
rm -f \
    "$DIST/swiftpkg-$VERSION-universal.pkg" \
    "$DIST/$COMBINED_PACKAGE_NAME" \
    "$DIST/$CLI_PACKAGE_NAME" \
    "$DIST/$APP_ARCHIVE_NAME" \
    "$DIST/$TARBALL_NAME" \
    "$DIST/SHA256SUMS"
ditto "$COMBINED_PACKAGE" "$DIST/$COMBINED_PACKAGE_NAME"
ditto "$CLI_PACKAGE" "$DIST/$CLI_PACKAGE_NAME"
ditto -c -k --keepParent "$APP_PRODUCT" "$DIST/$APP_ARCHIVE_NAME"
tar -C "$CLI_PRODUCTS" -czf "$DIST/$TARBALL_NAME" swiftpkg

APP_ARCHIVE_VALIDATION="$WORK/app-archive-validation"
mkdir -p "$APP_ARCHIVE_VALIDATION"
ditto -x -k "$DIST/$APP_ARCHIVE_NAME" "$APP_ARCHIVE_VALIDATION"
ARCHIVED_APP="$APP_ARCHIVE_VALIDATION/Swiftpkgr.app"
[ -d "$ARCHIVED_APP" ] || fail "$APP_ARCHIVE_NAME does not contain Swiftpkgr.app"
codesign --verify --deep --strict --verbose=2 "$ARCHIVED_APP"
xcrun stapler validate "$ARCHIVED_APP"
spctl --assess --type execute --verbose=4 "$ARCHIVED_APP"
[ "$(plutil -extract CFBundleShortVersionString raw "$ARCHIVED_APP/Contents/Info.plist")" = "$VERSION" ] ||
    fail "archived app version does not match VERSION"

(
    cd "$DIST"
    shasum -a 256 \
        "$COMBINED_PACKAGE_NAME" \
        "$CLI_PACKAGE_NAME" \
        "$APP_ARCHIVE_NAME" \
        "$TARBALL_NAME" > SHA256SUMS
)

[ "$MODE" != "--build" ] || {
    echo "Release artifacts: $DIST"
    exit 0
}

if ! git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    git -C "$ROOT" tag -a "$TAG" -m "swiftpkg $VERSION"
fi

if gh release view "$TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
    fail "$TAG already has a GitHub Release; release assets are immutable"
fi
git -C "$ROOT" push "$GIT_REMOTE" "$RELEASE_BRANCH"
git -C "$ROOT" push "$GIT_REMOTE" "refs/tags/$TAG"

gh release create "$TAG" \
    "$DIST/$COMBINED_PACKAGE_NAME" \
    "$DIST/$CLI_PACKAGE_NAME" \
    "$DIST/$APP_ARCHIVE_NAME" \
    "$DIST/$TARBALL_NAME" \
    "$DIST/SHA256SUMS" \
    --repo "$GITHUB_REPOSITORY" \
    --title "swiftpkg $VERSION" \
    --verify-tag \
    --generate-notes

CLI_SHA256=$(awk -v name="$TARBALL_NAME" '$2 == name { print $1 }' "$DIST/SHA256SUMS")
APP_SHA256=$(awk -v name="$APP_ARCHIVE_NAME" '$2 == name { print $1 }' "$DIST/SHA256SUMS")
[ -n "$CLI_SHA256" ] || fail "could not read the Homebrew CLI checksum"
[ -n "$APP_SHA256" ] || fail "could not read the Homebrew app checksum"
CLI_URL="https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG/$TARBALL_NAME"
APP_URL="https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG/$APP_ARCHIVE_NAME"
GH_TOKEN="$HOMEBREW_TAP_DISPATCH_TOKEN" gh api \
    --method POST \
    "repos/$HOMEBREW_TAP_REPOSITORY/dispatches" \
    -f event_type=swiftpkg-release \
    -f "client_payload[version]=$VERSION" \
    -f "client_payload[cli_url]=$CLI_URL" \
    -f "client_payload[cli_sha256]=$CLI_SHA256" \
    -f "client_payload[app_url]=$APP_URL" \
    -f "client_payload[app_sha256]=$APP_SHA256"

echo "Published $TAG to $GITHUB_REPOSITORY"
echo "Requested Homebrew formula and cask updates in $HOMEBREW_TAP_REPOSITORY"
echo "Release artifacts: $DIST"
