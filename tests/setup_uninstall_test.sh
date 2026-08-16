#!/usr/bin/env bash
# Single-quoted strings generate test executables.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORK="$(mktemp -d)"
FIXTURE_NUMBER=0
trap 'pkill -f "^handy 300$" 2>/dev/null || true; rm -rf -- "$WORK"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }
assert_file() { [[ -e "$1" ]] || fail "expected file: $1"; }

make_fixture() {
  FIXTURE_NUMBER=$((FIXTURE_NUMBER + 1))
  local home="$WORK/home-$FIXTURE_NUMBER" fakebin="$WORK/bin"
  rm -rf -- "$fakebin"
  mkdir -p "$home/.config/hypr" "$home/.local/share/com.pais.handy" "$home/.config/autostart" "$fakebin"
  printf 'o.bind("F9", "VoxType push-to-talk", "voxtype")\n' >"$home/.config/hypr/bindings.lua"
  printf '%s\n' '{"settings":{"bindings":{"transcribe":{"current_binding":"alt+space"}},"unrelated":{"keep":true}}}' >"$home/.local/share/com.pais.handy/settings_store.json"
  printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Existing Handy' 'Exec=handy --start-hidden' >"$home/.config/autostart/Handy.desktop"
  printf '%s\n' '#!/usr/bin/env bash' 'if [[ ${1:-} == --start-hidden ]]; then count=0; [[ -f "$HOME/.handy-start-count" ]] && count=$(<"$HOME/.handy-start-count"); printf "%s\n" "$((count + 1))" >"$HOME/.handy-start-count"; : >"$HOME/.handy-fake-running"; exit 0; fi' 'exit 0' >"$fakebin/handy"
  printf '%s\n' '#!/usr/bin/env bash' 'if [[ ${1:-} == -x && ${2:-} == handy ]]; then [[ -e "$HOME/.handy-fake-running" ]]; exit; fi' 'exec /usr/bin/pgrep "$@"' >"$fakebin/pgrep"
  printf '%s\n' '#!/usr/bin/env bash' 'if [[ ${1:-} == -x && ${2:-} == handy ]]; then rm -f -- "$HOME/.handy-fake-running"; exit 0; fi' 'exec /usr/bin/pkill "$@"' >"$fakebin/pkill"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$fakebin/omarchy"
  chmod +x "$fakebin/handy" "$fakebin/pgrep" "$fakebin/pkill" "$fakebin/omarchy"
  export HOME="$home" PATH="$fakebin:$PATH"
  export BLIZL_HANDY_STATE_DIR="$home/.local/state/blizl.handy"
  export HYPR_BINDINGS_FILE="$home/.config/hypr/bindings.lua"
  export HANDY_SETTINGS_FILE="$home/.local/share/com.pais.handy/settings_store.json"
  export HANDY_AUTOSTART_FILE="$home/.config/autostart/Handy.desktop"
  export VOXTYPE_CONFIG_FILE="$home/.config/voxtype/config.toml"
  export VOXTYPE_BINDINGS_FILE="$home/.stock-voxtype.lua"
  : >"$VOXTYPE_BINDINGS_FILE"
  export BLIZL_HANDY_NONINTERACTIVE=true BLIZL_HANDY_SHORTCUT='ALT + SPACE'
  export BLIZL_HANDY_DICTATION_TEST=passed BLIZL_HANDY_SKIP_RELOAD=true BLIZL_HANDY_CONFIRM=no
  export BLIZL_HANDY_VOXTYPE_PRESENT=false
  unset BLIZL_HANDY_PLUGIN_REMOVE_BIN BLIZL_HANDY_TEST_WINDOW_BIN
  unset HYPRLAND_INSTANCE_SIGNATURE
}

test_setup_uninstall_round_trip() {
  make_fixture
  local before_bindings before_settings before_autostart
  before_bindings="$(<"$HYPR_BINDINGS_FILE")"
  before_settings="$(<"$HANDY_SETTINGS_FILE")"
  before_autostart="$(<"$HANDY_AUTOSTART_FILE")"
  "$ROOT/bin/setup"
  "$ROOT/bin/setup" >/dev/null
  assert_file "$BLIZL_HANDY_STATE_DIR/install.json"
  [[ "$(grep -Fc -- 'BEGIN blizl.handy managed bindings' "$HYPR_BINDINGS_FILE")" == 1 ]] || fail 'managed block missing'
  [[ "$(grep -Fc -- 'Exec=handy --start-hidden' "$HANDY_AUTOSTART_FILE")" == 1 ]] || fail 'autostart changed incorrectly'
  "$ROOT/bin/uninstall"
  assert_eq "$(<"$HYPR_BINDINGS_FILE")" "$before_bindings"
  assert_eq "$(<"$HANDY_SETTINGS_FILE")" "$before_settings"
  assert_eq "$(<"$HANDY_AUTOSTART_FILE")" "$before_autostart"
  [[ ! -e "$BLIZL_HANDY_STATE_DIR/install.json" ]] || fail 'install marker remained'
  [[ "$(<"$HOME/.handy-start-count")" == 2 ]] || fail 'uninstall did not restart Handy after restoring its shortcut'
}

test_setup_rejects_incomplete_managed_block() {
  make_fixture
  printf '%s\n' '-- BEGIN blizl.handy managed bindings' >>"$HYPR_BINDINGS_FILE"
  if "$ROOT/bin/setup" >/dev/null 2>&1; then fail 'incomplete managed block was accepted'; fi
}

test_setup_rejects_malformed_lua() {
  make_fixture
  printf '%s\n' 'o.bind("broken", ' >>"$HYPR_BINDINGS_FILE"
  if "$ROOT/bin/setup" >/dev/null 2>&1; then fail 'malformed Lua was accepted'; fi
}

test_setup_rejects_malformed_settings_without_commit() {
  make_fixture
  printf '{broken\n' >"$HANDY_SETTINGS_FILE"
  if "$ROOT/bin/setup" >/dev/null 2>&1; then fail 'malformed Handy settings were accepted'; fi
  [[ ! -e "$BLIZL_HANDY_STATE_DIR/install.json" ]] || fail 'malformed settings setup committed state'
}

test_malformed_settings_restore_preexisting_handy_process() {
  make_fixture
  : >"$HOME/.handy-fake-running"
  printf '{broken\n' >"$HANDY_SETTINGS_FILE"

  if "$ROOT/bin/setup" >/dev/null 2>&1; then fail 'malformed Handy settings were accepted'; fi

  assert_file "$HOME/.handy-fake-running"
  assert_eq "$(<"$HOME/.handy-start-count")" '1'
}

test_setup_rolls_back_after_dictation_gate() {
  make_fixture
  local before_bindings before_settings before_autostart
  before_bindings="$(<"$HYPR_BINDINGS_FILE")"
  before_settings="$(<"$HANDY_SETTINGS_FILE")"
  before_autostart="$(<"$HANDY_AUTOSTART_FILE")"
  unset BLIZL_HANDY_DICTATION_TEST
  if "$ROOT/bin/setup" >/dev/null 2>&1; then fail 'dictation gate unexpectedly passed'; fi
  assert_eq "$(<"$HYPR_BINDINGS_FILE")" "$before_bindings"
  assert_eq "$(<"$HANDY_SETTINGS_FILE")" "$before_settings"
  assert_eq "$(<"$HANDY_AUTOSTART_FILE")" "$before_autostart"
  [[ ! -e "$BLIZL_HANDY_STATE_DIR/install.json" ]] || fail 'failed setup committed state'
  [[ ! -e "$HOME/.handy-fake-running" ]] || fail 'setup-owned Handy process was left running'
}

test_setup_uses_a_dedicated_dictation_window() {
  make_fixture
  local launcher="$WORK/bin/dictation-window"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$2" >"$HOME/.dictation-window-shortcut"' \
    'printf "%s\n" "$$" >"$BLIZL_HANDY_TEST_PID_FILE"' \
    'printf "passed\n" >"$1"' >"$launcher"
  chmod +x "$launcher"
  unset BLIZL_HANDY_DICTATION_TEST
  export BLIZL_HANDY_TEST_WINDOW_BIN="$launcher"

  "$ROOT/bin/setup" >/dev/null

  assert_eq "$(<"$HOME/.dictation-window-shortcut")" 'ALT + SPACE'
  assert_file "$BLIZL_HANDY_STATE_DIR/install.json"
  ! compgen -G "$BLIZL_HANDY_STATE_DIR/dictation-test.*" >/dev/null ||
    fail 'dictation test temporary directory remained'
  "$ROOT/bin/uninstall" >/dev/null
}

test_failed_dictation_window_restores_and_removes_plugin() {
  make_fixture
  local launcher="$WORK/bin/dictation-window" remover="$WORK/bin/remove-plugin"
  local before_bindings before_settings before_autostart
  before_bindings="$(<"$HYPR_BINDINGS_FILE")"
  before_settings="$(<"$HANDY_SETTINGS_FILE")"
  before_autostart="$(<"$HANDY_AUTOSTART_FILE")"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "failed\n" >"$1"' >"$launcher"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >"$HOME/.plugin-remove-args"' >"$remover"
  chmod +x "$launcher" "$remover"
  unset BLIZL_HANDY_DICTATION_TEST
  export BLIZL_HANDY_TEST_WINDOW_BIN="$launcher"
  export BLIZL_HANDY_PLUGIN_REMOVE_BIN="$remover"

  if "$ROOT/bin/setup" >/dev/null 2>&1; then fail 'failed dictation window unexpectedly passed'; fi

  assert_eq "$(<"$HYPR_BINDINGS_FILE")" "$before_bindings"
  assert_eq "$(<"$HANDY_SETTINGS_FILE")" "$before_settings"
  assert_eq "$(<"$HANDY_AUTOSTART_FILE")" "$before_autostart"
  assert_eq "$(<"$HOME/.plugin-remove-args")" 'blizl.handy --yes'
  [[ ! -e "$BLIZL_HANDY_STATE_DIR/install.json" ]] || fail 'failed setup committed state'
  [[ ! -e "$HOME/.handy-fake-running" ]] || fail 'setup-owned Handy process was left running'
}

test_dictation_result_must_contain_only_passed() {
  make_fixture
  local launcher="$WORK/bin/dictation-window" remover="$WORK/bin/remove-plugin"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "passed\nunexpected\n" >"$1"' >"$launcher"
  printf '%s\n' '#!/usr/bin/env bash' ': >"$HOME/.plugin-was-removed"' >"$remover"
  chmod +x "$launcher" "$remover"
  unset BLIZL_HANDY_DICTATION_TEST
  export BLIZL_HANDY_TEST_WINDOW_BIN="$launcher"
  export BLIZL_HANDY_PLUGIN_REMOVE_BIN="$remover"

  if "$ROOT/bin/setup" >/dev/null 2>&1; then fail 'multi-line dictation result was accepted'; fi

  assert_file "$HOME/.plugin-was-removed"
}

test_failed_dictation_window_restores_preexisting_handy_process() {
  make_fixture
  local launcher="$WORK/bin/dictation-window" remover="$WORK/bin/remove-plugin"
  : >"$HOME/.handy-fake-running"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "failed\n" >"$1"' >"$launcher"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$remover"
  chmod +x "$launcher" "$remover"
  unset BLIZL_HANDY_DICTATION_TEST
  export BLIZL_HANDY_TEST_WINDOW_BIN="$launcher"
  export BLIZL_HANDY_PLUGIN_REMOVE_BIN="$remover"

  if "$ROOT/bin/setup" >/dev/null 2>&1; then fail 'failed dictation window unexpectedly passed'; fi

  assert_file "$HOME/.handy-fake-running"
  assert_eq "$(<"$HOME/.handy-start-count")" '2'
}

test_setup_deduplicates_autostart_exec_lines() {
  make_fixture
  printf '%s\n' 'Exec=handy --start-hidden' >>"$HANDY_AUTOSTART_FILE"
  export BLIZL_HANDY_DICTATION_TEST=passed
  "$ROOT/bin/setup" >/dev/null
  [[ "$(grep -c '^Exec=' "$HANDY_AUTOSTART_FILE")" == 1 ]] || fail 'autostart has duplicate Exec lines'
  "$ROOT/bin/uninstall" >/dev/null
}

test_fresh_install_uses_aur_aware_installer() {
  make_fixture
  cp -- "$WORK/bin/handy" "$WORK/handy-template"
  rm -f -- "$WORK/bin/handy"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >"$HOME/.aur-install-args"' 'cp -- "$HANDY_INSTALL_TEMPLATE" "$(dirname "$0")/handy"' 'chmod +x "$(dirname "$0")/handy"' >"$WORK/bin/yay"
  chmod +x "$WORK/bin/yay"
  export HANDY_INSTALL_TEMPLATE="$WORK/handy-template"
  export BLIZL_HANDY_DICTATION_TEST=passed BLIZL_HANDY_FORCE_INSTALL=true BLIZL_HANDY_INSTALL_BIN="$WORK/bin/yay"
  "$ROOT/bin/setup"
  [[ "$(<"$HOME/.aur-install-args")" == '-S --needed --noconfirm handy-bin' ]] || fail 'fresh Handy setup did not use AUR installer'
  "$ROOT/bin/uninstall" >/dev/null
  unset BLIZL_HANDY_FORCE_INSTALL BLIZL_HANDY_INSTALL_BIN HANDY_INSTALL_TEMPLATE
}

test_setup_rejects_conflict_without_mutation() {
  make_fixture
  printf 'o.bind("ALT + SPACE", "Keep this action", "other")\n' >>"$HYPR_BINDINGS_FILE"
  local before
  before="$(<"$HYPR_BINDINGS_FILE")"
  if "$ROOT/bin/setup" >/dev/null 2>&1; then fail 'conflicting binding was accepted'; fi
  assert_eq "$(<"$HYPR_BINDINGS_FILE")" "$before"
  [[ ! -e "$BLIZL_HANDY_STATE_DIR/install.json" ]] || fail 'failed setup committed state'
}

test_setup_unbinds_stock_voxtype_before_claiming_its_key() {
  make_fixture
  export BLIZL_HANDY_VOXTYPE_PRESENT=true
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$WORK/bin/voxtype"
  chmod +x "$WORK/bin/voxtype"
  printf '%s\n' 'o.bind("SUPER + B", "Browser", "browser")' >"$HYPR_BINDINGS_FILE"
  printf '%s\n' \
    'o.bind("SUPER + CTRL + X", "Toggle dictation", "voxtype record toggle")' \
    'o.bind("F9", "Start dictation (push-to-talk)", "voxtype record start")' \
    'o.bind("F9", "Stop dictation (push-to-talk)", "voxtype record stop", { release = true })' \
    >"$VOXTYPE_BINDINGS_FILE"
  export BLIZL_HANDY_SHORTCUT=F9

  "$ROOT/bin/setup" >/dev/null

  assert_eq "$(grep -Fc -- 'hl.unbind("F9")' "$HYPR_BINDINGS_FILE")" 1
  grep -Fq -- '-- Previous action: Start dictation (push-to-talk): voxtype record start' \
    "$HYPR_BINDINGS_FILE" || fail 'stock VoxType ownership was not recorded'
  "$ROOT/bin/uninstall" >/dev/null
}

test_setup_launches_the_test_through_omarchy() {
  make_fixture
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ ${1:-} == launch && ${2:-} == tui ]]; then' \
    '  printf "%s\n" "$*" >"$HOME/.omarchy-test-window-args"' \
    '  printf "dictated words\n" | "$4" "$5" "$6"' \
    'fi' \
    'exit 0' >"$WORK/bin/omarchy"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$WORK/bin/uwsm-app"
  chmod +x "$WORK/bin/omarchy" "$WORK/bin/uwsm-app"
  export BLIZL_HANDY_NONINTERACTIVE=false
  unset BLIZL_HANDY_DICTATION_TEST BLIZL_HANDY_TEST_WINDOW_BIN

  printf '\n' | "$ROOT/bin/setup" >/dev/null

  grep -Fq -- "launch tui --app-id=blizl.handy-test $ROOT/bin/handy-test-window" \
    "$HOME/.omarchy-test-window-args" || fail 'setup did not use the Omarchy test window launcher'
  "$ROOT/bin/uninstall" >/dev/null
}

test_failed_test_removes_an_installed_checkout() {
  make_fixture
  local launcher="$WORK/bin/dictation-window"
  mkdir -p -- "$HOME/.config/omarchy/plugins"
  ln -s -- "$ROOT" "$HOME/.config/omarchy/plugins/blizl.handy"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "failed\n" >"$1"' >"$launcher"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >>"$HOME/.omarchy-commands"' \
    'exit 0' >"$WORK/bin/omarchy"
  chmod +x "$launcher" "$WORK/bin/omarchy"
  unset BLIZL_HANDY_DICTATION_TEST BLIZL_HANDY_PLUGIN_REMOVE_BIN
  export BLIZL_HANDY_TEST_WINDOW_BIN="$launcher"

  if "$ROOT/bin/setup" >/dev/null 2>&1; then fail 'failed dictation window unexpectedly passed'; fi

  grep -Fq -- 'plugin remove blizl.handy --yes' "$HOME/.omarchy-commands" ||
    fail 'installed plugin checkout was not removed after the failed test'
}

test_failed_test_attempts_plugin_removal_after_incomplete_rollback() {
  make_fixture
  local launcher="$WORK/bin/dictation-window" remover="$WORK/bin/remove-plugin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "failed\n" >"$1"' \
    'rm -f -- "$BLIZL_HANDY_STATE_DIR"/backups/*/targets.tsv' >"$launcher"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >"$HOME/.plugin-remove-args"' >"$remover"
  chmod +x "$launcher" "$remover"
  unset BLIZL_HANDY_DICTATION_TEST
  export BLIZL_HANDY_TEST_WINDOW_BIN="$launcher" BLIZL_HANDY_PLUGIN_REMOVE_BIN="$remover"

  if "$ROOT/bin/setup" >/dev/null 2>&1; then fail 'failed dictation window unexpectedly passed'; fi

  assert_eq "$(<"$HOME/.plugin-remove-args")" 'blizl.handy --yes'
}

test_failed_test_reports_plugin_removal_failure_when_checkout_remains() {
  make_fixture
  local launcher="$WORK/bin/dictation-window" remover="$WORK/bin/remove-plugin" output
  mkdir -p -- "$HOME/.config/omarchy/plugins"
  ln -s -- "$ROOT" "$HOME/.config/omarchy/plugins/blizl.handy"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "failed\n" >"$1"' >"$launcher"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$remover"
  chmod +x "$launcher" "$remover"
  unset BLIZL_HANDY_DICTATION_TEST
  export BLIZL_HANDY_TEST_WINDOW_BIN="$launcher" BLIZL_HANDY_PLUGIN_REMOVE_BIN="$remover"

  set +e
  output="$("$ROOT/bin/setup" 2>&1 >/dev/null)"
  set -e
  [[ "$output" == *'Plugin removal did not complete'* ]] ||
    fail 'incomplete plugin removal was not reported'
}

test_setup_disables_and_uninstall_restores_native_voxtype_hotkey() {
  make_fixture
  export BLIZL_HANDY_VOXTYPE_PRESENT=true
  local systemctl_log="$HOME/.systemctl-log" before
  mkdir -p -- "$(dirname -- "$VOXTYPE_CONFIG_FILE")"
  printf '%s\n' \
    'state_file = "auto"' \
    '' \
    '[hotkey]' \
    'enabled = true' \
    'key = "SPACE"' \
    'modifiers = ["LEFTALT"]' \
    '' \
    '[audio]' \
    'device = "default"' >"$VOXTYPE_CONFIG_FILE"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$WORK/bin/voxtype"
  chmod +x "$WORK/bin/voxtype"
  before="$(<"$VOXTYPE_CONFIG_FILE")"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >>"$HOME/.systemctl-log"' \
    '[[ $* == "--user is-active voxtype.service" ]] && { printf "active\n"; exit 0; }' \
    'exit 0' >"$WORK/bin/systemctl"
  chmod +x "$WORK/bin/systemctl" "$WORK/bin/voxtype"

  "$ROOT/bin/setup" >/dev/null

  grep -Fq 'enabled = false' "$VOXTYPE_CONFIG_FILE" || fail 'native VoxType hotkey remained enabled'
  grep -Fq 'key = "SPACE"' "$VOXTYPE_CONFIG_FILE" || fail 'VoxType hotkey details were lost'
  "$ROOT/bin/uninstall" >/dev/null
  assert_eq "$(<"$VOXTYPE_CONFIG_FILE")" "$before"
  assert_eq "$(grep -Fc -- '--user restart voxtype.service' "$systemctl_log")" 2
}

test_failed_dictation_restores_native_voxtype_hotkey() {
  make_fixture
  export BLIZL_HANDY_VOXTYPE_PRESENT=true
  local launcher="$WORK/bin/dictation-window" remover="$WORK/bin/remove-plugin" before
  mkdir -p -- "$(dirname -- "$VOXTYPE_CONFIG_FILE")"
  printf '%s\n' '[hotkey]' 'enabled = true' 'key = "F9"' >"$VOXTYPE_CONFIG_FILE"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$WORK/bin/voxtype"
  chmod +x "$WORK/bin/voxtype"
  before="$(<"$VOXTYPE_CONFIG_FILE")"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "failed\n" >"$1"' >"$launcher"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$remover"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    '[[ $* == "--user is-active voxtype.service" ]] && { printf "active\n"; exit 0; }' \
    'exit 0' >"$WORK/bin/systemctl"
  chmod +x "$launcher" "$remover" "$WORK/bin/systemctl" "$WORK/bin/voxtype"
  unset BLIZL_HANDY_DICTATION_TEST
  export BLIZL_HANDY_TEST_WINDOW_BIN="$launcher"
  export BLIZL_HANDY_PLUGIN_REMOVE_BIN="$remover"

  if "$ROOT/bin/setup" >/dev/null 2>&1; then fail 'failed dictation window unexpectedly passed'; fi

  assert_eq "$(<"$VOXTYPE_CONFIG_FILE")" "$before"
}

test_stale_voxtype_config_without_binary_is_untouched() {
  make_fixture
  local before
  mkdir -p -- "$(dirname -- "$VOXTYPE_CONFIG_FILE")"
  printf '%s\n' '[hotkey]' 'enabled = true' >"$VOXTYPE_CONFIG_FILE"
  before="$(<"$VOXTYPE_CONFIG_FILE")"
  rm -f -- "$WORK/bin/voxtype"

  "$ROOT/bin/setup" >/dev/null

  assert_eq "$(<"$VOXTYPE_CONFIG_FILE")" "$before"
  "$ROOT/bin/uninstall" >/dev/null
}

test_stale_voxtype_config_does_not_block_setup() {
  make_fixture
  mkdir -p -- "$(dirname -- "$VOXTYPE_CONFIG_FILE")"
  printf '%s\n' '[hotkey]' 'key = "F9"' >"$VOXTYPE_CONFIG_FILE"

  "$ROOT/bin/setup" >/dev/null

  grep -Fq 'key = "F9"' "$VOXTYPE_CONFIG_FILE" || fail 'stale VoxType config was changed'
  "$ROOT/bin/uninstall" >/dev/null
}

test_voxtype_removal_defaults_to_no() {
  make_fixture
  # A fake pacman reports VoxType but no exact cached package, so the destructive
  # path must remain skipped even if a future implementation changes its prompt.
  printf '%s\n' '#!/usr/bin/env bash' '[[ ${1:-} == -Q ]] && { echo "voxtype-bin 1.2.3"; exit 0; }' 'exit 1' >"$WORK/bin/pacman"
  chmod +x "$WORK/bin/pacman"
  "$ROOT/bin/setup" >/dev/null
  [[ ! -e "$HOME/.config/systemd/user/voxtype.service" ]] || fail 'VoxType files unexpectedly removed'
  "$ROOT/bin/uninstall"
}

test_voxtype_removal_uses_explicit_package_command() {
  grep -F -- 'sudo pacman -R --noconfirm voxtype-bin' "$ROOT/bin/setup" >/dev/null ||
    fail 'VoxType removal does not use an explicit non-interactive package command'
}

test_partial_voxtype_removal_restores_everything() {
  make_fixture
  local service="$HOME/.config/systemd/user/voxtype.service" config="$HOME/.config/voxtype/config" cache="$WORK/package-cache"
  mkdir -p "$(dirname "$service")" "$(dirname "$config")" "$cache"
  printf service-before >"$service"
  printf config-before >"$config"
  printf package >"$cache/voxtype-bin-1.2.3-1-x86_64.pkg.tar.zst"
  printf '%s\n' '#!/usr/bin/env bash' 'case ${1:-} in is-enabled) echo disabled;; is-active) echo inactive;; *) exit 0;; esac' >"$WORK/bin/systemctl"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$WORK/bin/remove-voxtype"
  printf '%s\n' '#!/usr/bin/env bash' ': >"$HOME/.voxtype-restored-package"' >"$WORK/bin/install-voxtype"
  chmod +x "$WORK/bin/systemctl" "$WORK/bin/remove-voxtype" "$WORK/bin/install-voxtype"
  printf '%s\n' '#!/usr/bin/env bash' '[[ ${1:-} == -Q && ${2:-} == voxtype-bin ]] && { echo "voxtype-bin 1.2.3"; exit 0; }' 'exit 1' >"$WORK/bin/pacman"
  chmod +x "$WORK/bin/pacman"
  export BLIZL_HANDY_PACKAGE_CACHE_DIR="$cache" BLIZL_HANDY_CONFIRM=yes BLIZL_HANDY_VOXTYPE_REMOVE_BIN="$WORK/bin/remove-voxtype" BLIZL_HANDY_VOXTYPE_INSTALL_BIN="$WORK/bin/install-voxtype"
  local before_service before_config
  before_service="$(<"$service")" before_config="$(<"$config")"
  if "$ROOT/bin/setup" >/dev/null 2>&1; then fail 'failed VoxType removal unexpectedly succeeded'; fi
  assert_eq "$(<"$service")" "$before_service"
  assert_eq "$(<"$config")" "$before_config"
  [[ -e "$HOME/.voxtype-restored-package" ]] || fail 'VoxType package artifact was not restored'
  [[ ! -e "$BLIZL_HANDY_STATE_DIR/install.json" ]] || fail 'partial setup committed install state'
  unset BLIZL_HANDY_CONFIRM BLIZL_HANDY_VOXTYPE_REMOVE_BIN BLIZL_HANDY_VOXTYPE_INSTALL_BIN BLIZL_HANDY_PACKAGE_CACHE_DIR
}

test_setup_uninstall_round_trip
test_setup_rejects_conflict_without_mutation
test_setup_unbinds_stock_voxtype_before_claiming_its_key
test_setup_launches_the_test_through_omarchy
test_failed_test_removes_an_installed_checkout
test_failed_test_attempts_plugin_removal_after_incomplete_rollback
test_failed_test_reports_plugin_removal_failure_when_checkout_remains
test_setup_disables_and_uninstall_restores_native_voxtype_hotkey
test_failed_dictation_restores_native_voxtype_hotkey
test_stale_voxtype_config_without_binary_is_untouched
test_stale_voxtype_config_does_not_block_setup
test_setup_rejects_incomplete_managed_block
test_setup_rejects_malformed_lua
test_setup_rejects_malformed_settings_without_commit
test_malformed_settings_restore_preexisting_handy_process
test_setup_rolls_back_after_dictation_gate
test_setup_uses_a_dedicated_dictation_window
test_failed_dictation_window_restores_and_removes_plugin
test_dictation_result_must_contain_only_passed
test_failed_dictation_window_restores_preexisting_handy_process
test_setup_deduplicates_autostart_exec_lines
test_fresh_install_uses_aur_aware_installer
test_voxtype_removal_defaults_to_no
test_voxtype_removal_uses_explicit_package_command
test_partial_voxtype_removal_restores_everything
printf 'setup/uninstall tests: ok\n'
