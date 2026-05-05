# Cooper 的贡献体系

> 在 fork 仓库中建立专业的 finding 和实施流程，成熟后向上游提交。

## 📁 文件结构

```
.github/
├── issues/
│   ├── EPIC-001-testing-infrastructure.md    # 测试基础设施母体 (41 tasks)
│   └── EPIC-002-asr-enhancement.md            # ASR 功能扩展母体 (71 tasks)
├── finding-reports/                           # Finding 分析报告
│   ├── test-coverage-20260504.md
│   ├── asr-analysis-20260504.md
│   ├── dependencies-20260504.md
│   └── finding-summary-20260504.md
├── COOPER_WORKFLOW.md                         # 工作流程文档
└── COOPER_CONTRIBUTION_STRATEGY.md            # 贡献策略分析

scripts/
└── finding-helper.sh                          # Finding 辅助脚本
```

## 🎯 两大 EPIC

### EPIC-001: 测试基础设施建设
- **目标**: 测试覆盖率 0% → 60%+
- **任务**: 41 个子任务
- **时间**: 6 周
- **文件**: `.github/issues/EPIC-001-testing-infrastructure.md`

### EPIC-002: ASR 功能扩展与优化
- **目标**: 混淆词纠错 + 本地 ASR 支持
- **任务**: 71 个子任务
- **时间**: 6 周
- **文件**: `.github/issues/EPIC-002-asr-enhancement.md`

## 🚀 快速开始

### 1. 查看 Finding 报告
```bash
# 运行 finding 脚本（已完成）
bash scripts/finding-helper.sh

# 查看总结
cat .github/finding-reports/finding-summary-20260504.md

# 查看详细报告
cat .github/finding-reports/test-coverage-20260504.md
cat .github/finding-reports/asr-analysis-20260504.md
```

### 2. 阅读工作流程
```bash
# 查看工作流程文档
cat .github/COOPER_WORKFLOW.md

# 查看贡献策略
cat .github/COOPER_CONTRIBUTION_STRATEGY.md
```

### 3. 开始第一个任务
```bash
# 创建分支
git checkout -b feat/asr-correction

# 开始实现混淆词纠错层
# 参考 EPIC-002 Phase 1 的任务清单
```

## 📊 当前状态

**Finding 阶段完成度**:
- ✅ 测试覆盖率分析
- ✅ ASR 模块分析
- ✅ 依赖关系分析
- ✅ 生成 Finding 报告
- ⏳ 更新 EPIC 文档（下一步）

**关键指标**:
- 包含测试的文件数: 15
- 测试函数数: 76
- 核心模块数: 17
- ASR 模块代码量: 1164 行

## 🎯 下一步行动

### 立即开始（本周）
1. ✅ 运行 finding-helper.sh 生成报告
2. ⏳ 阅读 3 份 finding 报告
3. ⏳ 更新 EPIC-001 和 EPIC-002 的 Finding 任务状态
4. ⏳ 开始实现混淆词纠错层（快速产出）

### 短期计划（Week 2-3）
- 为 recorder.rs 补测试
- 为 asr/frame.rs 补测试
- 编写测试规范文档

### 中期计划（Week 4-6）
- 完成本地 ASR 技术选型
- 实现本地 ASR 支持
- 建立 CI 自动化测试

## 🔄 工作流程

```
Finding 阶段
    ↓
实施阶段（在 fork 中）
    ↓
Review 阶段（自我 review）
    ↓
向上游提交 PR
    ↓
定期同步上游
```

详细流程见 `.github/COOPER_WORKFLOW.md`

## 📝 Commit 规范

```bash
# 格式
<type>(<scope>): <subject>

# 示例
test(recorder): add unit tests for PCM data collection
feat(asr): add correction layer for homophones
docs(testing): add testing guidelines
```

## 🔗 相关资源

- **上游仓库**: https://github.com/appergb/openless
- **你的 fork**: https://github.com/Cooper-X-Oak/openless
- **项目文档**: `CLAUDE.md`
- **开发文档**: `docs/openless-development.md`

## 💡 提示

- 所有工作先在 fork 中验证，成熟后再向上游提交
- 每个 Phase 对应一个 PR
- 定期运行 `finding-helper.sh` 更新分析报告
- 保持与上游同步（每周一次）

---

**创建时间**: 2026-05-04  
**负责人**: Cooper  
**当前阶段**: Finding  
**下一个里程碑**: 完成混淆词纠错层（Week 1）
