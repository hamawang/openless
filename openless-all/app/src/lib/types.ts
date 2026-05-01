// TypeScript mirror of src-tauri/src/types.rs.
// All keys are camelCase (Rust serializes with #[serde(rename_all = "camelCase")]).
// PolishMode is an exception — Rust uses lowercase serialization.

export type PolishMode = 'raw' | 'light' | 'structured' | 'formal';

export type InsertStatus = 'inserted' | 'pasteSent' | 'copiedFallback' | 'failed';

export interface DictationSession {
  id: string;
  createdAt: string; // ISO-8601
  rawTranscript: string;
  finalText: string;
  mode: PolishMode;
  appBundleId: string | null;
  appName: string | null;
  insertStatus: InsertStatus;
  errorCode: string | null;
  durationMs: number | null;
  dictionaryEntryCount: number | null;
}

export interface DictionaryEntry {
  id: string;
  phrase: string;
  note: string | null;
  enabled: boolean;
  hits: number;
  createdAt: string;
}

export type HotkeyTrigger =
  | 'rightOption'
  | 'leftOption'
  | 'rightControl'
  | 'leftControl'
  | 'rightCommand'
  | 'fn'
  | 'rightAlt';

export type HotkeyMode = 'toggle' | 'hold';

export interface HotkeyBinding {
  trigger: HotkeyTrigger;
  mode: HotkeyMode;
}

export type HotkeyAdapterKind = 'macEventTap' | 'windowsLowLevel' | 'rdev';

export interface HotkeyCapability {
  adapter: HotkeyAdapterKind;
  availableTriggers: HotkeyTrigger[];
  requiresAccessibilityPermission: boolean;
  supportsModifierOnlyTrigger: boolean;
  supportsSideSpecificModifiers: boolean;
  explicitFallbackAvailable: boolean;
  statusHint: string | null;
}

export interface HotkeyInstallError {
  code: string;
  message: string;
}

export type HotkeyStatusState = 'starting' | 'installed' | 'failed';

export interface HotkeyStatus {
  adapter: HotkeyAdapterKind;
  state: HotkeyStatusState;
  message: string | null;
  lastError: HotkeyInstallError | null;
}

export interface UserPreferences {
  hotkey: HotkeyBinding;
  defaultMode: PolishMode;
  enabledModes: PolishMode[];
  launchAtLogin: boolean;
  showCapsule: boolean;
  activeAsrProvider: string;
  activeLlmProvider: string;
  /** 仅 Windows/Linux：粘贴成功后是否恢复用户原剪贴板。默认 true。详见 issue #111。 */
  restoreClipboardAfterPaste: boolean;
  /** 用户的工作语言（多选，原生名）；作为前提注入 LLM polish/translate prompt 头部。 */
  workingLanguages: string[];
  /** 翻译模式目标语言（单选，原生名）；空串 = 不启用 Shift 翻译。详见 issue #4。 */
  translationTargetLanguage: string;
}

/** 内置语言列表 — 前端 Settings UI 用，后端只接收原生名字符串拼 prompt。
 *  添加新语言时直接在这里加一项（原生名），无需修改后端。 */
export const SUPPORTED_LANGUAGES: readonly string[] = [
  '简体中文',
  '繁体中文',
  'English',
  '日本語',
  '한국어',
  'Français',
  'Deutsch',
  'Español',
  'Italiano',
  'Português',
  'Русский',
  'العربية',
  'Tiếng Việt',
  'ไทย',
  'हिन्दी',
] as const;

export type CapsuleState =
  | 'idle'
  | 'recording'
  | 'transcribing'
  | 'polishing'
  | 'done'
  | 'cancelled'
  | 'error';

export interface CapsulePayload {
  state: CapsuleState;
  level: number; // 0..1 RMS
  elapsedMs: number;
  message: string | null;
  insertedChars: number | null;
  /** 当前 session 是否处于翻译模式（用户已按过 Shift）。详见 issue #4。 */
  translation: boolean;
}

export interface CredentialsStatus {
  volcengineConfigured: boolean;
  arkConfigured: boolean;
}

export interface TodayMetrics {
  charsToday: number;
  segmentsToday: number;
  avgLatencyMs: number;
  totalDurationMs: number;
}

export type PermissionStatus =
  | 'granted'
  | 'denied'
  | 'notDetermined'
  | 'restricted'
  | 'notApplicable';
