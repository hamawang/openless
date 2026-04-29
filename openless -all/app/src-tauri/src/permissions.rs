//! 系统权限请求 / 检查（macOS / Windows）。
//!
//! 与 Swift `Sources/OpenLessHotkey/AccessibilityPermission.swift` +
//! `Sources/OpenLessRecorder/MicrophonePermission.swift` 同源。
//!
//! - macOS Accessibility：`AXIsProcessTrusted` 检查；
//!   `AXIsProcessTrustedWithOptions({kAXTrustedCheckOptionPrompt: true})` 弹系统授权框。
//! - macOS Microphone：`AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio`。
//!   首次开 cpal 输入流时（Info.plist 已声明 NSMicrophoneUsageDescription）macOS 自动弹框。
//! - Windows：rdev / cpal 不需要 Accessibility 等价权限；麦克风首次使用时 Win10+ 弹一次系统提示。

use serde::Serialize;

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum PermissionStatus {
    Granted,
    Denied,
    NotDetermined,
    Restricted,
    /// 当前平台不需要这个权限（如 Windows 上的 Accessibility）。
    NotApplicable,
}

// ─────────────────────────── macOS ───────────────────────────

#[cfg(target_os = "macos")]
mod platform {
    use super::PermissionStatus;
    use std::ffi::c_void;

    #[link(name = "ApplicationServices", kind = "framework")]
    extern "C" {
        fn AXIsProcessTrusted() -> bool;
        fn AXIsProcessTrustedWithOptions(options: *const c_void) -> bool;
        static kAXTrustedCheckOptionPrompt: *const c_void;
    }

    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        fn CFDictionaryCreate(
            allocator: *const c_void,
            keys: *const *const c_void,
            values: *const *const c_void,
            num_values: isize,
            key_callbacks: *const c_void,
            value_callbacks: *const c_void,
        ) -> *const c_void;
        fn CFRelease(cf: *const c_void);
        static kCFTypeDictionaryKeyCallBacks: c_void;
        static kCFTypeDictionaryValueCallBacks: c_void;
        static kCFBooleanTrue: *const c_void;
    }

    #[link(name = "AVFoundation", kind = "framework")]
    extern "C" {
        // 直接拿 AVFoundation 导出的 NSString 静态符号；不用从 Rust 串构造 NSString。
        static AVMediaTypeAudio: *const c_void;
    }

    // AVAudioApplication 在 AVFAudio 框架（macOS 14+）。Swift 原版 MicrophonePermission.swift
    // 走的就是这条；它和 cpal/AVAudioEngine 共享同一个权限状态。
    #[link(name = "AVFAudio", kind = "framework")]
    extern "C" {}

    pub fn check_accessibility() -> PermissionStatus {
        unsafe {
            if AXIsProcessTrusted() {
                PermissionStatus::Granted
            } else {
                PermissionStatus::Denied
            }
        }
    }

    /// 弹 Accessibility 系统授权框（只在未授权时弹）。返回当前授权状态。
    pub fn request_accessibility() -> PermissionStatus {
        unsafe {
            let key = kAXTrustedCheckOptionPrompt;
            let value = kCFBooleanTrue;
            let keys: [*const c_void; 1] = [key];
            let values: [*const c_void; 1] = [value];
            let dict = CFDictionaryCreate(
                std::ptr::null(),
                keys.as_ptr(),
                values.as_ptr(),
                1,
                &kCFTypeDictionaryKeyCallBacks as *const _ as *const c_void,
                &kCFTypeDictionaryValueCallBacks as *const _ as *const c_void,
            );
            let trusted = AXIsProcessTrustedWithOptions(dict);
            CFRelease(dict);
            if trusted {
                PermissionStatus::Granted
            } else {
                PermissionStatus::Denied
            }
        }
    }

    pub fn check_microphone() -> PermissionStatus {
        // 优先 AVAudioApplication.shared.recordPermission（macOS 14+，与 Swift
        // MicrophonePermission 同源；和 cpal/AVAudioEngine 共享权限状态）。
        // macOS 13 及更老用 AVCaptureDevice 兜底。
        if let Some(status) = check_microphone_via_avaudio_application() {
            return status;
        }
        check_microphone_via_avcapture_device()
    }

    fn check_microphone_via_avaudio_application() -> Option<PermissionStatus> {
        use objc2::msg_send;
        use objc2::runtime::{AnyClass, AnyObject};

        // 类不存在 = 在老 macOS（< 14）上跑，回落到 capture device 路径
        let cls = AnyClass::get("AVAudioApplication")?;
        let shared: *mut AnyObject = unsafe { msg_send![cls, sharedInstance] };
        if shared.is_null() {
            log::warn!("[mic] AVAudioApplication sharedInstance returned null");
            return None;
        }
        // AVAudioApplicationRecordPermission 是 NS_ENUM(NSInteger, ...) FourCC：
        //   'grnt' = 0x67726e74 = 1735552628
        //   'deny' = 0x64656e79 = 1684368761
        //   'undt' = 0x756e6474 = 1970168948
        let perm: i64 = unsafe { msg_send![shared, recordPermission] };
        let mapped = match perm {
            0x6772_6e74 => PermissionStatus::Granted,
            0x6465_6e79 => PermissionStatus::Denied,
            0x756e_6474 => PermissionStatus::NotDetermined,
            _ => PermissionStatus::NotDetermined,
        };
        log::info!(
            "[mic] AVAudioApplication.recordPermission raw=0x{:x} ({}) → {:?}",
            perm, perm, mapped
        );
        Some(mapped)
    }

    fn check_microphone_via_avcapture_device() -> PermissionStatus {
        // [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]
        use objc2::msg_send;
        use objc2::runtime::AnyClass;

        let cls = match AnyClass::get("AVCaptureDevice") {
            Some(c) => c,
            None => return PermissionStatus::NotDetermined,
        };
        let status: i64 = unsafe {
            msg_send![cls, authorizationStatusForMediaType: AVMediaTypeAudio]
        };
        let mapped = match status {
            3 => PermissionStatus::Granted,
            2 => PermissionStatus::Denied,
            1 => PermissionStatus::Restricted,
            0 => PermissionStatus::NotDetermined,
            _ => PermissionStatus::NotDetermined,
        };
        log::info!("[mic] AVCaptureDevice.authStatus raw={} → {:?}", status, mapped);
        mapped
    }
}

// ─────────────────────────── Windows / 其他 ───────────────────────────

#[cfg(not(target_os = "macos"))]
mod platform {
    use super::PermissionStatus;

    /// Windows / Linux 不存在 macOS 那种 Accessibility 概念；rdev 直接监听键盘。
    pub fn check_accessibility() -> PermissionStatus {
        PermissionStatus::NotApplicable
    }

    pub fn request_accessibility() -> PermissionStatus {
        PermissionStatus::NotApplicable
    }

    /// Windows 的麦克风权限走系统设置 → 隐私 → 麦克风；
    /// 我们没法在用户态直接查授权状态，启动 cpal stream 时 Win10+ 会自动弹一次提示。
    /// 这里乐观返回 Granted；UI 上不需要展示 Denied 状态。
    pub fn check_microphone() -> PermissionStatus {
        PermissionStatus::Granted
    }
}

pub use platform::{check_accessibility, check_microphone, request_accessibility};

/// 兼容老调用：startup 时主动弹 Accessibility 框。
pub fn request_accessibility_with_prompt(_prompt: bool) -> bool {
    matches!(request_accessibility(), PermissionStatus::Granted)
}
