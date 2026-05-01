// QaPanel.tsx — 划词语音问答浮窗。详见 issue #118。
//
// 触发链路：
//   1) 用户选中文本 → 按 Cmd+Shift+;（默认）→ 后端打开本窗口（label="qa"）
//      并发 `qa:state { kind: "loading", selection_preview }` 事件，开始录音。
//   2) 用户提问完毕，再次按热键 → 后端转写 + LLM 回答 → 发
//      `qa:state { kind: "answer", answer_md }`，本组件用 marked 渲染。
//   3) 出错 → `qa:state { kind: "error", error }`，显示红色文案 + 重试按钮。
//
// 关闭时机（任一）：
//   - Esc / Close 按钮 / 点击窗口外（除非 Pin）→ qa_window_dismiss()
//   - 30s 超时（除非 Pin）→ qa_window_dismiss()
//   - 后端发 `qa:dismiss` 事件 → 直接关窗

import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react';
import { useTranslation } from 'react-i18next';
import { marked } from 'marked';
import { isTauri, qaWindowDismiss, qaWindowPin } from '../lib/ipc';
import type { QaStatePayload } from '../lib/types';

const AUTO_DISMISS_MS = 30_000;
const SELECTION_PREVIEW_MAX = 60;

// marked 配置：开启换行符识别，关闭 mangle/headerIds（v11 已默认关闭）。
marked.setOptions({ gfm: true, breaks: true });

export function QaPanel() {
  const { t } = useTranslation();
  const [payload, setPayload] = useState<QaStatePayload>({ kind: 'loading' });
  const [pinned, setPinned] = useState(false);
  const pinnedRef = useRef(false);

  // ── 后端事件订阅 ────────────────────────────────────────────────────
  useEffect(() => {
    if (!isTauri) return;
    let unlistenState: (() => void) | undefined;
    let unlistenDismiss: (() => void) | undefined;
    let cancelled = false;
    (async () => {
      const { listen } = await import('@tauri-apps/api/event');
      const stateHandle = await listen<QaStatePayload>('qa:state', event => {
        // 后端在 session 结束（含 cancel / 静默 / 完成）时会再发一条 kind:"idle"。
        // 它的语义是"会话状态机回到 Idle"，**不**应替换 UI（pinned 用户希望继续看 answer）。
        // 不 pinned 时后端紧接着自己 hide 窗口，前端拿到 idle 也无妨。
        const kind = (event.payload as { kind?: string }).kind;
        if (kind === 'idle') return;
        setPayload(event.payload);
      });
      const dismissHandle = await listen<unknown>('qa:dismiss', () => {
        // 后端要求关闭：直接转发到 dismiss 命令；同时 reset pin 状态
        // 让用户下次开新窗口拿到默认 unpinned。
        pinnedRef.current = false;
        setPinned(false);
        void qaWindowDismiss();
      });
      if (cancelled) {
        stateHandle();
        dismissHandle();
      } else {
        unlistenState = stateHandle;
        unlistenDismiss = dismissHandle;
      }
    })();
    return () => {
      cancelled = true;
      unlistenState?.();
      unlistenDismiss?.();
    };
  }, []);

  // ── Esc 关闭 ────────────────────────────────────────────────────────
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        void qaWindowDismiss();
      }
    };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, []);

  // ── 失焦自动关闭（除非 Pin）────────────────────────────────────────
  useEffect(() => {
    const onBlur = () => {
      if (pinnedRef.current) return;
      void qaWindowDismiss();
    };
    window.addEventListener('blur', onBlur);
    return () => window.removeEventListener('blur', onBlur);
  }, []);

  // ── 30s 自动关闭（除非 Pin），payload 变化或 pin 切换时重置 ──────
  useEffect(() => {
    if (pinned) return;
    const timer = window.setTimeout(() => {
      if (!pinnedRef.current) void qaWindowDismiss();
    }, AUTO_DISMISS_MS);
    return () => window.clearTimeout(timer);
  }, [payload, pinned]);

  const onTogglePin = () => {
    const next = !pinned;
    pinnedRef.current = next;
    setPinned(next);
    void qaWindowPin(next);
  };

  const onClose = () => {
    void qaWindowDismiss();
  };

  return (
    <div style={shellStyle}>
      <Toolbar pinned={pinned} onTogglePin={onTogglePin} onClose={onClose} />
      <div style={contentStyle}>
        <Body payload={payload} t={t} />
      </div>
    </div>
  );
}

// ── 子组件 ────────────────────────────────────────────────────────────

interface ToolbarProps {
  pinned: boolean;
  onTogglePin: () => void;
  onClose: () => void;
}

function Toolbar({ pinned, onTogglePin, onClose }: ToolbarProps) {
  const { t } = useTranslation();
  return (
    <div style={toolbarStyle}>
      <div style={{ flex: 1 }} />
      <IconBtn
        label={pinned ? t('qa.unpinTooltip') : t('qa.pinTooltip')}
        active={pinned}
        onClick={onTogglePin}
      >
        {/* Pin 图标 */}
        <svg width="13" height="13" viewBox="0 0 16 16" fill="none">
          <path
            d="M10.5 2L14 5.5L11.5 8L9.5 7L7 9.5L6.5 9L4 11.5L3 13L4.5 11.5L7 9L6.5 8.5L9 6L8 4L10.5 2Z"
            stroke="currentColor"
            strokeWidth="1.2"
            strokeLinejoin="round"
            fill={pinned ? 'currentColor' : 'none'}
          />
        </svg>
      </IconBtn>
      <IconBtn label={t('qa.closeTooltip')} onClick={onClose}>
        <svg width="11" height="11" viewBox="0 0 11 11">
          <path
            d="M1.5 1.5l8 8M9.5 1.5l-8 8"
            stroke="currentColor"
            strokeWidth="1.6"
            strokeLinecap="round"
          />
        </svg>
      </IconBtn>
    </div>
  );
}

interface IconBtnProps {
  label: string;
  active?: boolean;
  onClick: () => void;
  children: React.ReactNode;
}

function IconBtn({ label, active, onClick, children }: IconBtnProps) {
  return (
    <button
      onClick={onClick}
      title={label}
      aria-label={label}
      style={{
        ...iconBtnBaseStyle,
        color: active ? 'var(--ol-blue)' : 'var(--ol-ink-3)',
        background: active ? 'rgba(37,99,235,0.12)' : 'transparent',
      }}
    >
      {children}
    </button>
  );
}

interface BodyProps {
  payload: QaStatePayload;
  t: ReturnType<typeof useTranslation>['t'];
}

function Body({ payload, t }: BodyProps) {
  if (payload.kind === 'loading') {
    return <LoadingView preview={payload.selection_preview} t={t} />;
  }
  if (payload.kind === 'error') {
    return <ErrorView message={payload.error ?? t('qa.error')} t={t} />;
  }
  return <AnswerView markdown={payload.answer_md ?? ''} />;
}

function LoadingView({ preview, t }: { preview: string | undefined; t: BodyProps['t'] }) {
  const truncated = useMemo(() => truncate(preview ?? '', SELECTION_PREVIEW_MAX), [preview]);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      {truncated && (
        <div style={previewStyle}>
          <span style={{ color: 'var(--ol-ink-4)', marginRight: 4 }}>
            {t('qa.selectionPreview')}
          </span>
          <span style={{ color: 'var(--ol-ink-2)' }}>{truncated}</span>
        </div>
      )}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <SkeletonLine width="62%" />
        <SkeletonLine width="86%" />
        <SkeletonLine width="44%" />
      </div>
      <div style={{ fontSize: 12, color: 'var(--ol-ink-3)', fontWeight: 500 }}>
        {t('qa.thinking')}
      </div>
    </div>
  );
}

function SkeletonLine({ width }: { width: string }) {
  return (
    <div
      style={{
        height: 10,
        width,
        borderRadius: 6,
        background:
          'linear-gradient(90deg, rgba(0,0,0,0.06) 0%, rgba(0,0,0,0.10) 50%, rgba(0,0,0,0.06) 100%)',
        backgroundSize: '200% 100%',
        animation: 'qa-skeleton 1.4s ease-in-out infinite',
      }}
    />
  );
}

function ErrorView({ message, t }: { message: string; t: BodyProps['t'] }) {
  // 重试按钮：关掉浮窗，让用户重按 hotkey。详见 issue #118。
  const onRetry = () => {
    void qaWindowDismiss();
  };
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <div style={{ fontSize: 13, color: 'var(--ol-err)', lineHeight: 1.55 }}>{message}</div>
      <button onClick={onRetry} style={retryBtnStyle}>
        {t('qa.errorRetry')}
      </button>
    </div>
  );
}

function AnswerView({ markdown }: { markdown: string }) {
  // marked v11 同步调用返回 string；启用 GFM + breaks。
  // 注意：markdown 来自我们自己的后端 → LLM，链路可信，未额外 sanitize。
  // 如未来引入用户自由文本拼装到 prompt，需要补 DOMPurify。
  const html = useMemo(() => {
    try {
      return marked.parse(markdown, { async: false }) as string;
    } catch (error) {
      console.error('[qa] failed to render markdown', error);
      return '';
    }
  }, [markdown]);
  return (
    <div
      className="qa-answer"
      style={answerStyle}
      // eslint-disable-next-line react/no-danger
      dangerouslySetInnerHTML={{ __html: html }}
    />
  );
}

function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  return `${text.slice(0, max)}…`;
}

// ── 样式 ──────────────────────────────────────────────────────────────

const shellStyle: CSSProperties = {
  width: '100%',
  height: '100vh',
  display: 'flex',
  flexDirection: 'column',
  borderRadius: 14,
  overflow: 'hidden',
  background: 'rgba(255, 255, 255, 0.85)',
  backdropFilter: 'blur(24px) saturate(180%)',
  WebkitBackdropFilter: 'blur(24px) saturate(180%)',
  border: '0.5px solid rgba(255, 255, 255, 0.7)',
  boxShadow: 'var(--ol-shadow-lg)',
  fontFamily: 'var(--ol-font-sans)',
  color: 'var(--ol-ink)',
};

const toolbarStyle: CSSProperties = {
  height: 32,
  display: 'flex',
  alignItems: 'center',
  gap: 4,
  padding: '0 8px',
  borderBottom: '0.5px solid rgba(0, 0, 0, 0.06)',
  flexShrink: 0,
  // 让用户可以拖动整个浮窗（macOS / Win 通用）。
  // @ts-expect-error: vendor prefix not in CSSProperties typing
  WebkitAppRegion: 'drag',
};

const iconBtnBaseStyle: CSSProperties = {
  width: 22,
  height: 22,
  border: 0,
  borderRadius: 6,
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
  cursor: 'default',
  padding: 0,
  transition: 'background 0.12s ease-out, color 0.12s ease-out',
  // @ts-expect-error: vendor prefix not in CSSProperties typing
  WebkitAppRegion: 'no-drag',
};

const contentStyle: CSSProperties = {
  flex: 1,
  minHeight: 0,
  overflow: 'auto',
  padding: '14px 18px',
};

const previewStyle: CSSProperties = {
  fontSize: 11.5,
  lineHeight: 1.5,
  padding: '8px 10px',
  borderRadius: 8,
  background: 'rgba(0, 0, 0, 0.035)',
  border: '0.5px solid rgba(0, 0, 0, 0.06)',
};

const retryBtnStyle: CSSProperties = {
  alignSelf: 'flex-start',
  padding: '5px 12px',
  fontSize: 12,
  fontWeight: 500,
  border: '0.5px solid var(--ol-line-strong)',
  borderRadius: 6,
  background: 'var(--ol-surface)',
  color: 'var(--ol-ink-2)',
  cursor: 'default',
  fontFamily: 'inherit',
};

const answerStyle: CSSProperties = {
  fontSize: 13,
  lineHeight: 1.6,
  color: 'var(--ol-ink)',
  wordWrap: 'break-word',
};

// 注入全局 keyframes + .qa-answer 内 markdown 排版样式。
// 不放 styles/global.css 是因为只有这个窗口需要。
const globalCss = `
@keyframes qa-skeleton {
  0%   { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}
.qa-answer p        { margin: 0 0 8px; }
.qa-answer p:last-child { margin-bottom: 0; }
.qa-answer h1,
.qa-answer h2,
.qa-answer h3       { margin: 12px 0 6px; font-weight: 600; line-height: 1.35; }
.qa-answer h1       { font-size: 16px; }
.qa-answer h2       { font-size: 14px; }
.qa-answer h3       { font-size: 13px; }
.qa-answer ul,
.qa-answer ol       { margin: 0 0 8px; padding-left: 20px; }
.qa-answer li       { margin: 2px 0; }
.qa-answer code     { font-family: var(--ol-font-mono); font-size: 12px;
                      padding: 1px 5px; border-radius: 4px;
                      background: rgba(0,0,0,0.05); }
.qa-answer pre      { margin: 0 0 8px; padding: 10px 12px;
                      border-radius: 8px; background: rgba(0,0,0,0.05);
                      overflow-x: auto; }
.qa-answer pre code { padding: 0; background: transparent; }
.qa-answer a        { color: var(--ol-blue); text-decoration: none; }
.qa-answer a:hover  { text-decoration: underline; }
.qa-answer blockquote { margin: 0 0 8px; padding: 4px 0 4px 10px;
                        border-left: 2px solid rgba(0,0,0,0.15);
                        color: var(--ol-ink-3); }
.qa-answer hr       { border: 0; border-top: 0.5px solid rgba(0,0,0,0.10);
                      margin: 10px 0; }
`;

// 单次注入。重复挂载（HMR）时会被同 id 替换。
if (typeof document !== 'undefined' && !document.getElementById('qa-panel-style')) {
  const tag = document.createElement('style');
  tag.id = 'qa-panel-style';
  tag.textContent = globalCss;
  document.head.appendChild(tag);
}
