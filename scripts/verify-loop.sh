#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN="$ROOT/.build/release/swiftpkg"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/swiftpkg-verify.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

for tool in /usr/bin/pkgbuild /usr/sbin/pkgutil; do
    if [ ! -x "$tool" ]; then
        printf '%s\n' "missing required macOS tool: $tool" >&2
        exit 2
    fi
done

swift build --package-path "$ROOT" -c release

run() {
    printf '+ %s\n' "$*"
    "$@"
}

PROJECT="$WORK/Basic"
run "$BIN" --create "$PROJECT"
mkdir -p "$PROJECT/payload/usr/local/bin"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$PROJECT/payload/usr/local/bin/sample-tool"
chmod 755 "$PROJECT/payload/usr/local/bin/sample-tool"
run "$BIN" --export-bom-info "$PROJECT"
test -s "$PROJECT/Bom.txt"
run /usr/sbin/pkgutil --expand "$PROJECT/build/Basic-1.0.pkg" "$WORK/expanded-basic"
test -f "$WORK/expanded-basic/Payload"

IMPORTED="$WORK/Imported"
run "$BIN" --import "$PROJECT/build/Basic-1.0.pkg" "$IMPORTED"
test -f "$IMPORTED/payload/usr/local/bin/sample-tool"
test -f "$IMPORTED/build-info.plist"
run "$BIN" "$IMPORTED"

SCRIPTS="$WORK/Scripts"
run "$BIN" --create "$SCRIPTS"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$SCRIPTS/scripts/postinstall"
printf 'not metadata\n' > "$SCRIPTS/scripts/.DS_Store"
run "$BIN" "$SCRIPTS"
test ! -e "$SCRIPTS/scripts/.DS_Store"
test -x "$SCRIPTS/scripts/postinstall"

NOPAYLOAD="$WORK/NoPayload"
run "$BIN" --create "$NOPAYLOAD"
rm -rf "$NOPAYLOAD/payload"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$NOPAYLOAD/scripts/postinstall"
run "$BIN" "$NOPAYLOAD"
run /usr/sbin/pkgutil --expand "$NOPAYLOAD/build/NoPayload-1.0.pkg" "$WORK/expanded-nopayload"
test ! -e "$WORK/expanded-nopayload/Payload"

EMPTY="$WORK/EmptyPayload"
run "$BIN" --create "$EMPTY"
run "$BIN" "$EMPTY"
run /usr/sbin/pkgutil --expand "$EMPTY/build/EmptyPayload-1.0.pkg" "$WORK/expanded-empty"
test -e "$WORK/expanded-empty/Payload"

RECEIPT="$WORK/ReceiptOnly"
run "$BIN" --create "$RECEIPT"
rm -rf "$RECEIPT/payload" "$RECEIPT/scripts"
run "$BIN" "$RECEIPT"
run /usr/sbin/pkgutil --expand "$RECEIPT/build/ReceiptOnly-1.0.pkg" "$WORK/expanded-receipt"
test ! -e "$WORK/expanded-receipt/Payload"
test ! -e "$WORK/expanded-receipt/Scripts"
printf 'receipt-only package OK\n'

for format in json yaml; do
    PROJECT_FORMAT="$WORK/Format-$format"
    if [ "$format" = json ]; then
        run "$BIN" --create --json "$PROJECT_FORMAT"
    else
        run "$BIN" --create --yaml "$PROJECT_FORMAT"
    fi
    mkdir -p "$PROJECT_FORMAT/payload/Library/Application Support"
    printf '%s\n' "$format" > "$PROJECT_FORMAT/payload/Library/Application Support/format.txt"
    run "$BIN" "$PROJECT_FORMAT"
    test -f "$PROJECT_FORMAT/build/Format-$format-1.0.pkg"
done

VERIFY="$WORK/Verify"
run "$BIN" --create "$VERIFY"
mkdir -p "$VERIFY/payload/usr/local/bin"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$VERIFY/payload/usr/local/bin/tool"
run "$BIN" --verify "$VERIFY"
test -f "$VERIFY/build/Verify-1.0.pkg"

LINTGOOD="$WORK/LintGood"
run "$BIN" --create "$LINTGOOD"
mkdir -p "$LINTGOOD/payload"
printf 'x\n' > "$LINTGOOD/payload/file.txt"
run "$BIN" --lint "$LINTGOOD"
LINTBAD="$WORK/LintBad"
mkdir -p "$LINTBAD/payload"
printf 'x\n' > "$LINTBAD/payload/file.txt"
printf '%s\n' '{"name":"../evil.pkg","identifier":"com.example.bad","version":""}' > "$LINTBAD/build-info.json"
if "$BIN" --lint "$LINTBAD"; then
    printf 'lint should have failed on a bad project\n' >&2
    exit 1
fi
printf 'lint rejects bad project OK\n'

MANIFEST="$WORK/Manifest"
run "$BIN" --create "$MANIFEST"
mkdir -p "$MANIFEST/payload/usr/local/bin"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$MANIFEST/payload/usr/local/bin/tool"
chmod +x "$MANIFEST/payload/usr/local/bin/tool"
printf '+ %s\n' "$BIN --output-format json $MANIFEST"
"$BIN" --output-format json "$MANIFEST" > "$WORK/manifest.json"
python3 - "$WORK/manifest.json" "$MANIFEST/build/Manifest-1.0.pkg" <<'PY'
import hashlib, json, os.path, sys

# Explicit checks that raise, rather than assert: `python3 -O`/PYTHONOPTIMIZE
# strips assert statements, which would let a bad manifest print "manifest OK".
def fail(message):
    print("manifest check failed:", message, file=sys.stderr)
    raise SystemExit(1)

manifest = json.load(open(sys.argv[1]))
for key in ("name", "version", "identifier", "pkg_path", "sha256", "signed", "notarized", "stapled"):
    if key not in manifest:
        fail(f"missing key: {key}")
if manifest["name"] != "Manifest-1.0.pkg":
    fail(f'name: {manifest["name"]}')
if manifest["version"] != "1.0":
    fail(f'version: {manifest["version"]}')
if manifest["identifier"] != "com.github.munki.pkg.Manifest":
    fail(f'identifier: {manifest["identifier"]}')
if not (manifest["signed"] is False and manifest["notarized"] is False and manifest["stapled"] is False):
    fail("signed/notarized/stapled are not all false")
if os.path.normpath(manifest["pkg_path"]) != os.path.normpath(sys.argv[2]):
    fail(f'pkg_path: {manifest["pkg_path"]}')
if not os.path.isfile(manifest["pkg_path"]):
    fail(f'pkg not found: {manifest["pkg_path"]}')
digest = hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest()
if manifest["sha256"] != digest:
    fail(f'sha256 mismatch: {manifest["sha256"]} != {digest}')
print("manifest OK")
PY

OVERRIDE="$WORK/Override"
run "$BIN" --create "$OVERRIDE"
mkdir -p "$OVERRIDE/payload/usr/local/bin"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$OVERRIDE/payload/usr/local/bin/tool"
run "$BIN" --pkg-version 3.1.4 --output-dir "$WORK/artifacts" "$OVERRIDE"
test -f "$WORK/artifacts/Override-3.1.4.pkg"
test ! -e "$OVERRIDE/build/Override-3.1.4.pkg"

DYNAMIC="$WORK/Dynamic"
run "$BIN" --create --json "$DYNAMIC"
printf '%s\n' '{' '  "name": "Dyn-${version}.pkg",' '  "identifier": "com.example.dynamic",' '  "version": "${DATE}"' '}' > "$DYNAMIC/build-info.json"
printf '%s\n' 'dyn' > "$DYNAMIC/payload/marker.txt"
run "$BIN" "$DYNAMIC"
DYN_PKG=$(ls "$DYNAMIC/build/")
case "$DYN_PKG" in
    Dyn-[0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9].pkg) printf 'dynamic version OK: %s\n' "$DYN_PKG" ;;
    *) printf 'unexpected dynamic package name: %s\n' "$DYN_PKG" >&2; exit 1 ;;
esac

DISTRIBUTION="$WORK/Distribution"
run "$BIN" --create --json "$DISTRIBUTION"
printf '%s\n' '{' '  "name": "Distribution-${version}.pkg",' '  "identifier": "com.example.distribution",' '  "version": "2.0",' '  "title": "Distribution 2.0",' '  "ownership": "recommended",' '  "postinstall_action": "none",' '  "distribution_style": true' '}' > "$DISTRIBUTION/build-info.json"
printf '%s\n' 'distribution' > "$DISTRIBUTION/payload/distribution.txt"
run "$BIN" "$DISTRIBUTION"
test -f "$DISTRIBUTION/build/Distribution-2.0.pkg"
run /usr/sbin/pkgutil --expand "$DISTRIBUTION/build/Distribution-2.0.pkg" "$WORK/expanded-distribution"
test -f "$WORK/expanded-distribution/Distribution"

printf '%s\n' "verification passed: $WORK"
