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

new_fixture() {
  tests_run=$((tests_run + 1))
  FIXTURE="$TEST_ROOT/fixture-$tests_run"
  mkdir -p "$FIXTURE"
  RESULT_FILE="$FIXTURE/result"
}

run_helper() {
  local input=$1
  export BLIZL_HANDY_TEST_PID_FILE="$RESULT_FILE.pid"
  set +e
  printf '%s' "$input" | "$ROOT/bin/handy-test-window" "$RESULT_FILE" 'ALT + SPACE' >/dev/null 2>&1
  RUN_STATUS=$?
  set -e
}

assert_result() {
  local expected=$1
  [[ -f "$RESULT_FILE" ]] || return 1
  [[ "$(<"$RESULT_FILE")" == "$expected" ]] || return 1
  [[ "$(wc -l <"$RESULT_FILE")" == 1 ]] || return 1
  ! compgen -G "$RESULT_FILE.tmp.*" >/dev/null || return 1
  [[ ! -e "$RESULT_FILE.pid" ]]
}

test_non_empty_dictation_passes() {
  new_fixture
  run_helper $'this is a real test\n'
  [[ "$RUN_STATUS" == 0 ]] || return 1
  assert_result passed
}

test_non_empty_dictation_with_padding_passes() {
  new_fixture
  run_helper $'  this is a real test with spaces  \n'
  [[ "$RUN_STATUS" == 0 ]] || return 1
  assert_result passed
}

test_whitespace_only_dictation_fails() {
  new_fixture
  run_helper $' \t\n'
  [[ "$RUN_STATUS" != 0 ]] || return 1
  assert_result failed
}

test_eof_is_a_failed_test() {
  new_fixture
  run_helper ''
  [[ "$RUN_STATUS" != 0 ]] || return 1
  assert_result failed
}

test_instructions_explain_handy_and_conflict_safety() {
  new_fixture
  local output
  set +e
  output="$(printf 'test words\n' | "$ROOT/bin/handy-test-window" "$RESULT_FILE" 'ALT + SPACE' 2>&1)"
  RUN_STATUS=$?
  set -e
  [[ "$RUN_STATUS" == 0 ]] || return 1
  [[ "$output" == *'tests Handy with the selected shortcut: ALT + SPACE'* ]] || return 1
  [[ "$output" == *'Setup disabled any conflicting VoxType shortcut before opening this window.'* ]] || return 1
  [[ "$output" == *'Dictated text:'* ]] || return 1
  [[ "$output" == *'----------------------------------------------------------------------'* ]]
}

test_pid_file_identifies_live_helper_and_is_removed() {
  new_fixture
  local input_pipe="$FIXTURE/input" helper_pid recorded_pid writer_pid
  mkfifo "$input_pipe"
  export BLIZL_HANDY_TEST_PID_FILE="$RESULT_FILE.pid"
  {
    sleep 0.2
    printf 'dictated words\n'
  } >"$input_pipe" &
  writer_pid=$!
  "$ROOT/bin/handy-test-window" "$RESULT_FILE" 'ALT + SPACE' <"$input_pipe" >/dev/null 2>&1 &
  helper_pid=$!
  for _ in {1..50}; do
    [[ -f "$BLIZL_HANDY_TEST_PID_FILE" ]] && break
    sleep 0.01
  done
  [[ -f "$BLIZL_HANDY_TEST_PID_FILE" ]] || {
    kill "$helper_pid" 2>/dev/null || true
    kill "$writer_pid" 2>/dev/null || true
    return 1
  }
  recorded_pid=$(<"$BLIZL_HANDY_TEST_PID_FILE")
  [[ "$recorded_pid" == "$helper_pid" ]] || return 1
  wait "$helper_pid"
  wait "$writer_pid" || true
  [[ ! -e "$BLIZL_HANDY_TEST_PID_FILE" ]]
}

test_pid_file_is_removed_when_helper_is_terminated() {
  new_fixture
  local input_pipe="$FIXTURE/input" helper_pid writer_pid
  mkfifo "$input_pipe"
  export BLIZL_HANDY_TEST_PID_FILE="$RESULT_FILE.pid"
  {
    sleep 1
    printf 'dictated words\n'
  } >"$input_pipe" 2>/dev/null &
  writer_pid=$!
  "$ROOT/bin/handy-test-window" "$RESULT_FILE" 'ALT + SPACE' <"$input_pipe" >/dev/null 2>&1 &
  helper_pid=$!
  for _ in {1..50}; do
    [[ -f "$BLIZL_HANDY_TEST_PID_FILE" ]] && break
    sleep 0.01
  done
  [[ -f "$BLIZL_HANDY_TEST_PID_FILE" ]] || return 1
  kill -TERM "$helper_pid"
  set +e
  wait "$helper_pid"
  set -e
  wait "$writer_pid" 2>/dev/null || true
  [[ ! -e "$BLIZL_HANDY_TEST_PID_FILE" ]]
}

test_invalid_arguments_are_rejected() {
  new_fixture
  set +e
  "$ROOT/bin/handy-test-window" "$RESULT_FILE" >/dev/null 2>&1
  RUN_STATUS=$?
  set -e
  [[ "$RUN_STATUS" == 64 ]] || return 1
  [[ ! -e "$RESULT_FILE" ]]
}

for test_name in \
  test_non_empty_dictation_passes \
  test_non_empty_dictation_with_padding_passes \
  test_whitespace_only_dictation_fails \
  test_eof_is_a_failed_test \
  test_instructions_explain_handy_and_conflict_safety \
  test_pid_file_identifies_live_helper_and_is_removed \
  test_pid_file_is_removed_when_helper_is_terminated \
  test_invalid_arguments_are_rejected; do
  if "$test_name"; then pass "$test_name"; else fail "$test_name"; fi
done

if ((failures > 0)); then
  printf '%s test(s) failed.\n' "$failures" >&2
  exit 1
fi

printf 'dictation window tests: %s passed.\n' "$tests_run"
