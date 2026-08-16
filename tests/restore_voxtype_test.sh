#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  printf 'restore-voxtype test: %s\n' "$*" >&2
  exit 1
}

home="$TEST_ROOT/home"
fake_bin="$TEST_ROOT/bin"
omarchy_root="$TEST_ROOT/omarchy"
packages="$TEST_ROOT/packages"
command_log="$TEST_ROOT/commands.log"
mkdir -p \
  "$fake_bin" \
  "$home/.config/hypr" \
  "$home/.config/omarchy" \
  "$home/.config/autostart" \
  "$home/.local/bin" \
  "$home/.local/share/com.pais.handy" \
  "$home/.cache/huggingface/hub/models--handy-computer--parakeet-unified-en-0.6b-gguf" \
  "$omarchy_root/default/voxtype"

cat >"$home/.config/hypr/bindings.lua" <<'LUA'
-- personal binding
o.bind("SUPER + B", "Browser", "browser")

-- Dictation push-to-talk is ALT+SPACE via Handy's device-level hotkey
-- (settings in ~/.local/share/com.pais.handy/settings_store.json).
-- Unbind the F9 voxtype default; voxtype is retired.
hl.unbind("F9")

-- BEGIN blizl.handy managed bindings
o.bind("ALT + SPACE", "Start Handy dictation", "/plugin/bin/handy-trigger press")
o.bind("ALT + SPACE", "Stop Handy dictation", "/plugin/bin/handy-trigger release", { release = true })
-- END blizl.handy managed bindings
LUA

cat >"$home/.config/omarchy/shell.json" <<'JSON'
{
  "version": 1,
  "bar": {
    "layout": {
      "left": [{"id":"omarchy.menu"}],
      "center": [{"id":"vliang.indicators"}],
      "right": [{"id":"blizl.handy"}, {"id":"omarchy.audio"}]
    }
  }
}
JSON

cat >"$omarchy_root/default/voxtype/config.toml" <<'TOML'
state_file = "auto"

[hotkey]
enabled = false
TOML

printf 'handy-bin 0.9.5-1\nhandy-bin-debug 0.9.5-1\n' >"$packages"
printf 'settings\n' >"$home/.local/share/com.pais.handy/settings_store.json"
printf 'model\n' >"$home/.cache/huggingface/hub/models--handy-computer--parakeet-unified-en-0.6b-gguf/model"
printf 'desktop\n' >"$home/.config/autostart/Handy.desktop"
printf '#!/bin/sh\n' >"$home/.local/bin/handy-status-follow"
printf '#!/bin/sh\n' >"$home/.local/bin/handy-dictation-setup"

cat >"$fake_bin/pacman" <<'SH'
#!/usr/bin/env bash
if [[ $1 == -Q ]]; then
  line="$(grep -E "^${2//+/\\+} " "$FAKE_PACKAGES" || true)"
  [[ -n $line ]] || exit 1
  printf '%s\n' "$line"
  exit 0
fi
exit 0
SH

cat >"$fake_bin/pkg-add" <<'SH'
#!/usr/bin/env bash
for package in "$@"; do
  grep -q "^$package " "$FAKE_PACKAGES" || printf '%s 1.0-1\n' "$package" >>"$FAKE_PACKAGES"
done
printf 'pkg-add %s\n' "$*" >>"$FAKE_COMMAND_LOG"
SH

cat >"$fake_bin/pkg-drop" <<'SH'
#!/usr/bin/env bash
temporary="$(mktemp)"
cp "$FAKE_PACKAGES" "$temporary"
for package in "$@"; do
  grep -v "^$package " "$temporary" >"$temporary.next" || true
  mv "$temporary.next" "$temporary"
done
mv "$temporary" "$FAKE_PACKAGES"
printf 'pkg-drop %s\n' "$*" >>"$FAKE_COMMAND_LOG"
SH

cat >"$fake_bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$FAKE_COMMAND_LOG"
case "$*" in
  *is-enabled*) printf 'enabled\n' ;;
  *is-active*) printf 'active\n' ;;
esac
SH

cat >"$fake_bin/omarchy" <<'SH'
#!/usr/bin/env bash
printf 'omarchy %s\n' "$*" >>"$FAKE_COMMAND_LOG"
exit 0
SH

cat >"$fake_bin/hyprctl" <<'SH'
#!/usr/bin/env bash
[[ ${1:-} == configerrors ]] && printf ''
exit 0
SH

cat >"$fake_bin/voxtype" <<'SH'
#!/usr/bin/env bash
printf 'voxtype %s\n' "$*" >>"$FAKE_COMMAND_LOG"
exit 0
SH

cat >"$fake_bin/pkill" <<'SH'
#!/usr/bin/env bash
exit 1
SH

chmod +x "$fake_bin"/*

HOME="$home" \
  PATH="$fake_bin:$PATH" \
  OMARCHY_PATH="$omarchy_root" \
  FAKE_PACKAGES="$packages" \
  FAKE_COMMAND_LOG="$command_log" \
  BLIZL_HANDY_STATE_DIR="$home/.local/state/blizl.handy" \
  BLIZL_HANDY_PKG_ADD_BIN="$fake_bin/pkg-add" \
  BLIZL_HANDY_PKG_DROP_BIN="$fake_bin/pkg-drop" \
  BLIZL_HANDY_SKIP_CHECKPOINT=true \
  BLIZL_HANDY_SKIP_MODEL_SETUP=true \
  BLIZL_HANDY_SKIP_PLUGIN_REMOVE=true \
  "$ROOT/bin/restore-voxtype" --yes --bindings stock --keep-plugin >/dev/null

# The reset is intentionally safe to repeat from an already-native state.
HOME="$home" \
  PATH="$fake_bin:$PATH" \
  OMARCHY_PATH="$omarchy_root" \
  FAKE_PACKAGES="$packages" \
  FAKE_COMMAND_LOG="$command_log" \
  BLIZL_HANDY_STATE_DIR="$home/.local/state/blizl.handy" \
  BLIZL_HANDY_PKG_ADD_BIN="$fake_bin/pkg-add" \
  BLIZL_HANDY_PKG_DROP_BIN="$fake_bin/pkg-drop" \
  BLIZL_HANDY_SKIP_CHECKPOINT=true \
  BLIZL_HANDY_SKIP_MODEL_SETUP=true \
  BLIZL_HANDY_SKIP_PLUGIN_REMOVE=true \
  "$ROOT/bin/restore-voxtype" --yes --bindings stock --keep-plugin >/dev/null

grep -q '^voxtype-bin ' "$packages" || fail 'VoxType was not installed'
! grep -q '^handy-bin ' "$packages" || fail 'Handy remained installed'
! grep -q '^handy-bin-debug ' "$packages" || fail 'Handy debug package remained installed'
cmp -s "$home/.config/voxtype/config.toml" "$omarchy_root/default/voxtype/config.toml" || fail 'stock VoxType config was not restored'
grep -Fq 'o.bind("SUPER + B"' "$home/.config/hypr/bindings.lua" || fail 'personal binding was lost'
! grep -Fq 'hl.unbind("F9")' "$home/.config/hypr/bindings.lua" || fail 'stock F9 remained unbound'
! grep -Fq 'BEGIN blizl.handy' "$home/.config/hypr/bindings.lua" || fail 'managed Handy bindings remained'
jq -e '[.bar.layout[][] | select(.id == "omarchy.indicators")] | length == 1' "$home/.config/omarchy/shell.json" >/dev/null || fail 'stock indicator missing'
jq -e '[.bar.layout[][] | select(.id == "blizl.handy" or .id == "vliang.indicators")] | length == 0' "$home/.config/omarchy/shell.json" >/dev/null || fail 'Handy-era indicator remained'
[[ ! -e "$home/.local/share/com.pais.handy" ]] || fail 'Handy user data remained'
[[ ! -e "$home/.config/autostart/Handy.desktop" ]] || fail 'Handy autostart remained'
[[ ! -e "$home/.cache/huggingface/hub/models--handy-computer--parakeet-unified-en-0.6b-gguf" ]] || fail 'Handy model cache remained'
find "$home/.local/state/blizl.handy/restore-voxtype" -name handy-user-data.tar.gz -type f -print -quit | grep -q . || fail 'Handy backup archive was not created'
grep -Fq 'systemctl --user enable --now voxtype.service' "$command_log" || fail 'VoxType service was not enabled'
grep -Fq 'omarchy restart shell' "$command_log" || fail 'Omarchy shell was not restarted'

previous_home="$TEST_ROOT/previous-home"
previous_packages="$TEST_ROOT/previous-packages"
mkdir -p \
  "$previous_home/.config/hypr" \
  "$previous_home/.config/omarchy" \
  "$previous_home/.config/voxtype" \
  "$previous_home/.local/share/voxtype/models"

cat >"$previous_home/.config/hypr/bindings.lua" <<'LUA'
-- Preserve this custom native VoxType setup.
hl.unbind("F9")

-- BEGIN blizl.handy managed bindings
o.bind("ALT + SPACE", "Start Handy dictation", "/plugin/bin/handy-trigger press")
o.bind("ALT + SPACE", "Stop Handy dictation", "/plugin/bin/handy-trigger release", { release = true })
-- END blizl.handy managed bindings
LUA

cat >"$previous_home/.config/omarchy/shell.json" <<'JSON'
{
  "version": 1,
  "bar": {
    "layout": {
      "left": [],
      "center": [{"id":"omarchy.indicators"}],
      "right": [{"id":"blizl.handy"}]
    }
  }
}
JSON

cat >"$previous_home/.config/voxtype/config.toml" <<'TOML'
state_file = "auto"

[hotkey]
enabled = true
key = "SPACE"
modifiers = ["LEFTALT"]
mode = "push_to_talk"
TOML
cp "$previous_home/.config/voxtype/config.toml" "$TEST_ROOT/previous-config.toml"
printf 'model\n' >"$previous_home/.local/share/voxtype/models/ggml-base.en.bin"
printf 'voxtype-bin 1.0-1\nhandy-bin 0.9.5-1\n' >"$previous_packages"

HOME="$previous_home" \
  PATH="$fake_bin:$PATH" \
  OMARCHY_PATH="$omarchy_root" \
  FAKE_PACKAGES="$previous_packages" \
  FAKE_COMMAND_LOG="$command_log" \
  BLIZL_HANDY_STATE_DIR="$previous_home/.local/state/blizl.handy" \
  BLIZL_HANDY_PKG_ADD_BIN="$fake_bin/pkg-add" \
  BLIZL_HANDY_PKG_DROP_BIN="$fake_bin/pkg-drop" \
  BLIZL_HANDY_SKIP_CHECKPOINT=true \
  BLIZL_HANDY_SKIP_MODEL_SETUP=true \
  BLIZL_HANDY_SKIP_PLUGIN_REMOVE=true \
  "$ROOT/bin/restore-voxtype" --yes --bindings previous --keep-plugin >/dev/null

cmp -s "$previous_home/.config/voxtype/config.toml" "$TEST_ROOT/previous-config.toml" || fail 'previous VoxType config was overwritten'
grep -Fq 'hl.unbind("F9")' "$previous_home/.config/hypr/bindings.lua" || fail 'previous F9 override was not preserved'
! grep -Fq 'BEGIN blizl.handy' "$previous_home/.config/hypr/bindings.lua" || fail 'managed Handy bindings remained in preserve mode'
! grep -q '^handy-bin ' "$previous_packages" || fail 'Handy remained installed in preserve mode'

printf 'restore-voxtype tests: ok\n'
