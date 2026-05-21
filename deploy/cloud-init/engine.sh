#!/bin/bash
# cloud-init: iii Engine + Caller Worker VM (private subnet, 10.0.2.60)
# Runs the iii engine and the TypeScript caller-worker as systemd services
set -euo pipefail

PROJECT_DIR="/home/ubuntu/quickstart"
REPO_URL="https://github.com/__YOUR_ORG__/alchemyst-devops-assignment.git"

apt-get update -y

# Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs jq git

# iii CLI
sudo -u ubuntu bash -c '
  curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
  echo "export PATH=\"/home/ubuntu/.local/bin:\$PATH\"" >> /home/ubuntu/.bashrc
'

export PATH="/home/ubuntu/.local/bin:$PATH"

# Clone project (or copy via scp if no public repo)
sudo -u ubuntu git clone "$REPO_URL" "$PROJECT_DIR" 2>/dev/null || true

# Install caller-worker deps
sudo -u ubuntu bash -c "cd $PROJECT_DIR/workers/caller-worker && npm install"

# systemd: iii engine
cat > /etc/systemd/system/iii-engine.service <<EOF
[Unit]
Description=iii Engine
After=network.target

[Service]
User=ubuntu
WorkingDirectory=${PROJECT_DIR}
ExecStart=/home/ubuntu/.local/bin/iii -c config.yaml
Restart=always
RestartSec=5
Environment=PATH=/home/ubuntu/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin

[Install]
WantedBy=multi-user.target
EOF

# systemd: caller-worker (runs after engine is up)
cat > /etc/systemd/system/caller-worker.service <<EOF
[Unit]
Description=iii Caller Worker (TypeScript)
After=network.target iii-engine.service
Wants=iii-engine.service

[Service]
User=ubuntu
WorkingDirectory=${PROJECT_DIR}/workers/caller-worker
ExecStart=/usr/bin/npx tsx src/worker.ts
Restart=always
RestartSec=5
Environment=III_URL=ws://localhost:49134
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable iii-engine caller-worker
systemctl start iii-engine
sleep 5   # give engine time to bind port 49134
systemctl start caller-worker
