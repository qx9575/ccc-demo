#!/bin/bash
# simulate-conflict.sh - 模拟多 Agent 并发冲突场景
#
# 用法: ./simulate-conflict.sh

set -e

echo "=============================================="
echo "多 Agent 并发冲突模拟测试"
echo "=============================================="

# 设置环境
export GIT_AUTHOR_NAME="agent-coder-1"
export GIT_AUTHOR_EMAIL="coder1@agent.local"
export GIT_COMMITTER_NAME="agent-coder-1"
export GIT_COMMITTER_EMAIL="coder1@agent.local"

echo ""
echo "=== 场景 1: 同一文件并发修改冲突 ==="
echo ""

# 模拟 Agent 1 修改 src/hello.py
echo "# Agent 1: 修改 hello.py 添加新函数"
cat > src/hello.py << 'EOF'
"""Hello 模块 - 提供简单的问候功能"""

def say_hello(name: str) -> str:
    """生成问候语"""
    return f"Hello, {name}!"

def say_goodbye(name: str) -> str:
    """Agent 1 添加: 告别语"""
    return f"Goodbye, {name}!"
EOF

git add src/hello.py
git commit -m "feat(hello): Agent 1 添加 say_goodbye 函数"

echo ""
echo "现在需要模拟 Agent 2 在远程仓库做了不同的修改..."
echo "我们用另一个提交来模拟这个场景"

# 模拟远程修改（重置后重新提交）
git reset --hard HEAD~1

echo "# Agent 2: 修改 hello.py 添加不同的新函数（模拟远程）"
cat > src/hello.py << 'EOF'
"""Hello 模块 - 提供简单的问候功能"""

def say_hello(name: str) -> str:
    """生成问候语"""
    return f"Hello, {name}!"

def say_hi(name: str) -> str:
    """Agent 2 添加: 简短问候"""
    return f"Hi, {name}!"
EOF

git add src/hello.py
git commit -m "feat(hello): Agent 2 添加 say_hi 函数"

echo ""
echo "推送到远程（模拟 Agent 2 已推送）"
git push origin main

echo ""
echo "=== 现在 Agent 1 尝试推送 ==="

# 恢复 Agent 1 的修改
export GIT_AUTHOR_NAME="agent-coder-1"
export GIT_AUTHOR_EMAIL="coder1@agent.local"
export GIT_COMMITTER_NAME="agent-coder-1"
export GIT_COMMITTER_EMAIL="coder1@agent.local"

cat > src/hello.py << 'EOF'
"""Hello 模块 - 提供简单的问候功能"""

def say_hello(name: str) -> str:
    """生成问候语"""
    return f"Hello, {name}!"

def say_goodbye(name: str) -> str:
    """Agent 1 添加: 告别语"""
    return f"Goodbye, {name}!"
EOF

git add src/hello.py
git commit -m "feat(hello): Agent 1 添加 say_goodbye 函数"

echo ""
echo "Agent 1 尝试推送..."
if git push origin main 2>&1; then
    echo "推送成功（无冲突）"
else
    echo ""
    echo "=============================================="
    echo "检测到冲突！开始解决..."
    echo "=============================================="

    echo ""
    echo "步骤 1: 拉取远程变更（rebase 模式）"
    git pull --rebase origin main || true

    echo ""
    echo "步骤 2: 查看冲突内容"
    if [ -f src/hello.py ]; then
        echo "--- hello.py 内容 ---"
        cat src/hello.py
        echo "---"
    fi

    echo ""
    echo "步骤 3: 手动解决冲突（合并两个函数）"
    cat > src/hello.py << 'EOF'
"""Hello 模块 - 提供简单的问候功能"""

def say_hello(name: str) -> str:
    """生成问候语"""
    return f"Hello, {name}!"

def say_hi(name: str) -> str:
    """Agent 2 添加: 简短问候"""
    return f"Hi, {name}!"

def say_goodbye(name: str) -> str:
    """Agent 1 添加: 告别语"""
    return f"Goodbye, {name}!"
EOF

    git add src/hello.py
    git rebase --continue || git commit --amend --no-edit

    echo ""
    echo "步骤 4: 再次推送"
    git push origin main

    echo ""
    echo "=============================================="
    echo "冲突解决成功！"
    echo "=============================================="
fi

echo ""
echo "=== 场景 2: 任务锁竞争 ==="
echo ""

# 重置身份
export GIT_AUTHOR_NAME="root"
export GIT_AUTHOR_EMAIL="root@DESKTOP-QGKUAU3.localdomain"
export GIT_COMMITTER_NAME="root"
export GIT_COMMITTER_EMAIL="root@DESKTOP-QGKUAU3.localdomain"

git pull origin main

echo "模拟两个 Agent 同时认领 task-003..."
echo ""

# Agent 1 尝试认领
echo "# Agent 1: 尝试认领 task-003"
mkdir -p .agent/tasks/in-progress

if [ ! -f .agent/tasks/in-progress/task-003.lock ]; then
    cat > .agent/tasks/in-progress/task-003.lock << 'EOF'
agent_id: agent-coder-1
locked_at: 2026-03-16T15:05:00Z
expires_at: 2026-03-16T17:05:00Z
EOF
    git mv .agent/tasks/pending/task-003.yaml .agent/tasks/in-progress/
    git add .agent/tasks/
    git commit -m "chore: Agent 1 认领 task-003"
    echo "Agent 1 成功认领 task-003"
    TASK3_CLAIMED=1
else
    echo "Agent 1: task-003 已被锁定"
    TASK3_CLAIMED=0
fi

# 推送 Agent 1 的认领
if [ "$TASK3_CLAIMED" = "1" ]; then
    git push origin main
    echo "Agent 1 已推送认领记录"
fi

echo ""
echo "# Agent 2: 尝试认领 task-003"
git pull origin main

if [ -f .agent/tasks/in-progress/task-003.lock ]; then
    echo "Agent 2: task-003 已被 Agent 1 锁定"
    echo "Agent 2: 转而认领 task-004"

    cat > .agent/tasks/in-progress/task-004.lock << 'EOF'
agent_id: agent-coder-2
locked_at: 2026-03-16T15:05:30Z
expires_at: 2026-03-16T17:05:30Z
EOF
    git mv .agent/tasks/pending/task-004.yaml .agent/tasks/in-progress/
    git add .agent/tasks/
    git commit -m "chore: Agent 2 认领 task-004"
    git push origin main
    echo "Agent 2 成功认领 task-004"
else
    echo "Agent 2: 尝试认领 task-003"
    cat > .agent/tasks/in-progress/task-003.lock << 'EOF'
agent_id: agent-coder-2
locked_at: 2026-03-16T15:05:30Z
expires_at: 2026-03-16T17:05:30Z
EOF
    git mv .agent/tasks/pending/task-003.yaml .agent/tasks/in-progress/
    git add .agent/tasks/
    git commit -m "chore: Agent 2 认领 task-003"
    git push origin main || echo "推送失败，可能已被其他 Agent 认领"
fi

echo ""
echo "=============================================="
echo "最终状态"
echo "=============================================="
echo ""
echo "--- 进行中的任务 ---"
ls -la .agent/tasks/in-progress/*.yaml 2>/dev/null || echo "无"
echo ""
echo "--- 锁文件 ---"
ls -la .agent/tasks/in-progress/*.lock 2>/dev/null || echo "无"
echo ""
echo "--- Git 日志 ---"
git log --oneline -5

echo ""
echo "=============================================="
echo "测试完成"
echo "=============================================="
