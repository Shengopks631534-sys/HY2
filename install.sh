#!/bin/bash
# ==================================================
# Hysteria2 一键安装脚本 [ColoCrossing 1G 专用稳定版]
# 核心逻辑:
# 1. 16MB 内存保护 (防止 1G 内存溢出)
# 2. 锁定版本 v2.5.1 (固定下载地址，不走 API，解决连接失败问题)
# ==================================================
set -e

# --- 1. 基础检查 ---
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[31m错误: 必须使用 root 用户运行此脚本！\033[0m"
    exit 1
fi

echo ">>> [1/5] 初始化环境..."
# 定义固定版本 (像 Server A 那样稳定)
HY_VERSION="v2.5.1"
# 定义固定下载链接
DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/${HY_VERSION}/hysteria-linux-amd64"

# 随机端口与密码
PORT=$((RANDOM % 10000 + 40000))
PASSWORD=$(openssl rand -hex 8)

# 获取 IP (多接口备用)
NODE_IP=$(curl -s4m5 https://api.ipify.org || curl -s4m5 https://ifconfig.me || curl -s4m5 https://checkip.amazonaws.com)
if [[ -z "$NODE_IP" ]]; then
    echo "无法获取公网 IP，请检查网络设置。"
    exit 1
fi

echo ">>> [2/5] 写入 1G 内存专用优化参数..."
# 16MB 缓冲区：完美适配 100M 带宽 + 1G 内存
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

echo ">>> [3/5] 下载 Hysteria 核心 (版本: ${HY_VERSION})..."
# 直接下载，不查询 API，拒绝超时
if command -v apt >/dev/null; then
    apt update -qq && apt install -y -qq curl openssl >/dev/null
elif command -v yum >/dev/null; then
    yum install -y -q curl openssl >/dev/null
fi

mkdir -p /usr/local/bin /etc/hysteria
# 这里的 -L 是关键，自动处理跳转
curl -L -o /usr/local/bin/hysteria "$DOWNLOAD_URL"
chmod +x /usr/local/bin/hysteria

echo ">>> [4/5] 生成配置..."
# 自签证书
openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout /etc/hysteria/server.key \
    -out /etc/hysteria/server.crt \
    -subj "/CN=www.bing.com" -days 3650 >/dev/null 2>&1

# 写入配置文件
cat > /etc/hysteria/config.yaml << EOF
listen: :${PORT}
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: ${PASSWORD}
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com/
    rewriteHost: true
# 开启暴力模式
ignoreClientBandwidth: false
EOF

echo ">>> [5/5] 启动服务..."
cat > /etc/systemd/system/hysteria.service << EOF
[Unit]
Description=Hysteria2 Service
After=network.target
[Service]
User=root
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=always
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hysteria >/dev/null 2>&1
systemctl restart hysteria

# 放行防火墙
if command -v ufw >/dev/null; then
    ufw allow ${PORT}/udp >/dev/null 2>&1
elif command -v firewall-cmd >/dev/null; then
    firewall-cmd --permanent --add-port=${PORT}/udp >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1
fi

LINK="hysteria2://${PASSWORD}@${NODE_IP}:${PORT}/?insecure=1&sni=www.bing.com#Hy2_ColoCrossing"

echo -e "\n\033[32m====================================================="
echo -e "   Hysteria2 [ColoCrossing 稳定版] 部署成功"
echo -e "=====================================================\033[0m"
echo -e "版本:     ${HY_VERSION}"
echo -e "IP:       ${NODE_IP}"
echo -e "端口:     ${PORT}"
echo -e "密码:     ${PASSWORD}"
echo -e "SNI:      www.bing.com"
echo -e "-----------------------------------------------------"
echo -e "\033[36m${LINK}\033[0m"
echo -e "=====================================================\n"
