#!/bin/bash
# cloud-init: Nginx API Gateway (public subnet)
# Installs Nginx and configures reverse proxy to iii-http on the engine VM
set -euo pipefail

ENGINE_PRIVATE_IP="10.0.2.60"   # aws_instance.engine private IP from Terraform output

apt-get update -y
apt-get install -y nginx

cat > /etc/nginx/sites-available/iii-api <<EOF
server {
    listen 3111;

    location / {
        proxy_pass         http://${ENGINE_PRIVATE_IP}:3111;
        proxy_http_version 1.1;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_read_timeout 35s;   # > iii default_timeout of 30s
        proxy_send_timeout 35s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/iii-api /etc/nginx/sites-enabled/iii-api
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl enable nginx && systemctl restart nginx
