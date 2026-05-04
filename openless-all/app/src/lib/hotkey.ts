import i18n from '../i18n';
import type { HotkeyBinding, HotkeyTrigger } from './types';

export function getHotkeyTriggerLabel(trigger: HotkeyTrigger | null | undefined): string {
  if (!trigger) return i18n.t('hotkey.fallback');
  return i18n.t(`hotkey.triggers.${trigger}`);
}

export function getHotkeyStartStopLabel(binding: HotkeyBinding | null | undefined): string {
  const trigger = getHotkeyBindingLabel(binding);
  const suffix = binding?.mode === 'hold'
    ? i18n.t('hotkey.modeHoldSuffix')
    : binding?.mode === 'doubleClick'
      ? i18n.t('hotkey.modeDoubleClickSuffix')
      : i18n.t('hotkey.modeToggleSuffix');
  return `${trigger}${suffix}`;
}

export function getHotkeyUsageHint(binding: HotkeyBinding | null | undefined): string {
  const trigger = getHotkeyBindingLabel(binding);
  if (binding?.mode === 'hold') return i18n.t('hotkey.usageHold', { trigger });
  if (binding?.mode === 'doubleClick') return i18n.t('hotkey.usageDoubleClick', { trigger });
  return i18n.t('hotkey.usageToggle', { trigger });
}

export function getHotkeyBindingCodes(binding: HotkeyBinding | null | undefined): string[] {
  if (!binding) return [];
  if (Array.isArray(binding.keys)) {
    return binding.keys.map(key => key.code.trim()).filter(Boolean);
  }
  const legacy = legacyTriggerCode(binding.trigger);
  return legacy ? [legacy] : [];
}

export function getHotkeyBindingLabel(binding: HotkeyBinding | null | undefined): string {
  const codes = getHotkeyBindingCodes(binding);
  if (codes.length === 0) return i18n.t('hotkey.unset');
  return codes.map(getHotkeyCodeLabel).join('+');
}

export function getHotkeyCodeLabel(code: string): string {
  const zh = i18n.language.toLowerCase().startsWith('zh');
  const labels: Record<string, string> = {
    ControlLeft: zh ? '左Ctrl' : 'Left Ctrl',
    ControlRight: zh ? '右Ctrl' : 'Right Ctrl',
    AltLeft: zh ? '左Alt' : 'Left Alt',
    AltRight: zh ? '右Alt' : 'Right Alt',
    ShiftLeft: zh ? '左Shift' : 'Left Shift',
    ShiftRight: zh ? '右Shift' : 'Right Shift',
    MetaLeft: zh ? '左Win' : 'Left Win',
    MetaRight: zh ? '右Win' : 'Right Win',
    OSLeft: zh ? '左Win' : 'Left Win',
    OSRight: zh ? '右Win' : 'Right Win',
    Fn: 'Fn',
    FnLock: 'FnLock',
    CapsLock: 'CapsLock',
    ScrollLock: 'ScrLock',
    Pause: 'Pause',
    PrintScreen: 'PrtSc',
    Backspace: 'Backspace',
    Tab: 'Tab',
    Enter: 'Enter',
    Space: 'Space',
    Insert: 'Insert',
    Delete: 'Delete',
    Home: 'Home',
    End: 'End',
    PageUp: 'PageUp',
    PageDown: 'PageDown',
    ArrowUp: 'Up',
    ArrowDown: 'Down',
    ArrowLeft: 'Left',
    ArrowRight: 'Right',
    ContextMenu: 'Menu',
    NumpadAdd: 'Num+',
    NumpadSubtract: 'Num-',
    NumpadMultiply: 'Num*',
    NumpadDivide: 'Num/',
    NumpadDecimal: 'Num.',
    NumpadEnter: 'NumEnter',
    Mouse4: 'Mouse4',
    Mouse5: 'Mouse5',
    Backquote: '`',
    Minus: '-',
    Equal: '=',
    BracketLeft: '[',
    BracketRight: ']',
    Backslash: '\\',
    Semicolon: ';',
    Quote: "'",
    Comma: ',',
    Period: '.',
    Slash: '/',
  };
  if (labels[code]) return labels[code];
  const letter = code.match(/^Key([A-Z])$/);
  if (letter) return letter[1];
  const digit = code.match(/^Digit([0-9])$/);
  if (digit) return digit[1];
  const numpad = code.match(/^Numpad([0-9])$/);
  if (numpad) return `Num${numpad[1]}`;
  return code;
}

function legacyTriggerCode(trigger: HotkeyTrigger | null | undefined): string | null {
  switch (trigger) {
    case 'rightOption':
    case 'rightAlt':
      return 'AltRight';
    case 'leftOption':
      return 'AltLeft';
    case 'rightControl':
      return 'ControlRight';
    case 'leftControl':
      return 'ControlLeft';
    case 'rightCommand':
      return 'MetaRight';
    case 'fn':
      return 'Fn';
    default:
      return null;
  }
}
