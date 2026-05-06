#[cfg(target_os = "windows")]
#[allow(dead_code)]
mod imp {
    use std::path::Path;
    use std::sync::Arc;

    use anyhow::{Context, Result};
    use foundry_local_sdk::{FoundryLocalConfig, FoundryLocalManager, Model};
    use parking_lot::Mutex;
    use tokio::sync::Mutex as AsyncMutex;

    use crate::asr::local::foundry::{FoundryRuntimeStatus, PROVIDER_ID};

    #[derive(Clone)]
    struct LoadedModel {
        alias: String,
        model_id: String,
        model: Arc<Model>,
    }

    #[derive(Default)]
    struct RuntimeState {
        manager: Option<&'static FoundryLocalManager>,
        loaded: Option<LoadedModel>,
    }

    pub struct FoundryLocalRuntime {
        lifecycle: AsyncMutex<()>,
        state: Mutex<RuntimeState>,
    }

    impl Default for FoundryLocalRuntime {
        fn default() -> Self {
            Self::new()
        }
    }

    impl FoundryLocalRuntime {
        pub fn new() -> Self {
            Self {
                lifecycle: AsyncMutex::new(()),
                state: Mutex::new(RuntimeState::default()),
            }
        }

        pub fn status_snapshot(&self, active_model: &str) -> FoundryRuntimeStatus {
            let state = self.state.lock();
            FoundryRuntimeStatus {
                provider_id: PROVIDER_ID.into(),
                available: true,
                active_model: active_model.to_string(),
                loaded_model_id: state.loaded.as_ref().map(|loaded| loaded.model_id.clone()),
                endpoint: None,
                error: None,
            }
        }

        pub async fn ensure_loaded(&self, alias: &str) -> Result<String> {
            let _lifecycle = self.lifecycle.lock().await;
            Ok(self.ensure_loaded_locked(alias).await?.model_id)
        }

        pub async fn transcribe_audio_file(
            &self,
            alias: &str,
            audio_path: &Path,
        ) -> Result<String> {
            let _lifecycle = self.lifecycle.lock().await;
            let model = self.ensure_loaded_locked(alias).await?.model;
            let result = model
                .create_audio_client()
                .transcribe(audio_path)
                .await
                .with_context(|| format!("transcribe audio with Foundry model {alias}"))?;
            Ok(result.text)
        }

        pub async fn release_now(&self) -> Result<()> {
            let _lifecycle = self.lifecycle.lock().await;
            self.release_now_locked().await
        }

        async fn ensure_loaded_locked(&self, alias: &str) -> Result<LoadedModel> {
            if let Some(loaded) = self.cached_loaded_model(alias) {
                return Ok(loaded);
            }

            if let Some(previous) = self.loaded_for_different_alias(alias) {
                Self::unload_model(&previous).await?;
                self.clear_loaded_if_model_id(&previous.model_id);
            }

            let manager = self.manager()?;
            manager
                .download_and_register_eps_with_progress(None, |_ep_name: &str, _percent: f64| {})
                .await
                .context("download/register Foundry execution providers")?;

            let model = manager
                .catalog()
                .get_model(alias)
                .await
                .with_context(|| format!("get Foundry model {alias}"))?;

            if !model
                .is_cached()
                .await
                .context("check Foundry model cache")?
            {
                model
                    .download(Some(|_progress: f64| {}))
                    .await
                    .with_context(|| format!("download Foundry model {alias}"))?;
            }

            model
                .load()
                .await
                .with_context(|| format!("load Foundry model {alias}"))?;

            let loaded = LoadedModel {
                alias: alias.to_string(),
                model_id: model.id().to_string(),
                model,
            };
            *self.state.lock() = RuntimeState {
                manager: Some(manager),
                loaded: Some(loaded.clone()),
            };
            Ok(loaded)
        }

        async fn release_now_locked(&self) -> Result<()> {
            if let Some(loaded) = self.loaded_model_snapshot() {
                Self::unload_model(&loaded).await?;
                self.clear_loaded_if_model_id(&loaded.model_id);
            }
            Ok(())
        }

        fn cached_loaded_model(&self, alias: &str) -> Option<LoadedModel> {
            self.state
                .lock()
                .loaded
                .as_ref()
                .filter(|loaded| loaded.alias == alias)
                .cloned()
        }

        fn manager(&self) -> Result<&'static FoundryLocalManager> {
            if let Some(manager) = self.state.lock().manager {
                return Ok(manager);
            }

            let manager =
                FoundryLocalManager::create(FoundryLocalConfig::new("foundry_local_samples"))
                    .context("initialize Foundry Local manager")?;
            self.state.lock().manager = Some(manager);
            Ok(manager)
        }

        fn loaded_model_snapshot(&self) -> Option<LoadedModel> {
            self.state.lock().loaded.clone()
        }

        fn loaded_for_different_alias(&self, alias: &str) -> Option<LoadedModel> {
            self.state
                .lock()
                .loaded
                .as_ref()
                .filter(|loaded| loaded.alias != alias)
                .cloned()
        }

        fn clear_loaded_if_model_id(&self, model_id: &str) {
            let mut state = self.state.lock();
            if state
                .loaded
                .as_ref()
                .is_some_and(|loaded| loaded.model_id == model_id)
            {
                state.loaded.take();
            }
        }

        async fn unload_model(loaded: &LoadedModel) -> Result<()> {
            loaded
                .model
                .unload()
                .await
                .with_context(|| format!("unload Foundry model {}", loaded.model_id))?;
            Ok(())
        }
    }

    #[cfg(test)]
    mod lifecycle_tests {
        use super::FoundryLocalRuntime;

        #[test]
        fn runtime_has_async_lifecycle_gate() {
            let runtime = FoundryLocalRuntime::new();

            assert!(runtime.lifecycle.try_lock().is_ok());
        }
    }
}

#[cfg(target_os = "windows")]
pub use imp::FoundryLocalRuntime;

#[cfg(not(target_os = "windows"))]
pub struct FoundryLocalRuntime;

#[cfg(not(target_os = "windows"))]
impl Default for FoundryLocalRuntime {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(not(target_os = "windows"))]
impl FoundryLocalRuntime {
    pub fn new() -> Self {
        Self
    }

    pub fn status_snapshot(&self, active_model: &str) -> super::foundry::FoundryRuntimeStatus {
        super::foundry::FoundryRuntimeStatus::unavailable(
            active_model.to_string(),
            "Foundry Local Whisper is only available on Windows",
        )
    }

    pub async fn ensure_loaded(&self, alias: &str) -> anyhow::Result<String> {
        anyhow::bail!("Foundry Local Whisper is only available on Windows: {alias}");
    }

    pub async fn transcribe_audio_file(
        &self,
        alias: &str,
        _audio_path: &std::path::Path,
    ) -> anyhow::Result<String> {
        anyhow::bail!("Foundry Local Whisper is only available on Windows: {alias}");
    }

    pub async fn release_now(&self) -> anyhow::Result<()> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::FoundryLocalRuntime;

    #[test]
    fn new_runtime_reports_native_audio_status_shape() {
        let runtime = FoundryLocalRuntime::new();
        let status = runtime.status_snapshot("whisper-small");

        assert_eq!(status.provider_id, crate::asr::local::foundry::PROVIDER_ID);
        assert_eq!(status.active_model, "whisper-small");
        assert_eq!(status.loaded_model_id, None);
        assert_eq!(status.endpoint, None);
    }

    #[tokio::test]
    async fn new_runtime_release_now_has_real_async_unload_contract() {
        let runtime = FoundryLocalRuntime::new();

        runtime.release_now().await.unwrap();

        let status = runtime.status_snapshot("whisper-small");
        assert_eq!(status.loaded_model_id, None);
    }
}
