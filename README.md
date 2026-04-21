# Wishper

**Voice-to-text that runs entirely on your Mac.** Hold a hotkey, speak, watch your words land wherever your cursor is.

**Website:** [wishper.irangareddy.in](https://wishper.irangareddy.in) · **Download:** [latest DMG](https://github.com/irangareddy/wishper-app/releases/latest/download/Wishper.dmg)

## Features

- **100% on-device.** No network calls, no accounts, no analytics. Verify with Little Snitch.
- **Fast.** Powered by [MLX](https://github.com/ml-explore/mlx). Qwen3-ASR for transcription, a tiny Qwen3 for filler-word cleanup.
- **Works everywhere you type.** Slack, Mail, Notes, VS Code, Xcode, Chrome — if your cursor is blinking in a text field, Wishper can type there.
- **Hold-to-talk.** Hold a chosen hotkey (Right ⌘ by default), speak naturally, release. No wake word, no mode switching.
- **Privacy by construction.** Audio never leaves the device.
- **Auto-updates via Sparkle.** EdDSA-signed releases, daily check.

## Install

**Option 1 — Direct download (recommended)**

```
https://github.com/irangareddy/wishper-app/releases/latest/download/Wishper.dmg
```

Open the DMG, drag Wishper into Applications, launch it. macOS will ask for microphone + accessibility permissions on first run — grant them.

**Option 2 — Build from source**

```bash
git clone https://github.com/irangareddy/wishper-app.git
cd wishper-app
open WishperApp.xcodeproj
# Select the WishperApp scheme, hit Run
```

Requires Xcode 16+ and an Apple Silicon Mac.

## Requirements

- macOS 15 (Sequoia) or later
- Apple Silicon (M1 / M2 / M3 / M4). Intel is not supported — MLX is Apple-Silicon-only.
- ~2 GB free disk space for the ASR + LLM models (downloaded on first launch)

## How it works

```
 [ Mic ] ─► Silero VAD ─► Qwen3-ASR ─► Qwen3 cleanup LLM ─► Text injector ─► Your app
  (16kHz)   (on-device)   (on-device)   (on-device)         (AX / pasteboard)
```

1. You hold the hotkey
2. Audio streams through a voice activity detector so silence isn't transcribed
3. Speech segments go to Qwen3-ASR locally
4. The raw transcript passes through a small LLM that strips "um", "uh", repeated words, and cleans up punctuation
5. The result is injected into the focused text field — via Accessibility API when possible, Cmd+V clipboard simulation as a fallback

No network is involved at any step. Models live in `~/Library/Application Support/Wishper/models/`.

## Releasing (maintainers)

End-to-end release flow, one command:

```bash
export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="wishper-notary"

./script/release.sh --patch   # 0.5.x → 0.5.x+1 + build bump
./script/release.sh --minor   # 0.5.x → 0.6.0 + build bump
./script/release.sh --set 1.0.0
```

The script bumps the version, archives the app for arm64, signs it (Sparkle XPC services individually, no `--deep`), notarizes via `notarytool`, builds a signed + notarized + stapled DMG, generates the EdDSA-signed Sparkle appcast, tags `v<version>`, and creates a GitHub release with the DMG + `appcast.xml` attached.

One-time setup before the first release: see [docs/RELEASE.md](docs/RELEASE.md) (if you need it, open an issue and I'll add it).

## Contributing

Bug reports and feature ideas are welcome:

- **Bug?** [File an issue](https://github.com/irangareddy/wishper-app/issues/new?template=bug.yml) (or use **Settings → Report a Bug** in the app — it pre-fills the template).
- **Feature idea or question?** [Start a Discussion](https://github.com/irangareddy/wishper-app/discussions).
- **Code contribution?** Open a PR. Keep it focused — one concern per PR. The `100% on-device` constraint is hard; features that introduce a network dependency likely won't be merged.

## Acknowledgments

- [MLX Swift](https://github.com/ml-explore/mlx-swift) + [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) by Apple
- [speech-swift](https://github.com/soniqo/speech-swift) by @soniqo — Silero VAD + Qwen3-ASR wrappers
- [swift-transformers](https://github.com/huggingface/swift-transformers) by Hugging Face
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by @sindresorhus
- [Sparkle](https://sparkle-project.org/) for auto-updates

## License

[MIT](LICENSE) © 2026 Ranga Reddy Nukala
