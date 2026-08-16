#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

fail() {
  printf 'voxtype settings test: %s\n' "$*" >&2
  exit 1
}
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }

# shellcheck disable=SC1091
source "$ROOT/lib/voxtype-settings.sh"

test_reports_enabled_hotkey() {
  local file="$WORK/enabled.toml"
  printf '%s\n' '[hotkey]' 'enabled = true' '[audio]' 'enabled = false' >"$file"
  voxtype_hotkey_enabled "$file" || fail 'enabled hotkey was not reported as enabled'
}

test_false_and_absent_hotkeys_are_not_enabled() {
  local false_file="$WORK/false.toml" absent_file="$WORK/absent.toml"
  printf '%s\n' '[hotkey]' 'enabled = false' >"$false_file"
  printf '%s\n' '[audio]' 'enabled = true' >"$absent_file"
  if voxtype_hotkey_enabled "$false_file"; then fail 'false hotkey was reported as enabled'; fi
  if voxtype_hotkey_enabled "$absent_file"; then fail 'absent hotkey was reported as enabled'; fi
}

test_reads_native_alt_space_hotkey() {
  local file="$WORK/alt-space.toml"
  printf '%s\n' '[hotkey]' 'enabled = true' 'key = "SPACE"' \
    'modifiers = ["LEFTALT"]' >"$file"
  assert_eq "$(voxtype_hotkey_shortcut "$file")" 'ALT + SPACE'
}

test_reads_native_multi_modifier_hotkey() {
  local file="$WORK/multi-modifier.toml"
  printf '%s\n' '[hotkey]' 'enabled = true' 'key = "X"' \
    'modifiers = ["LEFTCTRL", "LEFTSHIFT"]' >"$file"
  assert_eq "$(voxtype_hotkey_shortcut "$file")" 'CTRL + SHIFT + X'
}

test_reads_native_alt_enter_hotkey() {
  local file="$WORK/alt-enter.toml"
  printf '%s\n' '[hotkey]' 'enabled = true' 'key = "ENTER"' \
    'modifiers = ["LEFTALT"]' >"$file"
  assert_eq "$(voxtype_hotkey_shortcut "$file")" 'ALT + ENTER'
}

test_rejects_malformed_native_hotkey() {
  local file="$WORK/malformed-hotkey.toml" modifiers="$WORK/malformed-modifiers.toml"
  printf '%s\n' '[hotkey]' 'enabled = true' 'key = ENTER' >"$file"
  if voxtype_hotkey_shortcut "$file" >/dev/null; then
    fail 'malformed native key was accepted'
  fi
  printf '%s\n' '[hotkey]' 'enabled = true' 'key = "ENTER"' \
    'modifiers = [LEFTALT]' >"$modifiers"
  if voxtype_hotkey_shortcut "$modifiers" >/dev/null; then
    fail 'unquoted native modifier was accepted'
  fi
}

test_normalizes_modifier_order_and_spacing() {
  assert_eq "$(voxtype_shortcut_normalize 'ALT+CTRL+X')" 'CTRL+ALT+X'
  voxtype_shortcuts_equal 'ALT + CTRL + X' 'CTRL+ALT+X' ||
    fail 'equivalent modifier chords were not matched'
}

test_disable_changes_only_true_value_and_is_atomic() {
  local file="$WORK/change.toml" before after expected
  printf '%s\n' '# keep this comment' 'state_file = "auto"' '' '[hotkey]' \
    'enabled = true # preserve this comment' 'other = "unchanged"' '' '[audio]' \
    'enabled = true' >"$file"
  before="$(<"$file")"
  voxtype_hotkey_disable "$file"
  after="$(<"$file")"
  assert_eq "$(grep -Fc 'enabled = false # preserve this comment' "$file")" 1
  assert_eq "$(grep -Fc 'enabled = true' "$file")" 1
  expected="$(printf '%s\n' "$before" | sed 's/enabled = true # preserve this comment/enabled = false # preserve this comment/')"
  assert_eq "$after" "$expected"
  if voxtype_hotkey_enabled "$file"; then fail 'disabled hotkey remained enabled'; fi
}

test_disable_returns_no_change_for_absent_or_false() {
  local absent="$WORK/no-section.toml" false_file="$WORK/no-change.toml" status
  printf '%s\n' '[audio]' 'enabled = true' >"$absent"
  printf '%s\n' '[hotkey]' 'enabled = false' >"$false_file"
  set +e
  voxtype_hotkey_disable "$absent"
  status=$?
  set -e
  assert_eq "$status" "$VOXTYPE_SETTINGS_NO_CHANGE"
  set +e
  voxtype_hotkey_disable "$false_file"
  status=$?
  set -e
  assert_eq "$status" "$VOXTYPE_SETTINGS_NO_CHANGE"
}

test_disable_rejects_malformed_hotkey_sections_without_mutating() {
  local duplicate="$WORK/duplicate.toml" missing="$WORK/missing.toml" before status
  printf '%s\n' '[hotkey]' 'enabled = true' 'enabled = false' >"$duplicate"
  printf '%s\n' '[hotkey]' 'other = true' >"$missing"
  before="$(<"$duplicate")"
  set +e
  voxtype_hotkey_disable "$duplicate"
  status=$?
  set -e
  assert_eq "$status" "$VOXTYPE_SETTINGS_ERROR"
  assert_eq "$(<"$duplicate")" "$before"
  set +e
  voxtype_hotkey_disable "$missing"
  status=$?
  set -e
  assert_eq "$status" "$VOXTYPE_SETTINGS_ERROR"
}

test_reports_enabled_hotkey
test_false_and_absent_hotkeys_are_not_enabled
test_reads_native_alt_space_hotkey
test_reads_native_multi_modifier_hotkey
test_reads_native_alt_enter_hotkey
test_rejects_malformed_native_hotkey
test_normalizes_modifier_order_and_spacing
test_disable_changes_only_true_value_and_is_atomic
test_disable_returns_no_change_for_absent_or_false
test_disable_rejects_malformed_hotkey_sections_without_mutating
printf 'voxtype settings tests: ok\n'
