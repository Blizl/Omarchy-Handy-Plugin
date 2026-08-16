#!/usr/bin/env bash

microphone_inspect() {
  local wpctl_bin="${WPCTL_BIN:-wpctl}"
  "$wpctl_bin" inspect @DEFAULT_AUDIO_SOURCE@ 2>/dev/null
}

microphone_is_available() {
  local inspected

  inspected="$(microphone_inspect)" || return 1
  grep -q 'media.class = "Audio/Source"' <<<"$inspected" || return 1
  grep -Eq 'node.name = "(auto_null|[^\"]*\.monitor)"' <<<"$inspected" && return 1
  return 0
}

notify_missing_microphone() {
  local notify_bin="${OMARCHY_NOTIFICATION_BIN:-omarchy}"
  "$notify_bin" notification send -u normal -g "󰍭" \
    "Microphone not detected" \
    "Connect or select an input device, then try voice typing again."
}

notify_handy_failure() {
  local notify_bin="${OMARCHY_NOTIFICATION_BIN:-omarchy}"
  "$notify_bin" notification send -u critical -g "󰍭" \
    "Handy could not start dictation" \
    "Open Handy and confirm that a speech model is installed."
}

notify_stop_failure() {
  local notify_bin="${OMARCHY_NOTIFICATION_BIN:-omarchy}"
  "$notify_bin" notification send -u critical -g "󰍭" \
    "Handy could not finish dictation" \
    "The recording was cancelled to avoid an accidental toggle."
}
