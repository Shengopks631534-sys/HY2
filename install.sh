#!/bin/bash
# ==================================================
# Hysteria2 暴力竞速版 [Pro 适配 ColoCrossing 1G]
# 优化点: 
# 1. 内存保护: 将 UDP 缓冲区从 26MB 降至 16MB (防 OOM 崩溃)
# 2. 自动追新: 自动抓取 GitHub 最新版核心 (不再死守旧版)
# 3. 拥塞控制: 强制开启 BBR + FQ
# ==================================================
set -e

# 1. 权限检查
[[ $EUID -ne 0 ]] && echo -e "\033[31m错误: 必须使用 root 用户运行\033[0m" && exit 1

echo ">>> [1/5] 初始化环境..."
# 随机端口 40000-50000
PORT=$((RANDOM % 10000 + 40000))
PASSWORD=$(openssl rand -hex 8)

# 增强型 IP 获取 (防止单接口报错)
NODE_IP=$(curl -s4m5 https://api.ipify.org || curl -s4m5 https://ifconfig.me || curl -s4m5 https://checkip.amazonaws.com)
if [[ -z "$NODE_IP" ]]; then
    echo "无法获取公网 IP，请检查网络设置。"
    exit 1
fi

echo ">>> [2/5] 写入内核优化参数 (1G内存专用版)..."
# 【关键优化】将缓冲区限制在 16MB，防止 1G 内存机器在高并发下死机
cat > /etc/sysctl.d/99-hysteria.conf << EOF
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 4194304
net.core.wmem_default = 4194304
net.core.netdev_max_backlog = 10000
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl -p /etc/sysctl.d/99-hysteria.conf >/dev/null 2>&1

echo ">>> [3/5] 安装 Hysteria2 最新内核..."
if command -v apt >/dev/null; then
    apt update -qq && apt install -y -qq curl openssl >/dev/null
elif command -v yum >/dev/null; then
    yum install -y -q curl openssl >/dev/null
fi

# 【自动追新】自动获取 GitHub 最新版本，不再使用半年前的 v2.2.4
mkdir -p /usr/local/bin /etc/hysteria
LATEST_URL=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/apernet/hysteria/releases/latest)
LATEST_TAG=$(echo $LATEST_URL | awk -F'/' '{print $NF}')
echo "检测到最新版本: ${LATEST_TAG}"
DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/${LATEST_TAG}/hyst
