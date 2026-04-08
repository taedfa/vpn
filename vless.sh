#!/bin/bash
set -e
# ===== 1. 基本参数 =====
DOMAIN="rnvless.500228.xyz"
PORT="443"
XRAY_CONF_DIR="/usr/local/etc/xray"
XRAY_CONF_FILE="$XRAY_CONF_DIR/config.json"
BACKUP_DIR="/root/xray_backup_$(date +%F_%H-%M-%S)"
echo "======================================================"
echo " Xray VLESS Reality 一键部署"
echo " 域名: $DOMAIN"
echo " 端口: $PORT"
echo "======================================================"
# ===== 2. 环境准备与 BBR =====
echo "-> 安装依赖并优化 BBR ..."
apt-get update
apt-get install -y curl openssl python3 qrencode
if ! sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
    grep -q '^net.core.default_qdisc=fq$' /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q '^net.ipv4.tcp_congestion_control=bbr$' /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
fi
# ===== 3. 检查 443 端口占用 =====
echo "-> 检查 TCP 端口占用 ..."
if ss -tlnp | grep -q ":$PORT "; then
    echo "⚠️ 检测到 TCP $PORT 端口已被占用："
    ss -tlnp | grep ":$PORT " || true
    echo "如果确认要继续，请先停止占用该 TCP 端口的服务。"
    exit 1
fi
# ===== 4. 安装 Xray 官方内核 =====
echo "-> 安装/升级 Xray ..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
# ===== 5. 备份旧配置 =====
mkdir -p "$XRAY_CONF_DIR"
mkdir -p "$BACKUP_DIR"
if [ -f "$XRAY_CONF_FILE" ]; then
    echo "-> 备份旧配置到 $BACKUP_DIR ..."
    cp -f "$XRAY_CONF_FILE" "$BACKUP_DIR/config.json.bak"
fi
# ===== 6. 生成 Reality 配置 =====
cat > /root/final_fix.py << 'EOF'
import os
import subprocess
import json
import secrets
XRAY_BIN = "/usr/local/bin/xray"
CONF_PATH = "/usr/local/etc/xray/config.json"
INFO_PATH = "/root/xray_reality_info.txt"
LINK_PATH = "/root/vless_link.txt"
DOMAIN = "rnvless.500228.xyz"
PORT = 443
def run(cmd):
    return subprocess.check_output(cmd, shell=True, text=True).strip()
def get_x25519_keys():
    out = run(f"{XRAY_BIN} x25519")
    lines = out.splitlines()
    priv = lines[0].split(": ", 1)[1].strip()
    pub = lines[1].split(": ", 1)[1].strip()
    return priv, pub
def get_uuid():
    try:
        return run(f"{XRAY_BIN} uuid")
    except:
        import uuid
        return str(uuid.uuid4())
print("🔍 正在生成 Reality 配置...")
priv_key, pub_key = get_x25519_keys()
uuid = get_uuid()
# shortId 最多 16 个十六进制字符；这里用 8 字节 = 16 hex
short_id = secrets.token_hex(8)
config = {
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": PORT,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": uuid,
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": False,
                    "dest": "dl.google.com:443",
                    "xver": 0,
                    "serverNames": [
                        "dl.google.com",
                        "www.google.com"
                    ],
                    "privateKey": priv_key,
                    "shortIds": [
                        short_id
                    ]
                }
            },
            "sniffing": {
                "enabled": True,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ]
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        }
    ]
}
os.makedirs("/usr/local/etc/xray", exist_ok=True)
with open(CONF_PATH, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
link = (
    f"vless://{uuid}@{DOMAIN}:{PORT}"
    f"?security=reality"
    f"&encryption=none"
    f"&pbk={pub_key}"
    f"&headerType=none"
    f"&fp=chrome"
    f"&type=tcp"
    f"&flow=xtls-rprx-vision"
    f"&sni=dl.google.com"
    f"&sid={short_id}"
    f"#RN_VLESS_REALITY_443"
)
with open(LINK_PATH, "w", encoding="utf-8") as f:
    f.write(link)
with open(INFO_PATH, "w", encoding="utf-8") as f:
    f.write("===== Xray Reality 部署信息 =====\n")
    f.write(f"域名: {DOMAIN}\n")
    f.write(f"端口: {PORT}\n")
    f.write(f"UUID: {uuid}\n")
    f.write(f"PublicKey: {pub_key}\n")
    f.write(f"PrivateKey: {priv_key}\n")
    f.write(f"ShortID: {short_id}\n")
    f.write(f"SNI: dl.google.com\n")
    f.write(f"Dest: dl.google.com:443\n")
    f.write("\n分享链接:\n")
    f.write(link + "\n")
print("✅ 配置文件已生成。")
print(f"UUID: {uuid}")
print(f"ShortID: {short_id}")
print(f"域名地址: {DOMAIN}:{PORT}")
EOF
python3 /root/final_fix.py
# ===== 7. 测试配置 =====
echo "-> 测试 Xray 配置 ..."
/usr/local/bin/xray run -test -config "$XRAY_CONF_FILE"
# ===== 8. 启动服务 =====
echo "-> 启动 Xray 服务 ..."
systemctl daemon-reload
systemctl enable xray
systemctl restart xray
# ===== 9. 输出结果 =====
if systemctl is-active --quiet xray; then
    echo
    echo -e "\033[32m✅ VLESS Reality 部署成功！\033[0m"
    echo "------------------------------------------------------"
    cat /root/vless_link.txt
    echo
    echo "配置详情保存在: /root/xray_reality_info.txt"
    echo "------------------------------------------------------"
    qrencode -t ANSIUTF8 < /root/vless_link.txt
    echo "------------------------------------------------------"
    echo "请确认以下两点："
    echo "1. 域名 $DOMAIN 已解析到本机公网 IP"
    echo "2. 防火墙 / 安全组已放行 TCP $PORT"
else
    echo
    echo -e "\033[31m❌ Xray 启动失败，请检查日志：\033[0m"
    echo "journalctl -u xray -e --no-pager"
    exit 1
fi
