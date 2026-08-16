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

bindings_normalize_shortcut() {
  local shortcut="${1^^}" compact part key result='' canonical
  local -a parts=()
  local has_ctrl=false has_alt=false has_shift=false has_super=false

  compact="${shortcut// /}"
  IFS='+' read -r -a parts <<<"$compact"
  ((${#parts[@]} > 0)) || return 1
  key="${parts[${#parts[@]} - 1]}"
  [[ -n "$key" ]] || return 1
  unset "parts[$((${#parts[@]} - 1))]"

  case "$key" in
    ENTER) key="RETURN" ;;
    ESC) key="ESCAPE" ;;
    *) ;;
  esac

  for part in "${parts[@]}"; do
    case "$part" in
      LEFTCTRL | RIGHTCTRL | CTRL | CONTROL | MOD3) has_ctrl=true ;;
      LEFTALT | RIGHTALT | ALT | MOD1) has_alt=true ;;
      LEFTSHIFT | RIGHTSHIFT | SHIFT) has_shift=true ;;
      LEFTSUPER | RIGHTSUPER | LEFTMETA | RIGHTMETA | SUPER | META | MOD4 | WIN | LOGO) has_super=true ;;
      '') ;;
      *) return 1 ;;
    esac
  done

  for canonical in CTRL ALT SHIFT SUPER; do
    case "$canonical" in
      CTRL) [[ "$has_ctrl" == true ]] || continue ;;
      ALT) [[ "$has_alt" == true ]] || continue ;;
      SHIFT) [[ "$has_shift" == true ]] || continue ;;
      SUPER) [[ "$has_super" == true ]] || continue ;;
    esac
    [[ -n "$result" ]] && result+=" + "
    result+="$canonical"
  done
  [[ -n "$result" ]] && result+=" + "
  printf '%s\n' "${result}${key}"
}

bindings_modifier_release_keys() {
  local shortcut="$1" part key
  local -a parts=() release_keys=()
  local has_alt=false has_super=false has_ctrl=false has_shift=false

  IFS='+' read -r -a parts <<<"$shortcut"
  ((${#parts[@]} > 1)) || return 0
  unset 'parts[${#parts[@]}-1]'

  for part in "${parts[@]}"; do
    part="${part//[[:space:]]/}"
    part="${part^^}"
    case "$part" in
      ALT | LEFTALT | RIGHTALT | MOD1 | ALT_L | ALT_R)
        if [[ "$has_alt" == false ]]; then
          has_alt=true
          release_keys+=("Alt_L" "Alt_R")
        fi
        ;;
      SUPER | LEFTSUPER | RIGHTSUPER | META | LEFTMETA | RIGHTMETA | MOD4 | WIN | LOGO | SUPER_L | SUPER_R)
        if [[ "$has_super" == false ]]; then
          has_super=true
          release_keys+=("Super_L" "Super_R")
        fi
        ;;
      CTRL | CONTROL | LEFTCTRL | RIGHTCTRL | MOD3 | CTRL_L | CTRL_R | CONTROL_L | CONTROL_R)
        if [[ "$has_ctrl" == false ]]; then
          has_ctrl=true
          release_keys+=("Control_L" "Control_R")
        fi
        ;;
      SHIFT | LEFTSHIFT | RIGHTSHIFT | SHIFT_L | SHIFT_R)
        if [[ "$has_shift" == false ]]; then
          has_shift=true
          release_keys+=("Shift_L" "Shift_R")
        fi
        ;;
    esac
  done

  for key in "${release_keys[@]}"; do
    printf '%s\n' "$key"
  done
}

bindings_write_managed() {
  local bindings_file="$1"
  local key="$2"
  local previous_action="${3:-}"
  local trigger_path="$4"
  local voxtype_keys="${5:-$key}" managed_key mod_release_key selected_unbound=false temporary clean normalized_key
  local -a modifier_releases=()

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

  normalized_key="$(bindings_normalize_shortcut "$key" 2>/dev/null || printf '%s' "$key")"

  while IFS= read -r mod_release_key; do
    [[ -n "$mod_release_key" ]] || continue
    modifier_releases+=("$mod_release_key")
  done < <(bindings_modifier_release_keys "$normalized_key")

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
    local normalized_unbound=false
    while IFS= read -r managed_key; do
      [[ -n "$managed_key" ]] || continue
      [[ "$managed_key" == "$key" ]] && selected_unbound=true
      [[ "$managed_key" == "$normalized_key" ]] && normalized_unbound=true
      printf 'hl.unbind("%s")\n' "$managed_key"
    done <<<"$voxtype_keys"
    [[ "$selected_unbound" == true ]] || printf 'hl.unbind("%s")\n' "$key"
    if [[ "$normalized_unbound" != true && "$normalized_key" != "$key" ]]; then
      printf 'hl.unbind("%s")\n' "$normalized_key"
    fi
    printf '\n'
    printf 'o.bind(\n  "%s",\n  "Start Handy dictation",\n  "%s press"\n)\n\n' "$normalized_key" "$trigger_path"
    printf 'o.bind(\n  "%s",\n  "Stop Handy dictation",\n  "%s release",\n  { release = true }\n)\n' "$normalized_key" "$trigger_path"
    if ((${#modifier_releases[@]} > 0)); then
      printf '\n'
      printf '%s\n' "-- Releasing either the chord or individual modifier key(s) stops dictation,"
      printf '%s\n' "-- ensuring push-to-talk ends even if the modifier is released before the base key."
      for mod_release_key in "${modifier_releases[@]}"; do
        [[ -n "$mod_release_key" ]] || continue
        printf 'o.bind(\n  "%s",\n  "Stop Handy dictation",\n  "%s release",\n  { release = true }\n)\n' "$mod_release_key" "$trigger_path"
      done
    fi
    printf '%s\n' "$HANDY_BINDINGS_END"
  } >>"$temporary"

  chmod --reference="$bindings_file" "$temporary"
  mv -- "$temporary" "$bindings_file"
}
