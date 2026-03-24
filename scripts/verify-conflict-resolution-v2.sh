#!/bin/bash
# verify-conflict-resolution-v2.sh - 验证代码冲突人工处理流程
#
# 这个脚本模拟真正的代码冲突场景：
# Agent 1 和 Agent 2 都基于同一个 main 分支修改同一文件

set -e

echo "=============================================="
echo "代码冲突人工处理流程验证 v2"
echo "=============================================="

WORK_DIR=$(pwd)
CONFLICT_DIR=".agent/conflicts"
NOTIFICATION_DIR=".agent/notifications"

# 清理函数
cleanup() {
    echo "清理中..."
    git checkout main -q 2>/dev/null || true
    git branch -D conflict-test-agent1 2>/dev/null || true
    git branch -D conflict-test-agent2 2>/dev/null || true
    git push origin --delete conflict-test-agent1 2>/dev/null || true
    git push origin --delete conflict-test-agent2 2>/dev/null || true
    rm -rf "$CONFLICT_DIR" "$NOTIFICATION_DIR"
    git checkout main -q
    git pull origin main -q
}

# 清理之前的状态
cleanup 2>/dev/null || true

echo ""
echo "=== 初始状态 ==="
echo "当前分支: $(git branch --show-current)"
echo "最新提交: $(git log --oneline -1)"

# 保存原始 utils.py 内容
ORIGINAL_UTILS=$(cat src/utils.py)

echo ""
echo "=============================================="
echo "场景：两个 Agent 同时修改 src/utils.py"
echo "=============================================="

echo ""
echo "=== 步骤 1: Agent 1 基于 main 创建分支并修改 ==="

git checkout -b conflict-test-agent1

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
    """Agent 1: 转大写"""
    return text.upper()

def format_lower(text: str) -> str:
    """Agent 1: 转小写"""
    return text.lower()
EOF

git add src/utils.py
git commit -m "feat(utils): Agent 1 添加 format_upper 和 format_lower"
git push origin conflict-test-agent1 -q

echo "✅ Agent 1 已推送到 conflict-test-agent1"

echo ""
echo "=== 步骤 2: Agent 2 基于 main 创建分支并修改（同一文件不同内容）==="

git checkout main
git pull origin main -q
git checkout -b conflict-test-agent2

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

# Agent 2 添加的函数
def format_reverse(text: str) -> str:
    """Agent 2: 反转字符串"""
    return text[::-1]

def format_capitalize(text: str) -> str:
    """Agent 2: 首字母大写"""
    return text.capitalize()
EOF

git add src/utils.py
git commit -m "feat(utils): Agent 2 添加 format_reverse 和 format_capitalize"
git push origin conflict-test-agent2 -q

echo "✅ Agent 2 已推送到 conflict-test-agent2"

echo ""
echo "=============================================="
echo "现在模拟 Agent 1 尝试将修改合并到 main"
echo "=============================================="

git checkout main
git pull origin main -q

echo ""
echo "=== 步骤 3: 合并 Agent 1 的修改到 main ==="
git merge conflict-test-agent1 -m "merge: Agent 1 的修改"
echo "✅ Agent 1 的修改已合并到 main"
git push origin main -q
echo "✅ 已推送到远程"

echo ""
echo "=== 步骤 4: 尝试合并 Agent 2 的修改（会产生冲突）==="
git pull origin main -q

if git merge conflict-test-agent2 -m "merge: Agent 2 的修改" 2>&1; then
    echo "合并成功（无冲突）"
    git push origin main -q
    cleanup
    exit 0
fi

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
REPORT_FILE="$CONFLICT_DIR/task-conflict-test_$(date +%Y%m%d_%H%M%S).yaml"

cat > "$REPORT_FILE" << EOF
# 代码冲突报告
task_id: task-conflict-test
agent_id: agent-2
detected_at: $(date -Iseconds)
status: pending

conflict_files:
$(for f in $CONFLICT_FILES; do echo "  - $f"; done)

# 冲突详情
conflicts:
EOF

for file in $CONFLICT_FILES; do
    echo "  - file: $file" >> "$REPORT_FILE"
    echo "    status: unresolved" >> "$REPORT_FILE"
done

echo ""
echo "冲突报告已创建: $REPORT_FILE"
echo ""
cat "$REPORT_FILE"

echo ""
echo "=== 步骤 6: 通知人工 ==="

mkdir -p "$NOTIFICATION_DIR"
ALERT_FILE="$NOTIFICATION_DIR/alerts.txt"

cat >> "$ALERT_FILE" << EOF

========================================
[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ 代码冲突需要人工处理
========================================

任务: task-conflict-test
Agent: agent-2
冲突文件数: $CONFLICT_COUNT

冲突文件:
$(for f in $CONFLICT_FILES; do echo "  - $f"; done)

请解决冲突后继续。

解决步骤:
1. 查看冲突内容: cat src/utils.py
2. 编辑文件，删除冲突标记
3. git add <files>
4. git commit
5. git push origin main
6. 更新冲突报告状态

EOF

echo "通知已写入: $ALERT_FILE"

echo ""
echo "=============================================="
echo "任务已暂停，等待人工处理"
echo "=============================================="

echo ""
echo "=== 步骤 7: 查看冲突内容 ==="
echo ""
echo "--- src/utils.py 冲突标记 ---"
cat src/utils.py
echo ""
echo "--- 文件末尾 ---"

echo ""
echo "=============================================="
echo "人工处理流程"
echo "=============================================="
echo ""
echo "冲突标记说明:"
echo "  <<<<<<< HEAD        (当前分支的代码)"
echo "  ...代码内容..."
echo "  =======             (分隔线)"
echo "  ...代码内容..."
echo "  >>>>>>> branch      (要合并的分支代码)"
echo ""
echo "解决步骤:"
echo "  1. 编辑冲突文件，保留需要的代码"
echo "  2. 删除冲突标记 (<<<<<<, =======, >>>>>>)"
echo "  3. git add <files>"
echo "  4. git commit"
echo "  5. 运行测试验证"
echo "  6. git push"
echo "  7. 更新冲突报告"

echo ""
echo "=== 步骤 8: 模拟人工解决冲突 ==="
echo ""
sleep 1
echo "人工编辑中..."

# 合并两个版本的所有函数
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

echo "✅ 已合并两个 Agent 的修改"

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

echo "✅ 已更新测试文件"

echo ""
echo "=== 步骤 9: 标记冲突已解决 ==="
git add src/utils.py tests/test_utils.py
git commit -m "merge: 解决冲突，合并 Agent 1 和 Agent 2 的修改"

echo ""
echo "=== 步骤 10: 运行测试验证 ==="
python3 tests/test_utils.py

echo ""
echo "=== 步骤 11: 更新冲突报告 ==="
cat > "$REPORT_FILE" << EOF
# 代码冲突报告
task_id: task-conflict-test
agent_id: agent-2
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
  3. 删除冲突标记
  4. 更新测试文件
  5. 运行测试验证通过
  6. git add && git commit
EOF

echo ""
echo "冲突报告已更新:"
cat "$REPORT_FILE"

echo ""
echo "=== 步骤 12: 推送代码 ==="
git push origin main

echo ""
echo "=============================================="
echo "✅ 冲突解决完成！"
echo "=============================================="

echo ""
echo "=== 最终代码状态 ==="
echo ""
echo "--- src/utils.py ---"
cat src/utils.py

echo ""
echo "--- Git 日志 ---"
git log --oneline -5

# 清理测试分支
echo ""
echo "=== 清理测试环境 ==="
git branch -D conflict-test-agent1 2>/dev/null || true
git branch -D conflict-test-agent2 2>/dev/null || true
git push origin --delete conflict-test-agent1 2>/dev/null || true
git push origin --delete conflict-test-agent2 2>/dev/null || true

echo ""
echo "=============================================="
echo "验证完成！"
echo "=============================================="
echo ""
echo "验证结果:"
echo "  ✅ 两个 Agent 同时修改同一文件"
echo "  ✅ 检测到代码冲突"
echo "  ✅ 创建冲突报告"
echo "  ✅ 通知人工处理"
echo "  ✅ 人工合并代码"
echo "  ✅ 测试验证通过"
echo "  ✅ 推送代码成功"
echo "  ✅ 更新冲突报告状态为 resolved"
echo ""
echo "冲突处理流程:"
echo "  1. git merge 时检测到冲突"
echo "  2. 创建 .agent/conflicts/ 报告"
echo "  3. 写入 .agent/notifications/alerts.txt"
echo "  4. Agent 暂停，等待人工处理"
echo "  5. 人工编辑文件解决冲突"
echo "  6. git add && git commit"
echo "  7. 运行测试验证"
echo "  8. git push"
echo "  9. 更新冲突报告状态"
