#!/bin/bash
# cloud-init: Python Inference Worker VM (private subnet, 10.0.2.157)
# Connects to the iii engine on the engine VM via WebSocket
set -euo pipefail

ENGINE_PRIVATE_IP="10.0.2.60"   # aws_instance.engine private IP from Terraform output
WORKER_DIR="/home/ubuntu/inference-worker"
REPO_URL="https://github.com/__YOUR_ORG__/alchemyst-devops-assignment.git"

apt-get update -y
apt-get install -y python3 python3-pip jq git

# iii CLI (needed for iii-sdk version pinning)
sudo -u ubuntu bash -c '
  curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
  echo "export PATH=\"/home/ubuntu/.local/bin:\$PATH\"" >> /home/ubuntu/.bashrc
'

# Clone project and extract inference worker
sudo -u ubuntu git clone "$REPO_URL" /home/ubuntu/repo 2>/dev/null || true
sudo -u ubuntu cp -r /home/ubuntu/repo/app/quickstart/workers/inference-worker "$WORKER_DIR"

# Install Python dependencies
sudo -u ubuntu pip3 install --user -r "$WORKER_DIR/requirements.txt"

# HuggingFace cache on a dedicated path (mount EBS here in production)
mkdir -p /opt/hf-cache
chown ubuntu:ubuntu /opt/hf-cache

# systemd service
cat > /etc/systemd/system/inference-worker.service <<EOF
[Unit]
Description=iii Inference Worker (Python)
After=network.target

[Service]
User=ubuntu
WorkingDirectory=${WORKER_DIR}
ExecStart=/usr/bin/python3 inference_worker.py
Restart=always
RestartSec=10
Environment=III_URL=ws://${ENGINE_PRIVATE_IP}:49134
Environment=HF_HOME=/opt/hf-cache
Environment=PATH=/home/ubuntu/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable inference-worker
systemctl start inference-worker
