//! Qwen3-ASR 模型下载管理。
//!
//! - 文件清单来自 `models.rs`，串行下载（一个模型 ≤7 个文件，并发收益小）
//! - 写入 `.partial` 后 `rename` 原子落盘；HF 不直接给文件级 sha256，所以
//!   这里**不**做强校验（与 antirez `download_model.sh` 一致）
//! - 取消通过 `AtomicBool` 在每个 chunk 边界检查，drop 时自然终止 reqwest stream
//! - 进度通过 Tauri 事件 `local-asr-download-progress` 上报前端

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

use super::models::{model_dir, ModelId};

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
        tokio::spawn(async move {
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

    let files = model_id.files();
    let file_count = files.len();
    let approx_total = model_id.approx_bytes();

    emit(
        app,
        DownloadProgress {
            model_id: model_id.as_str().into(),
            file: String::new(),
            file_index: 0,
            file_count,
            bytes_downloaded: super::models::downloaded_bytes(model_id),
            bytes_total: approx_total,
            phase: DownloadPhase::Started,
            error: None,
        },
    );

    let client = reqwest::Client::builder()
        .build()
        .context("build reqwest client failed")?;

    for (idx, fname) in files.iter().enumerate() {
        if cancel.load(Ordering::SeqCst) {
            emit_cancelled(app, model_id, fname, idx, file_count);
            return Ok(());
        }

        let dest = dir.join(fname);
        if dest.exists() {
            continue;
        }
        let url = format!(
            "{}/{}/resolve/main/{}",
            mirror.base_url(),
            model_id.hf_repo(),
            fname
        );
        if let Err(e) = download_one(&client, &url, &dest, cancel, |bytes| {
            emit(
                app,
                DownloadProgress {
                    model_id: model_id.as_str().into(),
                    file: (*fname).into(),
                    file_index: idx,
                    file_count,
                    bytes_downloaded: super::models::downloaded_bytes(model_id) + bytes,
                    bytes_total: approx_total,
                    phase: DownloadPhase::Progress,
                    error: None,
                },
            );
        })
        .await
        {
            if cancel.load(Ordering::SeqCst) {
                emit_cancelled(app, model_id, fname, idx, file_count);
                return Ok(());
            }
            emit(
                app,
                DownloadProgress {
                    model_id: model_id.as_str().into(),
                    file: (*fname).into(),
                    file_index: idx,
                    file_count,
                    bytes_downloaded: super::models::downloaded_bytes(model_id),
                    bytes_total: approx_total,
                    phase: DownloadPhase::Failed,
                    error: Some(format!("{e:#}")),
                },
            );
            return Err(e);
        }
    }

    emit(
        app,
        DownloadProgress {
            model_id: model_id.as_str().into(),
            file: String::new(),
            file_index: file_count,
            file_count,
            bytes_downloaded: super::models::downloaded_bytes(model_id),
            bytes_total: approx_total,
            phase: DownloadPhase::Finished,
            error: None,
        },
    );
    Ok(())
}

/// 下载单个文件到 `dest`，失败/取消时**保留** `.partial` 用于续传（HTTP Range 头）。
async fn download_one(
    client: &reqwest::Client,
    url: &str,
    dest: &Path,
    cancel: &AtomicBool,
    mut on_chunk: impl FnMut(u64),
) -> Result<()> {
    let partial = dest.with_extension("partial");
    let resume_from = std::fs::metadata(&partial).map(|m| m.len()).unwrap_or(0);

    let mut req = client.get(url);
    if resume_from > 0 {
        req = req.header("Range", format!("bytes={resume_from}-"));
    }
    let resp = req
        .send()
        .await
        .with_context(|| format!("HTTP GET {url} failed"))?;
    let status = resp.status();
    if !status.is_success() && status.as_u16() != 206 {
        anyhow::bail!("HTTP {status} for {url}");
    }

    let mut file = tokio::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&partial)
        .await
        .with_context(|| format!("open partial failed: {}", partial.display()))?;

    let mut stream = resp.bytes_stream();
    let mut total_written = resume_from;
    while let Some(chunk) = stream.next().await {
        if cancel.load(Ordering::SeqCst) {
            anyhow::bail!("cancelled");
        }
        let bytes = chunk.context("read stream chunk failed")?;
        file.write_all(&bytes).await.context("write chunk failed")?;
        total_written += bytes.len() as u64;
        on_chunk(total_written);
    }
    file.flush().await.ok();
    drop(file);

    tokio::fs::rename(&partial, dest)
        .await
        .with_context(|| format!("rename partial → final failed: {}", dest.display()))?;
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
) {
    emit(
        app,
        DownloadProgress {
            model_id: model_id.as_str().into(),
            file: fname.into(),
            file_index: idx,
            file_count,
            bytes_downloaded: super::models::downloaded_bytes(model_id),
            bytes_total: model_id.approx_bytes(),
            phase: DownloadPhase::Cancelled,
            error: None,
        },
    );
}
