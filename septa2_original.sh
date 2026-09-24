#!/bin/bash

# --- KONFIGURASI UTAMA ---
DOMAIN="h2.masjawa.my.id"
UUID="07e329c4-5b6b-41da-b4aa-0c8ca3e3fbfa"
BOT_TOKEN="7484227045:AAENQc5Dp8_Nno8Oarl79IfAZZtbg4eIQC0"
CHAT_ID="5026145251"

# --- 1. UPDATE & INSTALL DEPENDENCIES ---
echo "Update sistem dan install tools..."
apt update && apt upgrade -y
apt install -y curl socat xz-utils wget nginx certbot python3-certbot-nginx jq

# --- 2. AKTIFKAN TCP BBR ---
echo "Mengaktifkan TCP BBR..."
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
fi

# --- 3. INSTALL XRAY CORE ---
echo "Menginstall Xray Core..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# --- 4. GENERATE SERTIFIKAT SSL ---
echo "Memproses Sertifikat SSL..."
systemctl stop nginx
certbot certonly --standalone --preferred-challenges http --agree-tos --email admin@$DOMAIN -d $DOMAIN --non-interactive

# --- 5. KONFIGURASI XRAY JSON ---
cat <<EOF > /usr/local/etc/xray/config.json
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    { "tag": "vless-ws", "port": 1234, "listen": "127.0.0.1", "protocol": "vless", "settings": { "clients": [{ "id": "$UUID" }], "decryption": "none" }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/home" } } },
    { "tag": "vless-xhttp", "port": 1236, "listen": "127.0.0.1", "protocol": "vless", "settings": { "clients": [{ "id": "$UUID" }], "decryption": "none" }, "streamSettings": { "network": "xhttp", "xhttpSettings": { "path": "/home2", "mode": "auto" } } },
    { "tag": "vless-grpc", "port": 1237, "listen": "127.0.0.1", "protocol": "vless", "settings": { "clients": [{ "id": "$UUID" }], "decryption": "none" }, "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "grpc" } } },
    { "tag": "vless-upgrade", "port": 1238, "listen": "127.0.0.1", "protocol": "vless", "settings": { "clients": [{ "id": "$UUID" }], "decryption": "none" }, "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "/upgrade" } } }
  ],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
EOF

# --- 6. KONFIGURASI NGINX ---
cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 443 ssl http2;
    listen 8443 ssl http2;
    listen 2053 ssl http2;
    listen 2083 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location /home {
        proxy_pass http://127.0.0.1:1234;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
    location /home2 {
        proxy_pass http://127.0.0.1:1236;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_set_header Host \$host;
    }
    location /grpc {
        if (\$request_method != "POST") { return 404; }
        grpc_pass grpc://127.0.0.1:1237;
    }
    location /upgrade {
        proxy_pass http://127.0.0.1:1238;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}

server {
    listen 80; listen 8080; listen 8880; listen 2052; listen 2082;
    server_name $DOMAIN;

    location /home {
        proxy_pass http://127.0.0.1:1234;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
    location /home2 {
        proxy_pass http://127.0.0.1:1236;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_set_header Host \$host;
    }
    location /upgrade {
        proxy_pass http://127.0.0.1:1238;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF

# --- 7. RESTART SERVICES ---
systemctl restart nginx xray
systemctl enable nginx xray

# --- 8. GENERATE CLEAN LINKS & SEND TELEGRAM ---
echo "Mengirim link bersih ke Telegram..."

# TLS Links
L1="vless://$UUID@$DOMAIN:443?path=%2Fhome&security=tls&encryption=none&type=ws&sni=$DOMAIN&host=$DOMAIN#WS_TLS"
L2="vless://$UUID@$DOMAIN:443?path=%2Fhome2&security=tls&encryption=none&type=xhttp&sni=$DOMAIN&host=$DOMAIN#XHTTP_TLS"
L3="vless://$UUID@$DOMAIN:443?mode=multi&security=tls&encryption=none&type=grpc&serviceName=grpc&sni=$DOMAIN&host=$DOMAIN#GRPC_TLS"
L4="vless://$UUID@$DOMAIN:443?path=%2Fupgrade&security=tls&encryption=none&type=httpupgrade&sni=$DOMAIN&host=$DOMAIN#UPGRADE_TLS"

# Non-TLS Links
L5="vless://$UUID@$DOMAIN:80?path=%2Fhome&security=none&encryption=none&type=ws&host=$DOMAIN#WS_NTLS"
L6="vless://$UUID@$DOMAIN:80?path=%2Fhome2&security=none&encryption=none&type=xhttp&host=$DOMAIN#XHTTP_NTLS"
L7="vless://$UUID@$DOMAIN:80?path=%2Fupgrade&security=none&encryption=none&type=httpupgrade&host=$DOMAIN#UPGRADE_NTLS"

# Gabungkan link saja
ALL_LINKS=$(cat <<EOF
$L1
$L2
$L3
$L4
$L5
$L6
$L7
EOF
)

# Kirim via JSON Payload
curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
     -H 'Content-Type: application/json' \
     -d "$(jq -n --arg chat_id "$CHAT_ID" --arg text "$ALL_LINKS" '{chat_id: $chat_id, text: $text}')"

echo "Instalasi selesai. Link sudah dikirim ke Telegram tanpa teks tambahan."
