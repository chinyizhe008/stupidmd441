#!/bin/bash
# keepalive.sh - 在容器启动后持续运行，防止 Codespace 因闲置而休眠

while true; do
    # 每 5 分钟向健康检查端点发送请求
    curl -s "http://localhost:8080/health" > /dev/null 2>&1
    curl -s "http://localhost:5000/health" > /dev/null 2>&1
    sleep 300  # 5 分钟
done
