# Handy Dictation for Omarchy Quattro

> [!WARNING]
> **This repository is deprecated and no longer maintained.**
>
> It is not being pursued as an Omarchy plugin and has not been published to the
> plugin directory. The code stays up for reference only; there are no planned
> fixes, releases, or reviews.
>
> Note that `bin/setup` invokes `sudo` to grant evdev access to input devices.
> Read [Security notes](#security-notes) and understand what that grants before
> running anything here.

`blizl.handy` is a Quattro-native bar widget and dictation integration for
[Handy](https://github.com/cjpais/Handy). It keeps a dynamic microphone glyph visible,
shows capture state directly from PipeWire, and binds dictation to a single **toggle**
shortcut through Handy's kernel-level evdev hotkey engine (`handy_keys`): press once to
start recording, press again to stop.

![Handy Settings Preview](assets/handy-settings.png)

## About Handy

[Handy](https://github.com/cjpais/Handy) is a free and open-source desktop
speech-to-text application. It records speech when you press a
configured shortcut, transcribes it locally with a downloaded model, and
inserts the resulting text into the application you are using. Handy works
offline, so transcription does not require sending your voice to a cloud
service.

Handy is released under the MIT License and supports Whisper and Parakeet
speech-recognition models. Handy's own interface handles model downloads,
language and transcription settings, and transcript history. This plugin adds
the Omarchy-specific Quickshell microphone indicator, the toggle binding,
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

After updating an existing v1 installation, run
`~/.config/omarchy/plugins/blizl.handy/bin/setup` again. It first restores the
previous integration, then reapplies the latest conflict-safe setup so
uninstall still returns the machine to its original state.

Setup opens Handy's official onboarding for model selection. It then asks which
shortcut to own, configures Handy's native `handy_keys` engine with that shortcut in
toggle mode, ensures kernel input device permissions, and disables VoxType's own
hotkey.

**Setup never edits `~/.config/hypr/bindings.lua`.** Your keybindings are yours. If
the shortcut you pick is already bound there, setup stops and shows you the exact
line to change rather than rewriting the file — see
[Keybindings stay yours](#keybindings-stay-yours). VoxType may remain installed;
uninstall restores its hotkey.

Setup also replaces the built-in center Dictation indicator with Handy, then
runs an inline acceptance test directly in the active terminal that clearly
identifies Handy as the engine. It commits only when that test receives
non-empty dictated text.

If the dictation test fails or ends without text, setup restores the previous
bindings, shell layout, Handy and VoxType shortcut settings, autostart, and
process state. It then disables and removes the installed `blizl.handy` plugin,
avoiding a partially configured integration. VoxType removal is never the
default and is offered only after the dictation test succeeds.

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

Left-click opens Handy when it is idle. While Handy is recording, left-click is
an emergency stop that finishes the active dictation and preserves its text. If
Handy cannot finish it, the trigger cancels the recording and sends a failure
notification. Middle-click opens Omarchy's audio panel. Clicking while no
default microphone exists sends a notification instead.

### Why the shortcut is a toggle, not a hold

Dictation is a **single-tap toggle**: press the shortcut once to start recording, press it
again to stop. Setup writes `push_to_talk = false` into Handy's settings, so no key ever
has to stay held down.

Earlier versions used press-and-hold push-to-talk. Holding a chord is the fragile option
on Wayland, because stopping depends on correctly observing a key *release*:

- **Release order breaks hold bindings.** Hyprland release bindings (`bindr` /
  `{ release = true }`) only fire when the base key is released while every modifier is
  still down. Let go of `Alt` a millisecond before `Space` and the compositor drops the
  release entirely, leaving the microphone recording indefinitely.
- **A dropped release fails open.** The failure mode of a missed release is a hot
  microphone, which is the worst direction for a dictation tool to fail in. A missed
  toggle press just means nothing happened, and the next press fixes it.
- **Holding a chord is uncomfortable for real dictation.** Long-form speech means holding
  `Alt` for a minute at a time, and it collides with any application that reacts to a
  held modifier.

A toggle sidesteps all of it: only key *presses* matter, so release order is irrelevant by
construction.

### Keybindings stay yours

The plugin does not read, rewrite, or restore `~/.config/hypr/bindings.lua`. It has no
managed block, and uninstall has nothing to put back there.

That leaves one thing you may have to do by hand. Because `handy_keys` reads the
keyboard at the kernel level, Hyprland still receives the same chord, so a binding on
that chord keeps firing alongside Handy — one press, two actions. Setup therefore
checks the chord you picked and stops if it is already taken:

```
ALT + SPACE is already bound in your Hyprland configuration:
  /home/you/.config/hypr/bindings.lua:32
      o.bind("ALT + SPACE", "Toggle dictation", "voxtype record toggle")
      action: Toggle dictation: voxtype record toggle

Handy reads the shortcut directly from the kernel, so that binding would
still fire alongside Handy and one press would trigger both actions.
Remove or change that line, then run setup again.
```

If the chord comes from Omarchy's own stock bindings instead, that file belongs to
Omarchy, so setup tells you to override it from your own config:

```
  hl.unbind("F9")
```

Spacing does not matter: `ALT+ENTER` and `ALT + ENTER` are recognized as the same
chord. Bindings on *other* keys that still launch VoxType are listed as a warning
rather than removed, so you can decide whether Handy should be your only dictation
engine.

Versions up to 1.1.0 wrote a managed block into `bindings.lua` and unbound those keys
automatically. Upgrading removes that block; `bin/restore-voxtype` also strips a
leftover one.

### Native evdev hotkeys (`handy_keys`)

The toggle shortcut (such as `ALT + SPACE`, `ALT + ENTER`, `SUPER + SPACE`, or a custom
chord) is still delivered by Handy's kernel-level evdev engine rather than by a compositor
binding:

- **Direct kernel-level hotkeys**: Handy reads Linux input devices (`/dev/input/event*`)
  through its native Rust `handy_keys` engine, matching Omarchy's own VoxType
  architecture. This requires evdev read permission, which setup arranges via the `input`
  group.
- **No compositor round-trip**: the chord never has to pass through Hyprland's binding
  table to reach Handy. The flip side is that Hyprland still sees it too, which is why a
  conflicting binding has to go — see [Keybindings stay yours](#keybindings-stay-yours).
- **Zero wrapper overhead**: no external wrapper scripts, timeouts, or background daemons
  sit between the keypress and the recorder.

The widget's left-click emergency stop remains available whenever a recording needs to be
ended without the keyboard.

## Security notes

### What this plugin asks of your system

Handy's `handy_keys` engine reads hotkeys straight from `/dev/input/event*`, the
same mechanism Omarchy's own VoxType uses. Setup therefore offers to grant evdev
read access, and you should understand what that means before accepting:

- **`input` group membership** (offered first, **persistent across reboots**).
  Every process running as your user can then read *all* keyboard input
  system-wide, including passwords typed into other applications. This is the
  standard cost of any userspace global-hotkey daemon on Linux.
- **`setfacl` on `/dev/input/event*`** (offered only if `event0` is unreadable,
  **lasts until reboot** because udev recreates the nodes). Same capability,
  narrower lifetime.

Both prompts are opt-in and can be declined; Handy's hotkey simply will not work
until evdev is readable some other way. Setup derives the account it grants
access to from `id`, never from `$USER`, and passes the numeric uid to `setfacl`
so no part of the ACL specification can come from the environment.

### Trust boundaries

The plugin runs entirely as your user and calls `sudo` only for the two evdev
permission grants above. Package operations go through `omarchy pkg add` /
`omarchy pkg drop`, which handle their own privilege escalation.

Everything the plugin records under `~/.local/state/blizl.handy` — checkpoints,
transaction backups, `install.json` — is writable by any process running as your
user, so it is treated as untrusted input on the way back in:

- **Package names are never read from state.** Checkpoint restore iterates the
  hardcoded `CHECKPOINT_MANAGED_PACKAGES` list (`handy-bin`, `voxtype-bin`,
  `wtype`) in `lib/checkpoint.sh` and reads only the recorded version and
  presence from `package-state.json`. `checkpoint_verify` rejects any state file
  whose entries do not match that exact set, so editing it cannot stage an
  arbitrary system package install or removal.
- **Restore targets are canonicalized, not prefix-matched.** `checkpoint_safe_path`
  and `transaction_safe_target` resolve symlinks and `..` before confirming the
  path sits under `~/.config`, `~/.local/share`, `~/.local/state`, or
  `~/.local/bin`. `bin/uninstall` canonicalizes the transaction directory
  recorded in `install.json` the same way.
- **No executable config is generated.** `bindings.lua` is the only file in play
  that another program executes as code, and the plugin never writes it — see
  [Keybindings stay yours](#keybindings-stay-yours). Everything setup does write
  (`settings_store.json`, `shell.json`, `config.toml`, `Handy.desktop`) is inert
  data.

### Running as root

`bin/setup`, `bin/uninstall`, `bin/restore-voxtype`, and `bin/e2e-checkpoint`
refuse to run as root. They configure one user's desktop, and running them under
`sudo` would write root-owned files into `$HOME` and turn the `BLIZL_HANDY_*_BIN`
test seams into root code-execution paths. Set `BLIZL_HANDY_ALLOW_ROOT=true` only
in a container that genuinely has no unprivileged user.

### Reporting a vulnerability

Please open a security advisory on the GitHub repository rather than a public
issue.

## Remove the integration

### Standard Removal
To remove the plugin integration and restore all original configurations (Hyprland bindings, center indicators, autostart, and VoxType settings) while preserving Handy and downloaded models:

```bash
~/.config/omarchy/plugins/blizl.handy/bin/uninstall && omarchy plugin remove blizl.handy
```

*(When running directly from this repository checkout, use `./bin/uninstall && omarchy plugin remove blizl.handy`)*

---

### Complete Removal & Full VoxType Restoration
To completely remove the plugin and Handy, clean up downloaded model caches, and fully restore native Omarchy VoxType dictation with automated checkpoint backups:

```bash
~/.config/omarchy/plugins/blizl.handy/bin/restore-voxtype
```

* **Preserve previous custom VoxType bindings:**
  ```bash
  ~/.config/omarchy/plugins/blizl.handy/bin/restore-voxtype --yes --bindings previous
  ```
* **Restore stock Omarchy bindings (`F9` hold / `Super+Ctrl+X` toggle):**
  ```bash
  ~/.config/omarchy/plugins/blizl.handy/bin/restore-voxtype --yes --bindings stock
  ```

*(When running from a local checkout, replace the path above with `./bin/restore-voxtype`. Pass `--keep-plugin` if the checkout should stay installed after the reset, or `--keep-handy-data` to retain Handy's settings, recordings, and downloaded model caches).*

---

### Complete Purge of Handy & Speech Models
To manually remove Handy, all downloaded Whisper/Parakeet speech models, and all local configuration/databases:

```bash
# 1. Uninstall the plugin integration & restore configuration files
~/.config/omarchy/plugins/blizl.handy/bin/uninstall && omarchy plugin remove blizl.handy

# 2. Remove the Handy package
omarchy pkg drop handy-bin handy-bin-debug

# 3. Remove Handy user settings, databases, and autostart files
rm -rf ~/.local/share/com.pais.handy ~/.config/autostart/Handy.desktop

# 4. Remove all downloaded speech models
rm -rf ~/.cache/huggingface/hub/models--handy-computer--*
```

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

Set those confirmations only after manually proving the existing dictation
shortcut and microphone indicator. The runner records baseline Hyprland errors
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

Package removal and restoration use Omarchy's package manager (`omarchy pkg drop` /
`omarchy pkg add`), preserving user configurations without local package archive
manipulation.

Checkpoint restore only ever acts on the three packages this plugin manages; see
[Trust boundaries](#trust-boundaries) for why the names cannot come from the
checkpoint's own state file.

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

The implementation deliberately separates core responsibilities:

- `HandyWidget.qml`: PipeWire state and bar interaction
- `bin/handy-trigger`: runtime emergency stop, manual toggle, and notifications
- `bin/setup` and `bin/uninstall`: reversible integration ownership and native `handy_keys` configuration
- `lib/bindings.sh`: read-only inspection of `bindings.lua` for conflict reporting
- `bin/restore-voxtype`: clean rollback and recovery to stock or previous VoxType setup
- `bin/e2e-checkpoint`: machine-level E2E recovery
- `lib/privilege.sh`: refuses to run the privileged entry points as root

Shell helpers in `lib/` contain pure detection and file-transformation logic so
the risky orchestration remains small and testable.
