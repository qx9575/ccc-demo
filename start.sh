#!/bin/bash
# start.sh - 启动 Agent v0.1

set -e

echo "=============================================="
echo "Agent v0.1 启动脚本"
echo "=============================================="

# 检查环境变量
if [ -z "$OPENAI_API_KEY" ]; then
    echo "错误: 请设置 OPENAI_API_KEY 环境变量"
    echo ""
    echo "用法:"
    echo "  export OPENAI_API_KEY=your_key"
    echo "  ./start.sh"
    echo ""
    echo "或:"
    echo "  OPENAI_API_KEY=your_key ./start.sh"
    exit 1
fi

# 设置默认值
export OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://maas-api.ai-yuanjing.com/openapi/compatible-mode/v1}"
export OPENAI_MODEL="${OPENAI_MODEL:-glm-5}"
export AGENT_ROLE="${AGENT_ROLE:-coder}"
export AGENT_NAME="${AGENT_NAME:-程序员}"

echo "API 端点: $OPENAI_BASE_URL"
echo "模型: $OPENAI_MODEL"
echo "角色: $AGENT_ROLE"
echo ""

# 启动方式选择
echo "选择启动方式:"
echo "  1) 直接运行脚本"
echo "  2) Docker 容器"
echo "  3) Docker Compose"
echo ""
read -p "请选择 [1-3]: " choice

case $choice in
    1)
        echo "启动脚本..."
        chmod +x scripts/agent-v0.1.sh
        exec ./scripts/agent-v0.1.sh
        ;;
    2)
        echo "构建 Docker 镜像..."
        docker build -t agent-v0.1:latest .
        echo ""
        echo "启动容器..."
        docker run -it --rm \
            -e OPENAI_API_KEY="$OPENAI_API_KEY" \
            -e OPENAI_BASE_URL="$OPENAI_BASE_URL" \
            -e OPENAI_MODEL="$OPENAI_MODEL" \
            -e AGENT_ROLE="$AGENT_ROLE" \
            -e AGENT_NAME="$AGENT_NAME" \
            -v "$(pwd):/workspace" \
            -w /workspace \
            agent-v0.1:latest
        ;;
    3)
        echo "启动 Docker Compose..."
        docker-compose up --build
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac
