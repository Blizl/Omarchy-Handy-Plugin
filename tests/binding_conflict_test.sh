#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "expected $1 to contain [$2]"; }

# shellcheck disable=SC1091
source "$ROOT/lib/bindings.sh"
# shellcheck disable=SC1091
source "$ROOT/lib/handy-settings.sh"

test_detects_push_to_talk_over_toggle_across_user_and_stock_files() {
  local user="$WORK/user.lua" stock="$WORK/stock.lua"
  cat >"$user" <<'LUA'
o.bind("SUPER + CTRL + X", "Toggle dictation", "voxtype record toggle")
LUA
  cat >"$stock" <<'LUA'
o.bind("F9", "Start dictation (push-to-talk)", "voxtype record start")
o.bind("F9", "Stop dictation (push-to-talk)", "voxtype record stop", { release = true })
LUA
  assert_eq "$(bindings_detect_voxtype_key "$user" "$stock")" 'F9'
}

test_user_push_to_talk_wins_when_both_sources_have_one() {
  local user="$WORK/user-priority.lua" stock="$WORK/stock-priority.lua"
  printf '%s\n' 'o.bind("ALT + SPACE", "My push-to-talk", "voxtype record start")' >"$user"
  printf '%s\n' 'o.bind("F9", "Start dictation (push-to-talk)", "voxtype record start")' >"$stock"
  assert_eq "$(bindings_detect_voxtype_key "$user" "$stock")" 'ALT + SPACE'
}

test_detects_all_voxtype_entry_points() {
  local user="$WORK/user-all.lua" stock="$WORK/stock-all.lua"
  printf '%s\n' \
    'o.bind("SUPER + CTRL + X", "Toggle dictation", "voxtype record toggle")' \
    'o.bind("F9", "Start dictation", "voxtype record start")' >"$user"
  printf '%s\n' 'o.bind("F9", "Stop dictation", "voxtype record stop", { release = true })' \
    'o.bind("ALT + SPACE", "Other", "other")' >"$stock"
  assert_eq "$(bindings_detect_voxtype_keys "$user" "$stock" | paste -sd, -)" \
    'F9,SUPER + CTRL + X'
}

test_missing_voxtype_bindings_are_not_an_error() {
  local empty="$WORK/empty.lua"
  : >"$empty"
  assert_eq "$(bindings_detect_voxtype_key "$empty" "$WORK/not-installed.lua")" ''
}

test_managed_block_unbinds_even_without_previous_action() {
  local file="$WORK/no-previous.lua"
  printf '%s\n' 'o.bind("F9", "Open terminal", "kitty")' >"$file"
  bindings_write_managed "$file" 'ALT + SPACE' '' "$ROOT/bin/handy-trigger"
  assert_contains "$file" 'hl.unbind("ALT + SPACE")'
  assert_contains "$file" "Dictation push-to-talk is ALT + SPACE via Handy's native evdev hotkey (handy_keys)."
  assert_eq "$(grep -Fc -- 'hl.unbind("ALT + SPACE")' "$file")" 1
  ! grep -Fq -- '-- Previous action:' "$file" || fail 'unexpected previous-action comment'
}

test_detects_non_string_action_conflicts() {
  local file="$WORK/table-action.lua"
  printf '%s\n' 'o.bind("SUPER + B", "Browser", { launch = "chromium" })' >"$file"
  assert_eq "$(bindings_action_for_key "$file" 'SUPER + B')" \
    'Browser: { launch = "chromium" }'
}

test_previous_action_is_readable_and_write_is_idempotent() {
  local file="$WORK/idempotent.lua" first second
  printf '%s\n' 'o.bind("F9", "Start dictation (push-to-talk)", "voxtype record start")' >"$file"
  bindings_write_managed "$file" F9 \
    'Start dictation (push-to-talk): voxtype record start' "$ROOT/bin/handy-trigger"
  assert_contains "$file" '-- Previous action: Start dictation (push-to-talk): voxtype record start'
  assert_contains "$file" "Dictation push-to-talk is F9 via Handy's native evdev hotkey (handy_keys)."
  assert_contains "$file" 'hl.unbind("F9")'
  first="$(<"$file")"
  bindings_write_managed "$file" F9 \
    "$(bindings_action_for_key "$file" F9)" "$ROOT/bin/handy-trigger"
  second="$(<"$file")"
  assert_eq "$second" "$first"
  assert_eq "$(grep -Fc -- 'hl.unbind("F9")' "$file")" 1
  assert_eq "$(grep -Fc -- 'BEGIN blizl.handy managed bindings' "$file")" 1
}

test_managed_block_unbinds_all_voxtype_keys() {
  local file="$WORK/all-unbinds.lua"
  printf '%s\n' 'o.bind("F9", "Start dictation", "voxtype record start")' >"$file"
  bindings_write_managed "$file" 'ALT + SPACE' '' "$ROOT/bin/handy-trigger" $'F9\nSUPER + CTRL + X'
  assert_eq "$(grep -Fc -- 'hl.unbind("F9")' "$file")" 1
  assert_eq "$(grep -Fc -- 'hl.unbind("SUPER + CTRL + X")' "$file")" 1
  assert_eq "$(grep -Fc -- 'hl.unbind("ALT + SPACE")' "$file")" 1
}

test_managed_block_rejects_malformed_detected_key() {
  local file="$WORK/malformed-key.lua"
  printf '%s\n' 'o.bind("F9", "Start", "voxtype record start")' >"$file"
  if bindings_write_managed "$file" F9 '' "$ROOT/bin/handy-trigger" $'F9\nBAD"KEY'; then
    fail 'malformed detected key was accepted'
  fi
  ! grep -Fq -- 'BEGIN blizl.handy managed bindings' "$file" ||
    fail 'malformed key changed the bindings file'
}

test_managed_block_emits_native_unbindings_and_comments() {
  local file="$WORK/clean-bindings.lua"
  printf '%s\n' 'o.bind("F9", "Open terminal", "kitty")' >"$file"
  bindings_write_managed "$file" 'ALT + SPACE' '' "$ROOT/bin/handy-trigger"
  assert_contains "$file" 'hl.unbind("ALT + SPACE")'
  assert_contains "$file" "Handy's native evdev hotkey (handy_keys)"
  ! grep -Fq -- 'o.bind(' <(grep -A 10 -- "$HANDY_BINDINGS_BEGIN" "$file") || fail 'unexpected o.bind in managed block'
  ! grep -Fq -- 'release = true' "$file" || fail 'unexpected release = true binding in managed block'
  bindings_validate "$file" || fail 'bindings validation failed on generated file'
}

test_managed_block_multi_modifier_and_clean_removal() {
  local file="$WORK/multi-mod.lua" clean="$WORK/multi-mod-clean.lua" original
  printf '%s\n' 'o.bind("SUPER + B", "Browser", "browser")' >"$file"
  original="$(<"$file")"
  bindings_write_managed "$file" 'SUPER + CTRL + X' '' "$ROOT/bin/handy-trigger"
  assert_contains "$file" 'hl.unbind("SUPER + CTRL + X")'
  assert_contains "$file" "Handy's native evdev hotkey (handy_keys)"
  bindings_validate "$file" || fail 'bindings validation failed on multi-modifier file'

  bindings_remove_managed_block "$file" "$clean"
  assert_eq "$(<"$clean")" "$original"
  ! grep -Fq -- 'handy_keys' "$clean" || fail 'handy_keys comment leaked outside managed block'
  ! grep -Fq -- 'SUPER + CTRL + X' "$clean" || fail 'managed binding leaked outside managed block'
  bindings_validate "$clean" || fail 'bindings validation failed on cleaned file'
}

test_handy_shortcut_normalization_and_native_configuration() {
  assert_eq "$(handy_shortcut_normalize "ALT + SPACE")" "alt+space"
  assert_eq "$(handy_shortcut_normalize "SUPER + CTRL + X")" "super+ctrl+x"
  assert_eq "$(handy_shortcut_normalize "ALT + ENTER")" "alt+enter"
  assert_eq "$(handy_shortcut_normalize "  Ctrl + Shift + Space  ")" "ctrl+shift+space"
  assert_eq "$(handy_shortcut_normalize "F9")" "f9"

  local settings="$WORK/settings.json"
  cat >"$settings" <<'JSON'
{
  "settings": {
    "push_to_talk": false,
    "keyboard_implementation": "tauri",
    "bindings": {
      "transcribe": {
        "current_binding": "ctrl+space"
      }
    },
    "other": "value"
  },
  "root_field": 123
}
JSON

  handy_settings_configure_native "$settings" "ALT + SPACE"
  assert_eq "$(handy_settings_binding "$settings")" "alt+space"
  assert_eq "$(handy_settings_keyboard_implementation "$settings")" "handy_keys"
  assert_eq "$(handy_settings_push_to_talk "$settings")" "true"
  assert_eq "$(jq -r '.settings.other' "$settings")" "value"
  assert_eq "$(jq -r '.root_field' "$settings")" "123"
}

test_detects_push_to_talk_over_toggle_across_user_and_stock_files
test_user_push_to_talk_wins_when_both_sources_have_one
test_detects_all_voxtype_entry_points
test_missing_voxtype_bindings_are_not_an_error
test_managed_block_unbinds_even_without_previous_action
test_detects_non_string_action_conflicts
test_previous_action_is_readable_and_write_is_idempotent
test_managed_block_unbinds_all_voxtype_keys
test_managed_block_rejects_malformed_detected_key
test_managed_block_emits_native_unbindings_and_comments
test_managed_block_multi_modifier_and_clean_removal
test_handy_shortcut_normalization_and_native_configuration
printf 'binding conflict tests: ok\n'
