#!/usr/bin/env bash
# Single-quoted strings generate test executables.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_HOME="$(mktemp -d)"
trap 'rm -rf -- "$TEST_HOME"' EXIT

export HOME="$TEST_HOME/home"
export XDG_RUNTIME_DIR="$TEST_HOME/run"
export BLIZL_HANDY_SKIP_RUNTIME_RESTORE=true
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }
assert_file() { [[ -e "$1" ]] || fail "expected file: $1"; }
assert_absent() { [[ ! -e "$1" ]] || fail "expected absent: $1"; }

# The library is read-only by contract: nothing it exposes may modify the
# Hyprland bindings file, because Hyprland executes that file as Lua.
test_bindings_library_never_writes_the_file() {
  local file="$TEST_HOME/bindings.lua" before after
  cat >"$file" <<'LUA'
o.bind("F9", "Open terminal", "kitty")
o.bind("ALT + SPACE", "Toggle dictation", "voxtype record toggle")
LUA
  before="$(sha256sum -- "$file" | awk '{print $1}')"
  # shellcheck source=../lib/bindings.sh
  # Test paths are resolved at runtime.
  # shellcheck disable=SC1091
  source "$ROOT/lib/bindings.sh"
  bindings_validate "$file" || fail "bindings syntax validation failed"
  bindings_detect_voxtype_key "$file" >/dev/null
  bindings_detect_voxtype_keys "$file" >/dev/null
  bindings_action_for_key "$file" 'ALT + SPACE' >/dev/null
  bindings_locate_key "$file" 'ALT + SPACE' >/dev/null
  after="$(sha256sum -- "$file" | awk '{print $1}')"
  assert_eq "$after" "$before"
}

test_settings_preserve_and_reject_malformed() {
  local file="$TEST_HOME/settings.json"
  cat >"$file" <<'JSON'
{"settings":{"bindings":{"transcribe":{"current_binding":"alt+space","other":true}},"unrelated":{"keep":"me"}},"top":42}
JSON
  # shellcheck source=../lib/handy-settings.sh
  # Test paths are resolved at runtime.
  # shellcheck disable=SC1091
  source "$ROOT/lib/handy-settings.sh"
  handy_settings_set_shortcut "$file" "ALT + SPACE"
  assert_eq "$(jq -r '.settings.bindings.transcribe.current_binding' "$file")" 'alt+space'
  assert_eq "$(jq -r '.settings.keyboard_implementation' "$file")" 'handy_keys'
  assert_eq "$(jq -r '.settings.push_to_talk' "$file")" false
  assert_eq "$(jq -r '.settings.unrelated.keep' "$file")" me
  assert_eq "$(jq -r '.top' "$file")" 42
  printf '{broken\n' >"$file"
  if handy_settings_set_shortcut "$file" "ALT + SPACE" 2>/dev/null; then
    fail 'malformed Handy settings were accepted'
  fi
}

test_transaction_restores_absent_and_present_targets() {
  local state="$HOME/.local/state/test" present="$HOME/.config/present" absent="$HOME/.config/absent"
  mkdir -p "$(dirname "$present")" "$state"
  printf before >"$present"
  # shellcheck source=../lib/transaction.sh
  # Test paths are resolved at runtime.
  # shellcheck disable=SC1091
  source "$ROOT/lib/transaction.sh"
  transaction_begin "$state"
  transaction_backup "$present"
  transaction_backup "$absent"
  printf after >"$present"
  printf created >"$absent"
  transaction_restore "$TRANSACTION_DIR"
  assert_eq "$(<"$present")" before
  assert_absent "$absent"
}

test_transaction_rejects_symlink_escape() {
  local outside="$TEST_HOME/transaction-outside" link="$HOME/.config/escape"
  mkdir -p "$outside" "$(dirname -- "$link")"
  printf keep >"$outside/file"
  ln -s "$outside" "$link"
  # shellcheck source=../lib/transaction.sh
  # Test paths are resolved at runtime.
  # shellcheck disable=SC1091
  source "$ROOT/lib/transaction.sh"
  if transaction_safe_target "$link/file"; then
    fail 'transaction accepted a target resolving outside the user config roots'
  fi
}

test_checkpoint_round_trip_and_absent_manifest() {
  local state="$TEST_HOME/state" target="$HOME/.config/hypr/bindings.lua" id
  mkdir -p "$(dirname "$target")" "$state"
  printf baseline >"$target"
  export BLIZL_HANDY_STATE_DIR="$state"
  export BLIZL_HANDY_CHECKPOINT_PATHS="$target:$HOME/.config/omarchy/plugins/blizl.handy"
  id="$("$ROOT/bin/e2e-checkpoint" create)"
  assert_file "$state/e2e-checkpoints/$id/manifest.json"
  printf changed >"$target"
  mkdir -p "$HOME/.config/omarchy/plugins/blizl.handy"
  printf created >"$HOME/.config/omarchy/plugins/blizl.handy/new"
  "$ROOT/bin/e2e-checkpoint" verify "$id"
  "$ROOT/bin/e2e-checkpoint" restore "$id"
  assert_eq "$(<"$target")" baseline
  assert_absent "$HOME/.config/omarchy/plugins/blizl.handy"
  "$ROOT/bin/e2e-checkpoint" discard "$id"
  assert_absent "$state/e2e-checkpoints/$id"
}

test_checkpoint_rejects_unsafe_target() {
  export BLIZL_HANDY_STATE_DIR="$TEST_HOME/state-unsafe"
  export BLIZL_HANDY_CHECKPOINT_PATHS="/tmp/outside"
  if "$ROOT/bin/e2e-checkpoint" create >/dev/null 2>&1; then
    fail 'checkpoint accepted an unsafe path'
  fi
}

test_checkpoint_detects_archive_tampering() {
  local state="$TEST_HOME/state-tamper" target="$HOME/.config/tamper" id archive
  mkdir -p "$(dirname "$target")"
  printf baseline >"$target"
  export BLIZL_HANDY_STATE_DIR="$state"
  export BLIZL_HANDY_CHECKPOINT_PATHS="$target"
  id="$("$ROOT/bin/e2e-checkpoint" create)"
  archive="$state/e2e-checkpoints/$id/files/${target#/}"
  printf tampered >"$archive"
  if "$ROOT/bin/e2e-checkpoint" verify "$id"; then fail 'tampered archive was accepted'; fi
  if "$ROOT/bin/e2e-checkpoint" discard '../' 2>/dev/null; then fail 'unsafe discard id was accepted'; fi
  "$ROOT/bin/e2e-checkpoint" discard "$id"
}

test_checkpoint_restores_packages_via_package_manager() {
  local state="$TEST_HOME/state-package" target="$HOME/.config/package-target" id log="$TEST_HOME/pkg-commands.log"
  mkdir -p "$(dirname "$target")" "$state"
  printf baseline >"$target"
  printf '%s\n' '#!/usr/bin/env bash' 'if [[ ${1:-} == -Q ]]; then case ${2:-} in voxtype-bin) echo "voxtype-bin 1.2.3";; handy-bin) echo "handy-bin 0.9.5";; wtype) echo "wtype 0.4";; *) exit 1;; esac; exit 0; fi' 'exit 1' >"$TEST_HOME/pacman"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "add $*" >>"'"$log"'"' >"$TEST_HOME/pkg-add"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "drop $*" >>"'"$log"'"' >"$TEST_HOME/pkg-drop"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$TEST_HOME/systemctl"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$TEST_HOME/hyprctl"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$TEST_HOME/pgrep"
  chmod +x "$TEST_HOME/pacman" "$TEST_HOME/pkg-add" "$TEST_HOME/pkg-drop" "$TEST_HOME/systemctl" "$TEST_HOME/hyprctl" "$TEST_HOME/pgrep"
  export PATH="$TEST_HOME:$PATH" BLIZL_HANDY_STATE_DIR="$state" BLIZL_HANDY_CHECKPOINT_PATHS="$target" BLIZL_HANDY_PKG_ADD_BIN="$TEST_HOME/pkg-add" BLIZL_HANDY_PKG_DROP_BIN="$TEST_HOME/pkg-drop" BLIZL_HANDY_SKIP_RUNTIME_RESTORE=false
  id="$("$ROOT/bin/e2e-checkpoint" create)"
  assert_file "$state/e2e-checkpoints/$id/package-state.json"
  assert_absent "$state/e2e-checkpoints/$id/packages"
  "$ROOT/bin/e2e-checkpoint" verify "$id"
  # Change fake pacman to report voxtype-bin missing
  printf '%s\n' '#!/usr/bin/env bash' 'if [[ ${1:-} == -Q ]]; then case ${2:-} in handy-bin) echo "handy-bin 0.9.5";; wtype) echo "wtype 0.4";; *) exit 1;; esac; exit 0; fi' 'exit 1' >"$TEST_HOME/pacman"
  "$ROOT/bin/e2e-checkpoint" restore "$id"
  grep -Fq 'add voxtype-bin' "$log" || fail 'checkpoint restore did not invoke package add for missing package'
  unset BLIZL_HANDY_PKG_ADD_BIN BLIZL_HANDY_PKG_DROP_BIN
  export BLIZL_HANDY_SKIP_RUNTIME_RESTORE=true
}

test_verify_current_detects_file_mutation() {
  local state="$TEST_HOME/state-current" target="$HOME/.config/current" id
  mkdir -p "$(dirname "$target")"
  printf baseline >"$target"
  export BLIZL_HANDY_STATE_DIR="$state" BLIZL_HANDY_CHECKPOINT_PATHS="$target" BLIZL_HANDY_SKIP_RUNTIME_RESTORE=true
  id="$("$ROOT/bin/e2e-checkpoint" create)"
  "$ROOT/bin/e2e-checkpoint" verify-current "$id" baseline
  printf changed >"$target"
  if "$ROOT/bin/e2e-checkpoint" verify-current "$id" baseline; then fail 'current mutation was accepted'; fi
}

test_checkpoint_rejects_symlink_escape_and_archive_traversal() {
  local state="$TEST_HOME/state-hostile" outside="$TEST_HOME/outside" link="$HOME/.config/escape" target="$HOME/.config/safe" id manifest
  mkdir -p "$outside" "$(dirname "$link")"
  ln -s "$outside" "$link"
  export BLIZL_HANDY_STATE_DIR="$state" BLIZL_HANDY_CHECKPOINT_PATHS="$link/secret"
  if "$ROOT/bin/e2e-checkpoint" create >/dev/null 2>&1; then fail 'symlink escape was accepted'; fi
  rm -f "$link"
  mkdir -p "$(dirname "$target")"
  printf baseline >"$target"
  export BLIZL_HANDY_CHECKPOINT_PATHS="$target"
  id="$("$ROOT/bin/e2e-checkpoint" create)"
  manifest="$state/e2e-checkpoints/$id/manifest.json"
  jq '.[0].archive = "files/../outside"' "$manifest" >"$manifest.tmp"
  mv "$manifest.tmp" "$manifest"
  if "$ROOT/bin/e2e-checkpoint" verify "$id"; then fail 'manifest traversal was accepted'; fi
}

test_default_checkpoint_paths_are_all_data() {
  unset BLIZL_HANDY_CHECKPOINT_PATHS
  local checkpoint_output
  checkpoint_output="$(
    source "$ROOT/lib/checkpoint.sh"
    checkpoint_paths
  )"
  grep -F -- "$HOME/.local/state/blizl.handy/baseline-hypr-errors.txt" <<<"$checkpoint_output" >/dev/null || fail 'default checkpoint paths stopped early'
}

test_checkpoint_rejects_injected_package_names() {
  local state="$TEST_HOME/state-pkg-inject" target="$HOME/.config/pkg-inject" id log="$TEST_HOME/pkg-inject.log" state_file
  mkdir -p "$(dirname "$target")" "$state"
  printf baseline >"$target"
  printf '%s\n' '#!/usr/bin/env bash' 'if [[ ${1:-} == -Q ]]; then case ${2:-} in handy-bin) echo "handy-bin 0.9.5";; wtype) echo "wtype 0.4";; *) exit 1;; esac; exit 0; fi' 'exit 1' >"$TEST_HOME/pacman"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "add $*" >>"'"$log"'"' >"$TEST_HOME/pkg-add"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "drop $*" >>"'"$log"'"' >"$TEST_HOME/pkg-drop"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$TEST_HOME/systemctl"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$TEST_HOME/hyprctl"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$TEST_HOME/pgrep"
  chmod +x "$TEST_HOME/pacman" "$TEST_HOME/pkg-add" "$TEST_HOME/pkg-drop" "$TEST_HOME/systemctl" "$TEST_HOME/hyprctl" "$TEST_HOME/pgrep"
  export PATH="$TEST_HOME:$PATH" BLIZL_HANDY_STATE_DIR="$state" BLIZL_HANDY_CHECKPOINT_PATHS="$target" \
    BLIZL_HANDY_PKG_ADD_BIN="$TEST_HOME/pkg-add" BLIZL_HANDY_PKG_DROP_BIN="$TEST_HOME/pkg-drop" BLIZL_HANDY_SKIP_RUNTIME_RESTORE=false
  id="$("$ROOT/bin/e2e-checkpoint" create)"
  state_file="$state/e2e-checkpoints/$id/package-state.json"

  # A same-user process appends an unmanaged package it wants installed.
  jq '. + [{name:"malicious-pkg",version:"1.0",present:true}]' "$state_file" >"$state_file.tmp" && mv "$state_file.tmp" "$state_file"
  if "$ROOT/bin/e2e-checkpoint" verify "$id"; then fail 'injected package name was accepted by verify'; fi
  if "$ROOT/bin/e2e-checkpoint" restore "$id" >/dev/null 2>&1; then fail 'restore ran with an injected package name'; fi

  # A same-user process renames a managed entry to stage a system package removal.
  jq 'map(if .name == "wtype" then .name = "linux" | .present = false else . end)' "$state_file" >"$state_file.tmp" && mv "$state_file.tmp" "$state_file"
  if "$ROOT/bin/e2e-checkpoint" verify "$id"; then fail 'renamed package entry was accepted by verify'; fi
  if "$ROOT/bin/e2e-checkpoint" restore "$id" >/dev/null 2>&1; then fail 'restore ran with a renamed package entry'; fi

  if [[ -f "$log" ]] && grep -Eq 'malicious-pkg|linux' "$log"; then
    fail 'an unmanaged package name reached the package manager'
  fi
  unset BLIZL_HANDY_PKG_ADD_BIN BLIZL_HANDY_PKG_DROP_BIN
  export BLIZL_HANDY_SKIP_RUNTIME_RESTORE=true
}

test_no_sudo_pacman_u_in_scripts() {
  if grep -En 'sudo\s+pacman\s+-U' "$ROOT/bin/"* "$ROOT/lib/"*; then
    fail 'found sudo pacman -U invocation in scripts'
  fi
}

test_bindings_library_never_writes_the_file
test_settings_preserve_and_reject_malformed
test_transaction_restores_absent_and_present_targets
test_transaction_rejects_symlink_escape
test_checkpoint_round_trip_and_absent_manifest
test_checkpoint_rejects_unsafe_target
test_checkpoint_detects_archive_tampering
test_checkpoint_restores_packages_via_package_manager
test_checkpoint_rejects_injected_package_names
test_verify_current_detects_file_mutation
test_checkpoint_rejects_symlink_escape_and_archive_traversal
test_default_checkpoint_paths_are_all_data
test_no_sudo_pacman_u_in_scripts
printf 'lifecycle tests: ok\n'
