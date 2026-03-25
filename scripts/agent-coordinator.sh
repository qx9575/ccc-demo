#!/bin/bash
# agent-coordinator.sh - Multi-Agent Coordination Functions
#
# Provides shared coordination primitives:
# - Task claiming with atomic locks
# - Dependency checking
# - Task state transitions
# - Git-based synchronization
#
# Usage: source scripts/agent-coordinator.sh

set -e

# ============================================
# Configuration
# ============================================

COORDINATOR_DIR="${COORDINATOR_DIR:-.agent}"
TASKS_DIR="${TASKS_DIR:-$COORDINATOR_DIR/tasks}"
LOCK_TIMEOUT="${LOCK_TIMEOUT:-7200}"  # 2 hours default
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-60}"

# Task states
STATE_PENDING="pending"
STATE_ASSIGNED="assigned"
STATE_IN_PROGRESS="in_progress"
STATE_REVIEW="review"
STATE_ARCHIVED="archived"
STATE_CHANGES_REQUESTED="changes_requested"

# ============================================
# Color Output
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_coord() { echo -e "${CYAN}[COORD]${NC} $1"; }
log_lock() { echo -e "${YELLOW}[LOCK]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================
# Directory Initialization
# ============================================

init_coordinator_dirs() {
    mkdir -p "$TASKS_DIR/pending"
    mkdir -p "$TASKS_DIR/assigned"
    mkdir -p "$TASKS_DIR/in-progress"
    mkdir -p "$TASKS_DIR/review"
    mkdir -p "$COORDINATOR_DIR/archives/tasks"
    mkdir -p "$COORDINATOR_DIR/archives/tests"
    mkdir -p "$COORDINATOR_DIR/archives/commits"
    mkdir -p "$COORDINATOR_DIR/messages/inbox"
    mkdir -p "$COORDINATOR_DIR/messages/outbox"
    mkdir -p "$COORDINATOR_DIR/messages/archive"
    mkdir -p "$COORDINATOR_DIR/heartbeat"
    mkdir -p "$COORDINATOR_DIR/coordination"
    mkdir -p "$COORDINATOR_DIR/conflicts"
    mkdir -p "$COORDINATOR_DIR/notifications"
    mkdir -p "$COORDINATOR_DIR/shared-memory"
    log_coord "目录结构初始化完成"
}

# ============================================
# Git Synchronization
# ============================================

git_sync_pull() {
    local branch="${1:-main}"
    log_coord "拉取最新代码 ($branch)..." >&2
    git fetch origin "$branch" -q 2>/dev/null || true
    git pull --rebase origin "$branch" -q 2>/dev/null || true
}

git_sync_push() {
    local branch="${1:-main}"
    local message="${2:-sync}"
    log_coord "推送代码 ($branch)..."

    git add -A 2>/dev/null || true
    git commit -m "$message" --allow-empty 2>/dev/null || true

    if git push origin "$branch" 2>&1; then
        log_success "推送成功"
        return 0
    else
        log_error "推送失败，需要重试"
        return 1
    fi
}

git_atomic_push() {
    local branch="${1:-main}"
    local message="${2:-atomic update}"
    local max_retries=5
    local retry_delay=2

    for i in $(seq 1 $max_retries); do
        # Pull first
        git pull --rebase origin "$branch" -q 2>/dev/null || true

        # Check for conflicts
        local conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l)
        if [ "$conflicts" -gt 0 ]; then
            log_error "存在冲突，无法完成原子操作"
            return 1
        fi

        # Try push
        if git push origin "$branch" 2>&1; then
            log_success "原子推送成功"
            return 0
        fi

        log_coord "推送冲突，重试 ($i/$max_retries)..."
        sleep $retry_delay
        retry_delay=$((retry_delay * 2))
    done

    log_error "原子推送失败，已达最大重试次数"
    return 1
}

# ============================================
# Task State Management
# ============================================

get_task_state() {
    local task_id="$1"

    # First check for task yaml files in each state directory
    for state in pending assigned in-progress review; do
        if [ -f "$TASKS_DIR/$state/${task_id}.yaml" ]; then
            echo "$state"
            return 0
        fi
    done

    # Then check for lock files (only in in-progress)
    if [ -f "$TASKS_DIR/in-progress/${task_id}.lock" ]; then
        echo "in-progress"  # Locked means in-progress
        return 0
    fi

    # Check archives
    local month=$(date +"%Y-%m")
    if [ -f "$COORDINATOR_DIR/archives/tasks/$month/${task_id}.yaml" ]; then
        echo "archived"
        return 0
    fi

    return 1
}

get_task_file() {
    local task_id="$1"
    local state=$(get_task_state "$task_id")

    if [ -n "$state" ]; then
        echo "$TASKS_DIR/$state/${task_id}.yaml"
        return 0
    fi

    return 1
}

update_task_state() {
    local task_id="$1"
    local new_state="$2"
    local agent_id="${3:-$AGENT_ID}"

    local current_state=$(get_task_state "$task_id")
    local current_file="$TASKS_DIR/$current_state/${task_id}.yaml"
    local target_dir="$TASKS_DIR/$new_state"

    mkdir -p "$target_dir"

    # Update task file with new state and metadata
    if [ -f "$current_file" ]; then
        # Update state field
        sed -i "s/^status:.*/status: $new_state/" "$current_file"

        # Add state change metadata
        echo "" >> "$current_file"
        echo "# State transition at $(date -Iseconds)" >> "$current_file"
        echo "updated_at: $(date -Iseconds)" >> "$current_file"
        echo "updated_by: $agent_id" >> "$current_file"

        # Move to new state directory
        git mv "$current_file" "$target_dir/" 2>/dev/null || \
            mv "$current_file" "$target_dir/"

        log_coord "任务状态更新: $task_id [$current_state -> $new_state]"
        return 0
    else
        log_error "任务文件不存在: $task_id"
        return 1
    fi
}

# ============================================
# Task Claiming (Atomic Lock)
# ============================================

# Helper function to get ISO timestamp (BusyBox compatible)
get_iso_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Helper function to get future timestamp (BusyBox compatible)
get_future_timestamp() {
    local seconds="$1"
    # BusyBox date uses different syntax
    if date -u +"%Y-%m-%dT%H:%M:%SZ" -d "@$(( $(date +%s) + seconds ))" 2>/dev/null; then
        return
    fi
    # Fallback: GNU date syntax
    date -Iseconds -d "+${seconds} seconds" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ"
}

create_lock_file() {
    local task_id="$1"
    local agent_id="${2:-$AGENT_ID}"
    local lock_file="$TASKS_DIR/in-progress/${task_id}.lock"
    local now_ts=$(get_iso_timestamp)
    local expire_ts=$(get_future_timestamp "$LOCK_TIMEOUT")

    cat > "$lock_file" << EOF
agent_id: $agent_id
locked_at: $now_ts
expires_at: $expire_ts
heartbeat: $now_ts
task_id: $task_id
EOF

    echo "$lock_file"
}

check_lock_valid() {
    local task_id="$1"
    local lock_file="$TASKS_DIR/in-progress/${task_id}.lock"

    if [ ! -f "$lock_file" ]; then
        return 1  # No lock
    fi

    # Check expiration
    local expires=$(grep "^expires_at:" "$lock_file" | awk '{print $2}')
    local expires_ts=$(date -d "$expires" +%s 2>/dev/null || echo 0)
    local now_ts=$(date +%s)

    if [ $now_ts -gt $expires_ts ]; then
        log_lock "锁已过期: $task_id" >&2
        rm -f "$lock_file"
        return 1  # Expired
    fi

    return 0  # Valid lock
}

get_lock_owner() {
    local task_id="$1"
    local lock_file="$TASKS_DIR/in-progress/${task_id}.lock"

    if [ -f "$lock_file" ]; then
        grep "^agent_id:" "$lock_file" | awk '{print $2}'
    fi
}

update_heartbeat() {
    local task_id="$1"
    local lock_file="$TASKS_DIR/in-progress/${task_id}.lock"

    if [ -f "$lock_file" ]; then
        sed -i "s/^heartbeat:.*/heartbeat: $(date -Iseconds)/" "$lock_file"
    fi
}

claim_task() {
    local task_id="$1"
    local agent_id="${2:-$AGENT_ID}"

    log_coord "尝试认领任务: $task_id" >&2

    # 1. Pull latest
    git_sync_pull

    # 2. Check if task exists and is pending
    local state=$(get_task_state "$task_id")
    if [ "$state" != "pending" ]; then
        log_error "任务不可用 (状态: $state)" >&2
        return 1
    fi

    # 3. Check if already locked
    if check_lock_valid "$task_id"; then
        local owner=$(get_lock_owner "$task_id")
        log_error "任务已被锁定: $owner"
        return 1
    fi

    # 4. Create lock file atomically
    local lock_file=$(create_lock_file "$task_id" "$agent_id")

    # 5. Move task to in-progress
    local task_file="$TASKS_DIR/pending/${task_id}.yaml"
    if [ -f "$task_file" ]; then
        mkdir -p "$TASKS_DIR/in-progress"
        git mv "$task_file" "$TASKS_DIR/in-progress/" 2>/dev/null || \
            mv "$task_file" "$TASKS_DIR/in-progress/"
    fi

    # 6. Git push to claim
    git add "$TASKS_DIR/" 2>/dev/null || true
    git commit -m "chore: 认领任务 $task_id by $agent_id" 2>/dev/null || true

    if git_atomic_push "main" "claim: $task_id by $agent_id"; then
        log_success "成功认领任务: $task_id"
        return 0
    else
        # Push failed, rollback
        log_error "认领失败，回滚"
        rm -f "$lock_file"
        git checkout -- "$TASKS_DIR/" 2>/dev/null || true
        git_sync_pull
        return 1
    fi
}

release_task() {
    local task_id="$1"
    local agent_id="${2:-$AGENT_ID}"
    local reason="${3:-released}"

    log_coord "释放任务: $task_id (原因: $reason)"

    local lock_file="$TASKS_DIR/in-progress/${task_id}.lock"
    rm -f "$lock_file"

    # Move task back to pending
    local task_file="$TASKS_DIR/in-progress/${task_id}.yaml"
    if [ -f "$task_file" ]; then
        sed -i "s/^status:.*/status: pending/" "$task_file"
        git mv "$task_file" "$TASKS_DIR/pending/" 2>/dev/null || \
            mv "$task_file" "$TASKS_DIR/pending/"
    fi

    git add "$TASKS_DIR/" 2>/dev/null || true
    git commit -m "chore: 释放任务 $task_id by $agent_id ($reason)" 2>/dev/null || true
    git_atomic_push "main" "release: $task_id"
}

# ============================================
# Task Dependencies
# ============================================

check_dependencies() {
    local task_id="$1"
    local task_file=$(get_task_file "$task_id")

    if [ ! -f "$task_file" ]; then
        return 1
    fi

    # Extract dependencies from task file
    local deps=$(grep "^  - " "$task_file" 2>/dev/null | grep -A100 "dependencies:" | head -10)

    for dep in $deps; do
        if [ -n "$dep" ] && [ "$dep" != "dependencies:" ]; then
            local dep_state=$(get_task_state "$dep")
            # 依赖必须已完成（归档状态）
            if [ "$dep_state" != "archived" ] && [ "$dep_state" != "completed" ]; then
                log_coord "依赖未满足: $dep (状态: $dep_state)" >&2
                return 1
            fi
        fi
    done

    return 0
}

# ============================================
# Task Discovery
# ============================================

find_available_tasks() {
    local role="${1:-}"
    local limit="${2:-10}"

    git_sync_pull

    local count=0
    for task_file in "$TASKS_DIR/pending"/*.yaml; do
        # Skip if no matches (glob returned literal pattern)
        [ -e "$task_file" ] || continue
        if [ -f "$task_file" ]; then
            local task_id=$(basename "$task_file" .yaml)

            # Check if locked
            if check_lock_valid "$task_id"; then
                continue
            fi

            # Check role requirement
            if [ -n "$role" ]; then
                local task_role=$(grep "^role:" "$task_file" | awk '{print $2}')
                if [ -n "$task_role" ] && [ "$task_role" != "$role" ]; then
                    continue
                fi
            fi

            # Check dependencies
            if ! check_dependencies "$task_id"; then
                continue
            fi

            echo "$task_id"
            count=$((count + 1))

            if [ $count -ge $limit ]; then
                break
            fi
        fi
    done
}

# ============================================
# Task Creation
# ============================================

create_task() {
    local task_id="$1"
    local title="$2"
    local description="$3"
    local role="${4:-coder}"
    local priority="${5:-P1}"
    local created_by="${6:-$AGENT_ID}"

    local task_file="$TASKS_DIR/pending/${task_id}.yaml"

    cat > "$task_file" << EOF
id: $task_id
title: $title
priority: $priority
role: $role
status: pending
created_at: $(date -Iseconds)
created_by: $created_by

acceptance_criteria:
  - TBD

description: |
  $description
EOF

    log_coord "创建任务: $task_id"
    git add "$task_file"
    git commit -m "chore: 创建任务 $task_id - $title"
    git_atomic_push "main" "create task: $task_id"

    echo "$task_file"
}

# ============================================
# Review Flow
# ============================================

submit_for_review() {
    local task_id="$1"
    local agent_id="${2:-$AGENT_ID}"

    log_coord "提交任务进行审查: $task_id"

    # Update state to review
    update_task_state "$task_id" "review" "$agent_id"

    # Commit changes
    git add -A 2>/dev/null || true
    git commit -m "chore: 提交审查 $task_id by $agent_id" 2>/dev/null || true
    git_atomic_push "main" "submit for review: $task_id"
}

approve_task() {
    local task_id="$1"
    local reviewer_id="${2:-$AGENT_ID}"

    log_coord "批准任务: $task_id"

    # 获取任务文件
    local task_file="$TASKS_DIR/review/${task_id}.yaml"

    if [ ! -f "$task_file" ]; then
        # 尝试其他目录
        for state in in-progress pending; do
            if [ -f "$TASKS_DIR/$state/${task_id}.yaml" ]; then
                task_file="$TASKS_DIR/$state/${task_id}.yaml"
                break
            fi
        done
    fi

    if [ ! -f "$task_file" ]; then
        log_error "任务文件不存在: $task_id"
        return 1
    fi

    # 添加审查元数据
    echo "" >> "$task_file"
    echo "review:" >> "$task_file"
    echo "  approved_by: $reviewer_id" >> "$task_file"
    echo "  approved_at: $(date -Iseconds)" >> "$task_file"
    echo "status: completed" >> "$task_file"

    # 调用归档脚本（如果可用）
    if [ -f "/app/archive-task.sh" ]; then
        /app/archive-task.sh "$task_id" 2>/dev/null || true
    elif [ -f "./scripts/archive-task.sh" ]; then
        ./scripts/archive-task.sh "$task_id" 2>/dev/null || true
    else
        # 归档脚本不可用，直接删除任务文件
        rm -f "$task_file"
        log_coord "任务完成（归档脚本不可用）: $task_id"
    fi

    git add -A 2>/dev/null || true
    git commit -m "chore: 批准并归档任务 $task_id by $reviewer_id"
    git_atomic_push "main" "approve and archive: $task_id"

    log_coord "任务已归档: $task_id"
}

reject_task() {
    local task_id="$1"
    local reviewer_id="${2:-$AGENT_ID}"
    local reason="${3:-需要修改}"

    log_coord "驳回任务: $task_id (原因: $reason)"

    # Update state to changes_requested (back to in-progress)
    local task_file="$TASKS_DIR/review/${task_id}.yaml"
    if [ -f "$task_file" ]; then
        sed -i "s/^status:.*/status: changes_requested/" "$task_file"
        echo "" >> "$task_file"
        echo "review:" >> "$task_file"
        echo "  rejected_by: $reviewer_id" >> "$task_file"
        echo "  rejected_at: $(date -Iseconds)" >> "$task_file"
        echo "  rejection_reason: $reason" >> "$task_file"

        git mv "$task_file" "$TASKS_DIR/in-progress/" 2>/dev/null || \
            mv "$task_file" "$TASKS_DIR/in-progress/"
    fi

    git add "$TASKS_DIR/"
    git commit -m "chore: 驳回任务 $task_id - $reason"
    git_atomic_push "main" "reject: $task_id"
}

# ============================================
# Utility Functions
# ============================================

list_tasks_by_state() {
    local state="$1"

    for task_file in "$TASKS_DIR/$state"/*.yaml; do
        [ -e "$task_file" ] || continue
        if [ -f "$task_file" ]; then
            local task_id=$(basename "$task_file" .yaml)
            local title=$(grep "^title:" "$task_file" | cut -d: -f2- | sed 's/^ *//')
            echo "$task_id: $title"
        fi
    done
}

show_task() {
    local task_id="$1"
    local task_file=$(get_task_file "$task_id")

    if [ -f "$task_file" ]; then
        echo "=== 任务: $task_id ==="
        echo "状态: $(get_task_state $task_id)"
        cat "$task_file"
    else
        log_error "任务不存在: $task_id"
    fi
}

# Initialize directories when sourced
init_coordinator_dirs 2>/dev/null || true
