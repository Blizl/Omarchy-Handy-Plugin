#!/usr/bin/env bash

shell_settings_file() {
  printf '%s\n' "${OMARCHY_SHELL_FILE:-$HOME/.config/omarchy/shell.json}"
}

shell_settings_install_handy_widget() {
  local shell_file="${1:-$(shell_settings_file)}"
  local temporary

  [[ -f "$shell_file" ]] || return 1
  jq -e . "$shell_file" >/dev/null 2>&1 || return 1

  temporary="$(mktemp "${shell_file}.tmp.XXXXXX")" || return 1
  if ! jq '
    def handy_defaults:
      ["ScreenRecording", "Reminder", "NightLight", "Dnd", "StayAwake"];

    def entry_id:
      if type == "string" then .
      elif type == "object" then (.id // "")
      else ""
      end;

    def without_dictation:
      if type == "array" then map(select(entry_id != "Dictation")) else . end;

    def clean_indicators:
      (if type == "object" then . else {"id": entry_id} end) as $entry
      | ($entry.items | type) as $items_type
      | ($entry.indicators | type) as $indicators_type
      | (if $items_type == "array" and ($entry.items | length) > 0 then $entry.items
         elif $indicators_type == "array" and ($entry.indicators | length) > 0 then $entry.indicators
         else handy_defaults
         end) as $effective
      | ($effective | without_dictation) as $cleaned
      | if ($cleaned | length) == 0 then empty else ($entry | .items = $cleaned | del(.indicators)) end;

    def clean_layout:
      with_entries(
        if (.value | type) == "array" then
          .value |= map(
            select(entry_id != "blizl.handy")
            | if entry_id == "omarchy.indicators" then clean_indicators else . end
          )
        else .
        end
      );

    def install_in_center:
      (if (.center | type) == "array" then .center else [] end) as $center
      | ($center | map(select(entry_id != "blizl.handy"))) as $without_handy
      | ([$without_handy[] | entry_id] | index("omarchy.clock")) as $clock_index
      | ($clock_index // ($without_handy | length)) as $insert_index
      | .center = ($without_handy[0:$insert_index] + [{"id":"blizl.handy"}] + $without_handy[$insert_index:]);

    .bar.layout = ((.bar.layout // {}) | clean_layout | install_in_center)
  ' "$shell_file" >"$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi

  if ! chmod --reference="$shell_file" "$temporary" || ! mv -- "$temporary" "$shell_file"; then
    rm -f -- "$temporary"
    return 1
  fi
}
