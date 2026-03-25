#!/bin/bash
# archive-utils.sh - 归档工具函数
#
# 提供给 Agent 循环脚本调用的归档函数
#
# 用法: source scripts/archive-utils.sh

# ============================================
# 配置
# ============================================

ARCHIVES_DIR="${ARCHIVES_DIR:-.agent/archives}"
TASKS_DIR="${TASKS_DIR:-.agent/tasks}"

# 颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_archive() { echo -e "${BLUE}[ARCHIVE]${NC} $1"; }

# ============================================
# 归档完成的任务
# ============================================

archive_completed_task() {
    local task_id="$1"
    local month=$(date +"%Y-%m")

    log_archive "归档任务: $task_id"

    # 确保目录存在
    mkdir -p "$ARCHIVES_DIR/tasks/$month"
    mkdir -p "$ARCHIVES_DIR/tests/$month"
    mkdir -p "$ARCHIVES_DIR/commits/$month"

    # 调用归档脚本
    if [ -f "./scripts/archive-task.sh" ]; then
        bash ./scripts/archive-task.sh "$task_id" 2>/dev/null
    elif [ -f "/app/archive-task.sh" ]; then
        bash /app/archive-task.sh "$task_id" 2>/dev/null
    else
        log_archive "归档脚本不存在，执行简单归档"
        simple_archive_task "$task_id"
    fi

    return 0
}

# ============================================
# 简单归档（无脚本时使用）
# ============================================

simple_archive_task() {
    local task_id="$1"
    local month=$(date +"%Y-%m")
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # 查找任务文件
    local task_file=""
    for state in completed review in-progress pending assigned; do
        if [ -f "$TASKS_DIR/$state/${task_id}.yaml" ]; then
            task_file="$TASKS_DIR/$state/${task_id}.yaml"
            break
        fi
    done

    if [ -z "$task_file" ]; then
        return 1
    fi

    # 创建简单归档
    local archive_file="$ARCHIVES_DIR/tasks/$month/${task_id}.yaml"
    mkdir -p "$(dirname "$archive_file")"

    cat > "$archive_file" << EOF
# ============ 任务归档 ============
id: $task_id
archived_at: $timestamp
archived_by: ${AGENT_ID:-unknown}

# 原始任务内容
$(cat "$task_file")

# ============ 生命周期 ============
lifecycle:
  completed_at: $timestamp
  completed_by: ${AGENT_ID:-unknown}
EOF

    log_archive "任务已归档: $archive_file"

    # 移动原文件到 completed
    if [[ "$task_file" != *"/completed/"* ]]; then
        mkdir -p "$TASKS_DIR/completed"
        mv "$task_file" "$TASKS_DIR/completed/" 2>/dev/null || true
    fi

    # 更新索引
    update_simple_index "$month" "$task_id"
}

update_simple_index() {
    local month="$1"
    local task_id="$2"

    local index_file="$ARCHIVES_DIR/tasks/$month/index.yaml"

    if [ ! -f "$index_file" ]; then
        cat > "$index_file" << EOF
month: $month
tasks:
EOF
    fi

    echo "  - $task_id" >> "$index_file"
}

# ============================================
# 归档测试结果
# ============================================

archive_test_results() {
    local task_id="$1"
    local test_output="$2"
    local month=$(date +"%Y-%m")

    log_archive "归档测试结果: $task_id"

    local test_dir="$ARCHIVES_DIR/tests/$month/$task_id"
    mkdir -p "$test_dir"

    # 保存测试输出
    cat > "$test_dir/test_output.log" << EOF
# 测试输出 - $task_id
# 时间: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

$test_output
EOF

    # 检查测试结果
    local status="unknown"
    if echo "$test_output" | grep -qi "passed"; then
        status="passed"
    elif echo "$test_output" | grep -qi "failed"; then
        status="failed"
    fi

    # 创建测试报告
    cat > "$test_dir/test_report.yaml" << EOF
task_id: $task_id
tested_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
tested_by: ${AGENT_ID:-unknown}
result:
  status: $status
EOF

    log_archive "测试结果已归档: $test_dir"
}

# ============================================
# 创建提交记录
# ============================================

create_commit_record() {
    local task_id="$1"
    local commit_type="${2:-feat}"
    local scope="${3:-task}"
    local subject="$4"
    local body="$5"

    local month=$(date +"%Y-%m")
    local sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    local short_sha="${sha:0:7}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    log_archive "创建提交记录: $short_sha"

    local commit_dir="$ARCHIVES_DIR/commits/$month"
    mkdir -p "$commit_dir"

    local commit_file="$commit_dir/commit-${short_sha}.yaml"

    cat > "$commit_file" << EOF
# ============ 提交记录 ============
sha: $sha
short_sha: $short_sha
committed_at: $timestamp
committed_by: ${AGENT_ID:-unknown}

type: $commit_type
scope: $scope

subject: |
  $subject

description: |
$(echo "$body" | sed 's/^/  /')

related:
  task: $task_id
  task_archive: archives/tasks/$month/$task_id.yaml

files_changed:
$(git show --stat --format="" HEAD 2>/dev/null | head -20 | sed 's/^/  /')
EOF

    log_archive "提交记录已创建: $commit_file"
}

# ============================================
# 生成标准提交消息
# ============================================

generate_commit_message() {
    local task_id="$1"
    local commit_type="${2:-feat}"
    local subject="$3"
    local details="$4"

    cat << EOF
$commit_type($task_id): $subject

$details

Related: $task_id
Files: $(git diff --name-only HEAD~1 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
Tests: $(get_test_status)

Co-Authored-By: ${AGENT_ID:-agent}
EOF
}

get_test_status() {
    if [ -f "pytest" ] || command -v pytest &> /dev/null; then
        local result=$(pytest tests/ -q --tb=no 2>&1 | tail -1)
        if echo "$result" | grep -q "passed"; then
            echo "passed"
        else
            echo "unknown"
        fi
    else
        echo "not_run"
    fi
}

# ============================================
# Git 提交钩子辅助
# ============================================

# 在提交前调用，生成符合规范的提交消息
prepare_commit_message() {
    local task_id="$1"
    local change_type="$2"
    local change_scope="$3"

    local template="# 请填写提交消息
#
# 类型: $change_type
# 范围: $change_scope
# 任务: $task_id
#
# 提交消息格式:
# $change_type($change_scope): <简短描述>
#
# <详细描述>
#
# Related: $task_id
# Files: $(git diff --cached --name-only | tr '\n' ', ' | sed 's/,$//')
#
# Co-Authored-By: ${AGENT_ID:-agent}
"

    echo "$template"
}

# 导出函数
export -f archive_completed_task
export -f archive_test_results
export -f create_commit_record
export -f generate_commit_message
export -f prepare_commit_message
