# Pedoman Instalasi di cPanel (Shared Hosting)

Sistem Informasi Akreditasi Prodi TI, Sekolah Vokasi Universitas Tiga Serangkai (Laravel 11).

Di cPanel Anda biasanya **tidak punya akses root**, sehingga tidak ada `apt install`. Semua dilakukan lewat menu cPanel. Pedoman ini menyediakan dua jalur:

| Jalur | Syarat | Kapan dipakai |
|---|---|---|
| **A. Dengan SSH / Terminal cPanel** | Hosting punya menu *Terminal* atau akses SSH | Paling mudah: installer `.sh` dijalankan langsung di server |
| **B. Tanpa SSH** | Hanya File Manager + phpMyAdmin | Aplikasi dipasang dulu di komputer sendiri, lalu diunggah |

Cek dulu di cPanel: ada menu **Terminal** (bagian *Advanced*)? Jika ada, pakai Jalur A.

Prasyarat hosting (tanyakan ke penyedia bila ragu):
- PHP **8.2 atau lebih baru** tersedia (menu *MultiPHP Manager*).
- Ekstensi PHP: `mbstring`, `xml`, `curl`, `zip`, `fileinfo`, `openssl`, `tokenizer`, `ctype`, `json`, `pdo_mysql` (dan `gd`, `intl` disarankan).
- Satu database MySQL/MariaDB, dan kuota disk minimal ±500 MB.

---

## Langkah 1. Atur versi PHP (kedua jalur)

1. cPanel → **MultiPHP Manager** → centang domain Anda → pilih **PHP 8.2** (atau 8.3) → **Apply**.
2. cPanel → **Select PHP Version** (atau *MultiPHP INI Editor* → *Extensions*): aktifkan ekstensi di atas. Pada tampilan CloudLinux, centang kotak ekstensinya lalu **Save**.
3. cPanel → **MultiPHP INI Editor** → pilih domain → *Basic Mode*, isi:
   - `upload_max_filesize` = `20M`
   - `post_max_size` = `25M`
   - `memory_limit` = `512M`
   - `max_execution_time` = `120`

   Klik **Save**.

## Langkah 2. Buat database (kedua jalur)

1. cPanel → **MySQL® Database Wizard**.
2. Langkah 1: nama database, misalnya `akreditasi` (cPanel menambah awalan, jadi hasil akhirnya semacam `namauser_akreditasi`).
3. Langkah 2: buat pengguna, misalnya `akreditasi`, dengan sandi kuat. Hasilnya `namauser_akreditasi`.
4. Langkah 3: centang **ALL PRIVILEGES** → *Next Step*.
5. **Catat tiga hal ini** (nama lengkap database, nama lengkap pengguna, sandi). Dipakai di `.env`.

Kelola isi database lewat cPanel → **phpMyAdmin**.

## Langkah 3. Siapkan domain / subdomain yang menunjuk ke folder `public`

Laravel **wajib** dilayani dari folder `public/`. Ada dua cara.

**Cara 1 (disarankan): subdomain**, misalnya `akreditasi.domain-anda.ac.id`
1. cPanel → **Domains** (atau *Subdomains*) → **Create A New Domain**.
2. Isi nama subdomain. **Matikan** opsi "Share document root".
3. Pada *Document Root* ketik: `akreditasi/public` (relatif terhadap home, jadi hasilnya `/home/namauser/akreditasi/public`).
4. Simpan. Folder `akreditasi` kita buat di Jalur A/B.

**Cara 2: domain utama (`public_html`)** — dikerjakan setelah aplikasi terpasang, lihat Lampiran 1.

---

# JALUR A. Dengan SSH / Terminal cPanel

### A1. Buka terminal
cPanel → **Terminal** → *I understand, continue*. (Atau SSH: `ssh namauser@alamat-hosting -p 22`.)

### A2. Arahkan terminal ke PHP 8.2
Terminal cPanel sering memakai PHP bawaan yang lama. Cek:
```bash
php -v
```
Jika di bawah 8.2, paksa PHP 8.2 (sesuaikan `ea-php82` dengan versi di MultiPHP Manager, mis. `ea-php83`):
```bash
ls /opt/cpanel | grep ea-php          # lihat versi yang tersedia
echo 'export PATH=/opt/cpanel/ea-php82/root/usr/bin:$HOME/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
php -v                                 # harus 8.2.x
```

### A3. Pasang Composer (tanpa root)
```bash
mkdir -p ~/bin && cd ~/bin
php -r "copy('https://getcomposer.org/installer','composer-setup.php');"
php composer-setup.php --install-dir=$HOME/bin --filename=composer
rm composer-setup.php
composer --version
```
Jika `composer` sudah tersedia di server, lewati langkah ini.

### A4. Buat proyek Laravel
```bash
cd ~
export COMPOSER_MEMORY_LIMIT=-1
composer create-project "laravel/laravel:^11.0" akreditasi
```
Proses ini 2-10 menit. Jika terhenti karena batas memori/proses di hosting murah, gunakan **Jalur B**.

### A5. Isi `.env`
```bash
cd ~/akreditasi
nano .env
```
Ubah bagian ini (ganti dengan data dari Langkah 2):
```
APP_NAME="Sistem Akreditasi"
APP_URL=https://akreditasi.domain-anda.ac.id
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=namauser_akreditasi
DB_USERNAME=namauser_akreditasi
DB_PASSWORD=SandiDatabaseAnda
```
Simpan di `nano` dengan **Ctrl+O**, Enter, **Ctrl+X**.

### A6. Unggah dan jalankan installer
1. cPanel → **File Manager** → buka folder `akreditasi` → **Upload** → pilih `akreditasi-lengkap.sh`. (Atau unggah `akreditasi-sia.zip` ke home lalu `unzip`.)
2. Di terminal:
```bash
cd ~/akreditasi
bash akreditasi-lengkap.sh --produksi
```
Installer akan memeriksa PHP dan database, memasang modul, menjalankan migrasi, lalu menyimpan cache.

### A7. Tautan storage dan izin
```bash
cd ~/akreditasi
php artisan storage:link
chmod -R 775 storage bootstrap/cache
```
Jika `storage:link` ditolak hosting (symlink dimatikan), lihat bagian *Pemecahan masalah*.

### A8. Selesai
Buka `https://akreditasi.domain-anda.ac.id` dan login (lihat bagian *Setelah terpasang*).

---

# JALUR B. Tanpa SSH (pasang di komputer, lalu unggah)

Ide: jalankan instalasi lengkap di komputer Anda (Windows/Ubuntu, ikuti `README.md` atau `PEDOMAN-APACHE-PHPMYADMIN.md`), lalu pindahkan hasilnya ke hosting.

### B1. Pasang dan uji di komputer
1. Selesaikan instalasi lokal sampai aplikasi berjalan. **Gunakan PHP yang sama dengan hosting (8.2/8.3).**
2. Isi data awal yang diperlukan (opsional; bisa juga diisi setelah online).

### B2. Siapkan paket aplikasi
Di folder proyek lokal:
```bash
php artisan optimize:clear
rm -rf storage/logs/*.log
```
Kompres seluruh folder proyek **termasuk `vendor/`** menjadi `akreditasi.zip`, tetapi **jangan sertakan**:
- `.env` (kita buat baru di server)
- `node_modules/`
- `storage/framework/cache/*`, `storage/framework/sessions/*`, `storage/framework/views/*`

### B3. Ekspor database
1. Buka phpMyAdmin lokal → pilih database `akreditasi` → **Export** → *Quick* → format **SQL** → simpan `akreditasi.sql`.
2. (Jika memakai SQLite, ekspor tidak diperlukan; lihat catatan di bawah.)

### B4. Unggah ke hosting
1. cPanel → **File Manager** → folder home (`/home/namauser`, **bukan** `public_html`).
2. **Upload** `akreditasi.zip` → klik kanan → **Extract**. Hasil: `/home/namauser/akreditasi`.
3. Pastikan ada `akreditasi/vendor` dan `akreditasi/artisan`.
4. Salin `.env.example` menjadi `.env` (klik kanan → *Copy*), lalu **Edit** dan isi seperti A5. Nilai `APP_KEY` harus terisi; bila kosong, salin `APP_KEY=` dari `.env` lokal Anda.
5. Set `APP_ENV=production` dan `APP_DEBUG=false`.

### B5. Impor database
1. cPanel → **phpMyAdmin** → pilih database `namauser_akreditasi` (kosong).
2. Tab **Import** → pilih `akreditasi.sql` → **Import**.
3. Jika berkas lebih besar dari batas unggah phpMyAdmin, kompres jadi `.zip`/`.gz` terlebih dahulu atau naikkan `upload_max_filesize` (Langkah 1).

### B6. Izin dan folder
Di File Manager, ubah izin (klik kanan → *Change Permissions*) ke **775** untuk `storage` dan `bootstrap/cache` (centang *Recurse*). Pastikan subfolder ada:
`storage/framework/cache`, `storage/framework/sessions`, `storage/framework/views`, `storage/logs`, `storage/app/public`.

### B7. Selesai
Atur subdomain ke `akreditasi/public` (Langkah 3), lalu buka alamatnya.

> **Catatan SQLite:** hosting bersama sebaiknya memakai MySQL. Jika tetap memakai SQLite, unggah `database/database.sqlite` dan pastikan ekstensi `pdo_sqlite` aktif; folder `database/` harus dapat ditulis (775).

---

## Setelah terpasang

1. Login: `admin@example.com` / `GantiSandiIni123`. **Segera ganti sandi.**
2. Cek menu **Analitik**, **LKPS**, dan unggah satu lampiran uji.
3. cPanel → **SSL/TLS Status** → **Run AutoSSL** agar HTTPS aktif. Bila `APP_URL` berubah menjadi `https`, di terminal jalankan `php artisan config:clear` (Jalur B: ubah `.env` dan hapus berkas `bootstrap/cache/config.php` bila ada).
4. **Cadangan:** cPanel → **Backup** → *Download a Full Account Backup* / *Partial: Home Directory & MySQL Databases*. Lakukan berkala.
5. Pastikan folder aplikasi tidak bisa diakses langsung dari web: hanya `public/` yang menjadi document root.

## Memperbarui aplikasi

Jalur A:
```bash
cd ~/akreditasi
cp -r storage/app ~/cadangan-storage-$(date +%F)     # cadangkan unggahan
bash akreditasi-lengkap.sh --produksi                # skrip aman diulang, tidak menghapus data
```
Jalur B: ulangi B2-B4 dengan hasil terbaru, **jangan menimpa** `.env` dan `storage/app`.

---

## Lampiran 1. Memakai domain utama (`public_html`) tanpa subdomain

Aplikasi tetap di `~/akreditasi` (di luar `public_html`).

**Cara 1: symlink (jika hosting mengizinkan, terminal diperlukan)**
```bash
cd ~
mv public_html public_html_lama
ln -s ~/akreditasi/public public_html
```

**Cara 2: salin isi `public/` (tanpa terminal)**
1. Salin semua isi `akreditasi/public/` ke `public_html/` (termasuk `.htaccess`, `index.php`, `build/`).
2. Edit `public_html/index.php`, ubah dua baris path agar menunjuk ke `../akreditasi`:
```php
if (file_exists($maintenance = __DIR__.'/../akreditasi/storage/framework/maintenance.php')) {
    require $maintenance;
}
require __DIR__.'/../akreditasi/vendor/autoload.php';
$app = require_once __DIR__.'/../akreditasi/bootstrap/app.php';
```
3. Tautan storage manual: unggahan yang sudah ada harus tersedia di `public_html/storage`. Gunakan symlink bila bisa; jika tidak, lihat *Pemecahan masalah*.

---

## Pemecahan masalah

| Gejala | Penyebab umum | Solusi |
|---|---|---|
| `php -v` menunjukkan versi lama di terminal | Terminal memakai PHP bawaan | Langkah A2 (atur `PATH` ke `ea-php82`). |
| Error 500, halaman putih | `.env` salah, izin `storage`, atau PHP lama | Lihat `storage/logs/laravel.log`; periksa PHP 8.2 di MultiPHP Manager; `chmod -R 775 storage bootstrap/cache`. |
| 404 untuk semua halaman kecuali beranda | `.htaccess` tidak ada atau document root salah | Pastikan `public/.htaccess` ada dan document root = `.../public`. |
| `Permission denied` pada berkas `app/...` | Berkas berizin 600 | `find ~/akreditasi/app ~/akreditasi/resources ~/akreditasi/routes ~/akreditasi/config -type f -exec chmod 644 {} \;` |
| `could not find driver` | `pdo_mysql` belum aktif | Aktifkan di *Select PHP Version* / *Extensions*. |
| `SQLSTATE Access denied` | Nama/sandi database tidak lengkap | Pakai nama **dengan awalan** `namauser_`, samakan di `.env`, lalu hapus `bootstrap/cache/config.php`. |
| `SQLSTATE Connection refused` | `DB_HOST` salah | Coba `127.0.0.1`, lalu `localhost`. |
| `composer` terbunuh / `Killed` | Batas memori atau proses hosting | `export COMPOSER_MEMORY_LIMIT=-1`, atau pakai Jalur B. |
| `symlink() has been disabled` | Penyedia mematikan symlink | Minta penyedia mengaktifkan, atau salin isi `storage/app/public` ke `public/storage` secara manual (unggahan baru perlu disalin lagi), atau pakai disk `public` yang diarahkan ke `public/uploads` bila Anda mengubah konfigurasi. |
| Gambar/lampiran tidak tampil | Tautan `public/storage` hilang | `php artisan storage:link`, atau lihat baris di atas. |
| Unggah > 2 MB gagal | Batas PHP rendah | Langkah 1 poin 3 (MultiPHP INI Editor). |
| CSS/JS tidak termuat | `APP_URL` tidak sama dengan alamat | Samakan `APP_URL` (gunakan `https` bila SSL aktif), lalu bersihkan cache. |
| Perubahan `.env` tidak berefek | Konfigurasi ter-cache | `php artisan config:clear` atau hapus `bootstrap/cache/config.php`. |

Perintah berguna (Jalur A):
```bash
php artisan optimize:clear
tail -n 50 storage/logs/laravel.log
```
Log galat Apache ada di cPanel → **Metrics → Errors**.

### Keamanan singkat
- Ganti sandi admin awal dan gunakan sandi database yang kuat.
- Pastikan `APP_DEBUG=false` dan `APP_ENV=production` (opsi `--produksi` mengaturnya).
- Jangan pernah meletakkan folder aplikasi di dalam `public_html` kecuali isi `public/` saja.
- Jangan membagikan berkas `.env`.
