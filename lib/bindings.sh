#!/usr/bin/env bash

HANDY_BINDINGS_BEGIN="-- BEGIN blizl.handy managed bindings"
HANDY_BINDINGS_END="-- END blizl.handy managed bindings"

bindings_remove_managed_block() {
  local input="$1"
  local output="$2"
  awk -v begin="$HANDY_BINDINGS_BEGIN" -v end="$HANDY_BINDINGS_END" '
    $0 == begin { managed = 1; next }
    $0 == end { managed = 0; next }
    !managed { print }
  ' "$input" >"$output"
}

bindings_validate() {
  local bindings_file="$1"
  awk -v begin="$HANDY_BINDINGS_BEGIN" -v end="$HANDY_BINDINGS_END" '
    $0 == begin { if (managed) exit 1; managed = 1; next }
    $0 == end { if (!managed) exit 1; managed = 0; next }
    END { if (managed) exit 1 }
  ' "$bindings_file" || return 1
  if command -v luac >/dev/null 2>&1; then
    luac -p "$bindings_file" >/dev/null 2>&1
  fi
}

bindings_detect_voxtype_key() {
  local bindings_file="$1"
  perl -ne '
    next if /^\s*--/; $source .= $_;
    END { if ($source =~ /o\.bind\(\s*"([^"]+)"\s*,.*?voxtype.*?\)/si) { print "$1\n" } }
  ' "$bindings_file"
}

bindings_action_for_key() {
  local bindings_file="$1"
  local key="$2"
  KEY="$key" perl -ne '
    next if /^\s*--/; $source .= $_;
    END {
    my $key = quotemeta($ENV{KEY});
    if ($source =~ /o\.bind\(\s*"$key"\s*,\s*(?:"([^"]*)"|nil)\s*,\s*([^\n\)]*)/si) {
      my $description = defined($1) ? $1 : "unnamed action";
      my $command = $2 // ""; $command =~ s/^\s+|\s+$//g;
      print "$description: $command\n";
    } }
  ' "$bindings_file"
}

bindings_write_managed() {
  local bindings_file="$1"
  local key="$2"
  local previous_action="${3:-}"
  local trigger_path="$4"
  local temporary clean

  [[ "$key" =~ ^[A-Za-z0-9_+[:space:]-]+$ ]] || {
    echo "Shortcut contains unsupported characters: $key" >&2
    return 1
  }

  temporary="$(mktemp "${bindings_file}.tmp.XXXXXX")"
  clean="$(mktemp "${bindings_file}.clean.XXXXXX")"
  bindings_remove_managed_block "$bindings_file" "$clean"
  cp -- "$clean" "$temporary"
  rm -f -- "$clean"

  {
    printf '\n%s\n' "$HANDY_BINDINGS_BEGIN"
    if [[ -n "$previous_action" ]]; then
      printf '%s\n' "-- Previous action: ${previous_action//$'\n'/ }"
      printf 'hl.unbind("%s")\n\n' "$key"
    fi
    printf 'o.bind(\n  "%s",\n  "Start Handy dictation",\n  "%s press"\n)\n\n' "$key" "$trigger_path"
    printf 'o.bind(\n  "%s",\n  "Stop Handy dictation",\n  "%s release",\n  { release = true }\n)\n' "$key" "$trigger_path"
    printf '%s\n' "$HANDY_BINDINGS_END"
  } >>"$temporary"

  chmod --reference="$bindings_file" "$temporary"
  mv -- "$temporary" "$bindings_file"
}
