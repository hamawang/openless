//! 本地 Qwen3-ASR 模型注册表。
//!
//! 文件清单复刻 antirez `download_model.sh` —— 不能漏，否则 `qwen_load`
//! 会失败。增加新模型时这里加一条 + 前端 i18n 加文案即可。

use std::path::PathBuf;

use anyhow::Result;
use serde::Serialize;

use crate::persistence;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ModelId {
    Small06b,
    Large17b,
}

impl ModelId {
    pub fn as_str(self) -> &'static str {
        match self {
            ModelId::Small06b => "qwen3-asr-0.6b",
            ModelId::Large17b => "qwen3-asr-1.7b",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "qwen3-asr-0.6b" => Some(ModelId::Small06b),
            "qwen3-asr-1.7b" => Some(ModelId::Large17b),
            _ => None,
        }
    }

    pub fn all() -> &'static [ModelId] {
        &[ModelId::Small06b, ModelId::Large17b]
    }

    /// HuggingFace repo id（用于拼下载 URL）。
    pub fn hf_repo(self) -> &'static str {
        match self {
            ModelId::Small06b => "Qwen/Qwen3-ASR-0.6B",
            ModelId::Large17b => "Qwen/Qwen3-ASR-1.7B",
        }
    }

    /// 该模型在 HF 仓库下需要拉的所有文件（顺序无所谓）。
    pub fn files(self) -> &'static [&'static str] {
        match self {
            ModelId::Small06b => &[
                "config.json",
                "generation_config.json",
                "model.safetensors",
                "vocab.json",
                "merges.txt",
            ],
            ModelId::Large17b => &[
                "config.json",
                "generation_config.json",
                "model.safetensors.index.json",
                "model-00001-of-00002.safetensors",
                "model-00002-of-00002.safetensors",
                "vocab.json",
                "merges.txt",
            ],
        }
    }

    /// 大致体积（字节），用于前端进度条占位 + UI 显示。
    /// 数字来自 HF 仓库实测；不是精确校验，只用来估总和。
    pub fn approx_bytes(self) -> u64 {
        match self {
            ModelId::Small06b => 1_200 * 1024 * 1024,
            ModelId::Large17b => 3_400 * 1024 * 1024,
        }
    }
}

/// 模型在本地的根目录（可能不存在）。
pub fn model_dir(id: ModelId) -> Result<PathBuf> {
    Ok(persistence::local_models_root()?.join(id.as_str()))
}

/// 检查所有必需文件是否齐全。
pub fn is_downloaded(id: ModelId) -> bool {
    let dir = match model_dir(id) {
        Ok(d) => d,
        Err(_) => return false,
    };
    id.files().iter().all(|f| dir.join(f).exists())
}

/// 已下载文件的总字节数（用于 UI 显示"X / Y MB"）。
pub fn downloaded_bytes(id: ModelId) -> u64 {
    let dir = match model_dir(id) {
        Ok(d) => d,
        Err(_) => return 0,
    };
    id.files()
        .iter()
        .filter_map(|f| std::fs::metadata(dir.join(f)).ok())
        .map(|m| m.len())
        .sum()
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelStatus {
    pub id: String,
    pub hf_repo: String,
    pub approx_bytes: u64,
    pub downloaded_bytes: u64,
    pub is_downloaded: bool,
}

pub fn list_status() -> Vec<ModelStatus> {
    ModelId::all()
        .iter()
        .map(|&id| ModelStatus {
            id: id.as_str().to_string(),
            hf_repo: id.hf_repo().to_string(),
            approx_bytes: id.approx_bytes(),
            downloaded_bytes: downloaded_bytes(id),
            is_downloaded: is_downloaded(id),
        })
        .collect()
}

/// 删除本地模型目录（用户在 UI 主动删）。
pub fn delete_model(id: ModelId) -> Result<()> {
    let dir = model_dir(id)?;
    if dir.exists() {
        std::fs::remove_dir_all(&dir)?;
    }
    Ok(())
}
