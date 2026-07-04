#!/bin/bash

# 1. Basic system setup
sudo apt-get update && sudo apt-get install -y git wget python3-pip

# 2. Install ProjectDiscovery tools (Subfinder & Nuclei)
#    (Go is already installed via the devcontainer feature)
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/projectdiscovery/nuclei/v2/cmd/nuclei@latest
# Add Go binaries to PATH so they can be run directly
export PATH=$PATH:$(go env GOPATH)/bin

# 3. Install the LLM runner and server
pip install llama-cpp-python fastapi uvicorn huggingface_hub

# 4. Download the Kimi-K2.6 GGUF model from Hugging Face (free)
python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='moonshotai/Kimi-K2.6-GGUF', filename='kimi-k2.6-q4_k_m.gguf', local_dir='.')
"

# 5. Launch the API server on port 8080 (publicly forwarded)
python3 -m llama_cpp.server --model ./kimi-k2.6-q4_k_m.gguf --port 8080 --host 0.0.0.0 &

# 6. Start the autonomous agent loop (your Python script)
python3 agent_loop.py
