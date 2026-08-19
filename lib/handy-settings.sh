#!/usr/bin/env bash

handy_settings_file() {
  printf '%s\n' "${HANDY_SETTINGS_FILE:-$HOME/.local/share/com.pais.handy/settings_store.json}"
}

handy_shortcut_normalize() {
  local raw="${1:-}"
  local lower
  lower="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  printf '%s\n' "$lower"
}

handy_settings_validate() {
  local settings_file="${1:-$(handy_settings_file)}"
  jq -e '(.settings.bindings.transcribe | type) == "object" and (.settings.bindings.transcribe.current_binding | type) == "string"' \
    "$settings_file" >/dev/null
}

handy_settings_binding() {
  local settings_file="${1:-$(handy_settings_file)}"
  jq -r '.settings.bindings.transcribe.current_binding // empty' "$settings_file"
}

handy_settings_keyboard_implementation() {
  local settings_file="${1:-$(handy_settings_file)}"
  jq -r '.settings.keyboard_implementation // empty' "$settings_file"
}

handy_settings_push_to_talk() {
  local settings_file="${1:-$(handy_settings_file)}"
  # `// empty` would swallow a legitimate `false`, which is exactly the value
  # toggle mode stores, so test for the key instead of its truthiness.
  jq -r 'if (.settings | type) == "object" and (.settings | has("push_to_talk"))
         then (.settings.push_to_talk | tostring)
         else empty end' "$settings_file"
}

handy_settings_set_shortcut() {
  local settings_file shortcut
  if [[ $# -ge 2 ]]; then
    settings_file="$1"
    shortcut="$2"
  elif [[ $# -eq 1 ]]; then
    if [[ -f "$1" || "$1" =~ \.json$ ]]; then
      settings_file="$1"
      shortcut="ALT + SPACE"
    else
      settings_file="$(handy_settings_file)"
      shortcut="$1"
    fi
  else
    settings_file="$(handy_settings_file)"
    shortcut="ALT + SPACE"
  fi

  local normalized
  normalized="$(handy_shortcut_normalize "$shortcut")"
  [[ "$normalized" =~ ^[a-z0-9]+(\+[a-z0-9]+)*$ ]] || {
    echo "Invalid Handy shortcut: $shortcut" >&2
    return 1
  }

  handy_settings_validate "$settings_file"
  local temporary
  temporary="$(mktemp "${settings_file}.tmp.XXXXXX")"
  if ! jq --arg binding "$normalized" '
    .settings.push_to_talk = false |
    .settings.keyboard_implementation = "handy_keys" |
    .settings.bindings.transcribe.current_binding = $binding
  ' "$settings_file" >"$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  chmod --reference="$settings_file" "$temporary" 2>/dev/null || chmod 600 "$temporary"
  mv -- "$temporary" "$settings_file"
}

handy_settings_configure_native() {
  handy_settings_set_shortcut "$@"
}
