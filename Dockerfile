# Agent v0.2 - 多 Agent 协作
# 基于 Alpine Linux，支持 PM/Coder/Reviewer 三个角色

FROM alpine:3.19

LABEL maintainer="agent-framework"
LABEL version="v0.2"
LABEL description="Agent v0.2 - 多 Agent 协作模式"

# 安装依赖
RUN apk add --no-cache \
    bash \
    curl \
    git \
    git-lfs \
    openssh-client \
    ca-certificates \
    tzdata \
    jq \
    yq \
    && rm -rf /var/cache/apk/*

# 创建非 root 用户（可选，v0.5 后启用）
# RUN addgroup -S agentgroup && adduser -S agentuser -G agentgroup

# 设置工作目录
WORKDIR /workspace

# 环境变量
ENV AGENT_ID=""
ENV AGENT_ROLE="coder"
ENV AGENT_NAME="程序员"
ENV OPENAI_API_KEY=""
ENV OPENAI_BASE_URL="https://maas-api.ai-yuanjing.com/openapi/compatible-mode/v1"
ENV OPENAI_MODEL="glm-5"
ENV WORKSPACE="/workspace"
ENV POLL_INTERVAL="30"

# 复制脚本
# v0.1 脚本（保留向后兼容）
COPY scripts/agent-v0.1.sh /app/agent-v0.1.sh
COPY scripts/agent-loop-with-conflict-recovery.sh /app/agent-loop-with-conflict-recovery.sh

# v0.2 脚本（多 Agent 协作）
COPY scripts/agent-coordinator.sh /app/agent-coordinator.sh
COPY scripts/agent-messaging.sh /app/agent-messaging.sh
COPY scripts/agent-heartbeat.sh /app/agent-heartbeat.sh
COPY scripts/agent-v0.2.sh /app/agent-v0.2.sh
COPY scripts/agent-pm-loop.sh /app/agent-pm-loop.sh
COPY scripts/agent-coder-loop.sh /app/agent-coder-loop.sh
COPY scripts/agent-reviewer-loop.sh /app/agent-reviewer-loop.sh

# 归档脚本
COPY scripts/archive-task.sh /app/archive-task.sh
COPY scripts/archive-utils.sh /app/archive-utils.sh

# Git 提交模板
COPY .git-commit-template /workspace/.git-commit-template

# 复制角色配置
COPY .agent/roles/ /app/roles/

# 设置执行权限
RUN chmod +x /app/*.sh

# 创建必要目录
RUN mkdir -p /workspace/.agent/{tasks,conflicts,notifications,shared-memory} \
    && mkdir -p /workspace/.agent/tasks/{pending,assigned,in-progress,review,completed} \
    && mkdir -p /workspace/.agent/messages/{inbox,outbox,archive} \
    && mkdir -p /workspace/.agent/heartbeat \
    && mkdir -p /workspace/.agent/coordination \
    && mkdir -p /workspace/.agent/archives/{tasks,tests,commits}

# 入口（默认使用 v0.2）
ENTRYPOINT ["/app/agent-v0.2.sh"]
# 默认启动交互模式（无参数）
