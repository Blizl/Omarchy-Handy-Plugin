#!/usr/bin/env bash

HANDY_RESERVED_BINDING="${HANDY_RESERVED_BINDING:-ctrl+alt+shift+super+f24}"

handy_settings_file() {
  printf '%s\n' "${HANDY_SETTINGS_FILE:-$HOME/.local/share/com.pais.handy/settings_store.json}"
}

handy_settings_validate() {
  local settings_file="${1:-$(handy_settings_file)}"
  jq -e '(.settings.bindings.transcribe | type) == "object" and (.settings.bindings.transcribe.current_binding | type) == "string"' \
    "$settings_file" >/dev/null
}

handy_settings_binding() {
  local settings_file="${1:-$(handy_settings_file)}"
  jq -r '.settings.bindings.transcribe.current_binding' "$settings_file"
}

handy_settings_set_reserved() {
  local settings_file="${1:-$(handy_settings_file)}"
  local temporary

  [[ "$HANDY_RESERVED_BINDING" =~ ^[a-z0-9]+(\+[a-z0-9]+)+$ ]] || {
    echo "Invalid reserved Handy binding: $HANDY_RESERVED_BINDING" >&2
    return 1
  }
  handy_settings_validate "$settings_file"
  temporary="$(mktemp "${settings_file}.tmp.XXXXXX")"
  if ! jq --arg binding "$HANDY_RESERVED_BINDING" '
    .settings.bindings.transcribe.current_binding = $binding
  ' "$settings_file" >"$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  chmod --reference="$settings_file" "$temporary"
  mv -- "$temporary" "$settings_file"
}
