# 冲突处理

## 代码冲突检测

当 `git push` 失败且存在代码冲突时：

### 1. 检测冲突

```bash
CONFLICT_FILES=$(git diff --name-only --diff-filter=U)
```

### 2. 创建冲突报告

```yaml
# .agent/conflicts/{task_id}_{timestamp}.yaml
task_id: task-xxx
status: pending
conflict_files:
  - src/module.py
  - tests/test_module.py
```

### 3. 等待人工处理

- 不要强制推送 (`--force`)
- 等待人工解决冲突
- 检测到冲突解决后继续执行

## 冲突解决判断

以下情况表示冲突已解决：

1. 冲突报告中 `status: resolved`
2. `git diff --name-only --diff-filter=U` 返回空

## 任务锁冲突

如果任务已被其他 Agent 锁定：

1. 检查 `.agent/tasks/in-progress/{task_id}.lock`
2. 检查锁是否超时（默认 2 小时）
3. 超时可接管，否则选择其他任务
