#!/bin/bash
# ==================================================
# Hysteria2 一键安装脚本 [ColoCrossing 1G 稳定版]
# 针对网络差、下载易中断环境深度优化
# ==================================================
set -e

# 1. 权限检查
[[ $EUID -ne 0 ]] && echo -e "\033[31m错误: 必须使用 root 用户运行\033[0m" && exit 1

echo ">>> [1/5] 初始化环境..."
# 固定版本，防止 API 请求超时
HY_VERSION="v2.5.1"
PORT=$((RANDOM % 10000 + 40000))
PASSWORD=$(openssl rand -hex 8)

# 获取 IP
NODE_IP=$(curl -s4m5 https://api.ipify.org || curl -s4m5 https://ifconfig.me || curl -s4m5 https://checkip.amazonaws.com)

echo ">>> [2/5] 写入 1G 内存专用参数..."
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

echo ">>> [3/5] 下载 Hysteria 核心 (固定源 + 多次重试)..."
mkdir -p /usr/local/bin /etc/hysteria
# 使用 --retry 参数应对网络波动，确保下载完整
curl -L --retry 5 --retry-delay 2 -o /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/download/${HY_VERSION}/hysteria-linux-amd64"
chmod +x /usr/local/bin/hysteria

echo ">>> [4/5] 生成证书与配置..."
openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout /etc/hysteria/server.key \
    -out /etc/hysteria/server.crt \
    -subj "/CN=www.bing.com" -days 3650 >/dev/null 2>&1

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

LINK="hysteria2://${PASSWORD}@${NODE_IP}:${PORT}/?insecure=1&sni=www.bing.com#Hy2_ColoCrossing"

echo -e "\n\033[32m====================================================="
echo -e "   Hysteria2 [ColoCrossing 稳定版] 部署成功"
echo -e "=====================================================\033[0m"
echo -e "IP:       ${NODE_IP}"
echo -e "端口:     ${PORT}"
echo -e "密码:     ${PASSWORD}"
echo -e "-----------------------------------------------------"
echo -e "\033[36m${LINK}\033[0m"
echo -e "=====================================================\n"
