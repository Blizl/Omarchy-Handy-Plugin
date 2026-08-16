#!/usr/bin/env bash
set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
WIDGET="$ROOT/HandyWidget.qml"
failures=0
tests_run=0

pass() { printf 'ok - %s\n' "$1"; }
fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}

contains() { grep -Fq -- "$1" "$WIDGET"; }
line_of() { grep -nF -- "$1" "$WIDGET" | head -n1 | cut -d: -f1; }

run_test() {
  local name=$1
  tests_run=$((tests_run + 1))
  if "$name"; then pass "$name"; else fail "$name"; fi
}

test_safe_source_state() {
  contains 'readonly property bool microphonePresent: !!(source && source.audio)' || return 1
  contains 'readonly property bool microphoneMuted: microphonePresent && source.audio.muted' || return 1
}

test_state_precedence() {
  local missing muted recording in_use available
  missing=$(line_of 'if (!microphonePresent) return "missing"')
  muted=$(line_of 'if (microphoneMuted) return "muted"')
  recording=$(line_of 'if (handyRecording) return "recording"')
  in_use=$(line_of 'if (microphoneInUse) return "in-use"')
  available=$(line_of 'return "available"')
  [[ -n "$missing" && -n "$muted" && -n "$recording" && -n "$in_use" && -n "$available" ]] || return 1
  ((missing < muted && muted < recording && recording < in_use && in_use < available))
}

test_capture_stream_classification() {
  contains 'node.isStream' || return 1
  contains 'node.isSink === false' || return 1
  contains 'function hasHandyCaptureStream' || return 1
  contains 'function hasActiveCaptureStream' || return 1
}

test_pipewire_objects_are_tracked() {
  contains 'PwObjectTracker' || return 1
  contains 'objects: root.source ? [root.source].concat(root.nodes) : root.nodes' || return 1
}

test_glyph_and_click_actions() {
  contains 'text: root.icon' || return 1
  contains 'state === "missing" || state === "muted"' || return 1
  contains 'Qt.MiddleButton' || return 1
  contains 'Qt.LeftButton' || return 1
  contains 'button === Qt.LeftButton && root.handyRecording' || return 1
  contains 'if (root.handyRecording) return "Handy is recording — click to stop"' || return 1
  contains 'omarchy-shell shell toggle omarchy.audio' || return 1
  contains 'notify-missing-mic' || return 1
  contains 'triggerCommand("stop")' || return 1
  contains 'uwsm-app -- handy' || return 1
}

for test_name in \
  test_safe_source_state \
  test_state_precedence \
  test_capture_stream_classification \
  test_pipewire_objects_are_tracked \
  test_glyph_and_click_actions; do
  run_test "$test_name"
done

printf '\n%d tests, %d failures\n' "$tests_run" "$failures"
((failures == 0))
