#!/usr/bin/env bash
# Single-quoted strings generate test executables.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/home/.config/hypr" "$WORK/bin"
printf 'o.bind("F9", "VoxType", "voxtype")\n' >"$WORK/home/.config/hypr/bindings.lua"
for command in handy wpctl; do printf '#!/usr/bin/env bash\nexit 0\n' >"$WORK/bin/$command"; done
printf '%s\n' '#!/usr/bin/env bash' '[[ ${1:-} == configerrors ]] && exit 0' 'exit 0' >"$WORK/bin/hyprctl"
chmod +x "$WORK/bin"/*

if ! HOME="$WORK/home" PATH="$WORK/bin:$PATH" BLIZL_HANDY_BASELINE_TEST=passed "$ROOT/tests-e2e/verify-baseline" >/dev/null 2>&1; then
  : # missing indicator confirmation must fail
else
  echo 'baseline accepted without indicator confirmation' >&2
  exit 1
fi

HOME="$WORK/home" PATH="$WORK/bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=test BLIZL_HANDY_BASELINE_ERRORS_FILE="$WORK/baseline-errors" BLIZL_HANDY_BASELINE_TEST=passed BLIZL_HANDY_BASELINE_INDICATOR=passed "$ROOT/tests-e2e/verify-baseline" >/dev/null
printf '%s\n' '#!/usr/bin/env bash' '[[ ${1:-} == configerrors ]] && { echo broken; exit 0; }' 'exit 0' >"$WORK/bin/hyprctl"
chmod +x "$WORK/bin/hyprctl"
if HOME="$WORK/home" PATH="$WORK/bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=test BLIZL_HANDY_BASELINE_ERRORS_FILE="$WORK/baseline-errors" BLIZL_HANDY_BASELINE_TEST=passed BLIZL_HANDY_BASELINE_INDICATOR=passed "$ROOT/tests-e2e/verify-baseline" >/dev/null 2>&1; then
  echo 'baseline accepted Hyprland config errors' >&2
  exit 1
fi
printf 'baseline tests: ok\n'
