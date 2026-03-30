<h1 align="center">Tome</h1>

<p align="center">
  <strong>Local meeting capture → Obsidian vault → AI agent pipeline. No cloud. No API keys. Your data.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white" alt="Swift 6.2" />
  <img src="https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white" alt="macOS 26+" />
  <img src="https://img.shields.io/badge/License-MIT-blue" alt="MIT License" />
  <img src="https://img.shields.io/badge/Apple%20Silicon-Required-333333?logo=apple&logoColor=white" alt="Apple Silicon" />
</p>

---

Tome is a macOS app that captures meetings and voice memos, transcribes them locally with Parakeet-TDT v3, and drops structured `.md` files straight into your Obsidian vault. Everything runs on-device. Nothing phones home.

<p align="center">
  <img src="https://raw.githubusercontent.com/Gremble-io/Tome/main/assets/screenshot-idle.png" width="350" alt="Tome — idle state" />
  <img src="https://raw.githubusercontent.com/Gremble-io/Tome/main/assets/screenshot-recording.png" width="350" alt="Tome — recording with spectrum visualizer" />
</p>

## Background

I'm a consultant who fell down the Obsidian rabbit hole. I built out a vault as a second brain: structured notes with YAML frontmatter, backlinks, tags, and a Claude agent layer that processes everything. Client files, meeting notes, action items, daily briefs, all flowing through the vault automatically.

The problem was capture. I'm on calls all day and I don't take notes. I needed something that would listen, transcribe, and drop structured markdown into the vault where my agent could pick it up and do the rest. Pull out action items, update client files, connect the dots.

I looked at Otter, Granola, Fireflies. They all lock your data in their cloud, their format, their walled garden. None of them output plain markdown. None of them are built to feed into an agent workflow.

I started from [OpenGranola](https://github.com/yazinsai/OpenGranola), learned Swift along the way, and rebuilt it with a different audio pipeline, local ASR, speaker diarization, and vault-native output. If you're running Obsidian with any kind of AI agent setup, you probably have the same gap.

## Why Tome?

- **Plain markdown out.** YAML frontmatter, tags, timestamps. Your vault already knows what to do with it. No proprietary export, no copy-paste, no middleman.
- **Built for the agent pipeline.** Tome is just the capture layer. You talk, it transcribes, your agent picks up the `.md` and does whatever you've wired it to do.
- **Runs on your machine.** Parakeet-TDT v3 on Apple Silicon. No API keys, no accounts, no subscriptions, no data leaving the building.

```
speak → capture → vault → agent → knowledge base
```

Tome does the first three. Your agent does the rest.

## Features

- **Multilingual transcription** via Parakeet-TDT v3 ([FluidAudio](https://github.com/FluidInference/FluidAudio)) on Apple Silicon. 25 European languages, auto-detected. Nothing hits the network.
- **Call Capture** grabs mic + system audio. Detects which conferencing app you're in (Teams, Zoom, Slack, etc.) and filters audio to just that app. Your Spotify and notification sounds stay out of the transcript.
- **Voice Memo** is mic only. For quick thoughts, verbal notes, stream of consciousness. Saves to a separate folder so it doesn't clutter your meeting transcripts.
- **Speaker diarization** runs after the call ends. pyannote splits the remote audio into Speaker 2, Speaker 3, Speaker 4. Not perfect, but way better than one wall of unattributed text.
- **Vault-native output** writes `.md` with frontmatter: `type`, `created`, `attendees`, `tags`, `source_app`. Lands in your vault ready to process.
- **Privacy.** Hidden from screen sharing by default. No audio saved. Transcripts only.
- **Silence auto-stop.** 120 seconds of dead air and it stops itself.

## How It Works

```
┌─────────────┐     ┌──────────────────┐     ┌───────────────┐
│  Microphone  │────▶│                  │     │               │
└─────────────┘     │  Tome            │     │  Obsidian     │
                    │  ┌────────────┐  │────▶│  Vault        │
┌─────────────┐     │  │ Parakeet   │  │     │  (.md files)  │
│  System      │────▶│  │ TDT v3    │  │     │               │
│  Audio       │     │  └────────────┘  │     └───────┬───────┘
└─────────────┘     └──────────────────┘             │
                                                     ▼
                                              ┌──────────────┐
                                              │  AI Agent    │
                                              │  Layer       │
                                              │  (notes,     │
                                              │   actions,   │
                                              │   updates)   │
                                              └──────────────┘
```

1. **Capture** picks up mic audio + system audio from a specific conferencing app via ScreenCaptureKit.
2. **Transcribe** runs VAD to detect speech segments, then Parakeet transcribes locally.
3. **Diarize** splits the system audio into individual speakers after the session ends.
4. **Write** drops structured `.md` with YAML frontmatter into your vault folder.
5. **Agent picks up** whatever you've got downstream processes the transcript.

## Output

<p align="center">
  <img src="https://raw.githubusercontent.com/Gremble-io/Tome/main/assets/screenshot-vault-frontmatter.png?v=2" width="600" alt="Vault note with YAML frontmatter" />
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Gremble-io/Tome/main/assets/screenshot-vault-transcript.png?v=2" width="600" alt="Vault note transcript view" />
</p>

```markdown
---
type: meeting
created: "2026-03-23"
time: "10:00"
duration: "18:42"
source_app: "Zoom"
attendees: ["You", "Speaker 2"]
tags:
  - log/meeting
  - status/inbox
  - source/tome
---

# Call Recording — 2026-03-23 10:00

**You** (10:00:03)
Morning. Quick sync on the product launch. Where are we at?

**Speaker 2** (10:00:07)
We're in good shape. QA signed off yesterday, marketing assets
are locked, landing page is live in staging.
```

Voice memos use `type: fleeting` with a single speaker. Same structure, same frontmatter.

## Build

**Requirements:** Apple Silicon Mac, macOS 26+, Xcode 26.3+

```bash
git clone https://github.com/Gremble-io/Tome.git
cd Tome
./scripts/build_swift_app.sh
```

Builds and installs to `/Applications`. First launch downloads the Parakeet ASR model (~600MB, cached after that).

**Dev build:**

```bash
cd Tome
swift build
```

## Permissions

| Permission | When | Why |
|---|---|---|
| **Microphone** | All modes | Captures your voice |
| **Screen Recording** | Call Capture only | ScreenCaptureKit needs this for system audio from conferencing apps |

macOS re-prompts for Screen Recording permission roughly monthly. That's an OS thing, not Tome.

## Architecture

```
Tome/Sources/Tome/
├── App/
│   ├── TomeApp.swift               # App entry point
│   └── AppUpdaterController.swift  # Sparkle update controller
├── Audio/
│   ├── SystemAudioCapture.swift    # ScreenCaptureKit + per-app filtering
│   └── MicCapture.swift            # AVAudioEngine mic input
├── Models/
│   ├── Models.swift                # Domain types (Utterance, Speaker, etc.)
│   └── TranscriptStore.swift       # Observable transcript state
├── Transcription/
│   ├── TranscriptionEngine.swift   # Dual-stream capture + diarization
│   └── StreamingTranscriber.swift  # VAD + Parakeet ASR pipeline
├── Storage/
│   ├── TranscriptLogger.swift      # .md output with YAML frontmatter
│   └── SessionStore.swift          # Session metadata
├── Settings/
│   └── AppSettings.swift
└── Views/
    ├── ContentView.swift
    ├── ControlBar.swift
    ├── TranscriptView.swift
    ├── SettingsView.swift
    ├── OnboardingView.swift
    └── CheckForUpdatesView.swift
```

## Privacy

- Transcription runs entirely on-device. No audio is ever sent anywhere.
- No network calls. No analytics. No telemetry.
- No audio is saved to disk. Only text transcripts.
- The app window is hidden from screen sharing by default.
- Transcripts are saved as plain `.md` files to a folder you choose.

## Known Limitations

- **Apple Silicon only.** Parakeet and FluidAudio need Metal / ANE. No Intel.
- **macOS 26+ only.**
- **Screen Recording re-prompts monthly.** OS limitation.
- **Diarization is imperfect.** Works well with headset mics. Laptop speakers with crosstalk will give you worse speaker separation.
- **No live speaker labels.** Diarization runs after the session ends. During the call, remote audio shows as a single stream.

## Troubleshooting

**"Tome is damaged and can't be opened"**

This is macOS Gatekeeper blocking an unsigned app. Until a signed release is available:

1. Right-click (or Control-click) `Tome.app` in `/Applications`
2. Click **Open**
3. In the dialog, click **Open** again

You only need to do this once — after that, Tome launches normally.

Alternatively, build from source (see [Build](#build) above) to avoid Gatekeeper entirely.

## Credits

Started from [OpenGranola](https://github.com/yazinsai/OpenGranola). Substantially rewritten from there.

## License

[MIT](LICENSE)
