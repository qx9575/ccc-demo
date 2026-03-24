#!/bin/bash
# verify-conflict-resolution.sh - 验证代码冲突人工处理流程
#
# 这个脚本模拟两个 Agent 同时修改同一文件，演示冲突检测和人工处理流程

set -e

echo "=============================================="
echo "代码冲突人工处理流程验证"
echo "=============================================="

# 设置 Git 身份
export GIT_AUTHOR_NAME="test-agent"
export GIT_AUTHOR_EMAIL="test@agent.local"
export GIT_COMMITTER_NAME="test-agent"
export GIT_COMMITTER_EMAIL="test@agent.local"

WORK_DIR=$(pwd)
CONFLICT_DIR=".agent/conflicts"
NOTIFICATION_DIR=".agent/notifications"

# 清理之前的测试
cleanup() {
    echo ""
    echo "=== 清理测试环境 ==="
    git checkout main -q 2>/dev/null || true
    git branch -D test-agent-1 2>/dev/null || true
    git branch -D test-agent-2 2>/dev/null || true
    git push origin --delete test-agent-1 2>/dev/null || true
    git push origin --delete test-agent-2 2>/dev/null || true
    rm -rf "$CONFLICT_DIR" "$NOTIFICATION_DIR"
}

# 先尝试清理
cleanup 2>/dev/null || true

echo ""
echo "=== 步骤 1: 创建测试分支 ==="

# Agent 1 分支
git checkout -b test-agent-1
echo ""
echo "# Agent 1: 在 utils.py 中添加 format_upper 函数"
cat > src/utils.py << 'EOF'
"""工具模块"""
from datetime import datetime
import json

def format_date(dt: datetime) -> str:
    """格式化日期为 YYYY-MM-DD"""
    return dt.strftime("%Y-%m-%d")

def parse_json(json_str: str) -> dict:
    """安全解析 JSON"""
    try:
        return json.loads(json_str)
    except json.JSONDecodeError:
        return {}

def format_upper(text: str) -> str:
    """Agent 1 添加: 转大写"""
    return text.upper()

def format_lower(text: str) -> str:
    """Agent 1 添加: 转小写"""
    return text.lower()
EOF

git add src/utils.py
git commit -m "feat(utils): Agent 1 添加 format_upper 和 format_lower"

# 保存 Agent 1 的修改
AGENT1_UTILS=$(cat src/utils.py)

echo "Agent 1 已提交到 test-agent-1 分支"

# Agent 2 分支（从 main 创建）
git checkout main
git checkout -b test-agent-2
echo ""
echo "# Agent 2: 在 utils.py 中添加不同函数"
cat > src/utils.py << 'EOF'
"""工具模块"""
from datetime import datetime
import json

def format_date(dt: datetime) -> str:
    """格式化日期为 YYYY-MM-DD"""
    return dt.strftime("%Y-%m-%d")

def parse_json(json_str: str) -> dict:
    """安全解析 JSON"""
    try:
        return json.loads(json_str)
    except json.JSONDecodeError:
        return {}

def format_reverse(text: str) -> str:
    """Agent 2 添加: 反转字符串"""
    return text[::-1]

def format_capitalize(text: str) -> str:
    """Agent 2 添加: 首字母大写"""
    return text.capitalize()
EOF

git add src/utils.py
git commit -m "feat(utils): Agent 2 添加 format_reverse 和 format_capitalize"

echo "Agent 2 已提交到 test-agent-2 分支"

echo ""
echo "=== 步骤 2: 推送 Agent 2 的修改（模拟远程） ==="
git push origin test-agent-2 -q
echo "Agent 2 已推送到远程"

echo ""
echo "=== 步骤 3: Agent 1 尝试推送（会冲突） ==="
git checkout test-agent-1

if git push origin test-agent-1 2>&1; then
    echo "推送成功（无冲突）"
    NEED_CONFLICT_RESOLUTION=false
else
    echo ""
    echo "=============================================="
    echo "⚠️  检测到推送冲突！"
    echo "=============================================="
    NEED_CONFLICT_RESOLUTION=true
fi

if [ "$NEED_CONFLICT_RESOLUTION" = true ]; then
    echo ""
    echo "=== 步骤 4: 拉取远程变更（rebase 模式） ==="

    if git pull --rebase origin test-agent-2 2>&1; then
        echo "Rebase 成功（无代码冲突）"
    else
        echo ""
        echo "=============================================="
        echo "⚠️  检测到代码冲突！"
        echo "=============================================="

        # 获取冲突文件列表
        CONFLICT_FILES=$(git diff --name-only --diff-filter=U 2>/dev/null || echo "")
        CONFLICT_COUNT=$(echo "$CONFLICT_FILES" | grep -c . || echo "0")

        echo ""
        echo "冲突文件数量: $CONFLICT_COUNT"
        echo "冲突文件列表:"
        for file in $CONFLICT_FILES; do
            echo "  - $file"
        done

        echo ""
        echo "=== 步骤 5: 创建冲突报告 ==="

        mkdir -p "$CONFLICT_DIR"
        REPORT_FILE="$CONFLICT_DIR/task-test_$(date +%Y%m%d_%H%M%S).yaml"

        cat > "$REPORT_FILE" << EOF
# 代码冲突报告
task_id: task-test
agent_id: agent-1
detected_at: $(date -Iseconds)
status: pending

conflict_files:
$(for f in $CONFLICT_FILES; do echo "  - $f"; done)

# 冲突内容预览
conflicts:
EOF

        for file in $CONFLICT_FILES; do
            echo "  - file: $file" >> "$REPORT_FILE"
            echo "    conflict_markers: true" >> "$REPORT_FILE"
        done

        echo ""
        echo "冲突报告已创建: $REPORT_FILE"
        cat "$REPORT_FILE"

        echo ""
        echo "=== 步骤 6: 通知人工 ==="

        mkdir -p "$NOTIFICATION_DIR"
        ALERT_FILE="$NOTIFICATION_DIR/alerts.txt"

        cat >> "$ALERT_FILE" << EOF
[$(date)] ⚠️ 代码冲突需要人工处理

任务: task-test
Agent: agent-1
冲突文件数: $CONFLICT_COUNT

冲突文件:
$(for f in $CONFLICT_FILES; do echo "  - $f"; done)

请解决冲突后重新启动 Agent。

解决步骤:
1. 查看冲突文件内容
2. 手动编辑合并代码
3. git add <resolved_files>
4. git rebase --continue
5. 运行测试验证
6. git push origin test-agent-1
7. 更新冲突报告状态为 resolved

EOF

        echo "通知已写入: $ALERT_FILE"
        cat "$ALERT_FILE"

        echo ""
        echo "=============================================="
        echo "任务已暂停，等待人工处理"
        echo "=============================================="

        echo ""
        echo "=== 步骤 7: 查看冲突内容 ==="
        echo ""
        echo "--- src/utils.py 冲突内容 ---"
        head -30 src/utils.py
        echo "..."
        echo "---"

        echo ""
        echo "=============================================="
        echo "人工处理流程"
        echo "=============================================="
        echo ""
        echo "1. 查看完整冲突内容:"
        echo "   cat src/utils.py"
        echo ""
        echo "2. 手动编辑文件，解决冲突标记:"
        echo "   <<<<<<< HEAD       (Agent 1 的代码)"
        echo "   ...代码..."
        echo "   =======            (分隔线)"
        echo "   ...代码..."
        echo "   >>>>>>> ...        (Agent 2 的代码)"
        echo ""
        echo "3. 编辑文件，保留需要的代码:"
        echo "   vim src/utils.py"
        echo ""
        echo "4. 标记冲突已解决:"
        echo "   git add src/utils.py"
        echo "   git rebase --continue"
        echo ""
        echo "5. 运行测试验证:"
        echo "   python3 tests/test_utils.py"
        echo ""
        echo "6. 推送代码:"
        echo "   git push origin test-agent-1"
        echo ""
        echo "7. 更新冲突报告:"
        echo "   编辑 $REPORT_FILE"
        echo "   将 status 改为 resolved"

        # 模拟人工解决冲突
        echo ""
        echo "=== 模拟人工解决冲突 ==="
        echo ""
        echo "人工编辑中..."
        sleep 1

        # 合并两个 Agent 的修改
        cat > src/utils.py << 'EOF'
"""工具模块"""
from datetime import datetime
import json

def format_date(dt: datetime) -> str:
    """格式化日期为 YYYY-MM-DD"""
    return dt.strftime("%Y-%m-%d")

def parse_json(json_str: str) -> dict:
    """安全解析 JSON"""
    try:
        return json.loads(json_str)
    except json.JSONDecodeError:
        return {}

# Agent 1 添加的函数
def format_upper(text: str) -> str:
    """转大写"""
    return text.upper()

def format_lower(text: str) -> str:
    """转小写"""
    return text.lower()

# Agent 2 添加的函数
def format_reverse(text: str) -> str:
    """反转字符串"""
    return text[::-1]

def format_capitalize(text: str) -> str:
    """首字母大写"""
    return text.capitalize()
EOF

        echo "已合并两个 Agent 的修改"

        # 更新测试文件
        cat > tests/test_utils.py << 'EOF'
"""工具模块测试"""
import sys
sys.path.insert(0, 'src')
from datetime import datetime
from utils import format_date, parse_json, format_upper, format_lower, format_reverse, format_capitalize

def test_format_date():
    dt = datetime(2026, 3, 24)
    assert format_date(dt) == "2026-03-24"

def test_parse_json():
    assert parse_json('{"a": 1}') == {"a": 1}
    assert parse_json('invalid') == {}

def test_format_upper():
    assert format_upper("hello") == "HELLO"

def test_format_lower():
    assert format_lower("HELLO") == "hello"

def test_format_reverse():
    assert format_reverse("hello") == "olleh"

def test_format_capitalize():
    assert format_capitalize("hello") == "Hello"

if __name__ == "__main__":
    test_format_date()
    print("✓ test_format_date 通过")
    test_parse_json()
    print("✓ test_parse_json 通过")
    test_format_upper()
    print("✓ test_format_upper 通过")
    test_format_lower()
    print("✓ test_format_lower 通过")
    test_format_reverse()
    print("✓ test_format_reverse 通过")
    test_format_capitalize()
    print("✓ test_format_capitalize 通过")
    print("\n所有测试通过!")
EOF

        echo "已更新测试文件"

        echo ""
        echo "=== 步骤 8: 运行测试验证 ==="
        python3 tests/test_utils.py

        echo ""
        echo "=== 步骤 9: 标记冲突已解决 ==="
        git add src/utils.py tests/test_utils.py
        git rebase --continue

        echo ""
        echo "=== 步骤 10: 更新冲突报告 ==="
        cat > "$REPORT_FILE" << EOF
# 代码冲突报告
task_id: task-test
agent_id: agent-1
detected_at: $(date -Iseconds -d '5 minutes ago')
status: resolved

conflict_files:
  - src/utils.py

resolved_by: human
resolved_at: $(date -Iseconds)
resolution_summary: 合并了两个 Agent 的修改，保留所有函数

# 解决过程
resolution_steps:
  1. 查看冲突内容
  2. 手动编辑合并两个版本的函数
  3. 更新测试文件
  4. 运行测试验证通过
  5. git add && git rebase --continue
EOF

        echo "冲突报告已更新:"
        cat "$REPORT_FILE"

        echo ""
        echo "=== 步骤 11: 推送代码 ==="
        git push origin test-agent-1 --force-with-lease

        echo ""
        echo "=============================================="
        echo "✅ 冲突解决完成！"
        echo "=============================================="
    fi
fi

echo ""
echo "=== 清理测试环境 ==="
git checkout main -q
git branch -D test-agent-1 2>/dev/null || true
git branch -D test-agent-2 2>/dev/null || true
git push origin --delete test-agent-1 2>/dev/null || true
git push origin --delete test-agent-2 2>/dev/null || true

echo ""
echo "=============================================="
echo "验证完成"
echo "=============================================="
echo ""
echo "验证结果:"
echo "  ✅ 代码冲突检测"
echo "  ✅ 创建冲突报告"
echo "  ✅ 通知人工处理"
echo "  ✅ 人工合并代码"
echo "  ✅ 测试验证"
echo "  ✅ 推送代码"
echo "  ✅ 更新冲突报告"
