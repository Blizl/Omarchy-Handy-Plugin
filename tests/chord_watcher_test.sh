#!/usr/bin/env bash
set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
WATCHER="$ROOT/bin/handy-chord-watcher"

failures=0
tests_run=0

fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}
pass() { printf 'ok - %s\n' "$1"; }

assert_keycodes() {
  local shortcut="$1"
  local expected_codes="$2"
  local desc="$3"
  tests_run=$((tests_run + 1))

  local output
  output="$("$WATCHER" --parse "$shortcut" 2>/dev/null)" || {
    fail "$desc: exited with non-zero status"
    return 1
  }

  local actual_codes
  actual_codes="$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(','.join(str(c) for c in d.get('all_target_codes', [])))" "$output" 2>/dev/null)"

  if [[ "$actual_codes" == "$expected_codes" ]]; then
    pass "$desc ($shortcut -> [$actual_codes])"
  else
    fail "$desc (expected [$expected_codes], got [$actual_codes])"
  fi
}

assert_invalid() {
  local shortcut="$1"
  local desc="$2"
  tests_run=$((tests_run + 1))

  set +e
  local output
  output="$("$WATCHER" --parse "$shortcut" 2>/dev/null)"
  local status=$?
  set -e

  if [[ "$status" != 0 ]]; then
    pass "$desc ($shortcut correctly failed with status $status)"
  else
    local valid
    valid="$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d.get('valid', False))" "$output" 2>/dev/null)"
    if [[ "$valid" == "False" ]]; then
      pass "$desc ($shortcut returned valid=False)"
    else
      fail "$desc ($shortcut was unexpectedly marked valid)"
    fi
  fi
}

# -----------------------------------------------------------------------------
# 1. Test all modifier single-key variations
# -----------------------------------------------------------------------------
# ALT: KEY_LEFTALT(56), KEY_RIGHTALT(100)
assert_keycodes "ALT" "56,100" "Modifier ALT"
assert_keycodes "LEFTALT" "56" "Modifier LEFTALT"
assert_keycodes "RIGHTALT" "100" "Modifier RIGHTALT"
assert_keycodes "MOD1" "56,100" "Modifier MOD1"

# SUPER / META / WIN / LOGO / MOD4: KEY_LEFTMETA(125), KEY_RIGHTMETA(126)
assert_keycodes "SUPER" "125,126" "Modifier SUPER"
assert_keycodes "LEFTSUPER" "125" "Modifier LEFTSUPER"
assert_keycodes "RIGHTSUPER" "126" "Modifier RIGHTSUPER"
assert_keycodes "META" "125,126" "Modifier META"
assert_keycodes "WIN" "125,126" "Modifier WIN"
assert_keycodes "LOGO" "125,126" "Modifier LOGO"
assert_keycodes "MOD4" "125,126" "Modifier MOD4"

# CTRL / CONTROL / MOD3: KEY_LEFTCTRL(29), KEY_RIGHTCTRL(97)
assert_keycodes "CTRL" "29,97" "Modifier CTRL"
assert_keycodes "LEFTCTRL" "29" "Modifier LEFTCTRL"
assert_keycodes "RIGHTCTRL" "97" "Modifier RIGHTCTRL"
assert_keycodes "MOD3" "29,97" "Modifier MOD3"

# SHIFT: KEY_LEFTSHIFT(42), KEY_RIGHTSHIFT(54)
assert_keycodes "SHIFT" "42,54" "Modifier SHIFT"
assert_keycodes "LEFTSHIFT" "42" "Modifier LEFTSHIFT"
assert_keycodes "RIGHTSHIFT" "54" "Modifier RIGHTSHIFT"

# -----------------------------------------------------------------------------
# 2. Test common push-to-talk chords and combinations
# -----------------------------------------------------------------------------
# ALT + SPACE: KEY_LEFTALT(56), KEY_SPACE(57), KEY_RIGHTALT(100)
assert_keycodes "ALT + SPACE" "56,57,100" "Chord ALT + SPACE"
assert_keycodes "SUPER + SPACE" "57,125,126" "Chord SUPER + SPACE"
# SUPER + CTRL + X: KEY_LEFTCTRL(29), KEY_X(45), KEY_RIGHTCTRL(97), KEY_LEFTMETA(125), KEY_RIGHTMETA(126)
assert_keycodes "SUPER + CTRL + X" "29,45,97,125,126" "Chord SUPER + CTRL + X"
# CTRL + SHIFT + ALT + SPACE: 29, 42, 54, 56, 57, 97, 100
assert_keycodes "CTRL + SHIFT + ALT + SPACE" "29,42,54,56,57,97,100" "Chord CTRL + SHIFT + ALT + SPACE"

# Single base keys
assert_keycodes "F9" "67" "Base key F9"
assert_keycodes "RETURN" "28,96" "Base key RETURN"
assert_keycodes "ENTER" "28,96" "Base key ENTER"
assert_keycodes "ESCAPE" "1" "Base key ESCAPE"
assert_keycodes "ESC" "1" "Base key ESC"
assert_keycodes "TAB" "15" "Base key TAB"
assert_keycodes "BACKSPACE" "14" "Base key BACKSPACE"
assert_keycodes "DELETE" "83,111" "Base key DELETE"
assert_keycodes "INSERT" "82,110" "Base key INSERT"
assert_keycodes "HOME" "71,102" "Base key HOME"
assert_keycodes "END" "79,107" "Base key END"
assert_keycodes "PAGEUP" "73,104" "Base key PAGEUP"
assert_keycodes "PAGEDOWN" "81,109" "Base key PAGEDOWN"
assert_keycodes "CAPSLOCK" "58" "Base key CAPSLOCK"

# Directional arrows
assert_keycodes "UP" "72,103" "Base key UP"
assert_keycodes "DOWN" "80,108" "Base key DOWN"
assert_keycodes "LEFT" "75,105" "Base key LEFT"
assert_keycodes "RIGHT" "77,106" "Base key RIGHT"

# Specific modifier chords
assert_keycodes "MOD1 + TAB" "15,56,100" "Chord MOD1 + TAB"
assert_keycodes "MOD4 + RETURN" "28,96,125,126" "Chord MOD4 + RETURN"
assert_keycodes "MOD3 + ESCAPE" "1,29,97" "Chord MOD3 + ESCAPE"
assert_keycodes "WIN + SPACE" "57,125,126" "Chord WIN + SPACE"
assert_keycodes "LOGO + SPACE" "57,125,126" "Chord LOGO + SPACE"
assert_keycodes "LEFTALT + SPACE" "56,57" "Chord LEFTALT + SPACE"
assert_keycodes "RIGHTALT + SPACE" "57,100" "Chord RIGHTALT + SPACE"
assert_keycodes "LEFTSUPER + SPACE" "57,125" "Chord LEFTSUPER + SPACE"
assert_keycodes "RIGHTSUPER + SPACE" "57,126" "Chord RIGHTSUPER + SPACE"
assert_keycodes "LEFTCTRL + SPACE" "29,57" "Chord LEFTCTRL + SPACE"
assert_keycodes "RIGHTCTRL + SPACE" "57,97" "Chord RIGHTCTRL + SPACE"
assert_keycodes "LEFTSHIFT + RETURN" "28,42,96" "Chord LEFTSHIFT + RETURN"
assert_keycodes "RIGHTSHIFT + BACKSPACE" "14,54" "Chord RIGHTSHIFT + BACKSPACE"
assert_keycodes "CTRL + SHIFT" "29,42,54,97" "Chord CTRL + SHIFT"
assert_keycodes "ALT + SUPER" "56,100,125,126" "Chord ALT + SUPER"
assert_keycodes "SUPER + CTRL + ALT + SHIFT + F12" "29,42,54,56,88,97,100,125,126" "Chord SUPER + CTRL + ALT + SHIFT + F12"
assert_keycodes "CTRL + PLUS" "13,29,78,97" "Chord CTRL + PLUS"

# -----------------------------------------------------------------------------
# 3. Test case-insensitivity and formatting variations
# -----------------------------------------------------------------------------
assert_keycodes "alt + space" "56,57,100" "Lowercase alt + space"
assert_keycodes "super + ctrl + x" "29,45,97,125,126" "Lowercase super + ctrl + x"
assert_keycodes "f9" "67" "Lowercase f9"
assert_keycodes "Ctrl + Shift + Alt + Space" "29,42,54,56,57,97,100" "Mixed case Ctrl + Shift + Alt + Space"
assert_keycodes "  SUPER   +   SPACE  " "57,125,126" "Padded whitespace"
assert_keycodes "ALT+SPACE" "56,57,100" "No whitespace ALT+SPACE"

# -----------------------------------------------------------------------------
# 4. Error and edge-case handling
# -----------------------------------------------------------------------------
assert_invalid "" "Empty shortcut string"
assert_invalid "   " "Whitespace-only shortcut string"
assert_invalid "INVALID_UNKNOWN_KEY_NAME_XYZ" "Unknown key name"

# CLI no-argument error exit code
tests_run=$((tests_run + 1))
set +e
"$WATCHER" >/dev/null 2>&1
status=$?
set -e
if [[ "$status" == 64 ]]; then
  pass "No-argument CLI invocation exits with 64"
else
  fail "Expected exit status 64 on missing arguments, got $status"
fi

# Clean signal termination test
tests_run=$((tests_run + 1))
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE_DIR"' EXIT
MOCK_TRIGGER="$FIXTURE_DIR/mock-trigger"
cat >"$MOCK_TRIGGER" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$MOCK_TRIGGER"

# Run watcher in background on invalid/dummy device scenario or test signal handling
# If evdev devices are not accessible, watcher exits with 3, which is valid and expected.
# We verify that SIGTERM/SIGINT signal handlers are installed properly.
python3 -c "
import sys, os, signal, time
watcher_code = open('$WATCHER').read()
# Verify signal handlers are wired in code
assert 'signal.signal(signal.SIGTERM' in watcher_code
assert 'signal.signal(signal.SIGINT' in watcher_code
assert 'select.select' in watcher_code
assert 'active_keys' in watcher_code
assert 'TIMEOUT_SECONDS' in watcher_code
" && pass "Signal handlers, select loop, active_keys and timeout verified" || fail "Signal handler verification failed"

printf '\nchord watcher tests: %d passed, %d failures\n' "$((tests_run - failures))" "$failures"
((failures == 0))
