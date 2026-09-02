#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION="$ROOT/action.yml"
AZURE="$ROOT/azure-pipelines/swiftpkg-build.yml"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/swiftpkg-ci-contract.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

fail() {
  printf 'CI template contract test failed: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local contents="$1"
  local expected="$2"
  local context="$3"
  case "$contents" in
    *"$expected"*) ;;
    *) fail "$context does not contain '$expected'" ;;
  esac
}

assert_file_contains() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$file" || fail "$file does not contain '$expected'"
}

# Pull a marked bash body out of a YAML block scalar. The first body line sets
# the YAML indentation to remove, so nested shell indentation is preserved.
extract_block() {
  local file="$1"
  local start="$2"
  local end="$3"
  awk -v start="$start" -v end="$end" '
    index($0, start) { capturing = 1; next }
    index($0, end) { capturing = 0; exit }
    capturing {
      if (!indent_set) {
        match($0, /^[ ]*/)
        indent = RLENGTH
        indent_set = 1
      }
      print substr($0, indent + 1)
    }
  ' "$file"
}

action_contents="$(<"$ACTION")"
azure_contents="$(<"$AZURE")"

for template in action azure; do
  if [ "$template" = action ]; then
    contents="$action_contents"
    file="$ACTION"
    checksum_input='swiftpkg-sha256'
  else
    contents="$azure_contents"
    file="$AZURE"
    checksum_input='swiftpkgSha256'
  fi

  assert_contains "$contents" "default: 'v0.4.0'" "$file"
  assert_contains "$contents" 'BEGIN SWIFTPKG_COMPATIBILITY_CONTRACT' "$file"
  assert_contains "$contents" 'END SWIFTPKG_COMPATIBILITY_CONTRACT' "$file"
  assert_contains "$contents" 'BEGIN SWIFTPKG_BUILD_CONTRACT' "$file"
  assert_contains "$contents" 'END SWIFTPKG_BUILD_CONTRACT' "$file"
  assert_contains "$contents" "$checksum_input" "$file"
  assert_contains "$contents" 'SHA256SUMS' "$file"
  assert_contains "$contents" 'pkgutil --check-signature' "$file"
  assert_contains "$contents" 'spctl --assess --type install' "$file"
  assert_contains "$contents" 'jq -er' "$file"
  for option in --output-format --output-dir --pkg-version --lint --verify --provenance; do
    assert_contains "$contents" "$option" "$file"
  done
done

FAKE_BIN="$TEMP_ROOT/bin"
mkdir -p "$FAKE_BIN"
FAKE_SWIFTPKG="$FAKE_BIN/swiftpkg"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'case "${1:-}" in' \
  '  --version) printf "%s\\n" "${FAKE_SWIFTPKG_VERSION:?}" ;;' \
  '  --help) printf "%s\\n" "${FAKE_SWIFTPKG_HELP:?}" ;;' \
  '  *)' \
  '    printf "%s\\n" "$@" > "${FAKE_SWIFTPKG_ARGS:?}"' \
  '    printf "%s\\n" "${FAKE_SWIFTPKG_JSON:?}"' \
  '    ;;' \
  'esac' > "$FAKE_SWIFTPKG"
chmod +x "$FAKE_SWIFTPKG"

ALL_OPTIONS='--output-format --output-dir --pkg-version --lint --verify --provenance'

run_compatibility_contract() {
  local name="$1"
  local file="$2"
  local version="$3"
  local help="$4"
  local should_pass="$5"
  local expected_message="$6"
  local block stdout stderr status

  block="$(extract_block "$file" 'BEGIN SWIFTPKG_COMPATIBILITY_CONTRACT' 'END SWIFTPKG_COMPATIBILITY_CONTRACT')"
  [ -n "$block" ] || fail "$file compatibility contract is empty"
  stdout="$TEMP_ROOT/$name.stdout"
  stderr="$TEMP_ROOT/$name.stderr"
  if PATH="$FAKE_BIN:$PATH" \
    FAKE_SWIFTPKG_VERSION="$version" \
    FAKE_SWIFTPKG_HELP="$help" \
    bash -c "$block" > "$stdout" 2> "$stderr"; then
    status=0
  else
    status=$?
  fi

  if [ "$should_pass" = true ]; then
    [ "$status" -eq 0 ] || {
      cat "$stderr" >&2
      fail "$file rejected compatible swiftpkg $version"
    }
    assert_file_contains "$stdout" "Using swiftpkg $version"
  else
    [ "$status" -ne 0 ] || fail "$file accepted incompatible swiftpkg $version"
    if ! grep -Fq -- "$expected_message" "$stdout" "$stderr"; then
      cat "$stdout" "$stderr" >&2
      fail "$file did not explain why swiftpkg $version is incompatible"
    fi
  fi
}

for template in action azure; do
  if [ "$template" = action ]; then
    file="$ACTION"
  else
    file="$AZURE"
  fi
  run_compatibility_contract \
    "$template-compatible" "$file" '0.4.0' "$ALL_OPTIONS" true ''
  run_compatibility_contract \
    "$template-old-release" "$file" '0.3.1' "$ALL_OPTIONS" false \
    'requires swiftpkg >= 0.4.0'
  run_compatibility_contract \
    "$template-missing-option" "$file" '0.4.0' \
    '--output-format --output-dir --pkg-version --lint --verify' false \
    'missing required option(s): --provenance'
done

run_build_contract() {
  local name="$1"
  local file="$2"
  local block stdout output_file args_file expected_args
  local json='{"pkg_path":"dist/My.pkg","version":"2.3.4","sha256":"deadbeef","name":"My","identifier":"org.example.my","signed":false,"notarized":false,"stapled":false}'

  block="$(extract_block "$file" 'BEGIN SWIFTPKG_BUILD_CONTRACT' 'END SWIFTPKG_BUILD_CONTRACT')"
  [ -n "$block" ] || fail "$file build contract is empty"
  stdout="$TEMP_ROOT/$name-build.stdout"
  output_file="$TEMP_ROOT/$name-github-output"
  args_file="$TEMP_ROOT/$name-args"
  : > "$output_file"
  expected_args="$TEMP_ROOT/$name-expected-args"
  printf '%s\n' \
    '--skip-signing' '--quiet' \
    '--output-format' 'json' '--output-dir' 'dist' \
    '--pkg-version' '2.3.4' '--verify' '--provenance' 'project' \
    > "$expected_args"

  if ! PATH="$FAKE_BIN:$PATH" \
    PROJECT_PATH='project' \
    PKG_VERSION='2.3.4' \
    OUTPUT_DIR='dist' \
    DO_VERIFY='true' \
    DO_PROVENANCE='true' \
    EXTRA_ARGS='--skip-signing --quiet' \
    GITHUB_OUTPUT="$output_file" \
    FAKE_SWIFTPKG_ARGS="$args_file" \
    FAKE_SWIFTPKG_JSON="$json" \
    bash -c "$block" > "$stdout" 2> "$TEMP_ROOT/$name-build.stderr"; then
    cat "$TEMP_ROOT/$name-build.stderr" >&2
    fail "$file failed to build a manifest contract"
  fi
  cmp -s "$expected_args" "$args_file" || {
    printf '%s\n' 'expected arguments:' >&2
    cat "$expected_args" >&2
    printf '%s\n' 'actual arguments:' >&2
    cat "$args_file" >&2
    fail "$file constructed the wrong swiftpkg options"
  }

  if [ "$file" = "$ACTION" ]; then
    printf '%s\n' \
      'pkg-path=dist/My.pkg' \
      'version=2.3.4' \
      'sha256=deadbeef' > "$expected_args"
    cmp -s "$expected_args" "$output_file" || {
      cat "$output_file" >&2
      fail "$file did not expose the JSON manifest as GitHub outputs"
    }
  else
    assert_file_contains "$stdout" '##vso[task.setvariable variable=pkgPath;isOutput=true]dist/My.pkg'
    assert_file_contains "$stdout" '##vso[task.setvariable variable=version;isOutput=true]2.3.4'
    assert_file_contains "$stdout" '##vso[task.setvariable variable=sha256;isOutput=true]deadbeef'
  fi
}

run_invalid_manifest_contract() {
  local name="$1"
  local file="$2"
  local block stdout args_file
  local json='{"version":"2.3.4","sha256":"deadbeef"}'

  block="$(extract_block "$file" 'BEGIN SWIFTPKG_BUILD_CONTRACT' 'END SWIFTPKG_BUILD_CONTRACT')"
  stdout="$TEMP_ROOT/$name-invalid.stdout"
  args_file="$TEMP_ROOT/$name-invalid-args"
  : > "$TEMP_ROOT/$name-invalid-github-output"
  if PATH="$FAKE_BIN:$PATH" \
    PROJECT_PATH='project' \
    PKG_VERSION='' \
    OUTPUT_DIR='dist' \
    DO_VERIFY='false' \
    DO_PROVENANCE='false' \
    EXTRA_ARGS='' \
    GITHUB_OUTPUT="$TEMP_ROOT/$name-invalid-github-output" \
    FAKE_SWIFTPKG_ARGS="$args_file" \
    FAKE_SWIFTPKG_JSON="$json" \
    bash -c "$block" > "$stdout" 2> "$TEMP_ROOT/$name-invalid.stderr"; then
    fail "$file accepted a manifest with a missing pkg_path"
  fi
}

run_build_contract action "$ACTION"
run_build_contract azure "$AZURE"
run_invalid_manifest_contract action "$ACTION"
run_invalid_manifest_contract azure "$AZURE"

printf '%s\n' 'CI template contract tests passed.'
