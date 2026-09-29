#!/bin/bash
# ============================================================
#   AUTO INSTALL: VPN (XRAY) + WEBSITE KATALOG + AUTO SYNC + PWA
#   v3.0 — PWA Ready (Orange Theme)
# ============================================================
set -uo pipefail
IFS=$'\n\t'

DOMAIN="gudangbarang.com"
BUG_SNI="gudangbarang.com"
UUID="07e329c4-5b6b-41da-b4aa-0c8ca3e3fbfa"
BOT_TOKEN="7484227045:AAENQc5Dp8_Nno8Oarl79IfAZZtbg4eIQC0"
CHAT_ID="5026145251"

LOG_FILE="/var/log/install-katalog.log"
SYNC_USER="syncworker"
SYNC_DIR="/opt/sync-gudang"
APP_DIR="/var/www/html"
BACKUP_DIR="/root/backup-katalog-$(date +%Y%m%d-%H%M%S)"

log(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }
die(){ log "❌ ERROR: $*"; exit 1; }
ok(){  log "✅ $*"; }
warn(){ log "⚠️  $*"; }

[[ $EUID -ne 0 ]] && die "Root only"
[[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || die "Domain invalid: $DOMAIN"
[[ "$UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || die "UUID invalid: $UUID"

mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR"
log "===== MULAI INSTALASI v3.0 (PWA Ready) ====="

# Backup config lama (termasuk file PWA)
for f in /usr/local/etc/xray/config.json /etc/nginx/sites-available/default \
         /etc/cron.d/sync-gudang /etc/cron.d/certbot-renew \
         "$APP_DIR/index.html" "$APP_DIR/manifest.json" "$APP_DIR/sw.js" "$APP_DIR/icon.svg" \
         /etc/fail2ban/jail.d/sshd.local; do
    [[ -f "$f" ]] && cp -a "$f" "$BACKUP_DIR/" 2>/dev/null
done
ok "Backup di: $BACKUP_DIR"

# ============================================================
# 1. DEPENDENCIES
# ============================================================
log "[1/12] Install dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -q -y || die "apt update gagal"
apt-get install -y --no-install-recommends \
    curl socat xz-utils wget nginx certbot python3-certbot-nginx \
    jq cron ufw fail2ban python3-systemd ca-certificates gnupg logrotate \
    || die "Install deps gagal"

if ! command -v node &>/dev/null || [[ "$(node -v | cut -d. -f1 | tr -d v)" -lt 20 ]]; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - || die "NodeSource gagal"
    apt-get install -y nodejs || die "Node.js gagal"
fi
ok "Node.js $(node -v)"
apt-get autoremove -y >/dev/null 2>&1 || true

# ============================================================
# 2. FIREWALL + FAIL2BAN
# ============================================================
log "[2/12] Firewall + fail2ban..."
ufw limit ssh >/dev/null 2>&1 || ufw allow ssh >/dev/null 2>&1
for p in 80 443 8080 8880 2052 2053 2082 2083 8443; do
    ufw allow "${p}/tcp" >/dev/null 2>&1 || true
done
ufw --force enable >/dev/null 2>&1 || true
ok "UFW aktif"

cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled  = true
backend  = systemd
port     = ssh
maxretry = 5
bantime  = 3600
findtime = 600
EOF

systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban >/dev/null 2>&1 || warn "fail2ban restart gagal"
sleep 1
if fail2ban-client status sshd >/dev/null 2>&1; then
    ok "fail2ban aktif (jail sshd OK)"
else
    warn "fail2ban jalan tapi jail sshd belum aktif"
fi

# ============================================================
# 3. KERNEL TUNING
# ============================================================
log "[3/12] Tuning kernel..."
cat > /etc/security/limits.d/99-xray.conf <<'EOF'
*     soft nofile 512000
*     hard nofile 512000
root  soft nofile 512000
root  hard nofile 512000
EOF

cat > /etc/sysctl.d/99-xray.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.ip_local_port_range = 10000 65000
fs.file-max = 512000
EOF
sysctl --system >/dev/null 2>&1 || true
ok "Tuning kernel selesai"

# ============================================================
# 4. XRAY CORE
# ============================================================
log "[4/12] Install Xray Core..."
if ! command -v xray &>/dev/null; then
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install \
        || die "Gagal install Xray"
fi
command -v xray &>/dev/null || die "Binary xray tidak ditemukan"
ok "Xray $(xray version | head -1)"

# ============================================================
# 5. INDEX.HTML (dengan PWA tags)
# ============================================================
log "[5/12] Tulis index.html..."
mkdir -p "$APP_DIR/gambar"

cat > "$APP_DIR/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta http-equiv="Cache-Control" content="no-store, must-revalidate">
<meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=no">
<meta name="color-scheme" content="light">
<title>GudangBarang.com - Mas Septa</title>
<meta name="description" content="Katalog barang GudangBarang.com - Mas Septa">
<meta name="theme-color" content="#EA580C">
<link rel="manifest" href="manifest.json">
<link rel="icon" type="image/svg+xml" href="icon.svg">
<link rel="apple-touch-icon" href="icon.svg">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<meta name="apple-mobile-web-app-title" content="GudangBarang">
<style>
*{-webkit-tap-highlight-color:transparent;box-sizing:border-box}
html,body{font-family:'Segoe UI',Tahoma,sans-serif;background:#f5f5f5;margin:0;padding:0;min-height:100vh}
.app-container{max-width:480px;margin:0 auto;background:#f5f5f5;display:flex;flex-direction:column;min-height:100vh}
.sticky-atas{position:sticky;top:0;z-index:30;box-shadow:0 3px 8px rgba(0,0,0,.1);background:#fff}
header{position:relative;background:#EA580C;color:#fff;padding:12px 15px;text-align:center;overflow:hidden}
header::before{content:"";position:absolute;inset:0;background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='90' height='90'><g fill='%23ffffff' fill-opacity='0.15'><ellipse cx='45' cy='20' rx='9' ry='14'/><ellipse cx='45' cy='70' rx='9' ry='14'/><ellipse cx='20' cy='45' rx='14' ry='9'/><ellipse cx='70' cy='45' rx='14' ry='9'/></g></svg>");background-size:90px 90px;pointer-events:none;z-index:1}
header>*{position:relative;z-index:2}
.header-title{font-size:1.05rem;font-weight:800;margin:0;color:#fff}
.header-subtitle{font-size:.75rem;font-weight:600;margin:3px 0 0;color:rgba(255,255,255,.92)}
.wadah-pencarian{padding:10px 15px;background:#fff;border-bottom:1px solid #ddd}
.form-pencarian{display:flex;align-items:center;gap:12px}
.btn-back{background:none;border:none;padding:0;display:none;align-items:center;justify-content:center;cursor:pointer;color:#EA580C}
.input-wrapper{position:relative;flex-grow:1;display:flex;align-items:center;border:1.5px solid #EA580C;border-radius:4px;background:#fff;overflow:hidden;height:40px}
.input-wrapper input[type=search]{width:100%;height:100%;padding:0 35px 0 10px;border:none;outline:none;font-size:.95rem;background:transparent;z-index:2;-webkit-appearance:none}
.input-wrapper input[type=search]::-webkit-search-cancel-button{-webkit-appearance:none}
.btn-clear{position:absolute;right:50px;background:#c4c4c4;color:#fff;border:none;width:16px;height:16px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:10px;cursor:pointer;padding:0;z-index:3}
.btn-search-orange{background:#EA580C;color:#fff;border:none;height:100%;padding:0 12px;display:flex;align-items:center;justify-content:center;cursor:pointer;z-index:3}
.placeholder-animasi{position:absolute;left:10px;top:0;bottom:0;display:flex;align-items:center;pointer-events:none;color:#999;z-index:1;font-size:.95rem;overflow:hidden;white-space:nowrap}
.animasi-teks-wrapper{display:inline-block;height:1.2em;overflow:hidden;margin-left:4px}
.teks-bergerak{display:block;transition:transform .3s ease-in-out,opacity .3s ease}
.wadah-katalog{padding:15px;padding-bottom:100px;display:flex;flex-direction:column;gap:20px}
.kartu-barang{background:#fff;padding:15px;border-radius:12px;box-shadow:0 2px 8px rgba(0,0,0,.06);border-bottom:6px solid transparent;transition:border-color .3s}
.kartu-barang.aktif-keranjang{border-bottom-color:#25D366}
.teks-pilih-varian{font-size:.8rem;font-weight:700;color:#555;margin-bottom:6px}
.wadah-varian{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:15px}
.btn-varian{padding:6px 14px;border:1.5px solid #ddd;border-radius:20px;background:#fff;color:#555;font-size:.85rem;font-weight:600;cursor:pointer;transition:all .2s}
.btn-varian.aktif{border-color:#25D366;background:#e8fbf0;color:#25D366}
.btn-varian.di-keranjang{background:#25D366;color:#fff;border-color:#25D366}
.btn-varian.di-keranjang.aktif{box-shadow:0 0 0 3px rgba(37,211,102,.3)}
.btn-varian[disabled]{background:#f5f5f5;color:#bbb;border-color:#eee;text-decoration:line-through;cursor:not-allowed}
.slider-wrapper{position:relative;width:100%;border-radius:8px;overflow:hidden;background:#eee}
.slider-gambar{display:flex;overflow-x:auto;scroll-snap-type:x mandatory;scrollbar-width:none;scroll-behavior:smooth}
.slider-gambar::-webkit-scrollbar{display:none}
.slider-gambar img{flex:0 0 100%;scroll-snap-align:center;width:100%;height:300px;object-fit:cover;user-select:none;-webkit-user-select:none;-webkit-touch-callout:none}
.gambar-kosong{filter:grayscale(100%);opacity:.75}
.slider-counter{position:absolute;top:10px;right:10px;background:rgba(0,0,0,.6);color:#fff;font-size:.75rem;font-weight:700;padding:4px 10px;border-radius:12px;z-index:5;pointer-events:none}
.watermark-kosong{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%) rotate(-25deg);color:rgba(255,0,0,.6);font-size:2.5rem;font-weight:900;letter-spacing:2px;border:5px solid rgba(255,0,0,.6);padding:10px 20px;border-radius:10px;z-index:10;pointer-events:none}
.nama-barang{font-size:1.1rem;color:#333;margin:15px 0 5px;font-weight:700}
.harga-barang{color:#EA580C;font-weight:700;font-size:1.2rem;margin:0 0 10px}
.satuan-harga{font-size:.85rem;color:#666;font-weight:400}
.wadah-deskripsi{border:1.5px dashed #ccc;border-radius:8px;padding:10px;margin-bottom:15px;background:#fafafa}
.judul-deskripsi{font-size:.8rem;font-weight:700;color:#777;margin-bottom:6px}
.keterangan-barang{font-size:.85rem;color:#444;white-space:pre-wrap;line-height:1.4;margin:0}
.area-bawah-kartu{display:flex;justify-content:space-between;align-items:center;border-top:1px dashed #eee;padding-top:10px}
.kontrol-qty{display:flex;align-items:center;gap:10px;background:#fff5ee;border:1px solid #fed7aa;border-radius:25px;padding:3px}
.btn-qty{background:#EA580C;color:#fff;border:none;width:32px;height:32px;border-radius:50%;font-size:1.2rem;font-weight:700;cursor:pointer;display:flex;align-items:center;justify-content:center}
.btn-qty:disabled{background:#ccc;cursor:not-allowed}
.angka-qty{font-weight:700;min-width:25px;text-align:center;color:#333}
.btn-keranjang-atas{background:#EA580C;color:#fff;border:none;height:43px;width:45px;border-radius:6px;display:flex;align-items:center;justify-content:center;cursor:pointer;position:relative}
.badge-keranjang{position:absolute;top:-5px;right:-5px;background:#dc2626;color:#fff;font-size:.7rem;font-weight:700;width:18px;height:18px;border-radius:50%;display:flex;align-items:center;justify-content:center;border:2px solid #fff}
.modal-overlay{position:fixed;inset:0;background:rgba(0,0,0,.5);z-index:100;display:none;justify-content:center;align-items:flex-end}
.modal-content{background:#fff;width:100%;max-width:480px;max-height:85%;border-radius:20px 20px 0 0;padding:20px;display:flex;flex-direction:column;animation:slideUp .3s ease-out}
@keyframes slideUp{from{transform:translateY(100%)}to{transform:translateY(0)}}
.modal-header{display:flex;align-items:center;border-bottom:1px solid #eee;padding-bottom:10px;margin-bottom:15px;gap:10px}
.modal-header h2{margin:0;font-size:1.2rem;color:#333;flex-grow:1}
.btn-tutup{background:none;border:none;color:#EA580C;cursor:pointer;padding:0;display:flex;align-items:center}
.list-pesanan{overflow-y:auto;flex-grow:1;max-height:50vh;padding-right:5px}
.item-pesanan{display:flex;justify-content:space-between;align-items:center;margin-bottom:15px;border-bottom:1px dashed #eee;padding-bottom:15px}
.info-item-keranjang{flex:1;padding-right:15px}
.item-pesanan-nama{font-weight:700;font-size:.95rem;margin-bottom:4px;color:#333;text-transform:capitalize}
.item-pesanan-harga{font-size:.85rem;color:#777;margin-bottom:5px}
.total-harga-item{font-weight:700;color:#EA580C;font-size:1rem}
.area-checkout{margin-top:15px;padding-top:15px;border-top:2px solid #eee}
.form-tujuan{display:flex;flex-direction:column;gap:10px;margin-bottom:15px}
.input-tujuan{width:100%;padding:10px 12px;border:1.5px solid #ccc;border-radius:8px;font-size:.95rem;outline:none;background:#fff}
.input-tujuan:focus{border-color:#EA580C}
.baris-total{display:flex;justify-content:space-between;font-weight:700;font-size:1.2rem;margin-bottom:15px}
.btn-wa-checkout{background:#25D366;color:#fff;border:none;width:100%;padding:15px;border-radius:10px;font-size:1rem;font-weight:700;cursor:pointer;display:flex;justify-content:center;align-items:center;gap:10px}
.teks-loading{text-align:center;color:#777;font-weight:700;padding:40px 0}
.konfirmasi-overlay{position:fixed;inset:0;background:rgba(0,0,0,.6);z-index:999;display:none;justify-content:center;align-items:center;padding:20px}
.konfirmasi-box{background:#fff;width:100%;max-width:320px;border-radius:14px;padding:20px;text-align:center}
.konfirmasi-box h3{margin:0 0 10px;color:#333;font-size:1.1rem}
.konfirmasi-box p{color:#666;font-size:.9rem;margin-bottom:20px;line-height:1.4}
.konfirmasi-aksi{display:flex;gap:10px}
.btn-konfirmasi{flex:1;padding:10px;border-radius:8px;font-weight:700;font-size:.95rem;cursor:pointer;border:none}
.btn-tidak{background:#e5e7eb;color:#333}
.btn-ya,.btn-ok{background:#EA580C;color:#fff}
#btnInstallPWA{display:none;position:fixed;bottom:20px;right:20px;background:linear-gradient(135deg,#F97316,#EA580C);color:#fff;padding:14px 22px;border-radius:30px;font-size:14px;font-weight:700;box-shadow:0 8px 20px rgba(234,88,12,.4);z-index:9999;border:none;cursor:pointer;align-items:center;gap:8px;font-family:inherit}
</style>
</head>
<body>
<div class="app-container">
<div class="sticky-atas">
<header><h1 class="header-title">Gudangbarang.com</h1><p class="header-subtitle">Mas Septa</p></header>
<div class="wadah-pencarian">
<form class="form-pencarian" action="javascript:void(0);" onsubmit="jalankanCari(event)">
<button type="button" class="btn-back" id="btnBack" onclick="resetCari()"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><line x1="19" y1="12" x2="5" y2="12"/><polyline points="12 19 5 12 12 5"/></svg></button>
<div class="input-wrapper">
<input type="search" id="inputCari" onfocus="hidePH()" onblur="showPH()">
<div id="wadah-placeholder" class="placeholder-animasi"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#999" stroke-width="2" stroke-linecap="round" style="margin-right:5px"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>Cari <div class="animasi-teks-wrapper"><span id="teks-animasi" class="teks-bergerak">...</span></div></div>
<button type="button" class="btn-clear" id="btnClear" onclick="clearInput()" style="display:none"><svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg></button>
<button type="submit" class="btn-search-orange"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg></button>
</div>
<button type="button" class="btn-keranjang-atas" onclick="bukaKeranjang()"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/><path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6"/></svg><div class="badge-keranjang" id="badge-qty">0</div></button>
</form>
</div>
</div>
<div class="wadah-katalog" id="tempat-katalog"><div class="teks-loading">Mengambil data dari gudang...</div></div>
<div class="modal-overlay" id="modal-keranjang"><div class="modal-content">
<div class="modal-header"><button class="btn-tutup" onclick="tutupKeranjang()"><svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><line x1="19" y1="12" x2="5" y2="12"/><polyline points="12 19 5 12 12 5"/></svg></button><h2>Tinjau Pesanan</h2></div>
<div class="list-pesanan" id="list-pesanan"></div>
<div class="area-checkout">
<div class="form-tujuan">
<input type="text" id="inputKios" class="input-tujuan" placeholder="KIOS Nama Utama..." onfocus="cekKios(this)" oninput="valKios(this)">
<select id="inputDaerah" class="input-tujuan" onchange="simpanDaerah(this)"><option value="" disabled selected>-- Pilih Daerah --</option><option value="SOE">SOE</option><option value="KEFA">KEFA</option><option value="ATAMBUA">ATAMBUA</option><option value="MALAKA">MALAKA</option></select>
</div>
<div class="baris-total"><span>Total:</span><span id="total-harga-keranjang">Rp 0</span></div>
<button class="btn-wa-checkout" onclick="kirimKeWA()"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/></svg>Kirim Pesanan ke WA</button>
</div>
</div></div>
<div class="konfirmasi-overlay" id="modalKonfirmasiWA"><div class="konfirmasi-box"><h3>Konfirmasi Pesanan</h3><p>Apakah kamu sudah yakin?<br>Barang yang sudah dipesan tidak bisa dikembalikan pada saat pengantaran.</p><div class="konfirmasi-aksi"><button class="btn-konfirmasi btn-tidak" onclick="tutupKonfirmasiWA()">Cek Kembali</button><button class="btn-konfirmasi btn-ya" onclick="eksekusiKirimWA()">Ya, Yakin</button></div></div></div>
<div class="konfirmasi-overlay" id="modalAlertCustom"><div class="konfirmasi-box"><h3 id="alertJudul">Perhatian</h3><p id="alertPesan">Pesan alert</p><div class="konfirmasi-aksi"><button class="btn-konfirmasi btn-ok" onclick="tutupAlert()">OK</button></div></div></div>
</div>
<button id="btnInstallPWA">📲 Install Aplikasi</button>
<script>
'use strict';
const SHEET_URL='./data.json?t='+Date.now(),FOLDER='./gambar/',CART_KEY='keranjang_gudang_septa_v3',CART_TS='waktu_checkout_gudang_septa',CART_TTL=2*24*60*60*1000,WA_CD=3*60*1000;
function sParse(k,fb){try{const v=localStorage.getItem(k);return v?JSON.parse(v):fb}catch(e){return fb}}
function cekCart(){const t=localStorage.getItem(CART_TS);if(t&&Date.now()-parseInt(t,10)>CART_TTL){localStorage.removeItem(CART_KEY);localStorage.removeItem(CART_TS);return{}}return sParse(CART_KEY,{})}
let dataKatalog={},katalogByNama={},keranjang=cekCart(),daftarNama=[],nomorWA='',cari=false,stateVarian={},arrayHTML=[],jmlTampil=0;
const BATAS=20;
function esc(s){if(s==null)return'';return String(s).replace(/[&<>'"]/g,t=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[t]||t))}
function fileDariURL(u){const s=String(u).trim();return s.includes('/')?s.split('/').pop():s}
function rp(n){return'Rp '+Number(n||0).toLocaleString('id-ID')}
function pushM(n){window.history.pushState({modal:n},'','')}
window.addEventListener('popstate',function(){const a=document.getElementById('modalAlertCustom'),k=document.getElementById('modalKonfirmasiWA'),c=document.getElementById('modal-keranjang');if(a.style.display==='flex'){a.style.display='none';return}if(k.style.display==='flex'){k.style.display='none';return}if(c.style.display==='flex'){c.style.display='none';document.body.style.overflow='';return}if(location.hash!=='#cari'&&cari)resetCari()});
function alertBox(p,j){document.getElementById('alertJudul').innerText=j||'Perhatian';document.getElementById('alertPesan').innerText=p;document.getElementById('modalAlertCustom').style.display='flex';pushM('alert')}
function tutupAlert(){if(window.history.state&&window.history.state.modal==='alert')window.history.back();else document.getElementById('modalAlertCustom').style.display='none'}
function muatPelanggan(){const k=localStorage.getItem('gudang_septa_kios'),d=localStorage.getItem('gudang_septa_daerah');if(k)document.getElementById('inputKios').value=k;if(d)document.getElementById('inputDaerah').value=d}
function cekKios(i){if(i.value.trim()==='')i.value='KIOS '}
function valKios(i){let v=i.value.toUpperCase();if(!v.startsWith('KIOS ')){i.value='KIOS '}else{const s=v.substring(5);if(s.includes('KIOS')){alertBox('Harap hapus tulisan kios!');i.value='KIOS '+s.replace(/KIOS/g,'').trim()}else{i.value=v}}localStorage.setItem('gudang_septa_kios',i.value)}
function simpanDaerah(s){localStorage.setItem('gudang_septa_daerah',s.value)}
function updKartu(id){const b=dataKatalog[id];if(!b)return;let tq=0,mq=0,pre=b.nama+'_';for(const k in keranjang){if(k.startsWith(pre)){tq+=keranjang[k].qty;if(keranjang[k].qty>mq)mq=keranjang[k].qty}}const kt=document.getElementById('kartu-'+id);if(kt)kt.classList.toggle('aktif-keranjang',tq>0);const eq=document.getElementById('qty-'+id);if(b.varian&&b.varian.length>0){const av=stateVarian[id]||'';b.varian.forEach((v,i)=>{const btn=document.getElementById('btn-var-'+id+'-'+i);if(!btn)return;const k=b.nama+'_'+v,q=keranjang[k]?keranjang[k].qty:0;btn.classList.toggle('di-keranjang',q>0);btn.classList.toggle('aktif',v===av)});if(eq){if(av){const k=b.nama+'_'+av;eq.innerText=keranjang[k]?keranjang[k].qty:0}else{eq.innerText=mq>0?mq:0}}}else{const k=b.nama+'_';if(eq)eq.innerText=keranjang[k]?keranjang[k].qty:0}if(kt&&!b.isKosong){const m=kt.querySelectorAll('.btn-qty')[0];if(m&&eq)m.disabled=parseFloat(eq.innerText)<=0}}
function addBatch(n){const tk=document.getElementById('tempat-katalog');let h='';const b=Math.min(jmlTampil+n,arrayHTML.length);for(let i=jmlTampil;i<b;i++)h+=arrayHTML[i];if(h){tk.insertAdjacentHTML('beforeend',h);for(let i=jmlTampil;i<b;i++)updKartu(i);jmlTampil=b}}
async function ambilData(){try{const r=await fetch(SHEET_URL,{cache:'no-store'});if(!r.ok)throw new Error('HTTP '+r.status);const d=await r.json();if(!d||!d.table||!Array.isArray(d.table.rows))throw new Error('Format invalid');const rows=d.table.rows;arrayHTML=[];jmlTampil=0;let idx=0;dataKatalog={};katalogByNama={};daftarNama=[];nomorWA='';stateVarian={};rows.forEach((row,ri)=>{if(ri===0&&row.c&&row.c[1]&&typeof row.c[1].v==='string')return;if(!row.c||!row.c[0]||!row.c[0].v)return;let nama=String(row.c[0].v).trim();if(nama.includes('#'))return;let kosong=false;if(nama.includes('*')){kosong=true;nama=nama.replace(/\*/g,'').trim()}if(row.c[9]&&row.c[9].v&&!nomorWA){let n=String(row.c[9].v).replace(/\D/g,'');if(n.startsWith('0'))n='62'+n.substring(1);if(n.length>=10)nomorWA=n}let kl=1;const sk=row.c[7];if(sk&&(sk.f!==undefined||sk.v!==null)){const p=parseFloat(String(sk.f||sk.v).replace(',','.'));if(!isNaN(p)&&p>0)kl=p}const sat=row.c[8]&&row.c[8].v?String(row.c[8].v).trim():'',har=row.c[1]?Number(row.c[1].v)||0:0,ket=row.c[6]&&row.c[6].v!==undefined?String(row.c[6].v):'';let vr=[];if(row.c[11]&&row.c[11].v){const sv=String(row.c[11].v).trim();if(sv)vr=sv.split(',').map(v=>v.trim()).filter(v=>v)}daftarNama.push(nama);dataKatalog[idx]={id:idx,nama,harga:har,kelipatan:kl,satuan:sat?' '+sat:'',isKosong:kosong,varian:vr};katalogByNama[nama]=dataKatalog[idx];const f1=row.c[3]&&row.c[3].v?row.c[3].v:'',f2=row.c[4]&&row.c[4].v?row.c[4].v:'',f3=row.c[5]&&row.c[5].v?row.c[5].v:'';const fl=[f1,f2,f3].filter(v=>v).map(v=>FOLDER+fileDariURL(v));const tf=fl.length,kg=kosong?'gambar-kosong':'';const imgs=tf===0?'<img src="https://placehold.co/400x300/e0e0e0/666666?text=Tidak+Ada+Foto" alt="-" loading="lazy" class="'+kg+'" draggable="false">':fl.map(u=>'<img src="'+esc(u)+'" onerror="this.onerror=null;this.src=\'https://placehold.co/400x300/e0e0e0/666666?text=Loading\';" loading="lazy" class="'+kg+'" draggable="false">').join('');const kosEl=kosong?'<div class="watermark-kosong">KOSONG</div>':'';const ketEl=ket?'<div class="wadah-deskripsi"><div class="judul-deskripsi">Deskripsi:</div><div class="keterangan-barang">'+esc(ket)+'</div></div>':'';let vh='';if(vr.length>0){const btns=vr.map((v,i)=>{const k=v.includes('*'),nm=v.replace(/\*/g,'').trim(),dis=k?' disabled':'';return'<button type="button" class="btn-varian" id="btn-var-'+idx+'-'+i+'" data-id="'+idx+'" data-idx="'+i+'"'+dis+'>'+esc(nm)+'</button>'}).join('');vh='<div class="teks-pilih-varian">Pilih Varian:</div><div class="wadah-varian" id="wadah-varian-'+idx+'">'+btns+'</div>'}const satEl=sat?'<span class="satuan-harga"> / '+esc(sat)+'</span>':'';arrayHTML.push('<div class="kartu-barang" id="kartu-'+idx+'"><div class="slider-wrapper">'+kosEl+(tf>1?'<div class="slider-counter">1/'+tf+'</div>':'')+'<div class="slider-gambar" data-total="'+tf+'">'+imgs+'</div></div><h3 class="nama-barang">'+esc(nama)+'</h3><p class="harga-barang">'+rp(har)+satEl+'</p>'+vh+ketEl+'<div class="area-bawah-kartu"><div style="flex:1"></div><div class="kontrol-qty"><button class="btn-qty" data-action="qty" data-id="'+idx+'" data-arah="-1"'+(kosong?' disabled':'')+'>-</button><div style="display:flex;align-items:baseline;gap:2px;min-width:45px;justify-content:center"><span class="angka-qty" id="qty-'+idx+'">0</span><span style="font-size:.75rem;font-weight:700;color:#555">'+esc(sat)+'</span></div><button class="btn-qty" data-action="qty" data-id="'+idx+'" data-arah="1"'+(kosong?' disabled':'')+'>+</button></div></div></div>');idx++});document.getElementById('tempat-katalog').innerHTML='';addBatch(BATAS);pasangDelegasi();updBadge();animCari();autoSlide();const ws=localStorage.getItem('waktu_scroll_gudang');if(ws){const sel=Date.now()-parseInt(ws,10);if(sel<5*60*1000){const j=parseInt(localStorage.getItem('jumlah_tampil_gudang')||'0',10);if(j>20)addBatch(j-20);const ps=parseInt(localStorage.getItem('posisi_scroll_gudang')||'0',10);if(ps>0){const t=document.getElementById('tempat-katalog');t.style.visibility='hidden';requestAnimationFrame(()=>{window.scrollTo(0,ps);setTimeout(()=>t.style.visibility='visible',50)})}}else{['posisi_scroll_gudang','waktu_scroll_gudang','jumlah_tampil_gudang'].forEach(k=>localStorage.removeItem(k))}}}catch(e){console.error(e);document.getElementById('tempat-katalog').innerHTML='<div style="text-align:center;padding:40px 20px"><p style="color:#dc2626;font-weight:700">Gagal memuat barang. Periksa koneksi internet.</p><button onclick="ambilData()" style="padding:10px 20px;background:#EA580C;color:#fff;border:none;border-radius:8px;margin-top:10px;cursor:pointer">Coba Lagi</button></div>'}}
function pasangDelegasi(){const k=document.getElementById('tempat-katalog');if(k.dataset.bound==='1')return;k.dataset.bound='1';k.addEventListener('click',e=>{const b=e.target.closest('button');if(!b)return;if(b.classList.contains('btn-varian')){const id=parseInt(b.dataset.id,10),i=parseInt(b.dataset.idx,10),br=dataKatalog[id];if(!br)return;const v=br.varian[i];if(v)pilihVarian(id,v);return}if(b.dataset.action==='qty'){ubahQty(parseInt(b.dataset.id,10),parseInt(b.dataset.arah,10))}});k.addEventListener('scroll',e=>{const s=e.target;if(s.classList&&s.classList.contains('slider-gambar')){const t=parseInt(s.dataset.total,10)||1,c=s.parentElement.querySelector('.slider-counter');if(c&&s.clientWidth)c.innerText=(Math.round(s.scrollLeft/s.clientWidth)+1)+'/'+t}},true)}
function pilihVarian(id,v){const b=dataKatalog[id];if(!b||b.isKosong)return;stateVarian[id]=v;updKartu(id)}
function ubahQty(id,a){const b=dataKatalog[id];if(!b||b.isKosong)return;let v='';if(b.varian.length>0){if(!stateVarian[id]){alertBox('Silakan pilih varian terlebih dahulu!');return}v=stateVarian[id]}ubahQtyProses(id,v,a)}
function ubahQtyModal(k,a){const i=k.indexOf('_');ubahQtyProses(k.substring(0,i),k.substring(i+1),a,true)}
function ubahQtyProses(id,v,a,modal){const b=dataKatalog[id];if(!b)return;const k=b.nama+'_'+v,q=keranjang[k]?keranjang[k].qty:0;let nq=q+(a*b.kelipatan);if(nq<=0)delete keranjang[k];else{nq=Math.round(nq*100)/100;keranjang[k]={id:b.nama,varian:v,qty:nq}}localStorage.setItem(CART_KEY,JSON.stringify(keranjang));updBadge();updKartu(id);if(modal||document.getElementById('modal-keranjang').style.display==='flex'){const mk=id+'_'+v,eq=document.getElementById('modal-qty-'+mk),et=document.getElementById('modal-total-'+mk),er=document.getElementById('row-modal-'+mk);if(eq){eq.innerText=nq>0?nq:0;if(et)et.innerText=rp(nq*b.harga)}if(er){const inf=er.querySelector('.info-item-keranjang');if(inf)inf.style.opacity=nq<=0?'0.4':'1';const m=er.querySelectorAll('.btn-qty')[0];if(m)m.disabled=nq<=0}kalkTotal()}}
function updBadge(){const t=Object.keys(keranjang).length,b=document.getElementById('badge-qty');b.innerText=t;if(t>0){b.style.transform='scale(1.2)';setTimeout(()=>b.style.transform='scale(1)',200)}}
function kalkTotal(){let t=0;for(const k in keranjang){const i=keranjang[k],b=katalogByNama[i.id];if(b)t+=i.qty*b.harga}document.getElementById('total-harga-keranjang').innerText=rp(t)}
function bukaKeranjang(){const lp=document.getElementById('list-pesanan'),ks=Object.keys(keranjang);if(ks.length===0){lp.innerHTML="<p style='text-align:center;color:#999;margin-top:30px'>Keranjang masih kosong.</p>"}else{let h='';for(const k of ks){const i=keranjang[k],b=katalogByNama[i.id];if(!b)continue;const st=i.qty*b.harga,nc=i.varian?b.nama+' '+i.varian:b.nama;const mk=b.id+'_'+i.varian;h+='<div class="item-pesanan" id="row-modal-'+esc(mk)+'"><div class="info-item-keranjang"><div class="item-pesanan-nama">'+esc(nc)+'</div><div class="item-pesanan-harga">'+rp(b.harga)+' / '+esc(b.satuan.trim())+'</div><div class="total-harga-item" id="modal-total-'+esc(mk)+'">'+rp(st)+'</div></div><div class="kontrol-qty" style="margin:0"><button class="btn-qty" data-key="'+esc(mk)+'" data-arah="-1">-</button><div style="display:flex;align-items:baseline;gap:2px;min-width:45px;justify-content:center"><span class="angka-qty" id="modal-qty-'+esc(mk)+'">'+i.qty+'</span><span style="font-size:.75rem;font-weight:700;color:#555">'+esc(b.satuan.trim())+'</span></div><button class="btn-qty" data-key="'+esc(mk)+'" data-arah="1">+</button></div></div>'}lp.innerHTML=h;if(lp.dataset.bound!=='1'){lp.dataset.bound='1';lp.addEventListener('click',e=>{const b=e.target.closest('.btn-qty');if(!b)return;ubahQtyModal(b.dataset.key,parseInt(b.dataset.arah,10))})}}kalkTotal();document.getElementById('modal-keranjang').style.display='flex';pushM('keranjang');document.body.style.overflow='hidden'}
function tutupKeranjang(){if(window.history.state&&window.history.state.modal==='keranjang')window.history.back();else{document.getElementById('modal-keranjang').style.display='none';document.body.style.overflow=''}}
function kirimKeWA(){const k=document.getElementById('inputKios').value.trim(),d=document.getElementById('inputDaerah').value;if(!k||k==='KIOS'||k==='KIOS '||!d){alertBox('Mohon lengkapi Nama Kios dan pilih Daerah!');return}let ada=false;for(const x in keranjang){if(keranjang[x].qty>0){ada=true;break}}if(!ada){alertBox('Keranjang kosong!');return}if(!nomorWA){alertBox('Nomor WA owner belum tersedia.');return}document.getElementById('modalKonfirmasiWA').style.display='flex';pushM('konfirmasiWA')}
function eksekusiKirimWA(){const wt=localStorage.getItem('waktu_kirim_wa');if(wt){const s=Date.now()-parseInt(wt,10);if(s<WA_CD){const sisa=Math.ceil((WA_CD-s)/1000);alertBox('Mohon tunggu '+sisa+' detik lagi.');return}}tutupKonfirmasiWA();const k=document.getElementById('inputKios').value.trim(),d=document.getElementById('inputDaerah').value;let p='Halo Mas Septa, saya ada pesanan baru:\n\nNama Kios: '+k+'\nDaerah Tujuan: '+d+'\n--------------------------\n\n',t=0;for(const x in keranjang){const i=keranjang[x],b=katalogByNama[i.id];if(b&&i.qty>0){const st=i.qty*b.harga;t+=st;const nc=i.varian?b.nama+' ('+i.varian+')':b.nama;p+='- '+nc+'\n  '+i.qty+' '+b.satuan.trim()+' x '+rp(b.harga)+' = '+rp(st)+'\n'}}p+='\nTotal Semua = '+rp(t);const now=Date.now().toString();localStorage.setItem(CART_TS,now);localStorage.setItem('waktu_kirim_wa',now);['posisi_scroll_gudang','waktu_scroll_gudang','jumlah_tampil_gudang'].forEach(k=>localStorage.removeItem(k));window.location.href='whatsapp://send?phone='+nomorWA+'&text='+encodeURIComponent(p)}
function tutupKonfirmasiWA(){if(window.history.state&&window.history.state.modal==='konfirmasiWA')window.history.back();else document.getElementById('modalKonfirmasiWA').style.display='none'}
function jalankanCari(e){if(e)e.preventDefault();if(location.hash!=='#cari')history.pushState(null,null,'#cari');const kw=document.getElementById('inputCari').value.toLowerCase().trim();document.getElementById('inputCari').blur();cari=kw.length>0;document.getElementById('btnBack').style.display=cari?'flex':'none';const tk=document.getElementById('tempat-katalog');if(cari){let h='',ids=[];for(let i=0;i<arrayHTML.length;i++){if(daftarNama[i].toLowerCase().includes(kw)){h+=arrayHTML[i];ids.push(i)}}tk.innerHTML=h||"<p style='text-align:center;margin-top:20px;color:#777'>Barang tidak ditemukan.</p>";ids.forEach(i=>updKartu(i));window.scrollTo({top:0,behavior:'smooth'})}else{tk.innerHTML='';const m=jmlTampil;jmlTampil=0;addBatch(m>0?m:BATAS)}}
document.getElementById('inputCari').addEventListener('input',function(){document.getElementById('btnClear').style.display=this.value.length>0?'flex':'none'});
function clearInput(){const i=document.getElementById('inputCari');i.value='';document.getElementById('btnClear').style.display='none';i.focus()}
function resetCari(){if(location.hash==='#cari')history.replaceState(null,null,location.pathname+location.search);document.getElementById('inputCari').value='';document.getElementById('btnClear').style.display='none';document.getElementById('btnBack').style.display='none';cari=false;showPH();jalankanCari({})}
function hidePH(){document.getElementById('wadah-placeholder').style.display='none'}
function showPH(){if(document.getElementById('inputCari').value==='')document.getElementById('wadah-placeholder').style.display='flex'}
let intAnim=null;
function animCari(){if(daftarNama.length===0)return;if(intAnim)clearInterval(intAnim);let i=0;const t=document.getElementById('teks-animasi');t.innerText=daftarNama[0];intAnim=setInterval(()=>{t.style.transform='translateY(-100%)';t.style.opacity='0';setTimeout(()=>{i=(i+1)%daftarNama.length;t.innerText=daftarNama[i];t.style.transition='none';t.style.transform='translateY(100%)';requestAnimationFrame(()=>requestAnimationFrame(()=>{t.style.transition='transform .3s ease-out,opacity .3s ease-in';t.style.transform='translateY(0)';t.style.opacity='1'}))},300)},2500)}
function autoSlide(){document.querySelectorAll('.slider-gambar').forEach(s=>{if(s.children.length>1){setInterval(()=>{if(s.scrollLeft>=s.scrollWidth-s.clientWidth-5)s.scrollTo({left:0,behavior:'smooth'});else s.scrollBy({left:s.clientWidth,behavior:'smooth'})},3000)}})}
let scrollTimer=null;
window.addEventListener('scroll',function(){if(cari)return;if(scrollTimer)return;scrollTimer=setTimeout(()=>{scrollTimer=null;try{localStorage.setItem('posisi_scroll_gudang',window.scrollY.toString());localStorage.setItem('waktu_scroll_gudang',Date.now().toString());localStorage.setItem('jumlah_tampil_gudang',jmlTampil.toString())}catch(e){}const j=document.documentElement.scrollHeight-(window.innerHeight+window.scrollY);if(j<2500&&jmlTampil<arrayHTML.length)addBatch(BATAS)},300)},{passive:true});
window.onload=function(){muatPelanggan();ambilData()};
</script>
<script>
if('serviceWorker' in navigator){
  window.addEventListener('load',()=>{
    navigator.serviceWorker.register('sw.js')
      .then(r=>console.log('[PWA] SW aktif, scope:',r.scope))
      .catch(e=>console.warn('[PWA] SW gagal:',e));
  });
}
let deferredPrompt=null;
const btnInstall=document.getElementById('btnInstallPWA');
window.addEventListener('beforeinstallprompt',(e)=>{
  e.preventDefault();
  deferredPrompt=e;
  if(btnInstall)btnInstall.style.display='flex';
});
if(btnInstall){
  btnInstall.addEventListener('click',async()=>{
    if(!deferredPrompt)return;
    btnInstall.style.display='none';
    deferredPrompt.prompt();
    await deferredPrompt.userChoice;
    deferredPrompt=null;
  });
}
window.addEventListener('appinstalled',()=>{
  if(btnInstall)btnInstall.style.display='none';
  console.log('[PWA] Terinstall');
});
</script>
</body>
</html>
HTMLEOF

if ! grep -q '</html>' "$APP_DIR/index.html"; then
    die "index.html tidak lengkap"
fi
ok "index.html dibuat & divalidasi"

# ============================================================
# 5B. FILE PWA (manifest, service worker, icon)
# ============================================================
log "[5B/12] Tulis file PWA..."

cat > "$APP_DIR/manifest.json" <<'MANIFESTEOF'
{
  "name": "Gudangbarang.com — Mas Septa",
  "short_name": "GudangBarang",
  "description": "Katalog barang Gudangbarang.com — pesan langsung via WhatsApp",
  "start_url": "./",
  "scope": "./",
  "display": "standalone",
  "orientation": "portrait",
  "background_color": "#f5f5f5",
  "theme_color": "#EA580C",
  "lang": "id",
  "dir": "ltr",
  "categories": ["shopping", "business"],
  "icons": [
    { "src": "icon.svg", "sizes": "any", "type": "image/svg+xml", "purpose": "any" },
    { "src": "icon.svg", "sizes": "any", "type": "image/svg+xml", "purpose": "maskable" }
  ]
}
MANIFESTEOF

cat > "$APP_DIR/icon.svg" <<'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#F97316"/>
      <stop offset="100%" stop-color="#EA580C"/>
    </linearGradient>
  </defs>
  <rect width="512" height="512" rx="112" fill="url(#bg)"/>
  <path d="M 140 200 L 372 200 L 372 410 Q 372 442 340 442 L 172 442 Q 140 442 140 410 Z" fill="#ffffff"/>
  <rect x="128" y="180" width="256" height="40" rx="16" fill="#ffffff" opacity="0.85"/>
  <path d="M 200 200 Q 200 110 256 110 Q 312 110 312 200" fill="none" stroke="#ffffff" stroke-width="26" stroke-linecap="round"/>
  <path d="M 195 320 L 240 365 L 325 275" fill="none" stroke="#EA580C" stroke-width="34" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
SVGEOF

cat > "$APP_DIR/sw.js" <<'SWEOF'
const CACHE_NAME = 'gudangbarang-pwa-v1';
const VPN_PATHS = ['/home', '/home2', '/grpc', '/upgrade'];
const STATIC_ASSETS = ['./', './index.html', './manifest.json', './icon.svg'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(STATIC_ASSETS).catch(err => {
        console.warn('[SW] Install partial:', err);
      }))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  if (VPN_PATHS.some(p => url.pathname === p || url.pathname.startsWith(p + '/'))) return;
  if (req.headers.get('upgrade') === 'websocket') return;

  if (url.pathname.endsWith('/data.json')) {
    event.respondWith(
      fetch(req).then(res => {
        if (res && res.status === 200) {
          const clone = res.clone();
          caches.open(CACHE_NAME).then(c => c.put(new Request('/data.json'), clone));
        }
        return res;
      }).catch(() => caches.match('/data.json'))
    );
    return;
  }

  if (url.pathname.startsWith('/gambar/')) {
    event.respondWith(
      caches.open(CACHE_NAME).then(cache =>
        cache.match(req).then(cached => {
          const netFetch = fetch(req).then(res => {
            if (res && res.status === 200) cache.put(req, res.clone());
            return res;
          }).catch(() => cached);
          return cached || netFetch;
        })
      )
    );
    return;
  }

  event.respondWith(
    caches.match(req).then(cached => {
      if (cached) return cached;
      return fetch(req).then(res => {
        if (res && res.status === 200 && res.type === 'basic') {
          const clone = res.clone();
          caches.open(CACHE_NAME).then(c => c.put(req, clone));
        }
        return res;
      }).catch(() => {
        if (req.mode === 'navigate') return caches.match('/index.html');
      });
    })
  );
});
SWEOF

chmod 644 "$APP_DIR/manifest.json" "$APP_DIR/icon.svg" "$APP_DIR/sw.js"
ok "PWA files dibuat (manifest.json, sw.js, icon.svg)"

# ============================================================
# 6. SYNC.JS (FIXED Object.assign BUG)
# ============================================================
log "[6/12] Tulis sync.js..."
mkdir -p "$SYNC_DIR"

cat > "$SYNC_DIR/sync.js" <<'JSEOF'
'use strict';
const fs=require('fs'),path=require('path');
const SHEET_ID='12dmJadrRGYoTKg_nOA4GoCwlntjjO2EjG0tYCz-yFss';
const SHEET_URL='https://docs.google.com/spreadsheets/d/'+SHEET_ID+'/gviz/tq?tqx=out:json';
const DIR='/var/www/html/gambar',FILE='/var/www/html/data.json';
const MAX=2*1024*1024,TO=15000;
if(!fs.existsSync(DIR))fs.mkdirSync(DIR,{recursive:true});
const delay=ms=>new Promise(r=>setTimeout(r,ms));

async function fT(u,o,t){
  o=o||{};t=t||TO;
  const c=new AbortController();
  const id=setTimeout(()=>c.abort(),t);
  try{
    return await fetch(u,Object.assign({},o,{signal:c.signal}));
  }finally{
    clearTimeout(id);
  }
}

function driveId(u){try{const x=new URL(u);if(x.hostname.includes('google')){const i=x.searchParams.get('id');if(i)return i;const m=x.pathname.match(/\/d\/([^/]+)/);if(m)return m[1]}return null}catch(e){return null}}
function deteksiExt(buf){
  const s=buf.slice(0,12);
  if(s[0]===0xFF&&s[1]===0xD8)return'.jpg';
  if(s[0]===0x89&&s[1]===0x50)return'.png';
  if(s[0]===0x47&&s[1]===0x49)return'.gif';
  if(s.toString('ascii',0,4)==='RIFF'&&s.toString('ascii',8,12)==='WEBP')return'.webp';
  // AVIF: bytes 4-11 = "ftypavif"
  if(s.toString('ascii',4,12)==='ftypavif')return'.avif';
  return null;
}
function nFile(u){try{const id=driveId(u);if(id)return id;const last=new URL(u).pathname.split('/').filter(Boolean).pop();if(last&&last.includes('.'))return last;return Buffer.from(u).toString('hex').slice(0,16)}catch(e){return null}}
function cariFileAda(id){for(const ext of['.jpg','.jpeg','.png','.gif','.webp','.avif','']){const p=path.join(DIR,id+ext);if(fs.existsSync(p))return p}return null}
async function getSheet(){const r=await fT(SHEET_URL,{headers:{'User-Agent':'Mozilla/5.0'}});if(!r.ok)throw new Error('HTTP '+r.status);const t=await r.text();const s=t.indexOf('{'),e=t.lastIndexOf('}');if(s===-1||e===-1)throw new Error('Format sheet invalid');return t.substring(s,e+1)}
async function unduh(u){
  const nama=nFile(u);
  if(!nama)return;
  if(cariFileAda(nama))return;
  for(let a=1;a<=3;a++){
    try{
      const r=await fT(u,{headers:{'User-Agent':'Mozilla/5.0'},redirect:'follow'});
      if(!r.ok)throw new Error('HTTP '+r.status);
      const b=Buffer.from(await r.arrayBuffer());
      if(b.byteLength>MAX){console.log('Skip besar:',nama);return}
      if(b.byteLength<512){console.log('Skip kecil:',nama);return}
      let ext = deteksiExt(b);
      if(!ext){
          // Cek apakah link URL sudah memiliki akhiran format yang sah
          const cocok = nama.match(/\.(jpg|jpeg|png|gif|webp|avif)$/i);
          if (cocok) {
              ext = cocok[0]; // Paksa gunakan ekstensi dari link
          } else {
              console.log('Skip bukan gambar:', nama); return;
          }
      }
      
      // Mengecek apakah nama aslinya sudah berakhiran format gambar yang valid
      const namaFileFinal = /\.(jpg|jpeg|png|gif|webp|avif)$/i.test(nama) ? nama : nama + ext; 
      
      const target=path.join(DIR, namaFileFinal);
      fs.writeFileSync(target,b);
      console.log('Simpan:',namaFileFinal,'('+b.byteLength+'b)');
      return;
    }catch(e){
      console.warn('Attempt '+a+' gagal:',nama,e.message);
      if(a<3)await delay(2000);
    }
  }
}

(async()=>{
  try{
    console.log('['+new Date().toISOString()+'] Mulai sync...');
    const jt=await getSheet();
    JSON.parse(jt);
    fs.writeFileSync(FILE,jt);
    const d=JSON.parse(jt),rows=d.table.rows||[];
    let c=0;
    for(const r of rows){
      if(!r||!r.c)continue;
      const urls=[r.c[3]&&r.c[3].v,r.c[4]&&r.c[4].v,r.c[5]&&r.c[5].v];
      for(const u of urls){
        if(u&&typeof u==='string'&&/^https?:\/\//.test(u)){await unduh(u);c++}
      }
      await delay(300);
    }
    console.log('['+new Date().toISOString()+'] Selesai. Total URL: '+c+'\n');
  }catch(e){
    console.error('Error:',e.message);
    process.exitCode=1;
  }
})();
JSEOF
ok "sync.js dibuat"

# ============================================================
# 7. USER + PERMISSION + CRON
# ============================================================
log "[7/12] User, permission, cron..."

if ! id "$SYNC_USER" &>/dev/null; then
    useradd -r -s /usr/sbin/nologin -d "$SYNC_DIR" "$SYNC_USER" || warn "Buat user gagal"
fi
touch "$SYNC_DIR/sync.log"

chown -R www-data:www-data "$APP_DIR"
chmod -R 755 "$APP_DIR"

chown -R "$SYNC_USER":www-data "$APP_DIR/gambar"
chmod 755 "$APP_DIR/gambar"

touch "$APP_DIR/data.json"
chown "$SYNC_USER":"$SYNC_USER" "$APP_DIR/data.json"
chmod 644 "$APP_DIR/data.json"

chown -R "$SYNC_USER":"$SYNC_USER" "$SYNC_DIR"
chmod 750 "$SYNC_DIR"
usermod -aG www-data "$SYNC_USER" 2>/dev/null || true

NODE_PATH="$(command -v node)"
[[ -z "$NODE_PATH" ]] && die "Node tidak ada"

cat > /etc/cron.d/sync-gudang <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
*/5 * * * * $SYNC_USER cd $SYNC_DIR && $NODE_PATH sync.js >>$SYNC_DIR/sync.log 2>&1
EOF
printf '\n' >> /etc/cron.d/sync-gudang
chmod 644 /etc/cron.d/sync-gudang

cat > /etc/logrotate.d/sync-gudang <<EOF
$SYNC_DIR/sync.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    create 0640 $SYNC_USER $SYNC_USER
}
EOF
ok "User+cron+logrotate+data.json OK"

# ============================================================
# 8. SSL
# ============================================================
log "[8/12] SSL..."
systemctl stop nginx 2>/dev/null || true

if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    certbot certonly --standalone --preferred-challenges http --agree-tos \
        --email "admin@$DOMAIN" -d "$DOMAIN" --non-interactive \
        || { warn "Certbot gagal"; systemctl start nginx; die "Cek DNS $DOMAIN & port 80 terbuka"; }
    ok "SSL didapat"
else
    ok "SSL sudah ada"
fi

cat > /etc/cron.d/certbot-renew <<'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 0 1 * * root certbot renew --quiet --deploy-hook "systemctl reload nginx"
EOF
printf '\n' >> /etc/cron.d/certbot-renew
chmod 644 /etc/cron.d/certbot-renew
systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true

# ============================================================
# 9. XRAY CONFIG
# ============================================================
log "[9/12] Konfigurasi Xray..."
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    { "tag":"vless-ws","port":1234,"listen":"127.0.0.1","protocol":"vless",
      "settings":{"clients":[{"id":"$UUID"}],"decryption":"none"},
      "streamSettings":{"network":"ws","wsSettings":{"path":"/home"}} },
    { "tag":"vless-xhttp","port":1236,"listen":"127.0.0.1","protocol":"vless",
      "settings":{"clients":[{"id":"$UUID"}],"decryption":"none"},
      "streamSettings":{"network":"xhttp","xhttpSettings":{"path":"/home2","mode":"stream-up"}} },
    { "tag":"vless-grpc","port":1237,"listen":"127.0.0.1","protocol":"vless",
      "settings":{"clients":[{"id":"$UUID"}],"decryption":"none"},
      "streamSettings":{"network":"grpc","grpcSettings":{"serviceName":"grpc"}} },
    { "tag":"vless-upgrade","port":1238,"listen":"127.0.0.1","protocol":"vless",
      "settings":{"clients":[{"id":"$UUID"}],"decryption":"none"},
      "streamSettings":{"network":"httpupgrade","httpupgradeSettings":{"path":"/upgrade"}} }
  ],
  "outbounds": [{ "protocol":"freedom", "tag":"direct" }]
}
EOF
ok "Xray config dibuat"

# ============================================================
# 10. NGINX CONFIG
# ============================================================
log "[10/12] Konfigurasi Nginx..."

NGV=$(nginx -v 2>&1 | grep -oP '\d+\.\d+' | head -1)
NMaj=$(echo "$NGV" | cut -d. -f1)
NMin=$(echo "$NGV" | cut -d. -f2)
if [[ "$NMaj" -gt 1 ]] || { [[ "$NMaj" -eq 1 ]] && [[ "$NMin" -ge 25 ]]; }; then
    H2S="http2 on;"
    H2L=""
else
    H2S=""
    H2L=" http2"
fi
log "Nginx $NGV — pakai mode: $([ -n "$H2S" ] && echo 'directive baru' || echo 'syntax lama')"

cat > /etc/nginx/sites-available/default <<EOF
limit_req_zone \$binary_remote_addr zone=vpn_limit:10m rate=10r/s;

server {
    listen 443 ssl$H2L;
    listen 8443 ssl$H2L;
    listen 2053 ssl$H2L;
    listen 2083 ssl$H2L;
    $H2S
    server_name $DOMAIN;

    ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    root /var/www/html;
    index index.html;
    client_max_body_size 10m;

    location = /index.html {
        add_header Cache-Control "no-store, must-revalidate";
    }

    location / { try_files \$uri \$uri/ /index.html; }
    location ~* \.(jpg|jpeg|png|gif|webp|avif|svg|ico)\$ { expires 7d; add_header Cache-Control "public"; }
    location ~* \.(json)\$ { expires -1; add_header Cache-Control "no-store"; }

    location = /sw.js {
        add_header Cache-Control "no-store, must-revalidate";
        add_header Service-Worker-Allowed "/";
        types { } default_type application/javascript;
    }

    location = /manifest.json {
        add_header Cache-Control "no-store, must-revalidate";
        types { } default_type application/manifest+json;
    }

    location /home {
        limit_req zone=vpn_limit burst=10 nodelay;
        if (\$http_upgrade != "websocket") { rewrite ^ /index.html last; }
        proxy_pass http://127.0.0.1:1234;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
    location /home2 {
        limit_req zone=vpn_limit burst=10 nodelay;
        proxy_pass http://127.0.0.1:1236;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
    location /grpc {
        if (\$request_method != "POST") { return 404; }
        if (\$content_type !~ "application/grpc") { return 404; }
        grpc_pass grpc://127.0.0.1:1237;
        grpc_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
    location /upgrade {
        limit_req zone=vpn_limit burst=10 nodelay;
        if (\$http_upgrade = "") { rewrite ^ /index.html last; }
        proxy_pass http://127.0.0.1:1238;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}

server {
    listen 80;
    listen 8080;
    listen 8880;
    listen 2052;
    listen 2082;
    server_name $DOMAIN;

    root /var/www/html;
    index index.html;
    client_max_body_size 10m;

    location = /index.html {
        add_header Cache-Control "no-store, must-revalidate";
    }

    location / { try_files \$uri \$uri/ /index.html; }

    location = /sw.js {
        add_header Cache-Control "no-store, must-revalidate";
        add_header Service-Worker-Allowed "/";
        types { } default_type application/javascript;
    }

    location = /manifest.json {
        add_header Cache-Control "no-store, must-revalidate";
        types { } default_type application/manifest+json;
    }

    location /home {
        limit_req zone=vpn_limit burst=10 nodelay;
        if (\$http_upgrade != "websocket") { rewrite ^ /index.html last; }
        proxy_pass http://127.0.0.1:1234;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
    }
    location /home2 {
        limit_req zone=vpn_limit burst=10 nodelay;
        proxy_pass http://127.0.0.1:1236;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
    }
    location /upgrade {
        limit_req zone=vpn_limit burst=10 nodelay;
        if (\$http_upgrade = "") { rewrite ^ /index.html last; }
        proxy_pass http://127.0.0.1:1238;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

if ! nginx -t 2>/tmp/nginx-test-error.log; then
    warn "nginx -t GAGAL. Output:"
    cat /tmp/nginx-test-error.log | tee -a "$LOG_FILE"
    if [[ -f "$BACKUP_DIR/default" ]]; then
        warn "Restore config dari backup..."
        cp "$BACKUP_DIR/default" /etc/nginx/sites-available/default
        if nginx -t 2>/dev/null; then
            ok "Config lama di-restore, nginx OK"
        else
            die "Bahkan config backup gagal. Cek manual: nginx -t"
        fi
    else
        die "Tidak ada backup. Cek manual: nginx -t"
    fi
fi
ok "Nginx config valid"

# ============================================================
# 11. RESTART + HEALTH CHECK + TELEGRAM
# ============================================================
log "[11/12] Restart + Health Check..."
systemctl restart nginx xray || die "Restart gagal"
systemctl enable nginx xray fail2ban >/dev/null 2>&1 || true
sleep 3

log "===== HEALTH CHECK ====="
systemctl is-active --quiet nginx && ok "[1/10] nginx RUNNING" || warn "[1/10] nginx DOWN"
systemctl is-active --quiet xray  && ok "[2/10] xray RUNNING"  || warn "[2/10] xray DOWN"
systemctl is-active --quiet fail2ban && ok "[3/10] fail2ban RUNNING" || warn "[3/10] fail2ban DOWN"

HTTP=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$DOMAIN/" --max-time 10 || echo "000")
[[ "$HTTP" == "200" ]] && ok "[4/10] Web HTTPS 200" || warn "[4/10] Web HTTPS HTTP $HTTP"

HC=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$DOMAIN/home" --max-time 5 || echo "000")
if [[ "$HC" == "400" || "$HC" == "404" || "$HC" == "200" ]]; then
    ok "[5/10] VPN /home reachable (HTTP $HC)"
else
    warn "[5/10] VPN /home HTTP $HC"
fi

if xray -test -config /usr/local/etc/xray/config.json >/tmp/xray-test.log 2>&1; then
    ok "[6/10] Xray config VALID"
else
    warn "[6/10] Xray config INVALID. Output:"
    cat /tmp/xray-test.log | tee -a "$LOG_FILE"
fi

[[ -f /etc/cron.d/sync-gudang ]] && ok "[7/10] Cron sync OK" || warn "[7/10] Cron tidak ada"
id "$SYNC_USER" &>/dev/null && ok "[8/10] User $SYNC_USER OK" || warn "[8/10] User tidak ada"

# Cek file PWA
for pwa_file in manifest.json sw.js icon.svg; do
    if [[ -f "$APP_DIR/$pwa_file" ]]; then
        ok "[9/10] File PWA $pwa_file OK"
    else
        warn "[9/10] File PWA $pwa_file HILANG"
    fi
done

# Cek PWA accessible via HTTPS
PWA_CHECK=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$DOMAIN/manifest.json" --max-time 5 || echo "000")
if [[ "$PWA_CHECK" == "200" ]]; then
    ok "[10/10] PWA manifest accessible (HTTP 200)"
else
    warn "[10/10] PWA manifest HTTP $PWA_CHECK"
fi

L1="vless://$UUID@$DOMAIN:443?path=%2Fhome&security=tls&encryption=none&type=ws&sni=$BUG_SNI&host=$DOMAIN#WS_TLS"
L2="vless://$UUID@$DOMAIN:443?path=%2Fhome2&security=tls&encryption=none&type=xhttp&sni=$BUG_SNI&host=$DOMAIN#XHTTP_TLS"
L3="vless://$UUID@$DOMAIN:443?mode=multi&security=tls&encryption=none&type=grpc&serviceName=grpc&sni=$BUG_SNI&host=$DOMAIN#GRPC_TLS"
L4="vless://$UUID@$DOMAIN:443?path=%2Fupgrade&security=tls&encryption=none&type=httpupgrade&sni=$BUG_SNI&host=$DOMAIN#UPGRADE_TLS"
L5="vless://$UUID@$DOMAIN:80?path=%2Fhome&security=none&encryption=none&type=ws&host=$DOMAIN#WS_NTLS"
L6="vless://$UUID@$DOMAIN:80?path=%2Fhome2&security=none&encryption=none&type=xhttp&host=$DOMAIN#XHTTP_NTLS"
L7="vless://$UUID@$DOMAIN:80?path=%2Fupgrade&security=none&encryption=none&type=httpupgrade&host=$DOMAIN#UPGRADE_NTLS"

ALL_LINKS="🌐 Website: https://$DOMAIN
📱 PWA: Install dari Chrome → menu → Install app
🎯 SNI: $BUG_SNI
📖 README: $SYNC_DIR/README.md

━━━━━━━━━━━━━━━
📦 <b>V2RAY CONFIGS</b>
━━━━━━━━━━━━━━━
<code>$L1</code>

<code>$L2</code>

<code>$L3</code>

<code>$L4</code>

<code>$L5</code>

<code>$L6</code>

<code>$L7</code>"

if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -H 'Content-Type: application/json' \
        -d "$(jq -n --arg c "$CHAT_ID" --arg t "$ALL_LINKS" '{chat_id:$c,text:$t,parse_mode:"HTML"}')" \
        >/dev/null && ok "Telegram terkirim" || warn "Telegram gagal"
fi

# ============================================================
# 12. README + SYNC PERTAMA + VALIDASI
# ============================================================
log "[12/12] README + Sync pertama..."

cat > "$SYNC_DIR/README.md" <<'MDEOF'
# Panduan Gudang Katalog + VPN + PWA (v3.0)

## Lokasi File
- /var/www/html/index.html       - Website katalog (PWA ready)
- /var/www/html/manifest.json    - PWA manifest
- /var/www/html/sw.js            - Service Worker
- /var/www/html/icon.svg         - Icon aplikasi (orange)
- /var/www/html/data.json        - Data katalog (auto-sync)
- /var/www/html/gambar/          - Gambar produk
- /opt/sync-gudang/sync.js       - Script sync Google Sheets
- /opt/sync-gudang/sync.log      - Log sync
- /usr/local/etc/xray/config.json - Config Xray
- /etc/nginx/sites-available/default - Config Nginx
- /var/log/install-katalog.log   - Log instalasi

## Cara Manual
Sync ulang: sudo -u syncworker bash -c "cd /opt/sync-gudang && node sync.js"
Cek log:    tail -f /opt/sync-gudang/sync.log
Restart:    systemctl restart nginx xray

## Ganti UUID
sudo nano /usr/local/etc/xray/config.json
sudo systemctl restart xray

## Update PWA (kalau edit file PWA)
Naikkan versi CACHE_NAME di /var/www/html/sw.js (v1 -> v2)
User akan auto-update dalam 1-2 load berikutnya.

## Reset Keranjang (di browser user)
localStorage.removeItem('keranjang_gudang_septa_v2');
location.reload();
MDEOF

chown "$SYNC_USER":"$SYNC_USER" "$SYNC_DIR/README.md"
ok "README.md dibuat"

NODE_PATH=$(command -v node)
if [[ -n "$NODE_PATH" ]]; then
    sudo -u "$SYNC_USER" bash -c "cd $SYNC_DIR && $NODE_PATH sync.js" \
        || warn "Sync pertama gagal (cek: tail $SYNC_DIR/sync.log)"
fi

if [ -s "$APP_DIR/data.json" ]; then
    DATA_SIZE=$(stat -c%s "$APP_DIR/data.json")
    ok "data.json terisi ($DATA_SIZE bytes)"
else
    warn "data.json KOSONG — sync silent fail, cek: tail $SYNC_DIR/sync.log"
fi

cat <<EOF | tee -a "$LOG_FILE"

==================================================
 ✅ INSTALASI SELESAI (v3.0 — PWA Ready)
==================================================
 🌐 Web        : https://$DOMAIN
 📱 PWA        : Ready (manifest + sw + icon)
 🎨 Theme      : Orange #EA580C
 🛡️ VPN Paths  : /home, /home2, /grpc, /upgrade
 📖 README     : $SYNC_DIR/README.md
 📦 Backup     : $BACKUP_DIR
 🔄 Cron sync  : tiap 5 menit (user: $SYNC_USER)
 🧾 Log instal : $LOG_FILE
 🧾 Log sync   : $SYNC_DIR/sync.log
==================================================

📲 Cara install PWA di Android:
   1. Buka https://$DOMAIN di Chrome
   2. Refresh 1-2×
   3. Klik tombol "📲 Install Aplikasi" di kanan bawah
   4. Icon orange muncul di home screen
==================================================
EOF
