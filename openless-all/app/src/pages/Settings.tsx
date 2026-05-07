// Settings.tsx 鈥?ported verbatim from design_handoff_openless/pages.jsx::Settings.
// Internal sub-sections (Recording / Providers / Shortcuts / Permissions / Language / About)
// keep their inline-style literals 1:1 with the source JSX.

import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { useTranslation } from 'react-i18next';
import { Icon } from '../components/Icon';
import { ShortcutRecorder } from '../components/ShortcutRecorder';
import { isDialogStatus, UpdateDialog, useAutoUpdate } from '../components/AutoUpdate';
import { detectOS } from '../components/WindowChrome';
import { APP_VERSION_LABEL } from '../lib/appVersion';
import { isHotkeyModeMigrationNoticeActive } from '../lib/hotkeyMigration';
import {
  defaultQaShortcut,
  getHotkeyBindingCodes,
  getHotkeyBindingLabel,
  getHotkeyCodeLabel,
} from '../lib/hotkey';
import { createHotkeyRecorderState, orderHotkeyCodes, updateHotkeyRecorderState } from '../lib/hotkeyRecorder';
import {
  checkAccessibilityPermission,
  checkMicrophonePermission,
  getHotkeyStatus,
  getWindowsImeStatus,
  isTauri,
  openExternal,
  openSystemSettings,
  listProviderModels,
  readCredential,
  requestAccessibilityPermission,
  requestMicrophonePermission,
  setActiveAsrProvider,
  setActiveLlmProvider,
  setCredential,
  setDictationHotkey,
  setOpenAppHotkey,
  setQaHotkey,
  setSwitchStyleHotkey,
  setTranslationHotkey,
  validateProviderCredentials,
} from '../lib/ipc';
import type {
  HotkeyCapability,
  HotkeyBinding,
  HotkeyMode,
  HotkeyStatus,
  HotkeyTrigger,
  PermissionStatus,
  WindowsImeStatus,
} from '../lib/types';
import { useHotkeySettings } from '../state/HotkeySettingsContext';
import i18n, {
  FOLLOW_SYSTEM,
  getLocalePreference,
  outputPrefsForLocale,
  setLocalePreference,
  type SupportedLocale,
} from '../i18n';
import { Btn, Card, PageHeader, Pill } from './_atoms';
import {
  deleteLocalAsrModel,
  getLocalAsrSettings,
  listLocalAsrModels,
  type LocalAsrModelStatus,
  type LocalAsrSettings,
} from '../lib/localAsr';

/// Settings 鈫?ASR 閫変簡 local-qwen3 鏃惰Е鍙戣烦鍒般€屾ā鍨嬭缃€嶉〉 + 鍏?Settings modal銆?
/// FloatingShell 鐩戝惉鍚屽悕浜嬩欢鍋?setCurrentTab('localAsr') + setSettingsOpen(false)銆?
export const NAVIGATE_LOCAL_ASR_EVENT = 'openless:navigate-local-asr';

interface SettingsProps {
  embedded?: boolean;
  initialSection?: SettingsSectionId;
}
// "鍏充簬" tab 宸茬Щ闄わ紙鍐呭骞跺叆澶栧眰 SettingsModal 鐨?About 椤碉紝閬垮厤璁剧疆鍐呭閲嶅鍏ュ彛锛夈€?
export type SettingsSectionId = 'recording' | 'providers' | 'shortcuts' | 'permissions' | 'language';

const SECTION_ORDER: SettingsSectionId[] = ['recording', 'providers', 'shortcuts', 'permissions', 'language'];

async function autostartIsEnabled(): Promise<boolean> {
  const { invoke } = await import('@tauri-apps/api/core');
  return invoke<boolean>('plugin:autostart|is_enabled');
}

async function autostartEnable(): Promise<void> {
  const { invoke } = await import('@tauri-apps/api/core');
  await invoke('plugin:autostart|enable');
}

async function autostartDisable(): Promise<void> {
  const { invoke } = await import('@tauri-apps/api/core');
  await invoke('plugin:autostart|disable');
}

export function Settings({ embedded = false, initialSection = 'recording' }: SettingsProps) {
  const { t } = useTranslation();
  const [section, setSection] = useState<SettingsSectionId>(initialSection);

  useEffect(() => {
    setSection(initialSection);
  }, [initialSection]);

  return (
    <>
      {!embedded && (
        <PageHeader
          kicker={t('settings.kicker')}
          title={t('settings.title')}
          desc={t('settings.desc')}
        />
      )}
      {/* embedded锛堝湪 SettingsModal 閲岋級妯″紡涓嬶細mini-sidebar 鍥哄畾锛屼粎鍙虫爮 scroll銆?
          澶栧眰 flex:1 minHeight:0 璁?grid 鎷垮埌纭畾楂樺害锛沢ridTemplateRows: minmax(0, 1fr)
          寮哄埗琛岄珮绛変簬瀹瑰櫒楂樺害锛屽惁鍒?grid 榛樿 auto rows 浼氳窡鍐呭闀匡紝鍙虫爮 overflow:auto
          灏遍€€鍖栨垚"娌′笢瑗块渶瑕?scroll"锛屼簬鏄ぇ瀹剁収鏃т竴璧烽銆?*/}
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: embedded ? '120px 1fr' : '160px 1fr',
          gap: 18,
          ...(embedded ? { flex: 1, minHeight: 0, gridTemplateRows: 'minmax(0, 1fr)' } : {}),
        }}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          {SECTION_ORDER.map(s => (
            <button
              key={s}
              onClick={() => setSection(s)}
              style={{
                padding: '8px 12px', textAlign: 'left',
                fontSize: 13, color: section === s ? 'var(--ol-ink)' : 'var(--ol-ink-3)',
                background: section === s ? 'rgba(0,0,0,0.04)' : 'transparent',
                border: 0, borderRadius: 8, fontFamily: 'inherit', fontWeight: section === s ? 600 : 500,
                cursor: 'default',
                transition: 'background 0.16s var(--ol-motion-quick), color 0.16s var(--ol-motion-quick)',
              }}
            >
              {t(`settings.sections.${s}`)}
            </button>
          ))}
        </div>
        <div
          className={embedded ? 'ol-thinscroll' : undefined}
          style={{
            display: 'flex',
            flexDirection: 'column',
            gap: 12,
            ...(embedded ? { minHeight: 0, overflow: 'auto', paddingRight: 4 } : {}),
          }}
        >
          {section === 'recording' && <RecordingSection />}
          {section === 'providers' && <ProvidersSection />}
          {section === 'shortcuts' && <ShortcutsSection />}
          {section === 'permissions' && <PermissionsSection />}
          {section === 'language' && <LanguageSection />}
        </div>
      </div>
    </>
  );
}

interface SettingRowProps {
  label: string;
  desc?: string;
  children: ReactNode;
}

function SettingRow({ label, desc, children }: SettingRowProps) {
  return (
    <div style={{ display: 'grid', gridTemplateColumns: '180px 1fr', gap: 16, padding: '14px 0', borderTop: '0.5px solid var(--ol-line-soft)' }}>
      <div>
        <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--ol-ink)' }}>{label}</div>
        {desc && <div style={{ fontSize: 11.5, color: 'var(--ol-ink-4)', marginTop: 4, lineHeight: 1.5 }}>{desc}</div>}
      </div>
      <div style={{ display: 'flex', alignItems: 'flex-start' }}>{children}</div>
    </div>
  );
}

function RecordingSection() {
  const { t } = useTranslation();
  const { prefs, capability, updatePrefs: savePrefs } = useHotkeySettings();

  if (!prefs || !capability) {
    return (
      <Card>
        <div style={{ fontSize: 12, color: 'var(--ol-ink-4)' }}>{t('common.loading')}</div>
      </Card>
    );
  }

  const onModeChange = (mode: HotkeyMode) =>
    savePrefs({ ...prefs, hotkey: { ...prefs.hotkey, mode } });
  const onShowCapsuleChange = (showCapsule: boolean) =>
    savePrefs({ ...prefs, showCapsule });
  const onMuteDuringRecordingChange = (muteDuringRecording: boolean) =>
    savePrefs({ ...prefs, muteDuringRecording });
  const onRestoreClipboardChange = (restoreClipboardAfterPaste: boolean) =>
    savePrefs({ ...prefs, restoreClipboardAfterPaste });
  const onAllowNonTsfFallbackChange = (allowNonTsfInsertionFallback: boolean) =>
    savePrefs({ ...prefs, allowNonTsfInsertionFallback });

  const choices: Array<[HotkeyMode, string]> = [
    ['toggle', t('settings.recording.modeToggle')],
    ['hold', t('settings.recording.modeHold')],
  ];
  const hotkeyDesc = capability.requiresAccessibilityPermission
    ? t('settings.recording.hotkeyDescAcc')
    : t('settings.recording.hotkeyDescNoAcc');

  return (
    <Card>
      <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 4 }}>{t('settings.recording.title')}</div>
      <div style={{ fontSize: 11.5, color: 'var(--ol-ink-4)', marginBottom: 6 }}>{t('settings.recording.desc')}</div>
      {isHotkeyModeMigrationNoticeActive() && (
        <div
          style={{
            marginTop: 10,
            marginBottom: 8,
            padding: '12px 14px',
            borderRadius: 10,
            background: 'rgba(37,99,235,0.08)',
            border: '0.5px solid rgba(37,99,235,0.18)',
          }}
        >
          <div style={{ fontSize: 12.5, fontWeight: 600, color: 'var(--ol-blue)', marginBottom: 4 }}>
            {t('settings.recording.migrationNoticeTitle')}
          </div>
          <div style={{ fontSize: 11.5, color: 'var(--ol-ink-3)', lineHeight: 1.55 }}>
            {t('settings.recording.migrationNoticeDesc')}
          </div>
        </div>
      )}
      <SettingRow label={t('settings.recording.hotkeyLabel')} desc={hotkeyDesc}>
        <ShortcutRecorder
          value={prefs.dictationHotkey}
          onSave={async binding => {
            await setDictationHotkey(binding);
            await savePrefs({ ...prefs, dictationHotkey: binding });
          }}
        />
      </SettingRow>
      <SettingRow label={t('settings.recording.modeLabel')} desc={t('settings.recording.modeDesc')}>
        <div style={{ display: 'inline-flex', padding: 2, borderRadius: 8, background: 'rgba(0,0,0,0.05)' }}>
          {choices.map(([v, l]) => (
            <button
              key={v}
              onClick={() => onModeChange(v)}
              style={{
                padding: '5px 14px', fontSize: 12, fontWeight: 500,
                border: 0, borderRadius: 6, fontFamily: 'inherit',
                background: prefs.hotkey.mode === v ? '#fff' : 'transparent',
                color: prefs.hotkey.mode === v ? 'var(--ol-ink)' : 'var(--ol-ink-3)',
                boxShadow: prefs.hotkey.mode === v ? '0 1px 2px rgba(0,0,0,.08)' : 'none',
                cursor: 'default',
                transition: 'background 0.16s var(--ol-motion-quick), color 0.16s var(--ol-motion-quick), box-shadow 0.18s var(--ol-motion-soft)',
              }}
            >
              {l}
            </button>
          ))}        </div>
      </SettingRow>
      <SettingRow label={t('settings.recording.capsuleLabel')} desc={t('settings.recording.capsuleDesc')}>
        <Toggle on={prefs.showCapsule} onToggle={onShowCapsuleChange} />
      </SettingRow>
      <SettingRow
        label={t('settings.recording.muteDuringRecordingLabel')}
        desc={t('settings.recording.muteDuringRecordingDesc')}
      >
        <Toggle on={prefs.muteDuringRecording} onToggle={onMuteDuringRecordingChange} />
      </SettingRow>
      <SettingRow
        label={t('settings.recording.restoreClipboardLabel')}
        desc={t('settings.recording.restoreClipboardDesc')}
      >
        <Toggle on={prefs.restoreClipboardAfterPaste} onToggle={onRestoreClipboardChange} />
      </SettingRow>
      {capability.adapter === 'windowsLowLevel' && (
        <SettingRow
          label={t('settings.recording.allowNonTsfFallbackLabel')}
          desc={t('settings.recording.allowNonTsfFallbackDesc')}
        >
          <Toggle
            on={prefs.allowNonTsfInsertionFallback}
            onToggle={onAllowNonTsfFallbackChange}
          />
        </SettingRow>
      )}
      <AutostartRow />
      {capability.statusHint && (
        <div style={{ marginTop: 6, fontSize: 11.5, color: 'var(--ol-ink-4)', lineHeight: 1.5 }}>
          {capability.statusHint}
        </div>
      )}
    </Card>
  );
}

// 涓嶅瓨杩?prefs锛歛utostart 鐘舵€佺敱 OS 鎸佹湁锛坢ac LaunchAgent plist / linux .desktop /
// windows HKCU\Run锛夛紝prefs 缂撳瓨鍙嶈€屼細涓?OS 鐪熺浉涓嶄竴鑷淬€俰ssue #194銆?
function HotkeyRecorder({
  binding,
  onCommit,
}: {
  binding: HotkeyBinding;
  onCommit: (codes: string[]) => void;
}) {
  const { t } = useTranslation();
  const [recording, setRecording] = useState(false);
  const [draftCodes, setDraftCodes] = useState<string[]>([]);
  const recorderStateRef = useRef(createHotkeyRecorderState());
  const recordingRef = useRef(false);

  const resetRecording = () => {
    recordingRef.current = false;
    recorderStateRef.current = createHotkeyRecorderState();
    setDraftCodes([]);
    setRecording(false);
  };

  const commitCodes = (codes: string[]) => {
    const ordered = orderHotkeyCodes(codes);
    resetRecording();
    onCommit(ordered);
  };

  const startRecording = () => {
    recordingRef.current = true;
    recorderStateRef.current = createHotkeyRecorderState();
    setDraftCodes([]);
    setRecording(true);
  };

  useEffect(() => {
    if (!recording) return undefined;

    const stopEvent = (event: Event) => {
      event.preventDefault();
      event.stopPropagation();
    };

    const applyHotkeyCode = (code: string, pressed: boolean) => {
      if (!recordingRef.current) return;
      const next = updateHotkeyRecorderState(recorderStateRef.current, code, pressed);
      recorderStateRef.current = next.state;
      setDraftCodes(next.state.draftCodes);
      if (next.commitCodes) commitCodes(next.commitCodes);
    };

    const onKeyDown = (event: KeyboardEvent) => {
      stopEvent(event);
      if (event.key === 'Escape' || event.code === 'Escape') {
        resetRecording();
        return;
      }
      const code = normalizeKeyboardHotkeyCode(event);
      if (!code) return;
      applyHotkeyCode(code, true);
    };

    const onKeyUp = (event: KeyboardEvent) => {
      stopEvent(event);
      if (!recordingRef.current) return;
      if (event.key === 'Escape' || event.code === 'Escape') {
        resetRecording();
        return;
      }
      const code = normalizeKeyboardHotkeyCode(event);
      if (!code) return;
      applyHotkeyCode(code, false);
    };

    const onMouseDown = (event: MouseEvent) => {
      const code = mouseButtonToHotkeyCode(event.button);
      if (!code) return;
      stopEvent(event);
      applyHotkeyCode(code, true);
    };

    const onMouseUp = (event: MouseEvent) => {
      const code = mouseButtonToHotkeyCode(event.button);
      if (!code) return;
      stopEvent(event);
      applyHotkeyCode(code, false);
    };

    window.addEventListener('keydown', onKeyDown, true);
    window.addEventListener('keyup', onKeyUp, true);
    window.addEventListener('mousedown', onMouseDown, true);
    window.addEventListener('mouseup', onMouseUp, true);
    return () => {
      window.removeEventListener('keydown', onKeyDown, true);
      window.removeEventListener('keyup', onKeyUp, true);
      window.removeEventListener('mousedown', onMouseDown, true);
      window.removeEventListener('mouseup', onMouseUp, true);
    };
  }, [recording]);

  const label = recording
    ? draftCodes.length > 0
      ? draftCodes.map(getHotkeyCodeLabel).join('+')
      : t('settings.recording.hotkeyRecording')
    : getHotkeyBindingLabel(binding);
  const hasKeys = getHotkeyBindingCodes(binding).length > 0;

  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
      <button
        type="button"
        onClick={startRecording}
        style={{
          ...hotkeyRecorderButtonStyle,
          borderColor: recording ? 'var(--ol-blue)' : 'var(--ol-line-strong)',
          color: recording ? 'var(--ol-blue)' : 'var(--ol-ink)',
        }}
      >
        <span style={hotkeyRecorderLabelStyle}>{label}</span>
        {!recording && hasKeys && (
          <span
            role="button"
            tabIndex={0}
            aria-label={t('settings.recording.hotkeyClear')}
            onClick={event => {
              event.stopPropagation();
              onCommit([]);
            }}
            onKeyDown={event => {
              if (event.key === 'Enter' || event.key === ' ') {
                event.preventDefault();
                event.stopPropagation();
                onCommit([]);
              }
            }}
            style={hotkeyClearButtonStyle}
          >
            <Icon name="x" size={11} strokeWidth={2} />
          </span>
        )}
      </button>
    </div>
  );
}

function inferLegacyTrigger(codes: string[], fallback: HotkeyTrigger): HotkeyTrigger {
  if (codes.includes('ControlRight')) return 'rightControl';
  if (codes.includes('ControlLeft')) return 'leftControl';
  if (codes.includes('AltRight')) return 'rightAlt';
  if (codes.includes('AltLeft')) return 'leftOption';
  if (codes.includes('MetaRight')) return 'rightCommand';
  if (codes.includes('Fn')) return 'fn';
  return fallback;
}

function normalizeKeyboardHotkeyCode(event: KeyboardEvent): string | null {
  if (event.key === 'Fn' || event.code === 'Fn') return 'Fn';
  if (event.key === 'FnLock' || event.code === 'FnLock') return 'FnLock';
  const code = event.code === 'OSLeft' ? 'MetaLeft' : event.code === 'OSRight' ? 'MetaRight' : event.code;
  if (SUPPORTED_HOTKEY_CODES.has(code)) return code;
  if (/^Key[A-Z]$/.test(code)) return code;
  if (/^Digit[0-9]$/.test(code)) return code;
  if (/^F([1-9]|1[0-9]|2[0-4])$/.test(code)) return code;
  if (/^Numpad[0-9]$/.test(code)) return code;
  return null;
}

function mouseButtonToHotkeyCode(button: number): string | null {
  if (button === 3) return 'Mouse4';
  if (button === 4) return 'Mouse5';
  return null;
}

const SUPPORTED_HOTKEY_CODES = new Set([
  'ControlLeft', 'ControlRight', 'AltLeft', 'AltRight', 'ShiftLeft', 'ShiftRight',
  'MetaLeft', 'MetaRight', 'CapsLock', 'ScrollLock', 'Pause', 'PrintScreen',
  'Backspace', 'Tab', 'Enter', 'Space', 'Insert', 'Delete', 'Home', 'End',
  'PageUp', 'PageDown', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight',
  'ContextMenu', 'NumpadAdd', 'NumpadSubtract', 'NumpadMultiply', 'NumpadDivide',
  'NumpadDecimal', 'NumpadEnter', 'Backquote', 'Minus', 'Equal', 'BracketLeft',
  'BracketRight', 'Backslash', 'Semicolon', 'Quote', 'Comma', 'Period', 'Slash',
  'Fn', 'FnLock',
]);

function AutostartRow() {
  const { t } = useTranslation();
  const [enabled, setEnabled] = useState(false);
  const [loaded, setLoaded] = useState(false);
  // 鍒?plist / 娉ㄥ唽琛ㄥけ璐ユ椂缁欑敤鎴风湅鐨勯敊璇€俷ull = 娌℃湁澶辫触/涓婃鎿嶄綔宸叉垚鍔熴€?
  // 涓嶆覆鏌撶瓑浜庢妸澶辫触鍚炴帀 鈥斺€?Windows 鍐?HKCU\Run 琚粍绛栫暐鎷︺€乵acOS 鍐?
  // LaunchAgent plist 鏉冮檺涓嶅 閮芥槸鐪熷疄鍙兘銆俰ssue #194銆?
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isTauri) {
      setLoaded(true);
      return;
    }
    let cancelled = false;
    autostartIsEnabled()
      .then((v: boolean) => {
        if (!cancelled) {
          setEnabled(v);
          setLoaded(true);
        }
      })
      .catch((err: unknown) => {
        console.error('[autostart] isEnabled failed', err);
        if (!cancelled) setLoaded(true);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const onToggle = async (next: boolean) => {
    setEnabled(next);
    setError(null);
    try {
      if (!isTauri) return;
      if (next) await autostartEnable();
      else await autostartDisable();
    } catch (err) {
      console.error('[autostart] toggle failed', err);
      setEnabled(!next);
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  return (
    <SettingRow
      label={t('settings.recording.startupAtBoot')}
      desc={t('settings.recording.startupAtBootDesc')}
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        {loaded ? <Toggle on={enabled} onToggle={onToggle} /> : null}
        {error && (
          <div style={{ fontSize: 11, color: 'var(--ol-err)', marginTop: 4, lineHeight: 1.5 }}>
            {t('settings.recording.startupAtBootError', { message: error })}
          </div>
        )}
      </div>
    </SettingRow>
  );
}

function Toggle({ on, onToggle }: { on: boolean; onToggle?: (next: boolean) => void }) {
  return (
    <button
      onClick={() => onToggle?.(!on)}
      style={{
        position: 'relative', width: 32, height: 18, borderRadius: 999, border: 0,
        background: on ? 'var(--ol-blue)' : 'rgba(0,0,0,0.15)',
        cursor: 'default',
        transition: 'background 0.16s var(--ol-motion-quick)',
      }}
    >
      <span
        style={{
          position: 'absolute', top: 2, left: on ? 16 : 2,
          width: 14, height: 14, borderRadius: 999, background: '#fff',
          boxShadow: '0 1px 2px rgba(0,0,0,.25)', transition: 'left .16s var(--ol-motion-spring)',
        }}
      />
    </button>
  );
}

const LLM_PRESETS = [
  { id: 'ark',          nameKey: 'ark',         baseUrl: 'https://ark.cn-beijing.volces.com/api/v3', modelPlaceholder: 'deepseek-v3-2' },
  { id: 'deepseek',     nameKey: 'deepseek',    baseUrl: 'https://api.deepseek.com/v1',             modelPlaceholder: 'deepseek-v4-flash' },
  { id: 'siliconflow',  nameKey: 'siliconflow', baseUrl: 'https://api.siliconflow.cn/v1',           modelPlaceholder: 'Qwen/Qwen2.5-7B-Instruct' },
  { id: 'openai',       nameKey: 'openai',      baseUrl: 'https://api.openai.com/v1',               modelPlaceholder: 'gpt-4o' },
  { id: 'custom',       nameKey: 'custom',      baseUrl: '',                                        modelPlaceholder: '' },
] as const;

type LlmPresetId = typeof LLM_PRESETS[number]['id'];

const ASR_DEFAULT_RESOURCE_ID = 'volc.seedasr.sauc.duration';

// `volcengine` 璧拌嚜寤烘祦寮忓鎴风锛涘叾浣欒蛋 OpenAI 鍏煎 `/audio/transcriptions`
// 锛坄coordinator.rs::is_whisper_compatible_provider`锛夈€傛柊澧炲吋瀹瑰巶鍟嗭細
//   1. 鍦ㄨ繖閲屽姞涓€椤?`{ id, nameKey, baseUrl, model }`锛?
//   2. `coordinator.rs::is_whisper_compatible_provider` 鍔犲悓鍚?id锛?
//   3. 鍦?i18n 鐨?`settings.providers.presets.<nameKey>` 鍔犳枃妗堛€?
const ASR_PRESETS = [
  { id: 'volcengine',   nameKey: 'asrVolcengine',   baseUrl: '',                                              model: ''                              },
  { id: 'siliconflow',  nameKey: 'asrSiliconflow',  baseUrl: 'https://api.siliconflow.cn/v1',                  model: 'FunAudioLLM/SenseVoiceSmall' },
  { id: 'zhipu',        nameKey: 'asrZhipu',        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',           model: 'glm-asr-2512'                },
  { id: 'groq',         nameKey: 'asrGroq',         baseUrl: 'https://api.groq.com/openai/v1',                 model: 'whisper-large-v3-turbo'      },
  { id: 'whisper',      nameKey: 'asrWhisper',      baseUrl: 'https://api.openai.com/v1',                      model: 'whisper-1'                   },
  { id: 'foundry-local-whisper', nameKey: 'asrFoundryLocalWhisper', baseUrl: '',                              model: ''                              },
  // 鏈湴 Qwen3-ASR锛氭棤 baseUrl/model 閰嶇疆锛屾ā鍨嬪湪銆屾ā鍨嬭缃€嶉〉涓嬭浇涓庡垏鎹€?
  { id: 'local-qwen3',  nameKey: 'asrLocalQwen3',   baseUrl: '',                                              model: ''                              },
] as const;

type AsrPresetId = typeof ASR_PRESETS[number]['id'];

function ProvidersSection() {
  const { t } = useTranslation();
  const { prefs, updatePrefs } = useHotkeySettings();
  // `*Provider` 绔嬪嵆璺熼殢 <select> 鏀瑰姩锛堝彈鎺х粍浠跺繀椤诲疄鏃跺弽鏄犵敤鎴疯緭鍏ワ級锛?
  // `committed*Provider` 鎵嶅喅瀹?CredentialField 鐨?key锛屼粎鍦ㄥ悗绔?active
  // 鍒囨崲 + 榛樿鍊煎啓瀹屽悗鍐?commit銆備袱鑰呮媶寮€鏄负浜嗗悓鏃舵弧瓒筹細
  //   - <select> 绔嬪埢鏄剧ず鐢ㄦ埛鐨勯€夋嫨锛坕ssue #220 P2锛歝odex 鎸囧嚭鍙楁帶閫変笉搴旂瓑 await锛?
  //   - CredentialField 涓嶈鍦ㄥ悗绔?active 鍒囧畬鍓?remount锛坕ssue #219锛氶伩鍏嶈鍒版棫 entry锛?
  // `*SwitchSeq` 鏄?stale-write 瀹堝崼锛氱敤鎴?100ms 鍐呰繛鐐逛袱娆℃椂锛屽厛鍙戠殑璇锋眰鏅氬埌涓?
  // 浼氳鐩栧悗鍙戠殑 commit銆?
  const [llmProvider, setLlmProvider] = useState<LlmPresetId>('ark');
  const [asrProvider, setAsrProvider] = useState<AsrPresetId>('volcengine');
  const [committedLlmProvider, setCommittedLlmProvider] = useState<LlmPresetId>('ark');
  const [committedAsrProvider, setCommittedAsrProvider] = useState<AsrPresetId>('volcengine');
  const llmSwitchSeqRef = useRef(0);
  const asrSwitchSeqRef = useRef(0);
  const [llmModelRevision, setLlmModelRevision] = useState(0);
  const [asrModelRevision, setAsrModelRevision] = useState(0);
  const os = detectOS();
  const visibleAsrPresets = ASR_PRESETS.filter(
    p => p.id !== 'foundry-local-whisper' || os === 'win',
  );

  useEffect(() => {
    if (!prefs) return;
    const knownLlm = LLM_PRESETS.find(x => x.id === prefs.activeLlmProvider);
    const llmId = knownLlm ? knownLlm.id : 'custom';
    setLlmProvider(llmId);
    setCommittedLlmProvider(llmId);
    const knownAsr = visibleAsrPresets.find(x => x.id === prefs.activeAsrProvider);
    const asrId = knownAsr ? knownAsr.id : 'volcengine';
    setAsrProvider(asrId);
    setCommittedAsrProvider(asrId);
  }, [prefs, os]);

  // issue #219 / #220 P2锛?
  //   1. 绔嬪埢 setLlmProvider 鈥斺€?鍙楁帶 <select> 蹇呴』鍙嶆槧鐢ㄦ埛鏈€鏂伴€夋嫨銆?
  //   2. 鐢?seq 瀹堝崼姣忎釜 await锛氱敤鎴疯繛鐐逛袱娆℃椂鏃ц姹傛櫄鍒颁篃涓嶄細鐩栨帀鏂伴€夋嫨銆?
  //   3. 浠?setCommittedLlmProvider 涔嬪悗 CredentialField 鎵?remount 璇绘柊 entry锛?
  //      姝ゆ椂鍚庣 root.active.llm 宸茬粡鏄?id锛宭ookup_account 钀藉埌姝ｇ‘ entry銆?
  //   4. endpoint/model 榛樿鍊间粎鍦ㄨ provider entry 璇ュ瓧娈典负绌烘椂鎵嶅～锛屼笉瑕嗙洊鐢ㄦ埛鑷畾涔夈€?
  const onLlmProviderChange = async (id: LlmPresetId) => {
    setLlmProvider(id);
    const seq = ++llmSwitchSeqRef.current;
    await setActiveLlmProvider(id);
    if (seq !== llmSwitchSeqRef.current) return;
    if (prefs) {
      const next = { ...prefs, activeLlmProvider: id };
      await updatePrefs(next);
      if (seq !== llmSwitchSeqRef.current) return;
    }
    const preset = LLM_PRESETS.find(p => p.id === id);
    if (preset?.baseUrl) {
      const existing = await readCredential('ark.endpoint');
      if (seq !== llmSwitchSeqRef.current) return;
      if (!existing) {
        await setCredential('ark.endpoint', preset.baseUrl);
        if (seq !== llmSwitchSeqRef.current) return;
      }
    }
    setCommittedLlmProvider(id);
  };

  const onAsrProviderChange = async (id: AsrPresetId) => {
    setAsrProvider(id);
    const seq = ++asrSwitchSeqRef.current;
    await setActiveAsrProvider(id);
    if (seq !== asrSwitchSeqRef.current) return;
    if (prefs) {
      const next = { ...prefs, activeAsrProvider: id };
      await updatePrefs(next);
      if (seq !== asrSwitchSeqRef.current) return;
    }
    // OpenAI 鍏煎鍘傚晢棣栨鍒囨崲鏃堕濉?baseUrl / model 榛樿鍊硷紝鐪佸緱鐢ㄦ埛蹇呰俯
    // 銆岃法鍘傚晢 model 鍚嶆牴鏈笉涓€鏍枫€嶇殑鍧戯紱浣嗙敤鎴峰凡鑷畾涔夊悗灏变笉鍐嶈鐩栥€?
    // volcengine 璧板彟涓€濂楀嚟鎹紝璺宠繃銆?
    const preset = ASR_PRESETS.find(p => p.id === id);
    if (preset && preset.baseUrl) {
      const existing = await readCredential('asr.endpoint');
      if (seq !== asrSwitchSeqRef.current) return;
      if (!existing) {
        await setCredential('asr.endpoint', preset.baseUrl);
        if (seq !== asrSwitchSeqRef.current) return;
      }
    }
    if (preset && preset.model) {
      const existing = await readCredential('asr.model');
      if (seq !== asrSwitchSeqRef.current) return;
      if (!existing) {
        await setCredential('asr.model', preset.model);
        if (seq !== asrSwitchSeqRef.current) return;
      }
    }
    setCommittedAsrProvider(id);
  };

  // preset 鍐冲畾 placeholder 涓?default 鈥斺€?蹇呴』璺熺潃 committed*Provider 璧帮紝
  // 鍚﹀垯鍙楁帶 <select> 绔嬪埢鍒囧埌鏂板巶鍟嗭紝浣嗗嚟鎹瓧娈佃繕鍦ㄦ樉绀烘棫 entry锛宲laceholder
  // 浼氬厛浜庡疄闄呮暟鎹垏鎹€佽瑙変笂瀵逛笉涓娿€?
  const preset = LLM_PRESETS.find(p => p.id === committedLlmProvider) ?? LLM_PRESETS[LLM_PRESETS.length - 1];
  const asrPreset = visibleAsrPresets.find(p => p.id === committedAsrProvider);

  return (
    <>
      <div style={{ fontSize: 11.5, color: 'var(--ol-ink-4)', lineHeight: 1.6, marginBottom: 10 }}>
        {t('settings.providers.credentialStorageNotice')}
      </div>
      <Card>
        <div style={{ marginBottom: 10 }}>
          <div style={{ fontSize: 13, fontWeight: 600 }}>{t('settings.providers.llmTitle')}</div>
          <div style={{ fontSize: 11.5, color: 'var(--ol-ink-4)', marginTop: 2 }}>
            {t('settings.providers.llmDesc')}
          </div>
        </div>
        <SettingRow label={t('settings.providers.providerLabel')} desc={t('settings.providers.llmProviderDesc')}>
          <select
            value={llmProvider}
            onChange={e => onLlmProviderChange(e.target.value as LlmPresetId)}
            style={{ ...inputStyle, maxWidth: 200 }}
          >
            {LLM_PRESETS.map(p => (
              <option key={p.id} value={p.id}>{t(`settings.providers.presets.${p.nameKey}`)}</option>
            ))}
          </select>
        </SettingRow>
        <CredentialField key={`${committedLlmProvider}:api_key`} label={t('settings.providers.apiKeyLabel')} account="ark.api_key" mono mask />
        <CredentialField key={`${committedLlmProvider}:endpoint`} label={t('settings.providers.baseUrlLabel')} account="ark.endpoint"
          placeholder={preset.baseUrl || 'https://your-endpoint/v1'} />
        <CredentialField key={`${committedLlmProvider}:model:${llmModelRevision}`} label={t('settings.providers.modelLabel')} account="ark.model_id"
          placeholder={preset.modelPlaceholder || 'model-name'} mono />
        <ProviderTools key={committedLlmProvider} kind="llm" modelAccount="ark.model_id" onModelSelected={() => setLlmModelRevision(v => v + 1)} />
      </Card>

      <Card>
        <div style={{ marginBottom: 10 }}>
          <div style={{ fontSize: 13, fontWeight: 600 }}>{t('settings.providers.asrTitle')}</div>
          <div style={{ fontSize: 11.5, color: 'var(--ol-ink-4)', marginTop: 2 }}>{t('settings.providers.asrDesc')}</div>
        </div>
        <SettingRow label={t('settings.providers.providerLabel')} desc={t('settings.providers.asrProviderDesc')}>
          <select
            value={asrProvider}
            onChange={e => onAsrProviderChange(e.target.value as AsrPresetId)}
            style={{ ...inputStyle, maxWidth: 200 }}
          >
            {visibleAsrPresets.map(p => (
              <option key={p.id} value={p.id}>{t(`settings.providers.presets.${p.nameKey}`)}</option>
            ))}
          </select>
        </SettingRow>
        {committedAsrProvider === 'volcengine' ? (
          <>
            <CredentialField
              key={`${committedAsrProvider}:app_key`}
              label={t('settings.providers.volcengineAppKeyLabel')}
              account="volcengine.app_key"
              mono
              mask
            />
            <CredentialField
              key={`${committedAsrProvider}:access_key`}
              label={t('settings.providers.volcengineAccessKeyLabel')}
              account="volcengine.access_key"
              mono
              mask
            />
            <CredentialField
              key={`${committedAsrProvider}:resource_id`}
              label={t('settings.providers.volcengineResourceIdLabel')}
              account="volcengine.resource_id"
              mono
              placeholder={ASR_DEFAULT_RESOURCE_ID} defaultValue={ASR_DEFAULT_RESOURCE_ID} />
            <div style={{ marginTop: 2, fontSize: 11.5, color: 'var(--ol-ink-4)', lineHeight: 1.6 }}>
              {t('settings.providers.volcengineMappingNote')}
            </div>
          </>
        ) : committedAsrProvider === 'local-qwen3' || committedAsrProvider === 'foundry-local-whisper' ? (
          <LocalAsrProviderHint provider={committedAsrProvider} selectedProvider={asrProvider} />
        ) : (
          <>
            <CredentialField key={`${committedAsrProvider}:api_key`} label={t('settings.providers.apiKeyLabel')} account="asr.api_key" mono mask />
            <CredentialField key={`${committedAsrProvider}:endpoint`} label={t('settings.providers.baseUrlLabel')} account="asr.endpoint"
              placeholder={asrPreset?.baseUrl || 'https://api.openai.com/v1'}
              defaultValue={asrPreset?.baseUrl || undefined} />
            <CredentialField key={`${committedAsrProvider}:model:${asrModelRevision}`} label={t('settings.providers.modelLabel')} account="asr.model"
              placeholder={asrPreset?.model || 'whisper-1'} />
            <ProviderTools kind="asr" modelAccount="asr.model" onModelSelected={() => setAsrModelRevision(v => v + 1)} />
          </>
        )}
      </Card>
    </>
  );
}

type ProviderToolStatus = 'idle' | 'loading' | 'success' | 'empty' | 'error';

function ProviderTools({ kind, modelAccount, onModelSelected }: { kind: 'llm' | 'asr'; modelAccount: string; onModelSelected: () => void }) {
  const { t } = useTranslation();
  const [models, setModels] = useState<string[]>([]);
  const [selectedModel, setSelectedModel] = useState('');
  const [status, setStatus] = useState<ProviderToolStatus>('idle');
  const [message, setMessage] = useState('');

  const setResult = (next: ProviderToolStatus, nextMessage: string) => {
    setStatus(next);
    setMessage(nextMessage);
  };

  const validate = async () => {
    setModels([]);
    setSelectedModel('');
    setResult('loading', t('settings.providers.validating'));
    try {
      const result = await validateProviderCredentials(kind);
      setResult(result.ok ? 'success' : 'error', t('settings.providers.validateSuccess'));
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if ((kind === 'llm' && message === 'llmModelMissing') || (kind === 'asr' && message === 'asrModelMissing')) {
        setResult('empty', t('settings.providers.modelMissing'));
        return;
      }
      if (message === 'modelsEmpty') {
        setResult('empty', t('settings.providers.modelsEmpty'));
        return;
      }
      setResult('error', providerErrorMessage(error, t));
    }
  };

  const loadModels = async () => {
    setResult('loading', t('settings.providers.loadingModels'));
    try {
      const result = await listProviderModels(kind);
      setModels(result.models);
      if (result.models.length === 0) {
        setResult('empty', t('settings.providers.modelsEmpty'));
      } else {
        setSelectedModel('');
        setResult('success', t('settings.providers.modelsLoaded', { count: result.models.length }));
      }
    } catch (error) {
      setModels([]);
      setResult('error', providerErrorMessage(error, t));
    }
  };

  const applyModel = async (model: string) => {
    setResult('loading', t('common.saving'));
    try {
      await setCredential(modelAccount, model);
      setSelectedModel(model);
      onModelSelected();
      setResult('success', t('settings.providers.modelSaved', { model }));
    } catch (error) {
      setResult('error', providerErrorMessage(error, t));
    }
  };

  return (
    <SettingRow label={t('settings.providers.toolsLabel')} desc={t('settings.providers.toolsDesc')}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8, width: '100%', maxWidth: 420 }}>
        <div style={{ display: 'flex', gap: 6, alignItems: 'center', flexWrap: 'wrap' }}>
          <button onClick={validate} style={miniBtnStyle} disabled={status === 'loading'}>{t('settings.providers.validate')}</button>
          <button onClick={loadModels} style={miniBtnStyle} disabled={status === 'loading'}>{t('settings.providers.fetchModels')}</button>
          {models.length > 0 && (
            <select
              value={selectedModel}
              onChange={e => applyModel(e.target.value)}
              disabled={status === 'loading'}
              style={{ ...inputStyle, maxWidth: 220 }}
            >
              <option value="" disabled>{t('settings.providers.selectModel')}</option>
              {models.map(model => <option key={model} value={model}>{model}</option>)}
            </select>
          )}
        </div>
        {message && (
          <span style={{ fontSize: 11, color: status === 'error' ? 'var(--ol-warn)' : status === 'empty' ? 'var(--ol-ink-4)' : 'var(--ol-ok)', lineHeight: 1.4 }}>
            {message}
          </span>
        )}
      </div>
    </SettingRow>
  );
}


function providerErrorMessage(error: unknown, t: ReturnType<typeof useTranslation>['t']): string {
  const message = error instanceof Error ? error.message : String(error);
  if (message.startsWith('providerHttpStatus:')) {
    return t('settings.providers.providerHttpStatus', { status: message.split(':')[1] || '?' });
  }
  if (message === 'endpointMustUseHttps') return t('settings.providers.endpointMustUseHttps');
  if (message === 'endpointInvalid') return t('settings.providers.endpointInvalid');
  if (message === 'providerResponseTooLarge') return t('settings.providers.responseTooLarge');
  if (message === 'asrInvalidJson') return t('settings.providers.asrInvalidJson');
  if (message === 'asrMissingTextField') return t('settings.providers.asrMissingTextField');
  if (message === 'providerNetworkError') return t('common.networkError');
  if (message === 'providerReadResponseFailed' || message === 'providerClientInitFailed') return t('common.operationFailed');
  if (message === 'providerRequestTimeout') return t('settings.providers.requestTimeout');
  if (message.includes('API Key')) return t('settings.providers.apiKeyMissing');
  if (message.includes('Endpoint')) return t('settings.providers.endpointMissing');
  if (message.includes('timeout') || message.includes('超时')) return t('settings.providers.requestTimeout');
  return t('common.operationFailed');
}

type CredentialFieldStatus = 'idle' | 'saving' | 'saved' | 'readError' | 'saveError' | 'copied' | 'copyError';

interface CredentialFieldProps {
  label: string;
  account: string;
  placeholder?: string;
  mono?: boolean;
  mask?: boolean;
  defaultValue?: string;
}

function CredentialField({ label, account, placeholder, mono, mask, defaultValue }: CredentialFieldProps) {
  const { t } = useTranslation();
  const [value, setValue] = useState('');
  const [revealed, setRevealed] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [dirty, setDirty] = useState(false);
  const [status, setStatus] = useState<CredentialFieldStatus>('idle');
  const debounceRef = useRef<number | null>(null);
  const statusRef = useRef<number | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoaded(false);
    setDirty(false);
    setStatus('idle');
    setValue('');
    if (debounceRef.current) {
      clearTimeout(debounceRef.current);
      debounceRef.current = null;
    }
    readCredential(account)
      .then(v => {
        if (cancelled) return;
        setValue(v ?? '');
        setLoaded(true);
      })
      .catch(error => {
        if (cancelled) return;
        console.error('[settings] failed to read credential', account, error);
        setLoaded(true);
        setStatus('readError');
      });
    return () => {
      cancelled = true;
    };
  }, [account]);

  useEffect(() => {
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
      if (statusRef.current) clearTimeout(statusRef.current);
    };
  }, []);

  const showTemporaryStatus = (next: CredentialFieldStatus) => {
    setStatus(next);
    if (statusRef.current) clearTimeout(statusRef.current);
    statusRef.current = window.setTimeout(() => setStatus('idle'), 1600);
  };

  const save = async (v: string, force = false) => {
    if (!loaded || (!dirty && !force)) return;
    setStatus('saving');
    try {
      await setCredential(account, v);
      setDirty(false);
      showTemporaryStatus('saved');
    } catch (error) {
      console.error('[settings] failed to save credential', account, error);
      showTemporaryStatus('saveError');
    }
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const v = e.target.value;
    setValue(v);
    if (!loaded) return;
    setDirty(true);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = window.setTimeout(() => save(v, true), 300);
  };

  const onBlur = () => {
    if (!loaded || !dirty) return;
    if (debounceRef.current) {
      clearTimeout(debounceRef.current);
      debounceRef.current = null;
    }
    save(value, true);
  };

  const fillDefault = async () => {
    if (!loaded || !defaultValue) return;
    setValue(defaultValue);
    setDirty(true);
    await save(defaultValue, true);
  };

  const onCopy = async () => {
    if (!value || !loaded) return;
    try {
      if (!navigator.clipboard?.writeText) {
        throw new Error('Clipboard API unavailable');
      }
      await navigator.clipboard.writeText(value);
      showTemporaryStatus('copied');
    } catch (error) {
      console.error('[settings] failed to copy credential', account, error);
      showTemporaryStatus('copyError');
    }
  };

  const inputType = mask && !revealed ? 'password' : 'text';
  const disabled = !loaded;

  return (
    <SettingRow label={label}>
      <div style={{ display: 'flex', gap: 6, alignItems: 'center', width: '100%', maxWidth: 420 }}>
        <input
          type={inputType}
          value={value}
          placeholder={loaded ? placeholder : t('common.loading')}
          onChange={handleChange}
          onBlur={onBlur}
          disabled={disabled}
          style={{ ...inputStyle, fontFamily: mono ? 'var(--ol-font-mono)' : 'inherit' }}
        />
        {defaultValue && !value && loaded && (
          <button onClick={fillDefault} title={t('settings.providers.fillDefault')} style={iconBtnStyle} disabled={!loaded}>
            <Icon name="check" size={13} />
          </button>
        )}
        {mask && (
          <button
            onClick={() => setRevealed(r => !r)}
            title={revealed ? t('common.hide') : t('common.show')}
            style={iconBtnStyle}
            disabled={disabled}
          >
            <Icon name="eye" size={14} />
          </button>
        )}
        <button
          onClick={onCopy}
          title={t('common.copy')}
          style={iconBtnStyle}
          disabled={!value || disabled}
        >
          <Icon name="copy" size={14} />
        </button>
        {status !== 'idle' && (
          <span
            style={{
              fontSize: 11,
              color: status.endsWith('Error') ? 'var(--ol-warn)' : 'var(--ol-ok)',
              whiteSpace: 'nowrap',
            }}
          >
            {status === 'saving'
              ? t('common.saving')
              : status === 'saved'
                ? t('common.saved')
                : status === 'copied'
                  ? t('common.copied')
                  : status === 'readError'
                    ? t('settings.providers.readFailed')
                    : t('common.operationFailed')}
          </span>
        )}
      </div>
    </SettingRow>
  );
}

const inputStyle: CSSProperties = {
  flex: 1, height: 32, padding: '0 10px',
  border: '0.5px solid var(--ol-line-strong)',
  borderRadius: 8, fontSize: 12.5,
  fontFamily: 'inherit', outline: 'none',
  background: 'var(--ol-surface-2)',
  width: '100%', maxWidth: 360,
  transition: 'background 0.16s var(--ol-motion-quick), border-color 0.16s var(--ol-motion-quick)',
};
const miniBtnStyle: CSSProperties = {
  height: 32, padding: '0 10px',
  border: '0.5px solid var(--ol-line-strong)',
  borderRadius: 8, background: 'var(--ol-surface)',
  color: 'var(--ol-ink-2)', cursor: 'default', flexShrink: 0,
  fontSize: 12, fontWeight: 500,
  transition: 'background 0.16s var(--ol-motion-quick), border-color 0.16s var(--ol-motion-quick), color 0.16s var(--ol-motion-quick)',
};

const recordingHotkeyControlWidth = 178;

const hotkeyRecorderButtonStyle: CSSProperties = {
  width: recordingHotkeyControlWidth,
  height: 32,
  padding: '0 8px 0 11px',
  border: '0.5px solid var(--ol-line-strong)',
  borderRadius: 8,
  background: 'var(--ol-surface-2)',
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  gap: 8,
  fontFamily: 'var(--ol-font-mono)',
  fontSize: 12.5,
  cursor: 'default',
  transition: 'background 0.16s var(--ol-motion-quick), border-color 0.16s var(--ol-motion-quick), color 0.16s var(--ol-motion-quick)',
};

const recordingHotkeySegmentedStyle: CSSProperties = {
  width: recordingHotkeyControlWidth,
  display: 'inline-flex',
  padding: 2,
  borderRadius: 8,
  background: 'rgba(0,0,0,0.05)',
};

const recordingHotkeyGroupStyle: CSSProperties = {
  display: 'grid',
  gridTemplateColumns: 'auto',
  rowGap: 10,
  justifyItems: 'start',
};

const recordingHotkeyLineStyle: CSSProperties = {
  display: 'grid',
  gridTemplateColumns: '64px auto',
  alignItems: 'center',
  columnGap: 10,
};

const recordingHotkeyFieldLabelStyle: CSSProperties = {
  fontSize: 12,
  color: 'var(--ol-ink-4)',
  textAlign: 'right',
  whiteSpace: 'nowrap',
};

const recordingHotkeyStatusStyle: CSSProperties = {
  marginLeft: 74,
  fontSize: 12,
  lineHeight: 1.3,
};

const hotkeyRecorderLabelStyle: CSSProperties = {
  minWidth: 0,
  overflow: 'hidden',
  textOverflow: 'ellipsis',
  whiteSpace: 'nowrap',
};

const hotkeyClearButtonStyle: CSSProperties = {
  width: 18,
  height: 18,
  borderRadius: 999,
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
  flexShrink: 0,
  background: 'rgba(0,0,0,0.2)',
  color: '#fff',
};

const iconBtnStyle: CSSProperties = {
  width: 32, height: 32,
  border: '0.5px solid var(--ol-line-strong)',
  borderRadius: 8, background: 'var(--ol-surface)',
  display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
  color: 'var(--ol-ink-3)', cursor: 'default', flexShrink: 0,
  transition: 'background 0.16s var(--ol-motion-quick), border-color 0.16s var(--ol-motion-quick), color 0.16s var(--ol-motion-quick)',
};

function ShortcutsSection() {
  const { t } = useTranslation();
  const { prefs, hotkey, capability, updatePrefs: savePrefs } = useHotkeySettings();

  if (!prefs || !hotkey || !capability) {
    return (
      <Card>
        <div style={{ fontSize: 12, color: 'var(--ol-ink-4)' }}>{t('common.loading')}</div>
      </Card>
    );
  }

  const desc = capability.requiresAccessibilityPermission
    ? t('settings.shortcuts.descAcc')
    : t('settings.shortcuts.descNoAcc');
  const readonlyRows: Array<[string, string]> = [
    [t('settings.shortcuts.cancel'), 'Esc'],
    [t('settings.shortcuts.confirm'), t('settings.shortcuts.confirmHint')],
  ];
  return (
    <Card>
      <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 4 }}>{t('settings.shortcuts.title')}</div>
      <div style={{ fontSize: 11.5, color: 'var(--ol-ink-4)', marginBottom: 6 }}>{desc}</div>
      <SettingRow label={t('settings.shortcuts.startStop')}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6, width: '100%' }}>
          <ShortcutRecorder
            value={prefs.dictationHotkey}
            alignRecordButton
            onSave={async binding => {
              await setDictationHotkey(binding);
              await savePrefs({ ...prefs, dictationHotkey: binding });
            }}
          />
          <div style={{ fontSize: 11, color: 'var(--ol-ink-4)' }}>
            {hotkey.mode === 'hold' ? t('hotkey.modeHoldSuffix') : t('hotkey.modeToggleSuffix')}
          </div>
        </div>
      </SettingRow>
      <SettingRow label={t('translation.hotkey.title', 'Translation shortcut')}>
        <ShortcutRecorder
          value={prefs.translationHotkey}
          alignRecordButton
          onSave={async binding => {
            await setTranslationHotkey(binding);
            await savePrefs({ ...prefs, translationHotkey: binding });
          }}
        />
      </SettingRow>
      <SettingRow label={t('selectionAsk.hotkey.title')}>
        {prefs.qaHotkey ? (
          <ShortcutRecorder
            value={prefs.qaHotkey}
            alignRecordButton
            onSave={async binding => {
              await setQaHotkey(binding);
              await savePrefs({ ...prefs, qaHotkey: binding });
            }}
          />
        ) : (
          <button
            onClick={async () => {
              const binding = defaultQaShortcut();
              await setQaHotkey(binding);
              await savePrefs({ ...prefs, qaHotkey: binding });
            }}
            style={{ fontSize: 12, padding: '5px 14px', background: 'var(--ol-blue)', color: '#fff', border: 0, borderRadius: 6, fontFamily: 'inherit', fontWeight: 500, cursor: 'default' }}
          >
            {t('selectionAsk.hotkey.enable', 'Enable')}
          </button>
        )}
      </SettingRow>
      <SettingRow label={t('settings.shortcuts.switchStyle')}>
        <ShortcutRecorder
          value={prefs.switchStyleHotkey}
          alignRecordButton
          onSave={async binding => {
            await setSwitchStyleHotkey(binding);
            await savePrefs({ ...prefs, switchStyleHotkey: binding });
          }}
        />
      </SettingRow>
      <SettingRow label={t('settings.shortcuts.openApp')}>
        <ShortcutRecorder
          value={prefs.openAppHotkey}
          alignRecordButton
          onSave={async binding => {
            await setOpenAppHotkey(binding);
            await savePrefs({ ...prefs, openAppHotkey: binding });
          }}
        />
      </SettingRow>
      {readonlyRows.map(([k, v]) => (
        <SettingRow key={k} label={k}>
          <kbd style={{
            display: 'inline-flex', alignItems: 'center', gap: 4,
            padding: '4px 10px', fontSize: 12, fontFamily: 'var(--ol-font-mono)',
            borderRadius: 6, background: 'var(--ol-surface-2)',
            border: '0.5px solid var(--ol-line-strong)',
            boxShadow: '0 1px 0 rgba(0,0,0,0.04)',
            color: 'var(--ol-ink-2)',
          }}>{v}</kbd>
        </SettingRow>
      ))}
    </Card>
  );
}

function PermissionsSection() {
  const { t } = useTranslation();
  const [accessibility, setAccessibility] = useState<PermissionStatus | 'loading'>('loading');
  const [microphone, setMicrophone] = useState<PermissionStatus | 'loading'>('loading');
  const [hotkey, setHotkey] = useState<HotkeyStatus | null>(null);
  const [windowsIme, setWindowsIme] = useState<WindowsImeStatus | null>(null);
  const { capability } = useHotkeySettings();

  const refreshPermissions = async () => {
    const [a, m] = await Promise.all([
      checkAccessibilityPermission(),
      checkMicrophonePermission(),
    ]);
    setAccessibility(a);
    setMicrophone(m);
  };

  const refreshHotkey = async () => {
    setHotkey(await getHotkeyStatus());
  };

  const refreshWindowsIme = async () => {
    setWindowsIme(await getWindowsImeStatus());
  };

  useEffect(() => {
    refreshPermissions();
    refreshHotkey();
    refreshWindowsIme();
    const hotkeyId = window.setInterval(refreshHotkey, 1000);
    // 楹﹀厠椋庢鏌ヤ細鐭殏鎵撳紑杈撳叆娴侊紝閬垮厤姣忕鎺㈡祴瀵艰嚧闅愮鎸囩ず鍣ㄩ绻侀棯鐑併€?
    const permissionId = window.setInterval(refreshPermissions, 10000);
    const onFocus = () => {
      refreshPermissions();
      refreshHotkey();
      refreshWindowsIme();
    };
    window.addEventListener('focus', onFocus);
    return () => {
      window.clearInterval(hotkeyId);
      window.clearInterval(permissionId);
      window.removeEventListener('focus', onFocus);
    };
  }, []);

  const reRequestAccessibility = async () => {
    await requestAccessibilityPermission();
    refreshPermissions();
  };

  const reRequestMicrophone = async () => {
    if (microphone === 'denied' || microphone === 'restricted') {
      await openSystemSettings('microphone');
      refreshPermissions();
      return;
    }
    const status = await requestMicrophonePermission();
    setMicrophone(status);
    if (status === 'denied' || status === 'restricted') {
      await openSystemSettings('microphone');
    }
    refreshPermissions();
  };

  const desc = capability?.requiresAccessibilityPermission
    ? t('settings.permissions.descAcc')
    : t('settings.permissions.descNoAcc');

  return (
    <Card>
      <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 4 }}>{t('settings.permissions.title')}</div>
      <div style={{ fontSize: 11.5, color: 'var(--ol-ink-4)', marginBottom: 6 }}>
        {desc}
      </div>
      <SettingRow label={t('settings.permissions.micLabel')} desc={t('settings.permissions.micDesc')}>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
          <PermissionPill status={microphone} />
          {microphone !== 'granted' && microphone !== 'notApplicable' && microphone !== 'loading' && (
            <Btn variant="ghost" size="sm" onClick={reRequestMicrophone}>
              {microphone === 'denied' || microphone === 'restricted' ? t('settings.permissions.openSystem') : t('settings.permissions.grant')}
            </Btn>
          )}
        </div>
      </SettingRow>
      {capability?.requiresAccessibilityPermission && (
        <SettingRow label={t('settings.permissions.accLabel')} desc={t('settings.permissions.accDesc')}>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <PermissionPill status={accessibility} />
            {accessibility !== 'granted' && accessibility !== 'notApplicable' && (
              <Btn variant="ghost" size="sm" onClick={reRequestAccessibility}>
                {t('settings.permissions.grant')}
              </Btn>
            )}
          </div>
        </SettingRow>
      )}
      <SettingRow
        label={t('settings.permissions.hotkeyLabel')}
        desc={capability ? t('settings.permissions.hotkeyDescWithAdapter', { adapter: adapterDisplayName(capability.adapter) }) : t('settings.permissions.hotkeyDescPlain')}
      >
        <div style={{ display: 'flex', gap: 8, alignItems: 'center', minWidth: 0 }}>
          <HotkeyStatusPill status={hotkey} />
          {hotkey?.message && (
            <span style={{ fontSize: 11.5, color: 'var(--ol-ink-4)', overflow: 'hidden', textOverflow: 'ellipsis' }}>
              {hotkey.message}
            </span>
          )}
        </div>
      </SettingRow>
      {windowsIme?.state !== 'notWindows' && (
        <SettingRow
          label={t('settings.permissions.windowsImeLabel')}
          desc={t('settings.permissions.windowsImeDesc')}
        >
          <div style={{ display: 'flex', gap: 8, alignItems: 'center', minWidth: 0 }}>
            <WindowsImeStatusPill status={windowsIme} />
            {windowsIme && (
              <span style={{ fontSize: 11.5, color: 'var(--ol-ink-4)', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                {t(`settings.permissions.windowsIme.${windowsIme.state}`)}
              </span>
            )}
          </div>
        </SettingRow>
      )}
      <SettingRow label={t('settings.permissions.networkLabel')} desc={t('settings.permissions.networkDesc')}>
        <Pill tone="ok"><Icon name="check" size={11} />{t('settings.permissions.networkOk')}</Pill>
      </SettingRow>
    </Card>
  );
}

function PermissionPill({ status }: { status: PermissionStatus | 'loading' }) {
  const { t } = useTranslation();
  if (status === 'loading') {
    return <Pill tone="default">{t('settings.permissions.checking')}</Pill>;
  }
  if (status === 'granted') {
    return <Pill tone="ok"><Icon name="check" size={11} />{t('settings.permissions.granted')}</Pill>;
  }
  if (status === 'notApplicable') {
    return <Pill tone="default">{t('settings.permissions.notApplicable')}</Pill>;
  }
  if (status === 'denied' || status === 'restricted') {
    return <Pill tone="outline">{t('settings.permissions.denied')}</Pill>;
  }
  return <Pill tone="outline">{t('settings.permissions.indeterminate')}</Pill>;
}

function LanguageSection() {
  const { t } = useTranslation();
  const { updatePrefs } = useHotkeySettings();
  const [pref, setPref] = useState<SupportedLocale | typeof FOLLOW_SYSTEM>(getLocalePreference());

  const apply = async (next: SupportedLocale | typeof FOLLOW_SYSTEM) => {
    setPref(next);
    const resolved = await setLocalePreference(next);
    const localePrefs = outputPrefsForLocale(resolved);
    await updatePrefs(current => {
      if (
        current.chineseScriptPreference === localePrefs.chineseScriptPreference &&
        current.outputLanguagePreference === localePrefs.outputLanguagePreference
      ) {
        return current;
      }
      return { ...current, ...localePrefs };
    });
  };

  return (
    <Card>
      <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 4 }}>{t('settings.language.title')}</div>
      <div style={{ fontSize: 11.5, color: 'var(--ol-ink-4)', marginBottom: 6 }}>{t('settings.language.desc')}</div>
      <SettingRow label={t('settings.language.label')} desc={t('settings.language.labelDesc')}>
        <select
          value={pref}
          onChange={e => apply(e.target.value as SupportedLocale | typeof FOLLOW_SYSTEM)}
          style={{ ...inputStyle, maxWidth: 220 }}
        >
          <option value={FOLLOW_SYSTEM}>{t('settings.language.followSystem')}</option>
          <option value="zh-CN">{t('settings.language.zh')}</option>
          <option value="zh-TW">{t('settings.language.zhTW')}</option>
          <option value="en">{t('settings.language.en')}</option>
          <option value="ja">{t('settings.language.ja')}</option>
          <option value="ko">{t('settings.language.ko')}</option>
        </select>
      </SettingRow>
      <div style={{ fontSize: 11, color: 'var(--ol-ink-4)', marginTop: 8, lineHeight: 1.6 }}>
        {t('settings.language.restartHint')}
      </div>
    </Card>
  );
}

// AboutSection 宸茬Щ闄わ細鍐呭骞跺叆 SettingsModal 鐨?AboutMini锛岄伩鍏嶈缃唴澶栦袱涓?鍏充簬"閲嶅鍏ュ彛銆?

export function AboutUpdateControl({ tagline }: { tagline: string }) {
  const { t } = useTranslation();
  const u = useAutoUpdate();
  return (
    <>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 2 }}>
        <span style={{ fontSize: 12, color: 'var(--ol-ink-3)' }}>{tagline} 路 {APP_VERSION_LABEL}</span>
        <Btn variant="ghost" size="sm" onClick={u.checkForUpdates} disabled={u.checking || u.busy}>
          {u.checking ? t('settings.about.checkingUpdate') : t('settings.about.checkUpdateBtn')}
        </Btn>
      </div>
      {(u.status === 'none' || u.status === 'error') && (
        <div style={{ fontSize: 11, color: u.status === 'error' ? 'var(--ol-err)' : 'var(--ol-ink-4)', marginTop: 4 }}>
          {u.status === 'none' ? t('settings.about.upToDate') : t('settings.about.updateError')}
        </div>
      )}
      {isDialogStatus(u.status) && (
        <UpdateDialog
          status={u.status}
          version={u.version}
          progress={u.progress}
          downloaded={u.downloaded}
          contentLength={u.contentLength}
          onInstall={u.installUpdate}
          onClose={u.dismissDialog}
        />
      )}
    </>
  );
}

function HotkeyStatusPill({ status }: { status: HotkeyStatus | null }) {
  const { t } = useTranslation();
  if (!status) {
    return <Pill tone="default">{t('settings.permissions.checking')}</Pill>;
  }
  if (status.state === 'installed') {
    return <Pill tone="ok"><Icon name="check" size={11} />{t('settings.permissions.hotkeyInstalled')}</Pill>;
  }
  if (status.state === 'starting') {
    return <Pill tone="default">{t('settings.permissions.hotkeyStarting')}</Pill>;
  }
  return <Pill tone="outline">{t('settings.permissions.hotkeyFailed')}</Pill>;
}

function WindowsImeStatusPill({ status }: { status: WindowsImeStatus | null }) {
  const { t } = useTranslation();
  if (!status) {
    return <Pill tone="default">{t('settings.permissions.checking')}</Pill>;
  }
  if (status.state === 'installed') {
    return <Pill tone="ok"><Icon name="check" size={11} />{t('settings.permissions.windowsImeInstalled')}</Pill>;
  }
  return <Pill tone="outline">{t('settings.permissions.windowsImeUnavailable')}</Pill>;
}

function adapterDisplayName(adapter: HotkeyCapability['adapter'] | HotkeyStatus['adapter']) {
  if (adapter === 'macEventTap') return i18n.t('hotkey.adapter.macEventTap');
  if (adapter === 'windowsLowLevel') return i18n.t('hotkey.adapter.windowsLowLevel');
  return i18n.t('hotkey.adapter.rdev');
}

/// 鏈湴 Qwen3-ASR 鍦?Settings 鈫?鏈嶅姟鍟嗗尯閲?*涓?*璁╃敤鎴峰～绌衡€斺€斿睍绀哄綋鍓嶆縺娲绘ā鍨?
/// 鏄惁宸蹭笅杞姐€佸垪鍑烘墍鏈夊凡涓嬭浇妯″瀷 + 鍒犻櫎鎸夐挳锛屽苟鎻愮ず鎬ц兘/璐ㄩ噺棰勬湡锛屽紩瀵艰烦鍒?
/// 銆屾ā鍨嬭缃€嶉〉鍋氫笅杞姐€?
function LocalAsrProviderHint({
  provider,
  selectedProvider,
}: {
  provider: 'local-qwen3' | 'foundry-local-whisper';
  selectedProvider: AsrPresetId;
}) {
  const { t } = useTranslation();
  const [settings, setSettings] = useState<LocalAsrSettings | null>(null);
  const [models, setModels] = useState<LocalAsrModelStatus[]>([]);
  const [loading, setLoading] = useState(true);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const refreshSeqRef = useRef(0);
  const providerStateRef = useRef({ provider, selectedProvider });
  providerStateRef.current = { provider, selectedProvider };

  const qwenReadyForFetch = () => {
    const state = providerStateRef.current;
    return state.provider === 'local-qwen3' && state.selectedProvider === 'local-qwen3';
  };

  const refresh = async (seq: number) => {
    try {
      const [s, list] = await Promise.all([getLocalAsrSettings(), listLocalAsrModels()]);
      if (seq !== refreshSeqRef.current) {
        return;
      }
      setSettings(s);
      setModels(list);
    } catch (err) {
      if (seq !== refreshSeqRef.current) {
        return;
      }
      console.warn('[settings] load local asr status failed', err);
    } finally {
      if (seq === refreshSeqRef.current) {
        setLoading(false);
      }
    }
  };

  const beginRefresh = () => {
    const seq = ++refreshSeqRef.current;
    setSettings(null);
    setModels([]);
    setDeletingId(null);
    if (provider !== selectedProvider) {
      setLoading(true);
      return;
    }
    if (provider === 'foundry-local-whisper') {
      setLoading(false);
      return;
    }
    setLoading(true);
    void refresh(seq);
  };

  useEffect(() => {
    beginRefresh();
    return () => {
      refreshSeqRef.current += 1;
    };
  }, [provider, selectedProvider]);

  const goToLocalAsr = () => {
    window.dispatchEvent(new CustomEvent(NAVIGATE_LOCAL_ASR_EVENT));
  };

  const handleDelete = async (modelId: string) => {
    const seq = refreshSeqRef.current;
    if (!qwenReadyForFetch()) {
      return;
    }
    setDeletingId(modelId);
    try {
      await deleteLocalAsrModel(modelId);
      if (seq !== refreshSeqRef.current || !qwenReadyForFetch()) {
        return;
      }
      beginRefresh();
    } catch (err) {
      console.warn('[settings] delete local model failed', err);
    } finally {
      if (seq === refreshSeqRef.current && provider === 'local-qwen3') {
        setDeletingId(null);
      }
    }
  };

  const hintKey = provider === 'foundry-local-whisper'
    ? 'settings.providers.foundryLocalAsrHint'
    : 'settings.providers.localAsrHint';

  if (loading) {
    return (
      <div style={{ padding: '12px 0', fontSize: 12.5, color: 'var(--ol-ink-4)' }}>
        {t('common.loading')}
      </div>
    );
  }

  const active = models.find(m => m.id === settings?.activeModel);
  const isReady = active?.isDownloaded ?? false;
  const downloaded = models.filter(m => m.isDownloaded);

  if (provider === 'foundry-local-whisper') {
    return (
      <div style={{ padding: '8px 0 4px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        <div style={{ fontSize: 12.5, color: 'var(--ol-ink-3)', lineHeight: 1.6 }}>
          {t(hintKey)}
        </div>
        <div>
          <Btn variant="ghost" size="sm" onClick={goToLocalAsr}>
            {t('settings.providers.localAsrManage')}
          </Btn>
        </div>
      </div>
    );
  }

  return (
    <div style={{ padding: '8px 0 4px', display: 'flex', flexDirection: 'column', gap: 12 }}>
      {/* 鎬ц兘/璐ㄩ噺棰勬湡璀﹀憡 鈥斺€?鐢ㄦ埛纭姹傝鍐欐竻妤?*/}
      <div
        style={{
          padding: '10px 12px',
          background: 'rgba(255, 215, 130, 0.18)',
          borderRadius: 8,
          fontSize: 12.5,
          color: 'var(--ol-ink-2)',
          lineHeight: 1.6,
        }}>
        鈿狅笍 {t('settings.providers.localAsrPerformanceWarning')}
      </div>

      <div style={{ fontSize: 12.5, color: 'var(--ol-ink-3)', lineHeight: 1.6 }}>
        {t(hintKey)}
      </div>

      {/* 褰撳墠婵€娲绘ā鍨嬬姸鎬?+ 璺宠浆鎸夐挳 */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
        <Pill tone={isReady ? 'ok' : 'outline'} size="sm">
          {isReady
            ? t('settings.providers.localAsrReady', { model: active?.id ?? '' })
            : t('settings.providers.localAsrNotReady', { model: settings?.activeModel ?? '' })}
        </Pill>
        <Btn variant={isReady ? 'ghost' : 'primary'} size="sm" onClick={goToLocalAsr}>
          {isReady
            ? t('settings.providers.localAsrManage')
            : t('settings.providers.localAsrGoDownload')}
        </Btn>
      </div>

      {/* 宸蹭笅杞芥ā鍨嬪垪琛?+ 鍒犻櫎鎸夐挳锛堢敤鎴凤細宸蹭笅杞界殑椤圭洰瑕佸湪鏃佽竟鏄剧ず + 鎻愪緵鍒犻櫎锛?*/}
      {downloaded.length > 0 && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          <div style={{ fontSize: 11.5, fontWeight: 600, color: 'var(--ol-ink-4)', letterSpacing: '.04em', textTransform: 'uppercase' }}>
            {t('settings.providers.localAsrDownloadedTitle')}
          </div>
          {downloaded.map(m => (
            <div
              key={m.id}
              style={{
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                padding: '6px 10px',
                borderRadius: 6,
                background: 'rgba(0,0,0,0.03)',
                fontSize: 12.5,
                color: 'var(--ol-ink-2)',
              }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
                <span style={{ fontWeight: 500 }}>{m.id}</span>
                <span style={{ fontSize: 11, color: 'var(--ol-ink-4)' }}>
                  {formatBytes(m.downloadedBytes)}
                </span>
              </div>
              <Btn
                variant="ghost"
                size="sm"
                disabled={deletingId === m.id}
                onClick={() => void handleDelete(m.id)}>
                {t('settings.providers.localAsrDelete')}
              </Btn>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(0)} MB`;
  return `${(n / 1024 / 1024 / 1024).toFixed(2)} GB`;
}
