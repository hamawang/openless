# 模块依赖关系 Finding 报告

## 生成时间
2026-05-04 22:59:01

## 1. Cargo 依赖

```toml
[dependencies]
tauri = { version = "2", features = ["macos-private-api", "tray-icon"] }
tauri-plugin-shell = "2"
tauri-plugin-updater = "2"
tauri-plugin-single-instance = "2"
tauri-plugin-autostart = "2"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tokio = { version = "1", features = ["full"] }
tokio-tungstenite = { version = "0.24", features = ["rustls-tls-native-roots"] }
futures-util = "0.3"
reqwest = { version = "0.12", default-features = false, features = ["json", "multipart", "rustls-tls"] }
thiserror = "1"
anyhow = "1"
log = "0.4"
env_logger = "0.11"
simplelog = "0.12"
parking_lot = "0.12"
once_cell = "1"
uuid = { version = "1", features = ["v4", "serde"] }
chrono = { version = "0.4", features = ["serde"] }
bytes = "1"
url = "2"
raw-window-handle = "0.6"

# Hotkey + audio + insertion
global-hotkey = "0.6"
cpal = "0.15"
enigo = "0.2"
arboard = "3"
rdev = "0.5"

[target.'cfg(target_os = "macos")'.dependencies]
block2 = "0.5"
core-foundation = "0.10"
core-graphics = "0.24"
objc2 = "0.5"
objc2-foundation = "0.2"
objc2-app-kit = "0.2"

[target.'cfg(target_os = "windows")'.dependencies]
raw-window-handle = "0.6"
windows = { version = "0.58", features = [
  "Win32_Foundation",
  "Win32_Globalization",
  "Win32_Graphics_Dwm",
  "Win32_Graphics_Gdi",
  "Win32_System_Com",
  "Win32_System_Ole",
  "Win32_System_Registry",
  "Win32_System_Threading",
```

## 2. 模块间依赖（通过 use 语句分析）

### coordinator.rs 依赖
```
use crate::asr::{
use crate::hotkey::{HotkeyEvent, HotkeyMonitor};
use crate::insertion::TextInserter;
use crate::persistence::{
use crate::polish::{OpenAICompatibleConfig, OpenAICompatibleLLMProvider};
use crate::qa_hotkey::{QaHotkeyError, QaHotkeyEvent, QaHotkeyMonitor};
use crate::recorder::{Recorder, RecorderError};
use crate::selection::{capture_selection, SelectionContext};
use crate::types::{
use crate::windows_ime_ipc::ImeSubmitTarget;
use crate::windows_ime_session::{PreparedWindowsImeSession, WindowsImeSessionController};
```

### recorder.rs 依赖
```
```

## 3. Mock 策略建议

### 需要 Mock 的外部依赖
- **Volcengine ASR WebSocket**: 使用 mock WebSocket server
- **OpenAI Polish API**: 使用 mock HTTP server
- **Keychain**: 使用 trait abstraction + mock 实现
- **Clipboard**: 使用 trait abstraction + mock 实现
- **Audio Device**: 使用 mock audio stream

### 推荐工具
- `mockall`: 自动生成 mock
- `wiremock`: HTTP mock server
- `tokio-test`: 异步测试工具

