//! Qwen3-ASR 模型下载管理。
//!
//! 流程：
//!   1. GET `<mirror>/api/models/<repo>/tree/main` 拿真实文件清单 + 尺寸
//!   2. 过滤掉 .gitattributes / README 等非权重文件
//!   3. 串行下载每个文件 → `.partial` → 原子 rename
//!   4. 全部成功后写哨兵 `.openless-asr-ready` 标记完整
//!
//! 取消：每个 chunk 边界检查 `AtomicBool`；失败 / 取消保留 `.partial`，
//! 下次以 HTTP `Range` 头续传（与 antirez `download_model.sh` 行为对齐）。

use std::collections::HashMap;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use anyhow::{Context, Result};
use futures_util::StreamExt;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter};
use tokio::io::AsyncWriteExt;

use super::models::{model_dir, ModelId, READY_SENTINEL};

/// 下载源镜像。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum Mirror {
    /// 国外官方源 `huggingface.co`
    Huggingface,
    /// 国内镜像 `hf-mirror.com`（社区维护，非官方但稳定）
    HfMirror,
}

impl Default for Mirror {
    fn default() -> Self {
        Mirror::Huggingface
    }
}

impl Mirror {
    pub fn base_url(self) -> &'static str {
        match self {
            Mirror::Huggingface => "https://huggingface.co",
            Mirror::HfMirror => "https://hf-mirror.com",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s {
            "hf-mirror" => Mirror::HfMirror,
            _ => Mirror::Huggingface,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Mirror::Huggingface => "huggingface",
            Mirror::HfMirror => "hf-mirror",
        }
    }
}

/// 远端单个文件描述（来自 HF tree API）。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFile {
    pub path: String,
    pub size: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteInfo {
    pub model_id: String,
    pub mirror: String,
    pub files: Vec<RemoteFile>,
    pub total_bytes: u64,
}

#[derive(Debug, Deserialize)]
struct HfTreeEntry {
    #[serde(rename = "type")]
    entry_type: String,
    path: String,
    #[serde(default)]
    size: Option<u64>,
}

/// 拉远端文件清单（HF tree API）。供下载流程 + 前端"查看模型大小"按钮共用。
pub async fn fetch_remote_info(model_id: ModelId, mirror: Mirror) -> Result<RemoteInfo> {
    let client = reqwest::Client::builder()
        .build()
        .context("build reqwest client failed")?;
    let files = fetch_file_list(&client, model_id.hf_repo(), mirror).await?;
    let total_bytes = files.iter().map(|f| f.size).sum();
    Ok(RemoteInfo {
        model_id: model_id.as_str().into(),
        mirror: mirror.as_str().into(),
        files,
        total_bytes,
    })
}

async fn fetch_file_list(
    client: &reqwest::Client,
    repo: &str,
    mirror: Mirror,
) -> Result<Vec<RemoteFile>> {
    let url = format!("{}/api/models/{}/tree/main", mirror.base_url(), repo);
    let resp = client
        .get(&url)
        .send()
        .await
        .with_context(|| format!("HF tree API GET 失败: {url}"))?;
    if !resp.status().is_success() {
        anyhow::bail!("HF tree API HTTP {}: {url}", resp.status());
    }
    let entries: Vec<HfTreeEntry> = resp
        .json()
        .await
        .with_context(|| format!("HF tree JSON 解码失败: {url}"))?;
    let files: Vec<RemoteFile> = entries
        .into_iter()
        .filter(|e| e.entry_type == "file" && keep_file(&e.path))
        .map(|e| RemoteFile {
            path: e.path,
            size: e.size.unwrap_or(0),
        })
        .collect();
    if files.is_empty() {
        anyhow::bail!("HF tree 返回空文件列表 (repo={repo})");
    }
    Ok(files)
}

/// 是否保留下载？过滤 docs / git-attribute / 图片。
/// 白名单：模型权重 / 配置 / 词表用到的所有真实扩展名。
fn keep_file(path: &str) -> bool {
    if path.starts_with('.') {
        return false;
    }
    let lower = path.to_ascii_lowercase();
    if lower.ends_with(".md") || lower.ends_with(".png") || lower.ends_with(".jpg")
        || lower.ends_with(".jpeg") || lower.ends_with(".gif") || lower.ends_with(".svg")
    {
        return false;
    }
    let ext = lower.rsplit('.').next().unwrap_or("");
    matches!(ext, "json" | "safetensors" | "txt" | "bin" | "model" | "tiktoken")
}

/// 进度事件 payload；前端按 `model_id` 过滤。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DownloadProgress {
    pub model_id: String,
    pub file: String,
    pub file_index: usize,
    pub file_count: usize,
    pub bytes_downloaded: u64,
    pub bytes_total: u64,
    pub phase: DownloadPhase,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum DownloadPhase {
    Started,
    Progress,
    Finished,
    Cancelled,
    Failed,
}

#[derive(Default)]
pub struct DownloadManager {
    cancel_flags: Mutex<HashMap<String, Arc<AtomicBool>>>,
}

impl DownloadManager {
    pub fn new() -> Self {
        Self::default()
    }

    /// 启动一次下载；同一模型并发调只接受第一次（直到上一次结束/取消）。
    /// 立即返回；进度通过 Tauri 事件流上报。
    pub fn start(self: &Arc<Self>, app: AppHandle, model_id: ModelId, mirror: Mirror) {
        let key = model_id.as_str().to_string();
        let flag = {
            let mut flags = self.cancel_flags.lock();
            if flags.contains_key(&key) {
                log::info!("[local-asr] download already in progress: {key}");
                return;
            }
            let f = Arc::new(AtomicBool::new(false));
            flags.insert(key.clone(), Arc::clone(&f));
            f
        };

        let manager = Arc::clone(self);
        // 用 tauri::async_runtime::spawn 而不是 tokio::spawn ——
        // Tauri 同步 command 不在 tokio runtime 上下文里，调 tokio::spawn 会立刻
        // panic("there is no reactor running, must be called from the context of a Tokio 1.x runtime")。
        // tauri::async_runtime 走 Tauri 持有的 runtime handle，不依赖调用方上下文。
        tauri::async_runtime::spawn(async move {
            let result = run_download(&app, model_id, mirror, &flag).await;
            manager.cancel_flags.lock().remove(&key);
            match result {
                Ok(()) => log::info!("[local-asr] download finished: {key}"),
                Err(e) => log::error!("[local-asr] download failed: {key}: {e:#}"),
            }
        });
    }

    pub fn cancel(&self, model_id: ModelId) {
        if let Some(flag) = self.cancel_flags.lock().get(model_id.as_str()) {
            flag.store(true, Ordering::SeqCst);
        }
    }

    pub fn is_active(&self, model_id: ModelId) -> bool {
        self.cancel_flags.lock().contains_key(model_id.as_str())
    }
}

async fn run_download(
    app: &AppHandle,
    model_id: ModelId,
    mirror: Mirror,
    cancel: &AtomicBool,
) -> Result<()> {
    let dir = model_dir(model_id)?;
    std::fs::create_dir_all(&dir)
        .with_context(|| format!("create model dir failed: {}", dir.display()))?;

    // 用 native-tls (macOS = SecureTransport) 而非 rustls：HuggingFace 的 LFS CDN
    // 经常不发 TLS close_notify 就关 TCP，rustls 0.22+ 把这当致命 unexpected_eof。
    // SecureTransport 对 unclean close 容错。(Volcengine WebSocket 继续走 rustls。)
    //
    // 关键：必须发 User-Agent。HF 把 no-UA 流量算异常，可能限速 / 强制断流。
    // pool_idle_timeout 短一点，避免复用已被 CDN 关掉的连接造成 EOF。
    let client = reqwest::Client::builder()
        .use_native_tls()
        .user_agent(concat!("openless/", env!("CARGO_PKG_VERSION")))
        .connect_timeout(std::time::Duration::from_secs(30))
        .pool_idle_timeout(std::time::Duration::from_secs(15))
        .build()
        .context("build reqwest client failed")?;

    // 第一步：拉真实文件清单 + 尺寸（不再硬编码）。
    let info = match fetch_remote_info(model_id, mirror).await {
        Ok(i) => i,
        Err(e) => {
            emit(
                app,
                DownloadProgress {
                    model_id: model_id.as_str().into(),
                    file: String::new(),
                    file_index: 0,
                    file_count: 0,
                    bytes_downloaded: 0,
                    bytes_total: 0,
                    phase: DownloadPhase::Failed,
                    error: Some(format!("拉文件清单失败: {e:#}")),
                },
            );
            return Err(e);
        }
    };
    let total_bytes = info.total_bytes;
    let file_count = info.files.len();

    emit(
        app,
        DownloadProgress {
            model_id: model_id.as_str().into(),
            file: String::new(),
            file_index: 0,
            file_count,
            bytes_downloaded: super::models::downloaded_bytes(model_id),
            bytes_total: total_bytes,
            phase: DownloadPhase::Started,
            error: None,
        },
    );

    let mut bytes_done_before_current: u64 = 0;
    for (idx, file) in info.files.iter().enumerate() {
        if cancel.load(Ordering::SeqCst) {
            emit_cancelled(app, model_id, &file.path, idx, file_count, total_bytes);
            return Ok(());
        }

        let dest = dir.join(&file.path);
        if let Some(parent) = dest.parent() {
            std::fs::create_dir_all(parent)
                .with_context(|| format!("create dir failed: {}", parent.display()))?;
        }
        if dest.exists() {
            bytes_done_before_current += file.size;
            continue;
        }
        let url = format!(
            "{}/{}/resolve/main/{}",
            mirror.base_url(),
            model_id.hf_repo(),
            file.path
        );
        // download_one 内部用 Range 把文件切成 32MB 分块，每块独立 retry。
        // 这样 CDN 中途断流只丢一个 chunk，不丢整个 1.7GB 文件。
        let result = download_one(&client, &url, &dest, file.size, cancel, |file_bytes| {
            emit(
                app,
                DownloadProgress {
                    model_id: model_id.as_str().into(),
                    file: file.path.clone(),
                    file_index: idx,
                    file_count,
                    bytes_downloaded: bytes_done_before_current + file_bytes,
                    bytes_total: total_bytes,
                    phase: DownloadPhase::Progress,
                    error: None,
                },
            );
        })
        .await;
        match result {
            Ok(()) => {
                bytes_done_before_current += file.size;
            }
            Err(e) => {
                if cancel.load(Ordering::SeqCst) {
                    emit_cancelled(app, model_id, &file.path, idx, file_count, total_bytes);
                    return Ok(());
                }
                emit(
                    app,
                    DownloadProgress {
                        model_id: model_id.as_str().into(),
                        file: file.path.clone(),
                        file_index: idx,
                        file_count,
                        bytes_downloaded: super::models::downloaded_bytes(model_id),
                        bytes_total: total_bytes,
                        phase: DownloadPhase::Failed,
                        error: Some(format!("{e:#}")),
                    },
                );
                return Err(e);
            }
        }
    }

    // 全部成功 → 写哨兵 → is_downloaded 返回 true。
    let sentinel = dir.join(READY_SENTINEL);
    std::fs::write(&sentinel, b"")
        .with_context(|| format!("write sentinel failed: {}", sentinel.display()))?;

    emit(
        app,
        DownloadProgress {
            model_id: model_id.as_str().into(),
            file: String::new(),
            file_index: file_count,
            file_count,
            bytes_downloaded: super::models::downloaded_bytes(model_id),
            bytes_total: total_bytes,
            phase: DownloadPhase::Finished,
            error: None,
        },
    );
    Ok(())
}

/// 下载单个文件到 `dest` —— **HTTP Range 分块**模式。
///
/// 关键：
/// - 分块大小 32 MB；HF CDN 对几秒内完成的小请求容错好，对几分钟的长连接经常踢
/// - 每块 4 次 retry，指数退避 1s/4s/16s，每次都从 .partial 真实长度续传
/// - 如果服务端忽略 Range 返回 200（HF 偶尔，非常少见）→ 截断 .partial 重头来
/// - 失败 / 取消时保留 .partial，下次续传不重头
async fn download_one(
    client: &reqwest::Client,
    url: &str,
    dest: &Path,
    total_size: u64,
    cancel: &AtomicBool,
    mut on_progress: impl FnMut(u64),
) -> Result<()> {
    const CHUNK_SIZE: u64 = 32 * 1024 * 1024;
    const PER_CHUNK_ATTEMPTS: u32 = 4;

    let partial = dest.with_extension("partial");
    if let Some(parent) = partial.parent() {
        std::fs::create_dir_all(parent).ok();
    }

    // 已有 partial 比远端文件还大 = 上次下了被换掉的旧版本，从头来
    let initial = std::fs::metadata(&partial).map(|m| m.len()).unwrap_or(0);
    if initial > total_size && total_size > 0 {
        std::fs::remove_file(&partial).ok();
    }

    loop {
        if cancel.load(Ordering::SeqCst) {
            anyhow::bail!("cancelled");
        }

        let downloaded = std::fs::metadata(&partial).map(|m| m.len()).unwrap_or(0);
        if downloaded >= total_size && total_size > 0 {
            break;
        }

        let chunk_end = if total_size > 0 {
            (downloaded + CHUNK_SIZE - 1).min(total_size - 1)
        } else {
            // 极少数情况：HF 没给 size。退化为单连接整文件下（旧行为）。
            u64::MAX
        };

        let chunk_result = download_chunk(
            client,
            url,
            &partial,
            downloaded,
            chunk_end,
            total_size,
            cancel,
            PER_CHUNK_ATTEMPTS,
            &mut on_progress,
        )
        .await;
        if let Err(e) = chunk_result {
            // 检查是否还是有进展（哪怕这块没下完）
            let new_downloaded = std::fs::metadata(&partial).map(|m| m.len()).unwrap_or(0);
            if new_downloaded > downloaded {
                log::warn!(
                    "[local-asr] chunk failed but advanced {}→{}; loop will retry remainder",
                    downloaded,
                    new_downloaded
                );
                continue;
            }
            return Err(e);
        }
    }

    tokio::fs::rename(&partial, dest)
        .await
        .with_context(|| format!("rename partial → final failed: {}", dest.display()))?;
    Ok(())
}

/// 单个 chunk 的 HTTP Range 请求 + retry。
async fn download_chunk(
    client: &reqwest::Client,
    url: &str,
    partial: &Path,
    range_start: u64,
    range_end: u64,
    total_size: u64,
    cancel: &AtomicBool,
    max_attempts: u32,
    on_progress: &mut impl FnMut(u64),
) -> Result<()> {
    let mut last_err: Option<anyhow::Error> = None;
    for attempt in 1..=max_attempts {
        if cancel.load(Ordering::SeqCst) {
            anyhow::bail!("cancelled");
        }
        // 每次重新计算 .partial 真实长度，万一上一次请求写了一些再失败的，我们顺势接续
        let cur = std::fs::metadata(partial).map(|m| m.len()).unwrap_or(0);
        let try_start = cur.max(range_start);
        if try_start > range_end {
            return Ok(());
        }

        match try_download_range(client, url, partial, try_start, range_end, total_size, cancel, on_progress).await {
            Ok(()) => return Ok(()),
            Err(e) => {
                let msg = format!("{e:#}");
                last_err = Some(e);
                if attempt < max_attempts {
                    let backoff = std::time::Duration::from_secs(1u64 << (2 * (attempt - 1)));
                    log::warn!(
                        "[local-asr] chunk [{try_start}-{range_end}] attempt {attempt}/{max_attempts} failed: {msg}; sleep {:?}",
                        backoff
                    );
                    tokio::time::sleep(backoff).await;
                }
            }
        }
    }
    Err(last_err.unwrap_or_else(|| anyhow::anyhow!("download_chunk failed after {max_attempts} attempts")))
}

async fn try_download_range(
    client: &reqwest::Client,
    url: &str,
    partial: &Path,
    range_start: u64,
    range_end: u64,
    total_size: u64,
    cancel: &AtomicBool,
    on_progress: &mut impl FnMut(u64),
) -> Result<()> {
    let mut req = client.get(url);
    if total_size > 0 {
        req = req.header("Range", format!("bytes={range_start}-{range_end}"));
    } else if range_start > 0 {
        req = req.header("Range", format!("bytes={range_start}-"));
    }
    let resp = req
        .send()
        .await
        .with_context(|| format!("HTTP GET {url} failed"))?;

    let status = resp.status();
    let is_partial = status.as_u16() == 206;
    let is_full_ok = status.as_u16() == 200;
    if !is_partial && !is_full_ok {
        anyhow::bail!("HTTP {status} for {url}");
    }

    // 服务端忽略了 Range 返回 200 + 全文件：会污染 .partial，需要先截断从头来。
    if is_full_ok && range_start > 0 {
        log::warn!(
            "[local-asr] server ignored Range (got 200 not 206) for {url}; truncating partial and restarting"
        );
        let _ = std::fs::remove_file(partial);
    }

    let effective_start = if is_full_ok { 0 } else { range_start };

    let mut file = tokio::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(partial)
        .await
        .with_context(|| format!("open partial failed: {}", partial.display()))?;

    let mut stream = resp.bytes_stream();
    let mut written: u64 = 0;
    while let Some(chunk) = stream.next().await {
        if cancel.load(Ordering::SeqCst) {
            file.flush().await.ok();
            anyhow::bail!("cancelled");
        }
        let bytes = chunk.context("read stream chunk failed")?;
        file.write_all(&bytes).await.context("write chunk failed")?;
        written += bytes.len() as u64;
        on_progress(effective_start + written);
    }
    file.flush().await.ok();
    Ok(())
}

fn emit(app: &AppHandle, payload: DownloadProgress) {
    if let Err(e) = app.emit("local-asr-download-progress", payload) {
        log::warn!("[local-asr] emit progress failed: {e}");
    }
}

fn emit_cancelled(
    app: &AppHandle,
    model_id: ModelId,
    fname: &str,
    idx: usize,
    file_count: usize,
    total: u64,
) {
    emit(
        app,
        DownloadProgress {
            model_id: model_id.as_str().into(),
            file: fname.into(),
            file_index: idx,
            file_count,
            bytes_downloaded: super::models::downloaded_bytes(model_id),
            bytes_total: total,
            phase: DownloadPhase::Cancelled,
            error: None,
        },
    );
}
