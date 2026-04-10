# wishper-app

Native macOS voice-to-text with LLM cleanup, powered by MLX.

A free, open-source alternative to [Wispr Flow](https://wisprflow.ai/). Runs entirely on Apple Silicon — no cloud, no subscription, no Python.

## What makes this different

Every other open-source dictation app uses whisper.cpp (2022-era C++ code). wishper-app is built entirely on **Apple's MLX ecosystem**:

- **ASR:** Qwen3-ASR via [speech-swift](https://github.com/soniqo/speech-swift) (MLX, GPU)
- **LLM cleanup:** [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) (Apple's own package)
- **UI:** Native SwiftUI with MenuBarExtra
- **Zero Python.** Pure Swift. One binary.

## Requirements

- macOS 15+ (Sequoia)
- Apple Silicon (M1/M2/M3/M4)
- Xcode 16+ (for building)
- Accessibility permissions (System Settings > Privacy > Accessibility)

## Build & Run

```bash
git clone https://github.com/irangareddy/wishper-app.git
cd wishper-app
swift build
# or use the build script:
./script/build_and_run.sh
```

## Usage

The app lives in your menu bar. Hold **Right Cmd** to record, release to transcribe and paste.

The LLM adapts output tone based on the active app — casual in Slack, professional in Mail, technical in your IDE.

## Architecture

```
Sources/WishperApp/
├── WishperApp.swift              # @main, MenuBarExtra + Settings
├── Engine/
│   ├── PipelineCoordinator.swift # Orchestrates the full pipeline
│   ├── AudioRecorder.swift       # AVAudioEngine mic capture
│   ├── Transcriber.swift         # Qwen3-ASR via speech-swift (MLX)
│   ├── Cleaner.swift             # LLM cleanup via mlx-swift-lm
│   ├── TextInjector.swift        # Clipboard + CGEvent Cmd+V
│   ├── HotkeyManager.swift       # CGEventTap global hotkeys
│   ├── VoiceCommands.swift       # "period", "new paragraph", etc.
│   ├── AppContext.swift          # Active app detection + tone
│   └── SoundPlayer.swift         # macOS system sounds
├── Models/
│   └── AppState.swift            # Observable app state
└── Views/
    ├── MenuBarView.swift         # Menu bar popover
    └── SettingsView.swift        # Settings with model picker
```

## Tech Stack

| Component | Technology |
|---|---|
| ASR | Qwen3-ASR 0.6B (MLX, GPU) via speech-swift |
| LLM | Qwen3-0.6B-4bit (MLX, GPU) via mlx-swift-lm |
| Audio | AVAudioEngine |
| Hotkeys | CGEventTap |
| Text injection | NSPasteboard + CGEvent |
| UI | SwiftUI MenuBarExtra |
| Sounds | NSSound |

## Related

- [wishper](https://github.com/irangareddy/wishper) — Python prototype (pip installable, for testing models and pipeline ideas)

## License

MIT
