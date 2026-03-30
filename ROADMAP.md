# Roadmap

## Shipped

**Multilingual transcription (v1.1.0)**
Upgraded from Parakeet-TDT v2 (English-only) to v3 (25 European languages). Auto-detects spoken language.

## Up next

**Custom vocabulary boosting**
Decode-time vocabulary biasing via CTC keyword spotting. Feed a text file of domain-specific terms and the transcriber prioritizes those words. No retraining needed.

**FluidAudio fork** *(in progress)*
Fork FluidAudio with `@unchecked Sendable` on `AsrManager`/`VadManager` to fix Swift 6 build failures on Xcode 26.4+. Also includes source-specific decoder state reset.

**Per-stream model instances**
Create separate `AsrManager`/`VadManager` per audio stream to eliminate shared state across concurrent tasks.

**JSONL crash recovery**
Rebuild transcripts from session data if the app exits mid-session.
