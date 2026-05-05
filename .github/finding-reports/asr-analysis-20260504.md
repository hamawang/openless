# ASR 模块 Finding 报告

## 生成时间
2026-05-04 22:59:01

## 1. ASR 模块结构

```
total 48K
-rw-r--r-- 1 luoxu 197609 7.8K May  4 12:41 frame.rs
-rw-r--r-- 1 luoxu 197609 1.1K May  4 12:41 mod.rs
-rw-r--r-- 1 luoxu 197609  28K May  4 12:41 volcengine.rs
-rw-r--r-- 1 luoxu 197609 4.6K May  4 12:41 whisper.rs
```

## 2. ASR 模块代码量

```
  252 openless-all/app/src-tauri/src/asr/frame.rs
   35 openless-all/app/src-tauri/src/asr/mod.rs
  749 openless-all/app/src-tauri/src/asr/volcengine.rs
  128 openless-all/app/src-tauri/src/asr/whisper.rs
 1164 total
```

## 3. ASR Provider 接口分析

### 当前接口
- `AudioConsumer` trait: 接收 PCM 数据
- `RawTranscript` struct: ASR 输出结果

### 问题
- 缺少统一的 ASRProvider trait
- Volcengine 和 Whisper 实现重复代码
- 扩展新 provider 需要大量手工集成

### 改进建议
定义统一的 `ASRProvider` trait，包含：
- `open_session()`: 打开会话
- `get_audio_consumer()`: 获取音频消费者
- `close_session()`: 关闭会话并获取结果
- `cancel_session()`: 取消会话

## 4. 混淆词纠错层设计

### 插入位置
`coordinator.rs:616-617` - ASR 结果进入 polish 之前

### 数据结构
```rust
struct CorrectionRule {
    pattern: String,        // 错误模式（支持正则）
    replacement: String,    // 正确词汇
    context: Option<Vec<String>>,  // 上下文关键词
    enabled: bool,
}
```

### 内置混淆词表（初版）
- issue / iOS
- PR / 批阅
- CI / 西爱
- commit / 靠米特
- merge / 摸鸡
- release / 瑞丽丝

## 5. 本地 ASR 技术选型

### 候选方案

| 项目 | 形态 | 平台 | 加速 | License | 备注 |
|---|---|---|---|---|---|
| whisper.cpp | C/C++ | 全平台 | Metal/CoreML/CUDA | MIT | 主流候选 |
| whisper-rs | Rust binding | 全平台 | 同上 | MIT/Apache-2.0 | Rust 集成更顺 |
| sherpa-onnx | C++ + ONNX | 全平台 | CoreML/CUDA | Apache-2.0 | 多模型支持 |

### 推荐方案
**whisper-rs** - Rust 原生集成，跨平台支持好

### 集成方式
1. Rust crate 直接绑定（推荐）
2. 子进程 + HTTP（备选）

## 6. 下一步行动

### Phase 1: 混淆词纠错（Week 1）
1. 收集 50+ 真实错词样本
2. 实现 `asr/correction.rs` 模块
3. 集成到 coordinator
4. 编写测试

### Phase 2: 本地 ASR（Week 2-4）
1. 完成技术选型文档 `docs/local-asr-plan.md`
2. 测试 whisper-rs 性能
3. 实现模型下载管理
4. 实现本地推理
5. 跨平台测试

