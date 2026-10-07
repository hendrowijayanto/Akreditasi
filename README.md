# Sistem Informasi Akreditasi Program Studi Teknologi Informasi

Sekolah Vokasi Universitas Tiga Serangkai, berbasis LAM Infokom. Dibangun dengan Laravel 11.

Seluruh aplikasi dipasang oleh **satu berkas**: `akreditasi-lengkap.sh`.

**Isi aplikasi:** Kriteria Akreditasi, Isi Kriteria (editor narasi), Detail Dokumen (unggah berkas atau link), Data Induk (Standar Mutu, Universitas, Fakultas, Tambahan), LKPS LAM Infokom (31 tabel, Identitas UPPS dan Prodi, Daftar Dosen Homebase, lampiran berkas atau link, impor Excel/CSV per tabel), tiga tampilan dashboard (Ringkas, Analitik lima aspek, Panel Admin), Kelola Pengguna dan Akun Saya. Halaman dapat dilihat publik; tambah, ubah, dan hapus wajib login.

---

## Daftar isi

1. [Pilih jalur pemasangan](#1-pilih-jalur-pemasangan)
2. [Jalur A: Ubuntu Server (produksi, MySQL + Nginx)](#2-jalur-a-ubuntu-server-produksi)
3. [Jalur B: Windows dengan WSL2 (disarankan untuk Windows)](#3-jalur-b-windows-dengan-wsl2)
4. [Jalur C: Windows dengan Laragon (tanpa WSL)](#4-jalur-c-windows-dengan-laragon)
5. [Setelah terpasang: login pertama dan pemeriksaan](#5-setelah-terpasang)
6. [Opsi skrip](#6-opsi-skrip)
7. [Cadangan, pembaruan, dan pindah server](#7-cadangan-pembaruan-dan-pindah-server)
8. [Pemecahan masalah](#8-pemecahan-masalah)

---

## 1. Pilih jalur pemasangan

| Kebutuhan | Jalur | Database |
|---|---|---|
| Server kampus/hosting yang dipakai banyak pengguna | **A. Ubuntu Server** | MySQL/MariaDB |
| Komputer Windows untuk mencoba, mengembangkan, atau dipakai sendiri | **B. WSL2** (paling mirip server) atau **C. Laragon** | SQLite (paling mudah) atau MySQL |

**Prasyarat semua jalur:** PHP 8.2 atau lebih baru, Composer, `perl`, dan koneksi internet saat pemasangan. Peramban pengguna juga perlu internet karena Bootstrap dan editor narasi (TinyMCE) dimuat dari CDN.

**Pilihan database:**
- **SQLite:** tidak perlu memasang MySQL. Bawaan Laravel 11. Cukup untuk penggunaan ringan (satu atau beberapa admin). Datanya satu berkas: `database/database.sqlite`.
- **MySQL/MariaDB:** disarankan untuk server produksi dengan banyak pengguna.

> **Penting tentang berkas skrip:** simpan `akreditasi-lengkap.sh` dengan akhir baris **LF** (bukan CRLF). Jika error `$'\r': command not found`, jalankan `sed -i 's/\r$//' akreditasi-lengkap.sh`.

---

## 2. Jalur A: Ubuntu Server (produksi)

Diuji untuk Ubuntu 22.04 dan 24.04. Contoh memakai domain `akreditasi.kampus.ac.id`, folder `/var/www/akreditasi`, database `akreditasi`.

### Langkah A1. Perbarui sistem dan pasang paket

Ubuntu 24.04 sudah menyediakan PHP 8.3. Pada **Ubuntu 22.04** (PHP 8.1) tambahkan repositori PHP lebih dulu:

```bash
sudo apt update && sudo apt upgrade -y
# Hanya Ubuntu 22.04:
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:ondrej/php && sudo apt update
```

Pasang paket (ganti `8.3` bila memakai versi PHP lain, minimal 8.2):

```bash
sudo apt install -y nginx mysql-server git unzip perl curl \
  php8.3-fpm php8.3-cli php8.3-mysql php8.3-sqlite3 php8.3-mbstring php8.3-xml \
  php8.3-curl php8.3-zip php8.3-gd php8.3-intl php8.3-bcmath
sudo apt install -y composer
php -v          # harus 8.2 atau lebih baru
composer -V
```

Jika `composer -V` gagal atau terlalu lama, pasang Composer resmi: <https://getcomposer.org/download/>.

### Langkah A2. Buat database MySQL

```bash
sudo mysql
```

Di dalam konsol MySQL (ganti `SANDI_KUAT_ANDA`):

```sql
CREATE DATABASE akreditasi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'akreditasi'@'localhost' IDENTIFIED BY 'SANDI_KUAT_ANDA';
GRANT ALL PRIVILEGES ON akreditasi.* TO 'akreditasi'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

### Langkah A3. Buat proyek Laravel 11

```bash
sudo mkdir -p /var/www && sudo chown $USER:$USER /var/www
cd /var/www
composer create-project "laravel/laravel:^11.0" akreditasi
cd akreditasi
```

### Langkah A4. Isi pengaturan database di `.env`

```bash
nano .env
```

Ubah bagian database menjadi (hapus tanda `#` di depan baris yang dikomentari):

```ini
APP_NAME="SIA Akreditasi TI"
APP_URL=https://akreditasi.kampus.ac.id

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=akreditasi
DB_USERNAME=akreditasi
DB_PASSWORD=SANDI_KUAT_ANDA
```

Simpan (`Ctrl+O`, `Enter`, `Ctrl+X`).

### Langkah A5. Jalankan installer

Salin `akreditasi-lengkap.sh` ke server (misalnya dengan `scp akreditasi-lengkap.sh user@server:~/`), lalu dari folder proyek:

```bash
cd /var/www/akreditasi
bash ~/akreditasi-lengkap.sh --produksi
```

Skrip akan memeriksa prasyarat, memasang seluruh modul, menjalankan migrasi database, membuat akun admin awal, mengatur izin folder, menaikkan batas unggah menjadi 20 MB, dan membuat cache produksi. Prosesnya beberapa menit. Di akhir muncul **INSTALASI SELESAI**.

### Langkah A6. Atur Nginx

```bash
sudo nano /etc/nginx/sites-available/akreditasi
```

Isi (sesuaikan `server_name` dan versi PHP pada `fastcgi_pass`):

```nginx
server {
    listen 80;
    server_name akreditasi.kampus.ac.id;
    root /var/www/akreditasi/public;
    index index.php;
    client_max_body_size 25M;          # unggahan hingga 20 MB

    location / { try_files $uri $uri/ /index.php?$query_string; }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }
    location ~ /\.(?!well-known) { deny all; }
}
```

Aktifkan:

```bash
sudo ln -s /etc/nginx/sites-available/akreditasi /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

### Langkah A7. Pasang HTTPS (disarankan)

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d akreditasi.kampus.ac.id
```

Arahkan DNS domain ke IP server lebih dulu.

### Langkah A8. Pastikan izin folder

Skrip sudah mengatur ini. Jika nanti muncul "Permission denied" atau "failed to open stream":

```bash
cd /var/www/akreditasi
sudo chgrp -R www-data storage bootstrap/cache
sudo chmod -R ug+rwX storage bootstrap/cache
sudo find app resources routes config database public -type f -exec chmod a+r {} +
php artisan optimize:clear
```

Lanjut ke [bagian 5](#5-setelah-terpasang).

---

## 3. Jalur B: Windows dengan WSL2

WSL2 menjalankan Ubuntu di dalam Windows 10 (versi 2004 atau lebih baru) atau Windows 11. Langkahnya sama dengan Ubuntu, sehingga hasilnya paling mirip server sungguhan. Pada jalur ini dipakai SQLite dan `php artisan serve` (cocok untuk penggunaan pribadi).

### Langkah B1. Pasang WSL2 dan Ubuntu

Buka **PowerShell sebagai Administrator**:

```powershell
wsl --install -d Ubuntu-24.04
```

Mulai ulang komputer bila diminta. Setelah restart, jendela Ubuntu terbuka dan meminta nama pengguna serta kata sandi Linux. Isi, lalu lanjutkan.

### Langkah B2. Pasang paket di Ubuntu (WSL)

Di terminal Ubuntu:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git unzip perl curl composer \
  php8.3-cli php8.3-sqlite3 php8.3-mysql php8.3-mbstring php8.3-xml \
  php8.3-curl php8.3-zip php8.3-gd php8.3-intl php8.3-bcmath
php -v
```

### Langkah B3. Salin skrip ke WSL

Simpan `akreditasi-lengkap.sh` di Windows (misalnya `C:\Users\NAMA\Downloads`). Di terminal Ubuntu:

```bash
cp /mnt/c/Users/NAMA/Downloads/akreditasi-lengkap.sh ~/
sed -i 's/\r$//' ~/akreditasi-lengkap.sh      # pastikan akhir baris LF
```

Ganti `NAMA` dengan nama pengguna Windows Anda.

### Langkah B4. Pasang aplikasi

Pasang di sistem berkas Linux (`~`), **bukan** di `/mnt/c/...`, supaya cepat dan izinnya benar:

```bash
cd ~
bash akreditasi-lengkap.sh --buat akreditasi
```

Skrip membuat proyek Laravel 11 (SQLite bawaan), memasang semua modul, dan menjalankan migrasi. Tunggu hingga **INSTALASI SELESAI**.

### Langkah B5. Jalankan dan buka

```bash
cd ~/akreditasi
php artisan serve
```

Buka **http://127.0.0.1:8000** di peramban Windows. Hentikan dengan `Ctrl+C`. Untuk menjalankan lagi, ulangi `cd ~/akreditasi && php artisan serve`.

Berkas proyek dapat dilihat dari Windows di `\\wsl$\Ubuntu-24.04\home\NAMA_LINUX\akreditasi`.

Lanjut ke [bagian 5](#5-setelah-terpasang).

---

## 4. Jalur C: Windows dengan Laragon

Laragon adalah paket PHP + web server + MySQL untuk Windows tanpa WSL. Skrip `.sh` dijalankan lewat **Git Bash**.

### Langkah C1. Pasang alat

1. Unduh dan pasang **Laragon Full** dari <https://laragon.org/download>. Pasang di `C:\laragon`.
2. Pasang **Git for Windows** dari <https://git-scm.com/download/win> (menyediakan **Git Bash** beserta `perl`). Pilihan bawaan installer sudah cukup.
3. Jalankan Laragon, klik **Start All**.

### Langkah C2. Pastikan PHP 8.2 atau lebih baru

Klik kanan ikon Laragon (atau menu utamanya) → **PHP** → **Version**, pilih 8.2 atau lebih baru. Bila tidak ada, pasang versi PHP yang lebih baru lewat **Menu → Tools → Quick add** atau unduh PHP dari <https://windows.php.net/download> ke `C:\laragon\bin\php`.

Aktifkan ekstensi lewat **Menu → PHP → Extensions** (centang bila belum): `mbstring`, `openssl`, `curl`, `zip`, `fileinfo`, `gd`, `pdo_sqlite`, `sqlite3`, `pdo_mysql`, `intl`, `xml` (`dom`, `simplexml`, `xmlwriter`, `xmlreader`), `tokenizer`, `ctype`.

### Langkah C3. Naikkan batas unggah

Buka **Menu → PHP → php.ini** dan ubah:

```ini
upload_max_filesize = 20M
post_max_size = 25M
memory_limit = 256M
max_execution_time = 120
```

Lalu **Stop All** dan **Start All**. (Pada Windows, skrip tidak mengubah `php.ini` otomatis.)

### Langkah C4. Siapkan skrip

Simpan `akreditasi-lengkap.sh` di `C:\laragon\www\`. Pastikan akhir barisnya LF (di Git Bash: `sed -i 's/\r$//' akreditasi-lengkap.sh`).

### Langkah C5. Pasang aplikasi

Buka **Git Bash** (klik kanan di folder `C:\laragon\www` → **Git Bash Here**):

```bash
cd /c/laragon/www
bash akreditasi-lengkap.sh --buat akreditasi --lewati-server
```

Pastikan `php -v` dan `composer -V` di Git Bash berjalan. Jika tidak ditemukan, tambahkan `C:\laragon\bin\php\php-8.x...` dan `C:\laragon\bin\composer` ke PATH Windows, lalu buka Git Bash baru. Alternatifnya, jalankan Git Bash dari **terminal Laragon** (Menu → Terminal), yang sudah mengatur PATH.

### Langkah C6. Buka aplikasi

Pilihan 1, `php artisan serve`:

```bash
cd /c/laragon/www/akreditasi
php artisan serve
```

Buka **http://127.0.0.1:8000**.

Pilihan 2, alamat otomatis Laragon: setelah **Reload** pada Laragon, buka **http://akreditasi.test** (Laragon membuat host virtual dari nama folder, dengan root ke folder `public`).

### Langkah C7 (opsional). Memakai MySQL Laragon alih-alih SQLite

1. Di Laragon buka **Database** (HeidiSQL) atau jalankan `mysql -u root`, lalu buat database `akreditasi` (collation `utf8mb4_unicode_ci`).
2. Sebelum menjalankan skrip pada C5, buat proyek manual: `composer create-project "laravel/laravel:^11.0" akreditasi`, edit `.env` seperti pada [Langkah A4](#langkah-a4-isi-pengaturan-database-di-env) (`DB_HOST=127.0.0.1`, `DB_USERNAME=root`, `DB_PASSWORD=` kosong untuk bawaan Laragon), lalu `cd akreditasi` dan `bash ../akreditasi-lengkap.sh --lewati-server` (tanpa `--buat`).

### Catatan Windows
- Bila `php artisan storage:link` gagal, buka **Command Prompt sebagai Administrator** di folder proyek: `mklink /J public\storage storage\app\public`
- Skrip tidak mengubah izin folder di Windows (tidak diperlukan).

Lanjut ke [bagian 5](#5-setelah-terpasang).

---

## 5. Setelah terpasang

### 5.1 Login pertama

Buka alamat aplikasi, klik **Masuk**:

| | |
|---|---|
| Email | `admin@example.com` |
| Kata sandi | `GantiSandiIni123` |

**Segera ganti** lewat menu **Akun Saya** (ubah juga email bila perlu). Admin tambahan: isi `ADMIN_EMAILS=email1@kampus.ac.id,email2@kampus.ac.id` di `.env`, lalu `php artisan config:clear` (atau `config:cache` pada produksi). Pengguna lain dibuat lewat menu **Kelola Pengguna**.

### 5.2 Daftar periksa

Setelah login, pastikan:

- [ ] Dashboard tampil. Pemilih tampilan (Ringkas, Analitik, Panel) berfungsi.
- [ ] **Kriteria**: tambah satu kriteria dan satu isi kriteria; editor narasi muncul.
- [ ] Unggah satu dokumen PDF pada isi kriteria, lalu klik **Lihat** (pratinjau).
- [ ] **Data Induk**: tambah satu dokumen pada Dokumen Standar Mutu.
- [ ] **Data Induk → LKPS**: buka salah satu tabel, klik **Tambah data**, isi **Lampiran Bukti** berupa berkas atau link. Coba **Impor Excel** dengan templat CSV.
- [ ] **Identitas UPPS dan Program Studi**: isi identitas dan tambah satu dosen homebase.
- [ ] **Analitik**: lima bagian tampil (Budaya Mutu membaca Kriteria **C1**; buat kriteria berkode `C1` bernama Budaya Mutu agar bagian itu terisi).
- [ ] Impor/ekspor Excel `.xlsx`: bila memerlukannya, pastikan `composer require phpoffice/phpspreadsheet` sudah terpasang (skrip memasangnya otomatis kecuali memakai `--tanpa-excel`).

### 5.3 Mengisi data awal

1. Buat **Kriteria** sesuai LAM Infokom (misalnya kode `C1` Budaya Mutu, dan seterusnya) beserta isi/butirnya.
2. Isi **Data Induk** (dokumen standar mutu, universitas, fakultas).
3. Isi **LKPS**: Identitas, Daftar Dosen Homebase, lalu tabel 1 sampai 6 (manual atau impor).
4. Pantau kemajuan di **Dashboard** dan **Analitik**.

---

## 6. Opsi skrip

```bash
bash akreditasi-lengkap.sh [opsi]
```

| Opsi | Fungsi |
|---|---|
| `--buat NAMA` | Buat proyek Laravel 11 baru di folder `NAMA` bila belum ada (butuh Composer). Cocok untuk SQLite. |
| `--produksi` | `APP_ENV=production`, `APP_DEBUG=false`, lalu cache konfigurasi, route, dan view. |
| `--lewati-server` | Jangan ubah izin folder, `php.ini`, atau Apache. Pakai di Windows, hosting bersama, atau tanpa `sudo`. |
| `--paksa` | Timpa kode aplikasi dasar yang sudah terpasang (data database tidak dihapus). |
| `--tanpa-excel` | Jangan pasang PhpSpreadsheet (impor/ekspor `.xlsx` nonaktif; CSV tetap bisa). |
| `--data-induk-db` | (Opsional) pindahkan metadata Data Induk dari berkas JSON ke database. |
| `--tanpa-cadangan` | Lewati cadangan database otomatis. |
| `-h`, `--help` | Bantuan. |

**Aman diulang:** menjalankan ulang pada instalasi yang sudah ada tidak menimpa kode dasar (kecuali `--paksa`), mencadangkan database lebih dulu ke `storage/app/cadangan/`, dan hanya menambah modul/tabel yang belum ada.

---

## 7. Cadangan, pembaruan, dan pindah server

### 7.1 Apa yang perlu dicadangkan

1. **Database** (MySQL: `mysqldump`; SQLite: berkas `database/database.sqlite`).
2. **Folder `storage/app/`**: lampiran LKPS, dokumen Data Induk, dan berkas unggahan.
3. **Berkas `.env`**: berisi kata sandi database dan `APP_KEY`.

### 7.2 Cadangan manual (MySQL)

```bash
cd /var/www/akreditasi
mkdir -p ~/cadangan
mysqldump -u akreditasi -p --single-transaction --no-tablespaces akreditasi | gzip > ~/cadangan/db-$(date +%F).sql.gz
tar -czf ~/cadangan/storage-$(date +%F).tar.gz storage/app .env
```

Cadangan otomatis harian (jalankan `crontab -e`, ganti `SANDI`, `NAMA`):

```cron
15 2 * * * cd /var/www/akreditasi && MYSQL_PWD='SANDI' mysqldump -u akreditasi --single-transaction --no-tablespaces akreditasi | gzip > /home/NAMA/cadangan/db-$(date +\%F).sql.gz && tar -czf /home/NAMA/cadangan/storage-$(date +\%F).tar.gz storage/app .env
```

Salin cadangan juga ke tempat lain (komputer atau penyimpanan terpisah dari server).

### 7.3 Memulihkan cadangan

```bash
gunzip < db-TANGGAL.sql.gz | mysql -u akreditasi -p akreditasi
tar -xzf storage-TANGGAL.tar.gz -C /var/www/akreditasi
sudo chgrp -R www-data /var/www/akreditasi/storage && sudo chmod -R ug+rwX /var/www/akreditasi/storage
cd /var/www/akreditasi && php artisan optimize:clear
```

### 7.4 Memperbarui aplikasi

Bila ada versi baru `akreditasi-lengkap.sh`: cadangkan dulu (7.2), lalu jalankan di folder proyek:

```bash
cd /var/www/akreditasi
bash ~/akreditasi-lengkap.sh --produksi
```

Modul LKPS dan Analitik diperbarui secara aman. Untuk ikut menimpa kode aplikasi dasar, tambahkan `--paksa`.

### 7.5 Pindah ke server lain

1. **Server lama:**
   ```bash
   cd /var/www/akreditasi && php artisan down
   mysqldump -u USER -p --single-transaction --no-tablespaces NAMA_DB | gzip > /tmp/db.sql.gz
   cd /var/www && tar --exclude='akreditasi/vendor' --exclude='akreditasi/node_modules' \
     --exclude='akreditasi/storage/logs/*' --exclude='akreditasi/storage/framework/cache/*' \
     --exclude='akreditasi/storage/framework/views/*' --exclude='akreditasi/storage/framework/sessions/*' \
     -czf /tmp/app.tar.gz akreditasi
   scp /tmp/db.sql.gz /tmp/app.tar.gz USER@SERVER_BARU:/tmp/
   ```
2. **Server baru:** kerjakan [Langkah A1 sampai A2](#2-jalur-a-ubuntu-server-produksi) (paket dan database kosong), lalu:
   ```bash
   gunzip < /tmp/db.sql.gz | sudo mysql NAMA_DB
   sudo tar -xzf /tmp/app.tar.gz -C /var/www
   cd /var/www/akreditasi
   nano .env                         # sesuaikan DB_* dan APP_URL; JANGAN ubah APP_KEY
   composer install --no-dev --optimize-autoloader
   mkdir -p storage/framework/{cache,sessions,views} storage/logs
   php artisan storage:link
   sudo chown -R $USER:www-data . && sudo chmod -R ug+rwX storage bootstrap/cache
   sudo find app resources routes config database public -type f -exec chmod a+r {} +
   php artisan optimize:clear && php artisan up
   ```
3. Atur Nginx dan HTTPS ([Langkah A6 dan A7](#langkah-a6-atur-nginx)), lalu arahkan DNS ke server baru.
4. Pertahankan server lama beberapa hari sebagai cadangan.

---

## 8. Pemecahan masalah

Pertama, selalu lihat pesan galat yang sebenarnya:

```bash
tail -n 40 storage/logs/laravel.log
# atau hanya baris galat:
grep -n "ERROR" storage/logs/laravel.log | tail -3
```

| Gejala | Penyebab dan solusi |
|---|---|
| `Permission denied` / `failed to open stream` | Izin berkas. Jalankan perintah di [Langkah A8](#langkah-a8-pastikan-izin-folder). |
| `500 Server Error` tanpa pesan | Lihat `storage/logs/laravel.log`. Untuk sementara `APP_DEBUG=true` di `.env` (kembalikan `false` setelah selesai), lalu `php artisan config:clear`. |
| `413 Request Entity Too Large` saat unggah | Naikkan `client_max_body_size 25M;` pada Nginx dan `upload_max_filesize=20M`, `post_max_size=25M` pada PHP, lalu muat ulang Nginx dan restart `php-fpm`. |
| `could not find driver` | Ekstensi database PHP belum aktif: `sudo apt install php8.3-mysql php8.3-sqlite3` lalu restart `php-fpm`. Pada Laragon aktifkan `pdo_mysql`/`pdo_sqlite`. |
| `SQLSTATE[HY000] [1045] Access denied` | `DB_USERNAME`/`DB_PASSWORD` di `.env` salah. Setelah mengubah `.env`: `php artisan config:clear`. |
| `SQLSTATE[HY000] [2002] Connection refused` | MySQL belum berjalan (`sudo systemctl start mysql`) atau `DB_HOST` salah. |
| Skrip: `$'\r': command not found` | Akhir baris Windows (CRLF). Jalankan `sed -i 's/\r$//' akreditasi-lengkap.sh`. |
| Skrip: `dibutuhkan PHP 8.2 atau lebih baru` | Naikkan versi PHP (lihat Langkah A1; pada Laragon pilih versi di menu PHP). |
| Skrip: `ekstensi PHP belum aktif: ...` | Pasang atau aktifkan ekstensi yang disebutkan, lalu ulangi skrip. |
| Skrip: `tidak dapat terhubung ke database` | Periksa `DB_*` di `.env` dan pastikan database sudah dibuat (Langkah A2/A4). |
| Skrip: `Instalasi Akreditasi SUDAH ada` | Normal. Gunakan `--paksa` hanya bila ingin menimpa kode dasar. |
| Composer lambat atau `memory exhausted` | `COMPOSER_MEMORY_LIMIT=-1 composer install`. |
| Berkas lampiran tidak bisa dibuka (404) | `php artisan storage:link` (Windows: `mklink /J public\storage storage\app\public`). |
| Editor narasi atau tampilan tidak muncul | Peramban tidak bisa mengakses CDN (Bootstrap/TinyMCE). Periksa koneksi internet klien. |
| Lupa kata sandi admin | `php artisan tinker`, lalu: `App\Models\User::where('email','admin@example.com')->update(['password'=>Hash::make('SandiBaru123')]);` |
| Halaman Analitik: "Sebagian data tidak dapat dibaca" | Kotak kuning menyebut bagian dan pesan galatnya; kirimkan pesannya untuk ditelusuri. |
| `php artisan serve` port 8000 terpakai | `php artisan serve --port=8080`. |

**Perintah berguna:**

```bash
php artisan optimize:clear        # bersihkan semua cache
php artisan lkps:sinkron          # sinkronkan tabel LKPS dengan config/lkps.php (hanya menambah)
php artisan lkps:impor file.xlsx  # impor LKPS dari Excel template resmi
php artisan lkps:ekspor hasil.xlsx
```

**Catatan keamanan:**
- Ganti kata sandi admin awal segera, dan jangan menyimpan `.env` di tempat umum.
- Di produksi gunakan HTTPS, `APP_DEBUG=false`, dan pembaruan sistem berkala (`sudo apt upgrade`).
- Halaman baca bersifat publik. Bila ingin tertutup, jangan buka alamat aplikasi ke internet, atau batasi lewat firewall/VPN kampus.

Catatan rinci per modul dan riwayat pembaruan: `CATATAN-FITUR.md`.
