#!/bin/bash
# ==================================================
# Hysteria2 暴力竞速版 (针对 ColoCrossing/RackNerd 等廉价机器优化)
# 核心逻辑: 调大 UDP 缓冲区 + 激进拥塞控制
# 适配客户端: Shadowrocket (iOS), v2rayN (Win), Nekobox (Android)
# ==================================================

# 遇到错误立即停止，防止半途而废
set -e

# 1. 权限检查
[[ $EUID -ne 0 ]] && echo -e "\033[31m错误: 必须使用 root 用户运行\033[0m" && exit 1

echo ">>> [1/5] 初始化环境..."
# 随机选择 40000-50000 之间的端口，避开常用段
PORT=$((RANDOM % 10000 + 40000))
# 生成强密码
PASSWORD=$(openssl rand -hex 8)

# 获取 IP (ColoCrossing 机器有时获取 IP 较慢，增加重试)
NODE_IP=$(curl -s4m5 https://api.ipify.org || curl -s4m5 https://ifconfig.me || curl -s4m5 https://checkip.amazonaws.com)
if [[ -z "$NODE_IP" ]]; then
    echo "无法获取公网 IP，请检查网络设置。"
    exit 1
fi

echo ">>> [2/5] 写入内核优化参数 (暴力模式)..."
# 解释: Linux 默认的 UDP 缓冲区太小，根本跑不满 1Gbps。
# 这里我们将读写缓冲区强制扩大到 16MB-26MB，防止高并发下数据包被系统丢弃。
cat > /etc/sysctl.d/99-hysteria.conf << EOF
# 允许最大的接收缓冲区 (26MB)
net.core.rmem_max = 26214400
# 允许最大的发送缓冲区 (26MB)
net.core.wmem_max = 26214400
# 默认缓冲区大小
net.core.rmem_default = 6291456
net.core.wmem_default = 6291456
# 调整网络设备积压队列，防止瞬间流量突增导致丢包
net.core.netdev_max_backlog = 10000
# 开启 BBR (虽然 Hy2 走 UDP，但系统整体优化依然需要)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
# 立即应用参数
sysctl -p /etc/sysctl.d/99-hysteria.conf >/dev/null 2>&1

echo ">>> [3/5] 安装 Hysteria2 核心..."
# 安装必要工具
if command -v apt >/dev/null; then
    apt update -qq && apt install -y -qq curl openssl >/dev/null
elif command -v yum >/dev/null; then
    yum install -y -q curl openssl >/dev/null
fi

# 下载官方稳定版 v2.2.4 (该版本在低配机器上表现稳定)
mkdir -p /usr/local/bin /etc/hysteria
echo "正在下载核心..."
DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/v2.2.4/hysteria-linux-amd64"
curl -L -o /usr/local/bin/hysteria "$DOWNLOAD_URL"
chmod +x /usr/local/bin/hysteria

echo ">>> [4/5] 生成证书与配置..."

# 1. 生成自签证书 (有效期 10 年)
# 针对 Shadowrocket 优化，伪装成 bing.com
openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout /etc/hysteria/server.key \
    -out /etc/hysteria/server.crt \
    -subj "/CN=www.bing.com" -days 3650 >/dev/null 2>&1

# 2. 生成配置文件
# 核心优化点: 开启 ignoreClientBandwidth，由服务器端接管控制
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

# 流量控制: 既然是个人独享，我们不限制客户端速度，让它跑满
ignoreClientBandwidth: false
EOF

echo ">>> [5/5] 启动服务..."
# 创建系统服务
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

# 放行防火墙 (UDP)
if command -v ufw >/dev/null; then
    ufw allow ${PORT}/udp >/dev/null 2>&1
elif command -v firewall-cmd >/dev/null; then
    firewall-cmd --permanent --add-port=${PORT}/udp >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1
fi

# 生成 Shadowrocket 专用链接
# insecure=1 表示允许不安全证书
LINK="hysteria2://${PASSWORD}@${NODE_IP}:${PORT}/?insecure=1&sni=www.bing.com#Hy2_ColoCrossing"

echo -e "\n\033[32m====================================================="
echo -e "   Hysteria2 暴力竞速版部署成功"
echo -e "=====================================================\033[0m"
echo -e "服务器IP: ${NODE_IP}"
echo -e "端口(UDP): ${PORT}"
echo -e "密码:     ${PASSWORD}"
echo -e "-----------------------------------------------------"
echo -e "\033[33mShadowrocket(小火箭)设置提醒:\033[0m"
echo -e "1. 导入下方链接"
echo -e "2. 点击节点右侧 'i' 图标"
echo -e "3. 开启 \033[31m[允许不安全 / Allow Insecure]\033[0m (必须开!)"
echo -e "-----------------------------------------------------"
echo -e "\033[36m${LINK}\033[0m"
echo -e "=====================================================\n"
