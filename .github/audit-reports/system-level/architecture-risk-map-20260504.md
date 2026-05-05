# 架构风险地图

## 生成时间
2026-05-04 23:15:40

## 1. 整体架构评估

### 当前架构
```
┌─────────────────────────────────────────┐
│           Frontend (React/TS)           │
│  Capsule / Overview / Settings / QA     │
└──────────────┬──────────────────────────┘
               │ IPC (Tauri commands)
┌──────────────┴──────────────────────────┐
│         Coordinator (状态机)             │
│  Idle → Starting → Listening → Processing│
└─┬────┬────┬────┬────┬────┬────┬────┬───┘
  │    │    │    │    │    │    │    │
  ▼    ▼    ▼    ▼    ▼    ▼    ▼    ▼
Hotkey Recorder ASR Polish Insert Persist Perms History
```

### 架构优势
- ✅ Coordinator 作为单一状态机，职责清晰
- ✅ 模块间通过 Coordinator 协调，避免直接依赖
- ✅ 使用 trait 抽象（AudioConsumer）

### 架构风险

#### 🔴 高风险：Coordinator 过于庞大
**现象**：
- coordinator.rs 有 3462 行代码
- 承担了状态机、会话管理、模块协调、错误处理等多重职责

**影响**：
- 难以理解和维护
- 修改一个功能可能影响其他功能
- 测试困难（需要 mock 所有依赖）

**建议**：
- 拆分为多个子模块：
  - `coordinator/state_machine.rs` - 状态转换逻辑
  - `coordinator/session.rs` - 会话管理
  - `coordinator/orchestrator.rs` - 模块协调
  - `coordinator/error_handler.rs` - 错误处理

#### 🟡 中风险：缺少统一的 ASR Provider trait
**现象**：
- Volcengine 和 Whisper 实现各自独立
- 添加新 provider 需要大量手工集成
- 代码重复（会话管理、错误处理）

**影响**：
- 扩展性差
- 维护成本高
- 容易引入不一致

**建议**：
- 定义统一的 `ASRProvider` trait
- 重构现有 provider 实现该 trait
- 在 Coordinator 中使用 trait object

#### 🟡 中风险：测试基础设施缺失
**现象**：
- 无测试策略文档
- 无 CI 自动化测试
- 测试覆盖率接近 0%

**影响**：
- 重构风险高（容易引入回归 bug）
- 新功能质量无保障
- 技术债务累积

**建议**：
- 建立测试策略（单元测试、集成测试、E2E 测试比例）
- 配置 CI 自动化测试
- 为核心模块补充测试

#### 🟢 低风险：模块间依赖清晰
**现象**：
- 各模块只依赖 `types.rs`
- 模块间不直接调用

**影响**：
- 正面影响，易于维护

## 2. 模块依赖分析

### 核心模块依赖图
```
types.rs (530 行)
    ↑
    ├── coordinator.rs (3462 行)
    │       ↑
    │       ├── hotkey.rs (785 行)
    │       ├── recorder.rs (525 行)
    │       ├── asr/mod.rs (1164 行)
    │       ├── polish.rs (992 行)
    │       ├── insertion.rs (489 行)
    │       ├── persistence.rs (770 行)
    │       └── permissions.rs (428 行)
    │
    ├── commands.rs (712 行)
    └── lib.rs (844 行)
```

### 依赖健康度
- ✅ **单向依赖**：所有模块依赖 types，types 不依赖任何模块
- ✅ **无循环依赖**：模块间无循环依赖
- ⚠️  **Coordinator 依赖过多**：依赖 8+ 个模块

## 3. 技术栈评估

### 当前技术栈
```toml
[dependencies]
tauri = { version = "2", features = ["macos-private-api", "tray-icon"] }
tauri-plugin-shell = "2"
tauri-plugin-updater = "2"
tauri-plugin-single-instance = "2"
tauri-plugin-autostart = "2"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tokio = { version = "1", features = ["full"] }
tokio-tungstenite = { version = "0.24", features = ["rustls-tls-native-roots"] }
futures-util = "0.3"
reqwest = { version = "0.12", default-features = false, features = ["json", "multipart", "rustls-tls"] }
thiserror = "1"
anyhow = "1"
log = "0.4"
env_logger = "0.11"
simplelog = "0.12"
parking_lot = "0.12"
once_cell = "1"
uuid = { version = "1", features = ["v4", "serde"] }
chrono = { version = "0.4", features = ["serde"] }
bytes = "1"
url = "2"
raw-window-handle = "0.6"

# Hotkey + audio + insertion
global-hotkey = "0.6"
cpal = "0.15"
enigo = "0.2"
arboard = "3"
rdev = "0.5"
```

### 技术栈风险
- ✅ **Tauri 2**: 成熟稳定，社区活跃
- ✅ **Tokio**: 异步运行时，性能优秀
- ✅ **Serde**: 序列化标准，生态完善
- ⚠️  **global-hotkey 0.6**: 版本较新，可能有兼容性问题
- ⚠️  **cpal 0.15**: 音频库，跨平台兼容性需关注

## 4. 扩展性瓶颈

### 当前扩展点
1. **ASR Provider**: 需要手工集成，成本高
2. **Polish Provider**: 已支持 OpenAI 兼容接口，扩展性好
3. **Insertion Strategy**: 硬编码 AX → clipboard → copy-only，扩展性差

### 扩展性改进建议

#### ASR Provider 扩展
**当前成本**：添加新 provider 需要：
1. 实现 AudioConsumer trait
2. 在 Coordinator 中添加分支逻辑
3. 在 Settings UI 中添加配置
4. 在 persistence 中添加凭据存储

**改进方案**：
```rust
// 定义统一接口
#[async_trait]
pub trait ASRProvider: Send + Sync {
    async fn open_session(&self, hotwords: Vec<DictionaryHotword>) -> Result<()>;
    fn get_audio_consumer(&self) -> Arc<dyn AudioConsumer>;
    async fn close_session(&self) -> Result<RawTranscript>;
    async fn cancel_session(&self);
}

// 注册机制
pub struct ASRRegistry {
    providers: HashMap<String, Box<dyn ASRProvider>>,
}

impl ASRRegistry {
    pub fn register(&mut self, name: &str, provider: Box<dyn ASRProvider>) {
        self.providers.insert(name.to_string(), provider);
    }
}
```

#### Insertion Strategy 扩展
**当前成本**：添加新策略需要修改 insertion.rs 核心逻辑

**改进方案**：
```rust
// 策略模式
pub trait InsertionStrategy: Send + Sync {
    async fn insert(&self, text: &str) -> Result<()>;
}

pub struct AXInsertionStrategy;
pub struct ClipboardInsertionStrategy;
pub struct CopyOnlyStrategy;

// 策略链
pub struct InsertionChain {
    strategies: Vec<Box<dyn InsertionStrategy>>,
}
```

## 5. 性能瓶颈

### 潜在瓶颈
1. **Coordinator 锁竞争**: 所有操作都需要获取 Coordinator 锁
2. **音频数据拷贝**: Recorder → AudioConsumer 可能有多次拷贝
3. **WebSocket 缓冲**: BufferingAudioConsumer 可能积压大量数据

### 性能优化建议
- 使用细粒度锁（拆分 Coordinator 状态）
- 使用 zero-copy 音频传输（Arc<[u8]>）
- 限制 BufferingAudioConsumer 缓冲区大小

## 6. 架构演进路线图

### Phase 1: Coordinator 拆分（优先级：高）
**目标**: 将 3462 行的 Coordinator 拆分为多个子模块

**步骤**:
1. 提取状态机逻辑到 `state_machine.rs`
2. 提取会话管理到 `session.rs`
3. 提取模块协调到 `orchestrator.rs`
4. 保留 `coordinator.rs` 作为入口

**预期收益**:
- 代码可读性提升 50%+
- 测试覆盖率提升 30%+
- 维护成本降低 40%+

### Phase 2: ASR Provider 统一接口（优先级：高）
**目标**: 定义统一的 ASRProvider trait，重构现有 provider

**步骤**:
1. 定义 `ASRProvider` trait
2. 重构 Volcengine 实现该 trait
3. 重构 Whisper 实现该 trait
4. 添加 provider 注册机制

**预期收益**:
- 添加新 provider 成本降低 70%+
- 代码重复减少 50%+
- 扩展性提升 100%+

### Phase 3: 测试基础设施建设（优先级：高）
**目标**: 建立完整的测试基础设施

**步骤**:
1. 编写测试策略文档
2. 为核心模块补充单元测试
3. 添加集成测试
4. 配置 CI 自动化测试

**预期收益**:
- 测试覆盖率从 0% → 60%+
- 重构风险降低 80%+
- 代码质量提升 50%+

## 7. 风险优先级矩阵

| 风险 | 影响 | 紧急度 | 优先级 | 预计工作量 |
|------|------|--------|--------|-----------|
| Coordinator 过于庞大 | 高 | 中 | P1 | 2 周 |
| 缺少统一 ASR trait | 高 | 中 | P1 | 1 周 |
| 测试基础设施缺失 | 高 | 高 | P0 | 6 周 |
| Insertion 扩展性差 | 中 | 低 | P2 | 1 周 |
| 性能瓶颈 | 中 | 低 | P3 | 2 周 |

## 8. 下一步行动

### 立即开始（本周）
1. ✅ 完成系统级审计
2. ⏳ 决策：是否需要架构重构
3. ⏳ 如果需要，暂停低尺度审计，先做架构设计

### 短期计划（2-4 周）
1. Coordinator 拆分设计文档
2. ASR Provider trait 设计文档
3. 测试策略文档

### 中期计划（1-2 个月）
1. 实施 Coordinator 拆分
2. 实施 ASR Provider 统一接口
3. 建立测试基础设施

---

**审计结论**：
- 🔴 **需要架构重构**：Coordinator 过于庞大，ASR 缺少统一接口
- 🟡 **测试基础设施缺失**：需要优先建设
- 🟢 **模块依赖健康**：无循环依赖，单向依赖清晰

**建议**：
1. 优先建立测试基础设施（为重构保驾护航）
2. 然后进行 Coordinator 拆分
3. 最后统一 ASR Provider 接口
