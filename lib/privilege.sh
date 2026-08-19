#!/usr/bin/env bash

# These scripts configure a single user's desktop: they write under $HOME and
# call sudo only for the few operations that genuinely need it. Running the
# whole thing as root writes root-owned files into the user's configuration and
# promotes every BLIZL_HANDY_*_BIN test seam into a root code-execution path, so
# refuse up front instead of half-applying a broken install.
privilege_require_non_root() {
  local script="${1:-$0}"
  [[ "${BLIZL_HANDY_ALLOW_ROOT:-false}" == true ]] && return 0
  [[ "$(id -u)" == 0 ]] || return 0
  printf '%s: refusing to run as root. Run it as your normal user; it calls sudo only where required.\n' \
    "$(basename -- "$script")" >&2
  printf 'Set BLIZL_HANDY_ALLOW_ROOT=true only in a container that has no unprivileged user.\n' >&2
  return 1
}
