#!/bin/bash

# ============================================================
#   AUTO INSTALL: VPN (XRAY) + WEBSITE KATALOG + AUTO SYNC
#   1 Domain, 1 Server
# ============================================================

# --- KONFIGURASI UTAMA ---
DOMAIN="gudangbarang.com"
UUID="07e329c4-5b6b-41da-b4aa-0c8ca3e3fbfa"
BOT_TOKEN="7484227045:AAENQc5Dp8_Nno8Oarl79IfAZZtbg4eIQC0"
CHAT_ID="5026145251"

# Pastikan script dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo "Harap jalankan script ini sebagai root (sudo su)."
  exit 1
fi

# ============================================================
# --- 1. UPDATE & INSTALL DEPENDENCIES (Termasuk Node.js) ---
# ============================================================
echo "=================================================="
echo " [1/9] Update sistem dan install tools & Node.js..."
echo "=================================================="
apt update && apt upgrade -y
apt install -y curl socat xz-utils wget nginx certbot python3-certbot-nginx jq cron

# Install Node.js v20 (Dibutuhkan untuk sync.js)
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# ============================================================
# --- 2. TINGKATKAN LIMIT FILE DESCRIPTOR ---
# ============================================================
echo "=================================================="
echo " [2/9] Meningkatkan limit file descriptor..."
echo "=================================================="
cat <<EOF > /etc/security/limits.conf
* soft nofile 512000
* hard nofile 512000
root soft nofile 512000
root hard nofile 512000
EOF
ulimit -n 512000

# ============================================================
# --- 3. AKTIFKAN TCP BBR & TUNING KERNEL ---
# ============================================================
echo "=================================================="
echo " [3/9] Mengaktifkan TCP BBR dan Tuning Jaringan..."
echo "=================================================="
cat <<EOF > /etc/sysctl.d/99-xray.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.ip_local_port_range = 10000 65000
fs.file-max = 512000
EOF
sysctl --system

# ============================================================
# --- 4. INSTALL XRAY CORE ---
# ============================================================
echo "=================================================="
echo " [4/9] Menginstall Xray Core..."
echo "=================================================="
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# ============================================================
# --- 5. BUAT WEBSITE KATALOG & SCRIPT SYNC ---
# ============================================================
echo "=================================================="
echo " [5/9] Membuat halaman web katalog & script sync..."
echo "=================================================="

# Buat direktori aplikasi dan gambar
APP_DIR="/var/www/html"
mkdir -p $APP_DIR/gambar

# --- A. MENULIS FILE HTML ---
cat <<'HTMLEOF' > $APP_DIR/index.html
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>GudangBarang.com - Mas Septa</title>
    <style>
        html, body { font-family: 'Segoe UI', Tahoma, sans-serif; background-color: #333; margin: 0; padding: 0; width: 100%; min-height: 100vh; }
        .app-container { max-width: 480px; width: 100%; min-height: 100vh; margin: 0 auto; background-color: #f5f5f5; display: flex; flex-direction: column; position: relative; }
        .sticky-atas { position: sticky; top: 0; z-index: 30; box-shadow: 0 3px 8px rgba(0,0,0,0.1); }
        header { background: linear-gradient(135deg, #F97316, #EA580C); color: white; padding: 15px; text-align: center; }
        .header-title { font-size: 1.25rem; font-weight: 900; margin: 0; }
        .header-owner { font-size: 0.65rem; font-weight: 600; margin: 4px 0 2px 0; letter-spacing: 2px; color: rgba(255, 255, 255, 0.8); text-transform: uppercase; }
        .header-subtitle { font-size: 0.85rem; font-weight: 700; margin: 0; }
        .wadah-pencarian { padding: 10px 15px; background: white; border-bottom: 1px solid #ddd; }
        .form-pencarian { display: flex; align-items: center; gap: 12px; width: 100%; }
        .btn-back { background: none; border: none; padding: 0; display: none; align-items: center; justify-content: center; cursor: pointer; color: #EA580C; }
        .input-wrapper { position: relative; flex-grow: 1; display: flex; align-items: center; border: 1.5px solid #EA580C; border-radius: 4px; background: white; overflow: hidden; height: 40px; }
        .input-wrapper input[type="search"] { width: 100%; height: 100%; padding: 0 35px 0 10px; border: none; outline: none; font-size: 0.95rem; background: transparent; z-index: 2; -webkit-appearance: none; }
        .input-wrapper input[type="search"]::-webkit-search-cancel-button { -webkit-appearance: none; }
        .btn-clear { position: absolute; right: 50px; background: #c4c4c4; color: white; border: none; width: 16px; height: 16px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 10px; cursor: pointer; padding: 0; z-index: 3; }
        .btn-search-orange { background: #EA580C; color: white; border: none; height: 100%; padding: 0 12px; display: flex; align-items: center; justify-content: center; cursor: pointer; z-index: 3; }
        .placeholder-animasi { position: absolute; left: 10px; top: 0; bottom: 0; display: flex; align-items: center; pointer-events: none; color: #999; z-index: 1; font-size: 0.95rem; overflow: hidden; white-space: nowrap; }
        .animasi-teks-wrapper { display: inline-block; height: 1.2em; overflow: hidden; margin-left: 4px; }
        .teks-bergerak { display: block; transition: transform 0.3s ease-in-out, opacity 0.3s ease; }
        .wadah-katalog { padding: 15px; padding-bottom: 100px; display: flex; flex-direction: column; gap: 20px; }
        .kartu-barang { background: white; padding: 15px; border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); position: relative; border-bottom: 6px solid transparent; transition: border-color 0.3s ease; }
        .kartu-barang.aktif-keranjang { border-bottom: 6px solid #25D366; }
        .teks-pilih-varian { font-size: 0.8rem; font-weight: 700; color: #555; margin-bottom: 6px; }
        .wadah-varian { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 15px; }
        .btn-varian { padding: 6px 14px; border: 1.5px solid #ddd; border-radius: 20px; background: white; color: #555; font-size: 0.85rem; font-weight: 600; cursor: pointer; transition: all 0.2s; }
        .btn-varian.aktif { border-color: #25D366; background: #e8fbf0; color: #25D366; }
        .btn-varian.di-keranjang { background: #25D366; color: white; border-color: #25D366; }
        .btn-varian.di-keranjang.aktif { box-shadow: 0 0 0 3px rgba(37, 211, 102, 0.3); }
        .slider-wrapper { position: relative; width: 100%; border-radius: 8px; overflow: hidden; background-color: #eee; }
        .slider-gambar { display: flex; overflow-x: auto; scroll-snap-type: x mandatory; scrollbar-width: none; scroll-behavior: smooth; }
        .slider-gambar::-webkit-scrollbar { display: none; }
        .slider-gambar img { flex: 0 0 100%; scroll-snap-align: center; width: 100%; height: 300px; object-fit: cover; -webkit-user-select: none; user-select: none; -webkit-touch-callout: none; }
        .gambar-kosong { filter: grayscale(100%); opacity: 0.75; }
        .slider-counter { position: absolute; top: 10px; right: 10px; background: rgba(0, 0, 0, 0.6); color: white; font-size: 0.75rem; font-weight: bold; padding: 4px 10px; border-radius: 12px; z-index: 5; pointer-events: none; }
        .watermark-kosong { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%) rotate(-25deg); color: rgba(255, 0, 0, 0.6); font-size: 2.5rem; font-weight: 900; letter-spacing: 2px; border: 5px solid rgba(255, 0, 0, 0.6); padding: 10px 20px; border-radius: 10px; z-index: 10; pointer-events: none; text-shadow: 2px 2px 4px rgba(255,255,255,0.8); }
        .nama-barang { font-size: 1.1rem; color: #333; margin: 15px 0 5px 0; font-weight: bold; }
        .harga-barang { color: #EA580C; font-weight: bold; font-size: 1.2rem; margin: 0 0 10px 0; }
        .wadah-deskripsi { border: 1.5px dashed #ccc; border-radius: 8px; padding: 10px; margin-bottom: 15px; background-color: #fafafa; }
        .judul-deskripsi { font-size: 0.8rem; font-weight: 700; color: #777; margin-bottom: 6px; }
        .keterangan-barang { font-size: 0.85rem; color: #444; white-space: pre-wrap; line-height: 1.4; margin: 0; }
        .area-bawah-kartu { display: flex; justify-content: space-between; align-items: center; border-top: 1px dashed #eee; padding-top: 10px; }
        .keterangan-singkat { font-size: 0.8rem; color: #777; flex: 1; }
        .kontrol-qty { display: flex; align-items: center; gap: 10px; background: #fff5ee; border: 1px solid #fed7aa; border-radius: 25px; padding: 3px; }
        .btn-qty { background: #EA580C; color: white; border: none; width: 32px; height: 32px; border-radius: 50%; font-size: 1.2rem; font-weight: bold; cursor: pointer; display: flex; align-items: center; justify-content: center; }
        .btn-qty:disabled { background: #ccc; cursor: not-allowed; }
        .btn-qty:active:not(:disabled) { transform: scale(0.95); }
        .angka-qty { font-weight: bold; min-width: 25px; text-align: center; color: #333; }
        .fab-keranjang { position: fixed; bottom: 20px; right: 20px; background-color: #EA580C; color: white; width: 60px; height: 60px; border-radius: 50%; display: flex; align-items: center; justify-content: center; box-shadow: 0 4px 12px rgba(234, 88, 12, 0.4); cursor: pointer; z-index: 50; transition: transform 0.2s; }
        .fab-keranjang:active { transform: scale(0.9); }
        .badge-keranjang { position: absolute; top: -5px; right: -5px; background: #dc2626; color: white; font-size: 0.75rem; font-weight: bold; width: 22px; height: 22px; border-radius: 50%; display: flex; align-items: center; justify-content: center; border: 2px solid white; }
        @media (min-width: 481px) { .fab-keranjang { right: calc(50% - 220px); } }
        .modal-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); z-index: 100; display: none; justify-content: center; align-items: flex-end; }
        .modal-content { background: white; width: 100%; max-width: 480px; max-height: 85%; border-radius: 20px 20px 0 0; padding: 20px; box-sizing: border-box; display: flex; flex-direction: column; animation: slideUp 0.3s ease-out; }
        @keyframes slideUp { from { transform: translateY(100%); } to { transform: translateY(0); } }
        .modal-header { display: flex; align-items: center; border-bottom: 1px solid #eee; padding-bottom: 10px; margin-bottom: 15px; gap: 10px; }
        .modal-header h2 { margin: 0; font-size: 1.2rem; color: #333; flex-grow: 1; }
        .btn-tutup { background: none; border: none; color: #EA580C; cursor: pointer; padding: 0; display: flex; align-items: center; }
        .list-pesanan { overflow-y: auto; flex-grow: 1; max-height: 50vh; padding-right: 5px; }
        .item-pesanan { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; border-bottom: 1px dashed #eee; padding-bottom: 15px; transition: opacity 0.3s ease; }
        .info-item-keranjang { flex: 1; padding-right: 15px; }
        .item-pesanan-nama { font-weight: bold; font-size: 0.95rem; margin-bottom: 4px; color: #333; text-transform: capitalize; }
        .item-pesanan-harga { font-size: 0.85rem; color: #777; margin-bottom: 5px; }
        .total-harga-item { font-weight: bold; color: #EA580C; font-size: 1rem; }
        .area-checkout { margin-top: 15px; padding-top: 15px; border-top: 2px solid #eee; }
        .form-tujuan { display: flex; flex-direction: column; gap: 10px; margin-bottom: 15px; }
        .input-tujuan { width: 100%; padding: 10px 12px; border: 1.5px solid #ccc; border-radius: 8px; font-size: 0.95rem; outline: none; box-sizing: border-box; background: #fff; }
        .input-tujuan:focus { border-color: #EA580C; }
        .baris-total { display: flex; justify-content: space-between; font-weight: bold; font-size: 1.2rem; margin-bottom: 15px; }
        .btn-wa-checkout { background: #25D366; color: white; border: none; width: 100%; padding: 15px; border-radius: 10px; font-size: 1rem; font-weight: bold; cursor: pointer; display: flex; justify-content: center; align-items: center; gap: 10px; }
        .teks-loading { text-align: center; color: #777; font-weight: bold; padding: 40px 0; }
        .konfirmasi-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.6); z-index: 999; display: none; justify-content: center; align-items: center; padding: 20px; }
        .konfirmasi-box { background: white; width: 100%; max-width: 320px; border-radius: 14px; padding: 20px; text-align: center; box-shadow: 0 4px 20px rgba(0,0,0,0.2); animation: scaleIn 0.2s ease-out; }
        @keyframes scaleIn { from { transform: scale(0.9); opacity: 0; } to { transform: scale(1); opacity: 1; } }
        .konfirmasi-box h3 { margin: 0 0 10px 0; color: #333; font-size: 1.1rem; }
        .konfirmasi-box p { color: #666; font-size: 0.9rem; margin-bottom: 20px; line-height: 1.4; }
        .konfirmasi-aksi { display: flex; gap: 10px; }
        .btn-konfirmasi { flex: 1; padding: 10px; border-radius: 8px; font-weight: bold; font-size: 0.95rem; cursor: pointer; border: none; }
        .btn-tidak { background: #e5e7eb; color: #333; }
        .btn-ya { background: #EA580C; color: white; }
        .btn-ok { background: #EA580C; color: white; flex: 1; }
    </style>
</head>
<body>
    <div class="app-container">
        <div class="sticky-atas">
            <header>
                <h1 class="header-title">GudangBarang.com</h1>
                <div class="header-owner">Owner</div>
                <p class="header-subtitle">Mas Septa</p>
            </header>
            <div class="wadah-pencarian">
                <form class="form-pencarian" action="javascript:void(0);" onsubmit="eksekusiPencarian(event)">
                    <button type="button" class="btn-back" id="btnBack" onclick="resetPencarian()">
                        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="19" y1="12" x2="5" y2="12"></line><polyline points="12 19 5 12 12 5"></polyline></svg>
                    </button>
                    <div class="input-wrapper">
                        <input type="search" id="inputCari" onfocus="sembunyikanPlaceholder()" onblur="tampilkanPlaceholder()">
                        <div id="wadah-placeholder" class="placeholder-animasi">
                            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#999" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="margin-right: 5px;"><circle cx="11" cy="11" r="8"></circle><line x1="21" y1="21" x2="16.65" y2="16.65"></line></svg>
                            Cari <div class="animasi-teks-wrapper"><span id="teks-animasi" class="teks-bergerak">...</span></div>
                        </div>
                        <button type="button" class="btn-clear" id="btnClear" onclick="clearInput()" style="display:none;">
                            <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>
                        </button>
                        <button type="submit" class="btn-search-orange">
                            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"></circle><line x1="21" y1="21" x2="16.65" y2="16.65"></line></svg>
                        </button>
                    </div>
                </form>
            </div>
        </div>
        <div class="wadah-katalog" id="tempat-katalog"><div class="teks-loading">Mengambil data dari gudang... ⏳</div></div>
        <div class="fab-keranjang" onclick="bukaKeranjang()">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="21" r="1"></circle><circle cx="20" cy="21" r="1"></circle><path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6"></path></svg>
            <div class="badge-keranjang" id="badge-qty">0</div>
        </div>
        <div class="modal-overlay" id="modal-keranjang">
            <div class="modal-content">
                <div class="modal-header">
                    <button class="btn-tutup" onclick="tutupKeranjang()"><svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="19" y1="12" x2="5" y2="12"></line><polyline points="12 19 5 12 12 5"></polyline></svg></button>
                    <h2>Tinjau Pesanan</h2>
                </div>
                <div class="list-pesanan" id="list-pesanan"></div>
                <div class="area-checkout">
                    <div class="form-tujuan">
                        <input type="text" id="inputKios" class="input-tujuan" placeholder="KIOS Nama Utama..." onfocus="cekDanAturKios(this)" oninput="validasiKios(this)">
                        <select id="inputDaerah" class="input-tujuan" onchange="simpanDaerah(this)">
                            <option value="" disabled selected>-- Pilih Daerah --</option>
                            <option value="SOE">SOE</option>
                            <option value="KEFA">KEFA</option>
                            <option value="ATAMBUA">ATAMBUA</option>
                            <option value="MALAKA">MALAKA</option>
                        </select>
                    </div>
                    <div class="baris-total"><span>Total:</span><span id="total-harga-keranjang">Rp 0</span></div>
                    <button class="btn-wa-checkout" onclick="kirimKeWA()"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"></path></svg>Kirim Pesanan ke WA</button>
                </div>
            </div>
        </div>
        <div class="konfirmasi-overlay" id="modalKonfirmasiKeluar"><div class="konfirmasi-box"><h3>Konfirmasi Keluar</h3><p>Apakah kamu yakin ingin keluar dari aplikasi?</p><div class="konfirmasi-aksi"><button class="btn-konfirmasi btn-tidak" onclick="tutupKonfirmasiKeluar()">Tidak</button><button class="btn-konfirmasi btn-ya" onclick="eksekusiKeluarApp()">Ya, Keluar</button></div></div></div>
        <div class="konfirmasi-overlay" id="modalKonfirmasiWA"><div class="konfirmasi-box"><h3>Konfirmasi Pesanan</h3><p>Apakah kamu sudah yakin?<br>Barang yang sudah dipesan tidak bisa dikembalikan pada saat pengantaran.</p><div class="konfirmasi-aksi"><button class="btn-konfirmasi btn-tidak" onclick="tutupKonfirmasiWA()">Cek Kembali</button><button class="btn-konfirmasi btn-ya" onclick="eksekusiKirimWA()">Ya, Yakin</button></div></div></div>
        <div class="konfirmasi-overlay" id="modalAlertCustom"><div class="konfirmasi-box"><h3 id="alertJudul">Perhatian</h3><p id="alertPesan">Pesan alert di sini</p><div class="konfirmasi-aksi"><button class="btn-konfirmasi btn-ok" onclick="tutupAlert()">OK</button></div></div></div>
    </div>
    <script>
        const SHEET_ID = "12dmJadrRGYoTKg_nOA4GoCwlntjjO2EjG0tYCz-yFss";
        const SHEET_URL = `https://docs.google.com/spreadsheets/d/${SHEET_ID}/gviz/tq?tqx=out:json&t=${new Date().getTime()}`;
        const FOLDER_GAMBAR_SERVER = "./gambar/";
        let dataKatalog = {}, keranjang = JSON.parse(localStorage.getItem('keranjang_gudang_septa_v2')) || {}, daftarNamaBarang = [], nomorWAOwner = "6281234567890", sedangMencari = false, stateVarianKatalog = {}; 
        function escapeHTML(str) { if (!str) return ""; return str.replace(/[&<>'"]/g, tag => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[tag] || tag)); }
        function dapatkanNamaFile(urlMentah) { let urlStr = urlMentah.toString().trim(); if (urlStr.includes('/')) return urlStr.split('/').pop(); return urlStr; }
        window.history.replaceState({ page: 'homepage' }, null, window.location.href);
        window.addEventListener("popstate", function (event) {
            if (document.getElementById('modalAlertCustom').style.display === 'flex') document.getElementById('modalAlertCustom').style.display = 'none';
            else if (document.getElementById('modalKonfirmasiWA').style.display === 'flex') document.getElementById('modalKonfirmasiWA').style.display = 'none';
            else if (document.getElementById('modal-keranjang').style.display === 'flex') document.getElementById('modal-keranjang').style.display = 'none';
            else if (document.getElementById('modalKonfirmasiKeluar').style.display === 'flex') tutupKonfirmasiKeluar();
            else if (sedangMencari) resetPencarian();
            else { bukaKonfirmasiKeluar(); window.history.pushState({ page: 'homepage' }, null, window.location.href); }
        });
        function tampilkanAlert(pesan, judul = "Perhatian") { document.getElementById('alertJudul').innerText = judul; document.getElementById('alertPesan').innerText = pesan; document.getElementById('modalAlertCustom').style.display = 'flex'; window.history.pushState({ modal: 'alert' }, null, ""); }
        function tutupAlert() { if (window.history.state && window.history.state.modal === 'alert') window.history.back(); else document.getElementById('modalAlertCustom').style.display = 'none'; }
        function bukaKonfirmasiKeluar() { document.getElementById('modalKonfirmasiKeluar').style.display = 'flex'; }
        function tutupKonfirmasiKeluar() { document.getElementById('modalKonfirmasiKeluar').style.display = 'none'; }
        function eksekusiKeluarApp() { window.close(); window.location.href = "https://www.google.com"; }
        function muatDataPelanggan() { let simpananKios = localStorage.getItem('gudang_septa_kios'), simpananDaerah = localStorage.getItem('gudang_septa_daerah'); if (simpananKios) document.getElementById('inputKios').value = simpananKios; if (simpananDaerah) document.getElementById('inputDaerah').value = simpananDaerah; }
        function cekDanAturKios(input) { if (input.value.trim() === "") input.value = "KIOS "; }
        function validasiKios(input) {
            let nilai = input.value.toUpperCase();
            if (!nilai.startsWith("KIOS ")) { input.value = "KIOS "; } else { let sisaTeks = nilai.substring(5); if (sisaTeks.includes("KIOS")) { tampilkanAlert("Harap hapus tulisan kios yang kamu masukan!"); input.value = "KIOS " + sisaTeks.replace(/KIOS/g, '').trim(); } else { input.value = nilai; } }
            localStorage.setItem('gudang_septa_kios', input.value);
        }
        function simpanDaerah(select) { localStorage.setItem('gudang_septa_daerah', select.value); }
        function perbaruiUIKartu(id) {
            let barang = dataKatalog[id]; if (!barang) return;
            let totalQty = 0, maxQty = 0, prefix = id + "_";
            for (let key in keranjang) { if (key.startsWith(prefix)) { totalQty += keranjang[key].qty; if (keranjang[key].qty > maxQty) maxQty = keranjang[key].qty; } }
            let kartu = document.getElementById(`kartu-${id}`); if (kartu) totalQty > 0 ? kartu.classList.add('aktif-keranjang') : kartu.classList.remove('aktif-keranjang');
            let elQty = document.getElementById(`qty-${id}`);
            if (barang.varian && barang.varian.length > 0) {
                let varianAktif = stateVarianKatalog[id] || "";
                barang.varian.forEach(v => {
                    let btn = document.getElementById(`btn-var-${id}-${v.replace(/\s+/g, '-')}`);
                    if (btn) { let key = `${id}_${v}`; let qtyVarian = keranjang[key] ? keranjang[key].qty : 0; qtyVarian > 0 ? btn.classList.add('di-keranjang') : btn.classList.remove('di-keranjang'); v === varianAktif ? btn.classList.add('aktif') : btn.classList.remove('aktif'); }
                });
                if (elQty) { if (varianAktif) { let keyAktif = `${id}_${varianAktif}`; elQty.innerText = keranjang[keyAktif] ? keranjang[keyAktif].qty : 0; } else { elQty.innerText = maxQty > 0 ? maxQty : 0; } }
            } else { let key = `${id}_`; if (elQty) elQty.innerText = keranjang[key] ? keranjang[key].qty : 0; }
        }
        async function ambilDataDariGoogleSheets() {
            try {
                const response = await fetch(SHEET_URL); const textData = await response.text(); const baris = JSON.parse(textData.substring(47).slice(0, -2)).table.rows;
                let htmlKatalog = "", indexBarang = 0;
                baris.forEach((row, rowIndex) => {
                    if (rowIndex === 0 && row.c[1] && typeof row.c[1].v === 'string') return;
                    if (row.c[0] && row.c[0].v) {
                        let namaAsli = row.c[0].v.toString().trim(); if (namaAsli.includes('#')) return;
                        let isKosong = false; if (namaAsli.includes('*')) { isKosong = true; namaAsli = namaAsli.replace(/\*/g, '').trim(); }
                        if (row.c[9] && row.c[9].v && nomorWAOwner === "6281234567890") { let nomorMentah = row.c[9].v.toString().replace(/\D/g, ''); if (nomorMentah.startsWith('0')) nomorMentah = '62' + nomorMentah.substring(1); nomorWAOwner = nomorMentah; }
                        let kelipatan = 1, selKelipatan = row.c[7]; if (selKelipatan && (selKelipatan.f !== undefined || selKelipatan.v !== null)) { let angkaParsed = parseFloat(String(selKelipatan.f || selKelipatan.v).replace(',', '.')); if (!isNaN(angkaParsed) && angkaParsed > 0) kelipatan = angkaParsed; }
                        let satuan = row.c[8] && row.c[8].v ? String(row.c[8].v).trim() : "", harga = row.c[1] ? Number(row.c[1].v) : 0, keterangan = row.c[6] ? row.c[6].v : "", arrayVarian = [];
                        if (row.c[11] && row.c[11].v) { let strVarian = String(row.c[11].v).trim(); if (strVarian !== "") arrayVarian = strVarian.split(',').map(v => v.trim()).filter(v => v !== ""); }
                        daftarNamaBarang.push(namaAsli);
                        dataKatalog[indexBarang] = { id: indexBarang, nama: namaAsli, harga: harga, kelipatan: kelipatan, satuan: satuan ? " " + satuan : "", isKosong: isKosong, varian: arrayVarian };
                        let foto1 = row.c[3] && row.c[3].v ? row.c[3].v : "", foto2 = row.c[4] && row.c[4].v ? row.c[4].v : "", foto3 = row.c[5] && row.c[5].v ? row.c[5].v : "";
                        const daftarFoto = [foto1, foto2, foto3].filter(val => val !== "").map(val => FOLDER_GAMBAR_SERVER + dapatkanNamaFile(val));
                        const totalFoto = daftarFoto.length; let kelasGambar = isKosong ? "gambar-kosong" : "";
                        let kumpulangambar = totalFoto === 0 ? `<img src="https://placehold.co/400x300/e0e0e0/666666?text=Tidak+Ada+Foto" alt="Placeholder" loading="lazy" class="${kelasGambar}" draggable="false" oncontextmenu="return false;">` : daftarFoto.map(url => `<img src="${url}" onerror="this.onerror=null; this.src='https://placehold.co/400x300/e0e0e0/666666?text=Loading...';" loading="lazy" class="${kelasGambar}" draggable="false" oncontextmenu="return false;">`).join('');
                        let elemenKosong = isKosong ? `<div class="watermark-kosong">KOSONG</div>` : "", elemenKeterangan = keterangan ? `<div class="wadah-deskripsi"><div class="judul-deskripsi">Deskripsi:</div><div class="keterangan-barang">${escapeHTML(keterangan)}</div></div>` : "", elemenVarianHTML = "";
                        if (arrayVarian.length > 0) { let tombolVarian = arrayVarian.map(v => `<button type="button" class="btn-varian" id="btn-var-${indexBarang}-${escapeHTML(v.replace(/\s+/g, '-'))}" onclick="pilihVarian(${indexBarang}, '${escapeHTML(v)}')">${escapeHTML(v)}</button>`).join(''); elemenVarianHTML = `<div class="teks-pilih-varian">Pilih Varian:</div><div class="wadah-varian" id="wadah-varian-${indexBarang}">${tombolVarian}</div>`; }
                        htmlKatalog += `<div class="kartu-barang" id="kartu-${indexBarang}"><div class="slider-wrapper">${elemenKosong}${totalFoto > 1 ? `<div class="slider-counter">1/${totalFoto}</div>` : ""}<div class="slider-gambar" onscroll="perbaruiAngka(this, ${totalFoto})">${kumpulangambar}</div></div><h3 class="nama-barang">${escapeHTML(namaAsli)}</h3><p class="harga-barang">Rp ${harga.toLocaleString('id-ID')}</p>${elemenVarianHTML}${elemenKeterangan}<div class="area-bawah-kartu"><div class="keterangan-singkat">Order per: ${kelipatan}${dataKatalog[indexBarang].satuan}</div><div class="kontrol-qty"><button class="btn-qty" onclick="ubahQty(${indexBarang}, -1)" ${isKosong ? 'disabled' : ''}>-</button><span class="angka-qty" id="qty-${indexBarang}">0</span><button class="btn-qty" onclick="ubahQty(${indexBarang}, 1)" ${isKosong ? 'disabled' : ''}>+</button></div></div></div>`;
                        indexBarang++;
                    }
                });
                document.getElementById("tempat-katalog").innerHTML = htmlKatalog;
                for (let i = 0; i < indexBarang; i++) perbaruiUIKartu(i);
                perbaruiBadgeKeranjang(); jalankanAnimasiPencarian(); jalankanAutoSlide();
            } catch (error) { document.getElementById("tempat-katalog").innerHTML = `<div style="text-align:center; padding: 40px 20px;"><p style="color: #dc2626; font-weight:bold;">Gagal memuat barang. Periksa koneksi internet.</p><button onclick="ambilDataDariGoogleSheets()" style="padding: 10px 20px; background: #EA580C; color: white; border: none; border-radius: 8px; margin-top: 10px; cursor:pointer;">Coba Lagi</button></div>`; }
        }
        function pilihVarian(id, varian) { let barang = dataKatalog[id]; if (barang.isKosong) return; stateVarianKatalog[id] = varian; perbaruiUIKartu(id); }
        function ubahQty(id, arah) { let barang = dataKatalog[id]; if (barang.isKosong) return; let varianAktif = ""; if (barang.varian.length > 0) { if (!stateVarianKatalog[id]) { tampilkanAlert("Silakan pilih varian (warna/ukuran) terlebih dahulu!"); return; } varianAktif = stateVarianKatalog[id]; } prosesUbahQty(id, varianAktif, arah); }
        function ubahQtyDariModal(keyKeranjang, arah) { let item = keranjang[keyKeranjang]; if(!item) return; prosesUbahQty(item.id, item.varian, arah, true); }
        function prosesUbahQty(id, varian, arah, dariModal = false) {
            let barang = dataKatalog[id], key = `${id}_${varian}`, qtySekarang = keranjang[key] ? keranjang[key].qty : 0, qtyBaru = qtySekarang + (arah * barang.kelipatan);
            if (qtyBaru <= 0) { delete keranjang[key]; } else { qtyBaru = Math.round(qtyBaru * 100) / 100; keranjang[key] = { id: id, varian: varian, qty: qtyBaru }; }
            localStorage.setItem('keranjang_gudang_septa_v2', JSON.stringify(keranjang)); perbaruiBadgeKeranjang(); perbaruiUIKartu(id);
            if (dariModal || document.getElementById('modal-keranjang').style.display === 'flex') {
                let elModalQty = document.getElementById(`modal-qty-${key}`), elModalTotal = document.getElementById(`modal-total-${key}`), elModalBaris = document.getElementById(`row-modal-${key}`);
                if (elModalQty) { elModalQty.innerText = qtyBaru > 0 ? qtyBaru : 0; if (elModalTotal) elModalTotal.innerText = `Rp ${(qtyBaru * barang.harga).toLocaleString('id-ID')}`; if (elModalBaris) elModalBaris.style.opacity = qtyBaru <= 0 ? '0.4' : '1'; }
                kalkulasiTotalKeranjang();
            }
        }
        function perbaruiBadgeKeranjang() { let totalJenisItem = Object.keys(keranjang).length; const badge = document.getElementById('badge-qty'); badge.innerText = totalJenisItem; if (totalJenisItem > 0) { badge.style.transform = 'scale(1.2)'; setTimeout(() => badge.style.transform = 'scale(1)', 200); } }
        function kalkulasiTotalKeranjang() { let total = 0; for (let key in keranjang) { let item = keranjang[key], barang = dataKatalog[item.id]; if (barang) total += item.qty * barang.harga; } document.getElementById('total-harga-keranjang').innerText = `Rp ${total.toLocaleString('id-ID')}`; }
        function bukaKeranjang() {
            const listPesanan = document.getElementById('list-pesanan'); let htmlPesanan = "", adaBarang = Object.keys(keranjang).length > 0;
            if (!adaBarang) { listPesanan.innerHTML = "<p style='text-align:center; color:#999; margin-top:30px;'>Keranjang masih kosong.</p>"; } else {
                for (let key in keranjang) {
                    let item = keranjang[key], barang = dataKatalog[item.id]; if (!barang) continue;
                    let subTotal = item.qty * barang.harga, namaCetak = item.varian ? `${barang.nama} ${item.varian}` : barang.nama;
                    htmlPesanan += `<div class="item-pesanan" id="row-modal-${key}"><div class="info-item-keranjang"><div class="item-pesanan-nama">${escapeHTML(namaCetak)}</div><div class="item-pesanan-harga">Rp ${barang.harga.toLocaleString('id-ID')} / ${barang.satuan.trim()}</div><div class="total-harga-item" id="modal-total-${key}">Rp ${subTotal.toLocaleString('id-ID')}</div></div><div class="kontrol-qty" style="margin: 0;"><button class="btn-qty" onclick="ubahQtyDariModal('${key}', -1)">-</button><span class="angka-qty" id="modal-qty-${key}">${item.qty}</span><button class="btn-qty" onclick="ubahQtyDariModal('${key}', 1)">+</button></div></div>`;
                } listPesanan.innerHTML = htmlPesanan;
            }
            kalkulasiTotalKeranjang(); document.getElementById('modal-keranjang').style.display = 'flex'; window.history.pushState({ modal: 'keranjang' }, null, "");
        }
        function tutupKeranjang() { if (window.history.state && window.history.state.modal === 'keranjang') window.history.back(); else document.getElementById('modal-keranjang').style.display = 'none'; }
        function kirimKeWA() {
            const inputKios = document.getElementById('inputKios').value.trim(), daerah = document.getElementById('inputDaerah').value;
            if (!inputKios || inputKios === "KIOS" || inputKios === "KIOS " || !daerah) { tampilkanAlert("Mohon lengkapi Nama Kios dan pilih Daerah Anda terlebih dahulu!"); return; }
            let adaBarang = false; for (let key in keranjang) { if (keranjang[key].qty > 0) { adaBarang = true; break; } }
            if (!adaBarang) { tampilkanAlert("Keranjang kosong!"); return; }
            document.getElementById('modalKonfirmasiWA').style.display = 'flex'; window.history.pushState({ modal: 'konfirmasiWA' }, null, "");
        }
        function eksekusiKirimWA() {
            tutupKonfirmasiWA(); const inputKios = document.getElementById('inputKios').value.trim(), daerah = document.getElementById('inputDaerah').value;
            let pesan = "Halo Mas Septa, saya ada pesanan baru:\n\nNama Kios: " + inputKios + "\nDaerah Tujuan: " + daerah + "\n--------------------------\n\n", totalSemua = 0;
            for (let key in keranjang) {
                let item = keranjang[key], barang = dataKatalog[item.id];
                if (barang && item.qty > 0) {
                    let subTotal = item.qty * barang.harga; totalSemua += subTotal;
                    let namaCetak = item.varian ? `${barang.nama} (${item.varian})` : barang.nama;
                    pesan += `- ${namaCetak}\n  ${item.qty} ${barang.satuan.trim()} x Rp ${barang.harga.toLocaleString('id-ID')} = Rp ${subTotal.toLocaleString('id-ID')}\n`;
                }
            }
            pesan += `\nTotal Semua = Rp ${totalSemua.toLocaleString('id-ID')}`;
            window.open(`https://wa.me/${nomorWAOwner}?text=${encodeURIComponent(pesan)}`, '_blank');
        }
        function tutupKonfirmasiWA() { if (window.history.state && window.history.state.modal === 'konfirmasiWA') window.history.back(); else document.getElementById('modalKonfirmasiWA').style.display = 'none'; }
        function eksekusiPencarian(e) {
            if (e) e.preventDefault(); const keyword = document.getElementById('inputCari').value.toLowerCase(), elemenKartu = document.getElementsByClassName('kartu-barang');
            document.getElementById('inputCari').blur(); sedangMencari = keyword.length > 0; document.getElementById('btnBack').style.display = sedangMencari ? 'flex' : 'none';
            for (let i = 0; i < elemenKartu.length; i++) { const nama = elemenKartu[i].querySelector('.nama-barang'); if (nama && (nama.textContent || nama.innerText).toLowerCase().indexOf(keyword) > -1) { elemenKartu[i].style.display = ""; } else { elemenKartu[i].style.display = "none"; } }
        }
        document.getElementById('inputCari').addEventListener('input', function() { document.getElementById('btnClear').style.display = this.value.length > 0 ? 'flex' : 'none'; });
        function clearInput() { document.getElementById('inputCari').value = ''; document.getElementById('btnClear').style.display = 'none'; document.getElementById('inputCari').focus(); }
        function resetPencarian() { document.getElementById('inputCari').value = ''; document.getElementById('btnClear').style.display = 'none'; document.getElementById('btnBack').style.display = 'none'; sedangMencari = false; tampilkanPlaceholder(); eksekusiPencarian(); }
        function sembunyikanPlaceholder() { document.getElementById('wadah-placeholder').style.display = 'none'; }
        function tampilkanPlaceholder() { if(document.getElementById('inputCari').value === "") document.getElementById('wadah-placeholder').style.display = 'flex'; }
        let intervalAnimasiCari;
        function jalankanAnimasiPencarian() {
            if (daftarNamaBarang.length === 0) return; let indeks = 0; const teksAnimasi = document.getElementById('teks-animasi'); teksAnimasi.innerText = daftarNamaBarang[0];
            intervalAnimasiCari = setInterval(() => {
                teksAnimasi.style.transform = 'translateY(-100%)'; teksAnimasi.style.opacity = '0';
                setTimeout(() => {
                    indeks = (indeks + 1) % daftarNamaBarang.length; teksAnimasi.innerText = daftarNamaBarang[indeks]; teksAnimasi.style.transition = 'none'; teksAnimasi.style.transform = 'translateY(100%)';
                    requestAnimationFrame(() => { requestAnimationFrame(() => { teksAnimasi.style.transition = 'transform 0.3s ease-out, opacity 0.3s ease-in'; teksAnimasi.style.transform = 'translateY(0)'; teksAnimasi.style.opacity = '1'; }); });
                }, 300);
            }, 2500);
        }
        function jalankanAutoSlide() { document.querySelectorAll('.slider-gambar').forEach(slider => { if (slider.children.length > 1) { setInterval(() => { if (slider.scrollLeft >= slider.scrollWidth - slider.clientWidth - 5) { slider.scrollTo({ left: 0, behavior: 'smooth' }); } else { slider.scrollBy({ left: slider.clientWidth, behavior: 'smooth' }); } }, 3000); } }); }
        function perbaruiAngka(slider, total) { const counter = slider.parentElement.querySelector('.slider-counter'); if (counter) counter.innerText = Math.round(slider.scrollLeft / slider.clientWidth) + 1 + "/" + total; }
        window.onload = function() { muatDataPelanggan(); ambilDataDariGoogleSheets(); };
    </script>
</body>
</html>
HTMLEOF

# --- B. MENULIS FILE SCRIPT SYNC.JS ---
cat << 'EOF' > $APP_DIR/sync.js
const fs = require('fs');
const path = require('path');

const SHEET_ID = "12dmJadrRGYoTKg_nOA4GoCwlntjjO2EjG0tYCz-yFss";
const SHEET_URL = `https://docs.google.com/spreadsheets/d/${SHEET_ID}/gviz/tq?tqx=out:json`;
const DIR_GAMBAR = path.join(__dirname, 'gambar');

if (!fs.existsSync(DIR_GAMBAR)) { fs.mkdirSync(DIR_GAMBAR, { recursive: true }); }
const delay = ms => new Promise(res => setTimeout(res, ms));

async function jalankanSinkronisasi() {
    try {
        console.log(`[${new Date().toISOString()}] Memulai sinkronisasi...`);
        const response = await fetch(SHEET_URL);
        const textData = await response.text();
        const jsonText = textData.substring(47).slice(0, -2);
        const data = JSON.parse(jsonText);
        const baris = data.table.rows;

        for (let i = 0; i < baris.length; i++) { 
            const row = baris[i];
            if (!row || !row.c) continue; 
            const daftarLink = [row.c[3] ? row.c[3].v : null, row.c[4] ? row.c[4].v : null, row.c[5] ? row.c[5].v : null];

            for (let url of daftarLink) {
                if (url && typeof url === 'string' && url.startsWith('http')) {
                    let namaFile = url.split('/').pop().trim().split('?')[0]; 
                    if (!namaFile) continue;
                    const pathFile = path.join(DIR_GAMBAR, namaFile);

                    if (!fs.existsSync(pathFile)) {
                        console.log(`Mengunduh: ${namaFile}`);
                        let attempt = 0, success = false, maxRetries = 3;
                        while (attempt < maxRetries && !success) {
                            try {
                                const imgRes = await fetch(url, {
                                    headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' },
                                    timeout: 10000
                                });
                                if (!imgRes.ok) break; 
                                const buffer = Buffer.from(await imgRes.arrayBuffer());
                                fs.writeFileSync(pathFile, buffer);
                                console.log(`Disimpan: ${namaFile}`);
                                success = true;
                            } catch (err) {
                                attempt++;
                                if (attempt < maxRetries) await delay(2000);
                            }
                        }
                        await delay(500); 
                    }
                }
            }
        }
        console.log(`[${new Date().toISOString()}] Sinkronisasi selesai.\n`);
    } catch (error) { console.error("Error:", error); }
}
jalankanSinkronisasi();
EOF

# --- C. MENGATUR PERMISSION & CRONJOB SYNC ---
chown -R www-data:www-data $APP_DIR
chmod -R 755 $APP_DIR

NODE_PATH=$(which node)
echo "*/5 * * * * root cd $APP_DIR && $NODE_PATH sync.js >>$APP_DIR/sync.log 2>&1" > /etc/cron.d/sync-gudang
chmod 644 /etc/cron.d/sync-gudang


# ============================================================
# --- 6. GENERATE SERTIFIKAT SSL & SET CRONJOB ---
# ============================================================
echo "=================================================="
echo " [6/9] Memproses Sertifikat SSL..."
echo "=================================================="
systemctl stop nginx
certbot certonly --standalone --preferred-challenges http --agree-tos --email admin@$DOMAIN -d$DOMAIN --non-interactive

echo "0 0 1 * * root systemctl stop nginx && certbot renew && systemctl start nginx" > /etc/cron.d/certbot-renew
chmod 644 /etc/cron.d/certbot-renew
systemctl restart cron

# ============================================================
# --- 7. KONFIGURASI XRAY JSON ---
# ============================================================
echo "=================================================="
echo " [7/9] Konfigurasi Xray..."
echo "=================================================="
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

# ============================================================
# --- 8. KONFIGURASI NGINX (WEBSITE + VPN) ---
# ============================================================
echo "=================================================="
echo " [8/9] Konfigurasi Nginx (Website + VPN)..."
echo "=================================================="
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

    # ====== WEBSITE KATALOG (domain utama) ======
    root /var/www/html;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # ====== VPN PATHS ======
    location /home {
        proxy_pass http://127.0.0.1:1234;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        client_max_body_size 0;
    }
    location /home2 {
        proxy_pass http://127.0.0.1:1236;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        client_max_body_size 0;
    }
    location /grpc {
        if (\$request_method != "POST") { return 404; }
        grpc_pass grpc://127.0.0.1:1237;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        client_max_body_size 0;
    }
    location /upgrade {
        proxy_pass http://127.0.0.1:1238;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        client_max_body_size 0;
    }
}

server {
    listen 80; 
    listen 8080; 
    listen 8880; 
    listen 2052; 
    listen 2082;
    server_name $DOMAIN;

    # ====== WEBSITE KATALOG (HTTP) ======
    root /var/www/html;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # ====== VPN PATHS (Non-TLS) ======
    location /home {
        proxy_pass http://127.0.0.1:1234;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        client_max_body_size 0;
    }
    location /home2 {
        proxy_pass http://127.0.0.1:1236;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        client_max_body_size 0;
    }
    location /upgrade {
        proxy_pass http://127.0.0.1:1238;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        client_max_body_size 0;
    }
}
EOF

# Hapus default nginx kalau ada file sisa
rm -f /etc/nginx/sites-enabled/default 2>/dev/null
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

# Test konfigurasi Nginx
nginx -t

# ============================================================
# --- 9. RESTART SERVICES & KIRIM LINK TELEGRAM ---
# ============================================================
echo "=================================================="
echo " [9/9] Restart services & kirim link Telegram..."
echo "=================================================="
systemctl restart nginx xray
systemctl enable nginx xray

# TLS Links
L1="vless://$UUID@$DOMAIN:443?path=%2Fhome&security=tls&encryption=none&type=ws&sni=$DOMAIN&host=$DOMAIN#WS_TLS"
L2="vless://$UUID@$DOMAIN:443?path=%2Fhome2&security=tls&encryption=none&type=xhttp&sni=$DOMAIN&host=$DOMAIN#XHTTP_TLS"
L3="vless://$UUID@$DOMAIN:443?mode=multi&security=tls&encryption=none&type=grpc&serviceName=grpc&sni=$DOMAIN&host=$DOMAIN#GRPC_TLS"
L4="vless://$UUID@$DOMAIN:443?path=%2Fupgrade&security=tls&encryption=none&type=httpupgrade&sni=$DOMAIN&host=$DOMAIN#UPGRADE_TLS"

# Non-TLS Links
L5="vless://$UUID@$DOMAIN:80?path=\%2Fhome&security=none&encryption=none&type=ws&host=$DOMAIN#WS_NTLS"
L6="vless://$UUID@$DOMAIN:80?path=\%2Fhome2&security=none&encryption=none&type=xhttp&host=$DOMAIN#XHTTP_NTLS"
L7="vless://$UUID@$DOMAIN:80?path=\%2Fupgrade&security=none&encryption=none&type=httpupgrade&host=$DOMAIN#UPGRADE_NTLS"

ALL_LINKS=$(cat <<EOF
🌐 Website Katalog: https://$DOMAIN

━━━━━━━━━━━━━━━
🔐 VPN LINKS (TLS)
━━━━━━━━━━━━━━━
$L1$L2
$L3$L4

━━━━━━━━━━━━━━━
🔓 VPN LINKS (NON-TLS)
━━━━━━━━━━━━━━━
$L5
$L6$L7
EOF
)

curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
     -H 'Content-Type: application/json' \
     -d "$(jq -n --arg chat_id "$CHAT_ID" --arg text "$ALL_LINKS" '{chat_id: $chat_id, text:$text}')"

echo ""
echo "=================================================="
echo " ✅ INSTALASI SELESAI!"
echo "=================================================="
echo " 🌐 Website Katalog : https://$DOMAIN"
echo " 🔐 VPN Paths       : /home, /home2, /grpc, /upgrade"
echo " 📩 Link VPN dikirim ke Telegram."
echo " 🔄 Cronjob Sync    : Aktif mengecek gambar setiap 5 menit."
echo "=================================================="
