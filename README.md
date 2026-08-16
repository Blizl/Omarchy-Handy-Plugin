# Handy Dictation for Omarchy Quattro

`blizl.handy` is a Quattro-native bar widget and push-to-talk integration for
[Handy](https://github.com/cjpais/Handy). It keeps a microphone glyph visible,
shows capture state directly from PipeWire, and prevents a key release from
starting Handy when its matching key press was rejected.

## Install

```bash
omarchy plugin add https://github.com/Blizl/Omarchy-Handy-Plugin.git --enable \
  && ~/.config/omarchy/plugins/blizl.handy/bin/setup
```

Setup opens Handy's official onboarding for model selection. It then asks which
push-to-talk shortcut to own, moves Handy's internal shortcut to a reserved
chord so both layers cannot fire, installs press/release Hyprland bindings, and
runs a real dictation test. VoxType removal is never the default and is offered
only after that test succeeds.

Supported shortcut choices are a detected VoxType shortcut, `ALT + SPACE`, or a
custom Omarchy shortcut. Replacing a non-VoxType action requires confirmation.

## Widget behavior

The widget reads Quickshell's PipeWire objects; it does not tail logs or keep a
`pactl subscribe` process alive. States use this precedence:

1. microphone missing
2. microphone muted
3. Handy recording
4. another application capturing audio
5. microphone available

Left-click opens Handy. Middle-click opens Omarchy's audio panel. Clicking while
no default microphone exists sends a notification instead.

## Remove the integration

Run the plugin's uninstaller before removing its checkout:

```bash
~/.config/omarchy/plugins/blizl.handy/bin/uninstall
omarchy plugin remove blizl.handy
```

The uninstaller restores the previous Hyprland bindings, Handy shortcut, and
autostart file. It does not remove Handy, downloaded models, or VoxType.

## Safe end-to-end testing

Live testing must begin with a verified checkpoint:

```bash
bin/e2e-checkpoint create
bin/e2e-checkpoint verify CHECKPOINT_ID
```

The command prints the checkpoint ID and its manual recovery command. The E2E
runner restores automatically on errors, interrupts, and failed assertions:

```bash
BLIZL_HANDY_BASELINE_TEST=passed \
BLIZL_HANDY_BASELINE_INDICATOR=passed \
tests-e2e/run
```

Set those confirmations only after manually proving the existing Alt+Space
dictation and microphone indicator. The runner records baseline Hyprland errors
but does not start checkpointed live scenarios unless
`BLIZL_HANDY_E2E_LIVE=yes` is also set. Its checked-in scenarios validate the
plugin and runtime prerequisites; microphone plug/unplug, shell restart, login,
and real dictated-text checks remain guided manual acceptance steps.

Restore or discard a retained checkpoint explicitly:

```bash
bin/e2e-checkpoint restore CHECKPOINT_ID
bin/e2e-checkpoint discard CHECKPOINT_ID
```

`discard` is intentionally separate from restore. Keep the last checkpoint
until dictation, the widget, a shell restart, and a new login have all worked.

Live VoxType removal is skipped unless its exact installed package exists in
the package cache. This is what makes exact restoration possible.

## Development

Tests use temporary homes and fake system commands. They must never modify the
developer's live Omarchy configuration.

```bash
tests/run
shellcheck bin/* lib/*.sh tests/*.sh tests/run tests-e2e/*
shfmt -d -i 2 -ci bin/* lib/*.sh tests/*.sh tests/run tests-e2e/*
jq --exit-status . manifest.json
omarchy plugin validate .
git diff --check
```

`tests/run` executes every temporary-home test script. GitHub Actions runs the
same suite plus shell syntax/style, QML syntax, and manifest checks. Omarchy's
plugin validator is intentionally a local check because GitHub runners do not
ship the Omarchy shell.

The implementation deliberately separates four responsibilities:

- `HandyWidget.qml`: PipeWire state and bar interaction
- `bin/handy-trigger`: runtime press/release state machine
- `bin/setup` and `bin/uninstall`: reversible integration ownership
- `bin/e2e-checkpoint`: machine-level E2E recovery

Shell helpers in `lib/` contain pure detection and file-transformation logic so
the risky orchestration remains small and testable.
