# 测试覆盖率 Finding 报告

## 生成时间
2026-05-04 22:59:00

## 1. 现有测试文件统计

### Rust 测试模块
```
asr/frame.rs
asr/volcengine.rs
commands.rs
coordinator.rs
insertion.rs
lib.rs
persistence.rs
polish.rs
qa_hotkey.rs
selection.rs
types.rs
windows_ime_ipc.rs
windows_ime_profile.rs
windows_ime_protocol.rs
windows_ime_session.rs
```

### 测试数量统计
```
包含测试的文件数: 15
测试模块数: 15
测试函数数: 76
```

## 2. 核心模块代码量

```
 13256 total
  3462 openless-all/app/src-tauri/src/coordinator.rs
   992 openless-all/app/src-tauri/src/polish.rs
   844 openless-all/app/src-tauri/src/lib.rs
   785 openless-all/app/src-tauri/src/hotkey.rs
   770 openless-all/app/src-tauri/src/persistence.rs
   749 openless-all/app/src-tauri/src/asr/volcengine.rs
   730 openless-all/app/src-tauri/src/windows_ime_profile.rs
   712 openless-all/app/src-tauri/src/commands.rs
   590 openless-all/app/src-tauri/src/selection.rs
   530 openless-all/app/src-tauri/src/types.rs
   525 openless-all/app/src-tauri/src/recorder.rs
   489 openless-all/app/src-tauri/src/insertion.rs
   430 openless-all/app/src-tauri/src/windows_ime_ipc.rs
   428 openless-all/app/src-tauri/src/permissions.rs
   373 openless-all/app/src-tauri/src/qa_hotkey.rs
   253 openless-all/app/src-tauri/src/windows_ime_session.rs
   252 openless-all/app/src-tauri/src/asr/frame.rs
   173 openless-all/app/src-tauri/src/windows_ime_protocol.rs
   128 openless-all/app/src-tauri/src/asr/whisper.rs
```

## 3. 需要补测试的优先级模块

### 高优先级（核心功能）
- [ ] recorder.rs - 音频采集、watchdog
- [ ] coordinator.rs - 状态机、会话管理
- [ ] asr/volcengine.rs - WebSocket ASR
- [ ] asr/frame.rs - 二进制帧编解码

### 中优先级（工具模块）
- [ ] persistence.rs - 数据持久化
- [ ] types.rs - 类型定义、状态转换
- [ ] insertion.rs - 文本插入
- [ ] polish.rs - 文本润色

### 低优先级（平台特定）
- [ ] hotkey.rs - 热键监听
- [ ] permissions.rs - 权限检查
- [ ] windows_ime_*.rs - Windows IME

## 4. 测试工具调研

### 推荐工具
- **mockall**: Mock 框架，用于 mock 外部依赖
- **proptest**: 属性测试，生成随机测试数据
- **criterion**: 性能基准测试
- **cargo-llvm-cov**: 代码覆盖率工具

### 安装命令
```bash
cargo install cargo-llvm-cov
```

## 5. 下一步行动

1. 为 recorder.rs 编写单元测试（T1.1-T1.6）
2. 为 asr/frame.rs 扩展测试（T1.7-T1.10）
3. 建立测试编写规范文档
4. 配置 CI 自动化测试

