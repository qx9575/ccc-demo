# 查看冲突对方修改内容 - 快速参考

## 冲突发生时

### 1. 查看冲突文件
```bash
# 直接查看（最简单）
cat src/utils.py

# 查看所有冲突文件
git diff --name-only --diff-filter=U
```

### 2. 查看对方分支的内容
```bash
# 查看对方分支的原始文件
git show <对方分支名>:<文件路径>

# 示例
git show conflict-test-agent2:src/utils.py
```

### 3. 对比两个版本
```bash
# 对比当前版本和对方版本
git diff HEAD <对方分支名> -- <文件路径>

# 示例
git diff HEAD conflict-test-agent2 -- src/utils.py
```

### 4. 使用可视化工具
```bash
# 使用 difftool
git difftool HEAD <对方分支名> -- <文件路径>

# 使用 mergetool
git mergetool
```

## 冲突标记说明

```
<<<<<<< HEAD
这是当前分支（我们的修改）
=======
这是对方分支（他们的修改）
>>>>>>> branch-name
```

- `HEAD` 部分 = 我们的修改（当前分支）
- 分隔线之后 = 他们的修改（对方分支）

## 冲突报告位置

```bash
# 查看冲突报告
cat .agent/conflicts/*.yaml

# 查看通知
cat .agent/notifications/alerts.txt
```

## 冲突解决后查看历史

```bash
# 查看某个提交的内容
git show <commit-hash>:<文件路径>

# 查看合并提交详情
git show <merge-commit>

# 对比两个提交
git diff <commit1> <commit2> -- <文件路径>
```

## 常用命令汇总

| 场景 | 命令 |
|------|------|
| 查看冲突文件 | `cat <file>` |
| 列出冲突文件 | `git diff --name-only --diff-filter=U` |
| 查看对方分支文件 | `git show <branch>:<file>` |
| 对比两个版本 | `git diff HEAD <branch> -- <file>` |
| 查看冲突报告 | `cat .agent/conflicts/*.yaml` |
| 使用可视化工具 | `git mergetool` |
