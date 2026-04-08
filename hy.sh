#!/bin/bash
set -e
DOMAIN="rnhy.500228.xyz"
LISTEN_PORT=443
ACME_EMAIL="taedflh666@gmail.com"
BIN_DIR="/usr/local/bin"
CONF_DIR="/etc/hysteria"
CERT_DIR="/etc/hysteria/certs"
mkdir -p "$CONF_DIR" "$CERT_DIR"
echo "=========================================================="
echo " Hysteria 2 Pro 版 - 域名与正规证书自动部署"
echo " 目标域名: $DOMAIN | 监听端口: $LISTEN_PORT"
echo "=========================================================="
echo "-> 安装工具并开启内核 BBR 加速..."
apt update -q
apt install -y curl socat openssl qrencode ca-certificates
if ! sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
  grep -q '^net.core.default_qdisc=fq$' /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  grep -q '^net.ipv4.tcp_congestion_control=bbr$' /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
  sysctl -p > /dev/null 2>&1
fi
echo "-> 正在申请 Let's Encrypt 正式证书 (Standalone 模式)..."
curl -fsSL https://get.acme.sh | sh -s email="$ACME_EMAIL"
~/.acme.sh/acme.sh --upgrade --auto-upgrade
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256
~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --ecc \
  --fullchain-file "$CERT_DIR/server.crt" \
  --key-file "$CERT_DIR/server.key"
echo "-> 下载 Hysteria 2 核心..."
curl -fsSL -o "$BIN_DIR/hysteria" https://download.hysteria.network/app/latest/hysteria-linux-amd64
chmod +x "$BIN_DIR/hysteria"
ln -sf /usr/local/bin/hysteria /usr/local/bin/hy2
PASSWORD=$(openssl rand -hex 16)
MASQ_URL="https://www.kernel.org/"
cat > "$CONF_DIR/config.yaml" <<EOF
listen: :$LISTEN_PORT
tls:
  cert: $CERT_DIR/server.crt
  key: $CERT_DIR/server.key
auth:
  type: password
  password: "$PASSWORD"
masquerade:
  type: proxy
  proxy:
    url: $MASQ_URL
    rewriteHost: true
EOF
cat > /etc/systemd/system/hysteria-server.service <<EOF
[Unit]
Description=Hysteria 2 Server
After=network.target
[Service]
Type=simple
ExecStart=$BIN_DIR/hysteria server -c $CONF_DIR/config.yaml
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable hysteria-server
systemctl restart hysteria-server
sleep 2
STATUS=$(systemctl is-active hysteria-server)
if [ "$STATUS" = "active" ]; then
  SHARE_LINK="hysteria2://$PASSWORD@$DOMAIN:$LISTEN_PORT/?sni=$DOMAIN"
  echo "=========================================================="
  echo " ✅ Hysteria 2 运行成功！"
  echo "----------------------------------------------------------"
  echo -e "分享链接: \033[32m$SHARE_LINK\033[0m"
  echo "----------------------------------------------------------"
  qrencode -t ANSIUTF8 "$SHARE_LINK"
  echo "=========================================================="
  echo "提示: 请确保防火墙已放行 TCP 80 和 UDP $LISTEN_PORT"
else
  echo " ❌ 服务启动失败，请查看：journalctl -u hysteria-server -e --no-pager"
fi
