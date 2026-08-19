#!/usr/bin/env bash
# Single-quoted strings are grep patterns, not expansions.
# shellcheck disable=SC2016
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
# shellcheck disable=SC1091
source "$ROOT/lib/voxtype-settings.sh"

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

test_detects_non_string_action_conflicts() {
  local file="$WORK/table-action.lua"
  printf '%s\n' 'o.bind("SUPER + B", "Browser", { launch = "chromium" })' >"$file"
  assert_eq "$(bindings_action_for_key "$file" 'SUPER + B')" \
    'Browser: { launch = "chromium" }'
}

test_previous_action_is_readable() {
  local file="$WORK/previous.lua"
  printf '%s\n' 'o.bind("F9", "Start dictation (push-to-talk)", "voxtype record start")' >"$file"
  assert_eq "$(bindings_action_for_key "$file" F9)" \
    'Start dictation (push-to-talk): voxtype record start'
}

test_locates_the_conflicting_binding_line() {
  local file="$WORK/locate.lua" located
  printf '%s\n' \
    '-- a comment' \
    'o.bind("SUPER + B", "Browser", "browser")' \
    'o.bind("ALT + SPACE", "Toggle dictation", "voxtype record toggle")' >"$file"
  located="$(bindings_locate_key "$file" 'ALT + SPACE')"
  assert_eq "${located%%$'\t'*}" 3
  assert_eq "${located#*$'\t'}" 'o.bind("ALT + SPACE", "Toggle dictation", "voxtype record toggle")'
  assert_eq "$(bindings_locate_key "$file" 'CTRL + Q')" ''
}

test_locate_ignores_commented_and_managed_bindings() {
  local file="$WORK/locate-managed.lua"
  printf '%s\n' \
    '-- o.bind("ALT + SPACE", "Disabled", "old-command")' \
    "$HANDY_BINDINGS_BEGIN" \
    'o.bind("ALT + SPACE", "Leftover", "stale")' \
    "$HANDY_BINDINGS_END" >"$file"
  assert_eq "$(bindings_locate_key "$file" 'ALT + SPACE')" ''
}

# Setup no longer writes this block, but an install from 1.1.0 or earlier may
# still carry one, so removal has to keep working against a literal fixture.
test_all_keys_lists_every_binding_for_normalized_comparison() {
  local file="$WORK/all-keys.lua" keys
  printf '%s\n' \
    'o.bind("SUPER + B", "Browser", "browser")' \
    '-- o.bind("CTRL + Q", "Commented", "nope")' \
    'o.bind("ALT+ENTER", "Tight spacing", "something")' \
    "$HANDY_BINDINGS_BEGIN" \
    'o.bind("LEFTOVER", "Stale", "stale")' \
    "$HANDY_BINDINGS_END" >"$file"
  keys="$(bindings_all_keys "$file")"
  assert_eq "$keys" "$(printf '%s\n%s' 'SUPER + B' 'ALT+ENTER')"

  # The conflict gate relies on these comparing equal despite the spelling.
  voxtype_shortcuts_equal 'ALT+ENTER' 'ALT + ENTER' ||
    fail 'differently spaced spellings of one chord did not compare equal'
}

test_legacy_managed_block_is_removed_cleanly() {
  local file="$WORK/legacy.lua" clean="$WORK/legacy-clean.lua" original
  printf '%s\n' 'o.bind("SUPER + B", "Browser", "browser")' >"$file"
  original="$(<"$file")"
  {
    printf '\n%s\n' "$HANDY_BINDINGS_BEGIN"
    printf '%s\n' '-- Previous action: Browser: browser'
    printf '%s\n' "-- Dictation toggle is SUPER + CTRL + X via Handy's native evdev hotkey (handy_keys)."
    printf '%s\n' 'hl.unbind("SUPER + CTRL + X")'
    printf '%s\n' "$HANDY_BINDINGS_END"
  } >>"$file"
  bindings_validate "$file" || fail 'bindings validation failed on the legacy fixture'

  bindings_remove_managed_block "$file" "$clean"
  assert_eq "$(<"$clean")" "$original"
  ! grep -Fq -- 'handy_keys' "$clean" || fail 'handy_keys comment leaked outside managed block'
  ! grep -Fq -- 'SUPER + CTRL + X' "$clean" || fail 'managed binding leaked outside managed block'
  bindings_validate "$clean" || fail 'bindings validation failed on cleaned file'
}

test_bindings_library_exposes_no_writer() {
  grep -q 'bindings_write_managed' "$ROOT/lib/bindings.sh" &&
    fail 'lib/bindings.sh still defines a bindings.lua writer'
  grep -rn 'mv -- .*bindings_file\|>"\$bindings_file"' "$ROOT/lib/bindings.sh" &&
    fail 'lib/bindings.sh still writes to a bindings file'
  return 0
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
    "push_to_talk": true,
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
  assert_eq "$(handy_settings_push_to_talk "$settings")" "false"
  assert_eq "$(jq -r '.settings.other' "$settings")" "value"
  assert_eq "$(jq -r '.root_field' "$settings")" "123"
}

test_detects_push_to_talk_over_toggle_across_user_and_stock_files
test_user_push_to_talk_wins_when_both_sources_have_one
test_detects_all_voxtype_entry_points
test_missing_voxtype_bindings_are_not_an_error
test_detects_non_string_action_conflicts
test_previous_action_is_readable
test_locates_the_conflicting_binding_line
test_locate_ignores_commented_and_managed_bindings
test_all_keys_lists_every_binding_for_normalized_comparison
test_legacy_managed_block_is_removed_cleanly
test_bindings_library_exposes_no_writer
test_handy_shortcut_normalization_and_native_configuration
printf 'binding conflict tests: ok\n'
