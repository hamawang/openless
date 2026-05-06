use serde::Serialize;

pub const PROVIDER_ID: &str = "foundry-local-whisper";
pub const DEFAULT_MODEL_ALIAS: &str = "whisper-small";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)]
pub struct FoundryWhisperModel {
    pub alias: &'static str,
    pub display_name: &'static str,
    pub quality_tier: &'static str,
}

#[allow(dead_code)]
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

#[allow(dead_code)]
pub fn is_foundry_local_whisper(id: &str) -> bool {
    id == PROVIDER_ID
}

#[allow(dead_code)]
pub fn model_alias_is_known(alias: &str) -> bool {
    MODELS.iter().any(|model| model.alias == alias)
}

#[allow(dead_code)]
pub fn default_language_hint() -> Option<String> {
    None
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)]
pub struct FoundryRuntimeStatus {
    pub provider_id: String,
    pub available: bool,
    pub active_model: String,
    pub loaded_model_id: Option<String>,
    pub endpoint: Option<String>,
    pub error: Option<String>,
}

impl FoundryRuntimeStatus {
    #[allow(dead_code)]
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

    #[test]
    fn unavailable_runtime_status_uses_native_audio_shape() {
        let status = FoundryRuntimeStatus::unavailable("whisper-base".to_string(), "not ready");

        assert_eq!(status.provider_id, PROVIDER_ID);
        assert!(!status.available);
        assert_eq!(status.active_model, "whisper-base");
        assert_eq!(status.loaded_model_id, None);
        assert_eq!(status.endpoint, None);
        assert_eq!(status.error.as_deref(), Some("not ready"));
    }
}
