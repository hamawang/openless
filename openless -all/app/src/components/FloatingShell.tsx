// FloatingShell.tsx — frosted outer frame + raised inner console.
// Sidebar lives INSIDE the console card. Footer icons sit on the frosted outer.
// Settings is no longer a sidebar tab — it opens as a centered modal sheet.
//
// Ported verbatim from design_handoff_openless/variants.jsx::FloatingShell.

import { type ComponentType } from 'react';
import { Icon } from './Icon';
import { WindowChrome, detectOS, type OS } from './WindowChrome';
import { SettingsModal } from './SettingsModal';
import { Overview } from '../pages/Overview';
import { History } from '../pages/History';
import { Vocab } from '../pages/Vocab';
import { Style } from '../pages/Style';
import { OL_DATA } from '../lib/mockData';
import { useAppState, type AppTab } from '../state/useAppState';

interface NavItem {
  id: AppTab;
  name: string;
  icon: string;
  cmp: ComponentType;
}

const NAV: NavItem[] = [
  { id: 'overview', name: '概览', icon: 'overview', cmp: Overview },
  { id: 'history', name: '历史', icon: 'history', cmp: History },
  { id: 'vocab', name: '词汇表', icon: 'vocab', cmp: Vocab },
  { id: 'style', name: '风格', icon: 'style', cmp: Style },
];

interface FloatingShellProps {
  os?: OS;
  initialTab?: AppTab;
  initialSettings?: boolean;
}

export function FloatingShell({ os: osProp, initialTab = 'overview', initialSettings = false }: FloatingShellProps) {
  const os = osProp ?? detectOS();
  return (
    <WindowChrome os={os} title="OpenLess" height="100%">
      <FloatingShellBody os={os} initialTab={initialTab} initialSettings={initialSettings} />
    </WindowChrome>
  );
}

function FloatingShellBody({ os, initialTab, initialSettings }: { os: OS; initialTab: AppTab; initialSettings: boolean }) {
  const { currentTab, setCurrentTab, settingsOpen, setSettingsOpen } = useAppState(initialTab, initialSettings);
  const Page = (NAV.find((n) => n.id === currentTab) ?? NAV[0]).cmp;

  return (
    <div style={{ flex: 1, position: 'relative', display: 'flex', flexDirection: 'column', minHeight: 0, paddingTop: os === 'mac' ? 36 : 0 }}>

      {/* Main shell — flush with the frosted backplate (no separate float). */}
      <div
        style={{
          flex: 1, minHeight: 0,
          display: 'flex',
          background: 'transparent',
          overflow: 'hidden',
          position: 'relative',
          zIndex: 1,
        }}>

        {/* Sidebar — inside the raised console */}
        <aside
          style={{
            width: 188,
            flexShrink: 0,
            display: 'flex', flexDirection: 'column',
            background: 'linear-gradient(180deg, rgba(247,247,250,0.85) 0%, rgba(247,247,250,0.5) 100%)',
            padding: '14px 10px 12px',
          }}>

          {/* brand */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '4px 8px 14px' }}>
            <img
              src="AppIcon.png"
              alt="OpenLess"
              style={{ width: 22, height: 22, borderRadius: 5, boxShadow: '0 1px 2px rgba(0,0,0,.1), 0 0 0 0.5px rgba(0,0,0,.06)' }} />

            <div style={{ fontSize: 13.5, fontWeight: 600, letterSpacing: '-0.01em', color: 'var(--ol-ink)' }}>OpenLess</div>
            <span style={{
              marginLeft: 'auto', padding: '1px 6px', fontSize: 9.5, fontWeight: 600,
              borderRadius: 4, background: 'rgba(0,0,0,0.06)', color: 'var(--ol-ink-3)',
              letterSpacing: '0.04em',
            }}>v1.0</span>
          </div>

          {/* nav */}
          <nav style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            {NAV.map((n) => {
              const active = currentTab === n.id;
              return (
                <button
                  key={n.id}
                  onClick={() => setCurrentTab(n.id)}
                  style={{
                    display: 'flex', alignItems: 'center', gap: 10,
                    padding: '7px 10px',
                    borderRadius: 8, border: 0,
                    background: active ? 'var(--ol-surface)' : 'transparent',
                    color: active ? 'var(--ol-ink)' : 'var(--ol-ink-3)',
                    fontFamily: 'inherit', fontSize: 13, fontWeight: active ? 600 : 500,
                    boxShadow: active ? '0 1px 2px rgba(0,0,0,.05), 0 0 0 0.5px rgba(0,0,0,.06)' : 'none',
                    cursor: 'default', transition: 'background .12s, color .12s',
                    textAlign: 'left',
                  }}>

                  <Icon name={n.icon} size={14} />
                  <span style={{ flex: 1 }}>{n.name}</span>
                  {n.id === 'history' &&
                  <span style={{
                    fontSize: 10, fontFamily: 'var(--ol-font-mono)',
                    color: active ? 'var(--ol-ink-4)' : 'var(--ol-ink-5)',
                  }}>{OL_DATA.history.length}</span>
                  }
                </button>
              );
            })}
          </nav>

          <div style={{ flex: 1 }} />

          {/* shortcut hint */}
          <div
            style={{
              padding: '10px 10px 8px',
              borderTop: '0.5px dashed var(--ol-line)',
              marginTop: 8,
            }}>

            <div style={{ fontSize: 10.5, color: 'var(--ol-ink-4)', marginBottom: 6, letterSpacing: '0.02em' }}>录音快捷键</div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 11, color: 'var(--ol-ink-2)' }}>
              <kbd style={{
                padding: '2px 7px', fontSize: 10.5,
                background: '#fff', borderRadius: 5,
                border: '0.5px solid var(--ol-line-strong)',
                fontFamily: 'var(--ol-font-mono)', color: 'var(--ol-ink)',
                boxShadow: '0 1px 0 rgba(0,0,0,.04)',
              }}>右 Option</kbd>
              <span style={{ color: 'var(--ol-ink-4)' }}>开始 / 停止</span>
            </div>
          </div>

          {/* trial / status */}
          <div
            style={{
              marginTop: 10,
              padding: 12,
              borderRadius: 10,
              background: 'linear-gradient(160deg, rgba(37,99,235,0.08) 0%, rgba(37,99,235,0.02) 100%)',
              border: '0.5px solid rgba(37,99,235,0.15)',
            }}>

            <div style={{ fontSize: 10.5, fontWeight: 600, color: 'var(--ol-blue)', letterSpacing: '0.04em', textTransform: 'uppercase' }}>BETA</div>
            <div style={{ fontSize: 11.5, color: 'var(--ol-ink-2)', marginTop: 4, lineHeight: 1.5 }}>所有数据都只保存在本机。</div>
          </div>
        </aside>

        {/* Main content — inset white card sitting on the frosted backplate */}
        <div style={{ flex: 1, minWidth: 0, padding: '6px 8px 6px 0', display: 'flex' }}>
          <main
            style={{
              flex: 1, minWidth: 0,
              overflow: 'hidden',
              background: 'var(--ol-surface)',
              borderRadius: 12,
              border: '0.5px solid rgba(0,0,0,0.06)',
              boxShadow: '0 1px 0 rgba(255,255,255,0.8) inset, 0 8px 24px -12px rgba(15,17,22,0.10), 0 2px 6px -2px rgba(15,17,22,0.06)',
              display: 'flex',
              flexDirection: 'column',
            }}
          >
            <div style={{ padding: '24px 28px 32px', flex: 1, minHeight: 0, overflow: 'auto' }}>
              <Page />
            </div>
          </main>
        </div>
      </div>

      {/* Footer — sits on frosted outer, like Typeless */}
      <div
        style={{
          flexShrink: 0,
          height: 44,
          display: 'flex', alignItems: 'center',
          padding: '0 24px',
          gap: 4,
          fontSize: 11,
          color: 'var(--ol-ink-4)',
          position: 'relative',
          zIndex: 2,
        }}>

        <FooterIcon name="user" tip="账户" />
        <FooterIcon name="mail" tip="反馈" />
        <FooterIcon name="settings" tip="设置" active={settingsOpen} onClick={() => setSettingsOpen(true)} />
        <FooterIcon name="help" tip="帮助" />

        <div style={{ flex: 1 }} />

        <span style={{ fontFamily: 'var(--ol-font-sans)' }}>版本 v1.0.0</span>
        <a style={{ color: 'var(--ol-blue)', marginLeft: 8, textDecoration: 'none', fontWeight: 500 }}>检查更新</a>
      </div>

      {/* Settings modal — rendered inside this window */}
      {settingsOpen &&
        <SettingsModal os={os} onClose={() => setSettingsOpen(false)} />
      }
    </div>
  );
}

interface FooterIconProps {
  name: string;
  tip: string;
  active?: boolean;
  onClick?: () => void;
}

function FooterIcon({ name, tip, active, onClick }: FooterIconProps) {
  return (
    <button
      onClick={onClick}
      title={tip}
      style={{
        width: 30, height: 30, borderRadius: 7, border: 0,
        background: active ? 'rgba(0,0,0,0.06)' : 'transparent',
        color: active ? 'var(--ol-ink)' : 'var(--ol-ink-4)',
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        cursor: 'default',
      }}>
      <Icon name={name} size={15} />
    </button>
  );
}
