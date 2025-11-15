#!/bin/bash
# Script cài Docker nhanh cho Ubuntu 24.04.4 + chạy SOCKS5 proxy

# Cập nhật hệ thống
sudo apt update && sudo apt upgrade -y

# Cài gói phụ thuộc
sudo apt install -y ca-certificates curl gnupg lsb-release

# Thêm key GPG và repo Docker
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Cài Docker Engine
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Thêm user hiện tại vào nhóm docker (để chạy không cần sudo)
sudo usermod -aG docker $USER

# Kiểm tra phiên bản
docker --version
echo "Docker đã được cài đặt thành công!"

# Chạy container SOCKS5 proxy
docker run -d --name dantevsocks5 --restart=always -p 443:1080 \
-e PROXY_USER=msyusawi8821df -e PROXY_PASSWORD=jiasydwy6vvg2 \
serjs/go-socks5-proxy

echo "SOCKS5 proxy đã được khởi chạy trên cổng 443!"
