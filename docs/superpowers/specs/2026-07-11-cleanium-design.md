# Cleanium — Design Spec

Date: 2026-07-11
Status: approved pending user review

## Purpose

A macOS menu-bar app that scans user-configured folders for disk-cleanup
candidates and presents each with size, risk level, context, and restore
notes — reproducing a guided, expert cleanup session in a simple GUI.
Selected items move to the Trash.

## Decisions (locked with user)

- Native Swift/SwiftUI. No Tauri, no Electron, no web bundler.
- Menu-bar app (`MenuBarExtra`), no Dock icon. Non-intrusive.
- Deletion moves items to macOS Trash (recoverable). Items over 2 GB
  warn about Trash filling the disk and offer optional permanent delete.
- Classification: built-in deterministic rule engine first; optional LLM
  explanation for large unknown folders.
- LLM access via locally installed CLIs only — `claude -p`,
  `codex exec`, `gemini -p`. Uses the user's existing subscriptions
  (Claude Pro/Max, ChatGPT Plus, Gemini). No API keys, no HTTP SDK.
  Provider switchable in Settings; app auto-detects installed CLIs.
- Learning: when the user deletes an LLM-classified item, the LLM's
  suggested rule is persisted as a learned rule so future scans classify
  it deterministically. Deletion is the confirmation signal — no extra
  prompt. Non-deleted LLM classifications are session-only.
- Scan scope: curated defaults, user-editable in Settings.

## Architecture

Swift Package Manager executable target. No Xcode project file; builds
with `swift build`, packaged into `Cleanium.app` by `scripts/bundle.sh`
(creates the bundle layout, Info.plist with `LSUIElement=true`, copies
the binary and resources). macOS 14+.

Modules (single package, separate source directories, one library target
`CleaniumCore` + executable target `Cleanium` for UI):

### 1. Scanner (CleaniumCore)

- Walks configured roots with `FileManager` enumerator on a background
  task; never blocks the UI.
- Computes directory sizes bottom-up. When a directory matches a rule,
  records it as a candidate and does not descend further (a matched
  `node_modules` is one candidate, not thousands).
- Emits progress (current path, bytes seen) and a stream of candidates.
- Skips paths it cannot read; collects them into a `skipped` list.

### 2. RuleEngine (CleaniumCore)

- Pure functions: `(path, metadata) -> Classification?`.
- Bundled ruleset: ~40 rules in `rules.json` shipped as a resource.
  Each rule: id, name pattern (glob on path or directory name),
  category (`cache`, `devArtifact`, `llmModel`, `appLeftover`,
  `trash`, `download`), risk (`safe`, `rebuildable`, `redownload`,
  `userData`), context text, restore note, optional staleness threshold
  (days since last modification before it is flagged).
- Rules derived from the real cleanup session: `node_modules`, `.venv`,
  `target/`, `~/Library/Caches/*`, ShipIt updater leftovers, Xcode
  DerivedData, CoreSimulator, Playwright browsers, uv/npm/pnpm caches,
  Ollama/LM Studio model dirs, tool dot-folders for uninstalled apps,
  `~/.Trash`, stale Downloads, app leftovers in Application Support.
- Learned ruleset: `learned-rules.json` in
  `~/Library/Application Support/Cleanium/`, same schema plus
  provenance (source LLM, date, originating path, pattern kind:
  `exactPath` or `glob`).
- Precedence: bundled rules match first; learned rules never override
  bundled ones.

### 3. LLMExplainer (CleaniumCore)

- Optional; app is fully functional without it.
- Input: unmatched directories above a size threshold (default 500 MB).
- Runs the selected CLI via `Process` with a prompt asking for strict
  JSON: `{category, risk, context, restore_note, suggested_rule:
  {pattern, kind}}`. 30-second timeout per call; calls are serialized.
- Provider detection: checks PATH and common install locations for
  `claude`, `codex`, `gemini`. Settings shows only detected providers.
- Any failure (missing CLI, timeout, bad JSON) degrades to
  "unknown — inspect manually". Never blocks or fails a scan.

### 4. LearnedRuleStore (CleaniumCore)

- Persists learned rules; loaded by RuleEngine at scan start.
- A learned rule is written only when the user deletes an item whose
  classification came from the LLM in the current session.
- Exact-path rules by default; the LLM's broader glob suggestion is
  stored but marked `unverified` and shown as such in results.
- CRUD surface for the Settings pane (list, edit, delete).

### 5. TrashService (CleaniumCore)

- `FileManager.trashItem(at:)` per selected item.
- Per-item error handling: one failure never aborts the batch; failures
  reported per item.
- Items > 2 GB: warning in confirm dialog + opt-in permanent delete
  (`removeItem(at:)`).
- Only ever touches paths the user explicitly checked in the UI.

### 6. SettingsStore (CleaniumCore)

- `UserDefaults`-backed: scan roots (with defaults below), category
  toggles, staleness threshold days, size floor for listing, LLM
  provider selection, LLM enable/disable.
- Default roots: `~/Library/Caches`, `~/Library/Application Support`,
  `~/Library/Developer`, dev folders (any configured; default
  `~/Documents/Dev`), home dot-folders, `~/Downloads`, `~/.Trash`.

### 7. UI (Cleanium executable target)

- `MenuBarExtra` with window-style popover:
  - Header: disk free/total gauge, Scan / Cancel button, progress line.
  - Results grouped by risk tier (mirrors the A/B/C/D cleanup groups),
    sorted by size within groups. Checkbox per item, group select-all,
    running total of selected bytes.
  - Item row: name, size, category badge, risk badge; expandable detail
    with full path, context, restore note, provenance (rule vs LLM).
  - Footer: "Move to Trash" (item count + total size), confirm dialog.
- Settings window (`Settings` scene): General (roots, thresholds),
  Rules (bundled list read-only, learned rules editable), AI (provider
  pick among detected CLIs, on/off, size threshold).
- Skipped-paths view with Full Disk Access guidance (link to System
  Settings pane).

## Data Flow

Scan → Scanner streams candidates → RuleEngine (bundled + learned) →
matched: classified candidate; unmatched & big & LLM on: LLMExplainer →
results list → user selects → confirm → TrashService → deletion of
LLM-classified item triggers LearnedRuleStore.save → post-delete size
refresh.

## Error Handling

- Unreadable paths: skip, collect, surface with Full Disk Access hint.
- LLM CLI errors/timeouts: item stays "unknown", scan continues.
- Trash failures: per-item error shown inline; other items proceed.
- Learned-rules file corrupt: renamed aside, app continues with bundled
  rules, user notified in Settings.

## Testing

- Unit tests (XCTest, `swift test`): RuleEngine pattern matching, risk
  assignment, precedence, staleness logic; LearnedRuleStore round-trip
  and dedupe; LLMExplainer JSON parsing (fixture transcripts, no real
  CLI calls); Scanner against a fixture tree in a temp directory
  (sizes, prune-on-match, skip handling).
- TrashService: integration test against temp files (trash + error
  paths); permanent delete tested against temp files only.
- UI: manual verification via bundled app.

## Non-Goals (v1)

- No scheduled/background scans, no duplicate finder, no launch-at-login,
  no telemetry, no auto-update, no App Store packaging/signing.
