#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 destination" >&2
    exit 2
fi

DESTINATION=$1
mkdir -p "$DESTINATION"

for DOCUMENT in LICENSE NOTICE RELICENSE.md; do
    SOURCE="$ROOT/$DOCUMENT"
    [ -f "$SOURCE" ] || {
        echo "license document is missing: $SOURCE" >&2
        exit 1
    }
    install -m 644 "$SOURCE" "$DESTINATION/$DOCUMENT"
done
