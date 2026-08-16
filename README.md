# Handy Dictation for Omarchy Quattro

`blizl.handy` is a Quattro-native bar widget and push-to-talk integration for
[Handy](https://github.com/cjpais/Handy). It keeps a microphone glyph visible,
shows capture state directly from PipeWire, and prevents a key release from
starting Handy when its matching key press was rejected.

## About Handy

[Handy](https://github.com/cjpais/Handy) is a free and open-source desktop
speech-to-text application. It records speech when you press or hold a
configured shortcut, transcribes it locally with a downloaded model, and
inserts the resulting text into the application you are using. Handy works
offline, so transcription does not require sending your voice to a cloud
service.

Handy is released under the MIT License and supports Whisper and Parakeet
speech-recognition models. Handy's own interface handles model downloads,
language and transcription settings, and transcript history. This plugin adds
the Omarchy-specific Quickshell microphone indicator, push-to-talk bindings,
missing-microphone handling, and reversible setup around that upstream app.

### Supported languages

Language support depends on the model selected in Handy; this plugin does not
add or remove languages. Handy shows only the language choices supported by the
active model and offers automatic detection when that model provides it.

- Multilingual Whisper models support 99 languages. Whisper Large v3 and Large
  v3 Turbo also support Cantonese.
- Parakeet TDT 0.6B v3 supports Bulgarian, Croatian, Czech, Danish, Dutch,
  English, Estonian, Finnish, French, German, Greek, Hungarian, Italian,
  Latvian, Lithuanian, Maltese, Polish, Portuguese, Romanian, Russian, Slovak,
  Slovenian, Spanish, Swedish, and Ukrainian.
- Parakeet Unified EN and Parakeet TDT 0.6B v2 support English only.
- Other models available through Handy have their own language lists. Handy's
  model and language settings are the authoritative source for the installed
  version.

<details>
<summary>All 99 languages supported by multilingual Whisper models</summary>

English, Chinese, German, Spanish, Russian, Korean, French, Japanese,
Portuguese, Turkish, Polish, Catalan, Dutch, Arabic, Swedish, Italian,
Indonesian, Hindi, Finnish, Vietnamese, Hebrew, Ukrainian, Greek, Malay, Czech,
Romanian, Danish, Hungarian, Tamil, Norwegian, Thai, Urdu, Croatian, Bulgarian,
Lithuanian, Latin, Maori, Malayalam, Welsh, Slovak, Telugu, Persian, Latvian,
Bengali, Serbian, Azerbaijani, Slovenian, Kannada, Estonian, Macedonian, Breton,
Basque, Icelandic, Armenian, Nepali, Mongolian, Bosnian, Kazakh, Albanian,
Swahili, Galician, Marathi, Punjabi, Sinhala, Khmer, Shona, Yoruba, Somali,
Afrikaans, Occitan, Georgian, Belarusian, Tajik, Sindhi, Gujarati, Amharic,
Yiddish, Lao, Uzbek, Faroese, Haitian Creole, Pashto, Turkmen, Nynorsk, Maltese,
Sanskrit, Luxembourgish, Myanmar, Tibetan, Tagalog, Malagasy, Assamese, Tatar,
Hawaiian, Lingala, Hausa, Bashkir, Javanese, and Sundanese.

</details>

## Install

```bash
omarchy plugin add https://github.com/Blizl/Omarchy-Handy-Plugin.git --enable \
  && ~/.config/omarchy/plugins/blizl.handy/bin/setup
```

Setup opens Handy's official onboarding for model selection. It then asks which
push-to-talk shortcut to own, moves Handy's internal shortcut to a reserved
chord, disables VoxType's native hotkey when present, and unbinds any stock
VoxType action on the selected key. Setup then opens a focused test window where
the user dictates one line. It commits only when that window receives non-empty
text.

If the dictation test fails or the test window closes without text, setup
restores the previous bindings, Handy and VoxType shortcut settings, autostart,
and process state. It then disables and removes the installed `blizl.handy`
plugin, avoiding a partially configured integration. VoxType removal is never
the default and is offered only after the dictation test succeeds.

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

The uninstaller restores the previous Hyprland bindings, Handy shortcut,
VoxType native-hotkey setting, and autostart file. It does not remove Handy,
downloaded models, or VoxType.

To remove the plugin and Handy completely and return to native Omarchy
VoxType, use the all-in-one recovery command instead. This interactive form
asks whether to preserve the pre-plugin VoxType bindings or use stock Omarchy
bindings:

```bash
~/.config/omarchy/plugins/blizl.handy/bin/restore-voxtype
```

One-line reset that preserves the previous VoxType bindings:

```bash
~/.config/omarchy/plugins/blizl.handy/bin/restore-voxtype --yes --bindings previous
```

One-line reset to stock Omarchy bindings (`F9` push-to-talk and
`Super+Ctrl+X` toggle):

```bash
~/.config/omarchy/plugins/blizl.handy/bin/restore-voxtype --yes --bindings stock
```

When running directly from this repository checkout, replace the path above
with `./bin/restore-voxtype`. Pass `--keep-plugin` if the checkout should stay
installed after the reset, or `--keep-handy-data` to retain Handy's settings,
recordings, and downloaded model caches.

This creates a verified E2E checkpoint and a separate archive of Handy's user
data, restores the pre-plugin bindings when available, installs or recovers
VoxType, restores the stock `omarchy.indicators` widget, removes Handy and its
model caches, validates Hyprland, and finally removes the plugin checkout. It
asks whether to preserve the pre-plugin VoxType keybindings or restore
Omarchy's defaults—hold `F9` for push-to-talk, or press `Super+Ctrl+X` to
toggle dictation. It does not stage, commit, push, or otherwise modify dotfiles
Git history.

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
shellcheck bin/* lib/*.sh tests/*.sh tests-e2e/run tests-e2e/verify-baseline tests-e2e/scenarios/*
shfmt -d -i 2 -ci bin/* lib/*.sh tests/*.sh tests-e2e/run tests-e2e/verify-baseline tests-e2e/scenarios/*
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
