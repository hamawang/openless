//! 全局热键监听：发送按下 / 抬起 / 取消三类边沿事件。
//!
//! - macOS：原生 CGEventTap（core-foundation + core-graphics FFI），与 Swift
//!   `OpenLessHotkey/HotkeyMonitor.swift` 同源。**不能用 `rdev`**：rdev 在每个
//!   事件回调里同步调 `TSMGetInputSourceProperty`，macOS 14+ 强制断言主线程，
//!   非主线程触发 `dispatch_assert_queue_fail` → SIGTRAP abort（已踩坑）。
//! - Windows：原生 `WH_KEYBOARD_LL` low-level keyboard hook，保留 modifier-only
//!   trigger（如右 Control / 右 Alt）的真实语义，不再把平台能力藏在 `rdev` 抽象里。
//! - Linux / 其他：继续 best-effort 走 `rdev::listen`。
//!
//! 仅产出"边沿"事件，toggle vs hold 由 Coordinator 解释。

use std::collections::BTreeSet;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Sender};
use std::sync::Arc;
use std::time::Duration;

use parking_lot::RwLock;

use crate::types::{HotkeyAdapterKind, HotkeyBinding, HotkeyCapability, HotkeyInstallError};

#[derive(Clone, Copy, Debug)]
pub enum HotkeyEvent {
    Pressed,
    Released,
    Cancelled,
    /// Shift（或未来配置项指定的修饰键）按下边沿。可在录音过程中任何时刻产生；
    /// 上层据此切换到翻译输出管线。详见 issue #4。
    TranslationModifierPressed,
}

pub trait HotkeyAdapter: Send + Sync {
    fn kind(&self) -> HotkeyAdapterKind;
    fn update_binding(&self, binding: HotkeyBinding);
    fn shutdown(&self) {}
}

struct Shared {
    binding: RwLock<HotkeyBinding>,
    pressed_codes: RwLock<BTreeSet<String>>,
    /// 触发键当前是否处于"按住"状态。OS 自动重复事件用此去重。
    trigger_held: AtomicBool,
    /// Shift（翻译修饰键）当前是否按住。用于在 FLAGS_CHANGED 上识别 down 边沿
    /// （只在 false → true 时往上层发 TranslationModifierPressed）。详见 issue #4。
    translation_modifier_held: AtomicBool,
}

pub struct HotkeyMonitor {
    adapter: Box<dyn HotkeyAdapter>,
}

impl HotkeyMonitor {
    /// Spawn the listener thread and **wait synchronously** for it to confirm
    /// the OS-level hook installed so the caller can surface an actual adapter
    /// status instead of silently dropping events.
    pub fn start(
        binding: HotkeyBinding,
        tx: Sender<HotkeyEvent>,
    ) -> Result<Self, HotkeyInstallError> {
        Ok(Self {
            adapter: platform::start_adapter(binding, tx)?,
        })
    }

    pub fn update_binding(&self, binding: HotkeyBinding) {
        self.adapter.update_binding(binding);
    }

    pub fn kind(&self) -> HotkeyAdapterKind {
        self.adapter.kind()
    }

    pub fn capability() -> HotkeyCapability {
        HotkeyCapability::current()
    }
}

impl Drop for HotkeyMonitor {
    fn drop(&mut self) {
        self.adapter.shutdown();
    }
}

fn install_error(code: &str, message: impl Into<String>) -> HotkeyInstallError {
    HotkeyInstallError {
        code: code.into(),
        message: message.into(),
    }
}

fn send_or_log(tx: &Sender<HotkeyEvent>, evt: HotkeyEvent) {
    if let Err(e) = tx.send(evt) {
        log::warn!("[hotkey] 事件发送失败: {e}");
    }
}

type StartupTx<T> = mpsc::Sender<Result<T, HotkeyInstallError>>;

struct ListenerThread<T> {
    shared: Arc<Shared>,
    startup: T,
}

fn start_listener_thread<T, F>(
    binding: HotkeyBinding,
    tx: Sender<HotkeyEvent>,
    thread_name: &str,
    startup_timeout_message: &'static str,
    run_listen_loop: F,
) -> Result<ListenerThread<T>, HotkeyInstallError>
where
    T: Send + 'static,
    F: FnOnce(Arc<Shared>, Sender<HotkeyEvent>, StartupTx<T>) + Send + 'static,
{
    let shared = Arc::new(Shared {
        binding: RwLock::new(binding),
        pressed_codes: RwLock::new(BTreeSet::new()),
        trigger_held: AtomicBool::new(false),
        translation_modifier_held: AtomicBool::new(false),
    });

    let thread_shared = Arc::clone(&shared);
    let (status_tx, status_rx) = mpsc::channel::<Result<T, HotkeyInstallError>>();
    std::thread::Builder::new()
        .name(thread_name.into())
        .spawn(move || run_listen_loop(thread_shared, tx, status_tx))
        .map_err(|e| install_error("spawn_failed", format!("hotkey 线程启动失败: {e}")))?;

    match status_rx.recv_timeout(Duration::from_secs(3)) {
        Ok(Ok(startup)) => Ok(ListenerThread { shared, startup }),
        Ok(Err(err)) => Err(err),
        Err(_) => Err(install_error("startup_timeout", startup_timeout_message)),
    }
}

fn update_shared_binding(shared: &Shared, binding: HotkeyBinding) {
    *shared.binding.write() = binding;
    shared.pressed_codes.write().clear();
    shared
        .trigger_held
        .store(false, std::sync::atomic::Ordering::SeqCst);
}

fn dispatch_hotkey_code(shared: &Shared, tx: &Sender<HotkeyEvent>, code: &str, pressed: bool) {
    if code.is_empty() {
        return;
    }
    let binding = shared.binding.read().clone();
    let active_after = {
        let mut pressed_codes = shared.pressed_codes.write();
        if pressed {
            pressed_codes.insert(code.to_string());
        } else {
            pressed_codes.remove(code);
        }
        binding_matches_pressed_codes(&binding, &pressed_codes)
    };
    let was_active = shared
        .trigger_held
        .swap(active_after, std::sync::atomic::Ordering::SeqCst);
    if active_after && !was_active {
        send_or_log(tx, HotkeyEvent::Pressed);
    } else if !active_after && was_active {
        send_or_log(tx, HotkeyEvent::Released);
    }
}

fn dispatch_translation_modifier_code(
    shared: &Shared,
    tx: &Sender<HotkeyEvent>,
    code: &str,
    pressed: bool,
) {
    if !is_shift_hotkey_code(code) {
        return;
    }

    let shift_is_hotkey = shared
        .binding
        .read()
        .effective_codes()
        .iter()
        .any(|candidate| candidate == code);
    if shift_is_hotkey {
        return;
    }

    if pressed {
        let was_held = shared
            .translation_modifier_held
            .swap(true, Ordering::SeqCst);
        if !was_held {
            send_or_log(tx, HotkeyEvent::TranslationModifierPressed);
        }
    } else {
        shared
            .translation_modifier_held
            .store(false, Ordering::SeqCst);
    }
}

fn is_shift_hotkey_code(code: &str) -> bool {
    matches!(code, "ShiftLeft" | "ShiftRight")
}

#[cfg(any(target_os = "macos", test))]
fn dispatch_mac_caps_lock_flags_changed(
    shared: &Shared,
    tx: &Sender<HotkeyEvent>,
    alpha_shift_active: bool,
) {
    if shared.binding.read().mode == crate::types::HotkeyMode::Hold {
        dispatch_hotkey_code(shared, tx, "CapsLock", alpha_shift_active);
    } else {
        dispatch_hotkey_code(shared, tx, "CapsLock", true);
        dispatch_hotkey_code(shared, tx, "CapsLock", false);
    }
}

#[cfg(any(target_os = "macos", test))]
fn mac_keycode_uses_modifier_flags(keycode: i64) -> bool {
    matches!(keycode, 54 | 55 | 56 | 58 | 59 | 60 | 61 | 62 | 63)
}

pub(crate) fn binding_matches_pressed_codes(
    binding: &HotkeyBinding,
    pressed_codes: &BTreeSet<String>,
) -> bool {
    let codes = binding.effective_codes();
    !codes.is_empty()
        && codes
            .iter()
            .all(|code| pressed_codes.contains(code.as_str()))
}

// ─────────────────────────── macOS implementation ───────────────────────────

#[cfg(target_os = "macos")]
mod platform {
    use std::ffi::c_void;
    use std::sync::mpsc::Sender;
    use std::sync::Arc;

    use super::{
        dispatch_hotkey_code, dispatch_mac_caps_lock_flags_changed,
        dispatch_translation_modifier_code, install_error, is_shift_hotkey_code,
        mac_keycode_uses_modifier_flags, send_or_log, start_listener_thread, update_shared_binding,
        HotkeyAdapter, HotkeyEvent, Shared, StartupTx,
    };
    use crate::types::{HotkeyAdapterKind, HotkeyBinding, HotkeyInstallError};

    pub fn start_adapter(
        binding: HotkeyBinding,
        tx: Sender<HotkeyEvent>,
    ) -> Result<Box<dyn HotkeyAdapter>, HotkeyInstallError> {
        let listener = start_listener_thread(
            binding,
            tx,
            "openless-hotkey-mac-event-tap",
            "hotkey hook 启动超时",
            run_listen_loop,
        )?;
        listener.startup;
        Ok(Box::new(MacHotkeyAdapter {
            shared: listener.shared,
        }))
    }

    struct MacHotkeyAdapter {
        shared: Arc<Shared>,
    }

    impl HotkeyAdapter for MacHotkeyAdapter {
        fn kind(&self) -> HotkeyAdapterKind {
            HotkeyAdapterKind::MacEventTap
        }

        fn update_binding(&self, binding: HotkeyBinding) {
            update_shared_binding(&self.shared, binding);
        }
    }

    // ── Raw CG/CF FFI ──────────────────────────────────────────────────────

    #[repr(C)]
    struct OpaqueCgEvent(c_void);
    type CgEventRef = *mut OpaqueCgEvent;

    #[repr(C)]
    struct OpaqueCfMachPort(c_void);
    type CfMachPortRef = *mut OpaqueCfMachPort;

    #[repr(C)]
    struct OpaqueCfRunLoop(c_void);
    type CfRunLoopRef = *mut OpaqueCfRunLoop;

    #[repr(C)]
    struct OpaqueCfRunLoopSource(c_void);
    type CfRunLoopSourceRef = *mut OpaqueCfRunLoopSource;

    type CfStringRef = *const c_void;
    type CfAllocatorRef = *const c_void;

    type CgEventMask = u64;
    type CgEventType = u32;
    type CgEventTapLocation = u32;
    type CgEventTapPlacement = u32;
    type CgEventTapOptions = u32;
    type CgEventField = u32;
    type CgEventFlags = u64;

    const SESSION_EVENT_TAP: CgEventTapLocation = 1;
    const HEAD_INSERT: CgEventTapPlacement = 0;
    const TAP_OPTION_DEFAULT: CgEventTapOptions = 0;

    const KEY_DOWN: CgEventType = 10;
    const KEY_UP: CgEventType = 11;
    const FLAGS_CHANGED: CgEventType = 12;
    const OTHER_MOUSE_DOWN: CgEventType = 25;
    const OTHER_MOUSE_UP: CgEventType = 26;
    const TAP_DISABLED_BY_TIMEOUT: CgEventType = 0xFFFF_FFFE;
    const TAP_DISABLED_BY_USER_INPUT: CgEventType = 0xFFFF_FFFF;

    const MOUSE_EVENT_BUTTON_NUMBER: CgEventField = 3;
    const KEYBOARD_EVENT_KEYCODE: CgEventField = 9;

    const FLAG_MASK_ALPHA_SHIFT: CgEventFlags = 0x0001_0000;
    const FLAG_MASK_SHIFT: CgEventFlags = 0x0002_0000;
    const FLAG_MASK_CONTROL: CgEventFlags = 0x0004_0000;
    const FLAG_MASK_ALTERNATE: CgEventFlags = 0x0008_0000;
    const FLAG_MASK_COMMAND: CgEventFlags = 0x0010_0000;
    const FLAG_MASK_SECONDARY_FN: CgEventFlags = 0x0080_0000;

    const ESC_KEYCODE: i64 = 53;

    type CgEventTapCallBack = extern "C" fn(
        proxy: *mut c_void,
        event_type: CgEventType,
        event: CgEventRef,
        user_info: *mut c_void,
    ) -> CgEventRef;

    #[link(name = "CoreGraphics", kind = "framework")]
    extern "C" {
        fn CGEventTapCreate(
            tap: CgEventTapLocation,
            place: CgEventTapPlacement,
            options: CgEventTapOptions,
            events_of_interest: CgEventMask,
            callback: CgEventTapCallBack,
            user_info: *mut c_void,
        ) -> CfMachPortRef;
        fn CGEventTapEnable(tap: CfMachPortRef, enable: bool);
        fn CGEventGetIntegerValueField(event: CgEventRef, field: CgEventField) -> i64;
        fn CGEventGetFlags(event: CgEventRef) -> CgEventFlags;
    }

    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        fn CFMachPortCreateRunLoopSource(
            allocator: CfAllocatorRef,
            port: CfMachPortRef,
            order: isize,
        ) -> CfRunLoopSourceRef;
        fn CFRunLoopGetCurrent() -> CfRunLoopRef;
        fn CFRunLoopAddSource(rl: CfRunLoopRef, source: CfRunLoopSourceRef, mode: CfStringRef);
        fn CFRunLoopRun();
        static kCFRunLoopCommonModes: CfStringRef;
    }

    struct CallbackContext {
        shared: Arc<Shared>,
        tx: Sender<HotkeyEvent>,
        tap: std::sync::Mutex<Option<CfMachPortRef>>,
    }

    unsafe impl Send for CallbackContext {}
    unsafe impl Sync for CallbackContext {}

    fn run_listen_loop(shared: Arc<Shared>, tx: Sender<HotkeyEvent>, status_tx: StartupTx<()>) {
        let mask: CgEventMask = (1u64 << FLAGS_CHANGED)
            | (1u64 << KEY_DOWN)
            | (1u64 << KEY_UP)
            | (1u64 << OTHER_MOUSE_DOWN)
            | (1u64 << OTHER_MOUSE_UP);
        let context = Box::into_raw(Box::new(CallbackContext {
            shared,
            tx,
            tap: std::sync::Mutex::new(None),
        }));

        unsafe {
            let tap = CGEventTapCreate(
                SESSION_EVENT_TAP,
                HEAD_INSERT,
                TAP_OPTION_DEFAULT,
                mask,
                tap_callback,
                context as *mut c_void,
            );
            if tap.is_null() {
                log::warn!(
                    "[hotkey] CGEventTapCreate 失败 — Accessibility 权限未授予。Coordinator 会重试。"
                );
                let _ = Box::from_raw(context);
                let _ = status_tx.send(Err(install_error(
                    "accessibility_denied",
                    "hotkey hook 安装失败（辅助功能权限未授予）",
                )));
                return;
            }
            *(*context).tap.lock().unwrap() = Some(tap);

            let source = CFMachPortCreateRunLoopSource(std::ptr::null(), tap, 0);
            let runloop = CFRunLoopGetCurrent();
            CFRunLoopAddSource(runloop, source, kCFRunLoopCommonModes);
            CGEventTapEnable(tap, true);

            log::info!("[hotkey] CGEventTap 已启动");
            let _ = status_tx.send(Ok(()));
            CFRunLoopRun();
        }
    }

    extern "C" fn tap_callback(
        _proxy: *mut c_void,
        event_type: CgEventType,
        event: CgEventRef,
        user_info: *mut c_void,
    ) -> CgEventRef {
        if user_info.is_null() {
            return event;
        }
        let ctx = unsafe { &*(user_info as *const CallbackContext) };

        match event_type {
            TAP_DISABLED_BY_TIMEOUT | TAP_DISABLED_BY_USER_INPUT => {
                if let Some(tap) = *ctx.tap.lock().unwrap() {
                    unsafe { CGEventTapEnable(tap, true) };
                }
                return event;
            }
            FLAGS_CHANGED => handle_flags_changed(ctx, event),
            KEY_DOWN => handle_key_down(ctx, event),
            KEY_UP => handle_key_up(ctx, event),
            OTHER_MOUSE_DOWN => handle_mouse_button(ctx, event, true),
            OTHER_MOUSE_UP => handle_mouse_button(ctx, event, false),
            _ => {}
        }
        event
    }

    fn handle_flags_changed(ctx: &CallbackContext, event: CgEventRef) {
        let flags = unsafe { CGEventGetFlags(event) };
        let keycode = unsafe { CGEventGetIntegerValueField(event, KEYBOARD_EVENT_KEYCODE) };
        if keycode == 57 {
            dispatch_mac_caps_lock_flags_changed(
                &ctx.shared,
                &ctx.tx,
                (flags & FLAG_MASK_ALPHA_SHIFT) != 0,
            );
            return;
        }
        if let Some(code) = mac_keycode_to_hotkey_code(keycode) {
            if is_shift_hotkey_code(code) {
                // Shift 作为录音热键成员时只参与热键匹配，不再额外切到翻译模式。
                dispatch_translation_modifier_code(
                    &ctx.shared,
                    &ctx.tx,
                    code,
                    (flags & FLAG_MASK_SHIFT) != 0,
                );
            }
            if let Some(mask) = mac_keycode_flag_mask(keycode) {
                let family_active = (flags & mask) != 0;
                let code_was_pressed = ctx.shared.pressed_codes.read().contains(code);
                dispatch_hotkey_code(
                    &ctx.shared,
                    &ctx.tx,
                    code,
                    family_active && !code_was_pressed,
                );
            }
        }
    }

    fn handle_key_down(ctx: &CallbackContext, event: CgEventRef) {
        let keycode = unsafe { CGEventGetIntegerValueField(event, KEYBOARD_EVENT_KEYCODE) };
        if keycode == ESC_KEYCODE {
            send_or_log(&ctx.tx, HotkeyEvent::Cancelled);
            return;
        }
        if let Some(code) = mac_keycode_to_hotkey_code(keycode) {
            if mac_keycode_flag_mask(keycode).is_none() {
                dispatch_hotkey_code(&ctx.shared, &ctx.tx, code, true);
            }
        }
    }

    fn handle_key_up(ctx: &CallbackContext, event: CgEventRef) {
        let keycode = unsafe { CGEventGetIntegerValueField(event, KEYBOARD_EVENT_KEYCODE) };
        if let Some(code) = mac_keycode_to_hotkey_code(keycode) {
            if mac_keycode_flag_mask(keycode).is_none() {
                dispatch_hotkey_code(&ctx.shared, &ctx.tx, code, false);
            }
        }
    }

    fn handle_mouse_button(ctx: &CallbackContext, event: CgEventRef, pressed: bool) {
        let button = unsafe { CGEventGetIntegerValueField(event, MOUSE_EVENT_BUTTON_NUMBER) };
        let code = match button {
            3 => "Mouse4",
            4 => "Mouse5",
            _ => return,
        };
        dispatch_hotkey_code(&ctx.shared, &ctx.tx, code, pressed);
    }

    fn mac_keycode_flag_mask(keycode: i64) -> Option<CgEventFlags> {
        if !mac_keycode_uses_modifier_flags(keycode) {
            return None;
        }
        match keycode {
            54 | 55 => Some(FLAG_MASK_COMMAND),
            56 | 60 => Some(FLAG_MASK_SHIFT),
            58 | 61 => Some(FLAG_MASK_ALTERNATE),
            59 | 62 => Some(FLAG_MASK_CONTROL),
            63 => Some(FLAG_MASK_SECONDARY_FN),
            _ => None,
        }
    }

    fn mac_keycode_to_hotkey_code(keycode: i64) -> Option<&'static str> {
        match keycode {
            0 => Some("KeyA"),
            1 => Some("KeyS"),
            2 => Some("KeyD"),
            3 => Some("KeyF"),
            4 => Some("KeyH"),
            5 => Some("KeyG"),
            6 => Some("KeyZ"),
            7 => Some("KeyX"),
            8 => Some("KeyC"),
            9 => Some("KeyV"),
            11 => Some("KeyB"),
            12 => Some("KeyQ"),
            13 => Some("KeyW"),
            14 => Some("KeyE"),
            15 => Some("KeyR"),
            16 => Some("KeyY"),
            17 => Some("KeyT"),
            18 => Some("Digit1"),
            19 => Some("Digit2"),
            20 => Some("Digit3"),
            21 => Some("Digit4"),
            22 => Some("Digit6"),
            23 => Some("Digit5"),
            24 => Some("Equal"),
            25 => Some("Digit9"),
            26 => Some("Digit7"),
            27 => Some("Minus"),
            28 => Some("Digit8"),
            29 => Some("Digit0"),
            30 => Some("BracketRight"),
            31 => Some("KeyO"),
            32 => Some("KeyU"),
            33 => Some("BracketLeft"),
            34 => Some("KeyI"),
            35 => Some("KeyP"),
            36 => Some("Enter"),
            37 => Some("KeyL"),
            38 => Some("KeyJ"),
            39 => Some("Quote"),
            40 => Some("KeyK"),
            41 => Some("Semicolon"),
            42 => Some("Backslash"),
            43 => Some("Comma"),
            44 => Some("Slash"),
            45 => Some("KeyN"),
            46 => Some("KeyM"),
            47 => Some("Period"),
            48 => Some("Tab"),
            49 => Some("Space"),
            50 => Some("Backquote"),
            51 => Some("Backspace"),
            54 => Some("MetaRight"),
            55 => Some("MetaLeft"),
            56 => Some("ShiftLeft"),
            57 => Some("CapsLock"),
            58 => Some("AltLeft"),
            59 => Some("ControlLeft"),
            60 => Some("ShiftRight"),
            61 => Some("AltRight"),
            62 => Some("ControlRight"),
            63 => Some("Fn"),
            64 => Some("F17"),
            65 => Some("NumpadDecimal"),
            67 => Some("NumpadMultiply"),
            69 => Some("NumpadAdd"),
            75 => Some("NumpadDivide"),
            76 => Some("NumpadEnter"),
            78 => Some("NumpadSubtract"),
            79 => Some("F18"),
            80 => Some("F19"),
            82 => Some("Numpad0"),
            83 => Some("Numpad1"),
            84 => Some("Numpad2"),
            85 => Some("Numpad3"),
            86 => Some("Numpad4"),
            87 => Some("Numpad5"),
            88 => Some("Numpad6"),
            89 => Some("Numpad7"),
            91 => Some("Numpad8"),
            92 => Some("Numpad9"),
            96 => Some("F5"),
            97 => Some("F6"),
            98 => Some("F7"),
            99 => Some("F3"),
            100 => Some("F8"),
            101 => Some("F9"),
            103 => Some("F11"),
            105 => Some("F13"),
            106 => Some("F16"),
            107 => Some("F14"),
            109 => Some("F10"),
            111 => Some("F12"),
            113 => Some("F15"),
            115 => Some("Home"),
            116 => Some("PageUp"),
            117 => Some("Delete"),
            118 => Some("F4"),
            119 => Some("End"),
            120 => Some("F2"),
            121 => Some("PageDown"),
            122 => Some("F1"),
            123 => Some("ArrowLeft"),
            124 => Some("ArrowRight"),
            125 => Some("ArrowDown"),
            126 => Some("ArrowUp"),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{HotkeyKey, HotkeyMode, HotkeyTrigger};

    fn shared_with_binding(binding: HotkeyBinding) -> Shared {
        Shared {
            binding: RwLock::new(binding),
            pressed_codes: RwLock::new(BTreeSet::new()),
            trigger_held: AtomicBool::new(false),
            translation_modifier_held: AtomicBool::new(false),
        }
    }

    #[test]
    fn shift_hotkey_press_does_not_emit_translation_modifier() {
        let shared = shared_with_binding(HotkeyBinding {
            trigger: HotkeyTrigger::RightControl,
            mode: HotkeyMode::Toggle,
            keys: Some(vec![HotkeyKey::new("ShiftLeft")]),
        });
        let (tx, rx) = mpsc::channel();

        dispatch_translation_modifier_code(&shared, &tx, "ShiftLeft", true);
        assert!(rx.try_recv().is_err());

        dispatch_hotkey_code(&shared, &tx, "ShiftLeft", true);
        assert!(matches!(rx.try_recv(), Ok(HotkeyEvent::Pressed)));
    }

    #[test]
    fn unbound_shift_press_still_emits_translation_modifier_once_per_hold() {
        let shared = shared_with_binding(HotkeyBinding {
            trigger: HotkeyTrigger::RightControl,
            mode: HotkeyMode::Toggle,
            keys: Some(vec![HotkeyKey::new("ControlRight")]),
        });
        let (tx, rx) = mpsc::channel();

        dispatch_translation_modifier_code(&shared, &tx, "ShiftLeft", true);
        assert!(matches!(
            rx.try_recv(),
            Ok(HotkeyEvent::TranslationModifierPressed)
        ));

        dispatch_translation_modifier_code(&shared, &tx, "ShiftLeft", true);
        assert!(rx.try_recv().is_err());

        dispatch_translation_modifier_code(&shared, &tx, "ShiftLeft", false);
        dispatch_translation_modifier_code(&shared, &tx, "ShiftLeft", true);
        assert!(matches!(
            rx.try_recv(),
            Ok(HotkeyEvent::TranslationModifierPressed)
        ));
    }

    #[test]
    fn mac_caps_lock_toggle_mode_dispatches_click_edge_per_toggle() {
        let shared = shared_with_binding(HotkeyBinding {
            trigger: HotkeyTrigger::RightControl,
            mode: HotkeyMode::Toggle,
            keys: Some(vec![HotkeyKey::new("CapsLock")]),
        });
        let (tx, rx) = mpsc::channel();

        dispatch_mac_caps_lock_flags_changed(&shared, &tx, true);

        assert!(matches!(rx.try_recv(), Ok(HotkeyEvent::Pressed)));
        assert!(matches!(rx.try_recv(), Ok(HotkeyEvent::Released)));
        assert!(rx.try_recv().is_err());
    }

    #[test]
    fn mac_caps_lock_double_click_mode_dispatches_click_edge_per_toggle() {
        let shared = shared_with_binding(HotkeyBinding {
            trigger: HotkeyTrigger::RightControl,
            mode: HotkeyMode::DoubleClick,
            keys: Some(vec![HotkeyKey::new("CapsLock")]),
        });
        let (tx, rx) = mpsc::channel();

        dispatch_mac_caps_lock_flags_changed(&shared, &tx, true);

        assert!(matches!(rx.try_recv(), Ok(HotkeyEvent::Pressed)));
        assert!(matches!(rx.try_recv(), Ok(HotkeyEvent::Released)));
        assert!(rx.try_recv().is_err());
    }

    #[test]
    fn mac_caps_lock_hold_mode_tracks_toggle_state() {
        let shared = shared_with_binding(HotkeyBinding {
            trigger: HotkeyTrigger::RightControl,
            mode: HotkeyMode::Hold,
            keys: Some(vec![HotkeyKey::new("CapsLock")]),
        });
        let (tx, rx) = mpsc::channel();

        dispatch_mac_caps_lock_flags_changed(&shared, &tx, true);

        assert!(matches!(rx.try_recv(), Ok(HotkeyEvent::Pressed)));
        assert!(rx.try_recv().is_err());

        dispatch_mac_caps_lock_flags_changed(&shared, &tx, false);

        assert!(matches!(rx.try_recv(), Ok(HotkeyEvent::Released)));
        assert!(rx.try_recv().is_err());
    }

    #[test]
    fn mac_caps_lock_is_not_a_modifier_flag_code() {
        assert!(!mac_keycode_uses_modifier_flags(57));
    }
}

// ─────────────────────────── Windows implementation ───────────────────────────

#[cfg(target_os = "windows")]
mod platform {
    use std::sync::atomic::{AtomicPtr, Ordering as AtomicOrdering};
    use std::sync::mpsc::Sender;
    use std::sync::Arc;

    use windows::Win32::Foundation::{LPARAM, LRESULT, WPARAM};
    use windows::Win32::System::Threading::GetCurrentThreadId;
    use windows::Win32::UI::WindowsAndMessaging::{
        CallNextHookEx, DispatchMessageW, GetMessageW, PostThreadMessageW, SetWindowsHookExW,
        TranslateMessage, UnhookWindowsHookEx, HC_ACTION, HHOOK, KBDLLHOOKSTRUCT, MSG,
        MSLLHOOKSTRUCT, WH_KEYBOARD_LL, WH_MOUSE_LL, WM_QUIT,
    };

    use super::{
        dispatch_hotkey_code, dispatch_translation_modifier_code, install_error, send_or_log,
        start_listener_thread, update_shared_binding, HotkeyAdapter, HotkeyEvent, Shared,
        StartupTx,
    };
    use crate::types::{HotkeyAdapterKind, HotkeyBinding, HotkeyInstallError};

    const WM_KEYDOWN: usize = 0x0100;
    const WM_KEYUP: usize = 0x0101;
    const WM_SYSKEYDOWN: usize = 0x0104;
    const WM_SYSKEYUP: usize = 0x0105;
    const WM_XBUTTONDOWN: usize = 0x020B;
    const WM_XBUTTONUP: usize = 0x020C;

    const VK_BACK: u32 = 0x08;
    const VK_TAB: u32 = 0x09;
    const VK_RETURN: u32 = 0x0D;
    const VK_ESCAPE: u32 = 0x1B;
    const VK_SHIFT: u32 = 0x10;
    const VK_CONTROL: u32 = 0x11;
    const VK_MENU: u32 = 0x12;
    const VK_PAUSE: u32 = 0x13;
    const VK_CAPITAL: u32 = 0x14;
    const VK_SPACE: u32 = 0x20;
    const VK_PRIOR: u32 = 0x21;
    const VK_NEXT: u32 = 0x22;
    const VK_END: u32 = 0x23;
    const VK_HOME: u32 = 0x24;
    const VK_LEFT: u32 = 0x25;
    const VK_UP: u32 = 0x26;
    const VK_RIGHT: u32 = 0x27;
    const VK_DOWN: u32 = 0x28;
    const VK_SNAPSHOT: u32 = 0x2C;
    const VK_INSERT: u32 = 0x2D;
    const VK_DELETE: u32 = 0x2E;
    const VK_APPS: u32 = 0x5D;
    const VK_LWIN: u32 = 0x5B;
    const VK_RWIN: u32 = 0x5C;
    const VK_MULTIPLY: u32 = 0x6A;
    const VK_ADD: u32 = 0x6B;
    const VK_SUBTRACT: u32 = 0x6D;
    const VK_DECIMAL: u32 = 0x6E;
    const VK_DIVIDE: u32 = 0x6F;
    const VK_SCROLL: u32 = 0x91;
    const VK_LSHIFT: u32 = 0xA0;
    const VK_RSHIFT: u32 = 0xA1;
    const VK_LCONTROL: u32 = 0xA2;
    const VK_RCONTROL: u32 = 0xA3;
    const VK_LMENU: u32 = 0xA4;
    const VK_RMENU: u32 = 0xA5;
    const VK_OEM_1: u32 = 0xBA;
    const VK_OEM_PLUS: u32 = 0xBB;
    const VK_OEM_COMMA: u32 = 0xBC;
    const VK_OEM_MINUS: u32 = 0xBD;
    const VK_OEM_PERIOD: u32 = 0xBE;
    const VK_OEM_2: u32 = 0xBF;
    const VK_OEM_3: u32 = 0xC0;
    const VK_OEM_4: u32 = 0xDB;
    const VK_OEM_5: u32 = 0xDC;
    const VK_OEM_6: u32 = 0xDD;
    const VK_OEM_7: u32 = 0xDE;
    const XBUTTON1: u32 = 0x0001;
    const XBUTTON2: u32 = 0x0002;
    const LLKHF_INJECTED: u32 = 0x0000_0010;
    const ACCEPT_INJECTED_ENV: &str = "OPENLESS_ACCEPT_SYNTHETIC_HOTKEY_EVENTS";

    static HOOK_CONTEXT: AtomicPtr<CallbackContext> = AtomicPtr::new(std::ptr::null_mut());

    pub fn start_adapter(
        binding: HotkeyBinding,
        tx: Sender<HotkeyEvent>,
    ) -> Result<Box<dyn HotkeyAdapter>, HotkeyInstallError> {
        let listener = start_listener_thread(
            binding,
            tx,
            "openless-hotkey-win-ll-hook",
            "Windows hotkey hook 启动超时",
            run_listen_loop,
        )?;
        Ok(Box::new(WindowsHotkeyAdapter {
            shared: listener.shared,
            thread_id: listener.startup,
        }))
    }

    struct WindowsHotkeyAdapter {
        shared: Arc<Shared>,
        thread_id: u32,
    }

    impl HotkeyAdapter for WindowsHotkeyAdapter {
        fn kind(&self) -> HotkeyAdapterKind {
            HotkeyAdapterKind::WindowsLowLevel
        }

        fn update_binding(&self, binding: HotkeyBinding) {
            update_shared_binding(&self.shared, binding);
        }

        fn shutdown(&self) {
            unsafe {
                if let Err(err) = PostThreadMessageW(self.thread_id, WM_QUIT, WPARAM(0), LPARAM(0))
                {
                    log::warn!("[hotkey] Windows hook 退出消息发送失败: {err}");
                }
            }
        }
    }

    struct CallbackContext {
        shared: Arc<Shared>,
        tx: Sender<HotkeyEvent>,
        keyboard_hook: std::sync::Mutex<Option<HHOOK>>,
        mouse_hook: std::sync::Mutex<Option<HHOOK>>,
    }

    unsafe impl Send for CallbackContext {}
    unsafe impl Sync for CallbackContext {}

    fn run_listen_loop(shared: Arc<Shared>, tx: Sender<HotkeyEvent>, status_tx: StartupTx<u32>) {
        let thread_id = unsafe { GetCurrentThreadId() };
        let context = Box::into_raw(Box::new(CallbackContext {
            shared,
            tx,
            keyboard_hook: std::sync::Mutex::new(None),
            mouse_hook: std::sync::Mutex::new(None),
        }));
        HOOK_CONTEXT.store(context, AtomicOrdering::SeqCst);

        unsafe {
            let hook = SetWindowsHookExW(WH_KEYBOARD_LL, Some(low_level_keyboard_proc), None, 0);
            match hook {
                Ok(hook) => {
                    *(*context).keyboard_hook.lock().unwrap() = Some(hook);
                    log::info!("[hotkey] Windows low-level keyboard hook 已启动");
                }
                Err(err) => {
                    HOOK_CONTEXT.store(std::ptr::null_mut(), AtomicOrdering::SeqCst);
                    let _ = Box::from_raw(context);
                    let _ = status_tx.send(Err(install_error(
                        "hook_install_failed",
                        format!("Windows low-level keyboard hook 安装失败: {err}"),
                    )));
                    return;
                }
            }

            match SetWindowsHookExW(WH_MOUSE_LL, Some(low_level_mouse_proc), None, 0) {
                Ok(hook) => {
                    *(*context).mouse_hook.lock().unwrap() = Some(hook);
                    log::info!("[hotkey] Windows low-level mouse hook installed");
                }
                Err(err) => {
                    log::warn!(
                        "[hotkey] Windows low-level mouse hook install failed; Mouse4/Mouse5 hotkeys will be unavailable: {err}"
                    );
                }
            }
            let _ = status_tx.send(Ok(thread_id));

            let mut message = MSG::default();
            loop {
                let result = GetMessageW(&mut message, None, 0, 0).0;
                if result == -1 {
                    log::error!("[hotkey] Windows GetMessageW 返回错误，hook 线程退出");
                    break;
                }
                if result == 0 {
                    log::warn!("[hotkey] Windows hook 消息循环收到退出消息");
                    break;
                }
                let _ = TranslateMessage(&message);
                let _ = DispatchMessageW(&message);
            }

            if let Some(hook) = (*context).keyboard_hook.lock().unwrap().take() {
                let _ = UnhookWindowsHookEx(hook);
            }
            if let Some(hook) = (*context).mouse_hook.lock().unwrap().take() {
                let _ = UnhookWindowsHookEx(hook);
            }
            HOOK_CONTEXT.store(std::ptr::null_mut(), AtomicOrdering::SeqCst);
            let _ = Box::from_raw(context);
        }
    }

    unsafe extern "system" fn low_level_keyboard_proc(
        code: i32,
        wparam: WPARAM,
        lparam: LPARAM,
    ) -> LRESULT {
        if code == HC_ACTION as i32 && lparam.0 != 0 {
            if let Some(ctx) = callback_context() {
                let keyboard = *(lparam.0 as *const KBDLLHOOKSTRUCT);
                if keyboard.flags.0 & LLKHF_INJECTED == 0 || accept_injected_events() {
                    dispatch_keyboard_event(ctx, keyboard.vkCode, wparam.0);
                }
            }
        }

        CallNextHookEx(None, code, wparam, lparam)
    }

    unsafe extern "system" fn low_level_mouse_proc(
        code: i32,
        wparam: WPARAM,
        lparam: LPARAM,
    ) -> LRESULT {
        if code == HC_ACTION as i32 && lparam.0 != 0 {
            if let Some(ctx) = callback_context() {
                let mouse = *(lparam.0 as *const MSLLHOOKSTRUCT);
                dispatch_mouse_event(ctx, mouse.mouseData, wparam.0);
            }
        }

        CallNextHookEx(None, code, wparam, lparam)
    }

    unsafe fn callback_context<'a>() -> Option<&'a CallbackContext> {
        let ptr = HOOK_CONTEXT.load(AtomicOrdering::SeqCst);
        if ptr.is_null() {
            None
        } else {
            Some(&*ptr)
        }
    }

    fn dispatch_keyboard_event(ctx: &CallbackContext, vk_code: u32, message: usize) {
        let is_down = matches!(message, WM_KEYDOWN | WM_SYSKEYDOWN);
        let is_up = matches!(message, WM_KEYUP | WM_SYSKEYUP);

        if vk_code == VK_ESCAPE && is_down {
            send_or_log(&ctx.tx, HotkeyEvent::Cancelled);
            return;
        }

        if let Some(code) = vk_to_hotkey_code(vk_code) {
            if matches!(vk_code, VK_SHIFT | VK_LSHIFT | VK_RSHIFT) {
                // Shift 作为录音热键成员时只参与热键匹配，不再额外切到翻译模式。
                dispatch_translation_modifier_code(&ctx.shared, &ctx.tx, code, is_down);
            }
            if is_down {
                dispatch_hotkey_code(&ctx.shared, &ctx.tx, code, true);
            } else if is_up {
                dispatch_hotkey_code(&ctx.shared, &ctx.tx, code, false);
            }
        }
    }

    fn dispatch_mouse_event(ctx: &CallbackContext, mouse_data: u32, message: usize) {
        let code = match ((mouse_data >> 16) & 0xffff, message) {
            (XBUTTON1, WM_XBUTTONDOWN | WM_XBUTTONUP) => "Mouse4",
            (XBUTTON2, WM_XBUTTONDOWN | WM_XBUTTONUP) => "Mouse5",
            _ => return,
        };
        dispatch_hotkey_code(&ctx.shared, &ctx.tx, code, message == WM_XBUTTONDOWN);
    }

    fn vk_to_hotkey_code(vk_code: u32) -> Option<&'static str> {
        match vk_code {
            VK_SHIFT => Some("ShiftLeft"),
            VK_LSHIFT => Some("ShiftLeft"),
            VK_RSHIFT => Some("ShiftRight"),
            VK_CONTROL => Some("ControlLeft"),
            VK_LCONTROL => Some("ControlLeft"),
            VK_RCONTROL => Some("ControlRight"),
            VK_MENU => Some("AltLeft"),
            VK_LMENU => Some("AltLeft"),
            VK_RMENU => Some("AltRight"),
            VK_LWIN => Some("MetaLeft"),
            VK_RWIN => Some("MetaRight"),
            VK_BACK => Some("Backspace"),
            VK_TAB => Some("Tab"),
            VK_RETURN => Some("Enter"),
            VK_CAPITAL => Some("CapsLock"),
            VK_PAUSE => Some("Pause"),
            VK_SPACE => Some("Space"),
            VK_PRIOR => Some("PageUp"),
            VK_NEXT => Some("PageDown"),
            VK_END => Some("End"),
            VK_HOME => Some("Home"),
            VK_LEFT => Some("ArrowLeft"),
            VK_UP => Some("ArrowUp"),
            VK_RIGHT => Some("ArrowRight"),
            VK_DOWN => Some("ArrowDown"),
            VK_SNAPSHOT => Some("PrintScreen"),
            VK_INSERT => Some("Insert"),
            VK_DELETE => Some("Delete"),
            VK_APPS => Some("ContextMenu"),
            VK_MULTIPLY => Some("NumpadMultiply"),
            VK_ADD => Some("NumpadAdd"),
            VK_SUBTRACT => Some("NumpadSubtract"),
            VK_DECIMAL => Some("NumpadDecimal"),
            VK_DIVIDE => Some("NumpadDivide"),
            VK_SCROLL => Some("ScrollLock"),
            VK_OEM_1 => Some("Semicolon"),
            VK_OEM_PLUS => Some("Equal"),
            VK_OEM_COMMA => Some("Comma"),
            VK_OEM_MINUS => Some("Minus"),
            VK_OEM_PERIOD => Some("Period"),
            VK_OEM_2 => Some("Slash"),
            VK_OEM_3 => Some("Backquote"),
            VK_OEM_4 => Some("BracketLeft"),
            VK_OEM_5 => Some("Backslash"),
            VK_OEM_6 => Some("BracketRight"),
            VK_OEM_7 => Some("Quote"),
            0x30 => Some("Digit0"),
            0x31 => Some("Digit1"),
            0x32 => Some("Digit2"),
            0x33 => Some("Digit3"),
            0x34 => Some("Digit4"),
            0x35 => Some("Digit5"),
            0x36 => Some("Digit6"),
            0x37 => Some("Digit7"),
            0x38 => Some("Digit8"),
            0x39 => Some("Digit9"),
            0x41 => Some("KeyA"),
            0x42 => Some("KeyB"),
            0x43 => Some("KeyC"),
            0x44 => Some("KeyD"),
            0x45 => Some("KeyE"),
            0x46 => Some("KeyF"),
            0x47 => Some("KeyG"),
            0x48 => Some("KeyH"),
            0x49 => Some("KeyI"),
            0x4A => Some("KeyJ"),
            0x4B => Some("KeyK"),
            0x4C => Some("KeyL"),
            0x4D => Some("KeyM"),
            0x4E => Some("KeyN"),
            0x4F => Some("KeyO"),
            0x50 => Some("KeyP"),
            0x51 => Some("KeyQ"),
            0x52 => Some("KeyR"),
            0x53 => Some("KeyS"),
            0x54 => Some("KeyT"),
            0x55 => Some("KeyU"),
            0x56 => Some("KeyV"),
            0x57 => Some("KeyW"),
            0x58 => Some("KeyX"),
            0x59 => Some("KeyY"),
            0x5A => Some("KeyZ"),
            0x60 => Some("Numpad0"),
            0x61 => Some("Numpad1"),
            0x62 => Some("Numpad2"),
            0x63 => Some("Numpad3"),
            0x64 => Some("Numpad4"),
            0x65 => Some("Numpad5"),
            0x66 => Some("Numpad6"),
            0x67 => Some("Numpad7"),
            0x68 => Some("Numpad8"),
            0x69 => Some("Numpad9"),
            0x70 => Some("F1"),
            0x71 => Some("F2"),
            0x72 => Some("F3"),
            0x73 => Some("F4"),
            0x74 => Some("F5"),
            0x75 => Some("F6"),
            0x76 => Some("F7"),
            0x77 => Some("F8"),
            0x78 => Some("F9"),
            0x79 => Some("F10"),
            0x7A => Some("F11"),
            0x7B => Some("F12"),
            0x7C => Some("F13"),
            0x7D => Some("F14"),
            0x7E => Some("F15"),
            0x7F => Some("F16"),
            0x80 => Some("F17"),
            0x81 => Some("F18"),
            0x82 => Some("F19"),
            0x83 => Some("F20"),
            0x84 => Some("F21"),
            0x85 => Some("F22"),
            0x86 => Some("F23"),
            0x87 => Some("F24"),
            _ => None,
        }
    }

    fn accept_injected_events() -> bool {
        std::env::var(ACCEPT_INJECTED_ENV).ok().as_deref() == Some("1")
    }
}

// ─────────────────────────── Linux / other implementation ───────────────────────────

#[cfg(all(not(target_os = "macos"), not(target_os = "windows")))]
mod platform {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::mpsc::Sender;
    use std::sync::Arc;
    use std::time::Duration;

    use rdev::{listen, Button, Event, EventType, Key};

    use super::{
        dispatch_hotkey_code, dispatch_translation_modifier_code, install_error, send_or_log,
        start_listener_thread, update_shared_binding, HotkeyAdapter, HotkeyEvent, Shared,
        StartupTx,
    };
    use crate::types::{HotkeyAdapterKind, HotkeyBinding, HotkeyInstallError};

    pub fn start_adapter(
        binding: HotkeyBinding,
        tx: Sender<HotkeyEvent>,
    ) -> Result<Box<dyn HotkeyAdapter>, HotkeyInstallError> {
        if std::env::var("XDG_SESSION_TYPE").ok().as_deref() == Some("wayland") {
            return Err(install_error(
                "wayland_unsupported",
                "Wayland 暂不支持全局热键，请切到 X11 session 后再试",
            ));
        }
        let listener = start_listener_thread(
            binding,
            tx,
            "openless-hotkey-rdev",
            "hotkey hook 启动超时",
            run_listen_loop,
        )?;
        let _ = listener.startup;
        Ok(Box::new(RdevHotkeyAdapter {
            shared: listener.shared,
        }))
    }

    struct RdevHotkeyAdapter {
        shared: Arc<Shared>,
    }

    impl HotkeyAdapter for RdevHotkeyAdapter {
        fn kind(&self) -> HotkeyAdapterKind {
            HotkeyAdapterKind::Rdev
        }

        fn update_binding(&self, binding: HotkeyBinding) {
            update_shared_binding(&self.shared, binding);
        }
    }

    fn run_listen_loop(shared: Arc<Shared>, tx: Sender<HotkeyEvent>, status_tx: StartupTx<()>) {
        let status_sent = Arc::new(AtomicBool::new(false));
        let ready_status_sent = Arc::clone(&status_sent);
        let ready_status_tx = status_tx.clone();
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(350));
            if !ready_status_sent.swap(true, Ordering::SeqCst) {
                let _ = ready_status_tx.send(Ok(()));
            }
        });
        let cb_shared = Arc::clone(&shared);
        let result = listen(move |event: Event| {
            dispatch_event(&cb_shared, &tx, event);
        });
        if let Err(err) = result {
            if !status_sent.swap(true, Ordering::SeqCst) {
                let _ = status_tx.send(Err(install_error(
                    "listen_failed",
                    format!("rdev::listen 启动失败: {err:?}"),
                )));
            }
            log::error!("[hotkey] rdev::listen 启动失败: {:?}", err);
        }
    }

    fn dispatch_event(shared: &Shared, tx: &Sender<HotkeyEvent>, event: Event) {
        match event.event_type {
            EventType::KeyPress(key) => {
                if key == Key::Escape {
                    send_or_log(tx, HotkeyEvent::Cancelled);
                    return;
                }
                if let Some(code) = rdev_key_to_hotkey_code(key) {
                    if matches!(key, Key::ShiftLeft | Key::ShiftRight) {
                        // Shift 作为录音热键成员时只参与热键匹配，不再额外切到翻译模式。
                        dispatch_translation_modifier_code(shared, tx, code, true);
                    }
                    dispatch_hotkey_code(shared, tx, code, true);
                }
            }
            EventType::KeyRelease(key) => {
                if let Some(code) = rdev_key_to_hotkey_code(key) {
                    if matches!(key, Key::ShiftLeft | Key::ShiftRight) {
                        dispatch_translation_modifier_code(shared, tx, code, false);
                    }
                    dispatch_hotkey_code(shared, tx, code, false);
                }
            }
            EventType::ButtonPress(button) => {
                if let Some(code) = rdev_button_to_hotkey_code(button) {
                    dispatch_hotkey_code(shared, tx, code, true);
                }
            }
            EventType::ButtonRelease(button) => {
                if let Some(code) = rdev_button_to_hotkey_code(button) {
                    dispatch_hotkey_code(shared, tx, code, false);
                }
            }
            _ => {}
        }
    }

    fn rdev_button_to_hotkey_code(button: Button) -> Option<&'static str> {
        match button {
            Button::Unknown(4) | Button::Unknown(8) => Some("Mouse4"),
            Button::Unknown(5) | Button::Unknown(9) => Some("Mouse5"),
            _ => None,
        }
    }

    fn rdev_key_to_hotkey_code(key: Key) -> Option<&'static str> {
        match key {
            Key::Alt => Some("AltLeft"),
            Key::AltGr => Some("AltRight"),
            Key::Backspace => Some("Backspace"),
            Key::CapsLock => Some("CapsLock"),
            Key::ControlLeft => Some("ControlLeft"),
            Key::ControlRight => Some("ControlRight"),
            Key::Delete => Some("Delete"),
            Key::DownArrow => Some("ArrowDown"),
            Key::End => Some("End"),
            Key::F1 => Some("F1"),
            Key::F2 => Some("F2"),
            Key::F3 => Some("F3"),
            Key::F4 => Some("F4"),
            Key::F5 => Some("F5"),
            Key::F6 => Some("F6"),
            Key::F7 => Some("F7"),
            Key::F8 => Some("F8"),
            Key::F9 => Some("F9"),
            Key::F10 => Some("F10"),
            Key::F11 => Some("F11"),
            Key::F12 => Some("F12"),
            Key::Home => Some("Home"),
            Key::LeftArrow => Some("ArrowLeft"),
            Key::MetaLeft => Some("MetaLeft"),
            Key::MetaRight => Some("MetaRight"),
            Key::PageDown => Some("PageDown"),
            Key::PageUp => Some("PageUp"),
            Key::Return => Some("Enter"),
            Key::RightArrow => Some("ArrowRight"),
            Key::ShiftLeft => Some("ShiftLeft"),
            Key::ShiftRight => Some("ShiftRight"),
            Key::Space => Some("Space"),
            Key::Tab => Some("Tab"),
            Key::UpArrow => Some("ArrowUp"),
            Key::PrintScreen => Some("PrintScreen"),
            Key::ScrollLock => Some("ScrollLock"),
            Key::Pause => Some("Pause"),
            Key::BackQuote => Some("Backquote"),
            Key::Num0 => Some("Digit0"),
            Key::Num1 => Some("Digit1"),
            Key::Num2 => Some("Digit2"),
            Key::Num3 => Some("Digit3"),
            Key::Num4 => Some("Digit4"),
            Key::Num5 => Some("Digit5"),
            Key::Num6 => Some("Digit6"),
            Key::Num7 => Some("Digit7"),
            Key::Num8 => Some("Digit8"),
            Key::Num9 => Some("Digit9"),
            Key::Minus => Some("Minus"),
            Key::Equal => Some("Equal"),
            Key::KeyA => Some("KeyA"),
            Key::KeyB => Some("KeyB"),
            Key::KeyC => Some("KeyC"),
            Key::KeyD => Some("KeyD"),
            Key::KeyE => Some("KeyE"),
            Key::KeyF => Some("KeyF"),
            Key::KeyG => Some("KeyG"),
            Key::KeyH => Some("KeyH"),
            Key::KeyI => Some("KeyI"),
            Key::KeyJ => Some("KeyJ"),
            Key::KeyK => Some("KeyK"),
            Key::KeyL => Some("KeyL"),
            Key::KeyM => Some("KeyM"),
            Key::KeyN => Some("KeyN"),
            Key::KeyO => Some("KeyO"),
            Key::KeyP => Some("KeyP"),
            Key::KeyQ => Some("KeyQ"),
            Key::KeyR => Some("KeyR"),
            Key::KeyS => Some("KeyS"),
            Key::KeyT => Some("KeyT"),
            Key::KeyU => Some("KeyU"),
            Key::KeyV => Some("KeyV"),
            Key::KeyW => Some("KeyW"),
            Key::KeyX => Some("KeyX"),
            Key::KeyY => Some("KeyY"),
            Key::KeyZ => Some("KeyZ"),
            Key::LeftBracket => Some("BracketLeft"),
            Key::RightBracket => Some("BracketRight"),
            Key::SemiColon => Some("Semicolon"),
            Key::Quote => Some("Quote"),
            Key::BackSlash | Key::IntlBackslash => Some("Backslash"),
            Key::Comma => Some("Comma"),
            Key::Dot => Some("Period"),
            Key::Slash => Some("Slash"),
            Key::Insert => Some("Insert"),
            Key::KpReturn => Some("NumpadEnter"),
            Key::KpMinus => Some("NumpadSubtract"),
            Key::KpPlus => Some("NumpadAdd"),
            Key::KpMultiply => Some("NumpadMultiply"),
            Key::KpDivide => Some("NumpadDivide"),
            Key::Kp0 => Some("Numpad0"),
            Key::Kp1 => Some("Numpad1"),
            Key::Kp2 => Some("Numpad2"),
            Key::Kp3 => Some("Numpad3"),
            Key::Kp4 => Some("Numpad4"),
            Key::Kp5 => Some("Numpad5"),
            Key::Kp6 => Some("Numpad6"),
            Key::Kp7 => Some("Numpad7"),
            Key::Kp8 => Some("Numpad8"),
            Key::Kp9 => Some("Numpad9"),
            Key::KpDelete => Some("NumpadDecimal"),
            Key::Function => Some("Fn"),
            _ => None,
        }
    }
}
