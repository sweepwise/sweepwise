# Sweepwise

A native macOS menu-bar app that finds disk-cleanup candidates and tells you why each one is safe (or risky) to delete before you touch anything.

**Website: [sweepwise.app](https://sweepwise.app)**

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![swift](https://img.shields.io/badge/swift-5.9%2B-orange)
![license](https://img.shields.io/badge/license-MIT-green)

## What it does

Sweepwise scans a configurable set of folders (caches, dev artifacts, downloads, and more), classifies each cleanup candidate by risk, and shows the context and restore path *before* you delete it. When it finds a large folder it doesn't recognize, it can optionally ask a locally installed AI CLI (`claude`, `codex`, or `gemini` — using your existing subscription, no API keys) to explain what it probably is. If you act on an AI explanation, Sweepwise offers — with your explicit consent, every time — to remember that rule so future scans classify it instantly without asking the AI again. Deletion goes to the Trash by default.

## Features

- **Rule-based classification** of caches, dev artifacts (`node_modules`, `DerivedData`), LLM model stores, app leftovers, and stale downloads, each with a human-readable context note and a restore note.
- **Optional AI explanations** for unknown large folders via your locally installed `claude`, `codex`, or `gemini` CLI. Uses your existing subscription; no API keys are stored or required.
- **Consent-gated learning**: after you delete an AI-classified item, Sweepwise asks — every time, never silently — whether to save that classification as a rule so future scans are instant.
- **Trash-by-default deletion**: items move to macOS Trash. Permanent deletion is opt-in and only offered for items over 2 GB.

## Requirements

- macOS 14+
- Swift 5.9+ (Xcode Command Line Tools are enough — no Xcode project required)

## Install

One line — downloads the latest release, moves it to `/Applications`, and offers to open it at login:

```bash
curl -fsSL https://sweepwise.app/install.sh | bash
```

Or [download the zip](https://sweepwise.app/download), unzip, drag `Sweepwise.app` to Applications, and open it. Releases are signed with a Developer ID certificate and notarized by Apple, so macOS opens them without any warning.

## Build from source

```bash
swift test          # run the test suite
./scripts/bundle.sh  # build a release binary and produce dist/Sweepwise.app
open dist/Sweepwise.app
```

`bundle.sh` runs `swift build -c release` (universal binary), assembles `dist/Sweepwise.app`, and ad-hoc code-signs it so it runs locally without Gatekeeper prompts.

## Usage

1. Click the Sweepwise icon in the menu bar (a disk-drive symbol; there's no Dock icon).
2. Click **Scan**. Sweepwise walks your configured folders and groups what it finds into four risk tiers:
   - **A — Safe**: pure caches, regenerated automatically.
   - **B — Rebuildable**: restored by one command (`pnpm install`, `cargo build`, etc.).
   - **C — Re-downloadable**: installers, model weights, and similar artifacts.
   - **D — User data**: deletion loses information; verify before acting.
3. Expand a row to see its path, context, restore note, and source (built-in rule, learned rule, or AI).
4. Select the items you want gone and choose **Move to Trash**.
5. Open **Settings** to edit the scanned root folders, see which AI CLIs Sweepwise detected, and review or delete learned rules.

### AI setup

Install any of `claude`, `codex`, or `gemini` as a CLI on your machine and sign in as you normally would. Sweepwise detects installed CLIs automatically and lists them in Settings → AI. No configuration or API key is needed inside Sweepwise itself.

## Full Disk Access

Some folders (Mail, Safari data, and similar) are unreadable without Full Disk Access. Sweepwise lists any paths it had to skip; if you want them scanned, grant access in **System Settings → Privacy & Security → Full Disk Access**.

## How it works

Every scanned path is checked against a bundled rule set first, then against any rules you've personally taught Sweepwise. Only if nothing matches — and only for folders above a size threshold — does Sweepwise fall back to asking a local AI CLI for a one-off explanation. Nothing is deleted automatically, and nothing is learned without your explicit, per-item confirmation.

## Contributing

Pull requests are welcome. Before submitting, run:

```bash
swift test
```

Keep changes focused and match the existing code style.

## License

MIT — see [LICENSE](LICENSE).
