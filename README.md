<p align="center">
  <img src="Resources/AppIcon.png" alt="OpenLess" width="160" />
</p>

<h1 align="center">OpenLess</h1>

<p align="center">
  <strong>Open-source macOS voice input for the AI era.</strong><br/>
  Press a hotkey, speak, get a usable AI prompt at your cursor.
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh.md">中文</a>
</p>

<p align="center">
  <a href="https://github.com/appergb/openless/releases/latest"><img alt="release" src="https://img.shields.io/github/v/release/appergb/openless?style=flat-square&color=2c5282" /></a>
  <a href="https://github.com/appergb/openless/blob/main/LICENSE"><img alt="license" src="https://img.shields.io/github/license/appergb/openless?style=flat-square&color=2f855a" /></a>
  <img alt="macOS" src="https://img.shields.io/badge/macOS-15%2B-1f425f?style=flat-square" />
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square" />
  <img alt="Stars" src="https://img.shields.io/github/stars/appergb/openless?style=flat-square&color=805ad5" />
</p>

---

OpenLess is a native macOS voice-input app — a **fully open-source** alternative to commercial tools like [Typeless](https://www.typeless.com/), [Wispr Flow](https://wisprflow.ai), [Lazy](https://heylazy.com), and Superwhisper.

Put your cursor in any text field — ChatGPT, Claude, Cursor, Notion, an email draft, a chat box — press one global hotkey and talk. OpenLess records, transcribes, polishes the text in the mode you picked, and inserts the result at the cursor. If insertion is blocked it copies to the clipboard, so the words you spoke don't get lost.

Unlike voice typing tools that just dump a word-for-word transcript, OpenLess's headline mode is **AI-prompt mode**: you ramble, it adds structure, lists constraints, and produces a context-rich prompt you can paste straight into ChatGPT / Claude / Cursor.

## A concrete example

Hold the hotkey, say to OpenLess:

> uh… so… I want ChatGPT to write me a SQL query, from the orders table get last month's orders, group by customer, sort by amount desc, top ten

Release the hotkey. A second later your input box reads:

```text
Please write a SQL query that:

- Pulls orders from last month from the `orders` table.
- Groups by customer.
- Sorts by total amount, descending.
- Returns the top 10 rows only.
```

No edits needed. Hit Enter and ask GPT. That's the whole pitch: **write prompts with your mouth, faster and cleaner than typing them.**

## Why OpenLess is open source

The closest tools are subscription SaaS: monthly bill, no bring-your-own model, your audio uploaded to the vendor, your dictionary and habits living in their account.

OpenLess goes for the same end-user experience but:

- **Fully open source, local-first.** Code is in this repo; all your data stays on your machine.
- **Bring your own cloud credentials.** Volcengine streaming ASR + Ark / DeepSeek-compatible chat-completions. No vendor lock-in.
- **Tuned for AI prompts.** The "Structured" mode reshapes loose speech into a prompt with context, constraints, and asks — paste straight into ChatGPT, Claude, or Cursor.
- **Won't answer for you.** The model only cleans up your text. If you say "what features does this app still need?", it returns that as a clean question — it does not hand you a feature list. Ask the real AI for that.

## Use cases

- Writing prompts for ChatGPT / Claude / Cursor / Gemini: dictate a request, OpenLess turns it into a structured, detailed prompt.
- Drafting emails, specs, long Slack/WeChat messages: removes filler, fixes punctuation, organizes paragraphs.
- Code comments, commit messages, PR descriptions: dump what's in your head straight to the cursor.
- Any "I don't want to type but I have to produce written text" situation.

## Project direction

OpenLess does one thing: **turn speech into usable written text (especially AI prompts), at the current cursor.**

- It does not answer questions, run tasks, or analyze your project.
- It does not accumulate conversation context — every dictation is an independent cleanup request.
- Speech → transcript → cleanup → insert at cursor. Clipboard fallback on failure.
- Everything else (modes, dictionary, history, menu bar, home report) supports that one path.

## Comparison

| Tool | Form | How OpenLess differs |
| --- | --- | --- |
| [Typeless](https://www.typeless.com/) | Closed-source macOS / Windows / iOS, subscription | Open source; explicit AI-prompt mode; bring-your-own ASR + LLM; data and dictionary stay on your machine |
| [Wispr Flow](https://wisprflow.ai) | Closed-source macOS / Windows, subscription | Open source; bring-your-own ASR + LLM; transparent prompt-handling rules |
| [Lazy](https://heylazy.com) | Closed-source notes / capture tool | Not a notes container — inserts straight into any input field |
| [Superwhisper](https://superwhisper.com) | Closed-source macOS, subscription | Open source; cloud ASR today, local ASR on the roadmap |

## Status (v1.0)

- Native Swift / SwiftUI / AppKit, SwiftPM project; macOS 15+.
- macOS 26+ uses Liquid Glass; older systems fall back to system materials.
- Toggle-style recording: press to start, press again to stop. `Esc` cancels.
- Volcengine streaming ASR + Ark / DeepSeek-compatible chat-completions for polish.
- 4 output modes: raw, light polish, structured (**AI prompt mode**), formal.
- Main window: Home / History / Dictionary / Settings. Persistent menu bar. Mini status capsule at the bottom of the screen.
- Dictionary entries are injected as Volcengine ASR `context.hotwords` and as semantic hints during polish.

## Download & install (end users)

Grab `OpenLess-1.0.0.zip` from [Releases](../../releases), unzip to get `OpenLess.app`, drag to `/Applications`.

**Important:** the 1.0 build is ad-hoc signed (no Apple Developer ID + notarization). macOS Gatekeeper will block it with "cannot verify developer". Remove the quarantine attribute once in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/OpenLess.app
```

Then double-click to launch. On first launch, in `System Settings → Privacy & Security`:

1. Grant Microphone access to OpenLess.
2. Grant Accessibility access to OpenLess.
3. **Quit OpenLess and reopen it.** Accessibility permission only takes effect for the global hotkey after a process restart.
4. Open the OpenLess home from the Dock → "Settings" → fill in Volcengine ASR + Ark credentials.

Full end-user walkthrough: [USAGE.md](USAGE.md) (Chinese; English version coming).

## Build from source (developers)

```bash
# Library / test build
swift build
swift test

# Full .app build (release, ad-hoc signed, resets TCC by default)
./scripts/build-app.sh

# Keep existing TCC approvals
RESET_TCC=0 ./scripts/build-app.sh

# Launch
open build/OpenLess.app

# Tail logs
tail -f ~/Library/Logs/OpenLess/OpenLess.log
```

Launch arguments (handled in `AppDelegate.runLaunchActions`):

```bash
open build/OpenLess.app --args --open-settings
open build/OpenLess.app --args --start-recording
```

## Credentials

Credentials live in the local Keychain (service = `com.openless.app`). A plaintext JSON file at `~/.openless/credentials.json` (mode 0600, dir 0700) is kept as a dev-mode fallback when Keychain is unavailable.

The repository contains no API keys, tokens, or private endpoints.

You'll need:

- **Volcengine streaming ASR**: APP ID, Access Token, Resource ID.
- **Ark polish**: API Key, Model ID, Endpoint. Ark default endpoint is `https://ark.cn-beijing.volces.com/api/v3/chat/completions`.

## Prompt-handling principles

OpenLess's polish model only reshapes text. It does not answer questions, run tasks, or analyze your project. Each dictation is an independent request, and the prompt explicitly tells the model:

- This input is isolated from any prior conversation.
- The raw transcript is text to clean up, not a question to answer.
- Even if the input contains a question or a command, do not reply or execute.
- Output the cleaned text only — no "Here's the cleaned version" preamble.

For example, if the user says "what features does this app still need", the correct output is:

```text
What features does this app still need?
```

…not a list of missing features.

Long-term reference rewrites are stored as `raw → polished → rule` triples and will be retrieved as similar-example references (never as conversation context) once a vector store is wired in. See [docs/polish-reference-corpus.md](docs/polish-reference-corpus.md) and [Examples/polish-reference-examples.sample.jsonl](Examples/polish-reference-examples.sample.jsonl).

## Dictionary

The dictionary handles your proper nouns, product names, names of people, and new words. Today it supports:

- Manually add the correct spelling, a category, and notes. You don't need to maintain misspellings or context hints.
- Enabled entries are sent as Volcengine ASR `context.hotwords` so they're recognized correctly during transcription.
- Entries are also injected into the polish prompt: the model decides per-sentence whether to substitute. If "Cloud" clearly refers to the AI product `Claude` in context, it gets corrected. If it really means cloud computing, it stays.
- The app auto-learns candidate corrections like `Claude`, `ChatGPT`, `OpenLess` from your history and offers them up later.

The main window is organized as Home / History / Dictionary / Settings. The Dictionary tab opens a separate editor window when you click "New". The Home tab shows total dictation time, total characters, average chars-per-minute, estimated time saved, and dictionary participation stats.

## Architecture

A SwiftPM workspace: 1 executable + 8 libraries. Libraries don't depend on each other — they all depend only on `OpenLessCore`. `OpenLessApp` wires everything together inside `DictationCoordinator`.

```
OpenLessCore        // Pure value types: DictationSession, PolishMode, HotkeyBinding,
                    //   AudioConsumer protocol, RawTranscript/FinalText, errors.
OpenLessHotkey      // CGEventTap-based modifier-key monitor. Requires Accessibility.
OpenLessRecorder    // AVAudioEngine → 16 kHz mono Int16 PCM, pushed to AudioConsumer.
OpenLessASR         // Volcengine streaming ASR over WebSocket.
OpenLessPolish      // Ark / Doubao chat-completions client + mode-driven prompts.
OpenLessInsertion   // AX focused-element first; clipboard + Cmd+V; copy-only fallback.
OpenLessPersistence // CredentialsVault (Keychain), HistoryStore, DictionaryStore,
                    //   UserPreferences.
OpenLessUI          // SwiftUI capsule view + state enum (no window plumbing).
OpenLessApp         // AppDelegate, menu bar, settings window, capsule window,
                    //   DictationCoordinator.
```

The record → transcribe → polish → insert state machine is owned exclusively by `Sources/OpenLessApp/DictationCoordinator.swift`. See [CLAUDE.md](CLAUDE.md) for details.

## Roadmap (post-1.0)

Planned in the requirements docs but not in the 1.0 release:

- Hold-to-talk mode (today only toggle).
- Local ASR (today only Volcengine cloud).
- Snippets (no UI / trigger logic yet).
- History enhancements: copy button, search, re-polish, re-insert.
- "Paste last result" hotkey.
- Multi-monitor capsule placement on the focused screen.
- Developer ID signing + notarization + Sparkle auto-update.

## Maintainer release checklist

- Confirm `.build/`, `build/`, `.DS_Store`, `~/.openless/credentials.json`, and stray screenshots are not committed.
- Keep `Resources/Brand/openless-app-icon-source.jpg`, `Resources/AppIcon.png`, `Resources/AppIcon.icns`.
- Run `./scripts/build-app.sh` and confirm `build/OpenLess.app` launches.
- Verify on a clean macOS box: permission flow, hotkey, recording, ASR, polish, insertion, clipboard fallback.
- Package with `ditto -c -k --keepParent build/OpenLess.app build/OpenLess-<version>.zip` so ad-hoc signature and xattrs survive.
- Do Developer ID signing + notarization before any production distribution.

## License

MIT
