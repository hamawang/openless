# Windows Local ASR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Windows-only `foundry-local-whisper` ASR provider so new Windows users can dictate through OpenLess without external ASR keys or Windows Win+H Voice Typing.

**Architecture:** Keep `coordinator::Coordinator` as the single owner of dictation state. Add a Windows Foundry Local Whisper provider that buffers existing recorder PCM, transcribes it locally, then returns `RawTranscript` into the existing polish, Windows TSF IME insertion, and history pipeline.

**Tech Stack:** Tauri 2, Rust, React/TypeScript, Foundry Local Rust SDK, reqwest multipart REST call to local `/v1/audio/transcriptions`, existing Windows TSF IME backend.

---

## File Map

- Modify `openless-all/app/src-tauri/Cargo.toml`: add Windows-only Foundry Local SDK dependency after a compile probe.
- Create `openless-all/app/src-tauri/src/asr/wav.rs`: shared WAV encoder for Whisper HTTP and Foundry Local.
- Modify `openless-all/app/src-tauri/src/asr/mod.rs`: export `wav` and Windows Foundry Local modules.
- Modify `openless-all/app/src-tauri/src/asr/whisper.rs`: use the shared WAV encoder.
- Create `openless-all/app/src-tauri/src/asr/local/foundry.rs`: provider id, model registry, runtime status structs, and Windows runtime/proxy exports.
- Create `openless-all/app/src-tauri/src/asr/local/foundry_runtime.rs`: Windows-only Foundry Local SDK wrapper for model status, download, load, endpoint discovery, and local transcription.
- Create `openless-all/app/src-tauri/src/asr/local/foundry_provider.rs`: `FoundryLocalWhisperAsr` implementing `AudioConsumer` and producing `RawTranscript`.
- Modify `openless-all/app/src-tauri/src/asr/local/mod.rs`: keep Qwen3 macOS exports and add Foundry Whisper exports.
- Modify `openless-all/app/src-tauri/src/types.rs`: add Windows local ASR preferences and Windows default provider.
- Modify `openless-all/app/src-tauri/src/persistence.rs`: align credentials active ASR default with Windows local ASR for new installs.
- Modify `openless-all/app/src-tauri/src/commands.rs`: expose Foundry Local settings/status/download/test commands and ASR credential status.
- Modify `openless-all/app/src-tauri/src/lib.rs`: manage a shared Foundry Local runtime and register commands.
- Modify `openless-all/app/src-tauri/src/coordinator.rs`: add `ActiveAsr::FoundryLocalWhisper`, provider startup, transcribe branch, timeout, cancel, and preload/release hooks.
- Modify `openless-all/app/src/lib/localAsr.ts`: add Foundry Local IPC types and wrapper functions.
- Modify `openless-all/app/src/lib/types.ts` and `openless-all/app/src/lib/ipc.ts`: add preferences/mock defaults.
- Modify `openless-all/app/src/pages/Settings.tsx`: add `foundry-local-whisper` provider preset and local ASR hint behavior.
- Modify `openless-all/app/src/pages/LocalAsr.tsx`: show Windows Foundry Local model/runtime controls alongside macOS Qwen3.
- Modify `openless-all/app/src/i18n/zh-CN.ts` and `openless-all/app/src/i18n/en.ts`: add user-facing strings.
- Modify `openless-all/app/scripts/windows-real-asr-insertion-smoke.ps1`: add a local ASR mode that does not require Volcengine credentials.

## Implementation Tasks

### Task 1: Shared WAV Encoder

**Files:**
- Create: `openless-all/app/src-tauri/src/asr/wav.rs`
- Modify: `openless-all/app/src-tauri/src/asr/mod.rs`
- Modify: `openless-all/app/src-tauri/src/asr/whisper.rs`

- [ ] **Step 1: Write the shared WAV encoder tests**

Add this file:

```rust
//! WAV helpers for ASR providers that accept complete audio files.

/// Encode 16 kHz / mono / 16-bit little-endian PCM as a RIFF WAV file.
pub fn encode_wav_16k_mono(pcm: &[u8]) -> Vec<u8> {
    let sample_rate: u32 = 16_000;
    let num_channels: u16 = 1;
    let bits_per_sample: u16 = 16;
    let byte_rate = sample_rate * num_channels as u32 * (bits_per_sample as u32 / 8);
    let block_align = num_channels * (bits_per_sample / 8);
    let data_size = pcm.len() as u32;
    let chunk_size = 36 + data_size;

    let mut wav = Vec::with_capacity(44 + pcm.len());
    wav.extend_from_slice(b"RIFF");
    wav.extend_from_slice(&chunk_size.to_le_bytes());
    wav.extend_from_slice(b"WAVE");
    wav.extend_from_slice(b"fmt ");
    wav.extend_from_slice(&16u32.to_le_bytes());
    wav.extend_from_slice(&1u16.to_le_bytes());
    wav.extend_from_slice(&num_channels.to_le_bytes());
    wav.extend_from_slice(&sample_rate.to_le_bytes());
    wav.extend_from_slice(&byte_rate.to_le_bytes());
    wav.extend_from_slice(&block_align.to_le_bytes());
    wav.extend_from_slice(&bits_per_sample.to_le_bytes());
    wav.extend_from_slice(b"data");
    wav.extend_from_slice(&data_size.to_le_bytes());
    wav.extend_from_slice(pcm);
    wav
}

#[cfg(test)]
mod tests {
    use super::encode_wav_16k_mono;

    #[test]
    fn wav_header_matches_16k_mono_pcm() {
        let pcm = [0x01, 0x00, 0xff, 0x7f];
        let wav = encode_wav_16k_mono(&pcm);

        assert_eq!(&wav[0..4], b"RIFF");
        assert_eq!(u32::from_le_bytes(wav[4..8].try_into().unwrap()), 40);
        assert_eq!(&wav[8..12], b"WAVE");
        assert_eq!(&wav[12..16], b"fmt ");
        assert_eq!(u16::from_le_bytes(wav[20..22].try_into().unwrap()), 1);
        assert_eq!(u16::from_le_bytes(wav[22..24].try_into().unwrap()), 1);
        assert_eq!(u32::from_le_bytes(wav[24..28].try_into().unwrap()), 16_000);
        assert_eq!(u16::from_le_bytes(wav[34..36].try_into().unwrap()), 16);
        assert_eq!(&wav[36..40], b"data");
        assert_eq!(u32::from_le_bytes(wav[40..44].try_into().unwrap()), 4);
        assert_eq!(&wav[44..], &pcm);
    }
}
```

- [ ] **Step 2: Run the new unit test and verify the module is not wired yet**

Run:

```powershell
cargo test --manifest-path openless-all/app/src-tauri/Cargo.toml wav_header_matches_16k_mono_pcm
```

Expected: FAIL with an unresolved module only if `wav.rs` has not been registered yet.

- [ ] **Step 3: Register the module and replace Whisper's private encoder**

In `openless-all/app/src-tauri/src/asr/mod.rs`, add:

```rust
pub mod wav;
```

In `openless-all/app/src-tauri/src/asr/whisper.rs`, add:

```rust
use crate::asr::wav::encode_wav_16k_mono;
```

Then remove the private `fn encode_wav_16k_mono(pcm: &[u8]) -> Vec<u8>` from the bottom of `whisper.rs`.

- [ ] **Step 4: Run the WAV test**

Run:

```powershell
cargo test --manifest-path openless-all/app/src-tauri/Cargo.toml wav_header_matches_16k_mono_pcm
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add -- openless-all/app/src-tauri/src/asr/mod.rs openless-all/app/src-tauri/src/asr/whisper.rs openless-all/app/src-tauri/src/asr/wav.rs
git commit -m "refactor(asr): share wav encoding"
```

### Task 2: Provider Constants, Preferences, and Defaults

**Files:**
- Create: `openless-all/app/src-tauri/src/asr/local/foundry.rs`
- Modify: `openless-all/app/src-tauri/src/asr/local/mod.rs`
- Modify: `openless-all/app/src-tauri/src/types.rs`
- Modify: `openless-all/app/src-tauri/src/persistence.rs`
- Modify: `openless-all/app/src/lib/types.ts`
- Modify: `openless-all/app/src/lib/ipc.ts`

- [ ] **Step 1: Add provider constants and model registry**

Create `openless-all/app/src-tauri/src/asr/local/foundry.rs`:

```rust
use serde::Serialize;

pub const PROVIDER_ID: &str = "foundry-local-whisper";
pub const DEFAULT_MODEL_ALIAS: &str = "whisper-small";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FoundryWhisperModel {
    pub alias: &'static str,
    pub display_name: &'static str,
    pub quality_tier: &'static str,
}

pub const MODELS: &[FoundryWhisperModel] = &[
    FoundryWhisperModel {
        alias: "whisper-small",
        display_name: "Whisper Small",
        quality_tier: "balanced",
    },
    FoundryWhisperModel {
        alias: "whisper-base",
        display_name: "Whisper Base",
        quality_tier: "low-resource",
    },
    FoundryWhisperModel {
        alias: "whisper-tiny",
        display_name: "Whisper Tiny",
        quality_tier: "smoke-test",
    },
];

pub fn is_foundry_local_whisper(id: &str) -> bool {
    id == PROVIDER_ID
}

pub fn model_alias_is_known(alias: &str) -> bool {
    MODELS.iter().any(|model| model.alias == alias)
}

pub fn default_language_hint() -> Option<String> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn provider_id_is_stable() {
        assert!(is_foundry_local_whisper("foundry-local-whisper"));
        assert!(!is_foundry_local_whisper("local-qwen3"));
    }

    #[test]
    fn default_model_is_registered() {
        assert!(model_alias_is_known(DEFAULT_MODEL_ALIAS));
    }
}
```

- [ ] **Step 2: Export the Foundry module**

In `openless-all/app/src-tauri/src/asr/local/mod.rs`, add:

```rust
pub mod foundry;
```

- [ ] **Step 3: Add Rust preferences**

In `openless-all/app/src-tauri/src/types.rs`, add fields to `UserPreferences` after `local_asr_keep_loaded_secs`:

```rust
/// Windows Foundry Local Whisper 当前激活的模型 alias。
#[serde(default = "default_foundry_local_asr_model")]
pub foundry_local_asr_model: String,
/// Windows Foundry Local Whisper 语言 hint。空串 = 自动检测。
#[serde(default)]
pub foundry_local_asr_language_hint: String,
/// Windows Foundry Local Whisper 模型在 runtime 中保持加载多久。
#[serde(default = "default_local_asr_keep_loaded_secs")]
pub foundry_local_asr_keep_loaded_secs: u32,
```

Add the default helper:

```rust
fn default_foundry_local_asr_model() -> String {
    crate::asr::local::foundry::DEFAULT_MODEL_ALIAS.into()
}
```

Update `impl Default for UserPreferences`:

```rust
active_asr_provider: default_active_asr_provider(),
foundry_local_asr_model: default_foundry_local_asr_model(),
foundry_local_asr_language_hint: String::new(),
foundry_local_asr_keep_loaded_secs: default_local_asr_keep_loaded_secs(),
```

Add this helper near the existing preference defaults:

```rust
fn default_active_asr_provider() -> String {
    #[cfg(target_os = "windows")]
    {
        return crate::asr::local::foundry::PROVIDER_ID.into();
    }
    #[cfg(not(target_os = "windows"))]
    {
        "volcengine".into()
    }
}
```

- [ ] **Step 4: Align credentials active ASR default**

In `openless-all/app/src-tauri/src/persistence.rs`, replace `creds_default_asr()` with:

```rust
fn creds_default_asr() -> String {
    #[cfg(target_os = "windows")]
    {
        return crate::asr::local::foundry::PROVIDER_ID.into();
    }
    #[cfg(not(target_os = "windows"))]
    {
        "volcengine".into()
    }
}
```

- [ ] **Step 5: Add TypeScript preference fields**

In `openless-all/app/src/lib/types.ts`, add:

```ts
  foundryLocalAsrModel: string;
  foundryLocalAsrLanguageHint: string;
  foundryLocalAsrKeepLoadedSecs: number;
```

In `openless-all/app/src/lib/ipc.ts`, update mock defaults:

```ts
  activeAsrProvider: 'foundry-local-whisper',
  foundryLocalAsrModel: 'whisper-small',
  foundryLocalAsrLanguageHint: '',
  foundryLocalAsrKeepLoadedSecs: 300,
```

- [ ] **Step 6: Run default and provider tests**

Run:

```powershell
cargo test --manifest-path openless-all/app/src-tauri/Cargo.toml provider_id_is_stable default_model_is_registered
npm --prefix openless-all/app run build
```

Expected: Rust tests PASS; TypeScript build PASS.

- [ ] **Step 7: Commit**

```powershell
git add -- openless-all/app/src-tauri/src/asr/local/foundry.rs openless-all/app/src-tauri/src/asr/local/mod.rs openless-all/app/src-tauri/src/types.rs openless-all/app/src-tauri/src/persistence.rs openless-all/app/src/lib/types.ts openless-all/app/src/lib/ipc.ts
git commit -m "feat(asr): add Foundry local provider defaults"
```

### Task 3: Foundry Runtime Compile Probe

**Files:**
- Modify: `openless-all/app/src-tauri/Cargo.toml`
- Create: `openless-all/app/src-tauri/src/asr/local/foundry_runtime.rs`
- Modify: `openless-all/app/src-tauri/src/asr/local/foundry.rs`
- Modify: `openless-all/app/src-tauri/src/asr/local/mod.rs`

- [ ] **Step 1: Add the official Windows SDK dependency**

Run:

```powershell
cd openless-all/app/src-tauri
cargo add foundry-local-sdk --features winml --target 'cfg(target_os = "windows")'
```

Expected: `Cargo.toml` gains a Windows-only `foundry-local-sdk` dependency and `Cargo.lock` is updated.

- [ ] **Step 2: Add runtime status types**

Append to `openless-all/app/src-tauri/src/asr/local/foundry.rs`:

```rust
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FoundryRuntimeStatus {
    pub provider_id: String,
    pub available: bool,
    pub active_model: String,
    pub loaded_model_id: Option<String>,
    pub endpoint: Option<String>,
    pub error: Option<String>,
}

impl FoundryRuntimeStatus {
    pub fn unavailable(active_model: String, error: impl Into<String>) -> Self {
        Self {
            provider_id: PROVIDER_ID.into(),
            available: false,
            active_model,
            loaded_model_id: None,
            endpoint: None,
            error: Some(error.into()),
        }
    }
}
```

- [ ] **Step 3: Add the minimal Windows runtime wrapper**

Create `openless-all/app/src-tauri/src/asr/local/foundry_runtime.rs`:

```rust
#[cfg(target_os = "windows")]
mod imp {
    use anyhow::{Context, Result};
    use parking_lot::Mutex;

    use super::super::foundry::{FoundryRuntimeStatus, PROVIDER_ID};
    use foundry_local_sdk::{FoundryLocalConfig, FoundryLocalManager};

    #[derive(Debug, Clone)]
    struct LoadedModel {
        alias: String,
        model_id: String,
        endpoint: String,
    }

    pub struct FoundryLocalRuntime {
        loaded: Mutex<Option<LoadedModel>>,
    }

    impl Default for FoundryLocalRuntime {
        fn default() -> Self {
            Self::new()
        }
    }

    impl FoundryLocalRuntime {
        pub fn new() -> Self {
            Self {
                loaded: Mutex::new(None),
            }
        }

        pub fn status_snapshot(&self, active_model: &str) -> FoundryRuntimeStatus {
            let loaded = self.loaded.lock().clone();
            FoundryRuntimeStatus {
                provider_id: PROVIDER_ID.into(),
                available: true,
                active_model: active_model.to_string(),
                loaded_model_id: loaded.as_ref().map(|model| model.model_id.clone()),
                endpoint: loaded.as_ref().map(|model| model.endpoint.clone()),
                error: None,
            }
        }

        pub async fn ensure_loaded(&self, alias: &str) -> Result<(String, String)> {
            if let Some(loaded) = self.loaded.lock().as_ref() {
                if loaded.alias == alias {
                    return Ok((loaded.model_id.clone(), loaded.endpoint.clone()));
                }
            }

            let manager =
                FoundryLocalManager::create(FoundryLocalConfig::new("openless"))
                    .context("initialize Foundry Local manager")?;
            manager
                .download_and_register_eps_with_progress(None, |_ep, _percent| {})
                .await
                .context("download/register Foundry execution providers")?;
            let model = manager
                .catalog()
                .get_model(alias)
                .await
                .with_context(|| format!("get Foundry model {alias}"))?;
            if !model.is_cached().await.context("check Foundry model cache")? {
                model.download(Some(|_percent| {})).await.context("download Foundry model")?;
            }
            model.load().await.context("load Foundry model")?;
            manager.start_web_service().await.context("start Foundry web service")?;
            let endpoint = manager
                .urls()
                .context("read Foundry web service urls")?
                .first()
                .cloned()
                .context("Foundry web service returned no endpoint")?;
            let model_id = model.id().to_string();

            *self.loaded.lock() = Some(LoadedModel {
                alias: alias.to_string(),
                model_id: model_id.clone(),
                endpoint: endpoint.clone(),
            });
            Ok((model_id, endpoint))
        }

        pub fn release_now(&self) {
            self.loaded.lock().take();
        }
    }
}

#[cfg(target_os = "windows")]
pub use imp::FoundryLocalRuntime;

#[cfg(not(target_os = "windows"))]
pub struct FoundryLocalRuntime;

#[cfg(not(target_os = "windows"))]
impl FoundryLocalRuntime {
    pub fn new() -> Self {
        Self
    }

    pub fn status_snapshot(
        &self,
        active_model: &str,
    ) -> super::foundry::FoundryRuntimeStatus {
        super::foundry::FoundryRuntimeStatus::unavailable(
            active_model.to_string(),
            "Foundry Local Whisper is only available on Windows",
        )
    }

    pub fn release_now(&self) {}
}
```

- [ ] **Step 4: Export the runtime**

In `openless-all/app/src-tauri/src/asr/local/mod.rs`, add:

```rust
pub mod foundry_runtime;
pub use foundry_runtime::FoundryLocalRuntime;
```

- [ ] **Step 5: Compile-check the SDK API**

Run:

```powershell
cargo check --manifest-path openless-all/app/src-tauri/Cargo.toml
```

Expected: PASS. If the Foundry SDK names differ from Microsoft Learn, update only `foundry_runtime.rs` and rerun until this command passes before continuing.

- [ ] **Step 6: Commit**

```powershell
git add -- openless-all/app/src-tauri/Cargo.toml openless-all/app/src-tauri/Cargo.lock openless-all/app/src-tauri/src/asr/local/foundry.rs openless-all/app/src-tauri/src/asr/local/foundry_runtime.rs openless-all/app/src-tauri/src/asr/local/mod.rs
git commit -m "feat(asr): add Foundry local runtime wrapper"
```

### Task 4: Foundry Local Whisper Provider

**Files:**
- Create: `openless-all/app/src-tauri/src/asr/local/foundry_provider.rs`
- Modify: `openless-all/app/src-tauri/src/asr/local/mod.rs`

- [ ] **Step 1: Add provider with fakeable HTTP transcription**

Create `openless-all/app/src-tauri/src/asr/local/foundry_provider.rs`:

```rust
#[cfg(target_os = "windows")]
use std::sync::Arc;

use anyhow::{Context, Result};
use parking_lot::Mutex;

use crate::asr::wav::encode_wav_16k_mono;
use crate::asr::RawTranscript;

#[cfg(target_os = "windows")]
use super::foundry_runtime::FoundryLocalRuntime;

pub struct FoundryLocalWhisperAsr {
    #[cfg(target_os = "windows")]
    runtime: Arc<FoundryLocalRuntime>,
    model_alias: String,
    language_hint: Option<String>,
    buffer: Mutex<Vec<u8>>,
    client: reqwest::Client,
}

impl FoundryLocalWhisperAsr {
    #[cfg(target_os = "windows")]
    pub fn new(
        runtime: Arc<FoundryLocalRuntime>,
        model_alias: String,
        language_hint: Option<String>,
    ) -> Self {
        Self {
            runtime,
            model_alias,
            language_hint,
            buffer: Mutex::new(Vec::new()),
            client: reqwest::Client::new(),
        }
    }

    pub async fn transcribe(&self) -> Result<RawTranscript> {
        let pcm = self.buffer.lock().clone();
        if pcm.is_empty() {
            return Ok(RawTranscript {
                text: String::new(),
                duration_ms: 0,
            });
        }
        let duration_ms = (pcm.len() as u64 / 2) * 1000 / 16_000;
        let raw = self.transcribe_pcm(&pcm).await?;
        self.buffer.lock().clear();
        Ok(RawTranscript {
            text: raw.trim().to_string(),
            duration_ms,
        })
    }

    #[cfg(target_os = "windows")]
    async fn transcribe_pcm(&self, pcm: &[u8]) -> Result<String> {
        let (model_id, endpoint) = self.runtime.ensure_loaded(&self.model_alias).await?;
        self.post_transcription(&endpoint, &model_id, pcm).await
    }

    #[cfg(not(target_os = "windows"))]
    async fn transcribe_pcm(&self, _pcm: &[u8]) -> Result<String> {
        anyhow::bail!("Foundry Local Whisper is only available on Windows")
    }

    async fn post_transcription(
        &self,
        endpoint: &str,
        model_id: &str,
        pcm: &[u8],
    ) -> Result<String> {
        let wav = encode_wav_16k_mono(pcm);
        let wav_part = reqwest::multipart::Part::bytes(wav)
            .file_name("openless-foundry.wav")
            .mime_str("audio/wav")
            .context("set Foundry transcription MIME type")?;
        let mut form = reqwest::multipart::Form::new()
            .part("file", wav_part)
            .text("model", model_id.to_string())
            .text("response_format", "json".to_string());
        if let Some(language) = self.language_hint.as_deref().filter(|s| !s.trim().is_empty()) {
            form = form.text("language", language.to_string());
        }
        let url = format!("{}/v1/audio/transcriptions", endpoint.trim_end_matches('/'));
        let response = self
            .client
            .post(url)
            .multipart(form)
            .send()
            .await
            .context("Foundry Local transcription request failed")?;
        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            anyhow::bail!("Foundry Local transcription HTTP {status}: {body}");
        }
        let json: serde_json::Value = response
            .json()
            .await
            .context("parse Foundry Local transcription response")?;
        Ok(json["text"].as_str().unwrap_or("").to_string())
    }

    pub fn cancel(&self) {
        self.buffer.lock().clear();
    }
}

impl crate::recorder::AudioConsumer for FoundryLocalWhisperAsr {
    fn consume_pcm_chunk(&self, pcm: &[u8]) {
        self.buffer.lock().extend_from_slice(pcm);
    }
}
```

- [ ] **Step 2: Export the provider**

In `openless-all/app/src-tauri/src/asr/local/mod.rs`, add:

```rust
pub mod foundry_provider;
pub use foundry_provider::FoundryLocalWhisperAsr;
```

- [ ] **Step 3: Run cargo check**

Run:

```powershell
cargo check --manifest-path openless-all/app/src-tauri/Cargo.toml
```

Expected: PASS.

- [ ] **Step 4: Commit**

```powershell
git add -- openless-all/app/src-tauri/src/asr/local/foundry_provider.rs openless-all/app/src-tauri/src/asr/local/mod.rs
git commit -m "feat(asr): add Foundry local Whisper provider"
```

### Task 5: Backend Commands and Runtime State

**Files:**
- Modify: `openless-all/app/src-tauri/src/commands.rs`
- Modify: `openless-all/app/src-tauri/src/lib.rs`

- [ ] **Step 1: Manage runtime in Tauri**

In `openless-all/app/src-tauri/src/lib.rs`, after the local Qwen download manager:

```rust
let foundry_local_runtime = Arc::new(asr::local::FoundryLocalRuntime::new());
```

Add `.manage(foundry_local_runtime.clone())` to the Tauri builder.

- [ ] **Step 2: Add command result type and status command**

In `commands.rs`, import:

```rust
use crate::asr::local::foundry::{
    model_alias_is_known, FoundryRuntimeStatus, DEFAULT_MODEL_ALIAS,
    PROVIDER_ID as FOUNDRY_LOCAL_PROVIDER_ID,
};
use crate::asr::local::FoundryLocalRuntime;
```

Add commands:

```rust
#[tauri::command]
pub fn foundry_local_asr_status(
    coord: CoordinatorState<'_>,
    runtime: State<'_, Arc<FoundryLocalRuntime>>,
) -> FoundryRuntimeStatus {
    let prefs = coord.prefs().get();
    let active_model = if model_alias_is_known(&prefs.foundry_local_asr_model) {
        prefs.foundry_local_asr_model
    } else {
        DEFAULT_MODEL_ALIAS.to_string()
    };
    runtime.status_snapshot(&active_model)
}

#[tauri::command]
pub fn foundry_local_asr_set_model(
    coord: CoordinatorState<'_>,
    model_alias: String,
) -> Result<(), String> {
    if !model_alias_is_known(&model_alias) {
        return Err(format!("unknown Foundry Whisper model alias: {model_alias}"));
    }
    let mut prefs = coord.prefs().get();
    prefs.foundry_local_asr_model = model_alias;
    coord.prefs().set(prefs).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn foundry_local_asr_set_language_hint(
    coord: CoordinatorState<'_>,
    language_hint: String,
) -> Result<(), String> {
    let normalized = language_hint.trim().to_string();
    if !normalized.is_empty()
        && (normalized.len() != 2 || !normalized.bytes().all(|b| b.is_ascii_lowercase()))
    {
        return Err("language hint must be empty or ISO 639-1 lowercase code".to_string());
    }
    let mut prefs = coord.prefs().get();
    prefs.foundry_local_asr_language_hint = normalized;
    coord.prefs().set(prefs).map_err(|e| e.to_string())
}
```

- [ ] **Step 3: Make credential status treat Foundry as credential-free**

In `asr_configured_for_provider`, add:

```rust
if provider == FOUNDRY_LOCAL_PROVIDER_ID {
    return true;
}
```

- [ ] **Step 4: Register commands**

In `lib.rs` `invoke_handler`, add:

```rust
commands::foundry_local_asr_status,
commands::foundry_local_asr_set_model,
commands::foundry_local_asr_set_language_hint,
```

- [ ] **Step 5: Add command tests**

In `commands.rs` tests, add:

```rust
#[test]
fn credentials_status_treats_foundry_local_asr_as_configured() {
    assert!(asr_configured_for_provider(
        crate::asr::local::foundry::PROVIDER_ID,
        &CredentialsSnapshot::default()
    ));
}
```

- [ ] **Step 6: Run tests and build**

Run:

```powershell
cargo test --manifest-path openless-all/app/src-tauri/Cargo.toml credentials_status_treats_foundry_local_asr_as_configured
cargo check --manifest-path openless-all/app/src-tauri/Cargo.toml
```

Expected: PASS.

- [ ] **Step 7: Commit**

```powershell
git add -- openless-all/app/src-tauri/src/commands.rs openless-all/app/src-tauri/src/lib.rs
git commit -m "feat(asr): expose Foundry local ASR status"
```

### Task 6: Coordinator Integration

**Files:**
- Modify: `openless-all/app/src-tauri/src/coordinator.rs`

- [ ] **Step 1: Add runtime to `Inner`**

Import Foundry types:

```rust
#[cfg(target_os = "windows")]
use crate::asr::local::{foundry, FoundryLocalRuntime, FoundryLocalWhisperAsr};
```

Add field to `Inner`:

```rust
#[cfg(target_os = "windows")]
foundry_local_runtime: Arc<FoundryLocalRuntime>,
```

Initialize it in `Coordinator::new()`:

```rust
#[cfg(target_os = "windows")]
foundry_local_runtime: Arc::new(FoundryLocalRuntime::new()),
```

- [ ] **Step 2: Add active ASR variant**

Add to `ActiveAsr`:

```rust
#[cfg(target_os = "windows")]
FoundryLocalWhisper(Arc<FoundryLocalWhisperAsr>),
```

Update `cancel_active_asr`:

```rust
#[cfg(target_os = "windows")]
ActiveAsr::FoundryLocalWhisper(local) => local.cancel(),
```

- [ ] **Step 3: Start Foundry local provider in `begin_session`**

After `let active_asr = CredentialsVault::get_active_asr();`, add before Whisper-compatible branch:

```rust
#[cfg(target_os = "windows")]
if foundry::is_foundry_local_whisper(&active_asr) {
    let prefs = inner.prefs.get();
    let model_alias = if foundry::model_alias_is_known(&prefs.foundry_local_asr_model) {
        prefs.foundry_local_asr_model.clone()
    } else {
        foundry::DEFAULT_MODEL_ALIAS.to_string()
    };
    let language_hint = prefs
        .foundry_local_asr_language_hint
        .trim()
        .to_string();
    let language_hint = if language_hint.is_empty() {
        None
    } else {
        Some(language_hint)
    };
    let local = Arc::new(FoundryLocalWhisperAsr::new(
        Arc::clone(&inner.foundry_local_runtime),
        model_alias,
        language_hint,
    ));
    store_asr_for_session(
        inner,
        current_session_id,
        ActiveAsr::FoundryLocalWhisper(Arc::clone(&local)),
    );
    let consumer: Arc<dyn crate::recorder::AudioConsumer> = local;
    start_recorder_and_enter_listening(inner, current_session_id, &active_asr, consumer)
        .await?;
    return Ok(());
}
```

- [ ] **Step 4: Transcribe Foundry local results in `end_session`**

Add a match branch next to `ActiveAsr::Whisper`:

```rust
#[cfg(target_os = "windows")]
ActiveAsr::FoundryLocalWhisper(local) => {
    let timeout_duration = std::time::Duration::from_secs(COORDINATOR_GLOBAL_TIMEOUT_SECS);
    match tokio::time::timeout(timeout_duration, local.transcribe()).await {
        Ok(Ok(r)) => r,
        Ok(Err(e)) => {
            log::error!("[coord] Foundry Local Whisper transcribe failed: {e:#}");
            emit_capsule(
                inner,
                CapsuleState::Error,
                0.0,
                elapsed,
                Some(format!("本地识别失败: {e}")),
                None,
            );
            restore_prepared_windows_ime_session(inner, current_session_id);
            inner.state.lock().phase = SessionPhase::Idle;
            schedule_capsule_idle(inner, CAPSULE_AUTO_HIDE_DELAY_MS);
            return Err(e.to_string());
        }
        Err(_) => {
            log::error!(
                "[coord] Foundry Local Whisper 全局超时 {} 秒",
                COORDINATOR_GLOBAL_TIMEOUT_SECS
            );
            emit_capsule(
                inner,
                CapsuleState::Error,
                0.0,
                elapsed,
                Some("识别超时".to_string()),
                None,
            );
            restore_prepared_windows_ime_session(inner, current_session_id);
            inner.state.lock().phase = SessionPhase::Idle;
            schedule_capsule_idle(inner, CAPSULE_AUTO_HIDE_DELAY_MS);
            return Err("foundry local global timeout".to_string());
        }
    }
}
```

- [ ] **Step 5: Relax ASR credential gate**

In `ensure_asr_credentials`, add before local Qwen3:

```rust
#[cfg(target_os = "windows")]
if foundry::is_foundry_local_whisper(&active_asr) {
    return Ok(());
}
```

- [ ] **Step 6: Add coordinator tests for fallback routing**

Add tests in `coordinator.rs` tests:

```rust
#[test]
fn foundry_local_provider_is_not_whisper_compatible_cloud_provider() {
    assert!(!is_whisper_compatible_provider(
        crate::asr::local::foundry::PROVIDER_ID
    ));
}
```

- [ ] **Step 7: Run backend checks**

Run:

```powershell
cargo test --manifest-path openless-all/app/src-tauri/Cargo.toml foundry_local_provider_is_not_whisper_compatible_cloud_provider
cargo check --manifest-path openless-all/app/src-tauri/Cargo.toml
```

Expected: PASS.

- [ ] **Step 8: Commit**

```powershell
git add -- openless-all/app/src-tauri/src/coordinator.rs
git commit -m "feat(asr): route dictation through Foundry local Whisper"
```

### Task 7: Frontend IPC and Settings Provider

**Files:**
- Modify: `openless-all/app/src/lib/localAsr.ts`
- Modify: `openless-all/app/src/pages/Settings.tsx`
- Modify: `openless-all/app/src/i18n/zh-CN.ts`
- Modify: `openless-all/app/src/i18n/en.ts`

- [ ] **Step 1: Add TypeScript IPC wrappers**

In `openless-all/app/src/lib/localAsr.ts`, add:

```ts
export interface FoundryLocalAsrStatus {
  providerId: string;
  available: boolean;
  activeModel: string;
  loadedModelId: string | null;
  endpoint: string | null;
  error: string | null;
}

export function getFoundryLocalAsrStatus(): Promise<FoundryLocalAsrStatus> {
  return invokeOrMock('foundry_local_asr_status', undefined, () => ({
    providerId: 'foundry-local-whisper',
    available: true,
    activeModel: 'whisper-small',
    loadedModelId: null,
    endpoint: null,
    error: null,
  }));
}

export function setFoundryLocalAsrModel(modelAlias: string): Promise<void> {
  return invokeOrMock('foundry_local_asr_set_model', { modelAlias }, () => undefined);
}

export function setFoundryLocalAsrLanguageHint(languageHint: string): Promise<void> {
  return invokeOrMock(
    'foundry_local_asr_set_language_hint',
    { languageHint },
    () => undefined,
  );
}
```

- [ ] **Step 2: Add provider preset**

In `Settings.tsx`, add to `ASR_PRESETS` before `local-qwen3`:

```ts
{ id: 'foundry-local-whisper', nameKey: 'asrFoundryLocalWhisper', baseUrl: '', model: '' },
```

Update the union type automatically via `as const`.

- [ ] **Step 3: Render local provider hint**

Change:

```tsx
) : committedAsrProvider === 'local-qwen3' ? (
  <LocalAsrProviderHint />
) : (
```

to:

```tsx
) : committedAsrProvider === 'local-qwen3' || committedAsrProvider === 'foundry-local-whisper' ? (
  <LocalAsrProviderHint provider={committedAsrProvider} />
) : (
```

Change `LocalAsrProviderHint` signature:

```tsx
function LocalAsrProviderHint({ provider }: { provider: 'local-qwen3' | 'foundry-local-whisper' }) {
```

Use provider-specific text:

```tsx
const hintKey = provider === 'foundry-local-whisper'
  ? 'settings.providers.foundryLocalAsrHint'
  : 'settings.providers.localAsrHint';
```

- [ ] **Step 4: Add i18n strings**

In `zh-CN.ts` under `settings.providers.presets`:

```ts
asrFoundryLocalWhisper: '本地 Whisper（Foundry Local）',
```

Under `settings.providers`:

```ts
foundryLocalAsrHint: 'Windows 本地 Whisper 在本机运行，无需 ASR API Key。首次使用需下载 Foundry Local 运行组件和 Whisper 模型；LLM 润色仍按你配置的模型供应商调用。',
```

In `en.ts` add:

```ts
asrFoundryLocalWhisper: 'Local Whisper (Foundry Local)',
foundryLocalAsrHint: 'Windows local Whisper runs on this device and does not need an ASR API key. First use downloads Foundry Local runtime components and a Whisper model; LLM polishing still uses your configured LLM provider.',
```

- [ ] **Step 5: Build frontend**

Run:

```powershell
npm --prefix openless-all/app run build
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add -- openless-all/app/src/lib/localAsr.ts openless-all/app/src/pages/Settings.tsx openless-all/app/src/i18n/zh-CN.ts openless-all/app/src/i18n/en.ts
git commit -m "feat(ui): add Foundry local ASR provider"
```

### Task 8: Local ASR Page for Windows Foundry Models

**Files:**
- Modify: `openless-all/app/src/pages/LocalAsr.tsx`
- Modify: `openless-all/app/src/i18n/zh-CN.ts`
- Modify: `openless-all/app/src/i18n/en.ts`

- [ ] **Step 1: Load Foundry status on Local ASR page**

In `LocalAsr.tsx`, import:

```ts
getFoundryLocalAsrStatus,
setFoundryLocalAsrModel,
setFoundryLocalAsrLanguageHint,
type FoundryLocalAsrStatus,
```

Add state:

```ts
const [foundryStatus, setFoundryStatus] = useState<FoundryLocalAsrStatus | null>(null);
```

Add refresh function:

```ts
const refreshFoundryStatus = async () => {
  try {
    const status = await getFoundryLocalAsrStatus();
    setFoundryStatus(status);
  } catch (err) {
    console.warn('[localAsr] Foundry status query failed', err);
  }
};
```

Call it inside `refresh()`:

```ts
void refreshFoundryStatus();
```

- [ ] **Step 2: Add Windows Foundry model controls**

Add this block after the top page header:

```tsx
<Card>
  <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'center' }}>
    <div>
      <div style={{ fontSize: 13, fontWeight: 650 }}>
        {t('localAsr.foundryTitle')}
      </div>
      <div style={{ fontSize: 11.5, color: 'var(--ol-ink-4)', marginTop: 4, lineHeight: 1.55 }}>
        {t('localAsr.foundryDesc')}
      </div>
    </div>
    <Pill tone={foundryStatus?.available ? 'ok' : 'warn'}>
      {foundryStatus?.available ? t('localAsr.runtimeReady') : t('localAsr.runtimeUnavailable')}
    </Pill>
  </div>
  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginTop: 14 }}>
    <label style={{ display: 'grid', gap: 6, fontSize: 12 }}>
      {t('localAsr.foundryModelLabel')}
      <select
        value={foundryStatus?.activeModel ?? 'whisper-small'}
        onChange={async e => {
          await setFoundryLocalAsrModel(e.target.value);
          await setActiveAsrProvider('foundry-local-whisper');
          await refreshFoundryStatus();
        }}
      >
        <option value="whisper-small">Whisper Small</option>
        <option value="whisper-base">Whisper Base</option>
        <option value="whisper-tiny">Whisper Tiny</option>
      </select>
    </label>
    <label style={{ display: 'grid', gap: 6, fontSize: 12 }}>
      {t('localAsr.languageHintLabel')}
      <select
        value={foundryStatus ? '' : ''}
        onChange={async e => {
          await setFoundryLocalAsrLanguageHint(e.target.value);
          await refreshFoundryStatus();
        }}
      >
        <option value="">{t('localAsr.languageAuto')}</option>
        <option value="zh">{t('localAsr.languageZh')}</option>
        <option value="en">{t('localAsr.languageEn')}</option>
      </select>
    </label>
  </div>
  {foundryStatus?.error && (
    <div style={{ marginTop: 10, fontSize: 11.5, color: 'var(--ol-danger)' }}>
      {foundryStatus.error}
    </div>
  )}
</Card>
```

- [ ] **Step 3: Add i18n strings**

In `zh-CN.ts` under `localAsr`:

```ts
foundryTitle: 'Windows 本地 Whisper',
foundryDesc: '使用 Microsoft Foundry Local 在本机转写语音。无需 ASR API Key；首次使用会准备运行组件和 Whisper 模型。',
runtimeReady: '运行时可用',
runtimeUnavailable: '运行时不可用',
foundryModelLabel: 'Whisper 模型',
languageHintLabel: '识别语言',
languageAuto: '自动检测',
languageZh: '优先中文',
languageEn: '优先英文',
```

Add matching English strings in `en.ts`.

- [ ] **Step 4: Build frontend**

Run:

```powershell
npm --prefix openless-all/app run build
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add -- openless-all/app/src/pages/LocalAsr.tsx openless-all/app/src/i18n/zh-CN.ts openless-all/app/src/i18n/en.ts
git commit -m "feat(ui): manage Windows local Whisper"
```

### Task 9: Windows Smoke Script Local ASR Mode

**Files:**
- Modify: `openless-all/app/scripts/windows-real-asr-insertion-smoke.ps1`

- [ ] **Step 1: Add ASR mode parameter**

Add parameter:

```powershell
[ValidateSet("volcengine", "foundry-local-whisper")]
[string]$AsrProvider = "volcengine",
```

- [ ] **Step 2: Write active ASR preference for smoke**

In `Set-HoldHotkeyPreference`, replace the active ASR default line with:

```powershell
if ($null -eq $prefs.activeAsrProvider) {
  $prefs | Add-Member -NotePropertyName activeAsrProvider -NotePropertyValue $AsrProvider
} else {
  $prefs.activeAsrProvider = $AsrProvider
}
```

- [ ] **Step 3: Skip Volcengine credential requirement for local ASR**

Replace:

```powershell
if ($RequireJsonCredentials -and (-not $credentialStatus.VolcengineConfigured -or -not $credentialStatus.ArkConfigured)) {
  throw "Real ASR regression requires configured Volcengine ASR and Ark LLM credentials."
}
```

with:

```powershell
if ($RequireJsonCredentials -and $AsrProvider -eq "volcengine" -and (-not $credentialStatus.VolcengineConfigured -or -not $credentialStatus.ArkConfigured)) {
  throw "Real ASR regression requires configured Volcengine ASR and Ark LLM credentials."
}
if ($RequireJsonCredentials -and $AsrProvider -eq "foundry-local-whisper" -and (-not $credentialStatus.ArkConfigured)) {
  Write-Warning "Ark LLM credentials are not configured; local ASR smoke will accept raw transcript fallback."
}
```

- [ ] **Step 4: Add no Win+H log assertion**

After history verification, add:

```powershell
$logText = Get-Content -Raw $logPath
if ($logText -match "Win\\+H|Voice Typing|Windows\\.Media\\.SpeechRecognition|SAPI") {
  throw "Unexpected Windows system dictation path appeared in OpenLess log."
}
```

- [ ] **Step 5: Run script syntax check**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$null = [scriptblock]::Create((Get-Content -Raw '.\openless-all\app\scripts\windows-real-asr-insertion-smoke.ps1')); 'ok'"
```

Expected: prints `ok`.

- [ ] **Step 6: Commit**

```powershell
git add -- openless-all/app/scripts/windows-real-asr-insertion-smoke.ps1
git commit -m "test(windows): add local ASR smoke mode"
```

### Task 10: End-to-End Verification

**Files:**
- No code changes unless a verification step exposes a bug.

- [ ] **Step 1: Run backend unit and type checks**

Run:

```powershell
cargo test --manifest-path openless-all/app/src-tauri/Cargo.toml
cargo check --manifest-path openless-all/app/src-tauri/Cargo.toml
```

Expected: PASS.

- [ ] **Step 2: Run frontend build**

Run:

```powershell
npm --prefix openless-all/app run build
```

Expected: PASS.

- [ ] **Step 3: Run no Win+H source search**

Run:

```powershell
rg -n "Win\\+H|Voice Typing|Windows\\.Media\\.SpeechRecognition|SAPI|SendInput.*H" openless-all/app/src-tauri/src openless-all/app/windows-ime openless-all/app/src
```

Expected: no matches except documentation or explicit negative test strings.

- [ ] **Step 4: Run local ASR smoke on Windows**

Run after building a Windows executable:

```powershell
powershell -ExecutionPolicy Bypass -File .\openless-all\app\scripts\windows-real-asr-insertion-smoke.ps1 -AsrProvider foundry-local-whisper -Target notepad -ManualSpeech -AllowClipboardFallback
```

Expected:

- OpenLess observes hotkey and starts session.
- No Windows Voice Typing panel appears.
- History receives a new item with non-empty `rawTranscript` and `finalText`.
- If Ark is not configured, `finalText` equals raw transcript or records polish fallback.
- Notepad receives the final text through TSF or permitted fallback.

- [ ] **Step 5: Confirm verification did not create file changes**

Run:

```powershell
git status --short
```

Expected: no output. If a verification step exposed a code defect, stop this task and write a new focused fix task before continuing.

## Self-Review

Spec coverage:

- No Win+H: Task 10 source search and smoke log assertion cover it.
- Existing interaction: Task 6 routes through `Coordinator`; no UI shortcut path bypasses recorder/capsule.
- Local transcript into polish/history: Task 6 returns `RawTranscript` before existing polish and history code.
- First-use UX: Tasks 7 and 8 expose provider and runtime/model state.
- Windows TSF insertion unchanged: Task 6 leaves `insert_with_windows_ime_first` intact.
- Offline behavior after cache: Task 3 runtime caches loaded model state; Task 10 smoke can be repeated after model download.

Placeholder scan:

- This plan contains no unresolved placeholders or unspecified file paths.

Type consistency:

- Provider id is consistently `foundry-local-whisper`.
- Rust preference fields are `foundry_local_asr_model`, `foundry_local_asr_language_hint`, and `foundry_local_asr_keep_loaded_secs`.
- TypeScript preference fields use camelCase equivalents.
