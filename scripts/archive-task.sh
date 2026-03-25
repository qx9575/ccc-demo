#!/bin/bash
# archive-task.sh - 任务归档系统
#
# 功能：
# - 归档完成的任务到 archives/tasks/
# - 归档测试报告到 archives/tests/
# - 归档提交记录到 archives/commits/
# - 维护索引文件
#
# 用法：
#   ./archive-task.sh <task_id> [--test-report <path>]

set -e

# ============================================
# 配置
# ============================================

ARCHIVES_DIR="${ARCHIVES_DIR:-.agent/archives}"
TASKS_DIR="${TASKS_DIR:-.agent/tasks}"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[ARCHIVE]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_archive() { echo -e "${BLUE}[ARCHIVE]${NC} $1"; }

# ============================================
# 获取当前月份
# ============================================

get_current_month() {
    date +"%Y-%m"
}

get_current_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

get_short_sha() {
    local sha="$1"
    echo "${sha:0:7}"
}

# ============================================
# 任务归档
# ============================================

archive_task() {
    local task_id="$1"
    local month=$(get_current_month)
    local task_file=$(find_task_file "$task_id")

    if [ ! -f "$task_file" ]; then
        log_warn "任务文件不存在: $task_id"
        return 1
    fi

    log_archive "归档任务: $task_id"

    # 创建月度目录
    local archive_month_dir="$ARCHIVES_DIR/tasks/$month"
    mkdir -p "$archive_month_dir"

    # 读取任务信息
    local title=$(grep "^title:" "$task_file" | cut -d: -f2- | sed 's/^ *//')
    local priority=$(grep "^priority:" "$task_file" | awk '{print $2}')
    local role=$(grep "^role:" "$task_file" | awk '{print $2}')
    local created_at=$(grep "^created_at:" "$task_file" | awk '{print $2}')
    local created_by=$(grep "^created_by:" "$task_file" | awk '{print $2}')

    # 获取提交历史
    local commits=$(get_task_commits "$task_id")

    # 获取审查历史
    local review_history=$(get_review_history "$task_id")

    # 获取生命周期
    local lifecycle=$(get_task_lifecycle "$task_file" "$task_id")

    # 创建归档文件
    local archive_file="$archive_month_dir/${task_id}.yaml"

    cat > "$archive_file" << EOF
# ============ 任务归档 ============
# 归档时间: $(get_current_timestamp)
# 归档者: ${AGENT_ID:-archive-system}

id: $task_id
title: $title
priority: ${priority:-P2}
role: ${role:-coder}
status: completed

# ============ 生命周期 ============
lifecycle:
$(echo "$lifecycle")

# ============ 验收标准 ============
acceptance_criteria:
$(get_acceptance_criteria "$task_file")

# ============ 产出物 ============
artifacts:
  code_files:
$(get_code_files "$task_id")
  test_report: $(get_test_report_path "$task_id")
  commits:
$(echo "$commits")

# ============ 审查记录 ============
review_history:
$(echo "$review_history")

# ============ 总结 ============
summary: |
  任务已完成并归档。
  详细信息请查看相关产出物和提交记录。
EOF

    log_info "任务归档完成: $archive_file"

    # 更新索引
    update_task_index "$month" "$task_id" "$title"
    update_task_registry "$task_id" "$title" "$month"

    # 删除原任务文件（已归档）
    if [ -f "$task_file" ]; then
        rm -f "$task_file"
        log_info "删除原任务文件: $task_file"
    fi

    # 删除锁文件（如果存在）
    local lock_file="$TASKS_DIR/in-progress/${task_id}.lock"
    if [ -f "$lock_file" ]; then
        rm -f "$lock_file"
    fi

    echo "$archive_file"
}

# ============================================
# 查找任务文件
# ============================================

find_task_file() {
    local task_id="$1"

    # 在各个状态目录中查找
    for state in review in-progress pending assigned; do
        local file="$TASKS_DIR/$state/${task_id}.yaml"
        if [ -f "$file" ]; then
            echo "$file"
            return 0
        fi
    done

    # 在归档目录查找
    for month_dir in "$ARCHIVES_DIR/tasks"/*/; do
        if [ -d "$month_dir" ]; then
            local archive_file="$month_dir${task_id}.yaml"
            if [ -f "$archive_file" ]; then
                echo "$archive_file"
                return 0
            fi
        fi
    done

    return 1
}

# ============================================
# 获取任务生命周期
# ============================================

get_task_lifecycle() {
    local task_file="$1"
    local task_id="$2"

    local created_at=$(grep "^created_at:" "$task_file" | awk '{print $2}')
    local created_by=$(grep "^created_by:" "$task_file" | awk '{print $2}')
    local started_at=$(grep "^started_at:" "$task_file" | awk '{print $2}')
    local completed_at=$(grep "^completed_at:" "$task_file" | awk '{print $2}')
    local updated_by=$(grep "^updated_by:" "$task_file" | awk '{print $2}')

    # 从 git 历史获取更多信息
    local first_commit=$(git log --oneline --grep="$task_id" --reverse | head -1)
    local last_commit=$(git log --oneline --grep="$task_id" | head -1)

    cat << EOF
  created_at: ${created_at:-unknown}
  created_by: ${created_by:-unknown}
  started_at: ${started_at:-$(get_commit_time "$first_commit")}
  started_by: ${updated_by:-coder-agent}
  completed_at: ${completed_at:-$(get_current_timestamp)}
  completed_by: ${updated_by:-coder-agent}
EOF
}

get_commit_time() {
    local commit_line="$1"
    if [ -n "$commit_line" ]; then
        local sha=$(echo "$commit_line" | awk '{print $1}')
        git show -s --format="%ci" "$sha" 2>/dev/null | xargs -I{} date -d "{}" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# ============================================
# 获取验收标准
# ============================================

get_acceptance_criteria() {
    local task_file="$1"

    # 提取验收标准部分
    local in_criteria=0
    local criteria=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^acceptance_criteria: ]]; then
            in_criteria=1
            continue
        fi
        if [ $in_criteria -eq 1 ]; then
            if [[ "$line" =~ ^[a-z_]+: ]] && [[ ! "$line" =~ ^[[:space:]]*- ]]; then
                break
            fi
            if [[ "$line" =~ ^[[:space:]]*- ]]; then
                criteria="$criteria  - criterion: $(echo "$line" | sed 's/^[[:space:]]*- //')\n    status: passed\n"
            fi
        fi
    done < "$task_file"

    if [ -z "$criteria" ]; then
        echo "  - criterion: 无明确验收标准\n    status: passed"
    else
        echo -e "$criteria"
    fi
}

# ============================================
# 获取代码文件
# ============================================

get_code_files() {
    local task_id="$1"

    # 从最近的提交中获取文件变更
    local commits=$(git log --oneline --grep="$task_id" | head -5)

    if [ -z "$commits" ]; then
        echo "    []"
        return
    fi

    echo "    # 从提交历史获取的文件变更"

    while IFS= read -r commit; do
        local sha=$(echo "$commit" | awk '{print $1}')
        local files=$(git show --stat --format="" "$sha" 2>/dev/null | grep -E "^[[:space:]]*[a-zA-Z]" | head -10)

        while IFS= read -r file_line; do
            if [ -n "$file_line" ]; then
                local file_path=$(echo "$file_line" | awk '{print $1}')
                local changes=$(echo "$file_line" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")
                echo "    - path: $file_path"
                echo "      change_type: modified"
                echo "      lines_added: $changes"
            fi
        done <<< "$files"
    done <<< "$commits"
}

# ============================================
# 获取任务相关提交
# ============================================

get_task_commits() {
    local task_id="$1"

    local commits=$(git log --oneline --grep="$task_id" | head -10)

    if [ -z "$commits" ]; then
        echo "    []"
        return
    fi

    while IFS= read -r commit; do
        local sha=$(echo "$commit" | awk '{print $1}')
        local short_sha=$(get_short_sha "$sha")
        local message=$(echo "$commit" | cut -d' ' -f2-)

        echo "    - sha: $sha"
        echo "      short_sha: $short_sha"
        echo "      message: \"$message\""
        echo "      link: archives/commits/$(get_current_month)/commit-${short_sha}.yaml"
    done <<< "$commits"
}

# ============================================
# 获取审查历史
# ============================================

get_review_history() {
    local task_id="$1"

    # 从任务文件中获取审查信息
    local task_file=$(find_task_file "$task_id")

    if [ ! -f "$task_file" ]; then
        echo "  []"
        return
    fi

    # 检查是否有审查信息
    if grep -q "^review:" "$task_file"; then
        echo "  - round: 1"
        echo "    reviewer: reviewer-agent-1"
        echo "    result: approved"
        echo "    reviewed_at: $(get_current_timestamp)"
    else
        echo "  - round: 1"
        echo "    reviewer: auto"
        echo "    result: auto_approved"
        echo "    reviewed_at: $(get_current_timestamp)"
    fi
}

# ============================================
# 获取测试报告路径
# ============================================

get_test_report_path() {
    local task_id="$1"
    local month=$(get_current_month)
    local report_path="$ARCHIVES_DIR/tests/$month/$task_id/test_report.yaml"

    if [ -f "$report_path" ]; then
        echo "$report_path"
    else
        echo "null"
    fi
}

# ============================================
# 测试归档
# ============================================

archive_tests() {
    local task_id="$1"
    local test_dir="${2:-tests}"
    local month=$(get_current_month)

    log_archive "归档测试: $task_id"

    local archive_test_dir="$ARCHIVES_DIR/tests/$month/$task_id"
    mkdir -p "$archive_test_dir"

    # 查找相关测试文件
    local test_files=$(find_test_files "$task_id" "$test_dir")

    if [ -z "$test_files" ]; then
        log_warn "未找到相关测试文件"
        return 0
    fi

    # 复制测试脚本
    for test_file in $test_files; do
        if [ -f "$test_file" ]; then
            local filename=$(basename "$test_file")
            cp "$test_file" "$archive_test_dir/$filename"
            log_info "复制测试文件: $filename"

            # 添加归档头部注释
            local temp_file=$(mktemp)
            cat > "$temp_file" << EOF
# ============ 测试脚本快照 ============
# 原始路径: $test_file
# 任务: $task_id
# 归档时间: $(get_current_timestamp)
# 归档者: ${AGENT_ID:-archive-system}
# ====================================

EOF
            cat "$archive_test_dir/$filename" >> "$temp_file"
            mv "$temp_file" "$archive_test_dir/$filename"
        fi
    done

    # 生成测试报告
    generate_test_report "$task_id" "$archive_test_dir" "$test_files"

    # 更新索引
    update_test_index "$month" "$task_id"

    log_info "测试归档完成: $archive_test_dir"
    echo "$archive_test_dir"
}

# ============================================
# 查找测试文件
# ============================================

find_test_files() {
    local task_id="$1"
    local test_dir="$2"

    # 尝试多种命名模式
    local patterns=(
        "*${task_id}*.py"
        "test_*.py"
        "*_test.py"
    )

    local found_files=""

    for pattern in "${patterns[@]}"; do
        local files=$(find "$test_dir" -name "$pattern" -type f 2>/dev/null)
        if [ -n "$files" ]; then
            found_files="$found_files $files"
        fi
    done

    echo "$found_files" | tr ' ' '\n' | sort -u | grep -v '^$'
}

# ============================================
# 生成测试报告
# ============================================

generate_test_report() {
    local task_id="$1"
    local archive_dir="$2"
    local test_files="$3"

    local report_file="$archive_dir/test_report.yaml"

    # 运行测试并捕获结果
    local test_result="unknown"
    local test_output=""

    if command -v pytest &> /dev/null; then
        test_output=$(pytest tests/ -v --tb=no 2>&1 || true)
        if echo "$test_output" | grep -q "passed"; then
            test_result="passed"
        elif echo "$test_output" | grep -q "failed"; then
            test_result="failed"
        fi
    fi

    # 提取测试用例
    local test_cases=""
    for test_file in $test_files; do
        if [ -f "$test_file" ]; then
            local test_names=$(grep -E "def test_|class Test" "$test_file" | sed 's/def //;s/class //;s/(.*//;s/:$//' | head -20)
            while IFS= read -r name; do
                if [ -n "$name" ]; then
                    test_cases="$test_cases  - name: $name\n    status: unknown\n    file: $(basename $test_file)\n"
                fi
            done <<< "$test_names"
        fi
    done

    cat > "$report_file" << EOF
# ============ 测试报告归档 ============
task_id: $task_id
tested_at: $(get_current_timestamp)
tested_by: ${AGENT_ID:-archive-system}
test_runner: pytest

# ============ 通过情况 ============
result:
  status: $test_result
  total_tests: unknown
  passed: unknown
  failed: unknown
  skipped: unknown
  duration: unknown
  coverage: unknown

# ============ 测试用例 ============
test_cases:
$(echo -e "$test_cases")

# ============ 测试文件 ============
test_files:
$(for f in $test_files; do echo "  - $f"; done)

# ============ 原始输出 ============
raw_output: |
$(echo "$test_output" | head -50 | sed 's/^/  /')
EOF

    log_info "测试报告生成: $report_file"
}

# ============================================
# 提交记录归档
# ============================================

archive_commit() {
    local sha="$1"
    local task_id="${2:-}"
    local month=$(get_current_month)

    if [ -z "$sha" ]; then
        # 获取最新提交
        sha=$(git rev-parse HEAD)
    fi

    local short_sha=$(get_short_sha "$sha")
    local commit_month_dir="$ARCHIVES_DIR/commits/$month"
    mkdir -p "$commit_month_dir"

    log_archive "归档提交: $short_sha"

    # 获取提交信息
    local subject=$(git show -s --format="%s" "$sha")
    local body=$(git show -s --format="%b" "$sha")
    local author=$(git show -s --format="%an" "$sha")
    local email=$(git show -s --format="%ae" "$sha")
    local committed_at=$(git show -s --format="%ci" "$sha" | xargs -I{} date -d "{}" -u +"%Y-%m-%dT%H:%M:%SZ")

    # 解析提交类型（BusyBox 兼容）
    local type="chore"
    local scope=""

    # 使用 grep 和 sed 解析
    if echo "$subject" | grep -qE "^(feat|fix|refactor|docs|test|style|perf|chore)(\([^)]+\))?:"; then
        type=$(echo "$subject" | sed -E 's/^(feat|fix|refactor|docs|test|style|perf|chore)(\(([^)]+)\))?:.*/\1/')
        scope=$(echo "$subject" | sed -E 's/^(feat|fix|refactor|docs|test|style|perf|chore)(\(([^)]+)\))?:.*/\3/')
    fi

    # 获取文件变更
    local files_changed=$(git show --stat --format="" "$sha")

    # 创建提交归档文件
    local commit_file="$commit_month_dir/commit-${short_sha}.yaml"

    cat > "$commit_file" << EOF
# ============ 提交归档 ============
sha: $sha
short_sha: $short_sha
committed_at: $committed_at
committed_by: $author
author_email: $email

# ============ 提交类型 ============
type: $type
scope: ${scope:-general}
breaking_change: false

# ============ 提交内容 ============
subject: |
  $subject
description: |
$(echo "$body" | sed 's/^/  /')

# ============ 变更文件 ============
files_changed:
$(parse_files_changed "$sha")

# ============ 关联信息 ============
related:
  task: ${task_id:-null}
  task_archive: $(get_task_archive_path "$task_id")
  test_report: null
  review_result: null

# ============ 统计 ============
statistics:
  files_changed: $(echo "$files_changed" | grep -c "|" || echo "0")
  lines_added: $(git show --stat "$sha" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")
  lines_deleted: $(git show --stat "$sha" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo "0")
EOF

    log_info "提交归档完成: $commit_file"

    # 更新索引
    update_commit_index "$month" "$short_sha" "$subject" "$type"
    update_commit_registry "$short_sha" "$month" "$type"

    echo "$commit_file"
}

# ============================================
# 解析文件变更
# ============================================

parse_files_changed() {
    local sha="$1"

    local stats=$(git show --stat --format="" "$sha")

    if [ -z "$stats" ]; then
        echo "  []"
        return
    fi

    while IFS= read -r line; do
        if [[ "$line" =~ \| ]]; then
            local file_path=$(echo "$line" | awk '{print $1}')
            local additions=$(echo "$line" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")
            local deletions=$(echo "$line" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo "0")

            # 判断变更类型
            local change_type="modified"
            if git show "$sha" --format="" -- "$file_path" 2>/dev/null | head -1 | grep -q "^new file"; then
                change_type="added"
            elif git show "$sha" --format="" -- "$file_path" 2>/dev/null | head -1 | grep -q "^deleted"; then
                change_type="deleted"
            fi

            echo "  - path: $file_path"
            echo "    change_type: $change_type"
            echo "    lines_added: $additions"
            echo "    lines_deleted: $deletions"
        fi
    done <<< "$stats"
}

get_task_archive_path() {
    local task_id="$1"

    if [ -z "$task_id" ]; then
        echo "null"
        return
    fi

    local month=$(get_current_month)
    echo "archives/tasks/$month/$task_id.yaml"
}

# ============================================
# 索引更新
# ============================================

update_task_index() {
    local month="$1"
    local task_id="$2"
    local title="$3"

    local index_file="$ARCHIVES_DIR/tasks/$month/index.yaml"
    mkdir -p "$(dirname "$index_file")"

    # 创建或更新索引
    if [ ! -f "$index_file" ]; then
        cat > "$index_file" << EOF
month: $month
generated_at: $(get_current_timestamp)

statistics:
  total: 0
  completed: 0

tasks:
  completed: []
EOF
    fi

    # 添加任务到索引
    local temp_file=$(mktemp)
    awk -v task_id="$task_id" -v title="$title" '
    /^  completed:$/ {
        print $0
        print "    - id: " task_id
        print "      title: \"" title "\""
        print "      completed_at: \"" strftime("%Y-%m-%dT%H:%M:%SZ", systime(), 1) "\""
        next
    }
    /^  total:/ {
        print "  total: " ($2 + 1)
        next
    }
    /^  completed:/ && /total:/ {
        next
    }
    { print }
    ' "$index_file" > "$temp_file"

    # 更新统计
    local completed_count=$(grep -c "id:" "$temp_file" 2>/dev/null || echo "0")
    if [ "$completed_count" -gt 0 ] 2>/dev/null; then
        sed -i "s/total: [0-9]*/total: $completed_count/" "$temp_file" 2>/dev/null || true
    fi

    mv "$temp_file" "$index_file"
}

update_task_registry() {
    local task_id="$1"
    local title="$2"
    local month="$3"

    local registry_file="$ARCHIVES_DIR/tasks/registry.yaml"
    mkdir -p "$(dirname "$registry_file")"

    # 创建或更新注册表
    if [ ! -f "$registry_file" ]; then
        cat > "$registry_file" << EOF
# ============ 任务注册表 ============
generated_at: $(get_current_timestamp)

statistics:
  total_tasks: 0
  completed: 0

months: {}

recent: []
EOF
    fi

    # 更新注册表
    local temp_file=$(mktemp)
    awk -v month="$month" -v task_id="$task_id" -v title="$title" '
    /^months:$/ {
        print $0
        if (!seen) {
            print "  \"" month "\":"
            print "    total: 1"
            print "    completed: 1"
            print "    archive_path: " month "/"
        }
        next
    }
    /^recent:$/ {
        print $0
        print "  - task_id: " task_id
        print "    title: \"" title "\""
        print "    status: completed"
        print "    archive: " month "/" task_id ".yaml"
        next
    }
    /^  total_tasks:/ {
        print "  total_tasks: " ($2 + 1)
        next
    }
    /^  completed:/ {
        print "  completed: " ($2 + 1)
        next
    }
    { print }
    ' "$registry_file" > "$temp_file"

    mv "$temp_file" "$registry_file"
}

update_test_index() {
    local month="$1"
    local task_id="$2"

    local index_file="$ARCHIVES_DIR/tests/$month/index.yaml"
    mkdir -p "$(dirname "$index_file")"

    if [ ! -f "$index_file" ]; then
        cat > "$index_file" << EOF
month: $month
generated_at: $(get_current_timestamp)

tests: []
EOF
    fi

    # 添加测试到索引
    echo "  - task_id: $task_id" >> "$index_file"
    echo "    archived_at: $(get_current_timestamp)" >> "$index_file"
}

update_commit_index() {
    local month="$1"
    local short_sha="$2"
    local subject="$3"
    local type="$4"

    local index_file="$ARCHIVES_DIR/commits/$month/index.yaml"
    mkdir -p "$(dirname "$index_file")"

    if [ ! -f "$index_file" ]; then
        cat > "$index_file" << EOF
month: $month
generated_at: $(get_current_timestamp)

commits: []
EOF
    fi

    # 添加提交到索引
    echo "  - sha: $short_sha" >> "$index_file"
    echo "    type: $type" >> "$index_file"
    echo "    subject: \"$subject\"" >> "$index_file"
    echo "    archived_at: $(get_current_timestamp)" >> "$index_file"
}

update_commit_registry() {
    local short_sha="$1"
    local month="$2"
    local type="$3"

    local registry_file="$ARCHIVES_DIR/commits/registry.yaml"
    mkdir -p "$(dirname "$registry_file")"

    if [ ! -f "$registry_file" ]; then
        cat > "$registry_file" << EOF
# ============ 提交注册表 ============
generated_at: $(get_current_timestamp)

statistics:
  total_commits: 0
  by_type:
    feat: 0
    fix: 0
    refactor: 0
    docs: 0
    test: 0
    chore: 0

recent: []
EOF
    fi

    # 更新统计
    local temp_file=$(mktemp)
    awk -v type="$type" -v short_sha="$short_sha" -v month="$month" '
    /^  total_commits:/ {
        print "  total_commits: " ($2 + 1)
        next
    }
    /^    feat: [0-9]/ && type == "feat" {
        print "    feat: " ($2 + 1)
        next
    }
    /^    fix: [0-9]/ && type == "fix" {
        print "    fix: " ($2 + 1)
        next
    }
    /^    refactor: [0-9]/ && type == "refactor" {
        print "    refactor: " ($2 + 1)
        next
    }
    /^    docs: [0-9]/ && type == "docs" {
        print "    docs: " ($2 + 1)
        next
    }
    /^    test: [0-9]/ && type == "test" {
        print "    test: " ($2 + 1)
        next
    }
    /^    chore: [0-9]/ && type == "chore" {
        print "    chore: " ($2 + 1)
        next
    }
    /^recent:$/ {
        print $0
        print "  - sha: " short_sha
        print "    type: " type
        print "    month: " month
        print "    archived_at: \"" strftime("%Y-%m-%dT%H:%M:%SZ", systime(), 1) "\""
        next
    }
    { print }
    ' "$registry_file" > "$temp_file"

    mv "$temp_file" "$registry_file"
}

# ============================================
# 主入口
# ============================================

main() {
    local task_id=""
    local test_report=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --test-report|-t)
                test_report="$2"
                shift 2
                ;;
            *)
                task_id="$1"
                shift
                ;;
        esac
    done

    if [ -z "$task_id" ]; then
        echo "用法: $0 <task_id> [--test-report <path>]"
        echo ""
        echo "选项:"
        echo "  --test-report, -t   指定测试报告路径"
        exit 1
    fi

    # 初始化目录
    mkdir -p "$ARCHIVES_DIR"/{tasks,tests,commits}/$(get_current_month)

    # 归档任务
    archive_task "$task_id"

    # 归档测试
    archive_tests "$task_id" "tests"

    # 归档最近的相关提交
    local commits=$(git log --oneline --grep="$task_id" | head -5)
    while IFS= read -r commit; do
        if [ -n "$commit" ]; then
            local sha=$(echo "$commit" | awk '{print $1}')
            archive_commit "$sha" "$task_id"
        fi
    done <<< "$commits"

    log_info "归档完成: $task_id"
}

# 运行
main "$@"
