//! Tauri command surface — every IPC entry the React UI invokes lives here.

use std::sync::Arc;

use tauri::State;

use crate::coordinator::Coordinator;
use crate::permissions::{self, PermissionStatus};
use crate::persistence::{CredentialAccount, CredentialsSnapshot, CredentialsVault};
use crate::types::{
    CredentialsStatus, DictationSession, DictionaryEntry, PolishMode, UserPreferences,
};

type CoordinatorState<'a> = State<'a, Arc<Coordinator>>;

// ─────────────────────────── settings + credentials ───────────────────────────

#[tauri::command]
pub fn get_settings(coord: CoordinatorState<'_>) -> UserPreferences {
    coord.prefs().get()
}

#[tauri::command]
pub fn set_settings(
    coord: CoordinatorState<'_>,
    prefs: UserPreferences,
) -> Result<(), String> {
    coord.prefs().set(prefs).map_err(|e| e.to_string())?;
    coord.update_hotkey_binding();
    Ok(())
}

#[tauri::command]
pub fn get_credentials() -> CredentialsStatus {
    let snap = CredentialsVault::snapshot();
    CredentialsStatus {
        volcengine_configured: configured(&snap.volcengine_app_key)
            && configured(&snap.volcengine_access_key)
            && configured(&snap.volcengine_resource_id),
        ark_configured: configured(&snap.ark_api_key),
    }
}

fn configured(field: &Option<String>) -> bool {
    field.as_ref().map(|s| !s.is_empty()).unwrap_or(false)
}

#[tauri::command]
pub fn set_credential(account: String, value: String) -> Result<(), String> {
    let acc = parse_account(&account)?;
    if value.is_empty() {
        CredentialsVault::remove(acc).map_err(|e| e.to_string())
    } else {
        CredentialsVault::set(acc, &value).map_err(|e| e.to_string())
    }
}

/// 读出某个账号的实际值（用于设置页预填表单）。
/// 与 Swift `CredentialsVault.get` 同语义，先 Keychain，缺则回落 ~/.openless/credentials.json。
#[tauri::command]
pub fn read_credential(account: String) -> Result<Option<String>, String> {
    let acc = parse_account(&account)?;
    CredentialsVault::get(acc).map_err(|e| e.to_string())
}

fn parse_account(s: &str) -> Result<CredentialAccount, String> {
    match s {
        "volcengine.app_key" => Ok(CredentialAccount::VolcengineAppKey),
        "volcengine.access_key" => Ok(CredentialAccount::VolcengineAccessKey),
        "volcengine.resource_id" => Ok(CredentialAccount::VolcengineResourceId),
        "ark.api_key" => Ok(CredentialAccount::ArkApiKey),
        "ark.model_id" => Ok(CredentialAccount::ArkModelId),
        "ark.endpoint" => Ok(CredentialAccount::ArkEndpoint),
        _ => Err(format!("unknown account: {s}")),
    }
}

// ─────────────────────────── history ───────────────────────────

#[tauri::command]
pub fn list_history(coord: CoordinatorState<'_>) -> Result<Vec<DictationSession>, String> {
    coord.history().list().map_err(|e| e.to_string())
}

#[tauri::command]
pub fn delete_history_entry(coord: CoordinatorState<'_>, id: String) -> Result<(), String> {
    coord.history().delete(&id).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn clear_history(coord: CoordinatorState<'_>) -> Result<(), String> {
    coord.history().clear().map_err(|e| e.to_string())
}

// ─────────────────────────── vocab ───────────────────────────

#[tauri::command]
pub fn list_vocab(coord: CoordinatorState<'_>) -> Result<Vec<DictionaryEntry>, String> {
    coord.vocab().list().map_err(|e| e.to_string())
}

#[tauri::command]
pub fn add_vocab(
    coord: CoordinatorState<'_>,
    phrase: String,
    note: Option<String>,
) -> Result<DictionaryEntry, String> {
    coord.vocab().add(phrase, note).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn remove_vocab(coord: CoordinatorState<'_>, id: String) -> Result<(), String> {
    coord.vocab().remove(&id).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn set_vocab_enabled(
    coord: CoordinatorState<'_>,
    id: String,
    enabled: bool,
) -> Result<(), String> {
    coord
        .vocab()
        .set_enabled(&id, enabled)
        .map_err(|e| e.to_string())
}

// ─────────────────────────── dictation lifecycle ───────────────────────────

#[tauri::command]
pub async fn start_dictation(coord: CoordinatorState<'_>) -> Result<(), String> {
    coord.start_dictation().await
}

#[tauri::command]
pub async fn stop_dictation(coord: CoordinatorState<'_>) -> Result<(), String> {
    coord.stop_dictation().await
}

#[tauri::command]
pub fn cancel_dictation(coord: CoordinatorState<'_>) {
    coord.cancel_dictation();
}

#[tauri::command]
pub async fn repolish(
    coord: CoordinatorState<'_>,
    raw_text: String,
    mode: PolishMode,
) -> Result<String, String> {
    coord.repolish(raw_text, mode).await
}

// ─────────────────────────── style toggles (lightweight) ───────────────────────────

#[tauri::command]
pub fn set_default_polish_mode(
    coord: CoordinatorState<'_>,
    mode: PolishMode,
) -> Result<(), String> {
    let mut prefs = coord.prefs().get();
    prefs.default_mode = mode;
    coord.prefs().set(prefs).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn set_style_enabled(
    coord: CoordinatorState<'_>,
    mode: PolishMode,
    enabled: bool,
) -> Result<(), String> {
    let mut prefs = coord.prefs().get();
    if enabled {
        if !prefs.enabled_modes.contains(&mode) {
            prefs.enabled_modes.push(mode);
        }
    } else {
        prefs.enabled_modes.retain(|m| *m != mode);
    }
    coord.prefs().set(prefs).map_err(|e| e.to_string())
}

// ─────────────────────────── 系统权限 ───────────────────────────

#[tauri::command]
pub fn check_accessibility_permission() -> PermissionStatus {
    permissions::check_accessibility()
}

#[tauri::command]
pub fn request_accessibility_permission() -> PermissionStatus {
    permissions::request_accessibility()
}

#[tauri::command]
pub fn check_microphone_permission() -> PermissionStatus {
    permissions::check_microphone()
}

/// 跳到 macOS 系统设置的指定隐私面板。pane: "accessibility" | "microphone".
#[tauri::command]
pub fn open_system_settings(pane: String) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        let url = match pane.as_str() {
            "accessibility" => "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "microphone" => "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            _ => "x-apple.systempreferences:com.apple.preference.security?Privacy",
        };
        std::process::Command::new("open")
            .arg(url)
            .spawn()
            .map(|_| ())
            .map_err(|e| e.to_string())
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = pane;
        Ok(())
    }
}

/// 触发 macOS 系统弹"是否允许 OpenLess 访问麦克风"对话框。
/// 关键：**必须 `.play()` 才会触发 TCC 检查并弹框** —— `build_input_stream` 仅构造对象，
/// 不会让操作系统去问用户。**这是上次 trigger 看似不响应的真正原因。**
/// 流启动 ~400ms 后关闭 — 足够 macOS 处理弹窗,又不会真采到声音。
///
/// 注意：仅在权限 == NotDetermined 时调用有意义；Denied 状态下系统**不会再弹**任何框,
/// 必须用户手动到系统设置 → 隐私与安全性 → 麦克风 把 OpenLess 勾上。
#[tauri::command]
pub fn trigger_microphone_prompt() -> Result<(), String> {
    use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
    let host = cpal::default_host();
    let device = host
        .default_input_device()
        .ok_or_else(|| "no input device".to_string())?;
    let config = device
        .default_input_config()
        .map_err(|e| e.to_string())?;
    log::info!(
        "[mic] trigger_microphone_prompt: opening device {} ({} Hz, {:?})",
        device.name().unwrap_or_else(|_| "<unnamed>".into()),
        config.sample_rate().0,
        config.sample_format(),
    );
    let stream = match config.sample_format() {
        cpal::SampleFormat::F32 => device.build_input_stream(
            &config.into(),
            |_data: &[f32], _: &_| {},
            |err| log::warn!("[mic] trigger stream err: {err}"),
            None,
        ),
        cpal::SampleFormat::I16 => device.build_input_stream(
            &config.into(),
            |_data: &[i16], _: &_| {},
            |err| log::warn!("[mic] trigger stream err: {err}"),
            None,
        ),
        cpal::SampleFormat::U16 => device.build_input_stream(
            &config.into(),
            |_data: &[u16], _: &_| {},
            |err| log::warn!("[mic] trigger stream err: {err}"),
            None,
        ),
        other => return Err(format!("unsupported sample format {other:?}")),
    }
    .map_err(|e| {
        log::warn!("[mic] build_input_stream failed: {e}");
        e.to_string()
    })?;

    // ★ 关键：play() 才让 macOS 实际去 TCC 查权限 → 触发系统弹框。
    if let Err(e) = stream.play() {
        log::warn!("[mic] stream.play() failed: {e}");
        return Err(e.to_string());
    }
    // 给 OS 一点时间把弹框显示出来；用户在他们的世界里慢慢看 / 点。
    std::thread::sleep(std::time::Duration::from_millis(400));
    drop(stream);
    log::info!("[mic] trigger_microphone_prompt: stream play() + drop 完成");
    Ok(())
}

// ─────────────────────────── unused but exported (silences dead_code) ───────────────────────────

#[allow(dead_code)]
fn _ensure_snapshot_used(_: CredentialsSnapshot) {}
