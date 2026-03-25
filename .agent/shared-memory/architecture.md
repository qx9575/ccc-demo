# 项目架构

## 技术栈

### v0.1 MVP（Bash 实现）
- 语言: Bash
- 优势:
  - 镜像体积小（Alpine < 100MB）
  - 原生 Git 支持
  - 简单直接，适合 MVP
- API: GLM-5（OpenAI 兼容接口）

### v0.2 多 Agent 协作（Bash 实现）
- 语言: Bash
- 新增功能:
  - PM/Coder/Reviewer 三角色协作
  - 文件级消息传递
  - 心跳监控
  - 任务状态机
  - 原子任务认领（锁机制）
  - 多模型支持（GLM/GPT/DeepSeek/Kimi）
- API: GLM-4-plus（PM/Reviewer）、GLM-5（Coder）
- Docker: Alpine + openssh-client（支持 Git push）

### v0.3+（计划）
- 语言: Python 3.11+
- 框架: 待定
- 数据库: 待定

## 目录结构

```
ccc-demo/
├── scripts/
│   ├── agent-v0.1.sh              # v0.1 主入口
│   ├── agent-v0.2.sh              # v0.2 多 Agent 入口
│   ├── agent-coordinator.sh       # 任务协调
│   ├── agent-messaging.sh         # 消息传递
│   ├── agent-heartbeat.sh         # 心跳监控
│   ├── agent-pm-loop.sh           # PM Agent 循环
│   ├── agent-coder-loop.sh        # Coder Agent 循环
│   ├── agent-reviewer-loop.sh     # Reviewer Agent 循环
│   ├── agent-loop-with-conflict-recovery.sh  # 冲突恢复循环
│   ├── simulate-conflict.sh       # 冲突模拟
│   ├── verify-conflict-resolution.sh      # 冲突解决验证
│   └── verify-conflict-resolution-v2.sh   # 冲突解决验证 v2
├── .agent/
│   ├── roles/
│   │   ├── coder/config.yaml      # 程序员配置
│   │   ├── pm/config.yaml         # 项目经理配置
│   │   └── reviewer/config.yaml   # 审查者配置
│   ├── tasks/                     # 任务文件
│   │   ├── pending/               # 待认领
│   │   ├── assigned/              # 已分配
│   │   ├── in-progress/           # 进行中
│   │   ├── review/                # 待审查
│   │   └── completed/             # 已完成
│   ├── messages/                  # Agent 间消息
│   │   ├── inbox/{agent-id}/      # 收件箱
│   │   ├── outbox/                # 发件箱
│   │   └── archive/               # 归档
│   ├── heartbeat/                 # 心跳状态
│   ├── conflicts/                 # 冲突报告
│   ├── notifications/             # 通知文件
│   ├── shared-memory/             # 共享文档
│   ├── coordination/              # 协调数据
│   └── review-standards.md        # 审查标准
├── tests/
│   ├── test-multi-agent.sh        # 多 Agent 测试
│   ├── test_calculator.py         # 计算器测试
│   ├── test_hello.py              # Hello 测试
│   ├── test_utils.py              # 工具函数测试
│   └── test_validators.py         # 验证器测试
├── docs/
│   └── usage.md                   # 使用文档
├── src/                           # Python 源码（v0.3+）
├── Dockerfile
├── docker-compose.yaml
├── start.sh
└── .env.example
```

## 编码规范

### Bash (v0.1/v0.2)
- 使用 `set -e` 错误退出
- 函数必须有注释说明
- 日志使用统一格式（log_info/log_warn/log_error）

### Python (v0.3+)
- 使用 type hints
- 函数必须有 docstring
- 测试覆盖率 > 80%

## Agent 角色

| 角色 | ID | 职责 |
|------|------|------|
| 程序员 | coder | 编写代码、修复 bug |
| 项目经理 | pm | 任务分配、进度追踪 |
| 审查者 | reviewer | 代码审查、质量把控 |

## 冲突处理流程

```
检测冲突 → 生成报告 → Agent 暂停 → 人工解决 → 状态更新 → Agent 恢复
```

详见: `conflict-quick-reference.md`
