#!/usr/bin/env bash
set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

failures=0
tests_run=0

fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}
pass() { printf 'ok - %s\n' "$1"; }

assert_status() {
  local expected=$1 actual=$2
  [[ "$expected" == "$actual" ]] || {
    printf '  expected status %s, got %s\n' "$expected" "$actual"
    return 1
  }
}

new_fixture() {
  FIXTURE="$TEST_ROOT/fixture-$tests_run"
  mkdir -p "$FIXTURE/bin" "$FIXTURE/runtime"

  cat >"$FIXTURE/bin/wpctl" <<'EOF'
#!/usr/bin/env bash
cat "$WPCTL_FIXTURE"
exit "${WPCTL_STATUS:-0}"
EOF
  cat >"$FIXTURE/bin/omarchy" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
EOF
  cat >"$FIXTURE/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ -f "$HANDY_RUNNING" ]]
EOF
  cat >"$FIXTURE/bin/handy" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --start-hidden)
    status=${HANDY_START_STATUS:-0}
    [[ "$status" == 0 ]] && : >"$HANDY_RUNNING"
    exit "$status"
    ;;
  --toggle-transcription)
    count=0
    [[ -f "$TOGGLE_COUNT" ]] && count=$(<"$TOGGLE_COUNT")
    printf '%s\n' "$((count + 1))" >"$TOGGLE_COUNT"
    exit "${HANDY_TOGGLE_STATUS:-0}"
    ;;
  --cancel)
    status=${HANDY_CANCEL_STATUS:-0}
    [[ "$status" == 0 ]] && : >"$CANCELLED"
    exit "$status"
    ;;
esac
exit 64
EOF
  chmod +x "$FIXTURE/bin"/*

  WPCTL_FIXTURE="$FIXTURE/wpctl.out"
  NOTIFY_LOG="$FIXTURE/notifications.log"
  TOGGLE_COUNT="$FIXTURE/toggles"
  CANCELLED="$FIXTURE/cancelled"
  HANDY_RUNNING="$FIXTURE/handy.running"
  export WPCTL_FIXTURE NOTIFY_LOG TOGGLE_COUNT CANCELLED HANDY_RUNNING
  export WPCTL_BIN="$FIXTURE/bin/wpctl"
  export OMARCHY_NOTIFICATION_BIN="$FIXTURE/bin/omarchy"
  export PGREP_BIN="$FIXTURE/bin/pgrep"
  export HANDY_BIN="$FIXTURE/bin/handy"
  export BLIZL_HANDY_RUNTIME_DIR="$FIXTURE/runtime"
  : >"$NOTIFY_LOG"
  printf '0\n' >"$TOGGLE_COUNT"
  rm -f -- "$CANCELLED"
  rm -f -- "$HANDY_RUNNING"
  unset HANDY_START_STATUS HANDY_TOGGLE_STATUS HANDY_CANCEL_STATUS WPCTL_STATUS
  chmod +x "$ROOT/bin/handy-trigger"
}

run_trigger() {
  set +e
  "$ROOT/bin/handy-trigger" "$@"
  RUN_STATUS=$?
}

run_test() {
  local name=$1
  tests_run=$((tests_run + 1))
  new_fixture
  if "$name"; then pass "$name"; else fail "$name"; fi
}

microphone_fixture() {
  cat >"$WPCTL_FIXTURE" <<'EOF'
id 42, type PipeWire:Interface:Node/3
    media.class = "Audio/Source"
    node.name = "alsa_input.usb-microphone"
EOF
}

test_real_microphone_is_available() {
  microphone_fixture
  source "$ROOT/lib/microphone.sh"
  microphone_is_available
}

test_muted_microphone_is_still_available_to_trigger() {
  cat >"$WPCTL_FIXTURE" <<'EOF'
media.class = "Audio/Source"
node.name = "alsa_input.usb-microphone"
audio.muted = true
EOF
  source "$ROOT/lib/microphone.sh"
  microphone_is_available
}

test_absent_microphone_is_rejected() {
  : >"$WPCTL_FIXTURE"
  source "$ROOT/lib/microphone.sh"
  ! microphone_is_available
}

test_wpctl_failure_is_rejected() {
  microphone_fixture
  WPCTL_STATUS=1
  export WPCTL_STATUS
  source "$ROOT/lib/microphone.sh"
  ! microphone_is_available
}

test_dummy_microphone_is_rejected() {
  cat >"$WPCTL_FIXTURE" <<'EOF'
media.class = "Audio/Source"
node.name = "auto_null"
EOF
  source "$ROOT/lib/microphone.sh"
  ! microphone_is_available
}

test_monitor_microphone_is_rejected() {
  cat >"$WPCTL_FIXTURE" <<'EOF'
media.class = "Audio/Source"
node.name = "alsa_output.pci.monitor"
EOF
  source "$ROOT/lib/microphone.sh"
  ! microphone_is_available
}

test_toggle_without_microphone_fails_and_notifies() {
  : >"$WPCTL_FIXTURE"
  run_trigger toggle
  assert_status 2 "$RUN_STATUS" || return 1
  [[ $(<"$TOGGLE_COUNT") == 0 ]] || return 1
  grep -q 'Microphone not detected' "$NOTIFY_LOG"
}

test_toggle_starts_handy_if_not_running() {
  microphone_fixture
  run_trigger toggle
  assert_status 0 "$RUN_STATUS" || return 1
  [[ -f "$HANDY_RUNNING" ]] || return 1
  [[ $(<"$TOGGLE_COUNT") == 1 ]]
}

test_toggle_start_failure_notifies() {
  microphone_fixture
  HANDY_START_STATUS=1
  export HANDY_START_STATUS
  run_trigger toggle
  assert_status 1 "$RUN_STATUS" || return 1
  grep -q 'Handy could not start dictation' "$NOTIFY_LOG"
}

test_toggle_transcription_failure_notifies() {
  microphone_fixture
  HANDY_TOGGLE_STATUS=1
  export HANDY_TOGGLE_STATUS
  run_trigger toggle
  assert_status 1 "$RUN_STATUS" || return 1
  grep -q 'Handy could not start dictation' "$NOTIFY_LOG"
}

test_stop_when_running_calls_transcribe() {
  microphone_fixture
  : >"$HANDY_RUNNING"
  run_trigger stop
  assert_status 0 "$RUN_STATUS" || return 1
  [[ $(<"$TOGGLE_COUNT") == 1 ]] || return 1
  [[ ! -e "$CANCELLED" ]]
}

test_stop_when_not_running_is_noop() {
  microphone_fixture
  run_trigger stop
  assert_status 0 "$RUN_STATUS" || return 1
  [[ $(<"$TOGGLE_COUNT") == 0 ]]
}

test_stop_failure_cancels_and_notifies() {
  microphone_fixture
  : >"$HANDY_RUNNING"
  HANDY_TOGGLE_STATUS=1
  export HANDY_TOGGLE_STATUS
  run_trigger stop
  assert_status 1 "$RUN_STATUS" || return 1
  [[ -e "$CANCELLED" ]] || return 1
  grep -q 'Handy could not finish dictation' "$NOTIFY_LOG"
}

test_notify_missing_mic_action() {
  run_trigger notify-missing-mic
  assert_status 0 "$RUN_STATUS" || return 1
  grep -q 'Microphone not detected' "$NOTIFY_LOG"
}

test_invalid_action_exits_64() {
  run_trigger invalid-action
  assert_status 64 "$RUN_STATUS"
}

for test_name in \
  test_real_microphone_is_available \
  test_muted_microphone_is_still_available_to_trigger \
  test_absent_microphone_is_rejected \
  test_wpctl_failure_is_rejected \
  test_dummy_microphone_is_rejected \
  test_monitor_microphone_is_rejected \
  test_toggle_without_microphone_fails_and_notifies \
  test_toggle_starts_handy_if_not_running \
  test_toggle_start_failure_notifies \
  test_toggle_transcription_failure_notifies \
  test_stop_when_running_calls_transcribe \
  test_stop_when_not_running_is_noop \
  test_stop_failure_cancels_and_notifies \
  test_notify_missing_mic_action \
  test_invalid_action_exits_64; do
  run_test "$test_name"
done

printf '\n%d tests, %d failures\n' "$tests_run" "$failures"
((failures == 0))
