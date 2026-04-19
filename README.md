# Codex Voice

`Codex Voice` is an experimental macOS menu bar app that lets you hold `Control-M`, speak, and insert the transcript into the currently focused app.

It uses the same Codex desktop transcription flow as the Codex app, but works anywhere on your Mac.

## Demo

https://github.com/user-attachments/assets/ed182fc9-6cc2-4ef0-a2d8-344461a5719e

## What It Does

- Global `Control-M` hold-to-dictate hotkey
- Floating HUD while listening, transcribing, and inserting
- Microphone capture while the hotkey is held
- Transcript insertion into the focused app
- Accessibility-first insertion with clipboard paste fallback
- Codex-backed transcription using your local Codex sign-in

## Status

This is a reverse-engineered experimental tool.

- It depends on Codex being installed locally.
- It depends on local Codex auth already existing on your machine.
- It may break if Codex changes its internal transcription flow.

## Requirements

- macOS 14+
- Xcode
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Codex installed locally
- An active local Codex sign-in

## Permissions

On first run, macOS may ask for:

- Microphone
- Accessibility

Accessibility is required for reliable cross-app text insertion.

## Build

```bash
cd ~/Projects/codex-voice
xcodegen generate
xcodebuild -project CodexVoice.xcodeproj -scheme CodexVoice -configuration Debug build
```

## Install And Run

```bash
./scripts/install-local-app.sh
```

This installs the app to:

```bash
~/Applications/CodexVoice.app
```

Use that installed copy when granting Accessibility permission. Do not rely on a `DerivedData` build path for normal use, because macOS privacy permissions can be flaky when the app identity keeps moving around.

Then hold `Control-M`, speak, and release in any focused text field.

## Notes

- Audio is sent to the Codex transcription backend when you release the hotkey.
- The app reads local Codex auth from `~/.codex/auth.json`.
- If auth expires, the app tries to refresh it through the local `codex` CLI.
- The app looks for `codex` via `CODEX_CLI_PATH`, then your `PATH`, then `/Applications/Codex.app/Contents/Resources/codex`.
- Debug logging is off by default. To enable it temporarily, launch the app with `CODEX_VOICE_DEBUG_LOG=1`.

## License

MIT
