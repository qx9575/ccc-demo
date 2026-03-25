#!/bin/bash
# test-multi-agent.sh - 多 Agent 协作测试
#
# 测试内容：
# 1. 任务认领（单/并发）
# 2. 消息传递
# 3. 心跳检测
# 4. 状态转换
#
# 用法: ./tests/test-multi-agent.sh

set -e

# ============================================
# 测试配置
# ============================================

# 获取测试脚本所在目录，然后定位到 scripts 目录
TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_SCRIPT_DIR")"
SCRIPT_DIR="$PROJECT_ROOT/scripts"

TEST_DIR="${TEST_DIR:-.agent/test}"
TEST_AGENT_1="test-coder-1"
TEST_AGENT_2="test-coder-2"
TEST_TASK_1="test-task-001"
TEST_TASK_2="test-task-002"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

log_test() { echo -e "${CYAN}[TEST]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $1"; }

# ============================================
# 测试准备
# ============================================

setup() {
    log_test "设置测试环境..."

    # 加载模块
    source "$SCRIPT_DIR/agent-coordinator.sh"
    source "$SCRIPT_DIR/agent-messaging.sh"
    source "$SCRIPT_DIR/agent-heartbeat.sh"

    # 创建测试目录
    mkdir -p "$TEST_DIR"
    mkdir -p .agent/tasks/pending
    mkdir -p .agent/tasks/in-progress
    mkdir -p .agent/tasks/review
    mkdir -p .agent/tasks/completed
    mkdir -p .agent/messages/inbox
    mkdir -p .agent/heartbeat

    # 创建测试任务
    cat > ".agent/tasks/pending/${TEST_TASK_1}.yaml" << EOF
id: $TEST_TASK_1
title: 测试任务 1
priority: P1
role: coder
status: pending
created_at: $(date -Iseconds)
created_by: test-pm
description: |
  这是一个测试任务
EOF

    cat > ".agent/tasks/pending/${TEST_TASK_2}.yaml" << EOF
id: $TEST_TASK_2
title: 测试任务 2
priority: P2
role: coder
status: pending
created_at: $(date -Iseconds)
created_by: test-pm
description: |
  这是另一个测试任务
EOF

    log_test "测试环境设置完成"
}

teardown() {
    log_test "清理测试环境..."

    # 删除测试文件
    rm -f ".agent/tasks/pending/${TEST_TASK_1}.yaml"
    rm -f ".agent/tasks/pending/${TEST_TASK_2}.yaml"
    rm -f ".agent/tasks/in-progress/${TEST_TASK_1}.yaml"
    rm -f ".agent/tasks/in-progress/${TEST_TASK_2}.yaml"
    rm -f ".agent/tasks/in-progress/${TEST_TASK_1}.lock"
    rm -f ".agent/tasks/in-progress/${TEST_TASK_2}.lock"
    rm -f ".agent/tasks/review/${TEST_TASK_1}.yaml"
    rm -f ".agent/tasks/completed/${TEST_TASK_1}.yaml"
    rm -rf ".agent/messages/inbox/${TEST_AGENT_1}"
    rm -rf ".agent/messages/inbox/${TEST_AGENT_2}"
    rm -f ".agent/heartbeat/${TEST_AGENT_1}.yaml"
    rm -f ".agent/heartbeat/${TEST_AGENT_2}.yaml"
    rm -rf "$TEST_DIR"

    log_test "测试环境清理完成"
}

# ============================================
# 测试用例
# ============================================

# 测试任务状态查询
test_get_task_state() {
    log_test "测试: 获取任务状态"

    local state=$(get_task_state "$TEST_TASK_1")

    if [ "$state" = "pending" ]; then
        log_pass "任务状态正确: $state"
    else
        log_fail "任务状态错误: 期望 pending, 实际 $state"
    fi
}

# 测试创建锁文件
test_create_lock_file() {
    log_test "测试: 创建锁文件"

    local lock_file=$(create_lock_file "$TEST_TASK_1" "$TEST_AGENT_1")

    if [ -f "$lock_file" ]; then
        # 验证锁文件内容
        local agent=$(grep "^agent_id:" "$lock_file" | awk '{print $2}')
        local task=$(grep "^task_id:" "$lock_file" | awk '{print $2}')

        if [ "$agent" = "$TEST_AGENT_1" ] && [ "$task" = "$TEST_TASK_1" ]; then
            log_pass "锁文件创建成功: $lock_file"
        else
            log_fail "锁文件内容错误"
        fi

        # 清理
        rm -f "$lock_file"
    else
        log_fail "锁文件创建失败"
    fi
}

# 测试锁有效性检查
test_lock_validity() {
    log_test "测试: 锁有效性检查"

    # 创建有效锁
    create_lock_file "$TEST_TASK_1" "$TEST_AGENT_1"

    if check_lock_valid "$TEST_TASK_1"; then
        log_pass "有效锁检查通过"
    else
        log_fail "有效锁检查失败"
    fi

    # 创建过期锁
    cat > ".agent/tasks/in-progress/${TEST_TASK_2}.lock" << EOF
agent_id: $TEST_AGENT_2
locked_at: $(date -Iseconds -d "3 hours ago")
expires_at: $(date -Iseconds -d "1 hour ago")
heartbeat: $(date -Iseconds -d "2 hours ago")
task_id: $TEST_TASK_2
EOF

    if ! check_lock_valid "$TEST_TASK_2"; then
        log_pass "过期锁检查通过"
    else
        log_fail "过期锁检查失败"
    fi

    # 清理
    rm -f ".agent/tasks/in-progress/${TEST_TASK_1}.lock"
    rm -f ".agent/tasks/in-progress/${TEST_TASK_2}.lock"
}

# 测试心跳创建
test_heartbeat() {
    log_test "测试: 心跳创建"

    export AGENT_ID="$TEST_AGENT_1"
    export AGENT_ROLE="coder"

    create_heartbeat_file "$TEST_AGENT_1"

    local hb_file=".agent/heartbeat/${TEST_AGENT_1}.yaml"

    if [ -f "$hb_file" ]; then
        local role=$(parse_heartbeat "$TEST_AGENT_1" "role")
        local status=$(parse_heartbeat "$TEST_AGENT_1" "status")

        if [ "$role" = "coder" ] && [ "$status" = "active" ]; then
            log_pass "心跳文件创建成功"
        else
            log_fail "心跳文件内容错误: role=$role, status=$status"
        fi
    else
        log_fail "心跳文件创建失败"
    fi
}

# 测试心跳更新
test_heartbeat_update() {
    log_test "测试: 心跳更新"

    update_heartbeat "$TEST_AGENT_1" "idle" ""

    local status=$(parse_heartbeat "$TEST_AGENT_1" "status")

    if [ "$status" = "idle" ]; then
        log_pass "心跳更新成功: status=$status"
    else
        log_fail "心跳更新失败: status=$status"
    fi
}

# 测试 Agent 在线检测
test_agent_online() {
    log_test "测试: Agent 在线检测"

    # 刚创建的心跳应该在线
    if is_agent_online "$TEST_AGENT_1"; then
        log_pass "Agent 在线检测正确"
    else
        log_fail "Agent 应该在线但检测为离线"
    fi

    # 创建一个过期的心跳
    cat > ".agent/heartbeat/${TEST_AGENT_2}.yaml" << EOF
agent_id: $TEST_AGENT_2
role: coder
status: active
current_task: null
last_heartbeat: $(date -Iseconds -d "1 hour ago")
started_at: $(date -Iseconds -d "2 hours ago")
EOF

    if ! is_agent_online "$TEST_AGENT_2"; then
        log_pass "过期 Agent 检测为离线"
    else
        log_fail "过期 Agent 应该离线"
    fi
}

# 测试消息发送
test_message_send() {
    log_test "测试: 消息发送"

    local msg_id=$(send_message "$TEST_AGENT_1" "$TEST_AGENT_2" "test_message" "test content: hello world" "normal" "false")

    if [ -n "$msg_id" ]; then
        # 检查消息是否在收件箱
        local inbox_file=".agent/messages/inbox/${TEST_AGENT_2}/${msg_id}.yaml"

        if [ -f "$inbox_file" ]; then
            local from=$(parse_message "$inbox_file" "from")
            local to=$(parse_message "$inbox_file" "to")
            local type=$(parse_message "$inbox_file" "type")

            if [ "$from" = "$TEST_AGENT_1" ] && [ "$to" = "$TEST_AGENT_2" ] && [ "$type" = "test_message" ]; then
                log_pass "消息发送成功: $msg_id"
            else
                log_fail "消息内容错误"
            fi
        else
            log_fail "消息未出现在收件箱"
        fi
    else
        log_fail "消息发送失败"
    fi
}

# 测试消息读取
test_message_read() {
    log_test "测试: 消息读取"

    # 获取未读消息
    local unread=$(get_unread_messages "$TEST_AGENT_2")

    if [ -n "$unread" ]; then
        log_pass "获取未读消息成功"

        # 标记已读
        mark_message_read "$unread"

        # 再次获取未读消息
        unread=$(get_unread_messages "$TEST_AGENT_2")

        if [ -z "$unread" ]; then
            log_pass "消息标记已读成功"
        else
            log_fail "消息标记已读失败"
        fi
    else
        log_fail "未找到未读消息"
    fi
}

# 测试任务分配消息
test_task_assign_message() {
    log_test "测试: 任务分配消息"

    local msg_id=$(send_task_assign "$TEST_AGENT_1" "$TEST_AGENT_2" "$TEST_TASK_1" "测试任务" "P1")

    if [ -n "$msg_id" ]; then
        local inbox_file=".agent/messages/inbox/${TEST_AGENT_2}/${msg_id}.yaml"

        if [ -f "$inbox_file" ]; then
            local type=$(parse_message "$inbox_file" "type")
            local requires_ack=$(parse_message "$inbox_file" "requires_ack")

            if [ "$type" = "task_assign" ] && [ "$requires_ack" = "true" ]; then
                log_pass "任务分配消息发送成功"
            else
                log_fail "任务分配消息格式错误"
            fi
        else
            log_fail "任务分配消息未找到"
        fi
    else
        log_fail "任务分配消息发送失败"
    fi
}

# 测试审查请求消息
test_review_request_message() {
    log_test "测试: 审查请求消息"

    local msg_id=$(send_review_request "$TEST_AGENT_1" "$TEST_AGENT_2" "$TEST_TASK_1" "请审查代码" "src/main.py tests/test_main.py")

    if [ -n "$msg_id" ]; then
        local inbox_file=".agent/messages/inbox/${TEST_AGENT_2}/${msg_id}.yaml"

        if [ -f "$inbox_file" ]; then
            local type=$(parse_message "$inbox_file" "type")
            local priority=$(parse_message "$inbox_file" "priority")

            if [ "$type" = "review_request" ] && [ "$priority" = "high" ]; then
                log_pass "审查请求消息发送成功"
            else
                log_fail "审查请求消息格式错误"
            fi
        else
            log_fail "审查请求消息未找到"
        fi
    else
        log_fail "审查请求消息发送失败"
    fi
}

# 测试审查结果消息
test_review_result_message() {
    log_test "测试: 审查结果消息"

    local msg_id=$(send_review_result "$TEST_AGENT_1" "$TEST_AGENT_2" "$TEST_TASK_1" "approved" "代码质量良好")

    if [ -n "$msg_id" ]; then
        local inbox_file=".agent/messages/inbox/${TEST_AGENT_2}/${msg_id}.yaml"

        if [ -f "$inbox_file" ]; then
            local type=$(parse_message "$inbox_file" "type")
            local priority=$(parse_message "$inbox_file" "priority")

            if [ "$type" = "review_result" ] && [ "$priority" = "high" ]; then
                log_pass "审查结果消息发送成功"
            else
                log_fail "审查结果消息格式错误"
            fi
        else
            log_fail "审查结果消息未找到"
        fi
    else
        log_fail "审查结果消息发送失败"
    fi
}

# 测试任务状态转换
test_task_state_transition() {
    log_test "测试: 任务状态转换"

    # pending -> in-progress
    update_task_state "$TEST_TASK_1" "in-progress" "$TEST_AGENT_1"

    local state=$(get_task_state "$TEST_TASK_1")

    if [ "$state" = "in-progress" ]; then
        log_pass "状态转换成功: pending -> in-progress"
    else
        log_fail "状态转换失败: $state"
    fi

    # in-progress -> review
    update_task_state "$TEST_TASK_1" "review" "$TEST_AGENT_1"

    state=$(get_task_state "$TEST_TASK_1")

    if [ "$state" = "review" ]; then
        log_pass "状态转换成功: in-progress -> review"
    else
        log_fail "状态转换失败: $state"
    fi

    # review -> completed
    update_task_state "$TEST_TASK_1" "completed" "$TEST_AGENT_1"

    state=$(get_task_state "$TEST_TASK_1")

    if [ "$state" = "completed" ]; then
        log_pass "状态转换成功: review -> completed"
    else
        log_fail "状态转换失败: $state"
    fi
}

# 测试健康报告生成
test_health_report() {
    log_test "测试: 健康报告生成"

    local report_file="$TEST_DIR/health-report.yaml"
    generate_health_report "$report_file"

    if [ -f "$report_file" ]; then
        if grep -q "generated_at:" "$report_file" && grep -q "agents:" "$report_file"; then
            log_pass "健康报告生成成功"
        else
            log_fail "健康报告格式错误"
        fi
    else
        log_fail "健康报告生成失败"
    fi
}

# ============================================
# 运行测试
# ============================================

main() {
    echo "=============================================="
    echo "多 Agent 协作测试套件"
    echo "=============================================="
    echo ""

    # 设置测试环境
    setup

    echo ""
    echo "=============================================="
    echo "运行测试用例"
    echo "=============================================="
    echo ""

    # 任务协调测试
    test_get_task_state
    test_create_lock_file
    test_lock_validity

    echo ""

    # 心跳测试
    test_heartbeat
    test_heartbeat_update
    test_agent_online

    echo ""

    # 消息传递测试
    test_message_send
    test_message_read
    test_task_assign_message
    test_review_request_message
    test_review_result_message

    echo ""

    # 状态转换测试
    test_task_state_transition

    echo ""

    # 健康报告测试
    test_health_report

    echo ""
    echo "=============================================="
    echo "测试结果"
    echo "=============================================="
    echo -e "${GREEN}通过: $TESTS_PASSED${NC}"
    echo -e "${RED}失败: $TESTS_FAILED${NC}"
    echo ""

    # 清理测试环境
    teardown

    # 返回退出码
    if [ $TESTS_FAILED -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# 运行主函数
main "$@"
