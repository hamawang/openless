// LocalAsr.tsx — 本地 Qwen3-ASR 模型管理页。
//
// 功能：
//  - 顶部：当前激活模型 + 镜像源切换
//  - 模型列表：每行模型 = 真实尺寸 / 进度 / [下载|取消|删除|设为默认]
//  - 真实尺寸通过 fetchLocalAsrRemoteInfo 实时从 HuggingFace API 拉，**不硬编码**
//  - 监听 `local-asr-download-progress` 事件实时刷新进度
//  - Win 端引擎不可用时禁用下载按钮，提示见 issue #256

import { useEffect, useMemo, useRef, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { isTauri, setActiveAsrProvider } from '../lib/ipc';
import {
  cancelLocalAsrDownload,
  deleteLocalAsrModel,
  downloadLocalAsrModel,
  fetchLocalAsrRemoteInfo,
  getLocalAsrSettings,
  listLocalAsrModels,
  setLocalAsrActiveModel,
  setLocalAsrMirror,
  type LocalAsrDownloadProgress,
  type LocalAsrModelStatus,
  type LocalAsrSettings,
} from '../lib/localAsr';
import { Btn, Card, PageHeader, Pill } from './_atoms';

interface RemoteSize {
  totalBytes: number;
  fileCount: number;
  loading: boolean;
  error: string | null;
}

export function LocalAsr() {
  const { t } = useTranslation();
  const [settings, setSettings] = useState<LocalAsrSettings | null>(null);
  const [models, setModels] = useState<LocalAsrModelStatus[]>([]);
  const [progress, setProgress] = useState<Record<string, LocalAsrDownloadProgress>>({});
  const [remoteSizes, setRemoteSizes] = useState<Record<string, RemoteSize>>({});
  const [error, setError] = useState<string | null>(null);
  const [busyModelId, setBusyModelId] = useState<string | null>(null);
  const refreshTimer = useRef<number | null>(null);

  const refresh = async () => {
    try {
      setError(null);
      const [s, list] = await Promise.all([getLocalAsrSettings(), listLocalAsrModels()]);
      setSettings(s);
      setModels(list);
      // 拉远端真实尺寸（每个模型一次，结果留缓存）
      void Promise.all(
        list.map(async m => {
          await ensureRemoteSize(m.id, s.mirror);
        }),
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const ensureRemoteSize = async (modelId: string, mirror: string) => {
    setRemoteSizes(prev => {
      if (prev[modelId] && !prev[modelId].error) return prev;
      return { ...prev, [modelId]: { totalBytes: 0, fileCount: 0, loading: true, error: null } };
    });
    try {
      const info = await fetchLocalAsrRemoteInfo(modelId, mirror);
      setRemoteSizes(prev => ({
        ...prev,
        [modelId]: {
          totalBytes: info.totalBytes,
          fileCount: info.files.length,
          loading: false,
          error: null,
        },
      }));
    } catch (e) {
      setRemoteSizes(prev => ({
        ...prev,
        [modelId]: {
          totalBytes: 0,
          fileCount: 0,
          loading: false,
          error: e instanceof Error ? e.message : String(e),
        },
      }));
    }
  };

  useEffect(() => {
    void refresh();
    // refresh 内部已 fan-out 拉远端尺寸，不需要额外 effect
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 镜像变更后重拉一次远端尺寸（不同镜像 API 返回的 size 数值是一致的，
  // 但请求路径不同——切镜像时强制刷新一次让用户看到新源能否访通）。
  useEffect(() => {
    if (!settings) return;
    setRemoteSizes({});
    void Promise.all(
      models.map(m => ensureRemoteSize(m.id, settings.mirror)),
    );
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [settings?.mirror]);

  // 订阅下载进度事件 — 仅 Tauri 环境（浏览器 dev mock 无事件）。
  useEffect(() => {
    if (!isTauri) return;
    let unlisten: undefined | (() => void);
    let cancelled = false;
    (async () => {
      const { listen } = await import('@tauri-apps/api/event');
      const off = await listen<LocalAsrDownloadProgress>('local-asr-download-progress', e => {
        const payload = e.payload;
        setProgress(prev => ({ ...prev, [payload.modelId]: payload }));
        if (
          payload.phase === 'finished' ||
          payload.phase === 'cancelled' ||
          payload.phase === 'failed'
        ) {
          if (refreshTimer.current) window.clearTimeout(refreshTimer.current);
          refreshTimer.current = window.setTimeout(() => {
            void refresh();
          }, 200);
        }
      });
      if (cancelled) {
        off();
      } else {
        unlisten = off;
      }
    })().catch(err => console.warn('[localAsr] subscribe failed', err));
    return () => {
      cancelled = true;
      if (unlisten) unlisten();
      if (refreshTimer.current) window.clearTimeout(refreshTimer.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleSetActiveModel = async (modelId: string) => {
    setBusyModelId(modelId);
    try {
      await setLocalAsrActiveModel(modelId);
      // 顺手把 active provider 也切到本地（避免用户改了模型却忘了切 provider）
      await setActiveAsrProvider('local-qwen3');
      await refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusyModelId(null);
    }
  };

  const handleDownload = async (modelId: string) => {
    setBusyModelId(modelId);
    try {
      await downloadLocalAsrModel(modelId, settings?.mirror);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusyModelId(null);
    }
  };

  const handleCancel = async (modelId: string) => {
    try {
      await cancelLocalAsrDownload(modelId);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const handleDelete = async (modelId: string) => {
    setBusyModelId(modelId);
    try {
      await deleteLocalAsrModel(modelId);
      setProgress(prev => {
        const next = { ...prev };
        delete next[modelId];
        return next;
      });
      await refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusyModelId(null);
    }
  };

  const handleMirrorChange = async (mirror: string) => {
    try {
      await setLocalAsrMirror(mirror);
      await refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const engineAvailable = settings?.engineAvailable ?? false;

  return (
    <div style={{ padding: '20px 28px 32px', overflowY: 'auto', height: '100%' }}>
      <PageHeader
        kicker={t('localAsr.kicker')}
        title={t('localAsr.title')}
        desc={t('localAsr.desc')}
      />

      {!engineAvailable && (
        <Card style={{ marginBottom: 16, background: 'rgba(255, 235, 200, 0.4)' }}>
          <div style={{ fontSize: 13, color: 'var(--ol-ink-2)' }}>
            {t('localAsr.engineUnavailable')}
          </div>
        </Card>
      )}

      <Card style={{ marginBottom: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 16 }}>
          <div>
            <div style={{ fontSize: 12, fontWeight: 600, color: 'var(--ol-ink-4)', marginBottom: 4 }}>
              {t('localAsr.mirrorLabel')}
            </div>
            <div style={{ fontSize: 13, color: 'var(--ol-ink-3)' }}>
              {t('localAsr.mirrorDesc')}
            </div>
          </div>
          <select
            value={settings?.mirror ?? 'huggingface'}
            onChange={e => void handleMirrorChange(e.target.value)}
            style={{
              fontSize: 13,
              padding: '6px 10px',
              borderRadius: 8,
              border: '0.5px solid rgba(0,0,0,0.12)',
              background: 'var(--ol-surface)',
              color: 'var(--ol-ink)',
              minWidth: 200,
            }}>
            <option value="huggingface">{t('localAsr.mirrorHuggingface')}</option>
            <option value="hf-mirror">{t('localAsr.mirrorHfMirror')}</option>
          </select>
        </div>
      </Card>

      {error && (
        <Card style={{ marginBottom: 16, background: 'rgba(255, 220, 220, 0.5)' }}>
          <div style={{ fontSize: 13, color: '#9b2c2c' }}>{error}</div>
        </Card>
      )}

      <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        {models.map(model => (
          <ModelRow
            key={model.id}
            model={model}
            remoteSize={remoteSizes[model.id]}
            progress={progress[model.id]}
            isActive={settings?.activeModel === model.id}
            engineAvailable={engineAvailable}
            disabled={busyModelId !== null && busyModelId !== model.id}
            onDownload={() => void handleDownload(model.id)}
            onCancel={() => void handleCancel(model.id)}
            onDelete={() => void handleDelete(model.id)}
            onSetActive={() => void handleSetActiveModel(model.id)}
          />
        ))}
      </div>
    </div>
  );
}

interface ModelRowProps {
  model: LocalAsrModelStatus;
  remoteSize?: RemoteSize;
  progress?: LocalAsrDownloadProgress;
  isActive: boolean;
  engineAvailable: boolean;
  disabled: boolean;
  onDownload: () => void;
  onCancel: () => void;
  onDelete: () => void;
  onSetActive: () => void;
}

function ModelRow({
  model,
  remoteSize,
  progress,
  isActive,
  engineAvailable,
  disabled,
  onDownload,
  onCancel,
  onDelete,
  onSetActive,
}: ModelRowProps) {
  const { t } = useTranslation();
  const isDownloading = useMemo(
    () => progress?.phase === 'started' || progress?.phase === 'progress',
    [progress?.phase],
  );
  const downloadedBytes = progress?.bytesDownloaded ?? model.downloadedBytes;
  const totalBytes = progress?.bytesTotal ?? remoteSize?.totalBytes ?? 0;
  const ratio = totalBytes > 0 ? Math.min(1, downloadedBytes / totalBytes) : 0;
  const showProgress = isDownloading || progress?.phase === 'failed' || progress?.phase === 'cancelled';

  const sizeLabel = remoteSize?.loading
    ? t('localAsr.sizeLoading')
    : remoteSize?.error
    ? t('localAsr.sizeUnknown')
    : remoteSize && remoteSize.totalBytes > 0
    ? `${formatBytes(remoteSize.totalBytes)} · ${remoteSize.fileCount} ${t('localAsr.files')}`
    : t('localAsr.sizeUnknown');

  return (
    <Card>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 16 }}>
        <div style={{ minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
            <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--ol-ink)' }}>{model.id}</div>
            {isActive && <Pill tone="blue" size="sm">{t('localAsr.activeBadge')}</Pill>}
            {model.isDownloaded && <Pill tone="ok" size="sm">{t('localAsr.downloadedBadge')}</Pill>}
          </div>
          <div style={{ fontSize: 12, color: 'var(--ol-ink-3)' }}>
            {model.hfRepo} · {sizeLabel}
          </div>
          {showProgress && (
            <div style={{ marginTop: 10, maxWidth: 420 }}>
              <div
                style={{
                  height: 6,
                  borderRadius: 3,
                  background: 'rgba(0,0,0,0.06)',
                  overflow: 'hidden',
                }}>
                <div
                  style={{
                    width: `${ratio * 100}%`,
                    height: '100%',
                    background:
                      progress?.phase === 'failed'
                        ? '#d04545'
                        : progress?.phase === 'cancelled'
                        ? 'var(--ol-ink-4)'
                        : 'var(--ol-accent-blue, #2c5cff)',
                    transition: 'width 120ms linear',
                  }}
                />
              </div>
              <div style={{ fontSize: 11, color: 'var(--ol-ink-4)', marginTop: 6 }}>
                {progress?.phase === 'failed'
                  ? `${t('localAsr.failed')}: ${progress.error ?? ''}`
                  : progress?.phase === 'cancelled'
                  ? t('localAsr.cancelled')
                  : `${formatBytes(downloadedBytes)} / ${formatBytes(totalBytes)}` +
                    (progress?.file ? ` · ${progress.file}` : '')}
              </div>
            </div>
          )}
        </div>
        <div style={{ display: 'flex', gap: 8, flexShrink: 0 }}>
          {model.isDownloaded ? (
            <>
              {!isActive && (
                <Btn
                  variant="blue"
                  size="sm"
                  disabled={disabled || !engineAvailable}
                  onClick={onSetActive}>
                  {t('localAsr.setActive')}
                </Btn>
              )}
              <Btn variant="ghost" size="sm" disabled={disabled} onClick={onDelete}>
                {t('localAsr.delete')}
              </Btn>
            </>
          ) : isDownloading ? (
            <Btn variant="ghost" size="sm" onClick={onCancel}>
              {t('localAsr.cancel')}
            </Btn>
          ) : (
            <Btn
              variant="primary"
              size="sm"
              disabled={disabled || !engineAvailable}
              onClick={onDownload}>
              {t('localAsr.download')}
            </Btn>
          )}
        </div>
      </div>
    </Card>
  );
}

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(0)} MB`;
  return `${(n / 1024 / 1024 / 1024).toFixed(2)} GB`;
}
