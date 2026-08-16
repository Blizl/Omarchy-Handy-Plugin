#!/usr/bin/env bash
set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

failures=0
tests_run=0

fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}
pass() { printf 'ok - %s\n' "$1"; }

# shellcheck disable=SC1091
source "$ROOT/lib/shell-settings.sh"

new_file() {
  SHELL_FILE="$WORK/shell-$tests_run.json"
}

test_replaces_handy_and_dictation_across_layout() {
  new_file
  cat >"$SHELL_FILE" <<'JSON'
{
  "version": 7,
  "unrelated": {"keep": true},
  "bar": {"layout": {
    "left": [{"id":"blizl.handy"}, {"id":"left.keep"}],
    "center": [{"id":"omarchy.clock"}, {"id":"blizl.handy"}, {"id":"center.keep"}],
    "right": [
      {"id":"omarchy.indicators", "items":["Dictation", "Dnd", {"id":"NightLight", "keep":true}]},
      {"id":"omarchy.indicators"},
      {"id":"blizl.handy", "custom": "remove"}
    ]
  }}
}
JSON

  shell_settings_install_handy_widget "$SHELL_FILE"
  jq -e '.version == 7 and .unrelated.keep == true' "$SHELL_FILE" >/dev/null || return 1
  [[ "$(jq '[.bar.layout[][] | select(.id == "blizl.handy")] | length' "$SHELL_FILE")" == 1 ]] || return 1
  [[ "$(jq -c '[.bar.layout.center[].id]' "$SHELL_FILE")" == '["blizl.handy","omarchy.clock","center.keep"]' ]] || return 1
  [[ "$(jq -c '[.bar.layout.right[] | select(.id == "omarchy.indicators") | .items]' "$SHELL_FILE")" == '[["Dnd",{"id":"NightLight","keep":true}],["ScreenRecording","Reminder","NightLight","Dnd","StayAwake"]]' ]] || return 1
  ! jq -e '[.bar.layout[][] | select(.id == "omarchy.indicators") | (.items // [])[] | if type == "object" then .id else . end] | any(. == "Dictation")' "$SHELL_FILE" >/dev/null
}

test_nonempty_items_precede_legacy_indicators() {
  new_file
  cat >"$SHELL_FILE" <<'JSON'
{"bar":{"layout":{"right":[
  {"id":"omarchy.indicators","items":["Dnd"],"indicators":["Dictation"]}
]}}}
JSON

  shell_settings_install_handy_widget "$SHELL_FILE"
  jq -e '.bar.layout.right[0].items == ["Dnd"] and (.bar.layout.right[0] | has("indicators") | not)' "$SHELL_FILE" >/dev/null
}

test_dictation_only_indicator_entries_are_removed() {
  new_file
  cat >"$SHELL_FILE" <<'JSON'
{"bar":{"layout":{
  "left":[{"id":"omarchy.indicators","items":["Dictation"]}],
  "right":[{"id":"omarchy.indicators","indicators":[{"id":"Dictation"}]}]
}}}
JSON

  shell_settings_install_handy_widget "$SHELL_FILE"
  [[ "$(jq '[.bar.layout[][] | select(.id == "omarchy.indicators")] | length' "$SHELL_FILE")" == 0 ]] || return 1
  [[ "$(jq '[.bar.layout.center[] | select(.id == "blizl.handy")] | length' "$SHELL_FILE")" == 1 ]]
}

test_string_indicator_entries_are_materialized() {
  new_file
  cat >"$SHELL_FILE" <<'JSON'
{"bar":{"layout":{"left":["omarchy.indicators","left.string.keep"]}}}
JSON

  shell_settings_install_handy_widget "$SHELL_FILE"
  jq -e '.bar.layout.left[0].id == "omarchy.indicators" and .bar.layout.left[0].items == ["ScreenRecording","Reminder","NightLight","Dnd","StayAwake"]' "$SHELL_FILE" >/dev/null || return 1
  [[ "$(jq -r '.bar.layout.left[1]' "$SHELL_FILE")" == 'left.string.keep' ]]
}

test_materializes_defaults_for_absent_or_empty_lists() {
  new_file
  cat >"$SHELL_FILE" <<'JSON'
{"bar":{"layout":{"left":[
  {"id":"omarchy.indicators"},
  {"id":"omarchy.indicators","items":[]},
  {"id":"omarchy.indicators","indicators":[]}
]}}}
JSON

  shell_settings_install_handy_widget "$SHELL_FILE"
  [[ "$(jq '[.bar.layout.left[] | select(.id == "omarchy.indicators") | .items] | all(. == ["ScreenRecording","Reminder","NightLight","Dnd","StayAwake"])' "$SHELL_FILE")" == true ]] || return 1
}

test_appends_when_clock_is_absent_and_preserves_mode() {
  new_file
  printf '%s\n' '{"bar":{"layout":{"center":[{"id":"center.keep"}]}}}' >"$SHELL_FILE"
  chmod 640 "$SHELL_FILE"

  shell_settings_install_handy_widget "$SHELL_FILE"
  [[ "$(stat -c '%a' "$SHELL_FILE")" == 640 ]] || return 1
  [[ "$(jq -c '[.bar.layout.center[].id]' "$SHELL_FILE")" == '["center.keep","blizl.handy"]' ]]
}

test_malformed_json_is_rejected_without_mutation() {
  new_file
  printf '%s\n' '{"bar":' >"$SHELL_FILE"
  local before status
  before="$(<"$SHELL_FILE")"
  set +e
  shell_settings_install_handy_widget "$SHELL_FILE"
  status=$?
  set -e
  [[ "$status" != 0 ]] || return 1
  [[ "$(<"$SHELL_FILE")" == "$before" ]]
}

for test_name in \
  test_replaces_handy_and_dictation_across_layout \
  test_nonempty_items_precede_legacy_indicators \
  test_dictation_only_indicator_entries_are_removed \
  test_string_indicator_entries_are_materialized \
  test_materializes_defaults_for_absent_or_empty_lists \
  test_appends_when_clock_is_absent_and_preserves_mode \
  test_malformed_json_is_rejected_without_mutation; do
  tests_run=$((tests_run + 1))
  if "$test_name"; then pass "$test_name"; else fail "$test_name"; fi
done

printf '\n%d tests, %d failures\n' "$tests_run" "$failures"
((failures == 0))
