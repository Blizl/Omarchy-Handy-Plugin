#!/usr/bin/env bash

transaction_begin() {
  local state_root="$1"
  local stamp
  stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  TRANSACTION_DIR="$state_root/backups/$stamp"
  mkdir -p -- "$TRANSACTION_DIR/files"
  : >"$TRANSACTION_DIR/targets.tsv"
  export TRANSACTION_DIR
}

transaction_backup() {
  local target="$1"
  local relative="${target#/}"
  local destination="$TRANSACTION_DIR/files/$relative"

  if [[ -e "$target" || -L "$target" ]]; then
    mkdir -p -- "$(dirname -- "$destination")"
    cp -a --reflink=auto -- "$target" "$destination"
    printf 'present\t%s\n' "$target" >>"$TRANSACTION_DIR/targets.tsv"
  else
    printf 'absent\t%s\n' "$target" >>"$TRANSACTION_DIR/targets.tsv"
  fi
}

transaction_safe_target() {
  local target="$1" canonical
  [[ "$target" == /* ]] || return 1
  canonical="$(realpath -m -- "$target")" || return 1
  case "$canonical" in
    "$HOME/.config"/* | "$HOME/.local/share"/* | "$HOME/.local/state"/* | "$HOME/.local/bin"/*) return 0 ;;
    *) return 1 ;;
  esac
}

transaction_remove_target() {
  local target="$1"
  transaction_safe_target "$target" || {
    echo "Refusing unsafe rollback target: $target" >&2
    return 1
  }
  [[ "$target" != "$HOME" && "$target" != "$HOME/.config" && "$target" != "$HOME/.local" ]] || {
    echo "Refusing broad rollback target: $target" >&2
    return 1
  }
  if [[ -e "$target" || -L "$target" ]]; then
    rm -rf -- "$target"
  fi
}

transaction_restore() {
  local transaction_dir="${1:-$TRANSACTION_DIR}"
  local state target source

  while IFS=$'\t' read -r state target; do
    transaction_safe_target "$target" || {
      echo "Refusing unsafe rollback target: $target" >&2
      return 1
    }
    if [[ "$state" == present ]]; then
      source="$transaction_dir/files/${target#/}"
      [[ -e "$source" || -L "$source" ]] || return 1
      mkdir -p -- "$(dirname -- "$target")"
      transaction_remove_target "$target"
      cp -a --reflink=auto -- "$source" "$target"
    else
      transaction_remove_target "$target"
    fi
  done <"$transaction_dir/targets.tsv"
}
