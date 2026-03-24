# Agent v0.1 - 最小镜像
# 基于 Alpine Linux，体积 < 100MB

FROM alpine:3.19

LABEL maintainer="agent-framework"
LABEL version="v0.1"
LABEL description="Agent v0.1 MVP - CLI 交互模式"

# 安装依赖
RUN apk add --no-cache \
    bash \
    curl \
    git \
    ca-certificates \
    tzdata \
    jq \
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

# 复制脚本
COPY scripts/agent-v0.1.sh /app/agent-v0.1.sh
COPY scripts/agent-loop-with-conflict-recovery.sh /app/agent-loop-with-conflict-recovery.sh
COPY roles/ /app/roles/

RUN chmod +x /app/*.sh

# 创建必要目录
RUN mkdir -p /workspace/.agent/{tasks,conflicts,notifications,shared-memory}

# 入口
ENTRYPOINT ["/app/agent-v0.1.sh"]
CMD ["--help"]
