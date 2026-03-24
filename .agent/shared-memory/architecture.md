# 项目架构

## 技术栈

### v0.1 MVP（Bash 实现）
- 语言: Bash
- 优势:
  - 镜像体积小（Alpine < 100MB）
  - 原生 Git 支持
  - 简单直接，适合 MVP
- API: GLM-5（OpenAI 兼容接口）

### v0.2+（计划）
- 语言: Python 3.11+
- 框架: 待定
- 数据库: 待定

## 目录结构

```
ccc-demo/
├── scripts/
│   ├── agent-v0.1.sh              # v0.1 主入口
│   └── agent-loop-with-conflict-recovery.sh  # 冲突恢复循环
├── .agent/
│   ├── roles/
│   │   ├── coder/prompt.md        # 程序员角色
│   │   ├── pm/prompt.md           # 项目经理角色
│   │   └── reviewer/prompt.md     # 审查者角色
│   ├── shared-memory/
│   │   ├── architecture.md        # 架构文档
│   │   ├── progress.md            # 进度记录
│   │   └── conflict-quick-reference.md
│   ├── tasks/                     # 任务文件
│   ├── conflicts/                 # 冲突报告
│   └── notifications/             # 通知文件
├── src/                           # Python 源码（v0.2+）
├── tests/
├── Dockerfile
├── docker-compose.yaml
├── start.sh
└── .env.example
```

## 编码规范

### Bash (v0.1)
- 使用 `set -e` 错误退出
- 函数必须有注释说明
- 日志使用统一格式（log_info/log_warn/log_error）

### Python (v0.2+)
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
