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

assert_file_not_contains() {
  local file="$1"
  local unexpected="$2"
  if grep -Fq -- "$unexpected" "$file"; then
    fail "$file unexpectedly contains '$unexpected'"
  fi
}

assert_line_before() {
  local file="$1"
  local first="$2"
  local second="$3"
  local first_line second_line
  first_line="$(grep -n -m 1 -F -- "$first" "$file" | cut -d: -f1)"
  second_line="$(grep -n -m 1 -F -- "$second" "$file" | cut -d: -f1)"
  [ -n "$first_line" ] || fail "$file does not contain '$first'"
  [ -n "$second_line" ] || fail "$file does not contain '$second'"
  [ "$first_line" -lt "$second_line" ] || fail "$file checks '$first' after '$second'"
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
  assert_contains "$contents" 'BEGIN SWIFTPKG_INSTALL_CONTRACT' "$file"
  assert_contains "$contents" 'END SWIFTPKG_INSTALL_CONTRACT' "$file"
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
  assert_line_before "$file" 'END SWIFTPKG_COMPATIBILITY_CONTRACT' 'BEGIN SWIFTPKG_BUILD_CONTRACT'
  if [ "$template" = azure ]; then
    assert_contains "$contents" 'asset_count=' "$file"
    assert_line_before "$file" 'END SWIFTPKG_COMPATIBILITY_CONTRACT' '- bash: swiftpkg --lint'
  else
    assert_line_before "$file" 'END SWIFTPKG_COMPATIBILITY_CONTRACT' 'run: swiftpkg --lint'
  fi
done

FAKE_BIN="$TEMP_ROOT/bin"
mkdir -p "$FAKE_BIN"
FAKE_SWIFTPKG="$FAKE_BIN/swiftpkg"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [ -n "${FAKE_SWIFTPKG_CALLS:-}" ]; then printf "%s\\n" "$*" >> "$FAKE_SWIFTPKG_CALLS"; fi' \
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

FAKE_GH="$FAKE_BIN/gh"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\\n" "$*" >> "${FAKE_RELEASE_CALLS:?}"' \
  'directory=' \
  'previous=' \
  'for arg in "$@"; do' \
  '  if [ "$previous" = "--dir" ]; then directory="$arg"; fi' \
  '  previous="$arg"' \
  'done' \
  '[ -n "$directory" ]' \
  'package="$directory/swiftpkg-${FAKE_RELEASE_VERSION:?}-cli.pkg"' \
  'printf "%s\\n" fake-installer > "$package"' \
  'checksum="$(shasum -a 256 "$package")"' \
  'checksum="${checksum%% *}"' \
  'printf "%s  %s\\n" "$checksum" "$(basename "$package")" > "$directory/SHA256SUMS"' \
  > "$FAKE_GH"
chmod +x "$FAKE_GH"

FAKE_CURL="$FAKE_BIN/curl"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'url=' \
  'destination=' \
  'previous=' \
  'for arg in "$@"; do' \
  '  if [ "$previous" = "-o" ]; then destination="$arg"; fi' \
  '  url="$arg"' \
  '  previous="$arg"' \
  'done' \
  'printf "%s\\n" "$*" >> "${FAKE_RELEASE_CALLS:?}"' \
  'if [ -z "$destination" ]; then' \
  '  printf "%s\\n" "${FAKE_RELEASE_JSON:?}"' \
  'elif [ "$url" = "https://fake/SHA256SUMS" ]; then' \
  '  package="${AGENT_TEMPDIRECTORY:?}/swiftpkg-${FAKE_RELEASE_VERSION:?}-cli.pkg"' \
  '  checksum="$(shasum -a 256 "$package")"' \
  '  checksum="${checksum%% *}"' \
  '  printf "%s  %s\\n" "$checksum" "$(basename "$package")" > "$destination"' \
  'else' \
  '  printf "%s\\n" fake-installer > "$destination"' \
  'fi' \
  > "$FAKE_CURL"
chmod +x "$FAKE_CURL"

FAKE_PKGUTIL="$FAKE_BIN/pkgutil"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [ "${1:-}" = "--check-signature" ]; then' \
  '  printf "%s\\n" "Package: ${2:?}" "Status: signed" "Developer ID Installer: swiftpkg (${EXPECTED_TEAM_ID:?})"' \
  'fi' \
  > "$FAKE_PKGUTIL"
chmod +x "$FAKE_PKGUTIL"

FAKE_SPCTL="$FAKE_BIN/spctl"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'exit 0' \
  > "$FAKE_SPCTL"
chmod +x "$FAKE_SPCTL"

FAKE_SUDO="$FAKE_BIN/sudo"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\\n" "$*" >> "${FAKE_ROOT_COMMANDS:?}"' \
  > "$FAKE_SUDO"
chmod +x "$FAKE_SUDO"

release_json_for_version() {
  local version="$1"
  printf '{"assets":[{"name":"swiftpkg-%s-cli.pkg","browser_download_url":"https://fake/swiftpkg-%s-cli.pkg"},{"name":"SHA256SUMS","browser_download_url":"https://fake/SHA256SUMS"}]}\n' \
    "$version" "$version"
}

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

run_install_contract() {
  local name="$1"
  local file="$2"
  local selected_version="$3"
  local release_version="$4"
  local release_json="$5"
  local should_pass="$6"
  local expected_message="$7"
  local block wrapper stdout stderr calls root_calls swift_calls sentinel runner_tmp agent_tmp status

  block="$(extract_block "$file" 'BEGIN SWIFTPKG_INSTALL_CONTRACT' 'END SWIFTPKG_INSTALL_CONTRACT')"
  [ -n "$block" ] || fail "$file install contract is empty"
  stdout="$TEMP_ROOT/$name-install.stdout"
  stderr="$TEMP_ROOT/$name-install.stderr"
  calls="$TEMP_ROOT/$name-release.calls"
  root_calls="$TEMP_ROOT/$name-root.calls"
  swift_calls="$TEMP_ROOT/$name-swiftpkg.calls"
  sentinel="$TEMP_ROOT/$name-project-executed"
  runner_tmp="$TEMP_ROOT/$name-runner"
  agent_tmp="$TEMP_ROOT/$name-agent"
  mkdir -p "$runner_tmp" "$agent_tmp"
  : > "$calls"
  : > "$root_calls"
  : > "$swift_calls"
  wrapper="$block
printf \"%s\\n\" project-execution > \"$sentinel\""

  if [ "$file" = "$ACTION" ]; then
    if [ "$selected_version" = default ]; then
      if (
        unset SWIFTPKG_VERSION
        PATH="$FAKE_BIN:$PATH" \
        RUNNER_TEMP="$runner_tmp" \
        SWIFTPKG_SHA256='' \
        EXPECTED_TEAM_ID='DPXY7JLK67' \
        GH_TOKEN='' \
        FAKE_RELEASE_VERSION="$release_version" \
        FAKE_RELEASE_CALLS="$calls" \
        FAKE_ROOT_COMMANDS="$root_calls" \
        FAKE_SWIFTPKG_CALLS="$swift_calls" \
        FAKE_SWIFTPKG_VERSION="$release_version" \
        FAKE_SWIFTPKG_HELP="$ALL_OPTIONS" \
        bash -c "$wrapper" > "$stdout" 2> "$stderr"
      ); then
        status=0
      else
        status=$?
      fi
    else
      if PATH="$FAKE_BIN:$PATH" \
        SWIFTPKG_VERSION="$selected_version" \
        RUNNER_TEMP="$runner_tmp" \
        SWIFTPKG_SHA256='' \
        EXPECTED_TEAM_ID='DPXY7JLK67' \
        GH_TOKEN='' \
        FAKE_RELEASE_VERSION="$release_version" \
        FAKE_RELEASE_CALLS="$calls" \
        FAKE_ROOT_COMMANDS="$root_calls" \
        FAKE_SWIFTPKG_CALLS="$swift_calls" \
        FAKE_SWIFTPKG_VERSION="$release_version" \
        FAKE_SWIFTPKG_HELP="$ALL_OPTIONS" \
        bash -c "$wrapper" > "$stdout" 2> "$stderr"; then
        status=0
      else
        status=$?
      fi
    fi
  elif [ "$selected_version" = default ]; then
    if (
      unset SWIFTPKG_VERSION
      PATH="$FAKE_BIN:$PATH" \
      AGENT_TEMPDIRECTORY="$agent_tmp" \
      SWIFTPKG_SHA256='' \
      EXPECTED_TEAM_ID='DPXY7JLK67' \
      FAKE_RELEASE_VERSION="$release_version" \
      FAKE_RELEASE_JSON="$release_json" \
      FAKE_RELEASE_CALLS="$calls" \
      FAKE_ROOT_COMMANDS="$root_calls" \
      FAKE_SWIFTPKG_CALLS="$swift_calls" \
      FAKE_SWIFTPKG_VERSION="$release_version" \
      FAKE_SWIFTPKG_HELP="$ALL_OPTIONS" \
      bash -c "$wrapper" > "$stdout" 2> "$stderr"
    ); then
      status=0
    else
      status=$?
    fi
  else
    if PATH="$FAKE_BIN:$PATH" \
      SWIFTPKG_VERSION="$selected_version" \
      AGENT_TEMPDIRECTORY="$agent_tmp" \
      SWIFTPKG_SHA256='' \
      EXPECTED_TEAM_ID='DPXY7JLK67' \
      FAKE_RELEASE_VERSION="$release_version" \
      FAKE_RELEASE_JSON="$release_json" \
      FAKE_RELEASE_CALLS="$calls" \
      FAKE_ROOT_COMMANDS="$root_calls" \
      FAKE_SWIFTPKG_CALLS="$swift_calls" \
      FAKE_SWIFTPKG_VERSION="$release_version" \
      FAKE_SWIFTPKG_HELP="$ALL_OPTIONS" \
      bash -c "$wrapper" > "$stdout" 2> "$stderr"; then
      status=0
    else
      status=$?
    fi
  fi

  if [ "$should_pass" = true ]; then
    [ "$status" -eq 0 ] || {
      cat "$stdout" "$stderr" >&2
      fail "$file rejected the compatible default release"
    }
    [ -f "$sentinel" ] || fail "$file did not complete its install contract"
    if [ "$selected_version" = default ]; then
      if [ "$file" = "$ACTION" ]; then
        assert_file_contains "$calls" 'release download v0.4.0'
      else
        assert_file_contains "$calls" '/releases/tags/v0.4.0'
      fi
    fi
  else
    [ "$status" -ne 0 ] || fail "$file accepted an invalid install contract"
    [ ! -e "$sentinel" ] || fail "$file executed the project after a failed install contract"
    if ! grep -Fq -- "$expected_message" "$stdout" "$stderr"; then
      cat "$stdout" "$stderr" >&2
      fail "$file did not explain the failed install contract"
    fi
  fi

  if [ "$selected_version" = 'v0.3.1' ]; then
    assert_file_contains "$swift_calls" '--version'
    assert_file_not_contains "$swift_calls" '--help'
    [ "$(wc -l < "$swift_calls" | tr -d ' ')" -eq 1 ] || {
      cat "$swift_calls" >&2
      fail "$file ran more than the version check for an incompatible release"
    }
  fi
}

release_040="$(release_json_for_version '0.4.0')"
release_031="$(release_json_for_version '0.3.1')"
duplicate_release='{"assets":[{"name":"swiftpkg-0.4.0-cli.pkg","browser_download_url":"https://fake/swiftpkg-0.4.0-cli.pkg"},{"name":"swiftpkg-0.4.0-alt-cli.pkg","browser_download_url":"https://fake/swiftpkg-0.4.0-alt-cli.pkg"},{"name":"SHA256SUMS","browser_download_url":"https://fake/SHA256SUMS"}]}'

# These execute the complete install blocks, with no version input in the two
# default cases. The sentinel appended after the block proves that an
# incompatible release exits before the template can reach lint, build, or a
# project command. Azure also gets an ambiguous release response to exercise
# its exactly-one asset guard before any download or installation.
run_install_contract action-default "$ACTION" default '0.4.0' "$release_040" true ''
run_install_contract azure-default "$AZURE" default '0.4.0' "$release_040" true ''
run_install_contract action-old-release "$ACTION" 'v0.3.1' '0.3.1' "$release_031" false \
  'requires swiftpkg >= 0.4.0'
run_install_contract azure-old-release "$AZURE" 'v0.3.1' '0.3.1' "$release_031" false \
  'requires swiftpkg >= 0.4.0'
run_install_contract azure-ambiguous-release "$AZURE" 'v0.4.0' '0.4.0' "$duplicate_release" false \
  'Expected exactly one swiftpkg CLI package asset'

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
