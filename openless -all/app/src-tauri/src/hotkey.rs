//! 全局热键监听：发送按下 / 抬起 / 取消三类边沿事件。
//!
//! - macOS：原生 CGEventTap（core-foundation + core-graphics FFI），与 Swift
//!   `OpenLessHotkey/HotkeyMonitor.swift` 同源。**不能用 `rdev`**：rdev 在每个
//!   事件回调里同步调 `TSMGetInputSourceProperty`，macOS 14+ 强制断言主线程，
//!   非主线程触发 `dispatch_assert_queue_fail` → SIGTRAP abort（已踩坑）。
//! - 其他平台：继续用 `rdev::listen`（Linux/Windows 的 listen 路径不依赖 TSM）。
//!
//! 仅产出"边沿"事件，toggle vs hold 由 Coordinator 解释。

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Sender;
use std::sync::Arc;
use std::thread;

use parking_lot::RwLock;

use crate::types::HotkeyBinding;

#[derive(Clone, Copy, Debug)]
pub enum HotkeyEvent {
    Pressed,
    Released,
    Cancelled,
}

struct Shared {
    binding: RwLock<HotkeyBinding>,
    /// 触发键当前是否处于"按住"状态。OS 自动重复事件用此去重。
    trigger_held: AtomicBool,
}

pub struct HotkeyMonitor {
    shared: Arc<Shared>,
}

impl HotkeyMonitor {
    /// Spawn the listener thread and **wait synchronously** for it to confirm
    /// the OS-level hook installed (CGEventTap on macOS / rdev::listen otherwise).
    /// Returns Err if installation failed (typically Accessibility not granted on macOS),
    /// so the caller can schedule a retry instead of silently dropping events.
    pub fn start(
        binding: HotkeyBinding,
        tx: Sender<HotkeyEvent>,
    ) -> anyhow::Result<Self> {
        let shared = Arc::new(Shared {
            binding: RwLock::new(binding),
            trigger_held: AtomicBool::new(false),
        });

        let thread_shared = Arc::clone(&shared);
        let (status_tx, status_rx) = std::sync::mpsc::channel::<bool>();
        thread::Builder::new()
            .name("openless-hotkey".into())
            .spawn(move || platform::run_listen_loop(thread_shared, tx, status_tx))?;

        match status_rx.recv_timeout(std::time::Duration::from_secs(3)) {
            Ok(true) => Ok(Self { shared }),
            Ok(false) => Err(anyhow::anyhow!(
                "hotkey hook 安装失败（macOS 多半是辅助功能权限未授予）"
            )),
            Err(_) => Err(anyhow::anyhow!("hotkey hook 启动超时")),
        }
    }

    pub fn update_binding(&self, binding: HotkeyBinding) {
        *self.shared.binding.write() = binding;
        self.shared.trigger_held.store(false, Ordering::SeqCst);
    }
}

// ─────────────────────────── macOS implementation ───────────────────────────

#[cfg(target_os = "macos")]
mod platform {
    use std::ffi::c_void;
    use std::sync::atomic::Ordering;
    use std::sync::mpsc::Sender;
    use std::sync::Arc;

    use super::{HotkeyEvent, Shared};
    use crate::types::HotkeyTrigger;

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
    const FLAGS_CHANGED: CgEventType = 12;
    const TAP_DISABLED_BY_TIMEOUT: CgEventType = 0xFFFF_FFFE;
    const TAP_DISABLED_BY_USER_INPUT: CgEventType = 0xFFFF_FFFF;

    const KEYBOARD_EVENT_KEYCODE: CgEventField = 9;

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

    // ── Callback context ───────────────────────────────────────────────────

    struct CallbackContext {
        shared: Arc<Shared>,
        tx: Sender<HotkeyEvent>,
        tap: std::sync::Mutex<Option<CfMachPortRef>>,
    }

    // CallbackContext crosses an FFI boundary as a raw pointer; the only field
    // not auto-Send/Sync is the CfMachPortRef raw pointer, which is fine to
    // share since CGEventTapEnable is thread-safe for our usage.
    unsafe impl Send for CallbackContext {}
    unsafe impl Sync for CallbackContext {}

    pub fn run_listen_loop(
        shared: Arc<Shared>,
        tx: Sender<HotkeyEvent>,
        status_tx: std::sync::mpsc::Sender<bool>,
    ) {
        let mask: CgEventMask = (1u64 << FLAGS_CHANGED) | (1u64 << KEY_DOWN);
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
                let _ = status_tx.send(false);
                return;
            }
            *(*context).tap.lock().unwrap() = Some(tap);

            let source = CFMachPortCreateRunLoopSource(std::ptr::null(), tap, 0);
            let runloop = CFRunLoopGetCurrent();
            CFRunLoopAddSource(runloop, source, kCFRunLoopCommonModes);
            CGEventTapEnable(tap, true);

            log::info!("[hotkey] CGEventTap 已启动");
            let _ = status_tx.send(true);
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
            _ => {}
        }
        event
    }

    fn handle_flags_changed(ctx: &CallbackContext, event: CgEventRef) {
        let keycode = unsafe { CGEventGetIntegerValueField(event, KEYBOARD_EVENT_KEYCODE) };
        let trigger = ctx.shared.binding.read().trigger;
        let expected_keycode = trigger_to_keycode(trigger);
        if keycode != expected_keycode {
            return;
        }
        let flags = unsafe { CGEventGetFlags(event) };
        let mask = trigger_to_flag_mask(trigger);
        let is_active = (flags & mask) != 0;
        let was_held = ctx.shared.trigger_held.load(Ordering::SeqCst);

        if is_active && !was_held {
            ctx.shared.trigger_held.store(true, Ordering::SeqCst);
            send_or_log(&ctx.tx, HotkeyEvent::Pressed);
        } else if !is_active && was_held {
            ctx.shared.trigger_held.store(false, Ordering::SeqCst);
            send_or_log(&ctx.tx, HotkeyEvent::Released);
        }
    }

    fn handle_key_down(ctx: &CallbackContext, event: CgEventRef) {
        let keycode = unsafe { CGEventGetIntegerValueField(event, KEYBOARD_EVENT_KEYCODE) };
        if keycode == ESC_KEYCODE {
            send_or_log(&ctx.tx, HotkeyEvent::Cancelled);
        }
    }

    fn send_or_log(tx: &Sender<HotkeyEvent>, evt: HotkeyEvent) {
        if let Err(e) = tx.send(evt) {
            log::warn!("[hotkey] 事件发送失败: {e}");
        }
    }

    fn trigger_to_keycode(trigger: HotkeyTrigger) -> i64 {
        match trigger {
            HotkeyTrigger::LeftControl => 59,
            HotkeyTrigger::RightControl => 62,
            HotkeyTrigger::LeftOption => 58,
            HotkeyTrigger::RightOption | HotkeyTrigger::RightAlt => 61,
            HotkeyTrigger::RightCommand => 54,
            HotkeyTrigger::Fn => 63,
        }
    }

    fn trigger_to_flag_mask(trigger: HotkeyTrigger) -> CgEventFlags {
        match trigger {
            HotkeyTrigger::LeftControl | HotkeyTrigger::RightControl => FLAG_MASK_CONTROL,
            HotkeyTrigger::RightCommand => FLAG_MASK_COMMAND,
            HotkeyTrigger::LeftOption
            | HotkeyTrigger::RightOption
            | HotkeyTrigger::RightAlt => FLAG_MASK_ALTERNATE,
            HotkeyTrigger::Fn => FLAG_MASK_SECONDARY_FN,
        }
    }
}

// ─────────────────────────── non-macOS implementation ───────────────────────────

#[cfg(not(target_os = "macos"))]
mod platform {
    use std::sync::atomic::Ordering;
    use std::sync::mpsc::Sender;
    use std::sync::Arc;

    use rdev::{listen, Event, EventType, Key};

    use super::{HotkeyEvent, Shared};
    use crate::types::HotkeyTrigger;

    pub fn run_listen_loop(
        shared: Arc<Shared>,
        tx: Sender<HotkeyEvent>,
        status_tx: std::sync::mpsc::Sender<bool>,
    ) {
        // rdev 没有"安装即可知"的 API；我们乐观汇报成功，Linux/Win 上一般直接生效。
        let _ = status_tx.send(true);
        let cb_shared = Arc::clone(&shared);
        let result = listen(move |event: Event| {
            dispatch_event(&cb_shared, &tx, event);
        });
        if let Err(err) = result {
            log::error!("[hotkey] rdev::listen 启动失败: {:?}", err);
        }
    }

    fn dispatch_event(shared: &Shared, tx: &Sender<HotkeyEvent>, event: Event) {
        let trigger = shared.binding.read().trigger;
        match event.event_type {
            EventType::KeyPress(key) => {
                if key == Key::Escape {
                    let _ = tx.send(HotkeyEvent::Cancelled);
                    return;
                }
                if key == trigger_to_rdev_key(trigger) {
                    let was_held = shared.trigger_held.swap(true, Ordering::SeqCst);
                    if !was_held {
                        let _ = tx.send(HotkeyEvent::Pressed);
                    }
                }
            }
            EventType::KeyRelease(key) => {
                if key == trigger_to_rdev_key(trigger) {
                    let was_held = shared.trigger_held.swap(false, Ordering::SeqCst);
                    if was_held {
                        let _ = tx.send(HotkeyEvent::Released);
                    }
                }
            }
            _ => {}
        }
    }

    fn trigger_to_rdev_key(trigger: HotkeyTrigger) -> Key {
        match trigger {
            HotkeyTrigger::RightOption | HotkeyTrigger::RightAlt => Key::AltGr,
            HotkeyTrigger::LeftOption => Key::Alt,
            HotkeyTrigger::RightControl => Key::ControlRight,
            HotkeyTrigger::LeftControl => Key::ControlLeft,
            HotkeyTrigger::RightCommand => Key::MetaRight,
            HotkeyTrigger::Fn => Key::Function,
        }
    }
}
