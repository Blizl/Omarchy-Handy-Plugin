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

# Print the native VoxType hotkey in the same readable form used by Omarchy
# bindings, for example: ALT + SPACE. Return an error when the key cannot be
# read safely; setup must not guess about a possible conflict.
voxtype_hotkey_shortcut() {
  local config_file="$1" parsed key modifiers shortcut normalized

  [[ -f "$config_file" ]] || return "$VOXTYPE_SETTINGS_ERROR"
  parsed="$(awk '
    function quoted_value(line) {
      sub(/^[^=]*=[[:space:]]*"/, "", line)
      sub(/".*$/, "", line)
      return line
    }
    function array_value(line) {
      sub(/^[^=]*=[[:space:]]*\[/, "", line)
      sub(/\].*$/, "", line)
      gsub(/[[:space:]" ]/, "", line)
      return line
    }
    /^[[:space:]]*\[/ {
      header = $0
      sub(/^[[:space:]]*/, "", header)
      sub(/[[:space:]]*(#.*)?$/, "", header)
      in_hotkey = header == "[hotkey]"
      if (in_hotkey) hotkey_sections++
      next
    }
    in_hotkey && /^[[:space:]]*key[[:space:]]*=/ {
      key_values++
      if ($0 !~ /^[[:space:]]*key[[:space:]]*=[[:space:]]*"[^"]+"[[:space:]]*(#.*)?$/) malformed = 1
      key = quoted_value($0)
      next
    }
    in_hotkey && /^[[:space:]]*modifiers[[:space:]]*=/ {
      modifier_values++
      if ($0 !~ /^[[:space:]]*modifiers[[:space:]]*=[[:space:]]*\[[[:space:]]*("[^"]+"[[:space:]]*(,[[:space:]]*"[^"]+"[[:space:]]*)*)?\][[:space:]]*(#.*)?$/) malformed = 1
      modifiers = array_value($0)
      next
    }
    END {
      if (hotkey_sections != 1 || key_values != 1 || key == "" || modifier_values > 1 || malformed) {
        exit 1
      }
      print key "\t" modifiers
    }
  ' "$config_file")" || return "$VOXTYPE_SETTINGS_ERROR"

  key="${parsed%%$'\t'*}"
  modifiers="${parsed#*$'\t'}"
  shortcut="${modifiers//,/+}"
  [[ -n "$shortcut" ]] && shortcut+='+'
  normalized="$(voxtype_shortcut_normalize "${shortcut}${key}")" || return "$VOXTYPE_SETTINGS_ERROR"
  printf '%s\n' "${normalized//+/ + }"
}

# Canonicalize a shortcut so modifier order and spacing do not hide a match.
voxtype_shortcut_normalize() {
  local shortcut="${1^^}" compact part key result='' canonical
  local -a parts=() unknown_modifiers=()
  local has_ctrl=false has_alt=false has_shift=false has_super=false

  compact="${shortcut// /}"
  IFS='+' read -r -a parts <<<"$compact"
  ((${#parts[@]} > 0)) || return "$VOXTYPE_SETTINGS_ERROR"
  key="${parts[${#parts[@]} - 1]}"
  [[ -n "$key" ]] || return "$VOXTYPE_SETTINGS_ERROR"
  unset "parts[$((${#parts[@]} - 1))]"
  for part in "${parts[@]}"; do
    case "$part" in
      LEFTCTRL | RIGHTCTRL | CTRL) has_ctrl=true ;;
      LEFTALT | RIGHTALT | ALT) has_alt=true ;;
      LEFTSHIFT | RIGHTSHIFT | SHIFT) has_shift=true ;;
      LEFTSUPER | RIGHTSUPER | LEFTMETA | RIGHTMETA | SUPER | META) has_super=true ;;
      '') ;;
      *) unknown_modifiers+=("$part") ;;
    esac
  done
  for canonical in CTRL ALT SHIFT SUPER; do
    case "$canonical" in
      CTRL) [[ "$has_ctrl" == true ]] || continue ;;
      ALT) [[ "$has_alt" == true ]] || continue ;;
      SHIFT) [[ "$has_shift" == true ]] || continue ;;
      SUPER) [[ "$has_super" == true ]] || continue ;;
    esac
    [[ -n "$result" ]] && result+="+"
    result+="$canonical"
  done
  for canonical in "${unknown_modifiers[@]}"; do
    [[ -n "$result" ]] && result+="+"
    result+="$canonical"
  done
  [[ -n "$result" ]] && result+="+"
  printf '%s\n' "${result}${key^^}"
}

voxtype_shortcuts_equal() {
  [[ "$(voxtype_shortcut_normalize "$1")" == "$(voxtype_shortcut_normalize "$2")" ]]
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
