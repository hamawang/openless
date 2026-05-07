// SelectionAsk.tsx 鈥?鐙珛鐨?鍒掕瘝杩介棶"椤碉紙issue #118 / PR #119 閰嶇疆 UI 鎷嗗垎鐗堬級銆?
// 鍔熻兘锛氱敤鎴峰湪浠绘剰 app 閫変腑涓€娈垫枃瀛?鈫?鎸?hotkey 鈫?娴獥寮瑰嚭 + 杩涘叆璇煶褰曢煶 鈫?
// 鐢ㄦ埛鍙ｈ堪鎻愰棶 鈫?ASR + 閫夊尯 + 鎻愰棶 涓€璧烽€?LLM 鈫?绛旀浠?markdown 鏄剧ず鍦ㄦ诞绐椼€?
//
// 杩欎竴椤垫妸鍘熸湰鏁ｅ湪 Settings 鈫?褰曢煶 閲岀殑涓ゆ潯閰嶇疆锛坔otkey 棰勮 / 淇濆瓨 Q&A 鍘嗗彶锛?
// 闆嗕腑璧锋潵 + 鍔犲畬鏁翠娇鐢ㄦ寚鍗楋紝璺?缈昏瘧"椤靛钩绾с€?

import { useTranslation } from 'react-i18next';
import { Card, PageHeader } from './_atoms';
import { useHotkeySettings } from '../state/HotkeySettingsContext';
import { setQaHotkey } from '../lib/ipc';
import { defaultQaShortcut, formatComboLabel } from '../lib/hotkey';
import { ShortcutRecorder } from '../components/ShortcutRecorder';

export function SelectionAsk() {
  const { t } = useTranslation();
  const { prefs, updatePrefs: savePrefs } = useHotkeySettings();
  const defaultQaHotkey = defaultQaShortcut();
  const defaultHotkeyLabel = formatComboLabel(defaultQaHotkey);
  const recordHotkeyLabel = prefs ? formatComboLabel(prefs.dictationHotkey) : '快捷键';
  if (!prefs) {
    return (
      <>
        <PageHeader
          kicker={t('selectionAsk.kicker')}
          title={t('selectionAsk.title')}
          desc={t('selectionAsk.desc', {
            hotkey: defaultHotkeyLabel,
            recordHotkey: recordHotkeyLabel,
          })}
        />
        <Card>
          <div style={{ fontSize: 12, color: 'var(--ol-ink-4)' }}>{t('common.loading')}</div>
        </Card>
      </>
    );
  }

  const onSaveHistoryChange = (qaSaveHistory: boolean) =>
    savePrefs({ ...prefs, qaSaveHistory });

  const enabled = prefs.qaHotkey !== null;
  const currentLabel = prefs.qaHotkey ? formatComboLabel(prefs.qaHotkey) : defaultHotkeyLabel;

  return (
    <>
      <PageHeader
        kicker={t('selectionAsk.kicker')}
        title={t('selectionAsk.title')}
        desc={t('selectionAsk.desc', {
          hotkey: enabled ? currentLabel : defaultHotkeyLabel,
          recordHotkey: recordHotkeyLabel,
        })}
      />

      <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>

        {/* 1. 瑙﹀彂蹇嵎閿?*/}
        <Card>
          <CardHeaderToggle
            title={t('selectionAsk.hotkey.title')}
            checked={enabled}
            onToggle={async () => {
              const nextHotkey = enabled ? null : defaultQaHotkey;
              await setQaHotkey(nextHotkey);
              await savePrefs({ ...prefs, qaHotkey: nextHotkey });
            }}
          />
          <div style={{ fontSize: 11.5, color: 'var(--ol-ink-4)', marginBottom: prefs.qaHotkey ? 12 : 0, lineHeight: 1.55 }}>
            {t('selectionAsk.hotkey.desc', { recordHotkey: recordHotkeyLabel })}
          </div>
          {prefs.qaHotkey && (
            <ShortcutRecorder
              value={prefs.qaHotkey}
              onSave={async binding => {
                await setQaHotkey(binding);
                await savePrefs({ ...prefs, qaHotkey: binding });
              }}
            />
          )}
        </Card>

        {/* 2. 鍘嗗彶淇濆瓨 */}
        <Card>
          <CardHeaderToggle
            title={t('selectionAsk.history.title')}
            checked={prefs.qaSaveHistory}
            onToggle={() => onSaveHistoryChange(!prefs.qaSaveHistory)}
          />
          <div style={{ fontSize: 11.5, color: 'var(--ol-ink-4)', lineHeight: 1.55 }}>
            {t('selectionAsk.history.desc')}
          </div>
        </Card>

        {/* 3. 浣跨敤鏂规硶 */}
        <Card>
          <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 10 }}>{t('selectionAsk.howto.title')}</div>
          <ol style={{ margin: 0, paddingLeft: 18, fontSize: 12.5, color: 'var(--ol-ink-2)', lineHeight: 1.7 }}>
            <li>{t('selectionAsk.howto.step1', { hotkey: enabled ? currentLabel : defaultHotkeyLabel })}</li>
            <li>{t('selectionAsk.howto.step2')}</li>
            <li>{t('selectionAsk.howto.step3', { recordHotkey: recordHotkeyLabel })}</li>
            <li>{t('selectionAsk.howto.step4', { recordHotkey: recordHotkeyLabel })}</li>
            <li>{t('selectionAsk.howto.step5', { hotkey: enabled ? currentLabel : defaultHotkeyLabel })}</li>
          </ol>

          <div
            style={{
              marginTop: 14,
              padding: '10px 12px',
              borderRadius: 10,
              background: 'rgba(37,99,235,0.06)',
              border: '0.5px solid rgba(37,99,235,0.15)',
              fontSize: 11.5,
              color: 'var(--ol-ink-2)',
              lineHeight: 1.55,
            }}
          >
            <div style={{ fontWeight: 600, color: 'var(--ol-blue)', marginBottom: 4 }}>{t('selectionAsk.howto.windowTitle')}</div>
            {t('selectionAsk.howto.windowDesc')}
          </div>

          <div
            style={{
              marginTop: 10,
              padding: '10px 12px',
              borderRadius: 10,
              background: 'rgba(0,0,0,0.04)',
              fontSize: 11.5,
              color: 'var(--ol-ink-3)',
              lineHeight: 1.55,
            }}
          >
            <div style={{ fontWeight: 600, color: 'var(--ol-ink-2)', marginBottom: 4 }}>{t('selectionAsk.howto.privacyTitle')}</div>
            {t('selectionAsk.howto.privacyDesc')}
          </div>
        </Card>
      </div>
    </>
  );
}
// 鍗＄墖鏍囬琛屽彸渚у紑鍏筹細涓?Style 椤甸潰椤舵爮鐨?36脳20 toggle 鍚屾锛屼繚鎸佸叏灞€瑙嗚涓€鑷淬€?
function CardHeaderToggle({
  title,
  checked,
  onToggle,
}: {
  title: string;
  checked: boolean;
  onToggle: () => void;
}) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 }}>
      <div style={{ fontSize: 13, fontWeight: 600 }}>{title}</div>
      <button
        onClick={onToggle}
        aria-pressed={checked}
        style={{
          position: 'relative',
          width: 36,
          height: 20,
          borderRadius: 999,
          border: 0,
          background: checked ? 'var(--ol-blue)' : 'rgba(0,0,0,0.15)',
          cursor: 'default',
          transition: 'background 0.16s var(--ol-motion-quick)',
          padding: 0,
        }}
      >
        <span
          style={{
            position: 'absolute',
            top: 2,
            left: checked ? 18 : 2,
            width: 16,
            height: 16,
            borderRadius: 999,
            background: '#fff',
            boxShadow: '0 1px 2px rgba(0,0,0,.2)',
            transition: 'left .16s var(--ol-motion-spring)',
          }}
        />
      </button>
    </div>
  );
}
