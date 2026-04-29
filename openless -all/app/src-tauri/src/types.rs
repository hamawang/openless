//! Shared value types crossing the IPC boundary.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum PolishMode {
    Raw,
    Light,
    Structured,
    Formal,
}

impl Default for PolishMode {
    fn default() -> Self {
        PolishMode::Light
    }
}

impl PolishMode {
    pub fn display_name(&self) -> &'static str {
        match self {
            PolishMode::Raw => "原文",
            PolishMode::Light => "轻度润色",
            PolishMode::Structured => "清晰结构",
            PolishMode::Formal => "正式表达",
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum InsertStatus {
    Inserted,
    CopiedFallback,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DictationSession {
    pub id: String,
    pub created_at: String, // ISO-8601
    pub raw_transcript: String,
    pub final_text: String,
    pub mode: PolishMode,
    pub app_bundle_id: Option<String>,
    pub app_name: Option<String>,
    pub insert_status: InsertStatus,
    pub error_code: Option<String>,
    pub duration_ms: Option<u64>,
    pub dictionary_entry_count: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DictionaryEntry {
    pub id: String,
    pub phrase: String,
    pub note: Option<String>,
    pub enabled: bool,
    pub hits: u64,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UserPreferences {
    pub hotkey: HotkeyBinding,
    pub default_mode: PolishMode,
    pub enabled_modes: Vec<PolishMode>,
    pub launch_at_login: bool,
    pub show_capsule: bool,
    pub active_asr_provider: String, // "volcengine" | "apple-speech" | ...
    pub active_llm_provider: String, // "ark" | "openai" | ...
}

impl Default for UserPreferences {
    fn default() -> Self {
        Self {
            hotkey: HotkeyBinding::default(),
            default_mode: PolishMode::Light,
            enabled_modes: vec![
                PolishMode::Raw,
                PolishMode::Light,
                PolishMode::Structured,
                PolishMode::Formal,
            ],
            launch_at_login: false,
            show_capsule: true,
            active_asr_provider: "volcengine".into(),
            active_llm_provider: "ark".into(),
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum HotkeyTrigger {
    RightOption,
    LeftOption,
    RightControl,
    LeftControl,
    RightCommand,
    Fn,
    RightAlt, // Windows synonym for RightOption
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum HotkeyMode {
    Toggle,
    Hold,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct HotkeyBinding {
    pub trigger: HotkeyTrigger,
    pub mode: HotkeyMode,
}

impl Default for HotkeyBinding {
    fn default() -> Self {
        // Right Option (mac) / Right Alt (win) — toggle by default per design.
        Self {
            trigger: if cfg!(target_os = "windows") {
                HotkeyTrigger::RightAlt
            } else {
                HotkeyTrigger::RightOption
            },
            mode: HotkeyMode::Toggle,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum CapsuleState {
    Idle,
    Recording,
    Transcribing,
    Polishing,
    Done,
    Cancelled,
    Error,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CapsulePayload {
    pub state: CapsuleState,
    pub level: f32,            // 0..1 RMS
    pub elapsed_ms: u64,
    pub message: Option<String>,
    pub inserted_chars: Option<u32>,
}

/// Snapshot of credentials read from vault — only what the UI needs to know
/// (whether keys are set; never the values themselves).
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct CredentialsStatus {
    pub volcengine_configured: bool,
    pub ark_configured: bool,
}

/// Today's metrics shown on the Overview tab.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct TodayMetrics {
    pub chars_today: u64,
    pub segments_today: u64,
    pub avg_latency_ms: u64,
    pub total_duration_ms: u64,
}
