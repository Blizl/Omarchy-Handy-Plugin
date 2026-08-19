#!/usr/bin/env bash
# Single-quoted strings generate test executables.
# shellcheck disable=SC2016
# Fake binaries are injected by prepending to PATH, both inside subshells and as
# per-command prefixes; that scoping is deliberate, not a lost assignment.
# shellcheck disable=SC2030,SC2031
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# A poisoned $USER must never reach sudo. setfacl -m parses commas as extra ACL
# entries, so "o::rw" in a user name would expose every /dev/input/event* device
# to all local accounts.
POISON='pwned:r,o::rw,u:nobody'

test_privileged_commands_ignore_user_env() {
  local home="$WORK/input-home" fakebin="$WORK/input-bin" log="$WORK/sudo.log"
  mkdir -p "$home/.config/hypr" "$fakebin"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >>"'"$log"'"' >"$fakebin/sudo"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$fakebin/setfacl"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "users wheel"' >"$fakebin/groups"
  # A non-root uid keeps the root guard happy, and a group list without "input"
  # forces the privileged usermod branch to run.
  printf '%s\n' '#!/usr/bin/env bash' \
    'case "${1:-}" in' \
    '  -un) echo testuser ;;' \
    '  -u) echo 1234 ;;' \
    '  -nG) echo "users wheel" ;;' \
    '  *) exec /usr/bin/id "$@" ;;' \
    'esac' >"$fakebin/id"
  chmod +x "$fakebin/sudo" "$fakebin/setfacl" "$fakebin/groups" "$fakebin/id"

  # ensure_input_permissions runs inside preflight, before any file is touched;
  # setup then fails on the absent bindings file, which is all this test needs.
  (
    export HOME="$home" PATH="$fakebin:$PATH" USER="$POISON"
    export BLIZL_HANDY_STATE_DIR="$home/.local/state/blizl.handy"
    export HYPR_BINDINGS_FILE="$home/.config/hypr/missing-bindings.lua"
    export BLIZL_HANDY_NONINTERACTIVE=true BLIZL_HANDY_CONFIRM=yes
    "$ROOT/bin/setup" >/dev/null 2>&1
  ) || true

  [[ -f "$log" ]] || fail 'the privileged input-permission path never ran'
  ! grep -Fq -- "$POISON" "$log" || fail "poisoned \$USER reached sudo: $(cat "$log")"
  ! grep -Fq -- 'o::rw' "$log" || fail "an injected ACL entry reached setfacl: $(cat "$log")"
  grep -Fq -- 'usermod -aG input -- testuser' "$log" ||
    fail "usermod did not use the kernel-reported name behind --: $(cat "$log")"
}

# The setfacl branch only runs on a host where /dev/input/event0 exists and is
# unreadable, which is not reproducible in a test, so pin its shape in source.
test_setfacl_addresses_the_account_by_numeric_uid() {
  grep -Fq 'sudo setfacl -m "u:${current_uid}:r" /dev/input/event*' "$ROOT/bin/setup" ||
    fail 'setfacl no longer addresses the account by numeric uid'
  ! grep -Fq 'setfacl -m "u:${current_user}' "$ROOT/bin/setup" ||
    fail 'setfacl interpolates a user name again, which setfacl parses for commas'
  grep -Fq 'current_user="$(id -un)"' "$ROOT/bin/setup" ||
    fail 'the user name is no longer taken from id'
}

test_uninstall_rejects_transaction_path_traversal() {
  local home="$WORK/uninstall-home" state escape
  state="$home/.local/state/blizl.handy"
  escape="$WORK/outside-transaction"
  # backups/ must exist so the traversing path resolves on the filesystem; the
  # point is that the containment check accepts it, not that it dead-ends.
  mkdir -p "$state/backups" "$escape/files"
  : >"$escape/targets.tsv"
  # Enough ".." to reach / from any depth, then re-descend to a directory that
  # is a fully formed transaction. Without canonicalization the prefix test
  # accepts this and transaction_restore runs against it.
  local traversal
  traversal="$state/backups/$(printf '../%.0s' $(seq 40))${escape#/}"
  printf '{"version":2,"transaction":"%s","shortcut":"ALT + SPACE"}\n' \
    "$traversal" >"$state/install.json"
  [[ "$(realpath -m -- "$traversal")" == "$escape" ]] ||
    fail 'the traversal fixture does not resolve outside the state directory'

  local output status=0
  output="$(HOME="$home" BLIZL_HANDY_STATE_DIR="$state" "$ROOT/bin/uninstall" 2>&1)" || status=$?
  ((status != 0)) || fail 'uninstall accepted a traversing transaction path'
  [[ "$output" == *'Refusing unexpected transaction path'* ]] ||
    fail "traversal was not reported clearly: $output"
  [[ -f "$state/install.json" ]] ||
    fail 'uninstall consumed the transaction instead of refusing the traversing path'
}

# bindings.lua is the only file the plugin touches that another program then
# executes as code, which is where the carriage-return comment escape lived.
# Setup no longer writes it at all, so assert the absence of a writer rather
# than the correctness of an escaping routine. bin/restore-voxtype is exempt:
# it is an explicit reset that strips leftover blocks from older installs.
test_setup_never_writes_the_hyprland_bindings_file() {
  local writers
  writers="$(grep -n 'bindings_write_managed' "$ROOT/bin/setup" "$ROOT/lib/bindings.sh" || true)"
  [[ -z "$writers" ]] || fail "a bindings.lua writer came back: $writers"

  writers="$(grep -nE '(>|mv -- .*) *"\$(BINDINGS_FILE|bindings_file)"' \
    "$ROOT/bin/setup" "$ROOT/lib/bindings.sh" || true)"
  [[ -z "$writers" ]] || fail "setup writes the Hyprland bindings file again: $writers"

  grep -Fq 'transaction_backup "$BINDINGS_FILE"' "$ROOT/bin/setup" &&
    fail 'setup snapshots bindings.lua again; uninstall would clobber later edits'
  return 0
}

test_entry_points_refuse_to_run_as_root() {
  local script
  # shellcheck source=../lib/privilege.sh
  # Test paths are resolved at runtime.
  # shellcheck disable=SC1091
  source "$ROOT/lib/privilege.sh"
  local fakebin="$WORK/root-bin"
  mkdir -p "$fakebin"
  printf '%s\n' '#!/usr/bin/env bash' '[[ ${1:-} == -u ]] && { echo 0; exit 0; }' 'exec /usr/bin/id "$@"' >"$fakebin/id"
  chmod +x "$fakebin/id"
  PATH="$fakebin:$PATH" privilege_require_non_root /x/setup 2>/dev/null &&
    fail 'the guard allowed a root run'
  PATH="$fakebin:$PATH" BLIZL_HANDY_ALLOW_ROOT=true privilege_require_non_root /x/setup 2>/dev/null ||
    fail 'the documented container override did not work'
  privilege_require_non_root /x/setup || fail 'the guard blocked an ordinary user'

  for script in setup uninstall restore-voxtype e2e-checkpoint; do
    grep -Fq 'privilege_require_non_root' "$ROOT/bin/$script" ||
      fail "bin/$script is missing the root guard"
  done
}

test_no_privileged_command_takes_an_untrusted_name() {
  local offenders
  # Package names handed to omarchy must be shell literals or the hardcoded
  # allowlist variable, never a value parsed out of user-writable state.
  offenders="$(grep -rn 'omarchy pkg \(add\|drop\)' "$ROOT/bin" "$ROOT/lib" |
    grep -F '$' | grep -Fv 'omarchy pkg add "$name"' | grep -Fv 'omarchy pkg drop "$name"' || true)"
  [[ -z "$offenders" ]] || fail "unexpected variable in a privileged package command: $offenders"

  offenders="$(grep -rn 'sudo ' "$ROOT/bin" "$ROOT/lib" | grep -F 'USER' || true)"
  [[ -z "$offenders" ]] || fail "a sudo command interpolates \$USER again: $offenders"
}

test_privileged_commands_ignore_user_env
test_setfacl_addresses_the_account_by_numeric_uid
test_uninstall_rejects_transaction_path_traversal
test_setup_never_writes_the_hyprland_bindings_file
test_entry_points_refuse_to_run_as_root
test_no_privileged_command_takes_an_untrusted_name
printf 'security tests: ok\n'
