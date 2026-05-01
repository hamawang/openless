use std::time::Duration;

use crate::windows_ime_protocol::ImeSubmitStatus;

pub const IME_CLIENT_WAIT_TIMEOUT: Duration = Duration::from_millis(700);
pub const IME_SUBMIT_TIMEOUT: Duration = Duration::from_millis(900);
const IME_PIPE_RETRY_INTERVAL: Duration = Duration::from_millis(25);

const ERROR_FILE_NOT_FOUND: u32 = 2;
const ERROR_PATH_NOT_FOUND: u32 = 3;
const ERROR_SEM_TIMEOUT: u32 = 121;
const ERROR_PIPE_BUSY: u32 = 231;
const NMPWAIT_NOWAIT: u32 = 0x00000001;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WindowsImeIpcError {
    Unavailable(String),
    NoReadyClient,
    Timeout,
    Protocol(String),
    Io(String),
}

impl std::fmt::Display for WindowsImeIpcError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Unavailable(message) | Self::Protocol(message) | Self::Io(message) => {
                write!(f, "{message}")
            }
            Self::NoReadyClient => write!(f, "no OpenLess IME client is ready"),
            Self::Timeout => write!(f, "OpenLess IME IPC timed out"),
        }
    }
}

impl std::error::Error for WindowsImeIpcError {}

pub type WindowsImeIpcResult<T> = Result<T, WindowsImeIpcError>;

fn map_wait_named_pipe_error(error_code: Option<u32>) -> WindowsImeIpcError {
    match error_code {
        Some(ERROR_FILE_NOT_FOUND | ERROR_PATH_NOT_FOUND | ERROR_PIPE_BUSY) => {
            WindowsImeIpcError::NoReadyClient
        }
        Some(ERROR_SEM_TIMEOUT) => WindowsImeIpcError::Timeout,
        Some(code) => WindowsImeIpcError::Io(format!("WaitNamedPipeW failed with OS error {code}")),
        None => WindowsImeIpcError::Io("WaitNamedPipeW failed without OS error".to_string()),
    }
}

fn is_retryable_pipe_error(error_code: Option<u32>) -> bool {
    matches!(
        error_code,
        Some(ERROR_FILE_NOT_FOUND | ERROR_PATH_NOT_FOUND | ERROR_PIPE_BUSY | ERROR_SEM_TIMEOUT)
    )
}

#[derive(Debug)]
pub struct PendingImeSubmit {
    session_id: String,
    completed: bool,
}

impl PendingImeSubmit {
    pub fn new(session_id: String) -> Self {
        Self {
            session_id,
            completed: false,
        }
    }

    pub fn accept_result(
        &mut self,
        session_id: &str,
        status: ImeSubmitStatus,
    ) -> WindowsImeIpcResult<ImeSubmitStatus> {
        if self.completed {
            return Err(WindowsImeIpcError::Protocol(
                "submit result arrived after completion".to_string(),
            ));
        }
        if self.session_id != session_id {
            return Err(WindowsImeIpcError::Protocol(
                "submit result belongs to a different session".to_string(),
            ));
        }
        self.completed = true;
        Ok(status)
    }
}

#[derive(Debug, Clone)]
pub struct ImeSubmitRequest {
    pub session_id: String,
    pub text: String,
    pub created_at: String,
}

#[derive(Clone)]
pub struct WindowsImeIpcServer {
    inner: std::sync::Arc<parking_lot::Mutex<WindowsImeIpcState>>,
}

#[derive(Debug, Default)]
struct WindowsImeIpcState {
    ready_client_id: Option<String>,
}

impl WindowsImeIpcServer {
    pub fn new() -> Self {
        Self {
            inner: std::sync::Arc::new(parking_lot::Mutex::new(WindowsImeIpcState::default())),
        }
    }

    pub fn mark_client_ready_for_test(&self, client_id: String) {
        self.inner.lock().ready_client_id = Some(client_id);
    }

    pub fn has_ready_client(&self) -> bool {
        self.inner.lock().ready_client_id.is_some()
    }

    pub async fn submit_text(
        &self,
        request: ImeSubmitRequest,
    ) -> WindowsImeIpcResult<ImeSubmitStatus> {
        #[cfg(target_os = "windows")]
        {
            let _ = self;
            submit_text_to_platform(request).await
        }

        #[cfg(not(target_os = "windows"))]
        {
            let _ = self;
            let _ = request;
            Err(WindowsImeIpcError::Unavailable(
                "OpenLess IME IPC is only available on Windows".to_string(),
            ))
        }
    }
}

impl Default for WindowsImeIpcServer {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(target_os = "windows")]
async fn submit_text_to_platform(
    request: ImeSubmitRequest,
) -> WindowsImeIpcResult<ImeSubmitStatus> {
    windows_pipe::submit_text_over_pipe(request).await
}

#[cfg(target_os = "windows")]
mod windows_pipe {
    use std::ffi::OsStr;
    use std::os::windows::ffi::OsStrExt;
    use std::time::Instant;

    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
    use tokio::net::windows::named_pipe::{ClientOptions, NamedPipeClient};

    use super::{
        ImeSubmitRequest, PendingImeSubmit, WindowsImeIpcError, WindowsImeIpcResult,
        IME_CLIENT_WAIT_TIMEOUT, IME_PIPE_RETRY_INTERVAL, IME_SUBMIT_TIMEOUT,
    };
    use crate::windows_ime_protocol::{
        decode_message, encode_message, ImePipeMessage, OPENLESS_IME_PIPE_NAME,
        OPENLESS_IME_PROTOCOL_VERSION,
    };

    extern "system" {
        fn WaitNamedPipeW(lpNamedPipeName: *const u16, nTimeOut: u32) -> i32;
    }

    pub async fn submit_text_over_pipe(
        request: ImeSubmitRequest,
    ) -> WindowsImeIpcResult<crate::windows_ime_protocol::ImeSubmitStatus> {
        let mut pending = PendingImeSubmit::new(request.session_id.clone());
        let pipe = open_pipe_with_retry().await?;
        let (read_half, mut write_half) = tokio::io::split(pipe);
        let mut reader = BufReader::new(read_half);

        let message = ImePipeMessage::SubmitText {
            protocol_version: OPENLESS_IME_PROTOCOL_VERSION,
            session_id: request.session_id,
            text: request.text,
            created_at: request.created_at,
        };
        let line = encode_message(&message)
            .map_err(|error| WindowsImeIpcError::Protocol(error.to_string()))?;

        let response = tokio::time::timeout(IME_SUBMIT_TIMEOUT, async {
            write_half
                .write_all(line.as_bytes())
                .await
                .map_err(|error| WindowsImeIpcError::Io(error.to_string()))?;
            write_half
                .flush()
                .await
                .map_err(|error| WindowsImeIpcError::Io(error.to_string()))?;

            let mut response = String::new();
            let bytes_read = reader
                .read_line(&mut response)
                .await
                .map_err(|error| WindowsImeIpcError::Io(error.to_string()))?;

            if bytes_read == 0 {
                return Err(WindowsImeIpcError::Io(
                    "IME pipe closed before submit result".to_string(),
                ));
            }

            Ok(response)
        })
        .await
        .map_err(|_| WindowsImeIpcError::Timeout)??;

        match decode_message(response.trim_end())
            .map_err(|error| WindowsImeIpcError::Protocol(error.to_string()))?
        {
            ImePipeMessage::SubmitResult {
                protocol_version,
                session_id,
                status,
                ..
            } if protocol_version == OPENLESS_IME_PROTOCOL_VERSION => {
                pending.accept_result(&session_id, status)
            }
            ImePipeMessage::SubmitResult {
                protocol_version, ..
            } => Err(WindowsImeIpcError::Protocol(format!(
                "unsupported IME protocol version {protocol_version}"
            ))),
            _ => Err(WindowsImeIpcError::Protocol(
                "message is not a submit result".to_string(),
            )),
        }
    }

    async fn open_pipe_with_retry() -> WindowsImeIpcResult<NamedPipeClient> {
        let deadline = Instant::now() + IME_CLIENT_WAIT_TIMEOUT;

        loop {
            let retry_error = match wait_for_pipe_client() {
                Ok(()) => match ClientOptions::new().open(OPENLESS_IME_PIPE_NAME) {
                    Ok(pipe) => return Ok(pipe),
                    Err(error) => {
                        let error_code = error.raw_os_error().map(|code| code as u32);
                        if !super::is_retryable_pipe_error(error_code) {
                            return Err(WindowsImeIpcError::Io(error.to_string()));
                        }
                        super::map_wait_named_pipe_error(error_code)
                    }
                },
                Err(error) => {
                    if !is_retryable_wait_error(&error) {
                        return Err(error);
                    }
                    error
                }
            };

            if Instant::now() >= deadline {
                return Err(retry_error);
            }
            tokio::time::sleep(next_retry_delay(deadline)).await;
        }
    }

    fn wait_for_pipe_client() -> WindowsImeIpcResult<()> {
        let pipe_name = OsStr::new(OPENLESS_IME_PIPE_NAME)
            .encode_wide()
            .chain(std::iter::once(0))
            .collect::<Vec<u16>>();

        let is_ready = unsafe { WaitNamedPipeW(pipe_name.as_ptr(), super::NMPWAIT_NOWAIT) };
        if is_ready != 0 {
            return Ok(());
        }

        Err(super::map_wait_named_pipe_error(
            std::io::Error::last_os_error()
                .raw_os_error()
                .map(|code| code as u32),
        ))
    }

    fn is_retryable_wait_error(error: &WindowsImeIpcError) -> bool {
        matches!(
            error,
            WindowsImeIpcError::NoReadyClient | WindowsImeIpcError::Timeout
        )
    }

    fn next_retry_delay(deadline: Instant) -> std::time::Duration {
        deadline
            .saturating_duration_since(Instant::now())
            .min(IME_PIPE_RETRY_INTERVAL)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pending_submit_accepts_only_matching_session() {
        let mut pending = PendingImeSubmit::new("session-1".to_string());
        assert!(pending
            .accept_result("session-2", ImeSubmitStatus::Committed)
            .is_err());
        assert_eq!(
            pending.accept_result("session-1", ImeSubmitStatus::Committed),
            Ok(ImeSubmitStatus::Committed)
        );
    }

    #[test]
    fn pending_submit_rejects_second_result_after_completion() {
        let mut pending = PendingImeSubmit::new("session-1".to_string());
        assert_eq!(
            pending.accept_result("session-1", ImeSubmitStatus::Committed),
            Ok(ImeSubmitStatus::Committed)
        );
        assert!(pending
            .accept_result("session-1", ImeSubmitStatus::Committed)
            .is_err());
    }

    #[test]
    fn wait_pipe_error_mapping_treats_missing_or_busy_pipe_as_no_ready_client() {
        assert_eq!(
            map_wait_named_pipe_error(Some(2)),
            WindowsImeIpcError::NoReadyClient
        );
        assert_eq!(
            map_wait_named_pipe_error(Some(231)),
            WindowsImeIpcError::NoReadyClient
        );
    }

    #[test]
    fn wait_pipe_error_mapping_treats_wait_timeout_as_timeout() {
        assert_eq!(
            map_wait_named_pipe_error(Some(121)),
            WindowsImeIpcError::Timeout
        );
    }

    #[test]
    fn missing_busy_and_timeout_pipe_errors_are_retryable_before_deadline() {
        assert!(is_retryable_pipe_error(Some(2)));
        assert!(is_retryable_pipe_error(Some(3)));
        assert!(is_retryable_pipe_error(Some(121)));
        assert!(is_retryable_pipe_error(Some(231)));
        assert!(!is_retryable_pipe_error(Some(5)));
        assert!(!is_retryable_pipe_error(None));
    }
}
