# Roadmap

## Shipped

**Multilingual transcription (v1.1.0)**
Upgraded from Parakeet-TDT v2 (English-only) to v3 (25 European languages). Auto-detects spoken language.

## Up next

**Custom vocabulary boosting**
Decode-time vocabulary biasing via CTC keyword spotting. Feed a text file of domain-specific terms and the transcriber prioritizes those words. No retraining needed.

**FluidAudio fork**
Upstream fixes to the ASR pipeline: source-specific decoder state reset and a thread safety improvement.

**JSONL crash recovery**
Rebuild transcripts from session data if the app exits mid-session.
