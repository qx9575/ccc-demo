# 冲突解决快速参考

> 保存位置：.agent/shared-memory/conflict-quick-reference.md

## 一、冲突类型判断

```bash
# 推送失败后检查
git push origin main

# 如果失败，检查冲突类型
git diff --name-only --diff-filter=U
```

| 冲突类型 | 文件位置 | 处理方式 |
|----------|----------|----------|
| 任务锁冲突 | `.agent/tasks/in-progress/*.lock` | 自动（转其他任务） |
| 任务文件冲突 | `.agent/tasks/*.yaml` | 自动（用远程版本） |
| 代码冲突 | `src/`, `tests/` 等 | **人工处理** |

## 二、任务锁冲突（自动）

```bash
# 检测到锁文件存在
if [ -f ".agent/tasks/in-progress/task-001.lock" ]; then
    echo "任务已被锁定，认领其他任务"
    # 扫描其他可用任务
fi
```

## 三、代码冲突（人工）

### 步骤 1：查看冲突文件

```bash
# 列出冲突文件
git diff --name-only --diff-filter=U

# 查看冲突内容
cat <冲突文件>
```

### 步骤 2：查看对方修改

```bash
# 查看对方分支的原始内容
git show <对方分支名>:<文件路径>

# 对比两个版本
git diff HEAD <对方分支名> -- <文件路径>

# 查看远程分支内容
git show origin/main:<文件路径>
```

### 步骤 3：理解冲突标记

```
<<<<<<< HEAD        (我们的修改)
... 代码 ...
=======            (分隔线)
... 代码 ...
>>>>>>> branch      (对方的修改)
```

### 步骤 4：人工解决

```bash
# 编辑文件，删除冲突标记，保留需要的代码
vim <冲突文件>

# 标记已解决
git add <文件>

# 继续 rebase（如果在 rebase 中）
git rebase --continue

# 或完成合并（如果在 merge 中）
git commit
```

### 步骤 5：验证并推送

```bash
# 运行测试
python -m pytest tests/

# 推送
git push origin main
```

### 步骤 6：更新冲突报告

```yaml
# 编辑 .agent/conflicts/*.yaml
status: resolved
resolved_by: human
resolved_at: <时间戳>
resolution_summary: <解决说明>
```

## 四、查看命令汇总

| 场景 | 命令 |
|------|------|
| 列出冲突文件 | `git diff --name-only --diff-filter=U` |
| 查看冲突内容 | `cat <file>` |
| 查看对方分支文件 | `git show <branch>:<file>` |
| 对比两个版本 | `git diff HEAD <branch> -- <file>` |
| 查看冲突报告 | `cat .agent/conflicts/*.yaml` |
| 查看通知 | `cat .agent/notifications/alerts.txt` |
| 使用可视化工具 | `git mergetool` |

## 五、文件位置

```
.agent/
├── conflicts/              # 冲突报告目录
│   └── <task_id>_<timestamp>.yaml
├── notifications/          # 通知目录
│   └── alerts.txt
├── tasks/
│   ├── pending/           # 待认领
│   ├── in-progress/       # 进行中
│   │   ├── task-001.yaml
│   │   └── task-001.lock  # 任务锁
│   ├── review/            # 待审查
│   └── blocked/           # 阻塞
├── archives/              # 归档目录
│   ├── tasks/             # 任务归档（按月）
│   ├── tests/             # 测试归档
│   └── commits/           # 提交记录归档
└── shared-memory/         # 共享文档
    └── conflict-quick-reference.md
```

## 六、冲突报告格式

```yaml
# .agent/conflicts/task-001_20260324_103045.yaml
task_id: task-001
agent_id: coder-agent-1
detected_at: 2026-03-24T10:30:45Z
status: pending  # pending → resolved

conflict_files:
  - src/calculator.py
  - tests/test_calculator.py

# 人工解决后填写
resolved_by: human
resolved_at: 2026-03-24T11:15:00Z
resolution_summary: 合并了两个 Agent 的修改，保留所有函数

# 解决过程
resolution_steps:
  1. 查看冲突内容
  2. 手动编辑合并代码
  3. 运行测试验证
  4. git add && git commit
  5. git push
```
