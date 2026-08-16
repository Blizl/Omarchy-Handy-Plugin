#!/usr/bin/env bash

# Return codes used by voxtype_hotkey_disable.
VOXTYPE_SETTINGS_CHANGED=0
VOXTYPE_SETTINGS_ERROR=1
VOXTYPE_SETTINGS_NO_CHANGE=2

# Print: state<TAB>line-number. State is one of true, false, absent, error.
voxtype_hotkey_scan() {
  local config_file="$1"

  awk '
    function header_name(line) {
      sub(/^[[:space:]]*/, "", line)
      sub(/[[:space:]]*(#.*)?$/, "", line)
      return line
    }
    /^[[:space:]]*\[/ {
      header = header_name($0)
      if (header == "[hotkey]") {
        hotkey_sections++
        in_hotkey = 1
      } else {
        in_hotkey = 0
      }
      next
    }
    in_hotkey && /^[[:space:]]*enabled[[:space:]]*=/ {
      enabled_values++
      enabled_line = NR
      if ($0 ~ /^[[:space:]]*enabled[[:space:]]*=[[:space:]]*(true|false)([[:space:]]*#.*)?[[:space:]]*$/) {
        if ($0 ~ /^[[:space:]]*enabled[[:space:]]*=[[:space:]]*true([[:space:]]*#.*)?[[:space:]]*$/) {
          enabled_state = "true"
        } else {
          enabled_state = "false"
        }
      } else {
        malformed = 1
      }
    }
    END {
      if (hotkey_sections == 0) {
        print "absent\t0"
      } else if (hotkey_sections != 1 || enabled_values != 1 || malformed) {
        print "error\t0"
      } else {
        print enabled_state "\t" enabled_line
      }
    }
  ' "$config_file"
}

# Return success only when [hotkey] enabled is the TOML boolean true.
voxtype_hotkey_enabled() {
  local config_file="$1" scan state

  [[ -f "$config_file" ]] || return "$VOXTYPE_SETTINGS_ERROR"
  scan="$(voxtype_hotkey_scan "$config_file")" || return "$VOXTYPE_SETTINGS_ERROR"
  state="${scan%%$'\t'*}"
  [[ "$state" == true ]]
}

# Set [hotkey] enabled to false without changing unrelated file contents.
# Returns 0 when changed, 2 when no change was needed, and 1 on malformed input.
voxtype_hotkey_disable() {
  local config_file="$1" scan state line temporary

  [[ -f "$config_file" ]] || return "$VOXTYPE_SETTINGS_ERROR"
  scan="$(voxtype_hotkey_scan "$config_file")" || return "$VOXTYPE_SETTINGS_ERROR"
  state="${scan%%$'\t'*}"
  line="${scan##*$'\t'}"

  case "$state" in
    absent | false) return "$VOXTYPE_SETTINGS_NO_CHANGE" ;;
    error) return "$VOXTYPE_SETTINGS_ERROR" ;;
    true) ;;
    *) return "$VOXTYPE_SETTINGS_ERROR" ;;
  esac

  temporary="$(mktemp "${config_file}.tmp.XXXXXX")" || return "$VOXTYPE_SETTINGS_ERROR"
  if ! VOXTYPE_HOTKEY_LINE="$line" perl -pe '
    if ($. == $ENV{VOXTYPE_HOTKEY_LINE}) {
      s/^([[:space:]]*enabled[[:space:]]*=[[:space:]]*)true/${1}false/;
    }
  ' "$config_file" >"$temporary"; then
    rm -f -- "$temporary"
    return "$VOXTYPE_SETTINGS_ERROR"
  fi
  if ! chmod --reference="$config_file" "$temporary" || ! mv -- "$temporary" "$config_file"; then
    rm -f -- "$temporary"
    return "$VOXTYPE_SETTINGS_ERROR"
  fi
  return "$VOXTYPE_SETTINGS_CHANGED"
}
