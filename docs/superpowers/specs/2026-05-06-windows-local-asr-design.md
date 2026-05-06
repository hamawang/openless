# Windows 本地 ASR 设计

## 背景

OpenLess 的产品契约是：全局热键启动听写，胶囊显示录音状态，ASR 产出 transcript，现有 LLM provider 做润色、翻译或语义处理，再通过当前平台插入链路写回光标位置并保存历史。

Windows 新用户目前仍需要配置外部 ASR provider，才能完成真实听写。目标是在 Windows 上提供一个不依赖外部 ASR API Key 的本地识别方案，同时不调用 `Win+H`，不显示 Windows Voice Typing 系统面板，不绕开现有 polish、insert 和 history 流水线。

已确认的边界：

- Windows `Win+H` / Voice Typing 是用户级系统功能，没有适合 OpenLess 嵌入并拿回 transcript 的公开 API。
- `SendInput` 模拟 `Win+H` 只会打开系统面板，OpenLess 拿不到 transcript，也无法 polish 或写 history。
- `Windows.Media.SpeechRecognition` 对普通 desktop app 的支持和授权路径不适合作为主线。
- SAPI COM 可做 desktop dictation，但质量和现代体验不足以满足高品质目标。

## 官方资料核对

核对时间：2026-05-06。

Microsoft Learn 当前资料显示：

- Foundry Local 是本地 AI runtime，支持 Windows、macOS Apple silicon 和 Linux，提供 C#、JavaScript、Rust、Python SDK；本地推理数据不离开设备，首次模型和执行 provider 下载仍需要网络。
- Foundry Local catalog 覆盖 chat completion 和 audio transcription；音频转写示例明确使用 Whisper 模型。
- Rust SDK 在 Windows 上使用 `foundry-local-sdk --features winml`，Windows 包集成 Windows ML runtime。
- Rust native audio API 当前文档示例是：下载并 load Whisper 模型后 `model.create_audio_client()`，再调用 `audio_client.transcribe(file_path).await`。
- Foundry Local 也能启动 OpenAI-compatible local REST service；REST endpoint `POST /v1/audio/transcriptions` 接收 multipart `file`、`model`，可选 `language`、`temperature`、`response_format`，返回 `text`。
- REST service 的端口是动态分配，文档要求通过 SDK 暴露的 endpoint / urls 获取，不要硬编码。
- CLI 是开发和管理辅助工具，不是应用集成主线；生产应用应使用 SDK 嵌入 runtime。
- Foundry Local 仍是 preview，API、安装和分发方式可能变动。

主要来源：

- https://learn.microsoft.com/en-us/azure/foundry-local/what-is-foundry-local
- https://learn.microsoft.com/en-us/azure/foundry-local/get-started
- https://learn.microsoft.com/en-us/azure/foundry-local/how-to/how-to-transcribe-audio
- https://learn.microsoft.com/en-us/azure/foundry-local/reference/reference-rest
- https://learn.microsoft.com/en-us/azure/foundry-local/reference/reference-sdk-current
- https://learn.microsoft.com/en-us/azure/foundry-local/how-to/how-to-use-foundry-local-cli
- https://learn.microsoft.com/en-us/azure/foundry-local/concepts/foundry-local-architecture

## 目标

- Windows 新用户无需 Volcengine、Whisper HTTP、DashScope 等外部 ASR API Key，即可完成听写。
- 不调用 `Win+H`，用户完全看不到 Windows Voice Typing 弹窗。
- 现有交互不变：热键、OpenLess capsule、录音状态、转写、LLM polish / 翻译、插入、历史保存都走当前主流水线。
- LLM polish 仍沿用用户配置的 OpenAI-compatible LLM provider；LLM 未配置或失败时插入原始 transcript。
- 本地 ASR 缺 runtime / 模型时给出可操作引导，而不是静默失败。
- 下载完成后可离线识别；首次模型 / execution provider 下载可以联网。

## 非目标

- 不把 Windows Voice Typing、SAPI 或系统听写面板嵌入 OpenLess。
- 不在本阶段把 LLM polish 也改成本地模型；本设计只解决 ASR。
- 不把大型模型直接打进默认 Windows 安装包，除非后续逐项确认模型 license、再分发条款、安装包体积和 updater 影响。
- 不重写 Windows TSF IME 插入链路。
- 不保证所有隔离目标窗口都能 TSF 上屏；现有 TSF / Unicode / clipboard fallback 策略继续负责插入可用性。

## 现有系统切入点

主听写状态机集中在 `openless-all/app/src-tauri/src/coordinator.rs`：

- `ActiveAsr` 当前有 `Volcengine`、`Whisper`，以及 macOS-only `Local`。
- `begin_session` 从 `CredentialsVault::get_active_asr()` 读取 active provider，再分流到 local Qwen3、OpenAI-compatible Whisper 或 Volcengine。
- `end_session` 统一取得 `RawTranscript` 后，继续走 `polish_or_passthrough` / `translate_or_passthrough`、Windows TSF-first 插入和 history append。
- `ensure_asr_credentials` 是录音前的 provider gate；本地 ASR 需要在这里改成“无需云凭据，但需要 runtime / model ready”。
- `is_whisper_compatible_provider` 只覆盖云端 OpenAI-compatible `/audio/transcriptions` provider；Foundry Local 不应塞进这里，因为它需要 runtime / model lifecycle。

现有本地 ASR 模块在 `openless-all/app/src-tauri/src/asr/local/`：

- provider id 是 `local-qwen3`，模型枚举是 `qwen3-asr-0.6b` / `qwen3-asr-1.7b`。
- `LocalAsrCache` 目前只在 macOS 持有 `QwenAsrEngine`。
- 下载页和 IPC 命令已覆盖 model status、下载、删除、test、preload、release，但 UI 文案和目录语义都强绑定 Qwen3-ASR。
- Windows 端 `engine_available` 当前为 false，设置页提示“仅 macOS 已支持”。

Windows 插入链路已经满足本需求：

- 会话开始时 `prepare_session()` 捕获当前输入法 profile 并临时激活 OpenLess TSF。
- 会话结束时 `insert_with_windows_ime_first()` 通过 named pipe 把最终文本提交给 TSF DLL。
- TSF DLL 在目标应用内调用 `ITfInsertAtSelection::InsertTextAtSelection`。
- TSF 失败后按用户偏好走 Unicode `SendInput` 或 clipboard fallback。

## 推荐方案

新增 Windows-only provider：`foundry-local-whisper`。

实现上分两层：

1. `FoundryLocalWhisperAsr`：形状对齐 `WhisperBatchASR` 和 `LocalQwenAsr`，实现 `AudioConsumer`，录音阶段 buffer 16 kHz mono i16 PCM，stop 后编码 WAV 并调用 Foundry Local。
2. `FoundryLocalRuntime`：封装 Foundry Local SDK 的初始化、catalog 查询、execution provider 下载、模型下载、模型加载、endpoint 获取和卸载 / keep-loaded 管理。

MVP 调用路径建议先用 Foundry Local SDK 启动 local REST service，再调用 `/v1/audio/transcriptions`。原因：

- OpenLess 已经有成熟的 multipart WAV 转写路径。
- REST API 文档明确支持 `language` 参数，便于后续中文 / 中英混输策略调优。
- SDK 仍负责动态端口、模型下载和加载，避免硬编码本地服务地址。
- 后续如果 Rust native audio client 提供足够参数和稳定 API，可以把 REST 调用替换为纯 native audio client。

## Provider 与模型命名

新增 id：

- `foundry-local-whisper`：Windows 主线本地 ASR。

模型别名：

- 默认：`whisper-small`。
- 低配选项：`whisper-base`。
- 调试选项：`whisper-tiny`。

默认不强制 `language=zh`。中英混输时让 Whisper 自动检测更稳，避免英文产品名、代码词或中英夹杂被错误归入单一中文模式。后续可在高级设置里增加“优先中文识别”，仅用户明确选择时传 `language=zh`。

不要把 `foundry-local-whisper` 混入现有 `local-qwen3` provider。两者模型来源、runtime、平台支持和下载语义不同，应共享“本地 ASR 管理”页面的外壳，但后端 provider 和模型 registry 要分开。

## 会话时序

1. 用户按当前 OpenLess 全局热键。
2. `Coordinator` 进入 `Starting`，Windows 侧准备 TSF IME session。
3. `ensure_asr_credentials` 识别 active provider 是 `foundry-local-whisper`：
   - runtime 可用且模型已缓存：继续；
   - 模型未缓存：返回可操作错误，胶囊显示“请先下载本地语音模型”，不开始录音；
   - runtime 初始化失败：显示“本地语音运行时不可用”，引导设置页。
4. 创建 `FoundryLocalWhisperAsr`，把它作为 `AudioConsumer` 传给 `Recorder::start`。
5. 录音期间 recorder 继续向 consumer 推 PCM，capsule 继续显示电平。
6. 用户再次按热键或松开热键结束录音。
7. `end_session` 停 recorder，调用 `FoundryLocalWhisperAsr::transcribe()`：
   - PCM buffer 编码成临时 WAV；
   - 确保模型 loaded；
   - 通过 SDK endpoint 调 `/v1/audio/transcriptions`；
   - 解析 `{ text }` 为 `RawTranscript`。
8. 后续完全复用现有逻辑：空 transcript guard、polish / translate、Chinese script preference、Windows TSF-first insert、history append、capsule Done。

## 首次使用 UX

Windows 新用户默认 active ASR 使用 `foundry-local-whisper`，但只在“没有现有 preferences / credentials active ASR”的新安装路径生效，不覆盖老用户。

设置页增加或改造“本地语音识别”区：

- 显示 runtime 状态：可用、初始化中、不可用。
- 显示 execution provider 状态：已注册、需要下载、下载中、失败。
- 显示模型列表：`whisper-small`、`whisper-base`、`whisper-tiny`，尺寸和 license 从 Foundry catalog / REST metadata 获取。
- 提供一键下载 / 取消 / 删除 / 设为默认 / 加载并测试。
- 下载完成后后台 preload，减少第一次热键录音结束后的等待。

首次按热键但模型缺失时：

- 不调用 Win+H。
- 不弹系统 Voice Typing。
- 不开始录音，避免用户说完才发现没有模型。
- capsule 显示短错误，主窗口跳到本地语音识别页或给出“下载模型”入口。

## 质量与性能评估

中文 / 中英混输：

- Whisper 系列对普通话和英文都可用，但 `tiny/base/small` 本地模型质量通常低于云端大模型 ASR 或 Whisper large。
- `whisper-small` 更适合作为默认质量档；`whisper-base` 用于低配机器。
- 热词 bias 当前不会直接进入 Whisper 解码；词汇表仍可作为 LLM polish 上下文和 history 命中统计使用。

首次延迟：

- 首次下载 execution provider 和模型可能需要数分钟，取决于网络和硬件。
- 首次 load 模型可能需要数秒；应在切换 provider / 下载完成后后台 preload。
- 单次转写是 batch 型，不是 Volcengine 那种 streaming final；capsule 可保持“转写中”直到返回。

模型体积：

- 体积不硬编码。UI 通过 Foundry catalog / REST metadata 显示当前真实 `fileSizeMb`。
- 安装包不内置模型，避免 release artifact 暴涨和 license 风险。

离线能力：

- 模型和 execution provider 下载完成后，ASR 推理可离线。
- LLM polish 仍取决于用户配置的 LLM provider；LLM 不可用时按现有规则插入 raw transcript。

隐私：

- ASR 音频在本机处理，不发送到外部 ASR 服务。
- 首次下载模型和组件会访问 Foundry catalog / Microsoft 分发源。
- LLM polish 仍可能把 transcript 发送到用户配置的 LLM endpoint；设置页文案需要明确区分“ASR 本地”和“LLM 仍按配置调用”。

## Windows 安装器与分发

MVP 不修改 Windows TSF IME 注册流程。

需要验证：

- `foundry-local-sdk --features winml` 在 Tauri Windows build 中会引入哪些 DLL、runtime 文件和 redistributable 要求。
- NSIS / MSI 是否能自动收集这些 native 依赖。
- Windows release workflow 当前对 NSIS / MSI 有固定红线，不能把 bundler 两轮 invoke、`-sice:ICE80` repair 或 `bash` shell 约束顺手改掉。
- 如果 Foundry Local runtime 需要额外安装或动态下载组件，UI 必须把“正在准备本地语音运行时”作为一键流程的一部分，而不是要求用户手动跑 `winget`。

## 失败与 fallback

- Foundry runtime 缺失或初始化失败：不开始录音，提示本地语音运行时不可用，保留用户切回云 ASR 的入口。
- 模型未下载：不开始录音，提示下载模型。
- 模型下载失败：保留 partial / retry 状态，不切换到 Win+H。
- 转写超时：沿用 coordinator global timeout，写失败状态，不插入空文本。
- 转写返回空：沿用 `emptyTranscript` history guard。
- LLM polish 失败：插入 raw transcript，history 标记 `polishFailed`。
- TSF 提交失败：按现有 `allow_non_tsf_insertion_fallback` 走 Unicode / clipboard fallback；关闭 fallback 时标记 `windowsImeTsfRequired`。

## 文件与模块边界

后续实现计划触碰范围：

- `openless-all/app/src-tauri/Cargo.toml`：Windows 依赖增加 Foundry Local Rust SDK，必要时启用 `winml` feature。
- `openless-all/app/src-tauri/src/asr/local/`：拆出 provider-neutral local ASR registry，新增 Foundry Whisper runtime / provider；保留 macOS Qwen3 代码。
- `openless-all/app/src-tauri/src/coordinator.rs`：扩展 `ActiveAsr`，在 `begin_session` 和 `end_session` 分支接入 `FoundryLocalWhisperAsr`。
- `openless-all/app/src-tauri/src/commands.rs`：新增 Windows local Whisper runtime/model status、download、test、preload 命令，或把现有 `local_asr_*` 扩展成多 backend。
- `openless-all/app/src-tauri/src/types.rs`：新增 Windows local ASR preferences，如 active Foundry Whisper model、keep-loaded 时长、语言 hint。
- `openless-all/app/src/lib/localAsr.ts`、`src/pages/LocalAsr.tsx`、`src/pages/Settings.tsx`、`src/i18n/*`：展示 Windows 本地语音识别和模型管理。
- `openless-all/app/scripts/windows-real-asr-insertion-smoke.ps1`：增加 local ASR 模式，不再强制 Volcengine 凭据。

Rust 叶子模块仍只依赖 `types.rs` 和自身 provider 内部类型。跨模块编排继续放在 `coordinator.rs`。

## 验证计划

静态与单元验证：

- `asr_configured_for_provider("foundry-local-whisper")` 返回 true，不要求云端 API Key。
- `ensure_asr_credentials` 对模型缺失返回明确错误。
- fake Foundry endpoint 返回 `{ "text": "..." }` 时，`FoundryLocalWhisperAsr` 能把 PCM 编成 WAV 并产出 `RawTranscript`。
- model id、provider id、prefs default 的序列化和迁移测试。

集成验证：

- Windows 真机启动 OpenLess，active ASR 为 `foundry-local-whisper`，未配置 Volcengine / Whisper HTTP。
- 首次缺模型时按热键，不出现 Win+H 面板，不开始录音，提示下载模型。
- 下载模型后聚焦 Notepad，按热键录音，说测试短句，结束后 history 新增 session，`rawTranscript` 非空，`finalText` 非空。
- Ark / LLM 未配置时，最终插入 raw transcript，并按现有 polish fallback 规则记录。
- Ark / LLM 已配置时，transcript 进入现有 polish / translation 逻辑。
- Windows TSF IME 已安装时 `insertStatus=inserted`；禁用 TSF 或目标不支持时按当前 fallback 策略表现。
- 断网后重复已下载模型的听写，ASR 仍可完成；LLM 不可用时 raw transcript 不丢。

No Win+H 验证：

- 代码搜索确认没有 `Win+H`、Voice Typing、`Windows.Media.SpeechRecognition`、SAPI dictation 调用路径。
- 真机 smoke 过程中截图或窗口枚举确认没有 Voice Typing 面板窗口。
- 日志只出现 OpenLess recorder、Foundry local ASR、polish、Windows IME / fallback 插入事件。

## 开放风险

- Foundry Local preview API 可能变化，尤其是 Rust audio client 和 WinML package 分发。
- Foundry Local 的 Whisper 模型质量和中文标点风格需要真机样本验证，不能只靠官方能力声明。
- 首次 execution provider 下载和模型下载的错误码、进度回调、缓存位置需要实测。
- Windows installer 对 SDK native 依赖的收集需要 release workflow 验证。
- 如果 Foundry Local runtime 无法在 Tauri app 内稳定嵌入，备选路线是用 SDK 管理 local REST service；若 REST 也不稳定，再评估 `whisper.cpp` / ONNX Runtime 自管路线。
