#!/usr/bin/env bash

# blizl.handy no longer writes to bindings.lua. These markers and the block
# remover exist only to recognise and clean up the managed block that versions
# up to 1.1.0 inserted, so an upgrade or a reset still leaves the file tidy.
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
  # A VoxType start action names a more specific key than a toggle action, so a
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

# Print "<line number><TAB><source line>" for the first o.bind on KEY outside a
# managed block. Used only to make the conflict message actionable, so a binding
# split across lines simply yields nothing and the caller omits the location.
bindings_locate_key() {
  local bindings_file="$1"
  local key="$2"
  [[ -f "$bindings_file" ]] || return 1
  BEGIN_MARKER="$HANDY_BINDINGS_BEGIN" END_MARKER="$HANDY_BINDINGS_END" KEY="$key" perl -ne '
    if ($_ eq "$ENV{BEGIN_MARKER}\n") { $managed = 1; next }
    if ($_ eq "$ENV{END_MARKER}\n") { $managed = 0; next }
    next if $managed || /^\s*--/;
    my $key = quotemeta($ENV{KEY});
    if (/o\.bind\(\s*"$key"\s*,/i) { print "$.\t$_"; exit 0 }
  ' "$bindings_file"
}

# Print every key bound with o.bind outside a managed block, one per line, in
# the file's own spelling. Callers normalize before comparing, because Omarchy
# accepts "ALT+ENTER" and "ALT + ENTER" for the same chord.
bindings_all_keys() {
  local bindings_file="$1"
  [[ -f "$bindings_file" ]] || return 0
  BEGIN_MARKER="$HANDY_BINDINGS_BEGIN" END_MARKER="$HANDY_BINDINGS_END" perl -ne '
    if ($_ eq "$ENV{BEGIN_MARKER}\n") { $managed = 1; next }
    if ($_ eq "$ENV{END_MARKER}\n") { $managed = 0; next }
    next if $managed || /^\s*--/;
    while (/o\.bind\(\s*"([^"]+)"/g) { print "$1\n" }
  ' "$bindings_file"
}
