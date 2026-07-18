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

OVERRIDE="$WORK/Override"
run "$BIN" --create "$OVERRIDE"
mkdir -p "$OVERRIDE/payload/usr/local/bin"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$OVERRIDE/payload/usr/local/bin/tool"
run "$BIN" --pkg-version 3.1.4 --output-dir "$WORK/artifacts" "$OVERRIDE"
test -f "$WORK/artifacts/Override-3.1.4.pkg"
test ! -e "$OVERRIDE/build/Override-3.1.4.pkg"

DISTRIBUTION="$WORK/Distribution"
run "$BIN" --create --json "$DISTRIBUTION"
printf '%s\n' '{' '  "name": "Distribution-${version}.pkg",' '  "identifier": "com.example.distribution",' '  "version": "2.0",' '  "title": "Distribution 2.0",' '  "ownership": "recommended",' '  "postinstall_action": "none",' '  "distribution_style": true' '}' > "$DISTRIBUTION/build-info.json"
printf '%s\n' 'distribution' > "$DISTRIBUTION/payload/distribution.txt"
run "$BIN" "$DISTRIBUTION"
test -f "$DISTRIBUTION/build/Distribution-2.0.pkg"
run /usr/sbin/pkgutil --expand "$DISTRIBUTION/build/Distribution-2.0.pkg" "$WORK/expanded-distribution"
test -f "$WORK/expanded-distribution/Distribution"

printf '%s\n' "verification passed: $WORK"
