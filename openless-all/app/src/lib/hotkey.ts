import i18n from '../i18n';
import type { ComboBinding, HotkeyBinding, HotkeyTrigger, QaHotkeyBinding, ShortcutBinding } from './types';

export function getHotkeyTriggerLabel(trigger: HotkeyTrigger | null | undefined): string {
  if (!trigger) return i18n.t('hotkey.fallback');
  if (trigger === 'custom') return i18n.t('hotkey.triggers.custom');
  return i18n.t(`hotkey.triggers.${trigger}`);
}

export function getHotkeyStartStopLabel(
  binding: HotkeyBinding | null | undefined,
  comboBinding?: ComboBinding | null,
  shortcutBinding?: ShortcutBinding | null,
): string {
  if (shortcutBinding) {
    const suffix = binding?.mode === 'hold'
      ? i18n.t('hotkey.modeHoldSuffix')
      : i18n.t('hotkey.modeToggleSuffix');
    return `${formatComboLabel(shortcutBinding)}${suffix}`;
  }
  if (binding?.trigger === 'custom' && comboBinding) {
    const combo = formatComboLabel(comboBinding);
    const suffix = binding.mode === 'hold'
      ? i18n.t('hotkey.modeHoldSuffix')
      : i18n.t('hotkey.modeToggleSuffix');
    return `${combo}${suffix}`;
  }
  const trigger = getHotkeyTriggerLabel(binding?.trigger);
  const suffix = binding?.mode === 'hold'
    ? i18n.t('hotkey.modeHoldSuffix')
    : i18n.t('hotkey.modeToggleSuffix');
  return `${trigger}${suffix}`;
}

export function getHotkeyUsageHint(
  binding: HotkeyBinding | null | undefined,
  comboBinding?: ComboBinding | null,
  shortcutBinding?: ShortcutBinding | null,
): string {
  if (shortcutBinding) {
    const combo = formatComboLabel(shortcutBinding);
    return binding?.mode === 'hold'
      ? i18n.t('hotkey.usageHold', { trigger: combo })
      : i18n.t('hotkey.usageToggle', { trigger: combo });
  }
  if (binding?.trigger === 'custom' && comboBinding) {
    const combo = formatComboLabel(comboBinding);
    return binding.mode === 'hold'
      ? i18n.t('hotkey.usageHold', { trigger: combo })
      : i18n.t('hotkey.usageToggle', { trigger: combo });
  }
  const trigger = getHotkeyTriggerLabel(binding?.trigger);
  return binding?.mode === 'hold'
    ? i18n.t('hotkey.usageHold', { trigger })
    : i18n.t('hotkey.usageToggle', { trigger });
}

/** 把 ComboBinding 或 QaHotkeyBinding 格式化为可读标签，如 "⌘⇧D" / "Ctrl+Shift+D"。 */
export function formatComboLabel(binding: ComboBinding | QaHotkeyBinding | ShortcutBinding): string {
  const parts: string[] = [];
  const platform = currentPlatform();

  // 固定输出顺序：Ctrl/Cmd → Alt/Option → Shift → Super
  const modifierOrder = ['cmd', 'ctrl', 'alt', 'shift', 'super'] as const;
  for (const tag of modifierOrder) {
    if (binding.modifiers.some(m => m.toLowerCase() === tag)) {
      parts.push(modifierDisplayName(tag, platform));
    }
  }

  parts.push(formatPrimary(binding.primary));
  return parts.join(platform.isMac ? '' : '+');
}

function currentPlatform(): { isMac: boolean; isWindows: boolean } {
  const platform = navigator.platform || '';
  const userAgent = navigator.userAgent || '';
  return {
    isMac: platform.includes('Mac') || userAgent.includes('Mac'),
    isWindows: platform.includes('Win') || userAgent.includes('Windows'),
  };
}

function modifierDisplayName(tag: string, platform: { isMac: boolean; isWindows: boolean }): string {
  if (platform.isMac) {
    switch (tag) {
      case 'cmd': return '\u2318';
      case 'ctrl': return '\u2303';
      case 'alt': return '\u2325';
      case 'shift': return '\u21E7';
      case 'super': return '\u2318';
    }
  } else {
    switch (tag) {
      case 'cmd': return platform.isWindows ? 'Ctrl' : 'Super';
      case 'ctrl': return 'Ctrl';
      case 'alt': return 'Alt';
      case 'shift': return 'Shift';
      case 'super': return platform.isWindows ? 'Win' : 'Super';
    }
  }
  return tag;
}

function formatPrimary(primary: string): string {
  const trimmed = primary.trim();
  if (!trimmed) return '?';
  // 单字母归大写
  if (trimmed.length === 1 && /[a-zA-Z]/.test(trimmed)) {
    return trimmed.toUpperCase();
  }
  // 常见命名键的 macOS 符号
  const isMac = navigator.platform.includes('Mac') || navigator.userAgent.includes('Mac');
  if (isMac) {
    switch (trimmed.toLowerCase()) {
      case 'space': return '\u2423';
      case 'enter':
      case 'return': return '\u21A9';
      case 'tab': return '\u21E5';
      case 'escape':
      case 'esc': return '\u238B';
      case 'backspace': return '\u232B';
      case 'delete':
      case 'del': return '\u2326';
      case 'arrowup':
      case 'up': return '\u2191';
      case 'arrowdown':
      case 'down': return '\u2193';
      case 'arrowleft':
      case 'left': return '\u2190';
      case 'arrowright':
      case 'right': return '\u2192';
    }
  }
  switch (trimmed.toLowerCase()) {
    case 'rightoption': return isMac ? 'Right ⌥' : 'Right Alt';
    case 'leftoption': return isMac ? 'Left ⌥' : 'Left Alt';
    case 'rightcontrol': return isMac ? 'Right ⌃' : 'Right Ctrl';
    case 'leftcontrol': return isMac ? 'Left ⌃' : 'Left Ctrl';
    case 'rightcommand': return isMac ? 'Right ⌘' : (currentPlatform().isWindows ? 'Right Win' : 'Right Super');
    case 'fn': return 'Fn';
    case 'shift': return isMac ? '⇧' : 'Shift';
  }
  return trimmed;
}
