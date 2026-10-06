# Sistem Informasi Akreditasi Program Studi Teknologi Informasi
**Sekolah Vokasi Universitas Tiga Serangkai** · berbasis Lembaga Akreditasi Mandiri Infokom (LAM Infokom)

Aplikasi web berbasis **Laravel 11** untuk mengelola dokumen dan isian akreditasi. Seluruh fitur dipasang oleh **satu skrip** (`akreditasi-installer.sh`) pada proyek Laravel yang baru, sehingga dapat dipindahkan ke server lain dengan langkah yang sama.

> **Catatan jujur tentang pengujian:** seluruh kode PHP lolos pemeriksaan sintaks, dan installer diuji pada kerangka proyek Laravel tiruan (instalasi baru, pengulangan, dan pembaruan situs lama). Aplikasi lengkap belum diuji end-to-end pada server nyata. Pasang dulu di server uji coba sebelum dipakai untuk data sebenarnya.

---

## 1. Isi paket

| Berkas | Fungsi |
|---|---|
| `akreditasi-installer.sh` | Installer tunggal: memasang **semua** fitur di bawah ini (untuk server/instalasi baru). |
| `perbarui-lihat-stmik.sh` | Pembaruan untuk situs **lama yang sudah berjalan** (tautan Lihat, hapus "Diperbarui", kategori Dokumen Tambahan). Tidak perlu dipakai pada instalasi baru karena sudah ada di installer. |
| `README.md` | Panduan ini. |

## 2. Fitur

- **Kriteria Akreditasi** → **Isi Kriteria** (butir, elemen penilaian ditampilkan utuh, narasi dengan editor TinyMCE: tabel, gambar, daftar) → **Detail Dokumen** (unggah berkas atau link).
- **Dashboard capaian**: isian per kriteria, isian narasi, kelengkapan dokumen.
- **Hak akses**: melihat dan membaca tanpa login; tambah, ubah, hapus wajib login.
- **Data Induk**: Dokumen Standar Mutu, Dokumen Universitas, Dokumen Fakultas, Dokumen Tambahan (**tanpa tabel database**; metadata disimpan berupa berkas JSON).
- **Tautan "Lihat"**: dokumen tampil sebagai pratinjau di browser (PDF, gambar; Office bila situs publik HTTPS), bukan langsung terunduh.
- **Gunakan kembali dokumen** yang pernah diunggah (dari Data Induk atau kriteria lain) saat menambah dokumen.
- **Kelola Pengguna** (khusus admin) dan **Akun Saya** (semua pengguna).
- **Batas unggah 20 MB per berkas**, tema antarmuka profesional (sidebar, header, dashboard).

## 3. Persyaratan

| Komponen | Versi / catatan |
|---|---|
| PHP | **8.2 atau lebih baru** dengan ekstensi `mbstring`, `xml`, `curl`, `zip`, `bcmath`, `gd`, `pdo_mysql`, `fileinfo`, `openssl`, `tokenizer` |
| Composer | 2.x |
| Database | MySQL 8 atau MariaDB 10.6+ |
| Web server | Apache 2.4 (dengan `mod_rewrite`) atau Nginx |
| Alat bantu | `bash`, `perl`, `git`, `curl`. Di Windows: **Git Bash** |
| Internet | Saat instalasi (Composer). Saat dipakai, browser pengguna memuat Bootstrap, TinyMCE, dan font dari CDN, jadi jaringan **tanpa internet (intranet murni)** memerlukan penyesuaian tambahan. |

Gunakan **Laravel 11** (`laravel/laravel:^11.0`). Installer memberi peringatan bila versinya berbeda.

---

## 4. Instalasi di Ubuntu 22.04 / 24.04 (Apache + MySQL + phpMyAdmin)

Jalankan sebagai user biasa yang punya `sudo` (bukan `root`).

**4.1 Pasang paket**
```bash
sudo apt update
sudo apt install -y apache2 mysql-server unzip git curl perl \
  php libapache2-mod-php php-cli php-mysql php-mbstring php-xml php-curl php-zip php-bcmath php-gd php-intl
sudo a2enmod rewrite
php -v          # harus 8.2 atau lebih baru
```
Jika di Ubuntu 22.04 PHP masih 8.1: `sudo add-apt-repository ppa:ondrej/php && sudo apt update`, lalu pasang paket dengan awalan `php8.3-` (misalnya `php8.3 php8.3-mysql libapache2-mod-php8.3`).

**4.2 (Opsional) phpMyAdmin**
```bash
sudo apt install -y phpmyadmin     # pada dialog: pilih apache2 (Spasi), konfigurasi database: Yes
sudo phpenmod mbstring && sudo systemctl restart apache2
```
Batasi alamat `/phpmyadmin` (misalnya per IP) atau nonaktifkan setelah selesai: `sudo a2disconf phpmyadmin && sudo systemctl reload apache2`.

**4.3 Buat database dan user**
```bash
sudo mysql
```
```sql
CREATE DATABASE akreditasi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'akreditasi'@'localhost' IDENTIFIED BY 'GANTI_DENGAN_SANDI_KUAT';
GRANT ALL PRIVILEGES ON akreditasi.* TO 'akreditasi'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```
Login phpMyAdmin dengan user `akreditasi` hanya menampilkan database tersebut (lebih aman daripada akun root).

**4.4 Pasang Composer**
```bash
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer
composer --version
```

**4.5 Buat proyek Laravel 11**
```bash
sudo mkdir -p /var/www/akreditasi
sudo chown $USER:www-data /var/www/akreditasi
composer create-project "laravel/laravel:^11.0" /var/www/akreditasi
cd /var/www/akreditasi
```

**4.6 Isi `.env`** (`nano .env`). Hapus tanda `#` pada baris `DB_*` dan ganti `sqlite` menjadi `mysql`:
```
APP_NAME="SIA Akreditasi"
APP_ENV=production
APP_DEBUG=false
APP_URL=http://domain-atau-ip-server

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=akreditasi
DB_USERNAME=akreditasi
DB_PASSWORD=GANTI_DENGAN_SANDI_KUAT
```

**4.7 Jalankan installer**
```bash
cp /lokasi/akreditasi-installer.sh .     # atau unggah dengan scp
bash akreditasi-installer.sh --migrate --produksi
```
Installer meminta sandi `sudo` untuk mengatur izin folder, batas unggah PHP, dan me-restart Apache. Pada akhirnya tampil ringkasan dan akun admin awal.

**4.8 Buat virtual host Apache** (`sudo nano /etc/apache2/sites-available/akreditasi.conf`)
```apache
<VirtualHost *:80>
    ServerName domain-atau-ip-server
    DocumentRoot /var/www/akreditasi/public

    <Directory /var/www/akreditasi/public>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/akreditasi-error.log
    CustomLog ${APACHE_LOG_DIR}/akreditasi-access.log combined
</VirtualHost>
```
```bash
sudo a2dissite 000-default
sudo a2ensite akreditasi
sudo apache2ctl configtest && sudo systemctl reload apache2
```
`AllowOverride All` wajib; tanpa itu semua halaman selain beranda menghasilkan 404.

**4.9 HTTPS dan firewall** (sangat disarankan; pratinjau dokumen Office juga membutuhkan HTTPS publik)
```bash
sudo apt install -y certbot python3-certbot-apache
sudo certbot --apache -d domain-anda
# ubah APP_URL di .env menjadi https://..., lalu: php artisan config:cache
sudo ufw allow 'Apache Full' && sudo ufw allow OpenSSH && sudo ufw enable
```

**4.10 Uji**: buka situs, klik **Masuk** (`admin@example.com` / `GantiSandiIni123`), lalu **segera ganti sandi** lewat menu **Akun Saya** (klik nama di pojok kanan atas).

---

## 5. Instalasi di Windows

Cara termudah: **Laragon** (paket Apache + MySQL + PHP + Composer). Alternatif ada di bagian 5.2.

### 5.1 Laragon (disarankan)

1. Pasang **Laragon Full** (laragon.org) dan **Git for Windows** (git-scm.com, menyediakan *Git Bash* beserta `bash` dan `perl`).
2. Jalankan Laragon, klik **Start All**. Pastikan PHP **8.2+** (Menu → PHP → pilih versi). Lalu **Menu → Tools → Path → Add Laragon to Path** supaya `php` dan `composer` dikenali di Git Bash.
3. Buka **Git Bash**, lalu buat proyek Laravel 11 di folder `www` Laragon:
   ```bash
   cd /c/laragon/www
   composer create-project "laravel/laravel:^11.0" akreditasi
   cd akreditasi
   ```
4. Buat database (Laragon: MySQL `root` tanpa sandi):
   ```bash
   mysql -u root -e "CREATE DATABASE akreditasi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
   ```
5. Edit `.env` (Notepad atau `nano .env`):
   ```
   APP_URL=http://akreditasi.test
   DB_CONNECTION=mysql
   DB_HOST=127.0.0.1
   DB_PORT=3306
   DB_DATABASE=akreditasi
   DB_USERNAME=root
   DB_PASSWORD=
   ```
6. Salin `akreditasi-installer.sh` ke folder proyek, lalu jalankan di Git Bash:
   ```bash
   bash akreditasi-installer.sh --migrate --lewati-server
   ```
   Opsi `--lewati-server` dipakai karena izin folder dan restart Apache tidak berlaku di Windows.
7. **Batas unggah 20 MB**: buka php.ini lewat **Laragon → Menu → PHP → php.ini**, ubah (atau tambahkan) baris berikut, simpan, lalu **Stop All → Start All**:
   ```ini
   upload_max_filesize = 20M
   post_max_size = 25M
   memory_limit = 256M
   max_execution_time = 120
   ```
8. Buka **http://akreditasi.test** (Laragon membuat alamat ini otomatis untuk folder `www\akreditasi`; jika belum muncul: Menu → Preferences → pastikan *Auto virtual hosts* aktif, lalu Reload).
9. **Jika installer melaporkan `storage:link` gagal** (butuh hak symlink), buka *Command Prompt* di folder proyek dan jalankan:
   ```bat
   mklink /J public\storage storage\app\public
   ```

### 5.2 Alternatif

- **WSL2 (Ubuntu di Windows):** buka Ubuntu di WSL, lalu ikuti bagian 4 seluruhnya.
- **XAMPP:** pakai paket dengan PHP 8.2+, pasang Composer terpisah, arahkan *DocumentRoot* virtual host ke `...\akreditasi\public` (aktifkan `mod_rewrite` dan `AllowOverride All`), ubah `php.ini` di `C:\xampp\php\php.ini` seperti langkah 7 di atas, lalu jalankan installer di Git Bash dengan `--lewati-server`.
- **Nginx:** arahkan `root` ke `public`, tambahkan `client_max_body_size 25M;`, dan gunakan konfigurasi Laravel standar (`try_files $uri $uri/ /index.php?$query_string;`).

---

## 6. Opsi installer

```
bash akreditasi-installer.sh [--migrate] [--produksi] [--lewati-server] [--paksa]
```

| Opsi | Arti |
|---|---|
| `--migrate` | Jalankan `migrate`, buat akun admin awal, dan `storage:link` (database di `.env` harus sudah ada). |
| `--produksi` | Atur `APP_ENV=production`, `APP_DEBUG=false`, dan buat cache konfigurasi. |
| `--lewati-server` | Jangan ubah izin folder, pengaturan PHP, atau restart Apache (Windows, hosting bersama, atau tanpa `sudo`). |
| `--paksa` | Izinkan menimpa instalasi yang sudah ada. **Hati-hati**, lihat bagian 9. |

Installer menolak berjalan jika aplikasi sudah terpasang di folder itu, agar kode yang sudah Anda ubah tidak tertimpa.

## 7. Batas unggah 20 MB

Dua lapis harus selaras:
1. **Laravel**: validasi `max:20480` (20 MB) pada unggahan dokumen kriteria dan Data Induk (sudah diatur installer).
2. **PHP**: `upload_max_filesize = 20M`, `post_max_size = 25M`. Di Linux installer membuat `99-akreditasi-upload.ini` di folder `conf.d` PHP (`apache2` dan `fpm`) dan me-restart Apache. Di Windows ubah `php.ini` manual (bagian 5.1 langkah 7).

Gambar yang disisipkan di editor narasi dibatasi **4 MB**. Cek nilai yang dipakai web: buat berkas sementara `public/cek.php` berisi `<?php phpinfo();`, buka di browser, cari `upload_max_filesize`, lalu **hapus** berkas itu.

## 8. Setelah instalasi

- **Login awal:** `admin@example.com` / `GantiSandiIni123` → ganti segera.
- **Admin:** akun dengan id 1 dan email yang tercantum di `.env` pada baris `ADMIN_EMAILS=email1@kampus.ac.id,email2@kampus.ac.id` (lalu `php artisan config:cache`). Hanya admin yang melihat menu **Administrasi → Kelola Pengguna**. Pengguna biasa tetap bisa mengelola dokumen dan isian.
- **Tambah akun:** lewat Kelola Pengguna (tidak ada registrasi publik, tidak ada "lupa kata sandi" lewat email; admin mereset sandi).
- **Data Induk** menyimpan metadata di `storage/app/data-induk/*.json` dan berkas di `storage/app/public/data-induk/`.
- **Tautan "Lihat"** membuka pratinjau di tab baru. PDF dan gambar tampil langsung. Dokumen Word/Excel/PowerPoint dipratinjau lewat layanan Microsoft hanya jika situs dapat diakses publik lewat **HTTPS**; selain itu muncul tombol Unduh. Format lain (misalnya ZIP) hanya dapat diunduh.
  > Pratinjau **bukan pengaman**: siapa pun yang tahu alamat berkas di `/storage/...` tetap dapat mengunduhnya, dan penampil PDF di browser punya tombol unduh sendiri. Dokumen yang benar-benar tertutup memerlukan penyajian berkas lewat controller yang memeriksa login.

## 9. Memindahkan ke server lain, backup, dan pembaruan

**Yang harus dicadangkan:** database, folder `storage/app` (berisi unggahan dokumen, gambar narasi, dan JSON Data Induk), serta `.env`.
```bash
cd /var/www/akreditasi
mysqldump -u akreditasi -p akreditasi > akreditasi_$(date +%F).sql
tar czf berkas_$(date +%F).tgz storage/app
cp .env env_cadangan.txt
```
Jadwalkan harian dengan `crontab -e`, misalnya `0 2 * * * /home/USER/backup-akreditasi.sh`, dan salin hasilnya ke tempat lain (cadangan di server yang sama tidak melindungi dari kerusakan server).

**Memulihkan di server baru:**
1. Ikuti bagian 4 atau 5 sampai langkah mengisi `.env`.
2. Jalankan installer **tanpa** `--migrate`: `bash akreditasi-installer.sh --produksi`.
3. Impor database dan kembalikan berkas:
   ```bash
   mysql -u akreditasi -p akreditasi < akreditasi_TANGGAL.sql
   tar xzf berkas_TANGGAL.tgz -C /var/www/akreditasi
   php artisan storage:link && php artisan optimize:clear
   ```
4. Jika memakai `.env` lama, sesuaikan `APP_URL` dan `DB_*`.

**Situs lama yang belum punya fitur Lihat/Dokumen Tambahan:** cukup jalankan `bash perbarui-lihat-stmik.sh` di folder proyek (aman diulang, berkas yang diubah dicadangkan sebagai `*.bak5`).

**Jangan** menjalankan ulang `akreditasi-installer.sh --paksa` pada situs yang sudah berisi perubahan Anda: seluruh controller, view, dan route akan ditimpa dengan versi awal (data database tidak terhapus).

## 10. Mengubah dan menambah fungsi

Setelah terpasang, ubah **berkasnya langsung** (di `/var/www/akreditasi`). Gunakan Git (`git init && git add -A && git commit -m "versi awal"`) agar setiap perubahan bisa dibatalkan.

| Yang ingin diubah | Lokasi |
|---|---|
| Kriteria, isi kriteria, dokumen | `app/Http/Controllers/{Kriteria,IsiKriteria,Dokumen}Controller.php`, `app/Models/`, `resources/views/{kriteria,isi,dokumen}/` |
| Dashboard | `DashboardController.php`, `resources/views/dashboard.blade.php` |
| Tampilan (sidebar, header, warna) | `resources/views/layout.blade.php`, `public/css/tema.css` |
| Data Induk (kategori dan penyimpanan) | `app/Support/DataInduk.php`, `DataIndukController.php`, `resources/views/datainduk/` |
| Pratinjau "Lihat" | `app/Http/Controllers/LihatController.php`, `resources/views/lihat.blade.php` |
| Pengguna dan akun | `PenggunaController.php`, `AkunController.php`, `app/Http/Middleware/HanyaAdmin.php`, `config/akreditasi.php` |
| Pakai ulang dokumen | `app/Support/SumberDokumen.php`, `DokumenArsipController.php`, bagian bawah `resources/views/dokumen/form.blade.php` |
| Alamat halaman dan hak akses login | `routes/web.php` |
| Struktur tabel | buat migration baru (`php artisan make:migration ...`), jangan ubah migration lama |

**Menambah kategori Data Induk:** tambahkan satu baris `'slug-baru' => 'Nama Kategori',` pada konstanta `KATEGORI` di `app/Support/DataInduk.php`, lalu satu tautan menu di `layout.blade.php` (salin baris "Dokumen Tambahan" dan ganti slug serta namanya). Rute dan daftar sumber "gunakan kembali dokumen" mengikuti otomatis.

> Catatan: kategori **Dokumen Tambahan** memakai kode internal `stmik-sinus` (alamatnya `/data-induk/stmik-sinus`, folder `storage/app/public/data-induk/stmik-sinus/`). Hanya labelnya yang diganti agar dokumen dan tautan yang sudah ada tetap berlaku.

**Setelah mengubah kode di server produksi**, bersihkan cache, karena route, config, dan view di-cache:
```bash
php artisan optimize:clear
php artisan config:cache && php artisan route:cache && php artisan view:cache
```

## 11. Pemecahan masalah

Pertama selalu lihat penyebab pastinya: `tail -n 40 storage/logs/laravel.log` (dan `/var/log/apache2/akreditasi-error.log`). Jangan membagikan isi `.env`.

| Gejala | Penyebab dan solusi |
|---|---|
| Error 500 | Lihat `laravel.log`. Penyebab tersering: versi PHP < 8.2, izin `storage`, `APP_KEY` kosong. |
| "No application encryption key" | `php artisan key:generate`, lalu `php artisan config:cache`. |
| 404 di semua halaman selain beranda | `a2enmod rewrite` terlewat atau `AllowOverride All` tidak ada. |
| `Permission denied` pada `storage` | `sudo chgrp -R www-data storage bootstrap/cache && sudo chmod -R ug+rwX storage bootstrap/cache`. |
| Dokumen/gambar tidak muncul | `php artisan storage:link` (Windows: `mklink /J`), dan periksa `APP_URL`. |
| Unggah di atas 2 MB gagal | Batas PHP belum naik. Ulangi bagian 7 dan restart Apache. |
| `Route [...] not defined` setelah mengubah route | `php artisan route:clear`, lalu cache ulang. |
| 419 Page Expired | Cookie/sesi bermasalah. Pastikan `APP_URL` sesuai alamat yang dibuka, lalu `php artisan config:clear`. |
| Editor narasi tidak muncul | Browser pengguna tidak dapat memuat `cdnjs.cloudflare.com` (TinyMCE). |
| Pratinjau Office kosong atau muncul tombol Unduh | Situs belum publik HTTPS. PDF dan gambar tidak terpengaruh. |
| `perl: command not found` / `composer: command not found` | Ubuntu: `sudo apt install perl`. Windows: pakai Git Bash dan jalankan *Add Laragon to Path*. |
| Error koneksi database (`SQLSTATE ... refused`) | `DB_*` di `.env` salah atau masih diberi `#`; pastikan database sudah dibuat. |

## 12. Daftar periksa keamanan

- [ ] Sandi admin awal sudah diganti.
- [ ] `APP_DEBUG=false` dan `APP_ENV=production`.
- [ ] HTTPS aktif.
- [ ] phpMyAdmin dibatasi per IP atau dinonaktifkan.
- [ ] `.env` tidak dapat diakses dari web (DocumentRoot mengarah ke `public`).
- [ ] Backup harian (database dan `storage/app`) tersimpan di tempat lain.
- [ ] Sistem operasi diperbarui berkala (`sudo apt update && sudo apt upgrade`).
