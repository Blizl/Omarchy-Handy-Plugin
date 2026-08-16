#!/usr/bin/env bash

HANDY_BINDINGS_BEGIN="-- BEGIN blizl.handy managed bindings"
HANDY_BINDINGS_END="-- END blizl.handy managed bindings"

bindings_remove_managed_block() {
  local input="$1"
  local output="$2"
  awk -v begin="$HANDY_BINDINGS_BEGIN" -v end="$HANDY_BINDINGS_END" '
    { lines[NR] = $0 }
    END {
      for (line = 1; line <= NR; line++) {
        if (lines[line] == begin) {
          if (out_count > 0 && output[out_count] == "") out_count--
          managed = 1
          continue
        }
        if (lines[line] == end) { managed = 0; continue }
        if (!managed) output[++out_count] = lines[line]
      }
      for (line = 1; line <= out_count; line++) print output[line]
    }
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
  local bindings_file candidate key score best_key='' best_score=0

  # Accept the user bindings first and an optional stock binding file second.
  # A push-to-talk start action is more specific than a toggle action, so a
  # stock start binding still wins when the user file only contains a toggle.
  for bindings_file in "$@"; do
    [[ -f "$bindings_file" ]] || continue
    candidate="$(perl -0777 -ne '
      my $source = $_;
      $source =~ s/--[^\n]*//g;
      my ($best_key, $best_score) = ("", 0);
      while ($source =~ /o\.bind\(\s*"([^"]+)"\s*,\s*(?:"[^"]*"|nil)\s*,\s*(?:"([^"]*)"|nil)/g) {
        my ($key, $command) = ($1, $2 // "");
        next unless $command =~ /\bvoxtype\b/i;
        my $score = $command =~ /\bvoxtype\s+record\s+start\b/i ? 2 :
                    $command =~ /\bvoxtype\s+record\s+toggle\b/i ? 1 :
                    $command =~ /\bvoxtype\s+record\s+stop\b/i ? 0 : 1;
        if ($score > $best_score) {
          ($best_key, $best_score) = ($key, $score);
        }
      }
      print "$best_key\t$best_score\n" if $best_score;
    ' "$bindings_file")"
    [[ -n "$candidate" ]] || continue
    key="${candidate%%$'\t'*}"
    score="${candidate##*$'\t'}"
    if ((score > best_score)); then
      best_key="$key"
      best_score="$score"
    fi
  done
  if [[ -n "$best_key" ]]; then
    printf '%s\n' "$best_key"
  fi
}

bindings_detect_voxtype_keys() {
  local bindings_file="$1"
  shift
  for bindings_file in "$bindings_file" "$@"; do
    [[ -f "$bindings_file" ]] || continue
    perl -0777 -ne '
      my $source = $_;
      $source =~ s/--[^\n]*//g;
      while ($source =~ /o\.bind\(\s*"([^"]+)"\s*,\s*(?:"[^"]*"|nil)\s*,\s*(?:"([^"]*)"|nil)/g) {
        my ($key, $command) = ($1, $2 // "");
        print "$key\n" if $command =~ /\bvoxtype\b/i;
      }
    ' "$bindings_file"
  done | sort -u
}

bindings_action_for_key() {
  local bindings_file="$1"
  local key="$2"
  [[ -f "$bindings_file" ]] || return 0
  BEGIN_MARKER="$HANDY_BINDINGS_BEGIN" END_MARKER="$HANDY_BINDINGS_END" KEY="$key" perl -ne '
    if ($_ eq "$ENV{BEGIN_MARKER}\n") { $managed = 1; next }
    if ($_ eq "$ENV{END_MARKER}\n") { $managed = 0; next }
    next if $managed || /^\s*--/; $source .= $_;
    END {
    my $key = quotemeta($ENV{KEY});
    if ($source =~ /o\.bind\(\s*"$key"\s*,\s*(?:"([^"]*)"|nil)\s*,\s*(?:"([^"]*)"|([^\n\)]*))/si) {
      my $description = defined($1) ? $1 : "unnamed action";
      my $command = defined($2) ? $2 : ($3 // "");
      $command =~ s/^\s+|\s+$//g;
      print "$description: $command\n";
    } }
  ' "$bindings_file"
}

bindings_write_managed() {
  local bindings_file="$1"
  local key="$2"
  local previous_action="${3:-}"
  local trigger_path="${4:-}"
  local voxtype_keys="${5:-$key}" managed_key selected_unbound=false temporary clean

  [[ "$key" =~ ^[A-Za-z0-9_+[:space:]-]+$ ]] || {
    echo "Shortcut contains unsupported characters: $key" >&2
    return 1
  }
  while IFS= read -r managed_key; do
    [[ -n "$managed_key" ]] || continue
    [[ "$managed_key" =~ ^[A-Za-z0-9_+[:space:]-]+$ ]] || {
      echo "Shortcut contains unsupported characters: $managed_key" >&2
      return 1
    }
  done <<<"$voxtype_keys"

  temporary="$(mktemp "${bindings_file}.tmp.XXXXXX")"
  clean="$(mktemp "${bindings_file}.clean.XXXXXX")"
  bindings_remove_managed_block "$bindings_file" "$clean"
  cp -- "$clean" "$temporary"
  rm -f -- "$clean"

  {
    printf '\n%s\n' "$HANDY_BINDINGS_BEGIN"
    if [[ -n "$previous_action" ]]; then
      printf '%s\n' "-- Previous action: ${previous_action//$'\n'/ }"
    fi
    printf '%s\n' "-- Dictation push-to-talk is $key via Handy's native evdev hotkey (handy_keys)."
    while IFS= read -r managed_key; do
      [[ -n "$managed_key" ]] || continue
      [[ "$managed_key" == "$key" ]] && selected_unbound=true
      printf 'hl.unbind("%s")\n' "$managed_key"
    done <<<"$voxtype_keys"
    [[ "$selected_unbound" == true ]] || printf 'hl.unbind("%s")\n' "$key"
    printf '%s\n' "$HANDY_BINDINGS_END"
  } >>"$temporary"

  chmod --reference="$bindings_file" "$temporary" 2>/dev/null || chmod 644 "$temporary"
  mv -- "$temporary" "$bindings_file"
}
