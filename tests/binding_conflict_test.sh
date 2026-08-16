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
  assert_contains "$file" $'-- Previous action: Start dictation (push-to-talk): voxtype record start\nhl.unbind("F9")'
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

test_modifier_release_keys_extraction() {
  assert_eq "$(bindings_modifier_release_keys 'ALT + SPACE' | paste -sd, -)" 'Alt_L,Alt_R'
  assert_eq "$(bindings_modifier_release_keys 'SUPER + SPACE' | paste -sd, -)" 'Super_L,Super_R'
  assert_eq "$(bindings_modifier_release_keys 'CTRL + SPACE' | paste -sd, -)" 'Control_L,Control_R'
  assert_eq "$(bindings_modifier_release_keys 'SHIFT + SPACE' | paste -sd, -)" 'Shift_L,Shift_R'
  assert_eq "$(bindings_modifier_release_keys 'SUPER + CTRL + X' | paste -sd, -)" 'Super_L,Super_R,Control_L,Control_R'
  assert_eq "$(bindings_modifier_release_keys 'CTRL + ALT + SHIFT + SUPER + SPACE' | paste -sd, -)" 'Control_L,Control_R,Alt_L,Alt_R,Shift_L,Shift_R,Super_L,Super_R'
  assert_eq "$(bindings_modifier_release_keys 'F9')" ''
  assert_eq "$(bindings_modifier_release_keys 'SPACE')" ''
  assert_eq "$(bindings_modifier_release_keys 'alt + space' | paste -sd, -)" 'Alt_L,Alt_R'
  assert_eq "$(bindings_modifier_release_keys 'Control + space' | paste -sd, -)" 'Control_L,Control_R'
  assert_eq "$(bindings_modifier_release_keys 'LEFTCTRL + space' | paste -sd, -)" 'Control_L,Control_R'
  assert_eq "$(bindings_modifier_release_keys 'RIGHTALT + space' | paste -sd, -)" 'Alt_L,Alt_R'
  assert_eq "$(bindings_modifier_release_keys 'LEFTSHIFT + space' | paste -sd, -)" 'Shift_L,Shift_R'
  assert_eq "$(bindings_modifier_release_keys 'META + space' | paste -sd, -)" 'Super_L,Super_R'
}

test_managed_block_emits_modifier_release_bindings() {
  local file="$WORK/modifier-releases.lua"
  printf '%s\n' 'o.bind("F9", "Open terminal", "kitty")' >"$file"
  bindings_write_managed "$file" 'ALT + SPACE' '' "$ROOT/bin/handy-trigger"
  assert_contains "$file" 'o.bind('
  assert_contains "$file" '"ALT + SPACE"'
  assert_contains "$file" '"Alt_L"'
  assert_contains "$file" '"Alt_R"'
  assert_contains "$file" '{ release = true }'
  assert_eq "$(grep -Fc -- '"Alt_L"' "$file")" 1
  assert_eq "$(grep -Fc -- '"Alt_R"' "$file")" 1
  assert_eq "$(grep -Fc -- 'release = true' "$file")" 3
  bindings_validate "$file" || fail 'bindings validation failed on generated file'
}

test_managed_block_single_key_has_no_modifier_releases() {
  local file="$WORK/single-key.lua"
  printf '%s\n' 'o.bind("SUPER + B", "Browser", "browser")' >"$file"
  bindings_write_managed "$file" 'F9' '' "$ROOT/bin/handy-trigger"
  assert_contains "$file" '"F9"'
  assert_eq "$(grep -Fc -- '"F9"' "$file")" 3
  assert_eq "$(grep -Fc -- 'release = true' "$file")" 1
  ! grep -Fq -- '"Alt_L"' "$file" || fail 'unexpected Alt_L in single-key managed block'
  ! grep -Fq -- '"Super_L"' "$file" || fail 'unexpected Super_L in single-key managed block'
  bindings_validate "$file" || fail 'bindings validation failed on single-key file'
}

test_managed_block_multi_modifier_and_clean_removal() {
  local file="$WORK/multi-mod.lua" clean="$WORK/multi-mod-clean.lua" original
  printf '%s\n' 'o.bind("SUPER + B", "Browser", "browser")' >"$file"
  original="$(<"$file")"
  bindings_write_managed "$file" 'SUPER + CTRL + X' '' "$ROOT/bin/handy-trigger"
  assert_contains "$file" '"Super_L"'
  assert_contains "$file" '"Super_R"'
  assert_contains "$file" '"Control_L"'
  assert_contains "$file" '"Control_R"'
  assert_eq "$(grep -Fc -- 'release = true' "$file")" 5
  bindings_validate "$file" || fail 'bindings validation failed on multi-modifier file'

  bindings_remove_managed_block "$file" "$clean"
  assert_eq "$(<"$clean")" "$original"
  ! grep -Fq -- 'Super_L' "$clean" || fail 'Super_L leaked outside managed block'
  ! grep -Fq -- 'handy-trigger' "$clean" || fail 'handy-trigger leaked outside managed block'
  bindings_validate "$clean" || fail 'bindings validation failed on cleaned file'
}

test_managed_block_modifier_release_idempotency() {
  local file="$WORK/mod-idempotency.lua" first second
  printf '%s\n' 'o.bind("F9", "Stock", "action")' >"$file"
  bindings_write_managed "$file" 'ALT + SPACE' '' "$ROOT/bin/handy-trigger"
  first="$(<"$file")"
  bindings_write_managed "$file" 'ALT + SPACE' '' "$ROOT/bin/handy-trigger"
  second="$(<"$file")"
  assert_eq "$second" "$first"
  assert_eq "$(grep -Fc -- '"Alt_L"' "$file")" 1
  assert_eq "$(grep -Fc -- '"Alt_R"' "$file")" 1
  assert_eq "$(grep -Fc -- 'BEGIN blizl.handy managed bindings' "$file")" 1
  bindings_validate "$file" || fail 'bindings validation failed after idempotent write'
}

test_normalize_shortcut() {
  assert_eq "$(bindings_normalize_shortcut 'ALT + ENTER')" 'ALT + RETURN'
  assert_eq "$(bindings_normalize_shortcut 'alt + enter')" 'ALT + RETURN'
  assert_eq "$(bindings_normalize_shortcut 'ctrl + esc')" 'CTRL + ESCAPE'
  assert_eq "$(bindings_normalize_shortcut 'SUPER + SPACE')" 'SUPER + SPACE'
  assert_eq "$(bindings_normalize_shortcut 'F9')" 'F9'
}

test_managed_block_normalizes_enter_to_return() {
  local file="$WORK/enter-to-return.lua"
  printf '%s\n' 'o.bind("SUPER + B", "Browser", "browser")' >"$file"
  bindings_write_managed "$file" 'ALT + ENTER' '' "$ROOT/bin/handy-trigger"
  assert_contains "$file" 'hl.unbind("ALT + ENTER")'
  assert_contains "$file" 'hl.unbind("ALT + RETURN")'
  assert_contains "$file" '"ALT + RETURN"'
  assert_contains "$file" '"Alt_L"'
  assert_contains "$file" '"Alt_R"'
  ! grep -Eq 'o\.bind\(\s*"ALT \+ ENTER"' "$file" || fail 'unnormalized ALT + ENTER was bound'
  bindings_validate "$file" || fail 'bindings validation failed on normalized enter file'
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
test_modifier_release_keys_extraction
test_managed_block_emits_modifier_release_bindings
test_managed_block_single_key_has_no_modifier_releases
test_managed_block_multi_modifier_and_clean_removal
test_managed_block_modifier_release_idempotency
test_normalize_shortcut
test_managed_block_normalizes_enter_to_return
printf 'binding conflict tests: ok\n'
