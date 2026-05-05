import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { getHotkeyCapability, getSettings, setSettings } from '../lib/ipc';
import type { HotkeyBinding, HotkeyCapability, UserPreferences } from '../lib/types';
import i18n from '../i18n';

interface HotkeySettingsContextValue {
  prefs: UserPreferences | null;
  hotkey: HotkeyBinding | null;
  capability: HotkeyCapability | null;
  loading: boolean;
  refresh: () => Promise<void>;
  updatePrefs: (
    next: UserPreferences | ((current: UserPreferences) => UserPreferences),
  ) => Promise<void>;
}

const HotkeySettingsContext = createContext<HotkeySettingsContextValue | null>(null);

export function HotkeySettingsProvider({ children }: { children: ReactNode }) {
  const [prefs, setPrefs] = useState<UserPreferences | null>(null);
  const [capability, setCapability] = useState<HotkeyCapability | null>(null);
  const [loading, setLoading] = useState(true);
  const persistQueueRef = useRef<Promise<void>>(Promise.resolve());
  const latestPrefsRef = useRef<UserPreferences | null>(null);

  const refresh = useCallback(async () => {
    const [nextPrefs, nextCapability] = await Promise.all([getSettings(), getHotkeyCapability()]);
    setPrefs(nextPrefs);
    setCapability(nextCapability);
    setLoading(false);
  }, []);

  const queueSetSettings = useCallback((resolveNext: (current: UserPreferences) => UserPreferences) => {
    const task = persistQueueRef.current
      .catch(() => undefined)
      .then(async () => {
        const current = latestPrefsRef.current;
        if (!current) return;
        const next = resolveNext(current);
        await setSettings(next);
      });
    persistQueueRef.current = task;
    return task;
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    latestPrefsRef.current = prefs;
  }, [prefs]);

  useEffect(() => {
    const currentPrefs = latestPrefsRef.current;
    if (!currentPrefs) return;
    const lang = (i18n.resolvedLanguage || i18n.language || '').toLowerCase();
    const nextScript: UserPreferences['chineseScriptPreference'] =
      lang.startsWith('zh-tw') || lang.includes('hant')
        ? 'traditional'
        : lang.startsWith('zh-cn') || lang.startsWith('zh')
          ? 'simplified'
          : 'auto';
    if (currentPrefs.chineseScriptPreference === nextScript) return;
    const merged = { ...currentPrefs, chineseScriptPreference: nextScript };
    latestPrefsRef.current = merged;
    setPrefs(merged);
    void queueSetSettings(current => ({ ...current, chineseScriptPreference: nextScript })).catch(
      error => {
        console.warn('[settings] sync chineseScriptPreference failed', error);
      },
    );
  }, [prefs, queueSetSettings]);

  const updatePrefs = useCallback(
    async (next: UserPreferences | ((current: UserPreferences) => UserPreferences)) => {
      const current = latestPrefsRef.current;
      if (!current) return;
      const resolved = typeof next === 'function' ? next(current) : next;
      setPrefs(resolved);
      latestPrefsRef.current = resolved;
      await queueSetSettings(() => resolved);
    },
    [queueSetSettings],
  );

  const value = useMemo<HotkeySettingsContextValue>(
    () => ({
      prefs,
      hotkey: prefs?.hotkey ?? null,
      capability,
      loading,
      refresh,
      updatePrefs,
    }),
    [capability, loading, prefs, refresh, updatePrefs],
  );

  return <HotkeySettingsContext.Provider value={value}>{children}</HotkeySettingsContext.Provider>;
}

export function useHotkeySettings() {
  const value = useContext(HotkeySettingsContext);
  if (!value) {
    throw new Error('useHotkeySettings must be used within HotkeySettingsProvider');
  }
  return value;
}
