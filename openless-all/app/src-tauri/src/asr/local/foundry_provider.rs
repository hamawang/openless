#![allow(dead_code)] // Task 6 接入 coordinator 后这些路径会变成运行时路径。

#[cfg(target_os = "windows")]
use std::fs::{self, OpenOptions};
#[cfg(target_os = "windows")]
use std::io::Write;
#[cfg(target_os = "windows")]
use std::path::{Path, PathBuf};
#[cfg(target_os = "windows")]
use std::sync::Arc;

#[cfg(target_os = "windows")]
use anyhow::Context;
use anyhow::Result;
use parking_lot::Mutex;
#[cfg(target_os = "windows")]
use uuid::Uuid;

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
            language_hint: normalize_language_hint(language_hint),
            buffer: Mutex::new(Vec::new()),
        }
    }

    #[cfg(not(target_os = "windows"))]
    pub fn new(model_alias: String, language_hint: Option<String>) -> Self {
        Self {
            model_alias,
            language_hint: normalize_language_hint(language_hint),
            buffer: Mutex::new(Vec::new()),
        }
    }

    pub fn model_alias(&self) -> &str {
        &self.model_alias
    }

    pub fn language_hint(&self) -> Option<&str> {
        self.language_hint.as_deref()
    }

    pub async fn transcribe(&self) -> Result<RawTranscript> {
        let pcm = self.buffer.lock().clone();
        if pcm.is_empty() {
            return Ok(RawTranscript {
                text: String::new(),
                duration_ms: 0,
            });
        }

        let result = self.transcribe_inner(&pcm).await;
        if result.is_ok() {
            self.buffer.lock().clear();
        }
        result
    }

    async fn transcribe_inner(&self, pcm: &[u8]) -> Result<RawTranscript> {
        let duration_ms = pcm_duration_ms(pcm);

        #[cfg(not(target_os = "windows"))]
        {
            let _ = pcm;
            anyhow::bail!(
                "Foundry Local Whisper is only available on Windows: {}",
                self.model_alias
            );
        }

        #[cfg(target_os = "windows")]
        {
            let wav_file = TempWavFile::create(pcm)?;
            let text = self
                .runtime
                .transcribe_audio_file(&self.model_alias, wav_file.path())
                .await
                .with_context(|| {
                    format!(
                        "transcribe audio file with Foundry Local Whisper model {}",
                        self.model_alias
                    )
                })?;

            Ok(RawTranscript {
                text: trim_transcript_text(&text),
                duration_ms,
            })
        }
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

fn pcm_duration_ms(pcm: &[u8]) -> u64 {
    (pcm.len() as u64 / 2) * 1000 / 16_000
}

fn pcm_to_wav(pcm: &[u8]) -> Vec<u8> {
    let samples: Vec<i16> = pcm
        .chunks_exact(2)
        .map(|chunk| i16::from_le_bytes([chunk[0], chunk[1]]))
        .collect();
    encode_wav_16k_mono(&samples)
}

#[cfg(target_os = "windows")]
struct TempWavFile {
    path: PathBuf,
}

#[cfg(target_os = "windows")]
impl TempWavFile {
    fn create(pcm: &[u8]) -> Result<Self> {
        let dir = foundry_temp_dir();
        fs::create_dir_all(&dir).with_context(|| format!("create {}", dir.display()))?;
        let path = dir.join(format!("foundry-whisper-{}.wav", Uuid::new_v4()));
        let wav = pcm_to_wav(pcm);
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
            .with_context(|| format!("create {}", path.display()))?;

        if let Err(err) = file.write_all(&wav) {
            drop(file);
            remove_partial_temp_wav(&path);
            return Err(err).with_context(|| format!("write {}", path.display()));
        }
        if let Err(err) = file.sync_all() {
            drop(file);
            remove_partial_temp_wav(&path);
            return Err(err).with_context(|| format!("sync {}", path.display()));
        }

        Ok(Self { path })
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

#[cfg(target_os = "windows")]
impl Drop for TempWavFile {
    fn drop(&mut self) {
        match fs::remove_file(&self.path) {
            Ok(()) => {}
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
            Err(err) => {
                log::warn!(
                    "[foundry-asr] 清理临时 WAV 失败 {}: {err}",
                    self.path.display()
                );
            }
        }
    }
}

#[cfg(target_os = "windows")]
fn remove_partial_temp_wav(path: &Path) {
    match fs::remove_file(path) {
        Ok(()) => {}
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
        Err(err) => {
            log::warn!(
                "[foundry-asr] 清理未完成的临时 WAV 失败 {}: {err}",
                path.display()
            );
        }
    }
}

#[cfg(target_os = "windows")]
fn foundry_temp_dir() -> PathBuf {
    std::env::temp_dir()
        .join("OpenLess")
        .join("foundry-local-asr")
}

fn normalize_language_hint(language_hint: Option<String>) -> Option<String> {
    language_hint
        .map(|hint| hint.trim().to_string())
        .filter(|hint| !hint.is_empty())
}

fn trim_transcript_text(text: &str) -> String {
    text.trim().to_string()
}

#[cfg(test)]
mod tests {
    use crate::recorder::AudioConsumer;

    #[cfg(target_os = "windows")]
    fn test_provider() -> super::FoundryLocalWhisperAsr {
        use std::sync::Arc;

        super::FoundryLocalWhisperAsr::new(
            Arc::new(super::FoundryLocalRuntime::new()),
            "whisper-small".into(),
            Some(" zh ".into()),
        )
    }

    #[cfg(not(target_os = "windows"))]
    fn test_provider() -> super::FoundryLocalWhisperAsr {
        super::FoundryLocalWhisperAsr::new("whisper-small".into(), Some(" zh ".into()))
    }

    #[test]
    fn foundry_provider_duration_uses_16k_i16_pcm() {
        let pcm = vec![0u8; 32_000];

        assert_eq!(super::pcm_duration_ms(&pcm), 1000);
    }

    #[test]
    fn foundry_provider_wav_ignores_odd_trailing_byte() {
        let pcm = [0x01, 0x00, 0xff, 0x7f, 0xee];
        let wav = super::pcm_to_wav(&pcm);

        assert_eq!(&wav[0..4], b"RIFF");
        assert_eq!(u32::from_le_bytes(wav[40..44].try_into().unwrap()), 4);
        assert_eq!(&wav[44..], &[0x01, 0x00, 0xff, 0x7f]);
    }

    #[cfg(target_os = "windows")]
    #[test]
    fn foundry_provider_temp_wav_drop_removes_file() {
        let pcm = [0x01, 0x00, 0xff, 0x7f];
        let path = {
            let temp = super::TempWavFile::create(&pcm).unwrap();
            let path = temp.path().to_path_buf();

            assert!(path.exists());

            path
        };

        assert!(!path.exists());
    }

    #[test]
    fn foundry_provider_normalizes_language_hint_and_text() {
        assert_eq!(
            super::normalize_language_hint(Some(" zh ".into())),
            Some("zh".into())
        );
        assert_eq!(super::normalize_language_hint(Some(" ".into())), None);
        assert_eq!(super::trim_transcript_text("  hello\r\n"), "hello");
    }

    #[test]
    fn foundry_provider_cancel_clears_buffer() {
        let provider = test_provider();

        provider.consume_pcm_chunk(&[1, 0, 2, 0]);
        provider.cancel();

        assert!(provider.buffer.lock().is_empty());
        assert_eq!(provider.model_alias(), "whisper-small");
        assert_eq!(provider.language_hint(), Some("zh"));
    }
}
