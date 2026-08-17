#!/usr/bin/env bash

checkpoint_state_root() {
  printf '%s\n' "${BLIZL_HANDY_STATE_DIR:-$HOME/.local/state/blizl.handy}"
}

checkpoint_root() {
  printf '%s/e2e-checkpoints\n' "$(checkpoint_state_root)"
}

checkpoint_valid_id() {
  [[ "${1:-}" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]]
}

checkpoint_safe_path() {
  local path="$1" root canonical
  root="$(checkpoint_root)"
  [[ "$path" == /* && "$path" != *"/../"* && "$path" != */.. && "$path" != *"/./"* && "$path" != */. ]] || return 1
  canonical="$(realpath -m -- "$path")" || return 1
  case "$canonical" in
    "$HOME/.config"/* | "$HOME/.local/share"/* | "$HOME/.local/state"/* | "$HOME/.local/bin"/*) ;;
    *) return 1 ;;
  esac
  [[ "$canonical" != "$root" && "$canonical" != "$root"/* ]]
}

checkpoint_paths() {
  if [[ -n "${BLIZL_HANDY_CHECKPOINT_PATHS:-}" ]]; then
    local old_ifs="$IFS" path
    local -a paths
    IFS=:
    read -ra paths <<<"$BLIZL_HANDY_CHECKPOINT_PATHS"
    IFS="$old_ifs"
    for path in "${paths[@]}"; do printf '%s\n' "$path"; done
    return
  fi
  printf '%s\n' \
    "$HOME/.config/hypr/bindings.lua" \
    "$HOME/.config/omarchy/shell.json" \
    "$HOME/.config/omarchy/plugins/vliang.indicators" \
    "$HOME/.config/omarchy/plugins/blizl.handy" \
    "$HOME/.local/bin/handy-status-follow" \
    "$HOME/.local/share/com.pais.handy/settings_store.json" \
    "$HOME/.config/autostart/Handy.desktop" \
    "$HOME/.config/systemd/user/voxtype.service" \
    "$HOME/.config/voxtype" \
    "$HOME/.local/share/voxtype" \
    "$HOME/.local/state/blizl.handy/install.json" \
    "$HOME/.local/state/blizl.handy/backups" \
    "$HOME/.local/state/blizl.handy/voxtype-recovery" \
    "$HOME/.local/state/blizl.handy/baseline-hypr-errors.txt"
}

checkpoint_type() {
  local path="$1"
  if [[ -L "$path" ]]; then
    printf 'symlink\n'
  elif [[ -f "$path" ]]; then
    printf 'file\n'
  elif [[ -d "$path" ]]; then
    printf 'directory\n'
  else
    printf 'absent\n'
  fi
}

checkpoint_hash_files() {
  local target="$1" output="$2" file
  if [[ -f "$target" && ! -L "$target" ]]; then
    sha256sum -- "$target" | awk -v path="$target" '{print path "\t" $1}' >>"$output"
  elif [[ -d "$target" && ! -L "$target" ]]; then
    while IFS= read -r -d '' file; do
      sha256sum -- "$file" | awk -v path="$file" '{print path "\t" $1}' >>"$output"
    done < <(find "$target" -type f -print0 | sort -z)
  fi
}

checkpoint_snapshot_commands() {
  local directory="$1" hashes_file="$2" package version present enabled active handy_running quickshell_running packages='[]'
  for package in handy-bin voxtype-bin wtype; do
    version=''
    present=false
    if command -v pacman >/dev/null 2>&1 && version="$(pacman -Q "$package" 2>/dev/null | awk '{print $2}')" && [[ -n "$version" ]]; then
      present=true
    fi
    packages="$(jq --arg name "$package" --arg version "$version" --argjson present "$present" '. + [{name:$name,version:$version,present:$present}]' <<<"$packages")"
  done
  printf '%s\n' "$packages" >"$directory/package-state.json"

  enabled=disabled
  active=inactive
  if command -v systemctl >/dev/null 2>&1; then
    enabled="$(timeout 5s systemctl --user is-enabled voxtype.service 2>/dev/null || printf disabled)"
    active="$(timeout 5s systemctl --user is-active voxtype.service 2>/dev/null || printf inactive)"
  fi
  jq -n --arg enabled "$enabled" --arg active "$active" '{unit:"voxtype.service",enabled:$enabled,active:$active}' >"$directory/service-state.json"

  handy_running=false
  quickshell_running=false
  command -v pgrep >/dev/null 2>&1 && pgrep -x handy >/dev/null 2>&1 && handy_running=true
  command -v pgrep >/dev/null 2>&1 && pgrep -x quickshell >/dev/null 2>&1 && quickshell_running=true
  jq -n --argjson handy "$handy_running" --argjson quickshell "$quickshell_running" '{handy:$handy,quickshell:$quickshell}' >"$directory/process-state.json"
}

checkpoint_has_space() {
  local root="$1" required=10240 available path size
  while IFS= read -r path; do
    [[ -e "$path" || -L "$path" ]] || continue
    size="$(du -sk -- "$path" 2>/dev/null | awk '{print $1}')"
    required=$((required + size))
  done < <(checkpoint_paths)
  available="$(df -Pk -- "$root" | awk 'NR == 2 { print $4 }')"
  [[ "$available" =~ ^[0-9]+$ && "$available" -ge "$required" ]]
}

checkpoint_create() {
  local root id directory path type relative archive entries_file hashes_file
  root="$(checkpoint_root)"
  id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  directory="$root/$id"
  entries_file="$directory/entries.jsonl"
  hashes_file="$directory/hashes.txt"
  mkdir -p -- "$root"
  checkpoint_has_space "$root" || {
    echo "Insufficient disk space for checkpoint" >&2
    return 1
  }
  mkdir -p -- "$directory/files"
  : >"$entries_file"
  : >"$hashes_file"

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    checkpoint_safe_path "$path" || {
      rm -rf -- "$directory"
      echo "Unsafe checkpoint path: $path" >&2
      return 1
    }
    type="$(checkpoint_type "$path")"
    relative="${path#/}"
    archive="files/$relative"
    if [[ "$type" != absent ]]; then
      mkdir -p -- "$directory/files/$(dirname -- "$relative")"
      cp -a --reflink=auto -- "$path" "$directory/files/$relative"
      checkpoint_hash_files "$directory/$archive" "$hashes_file"
    fi
    jq -cn --arg path "$path" --arg type "$type" --arg archive "$archive" \
      '{path:$path, existed:($type != "absent"), type:$type, archive:$archive}' >>"$entries_file"
  done < <(checkpoint_paths)

  jq -s '.' "$entries_file" >"$directory/manifest.json"
  rm -f -- "$entries_file"
  checkpoint_snapshot_commands "$directory" "$hashes_file" || {
    rm -rf -- "$directory"
    return 1
  }
  printf '%s\n' "$id"
}

checkpoint_hashes_verify() {
  local directory="$1" path expected actual
  [[ -f "$directory/hashes.txt" ]] || return 1
  while IFS=$'\t' read -r path expected; do
    [[ -n "$path" ]] || continue
    [[ -f "$path" ]] || return 1
    actual="$(sha256sum -- "$path" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || return 1
  done <"$directory/hashes.txt"
}

checkpoint_verify() {
  local id="$1" directory path existed archive
  directory="$(checkpoint_root)/$id"
  checkpoint_valid_id "$id" || return 1
  [[ -f "$directory/manifest.json" && -f "$directory/hashes.txt" ]] || return 1
  [[ -f "$directory/package-state.json" && -f "$directory/service-state.json" && -f "$directory/process-state.json" ]] || return 1
  jq -e 'type == "array" and all(.[]; (.name|type) == "string" and (.present|type) == "boolean")' "$directory/package-state.json" >/dev/null || return 1
  jq -e '(.unit == "voxtype.service") and (.enabled|type == "string") and (.active|type == "string")' "$directory/service-state.json" >/dev/null || return 1
  jq -e '(.handy|type == "boolean") and (.quickshell|type == "boolean")' "$directory/process-state.json" >/dev/null || return 1
  jq -e 'type == "array"' "$directory/manifest.json" >/dev/null || return 1
  jq -e 'all(.[]; (.archive|startswith("files/")) and ((.archive|contains(".."))|not))' "$directory/manifest.json" >/dev/null || return 1
  while IFS=$'\t' read -r path existed archive; do
    : "$path"
    if [[ "$existed" == true ]]; then
      [[ -e "$directory/$archive" || -L "$directory/$archive" ]] || return 1
    fi
  done < <(jq -r '.[] | [.path, (.existed|tostring), .archive] | @tsv' "$directory/manifest.json")
  while IFS= read -r path; do
    checkpoint_safe_path "$path" || return 1
  done < <(jq -r '.[].path' "$directory/manifest.json")
  checkpoint_hashes_verify "$directory"
}

checkpoint_restore() {
  local id="$1" directory path existed archive source
  directory="$(checkpoint_root)/$id"
  checkpoint_verify "$id" || {
    echo "Checkpoint verification failed: $id" >&2
    return 1
  }
  while IFS=$'\t' read -r path existed archive; do
    checkpoint_safe_path "$path" || return 1
    if [[ "$existed" == true ]]; then
      source="$directory/$archive"
      [[ -e "$source" || -L "$source" ]] || return 1
      mkdir -p -- "$(dirname -- "$path")"
      rm -rf -- "$path"
      cp -a --reflink=auto -- "$source" "$path"
    else
      rm -rf -- "$path"
    fi
  done < <(jq -r '.[] | [.path, (.existed|tostring), .archive] | @tsv' "$directory/manifest.json")
  checkpoint_restore_packages "$directory"
  checkpoint_restore_service "$directory"
  checkpoint_restore_processes "$directory"
  checkpoint_restore_hyprland "$directory"
}

checkpoint_restore_service() {
  local directory="$1" enabled active
  [[ "${BLIZL_HANDY_SKIP_RUNTIME_RESTORE:-false}" == true ]] && return 0
  command -v systemctl >/dev/null 2>&1 || {
    [[ "$(jq -r '.enabled' "$directory/service-state.json")" == disabled && "$(jq -r '.active' "$directory/service-state.json")" == inactive ]]
    return
  }
  enabled="$(jq -r '.enabled' "$directory/service-state.json")"
  active="$(jq -r '.active' "$directory/service-state.json")"
  if [[ "$enabled" == enabled ]]; then
    if [[ "$active" == active ]]; then
      timeout 5s systemctl --user enable --now voxtype.service >/dev/null 2>&1
    else
      timeout 5s systemctl --user enable voxtype.service >/dev/null 2>&1
      timeout 5s systemctl --user stop voxtype.service >/dev/null 2>&1
    fi
  else
    timeout 5s systemctl --user disable --now voxtype.service >/dev/null 2>&1
  fi
  timeout 5s systemctl --user daemon-reload >/dev/null 2>&1
}

checkpoint_restore_packages() {
  local directory="$1" name expected_version expected_present current_version add_bin drop_bin
  [[ "${BLIZL_HANDY_SKIP_RUNTIME_RESTORE:-false}" == true ]] && return 0
  command -v pacman >/dev/null 2>&1 || {
    jq -e 'any(.[]; .present)' "$directory/package-state.json" >/dev/null && return 1
    return 0
  }
  add_bin="${BLIZL_HANDY_PKG_ADD_BIN:-}"
  drop_bin="${BLIZL_HANDY_PKG_DROP_BIN:-}"
  while IFS=$'\t' read -r name expected_version expected_present; do
    current_version="$(pacman -Q "$name" 2>/dev/null | awk '{print $2}')" || current_version=''
    if [[ "$expected_present" == true ]]; then
      [[ "$current_version" == "$expected_version" ]] && continue
      if [[ -n "$add_bin" ]]; then
        "$add_bin" "$name"
      elif command -v omarchy >/dev/null 2>&1; then
        omarchy pkg add "$name"
      else
        echo "Cannot restore package $name: omarchy command not found" >&2
        return 1
      fi
    elif [[ -n "$current_version" ]]; then
      if [[ -n "$drop_bin" ]]; then
        "$drop_bin" "$name"
      elif command -v omarchy >/dev/null 2>&1; then
        omarchy pkg drop "$name"
      else
        echo "Cannot drop package $name: omarchy command not found" >&2
        return 1
      fi
    fi
  done < <(jq -r '.[] | [.name, (.version // ""), (.present|tostring)] | @tsv' "$directory/package-state.json")
}

checkpoint_restore_processes() {
  local directory="$1" handy_baseline quickshell_baseline
  [[ "${BLIZL_HANDY_SKIP_RUNTIME_RESTORE:-false}" == true ]] && return 0
  handy_baseline="$(jq -r '.handy' "$directory/process-state.json")"
  quickshell_baseline="$(jq -r '.quickshell' "$directory/process-state.json")"
  command -v pgrep >/dev/null 2>&1 || {
    [[ "$handy_baseline" == false && "$quickshell_baseline" == false ]]
    return
  }
  if [[ "$handy_baseline" == true ]] && ! pgrep -x handy >/dev/null 2>&1; then
    command -v handy >/dev/null 2>&1 || return 1
    handy --start-hidden >/dev/null 2>&1 &
  elif [[ "$handy_baseline" == false ]] && pgrep -x handy >/dev/null 2>&1; then
    pkill -x handy
  fi
  if [[ "$quickshell_baseline" == true ]]; then
    command -v omarchy >/dev/null 2>&1 || return 1
    omarchy restart shell
  elif [[ "$quickshell_baseline" == false ]] && pgrep -x quickshell >/dev/null 2>&1; then
    pkill -x quickshell
  fi
}

checkpoint_expected_hypr_errors() {
  local directory="$1" archive errors_path
  errors_path="${BLIZL_HANDY_BASELINE_ERRORS_FILE:-$(checkpoint_state_root)/baseline-hypr-errors.txt}"
  archive="$(jq -r --arg path "$errors_path" '.[] | select(.path == $path) | .archive' "$directory/manifest.json" 2>/dev/null || :)"
  if [[ -n "$archive" && -f "$directory/$archive" ]]; then
    cat "$directory/$archive"
  else
    printf '\n'
  fi
}

checkpoint_verify_hyprland() {
  local directory="$1" current expected
  [[ "${BLIZL_HANDY_SKIP_RUNTIME_RESTORE:-false}" == true ]] && return 0
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 0
  command -v hyprctl >/dev/null 2>&1 || return 0
  current="$(hyprctl configerrors)"
  expected="$(checkpoint_expected_hypr_errors "$directory")"
  [[ "$current" == "$expected" ]]
}

checkpoint_restore_hyprland() {
  local directory="$1"
  [[ "${BLIZL_HANDY_SKIP_RUNTIME_RESTORE:-false}" == true ]] && return 0
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 0
  command -v hyprctl >/dev/null 2>&1 || return 1
  hyprctl reload >/dev/null
  checkpoint_verify_hyprland "$directory"
}

checkpoint_tree_fingerprint() {
  local target="$1" output="$2" file relative
  if [[ -f "$target" && ! -L "$target" ]]; then
    printf '.\t%s\n' "$(sha256sum -- "$target" | awk '{print $1}')" >"$output"
  elif [[ -L "$target" ]]; then
    printf '.\t%s\n' "$(readlink -- "$target")" >"$output"
  elif [[ -d "$target" ]]; then
    : >"$output"
    while IFS= read -r -d '' file; do
      relative="${file#"$target"/}"
      printf '%s\t%s\n' "$relative" "$(sha256sum -- "$file" | awk '{print $1}')" >>"$output"
    done < <(find "$target" -type f -print0 | sort -z)
  else
    printf 'absent\n' >"$output"
  fi
}

checkpoint_verify_current_files() {
  local directory="$1" path existed archive type temporary expected actual failed=false
  temporary="$(mktemp -d)"
  while IFS=$'\t' read -r path existed archive; do
    type="$(checkpoint_type "$path")"
    if [[ "$existed" == true ]]; then
      if [[ "$type" == absent ]]; then
        failed=true
        break
      fi
      expected="$temporary/expected"
      actual="$temporary/actual"
      checkpoint_tree_fingerprint "$directory/$archive" "$expected"
      checkpoint_tree_fingerprint "$path" "$actual"
      if ! cmp -s "$expected" "$actual"; then
        failed=true
        break
      fi
    else
      if [[ "$type" != absent ]]; then
        failed=true
        break
      fi
    fi
  done < <(jq -r '.[] | [.path, (.existed|tostring), .archive] | @tsv' "$directory/manifest.json")
  rm -rf -- "$temporary"
  [[ "$failed" == false ]]
}

checkpoint_verify_current_runtime() {
  local directory="$1" check_process="${2:-true}" name expected_version expected_present current_version enabled active handy quickshell
  [[ "${BLIZL_HANDY_SKIP_RUNTIME_RESTORE:-false}" == true ]] && return 0
  if jq -e 'any(.[]; .present)' "$directory/package-state.json" >/dev/null; then
    command -v pacman >/dev/null 2>&1 || return 1
  fi
  while IFS=$'\t' read -r name expected_version expected_present; do
    current_version="$(pacman -Q "$name" 2>/dev/null | awk '{print $2}')" || current_version=''
    if [[ "$expected_present" == true ]]; then
      [[ "$current_version" == "$expected_version" ]] || return 1
    else
      [[ -z "$current_version" ]] || return 1
    fi
  done < <(jq -r '.[] | [.name, (.version // ""), (.present|tostring)] | @tsv' "$directory/package-state.json")
  command -v systemctl >/dev/null 2>&1 || return 1
  enabled="$(timeout 5s systemctl --user is-enabled voxtype.service 2>/dev/null || printf disabled)"
  active="$(timeout 5s systemctl --user is-active voxtype.service 2>/dev/null || printf inactive)"
  [[ "$enabled" == "$(jq -r '.enabled' "$directory/service-state.json")" ]] || return 1
  [[ "$active" == "$(jq -r '.active' "$directory/service-state.json")" ]] || return 1
  if [[ "$check_process" == true ]]; then
    handy=false
    quickshell=false
    pgrep -x handy >/dev/null 2>&1 && handy=true
    pgrep -x quickshell >/dev/null 2>&1 && quickshell=true
    [[ "$handy" == "$(jq -r '.handy' "$directory/process-state.json")" ]] || return 1
    [[ "$quickshell" == "$(jq -r '.quickshell' "$directory/process-state.json")" ]]
  fi
}

checkpoint_discard() {
  local id="$1" directory
  directory="$(checkpoint_root)/$id"
  checkpoint_valid_id "$id" || return 1
  [[ -d "$directory" ]] || return 1
  rm -rf -- "$directory"
}

checkpoint_verify_current() {
  local id="$1" expected_state="${2:-baseline}" directory
  directory="$(checkpoint_root)/$id"
  checkpoint_verify "$id" || return 1
  case "$expected_state" in
    baseline | --expected-baseline)
      checkpoint_verify_current_files "$directory"
      checkpoint_verify_current_runtime "$directory"
      checkpoint_verify_hyprland "$directory"
      ;;
    plugin | --expected-plugin-state)
      [[ -e "$HOME/.config/omarchy/plugins/blizl.handy" ]] || return 1
      checkpoint_verify_current_runtime "$directory" false
      checkpoint_verify_hyprland "$directory"
      ;;
    *) return 1 ;;
  esac
}
