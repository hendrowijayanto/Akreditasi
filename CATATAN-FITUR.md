# Catatan fitur dan pembaruan (arsip)

> Panduan instalasi terbaru ada di **README.md**. Berkas ini menyimpan catatan rinci per modul/pembaruan.

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
| `migrasi-data-induk-db.sh` | **Opsional.** Memindahkan metadata Data Induk dari JSON ke tabel database dengan aman (lihat bagian 13). |
| `tambah-tampilan.sh` | **Pemilih tampilan Dashboard**: ganti-ganti Ringkas / Analitik / Panel Admin, diingat per browser; sudah ada di installer (bagian 18). |
| `tambah-panel.sh` | **Panel Admin**: dashboard visualisasi gaya admin klasik (kartu statistik, grafik area/radial, aktivitas terbaru); sudah ada di installer (bagian 17). |
| `tambah-analitik.sh` | Halaman **Analitik** (dashboard data analytic): sorotan otomatis, tren, peta panas, corong, butir prioritas (sudah ada di installer; lihat bagian 16). |
| `dashboard-vektor.sh` | Tampilan Dashboard berbasis **grafik vektor (SVG)** untuk situs lama (sudah ada di installer; lihat bagian 15). |
| `tambah-lkps.sh` | **Opsional.** Menambahkan fasilitas **LKPS LAM Infokom** (31 tabel) di bawah menu Data Induk, dengan dashboard gabungan (lihat bagian 14). |
| `README.md` | Panduan ini. |

## 2. Fitur

- **Kriteria Akreditasi** → **Isi Kriteria** (butir, elemen penilaian ditampilkan utuh, narasi dengan editor TinyMCE: tabel, gambar, daftar) → **Detail Dokumen** (unggah berkas atau link).
- **Dashboard capaian**: isian per kriteria, isian narasi, kelengkapan dokumen.
- **Hak akses**: melihat dan membaca tanpa login; tambah, ubah, hapus wajib login.
- **Data Induk**: Dokumen Standar Mutu, Dokumen Universitas, Dokumen Fakultas, Dokumen Tambahan (**tanpa tabel database**; metadata disimpan berupa berkas JSON).
- **Tautan "Lihat"**: dokumen tampil sebagai pratinjau di browser (PDF, gambar; Office bila situs publik HTTPS), bukan langsung terunduh.
- **Gunakan kembali dokumen** yang pernah diunggah (dari Data Induk atau kriteria lain) saat menambah dokumen.
- **Kelola Pengguna** (khusus admin) dan **Akun Saya** (semua pengguna).
- **LKPS LAM Infokom** (opsional, bagian 14): 31 tabel LKPS dengan CRUD, lampiran bukti, impor/ekspor Excel, dan kelengkapannya tampil di Dashboard Akreditasi.
- **Pemilih tampilan Dashboard**: pengguna bebas mengganti model dashboard (Ringkas, Analitik, Panel Admin); pilihannya diingat (bagian 18).
- **Panel Admin**: dashboard visualisasi gaya admin klasik (kartu berikon, tren, aktivitas terbaru, dokumen terbaru), bagian 17.
- **Analitik**: halaman analisis data (sorotan otomatis, tren aktivitas, peta panas, corong kelengkapan, butir prioritas), bagian 16.
- **Dashboard grafik vektor (SVG)**: gauge kesiapan, cincin KPI, diagram radar, dan batang capaian per kriteria (bagian 15).
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
- **Data Induk** menyimpan metadata di `storage/app/data-induk/*.json` dan berkas di `storage/app/public/data-induk/`. Setelah menjalankan `migrasi-data-induk-db.sh`, metadata berada di tabel `data_induk_dokumen` (bagian 13).
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

## 13. (Opsional) Memindahkan Data Induk ke database

Secara bawaan metadata Data Induk (nama, keterangan, link) disimpan sebagai JSON. Skrip `migrasi-data-induk-db.sh` memindahkannya ke tabel **`data_induk_dokumen`** (satu tabel untuk keempat kategori) tanpa merusak data yang ada. Manfaatnya: metadata ikut terbawa di `mysqldump`, pencarian dan pengurutan lebih baik, tercatat siapa yang mengunggah, dan siap untuk fitur lanjutan.

```bash
cd /var/www/akreditasi
bash migrasi-data-induk-db.sh
php artisan config:cache && php artisan route:cache && php artisan view:cache
```
Jalankan dulu di server uji coba. Pada hosting tanpa `mysqldump`, buat cadangan manual (phpMyAdmin → Export) lalu jalankan dengan `--tanpa-dump`.

**Yang dikerjakan skrip (berurutan, berhenti di langkah yang gagal):**
1. Memeriksa koneksi database.
2. Membuat cadangan: `mysqldump` ke `storage/app/cadangan-sebelum-migrasi-datainduk-*.sql`, salinan folder JSON, dan `DataInduk.php.bak7`. Jika cadangan database gagal, skrip **berhenti sebelum mengubah apa pun**.
3. Menulis migration, model, dan dua perintah artisan. Daftar kategori yang sudah ada di `DataInduk.php` dipertahankan.
4. Menjalankan **hanya** migration tabel baru ini (migration lain tidak ikut dijalankan).
5. Mengimpor JSON ke tabel, **memverifikasi** bahwa setiap dokumen ada di tabel, lalu baru mengaktifkan database lewat berkas penanda `storage/app/data-induk/.db-aktif`.

**Jaminan keamanan**
- Hanya **menambah** satu tabel baru; tabel dan data yang ada tidak disentuh.
- Berkas unggahan tidak dipindah, dan **JSON lama tidak dihapus**.
- Jika impor atau verifikasi gagal, aplikasi tetap memakai JSON seperti semula.
- Skrip aman diulang. Setelah database aktif, impor ulang dilewati agar dokumen yang sudah dihapus tidak hidup kembali.
- Identitas dokumen (UUID) dipertahankan, sehingga alamat dan tautan lama tetap berlaku.

**Perintah berguna**
```bash
php artisan datainduk:impor-json --dry-run   # lihat ringkasan tanpa menulis (tabel harus sudah ada)
php artisan datainduk:kembali-ke-json        # jalan kembali: ekspor database ke JSON lalu pakai JSON lagi
```
`datainduk:kembali-ke-json` menyertakan perubahan yang dibuat setelah migrasi dan mencadangkan JSON sebelumnya (`*.json.bak-TANGGAL`). Tabel tidak dihapus.

**Catatan**
- Kategori tetap didefinisikan di kode (`KATEGORI` pada `app/Support/DataInduk.php`); belum ada menu untuk mengelola kategori.
- Skrip mengganti `app/Support/DataInduk.php` dengan versi yang mendukung database dan JSON. Jika Anda pernah mengubah berkas itu selain daftar kategori, perubahan tersebut perlu digabungkan kembali dari `DataInduk.php.bak7`.
- Setelah migrasi, cadangan tetap harus mencakup `storage/app` (berkas unggahan) dan database.

## 14. (Opsional) Menambahkan LKPS LAM Infokom

Skrip `tambah-lkps.sh` menambahkan fasilitas **LKPS** (Diploma III, 31 tabel sesuai template `Data_DKPS_TI-D3_2025_New.xlsx`) ke aplikasi yang sudah berjalan. Sumbernya adalah skrip `buat-lkps-laravel.sh` (aplikasi LKPS terpisah) yang disesuaikan agar **menempel** pada aplikasi ini, bukan membuat proyek baru.

```bash
cd /var/www/akreditasi
bash tambah-lkps.sh
php artisan config:cache && php artisan route:cache && php artisan view:cache
```
Jalankan dulu di server uji coba. Pada hosting tanpa `mysqldump`, buat cadangan manual lalu gunakan `--tanpa-dump`. Opsi lain: `--tanpa-excel` (tidak memasang PhpSpreadsheet) dan `--timpa` (menimpa berkas LKPS yang sudah ada; yang lama dicadangkan `*.bak8`).

**Hasilnya**
- Sidebar: **Data Induk → LKPS** (alamat `/lkps`): daftar 31 tabel per kelompok dengan jumlah baris. Tiap tabel punya CRUD, pencarian, ekspor CSV, dan kolom **Lampiran Bukti** (PDF/gambar hingga 20 MB, dibuka sebagai pratinjau, bukan diunduh).
- **Dashboard Akreditasi gabungan:** kartu utama mendapat angka **Kelengkapan LKPS** (% tabel yang sudah berisi data), dan di bawah tabel capaian muncul bagian **Kelengkapan LKPS** per kelompok. Angka "Kesiapan akreditasi (rata-rata)" tetap dihitung dari tiga ukuran lama, jadi nilainya tidak berubah.
- **Identitas UPPS dan Program Studi** (tombol berwarna kuning di halaman LKPS; berisi sheet Identitas dan **Daftar Dosen Homebase**) serta **Impor & ekspor Excel** memakai template resmi LKPS (unggah template `.xlsx` sekali, lalu ekspor mengisinya).

**Jaminan keamanan data**
- Hanya **menambah** tabel baru berawalan `lkps_` (31 tabel + `lkps_isian`). Tabel yang sudah ada tidak disentuh, dan hanya migration LKPS yang dijalankan.
- `routes/web.php`, layout, dan dashboard **tidak ditimpa**; skrip hanya menyisipkan blok kecil dan mencadangkannya (`*.bak8`). Controller dan halaman lama tidak diubah.
- Cadangan database (`mysqldump`) dibuat lebih dulu; jika gagal, skrip berhenti sebelum mengubah apa pun.
- Berkas yang sudah ada (misalnya `config/lkps.php` yang Anda ubah) tidak ditimpa. Skrip aman diulang.
- Migration `down()` hanya menghapus tabel LKPS yang **kosong**; tabel berisi data dibiarkan.
- Impor Excel secara bawaan **menambahkan** data (tidak menghapus). Mode **ganti** (menghapus isi tabel yang ada di file) hanya tersedia untuk **admin**, begitu juga pengunggahan template.

**Hak akses:** melihat dan mengekspor: publik; tambah/ubah/hapus: login; impor Excel, mode ganti, dan unggah template: admin (bila fitur Kelola Pengguna terpasang; jika tidak, semua pengguna yang login).

**Perintah artisan**
```bash
php artisan lkps:sinkron                 # buat tabel/kolom baru sesuai config/lkps.php (tidak menghapus data)
php artisan lkps:impor file.xlsx         # menambahkan; tambahkan --ganti untuk mengganti isi tabel
php artisan lkps:ekspor hasil.xlsx       # isi template dengan seluruh data
```
**Mengubah struktur tabel LKPS:** edit `config/lkps.php` (satu-satunya berkas definisi), lalu `php artisan lkps:sinkron`. Kolom baru ditambahkan tanpa menghapus data lama.

**Yang perlu diperhatikan**
- Impor/ekspor Excel membutuhkan pustaka **PhpSpreadsheet** dan ekstensi PHP `zip`, `gd`, `xml`, `mbstring`. Skrip memasangnya lewat Composer (mengubah `composer.json` dan `composer.lock`; simpan keduanya). Tanpa pustaka itu, bagian lain LKPS tetap berfungsi dan halaman Excel menampilkan petunjuk.
- **Lampiran Bukti** disimpan di disk privat Laravel (`storage/app/private/lkps/...` pada Laravel 11) dan dibuka lewat halaman pratinjau. Sertakan folder `storage/app` dalam backup, bersama database.
- Pratinjau Lampiran, seperti "Lihat" pada Data Induk, bukan pengaman: siapa pun yang membuka halamannya dapat melihat lampiran karena aturan baca bebas.
- Kode inti LKPS (`config/lkps.php`, `config/lkps_excel.php`, dan kelas `Lkps*`) dipakai sama seperti pada skrip asli Anda. Bagian impor/ekspor Excel belum diuji karena membutuhkan template resmi dan PhpSpreadsheet.
- **Batal/lepas:** hapus blok `LKPS` pada `routes/web.php`, baris menu LKPS pada layout, dan dua baris `@includeIf('lkps...')` pada dashboard (atau kembalikan dari `*.bak8`). Tabel `lkps_*` boleh dibiarkan.

## 15. Dashboard grafik vektor (SVG)

Dashboard memakai grafik **vektor (SVG)** yang digambar langsung oleh server, tanpa pustaka JavaScript atau file gambar. Grafiknya tajam di layar apa pun (termasuk saat di-zoom atau dicetak), ringan, dan warnanya mengikuti tema.

**Isi tampilan**
- **Gauge besar "Kesiapan Akreditasi"** (rata-rata isian kriteria, narasi, dan dokumen) dengan latar biru gradien.
- **Empat cincin KPI:** Isian kriteria, Isian narasi, Kelengkapan dokumen, dan Kelengkapan LKPS (cincin LKPS muncul otomatis bila LKPS terpasang).
- **Diagram radar** profil capaian seluruh kriteria (tampil bila ada minimal 3 kriteria) dan **batang capaian per kriteria** untuk isian, narasi, dan dokumen.
- **Kelengkapan LKPS:** cincin ringkasan dan segmen per kelompok tabel (hijau = sudah berisi data).
- **Tabel rincian per kriteria** tetap ada di bawahnya, jadi angka persisnya selalu terbaca, termasuk oleh pembaca layar. Setiap grafik juga memiliki teks alternatif (`aria-label`).

**Pemasangan**
- **Instalasi baru:** sudah termasuk dalam `akreditasi-installer.sh` (langkah 7 dari 8).
- **Situs yang sudah berjalan:**
  ```bash
  cd /var/www/akreditasi
  bash dashboard-vektor.sh
  php artisan view:cache
  ```
  Skrip hanya mengganti tampilan (Blade): `dashboard.blade.php` lama dicadangkan sebagai `dashboard.blade.php.bak9`, dan partial grafik ditulis di `resources/views/vk/`. Controller, route, database, dan data tidak disentuh. Skrip aman diulang, dan bisa dijalankan sebelum atau sesudah `tambah-lkps.sh`.
- **Kembali ke tampilan lama:** `cp resources/views/dashboard.blade.php.bak9 resources/views/dashboard.blade.php && php artisan view:clear`.

**Mengubah tampilan:** warna dan ukuran ada di `resources/views/vk/_gaya.blade.php` (CSS) dan di partial `vk/gauge`, `vk/ring`, `vk/radar`, `vk/batang`, `vk/segmen`. Susunan halaman ada di `resources/views/dashboard.blade.php`.

**Catatan:** animasi gambar busur otomatis nonaktif bagi pengguna yang mengaktifkan "kurangi gerakan" di perangkatnya. Dashboard membutuhkan browser modern (Chrome, Edge, Firefox, Safari versi beberapa tahun terakhir). Mode gelap tidak didukung pada versi Laravel (hanya terang), seperti bagian lain tema.

## 16. Halaman Analitik (dashboard data analytic)

Menu **Analitik** (di bawah Dashboard, alamat `/analitik`) menganalisis data yang sudah ada dan menampilkannya dengan grafik vektor (SVG). Halaman ini **hanya membaca data**: tidak ada tabel baru, tidak ada migration, dan tidak ada data yang diubah.

**Isi halaman**
- **Sorotan otomatis:** kriteria dengan capaian terendah dan tertinggi, jumlah butir tanpa narasi atau tanpa dokumen, tren aktivitas 30 hari, dan kelengkapan LKPS (bila terpasang).
- **Empat KPI:** kesiapan keseluruhan, butir siap, total dokumen (dengan grafik kumulatif 12 minggu), dan aktivitas 30 hari (dengan perubahan dibanding 30 hari sebelumnya).
- **Aktivitas pengisian per bulan** (pilihan 3, 6, atau 12 bulan): dokumen kriteria, Data Induk, LKPS, dan butir yang diperbarui.
- **Status butir** (siap, sebagian, belum dimulai), **peta panas** capaian kriteria × (isian, narasi, dokumen), **corong** dari seluruh butir sampai siap, dan **jenis dokumen** (PDF, Word, Excel, PowerPoint, gambar, arsip, tautan).
- **Butir prioritas:** delapan butir dengan celah terbesar, lengkap dengan penyebabnya dan tautan **Buka** langsung ke butir itu.

**Definisi** (juga tertulis di bawah halaman)
- Butir **siap**: narasi terisi (teks, gambar, atau tabel), memiliki minimal satu dokumen, dan isian ≥ 80%. Butir **belum dimulai**: tanpa narasi, tanpa dokumen, isian 0%. Selain itu: **sebagian**.
- **Kesiapan keseluruhan** memakai rumus yang sama dengan Dashboard (rata-rata isian, narasi, dokumen), sehingga angkanya selalu sama.
- **Aktivitas** dihitung dari tanggal tambah atau ubah data. Itu berarti riwayat sebelum aplikasi dipakai tidak ada, dan satu butir yang diubah berkali-kali pada bulan yang sama dihitung satu kali. Tidak ada prakiraan atau data buatan; semua angka berasal dari data yang tersimpan.

**Pemasangan**
- **Instalasi baru:** sudah termasuk dalam `akreditasi-installer.sh` (langkah 8 dari 9).
- **Situs yang sudah berjalan:**
  ```bash
  cd /var/www/akreditasi
  bash tambah-analitik.sh
  php artisan route:cache && php artisan view:cache
  ```
  Skrip menulis berkas baru, lalu menyisipkan satu route dan satu menu (`routes/web.php` dan layout dicadangkan `*.bak10`). Aman diulang, dan Data Induk serta LKPS dibaca otomatis bila terpasang.
- **Melepas:** hapus blok `Analitik` pada `routes/web.php` dan blok menu `Analitik` pada layout (atau kembalikan dari `*.bak10`).

**Hak akses dan kinerja:** halaman ini dapat dilihat publik, sama seperti Dashboard. Perhitungannya membaca seluruh kriteria, butir, dan dokumen, ditambah tanggal baris pada tabel LKPS; ini cepat untuk ribuan baris. Bila data sangat besar, hasilnya dapat disimpan di cache beberapa menit.

**Mengubah:** perhitungan ada di `app/Support/Analitik.php`, susunan halaman di `resources/views/analitik/index.blade.php`, dan grafik di `resources/views/vk/` (`spark`, `donat`, `tumpuk`, `peta`, `corong`).

## 17. Panel Admin (dashboard visualisasi gaya admin)

Menu **Panel Admin** (di bawah Dashboard dan Analitik, alamat `/panel`) adalah model dashboard lain: tampilan admin klasik dengan grafik vektor (SVG). Dashboard utama dan Analitik tetap ada, sehingga Anda bisa memakai model yang paling cocok. Seperti Analitik, halaman ini **hanya membaca data**: tidak ada tabel baru, migration, atau perubahan data.

**Isi halaman**
- **Sapaan dan aksi cepat:** "Halo, nama" bagi yang sudah login (tombol Kelola kriteria, Unggah Data Induk, LKPS, Analitik); pengunjung melihat tombol Masuk.
- **Empat kartu statistik** berikon gradien dengan grafik mini: Kriteria, Butir penilaian, Dokumen, dan **Pengguna** (hanya tampil bagi yang login; pengunjung melihat **Dokumen Data Induk**). Setiap kartu menampilkan penambahan bulan ini.
- **Tren aktivitas** 12 bulan (grafik area) dan **kelengkapan** (grafik radial: isian, narasi, dokumen, dan LKPS bila terpasang).
- **Progres per kriteria**, **dokumen Data Induk per kategori**, dan **aktivitas terbaru** (linimasa dengan waktu relatif seperti "3 hari lalu").
- **Dokumen terbaru** (dari kriteria dan Data Induk, dengan tautan Lihat) dan daftar **Perlu perhatian** (butir dengan celah terbesar, tautan Buka).

**Pemasangan**
- **Instalasi baru:** sudah termasuk dalam `akreditasi-installer.sh` (langkah 9 dari 10).
- **Situs yang sudah berjalan:**
  ```bash
  cd /var/www/akreditasi
  bash tambah-panel.sh
  php artisan route:cache && php artisan view:cache
  ```
  Skrip menulis berkas baru lalu menyisipkan satu route dan satu menu (`routes/web.php` dan layout dicadangkan `*.bak11`). Aman diulang. Halaman memakai kelas `Analitik`; bila belum ada, skrip ikut memasangnya (tanpa menambah menu Analitik).
- **Melepas:** hapus blok `Panel Admin` pada `routes/web.php` dan menu `Panel Admin` pada layout (atau kembalikan dari `*.bak11`).

**Catatan**
- Aktivitas dan penambahan bulan ini dihitung dari tanggal tambah/ubah data, sama seperti Analitik. Pengguna dihitung dari tabel `users`; tidak ada nama atau data pribadi yang ditampilkan di linimasa.
- Halaman ini dapat dilihat publik, kecuali kartu Pengguna dan tombol aksi cepat yang hanya muncul bagi yang login.
- **Mengubah:** perhitungan di `app/Support/Panel.php`, susunan halaman di `resources/views/panel/index.blade.php`, grafik di `resources/views/vk/` (`area`, `radial`, `hbar`, `spark`).

## 18. Pemilih tampilan Dashboard (ganti-ganti dashboard)

Aplikasi punya tiga model dashboard: **Ringkas** (Dashboard bawaan dengan gauge kesiapan), **Analitik**, dan **Panel Admin**. Di atas ketiganya ada pilihan segmen **"Tampilan dashboard"** untuk berpindah kapan saja.

**Cara kerja**
- Klik salah satu pilihan, dan halaman **Dashboard** (menu pertama, alamat `/`) langsung menampilkan model itu. Alamatnya tidak berubah dan menu Dashboard tetap yang menyala.
- Pilihan **diingat per browser** (cookie 1 tahun), sehingga setiap pengguna dapat memakai model kesukaannya sendiri, termasuk pengunjung tanpa login. Menu **Analitik** dan **Panel Admin** tetap bisa dibuka langsung.
- **Model bawaan** bagi pengunjung yang belum memilih diatur admin lewat `.env`:
  ```
  DASHBOARD_DEFAULT=ringkas    # atau analitik, atau panel
  ```
  lalu `php artisan config:cache`. Pilihan pengguna di browsernya selalu didahulukan, kemudian model bawaan, kemudian Ringkas.
- Model yang belum terpasang otomatis tidak muncul (dan diabaikan bila ada di cookie atau `.env`). Bila hanya Ringkas yang terpasang, pemilih disembunyikan.

**Pemasangan**
- **Instalasi baru:** sudah termasuk dalam `akreditasi-installer.sh` (langkah 10 dari 11).
- **Situs yang sudah berjalan:**
  ```bash
  cd /var/www/akreditasi
  bash tambah-tampilan.sh
  php artisan route:cache && php artisan view:cache
  ```
  Skrip menulis berkas pemilih (`PilihDashboard`, `TampilanController`, `config/tampilan.php`, partial `dash/_pilih`), menambah satu route, menyisipkan `->middleware(PilihDashboard::class)` pada route halaman utama, dan menyisipkan satu baris pemilih pada ketiga halaman dashboard. Semua perubahan pada `routes/web.php` dan view dicadangkan `*.bak12`. Skrip aman diulang. Pasang dulu `tambah-analitik.sh` dan `tambah-panel.sh` agar pemilihnya menampilkan ketiga model.
- **Melepas:** hapus `->middleware(\App\Http\Middleware\PilihDashboard::class)` dari route `/`, route `dashboard.tampilan`, dan baris `@includeIf('dash._pilih', ...)` pada tiga halaman (atau kembalikan dari `*.bak12`).

**Catatan**
- Tidak ada tabel, migration, atau data yang diubah; hanya cookie di browser pengguna.
- Jika Anda memasang ulang dashboard dengan `--timpa` pada skrip lama, jalankan ulang `tambah-tampilan.sh` bila pemilihnya hilang dari halaman.
- Saat model Analitik tampil di `/`, tombol periode (3/6/12 bulan) membuka halaman `/analitik` agar parameter periode ikut terbawa.

## 19. Pembaruan menu LKPS: Identitas UPPS dan Program Studi + Daftar Dosen Homebase

Untuk situs yang **sudah** menjalankan `tambah-lkps.sh`, jalankan skrip patch (pemasangan baru lewat `tambah-lkps.sh` versi terbaru sudah memuat perubahan ini):

```bash
cd /var/www/akreditasi
bash perbarui-lkps-identitas.sh        # tambahkan --tanpa-dump bila tanpa mysqldump
php artisan config:cache && php artisan route:cache && php artisan view:cache
```

**Perubahan**
- Halaman LKPS: subjudul diganti menjadi **"Laporan Kinerja Program Studi Tahun Semester 2023/2024, 2024/2025 dan 2025/2026"** (satu baris, menggantikan subjudul "Tahun TS" sebelumnya).
- Tombol *Identitas & isian tambahan* menjadi **"Identitas UPPS dan Program Studi"** dengan warna sorot kuning.
- Di halaman itu, **Tabel 3.A.3 Jumlah Dosen DTPR** tidak lagi tampil dan diganti **Daftar Dosen Homebase**: Nama Dosen, NIDN, NUPTK, Golongan, Jabatan Fungsional Akademik, Pendidikan S1, S2, S3, Keilmuan, dan Lampiran Bukti. Datanya disimpan di tabel baru `lkps_dosen_homebase`, jadi tersedia tombol *Tambah dosen*, *Kelola daftar* (ubah/hapus/ekspor CSV), dan lampiran bukti PDF/gambar hingga 20 MB.

**Keamanan data:** hanya menambah satu tabel; tidak ada tabel atau kolom yang dihapus. Nilai lama *Jumlah Dosen DTPR* di `lkps_isian` **tidak dihapus** (hanya disembunyikan dari formulir lewat `isian_sembunyi` di `config/lkps.php`). Berkas yang diubah dicadangkan `*.bak13`, database dicadangkan lebih dulu, dan skrip aman diulang. Daftar Dosen Homebase belum dipetakan ke template Excel, sehingga tidak ikut impor/ekspor Excel. Daftar Dosen Homebase **tidak** tampil dalam daftar 31 tabel LKPS dan tidak dihitung pada kelengkapan di dashboard; datanya hanya ada di halaman *Identitas UPPS dan Program Studi* (tombol *Kelola daftar* di sana membuka halaman CRUD-nya). Pengaturannya: `'tersembunyi' => true` pada tabel `dosen_homebase` di `config/lkps.php`.

**Catatan:** bila Anda sudah menjalankan versi pertama skrip ini, jalankan `perbarui-lkps-identitas.sh` sekali lagi: skrip menambahkan kolom **Golongan** dan **Jabatan Fungsional Akademik** (kolom baru, data dosen yang sudah ada tidak berubah).

**CRUD dosen di halaman Identitas:** setiap baris dosen punya tombol **Ubah** dan **Hapus** (khusus yang sudah login), di samping **Tambah dosen**. Setelah simpan, ubah, atau hapus, Anda kembali ke halaman Identitas (bukan ke daftar tabel). Menghapus dosen juga menghapus berkas lampirannya. Situs yang sudah memakai versi sebelumnya: jalankan `perbarui-lkps-identitas.sh` sekali lagi (mengubah `LkpsController.php` dan `form.blade.php`, dicadangkan `*.bak13`).

## 20. Lampiran Bukti berupa Link + Impor Excel/CSV per tabel LKPS

```bash
bash perbarui-lkps-link-impor.sh          # untuk situs yang sudah memasang LKPS
# pemasangan baru: tambah-lkps.sh versi terbaru sudah memuat semuanya
```

**Lampiran Bukti (Link).** Pada form *Tambah data* / *Ubah data* di setiap tabel LKPS (termasuk Daftar Dosen Homebase) ada kolom baru **Lampiran Bukti (Link)** di samping unggah berkas. Isi dengan alamat `http://` atau `https://` (Google Drive, repositori, situs resmi). Boleh diisi bersama berkas. Di tabel muncul **Lihat bukti** (berkas) dan/atau **Buka link**. Pada ekspor Excel, bila tidak ada berkas, yang dicantumkan adalah link-nya. Kolom baru dibuat oleh `php artisan lkps:sinkron` (aditif; data lama tidak berubah).

**Impor per tabel.** Setiap tabel punya tombol **Impor Excel** (khusus yang sudah login): unduh templat (kolom sudah sesuai tabel), isi, unggah.
- Format: `.xlsx`/`.xls` (butuh `composer require phpoffice/phpspreadsheet`; lembar bernama "Data") atau `.csv` (pemisah `;`, `,` atau tab; selalu bisa tanpa tambahan paket).
- Impor **hanya menambah** baris; data yang ada tidak diubah atau dihapus.
- **Semua atau tidak sama sekali**: bila ada satu baris yang salah (kolom wajib kosong, angka/tanggal/pilihan tidak valid, link tidak valid), tidak ada yang disimpan dan nomor baris yang salah ditampilkan.
- Kolom yang tidak dikenal diabaikan; nama kolom tidak peka huruf besar/kecil; angka format Indonesia (`1.234,5`) dan tanggal `dd/mm/yyyy` dikenali.
- **Lampiran berkas tidak dapat diimpor** (unggah lewat Ubah data), tetapi kolom *Lampiran Bukti (Link)* bisa diimpor.
- Untuk Daftar Dosen Homebase, tombol Impor Excel ada di halaman *Identitas UPPS dan Program Studi*.

Berkas yang diubah dicadangkan `*.bak14`. Catatan pengujian: logika pembaca berkas, dan skrip patch (dua kali jalan) diuji pada simulasi; jalur `.xlsx` serta tampilan di Laravel nyata belum diuji, karena PhpSpreadsheet dan Laravel tidak tersedia di lingkungan pengujian.

## 21. Analitik lima aspek (Budaya Mutu, Relevansi Pendidikan, Penelitian, PkM, Akuntabilitas)

```bash
bash ganti-analitik-lima-aspek.sh      # prasyarat: tambah-analitik.sh sudah dijalankan
```

Isi halaman **Analitik** diganti dengan lima bagian berdiagram (kotak ringkasan di atas bisa diklik untuk meloncat ke bagiannya). Tulisan "Analisis kesiapan, kelengkapan, dan aktivitas pengisian · data per ..." dan pemilih periode dihapus.

| Aspek | Sumber data | Diagram |
|---|---|---|
| 1. Budaya Mutu | Kriteria **C1** (kode `C1` atau nama memuat "Budaya Mutu") dan Dokumen Standar Mutu (Data Induk) | kesiapan isian/narasi/dokumen, isian per butir, jenis dokumen |
| 2. Relevansi Pendidikan | Daftar Dosen Homebase (Doktor bila Pendidikan S3 terisi, Magister bila S2 terisi; jabatan fungsional), tabel 1.A.4 (rata-rata beban DTPR), 2.B.4 (masa tunggu lulusan, rata-rata tertimbang jumlah terlacak), 2.A.3 (kondisi jumlah mahasiswa) | donat, batang, kolom |
| 3. Relevansi Penelitian | 3.C.2 Publikasi, 3.C.3 HKI | publikasi per jenis, per tahun, HKI per jenis |
| 4. Relevansi PkM | 4.C.1 Kerja sama, 4.C.2 Diseminasi, 4.C.3 HKI PkM | donat, batang, kolom per tahun |
| 5. Akuntabilitas | 5.1 Sistem Tata Kelola, 5.2 Sarana dan Prasarana | donat akses, kepemilikan, lisensi |

Hanya membaca data (tidak ada migrasi). Berkas lama dicadangkan `*.bak15` dan skrip aman diulang. Bagian yang datanya belum diisi menampilkan "Belum ada data" beserta tautan ke tabel LKPS terkait. Kelas lama `Analitik` tetap ada (dipakai dashboard lain). Catatan pengujian: logika hitung diuji dengan data contoh, tampilan dirender dengan pengompil Blade tiruan dan diperiksa lewat screenshot; belum dijalankan di Laravel sungguhan.

**Pengaman error (pembaruan).** `AnalitikLima::data()` membaca tiap bagian secara terpisah: bila satu sumber data gagal dibaca (mis. tabel rusak), bagian itu tampil kosong dan sebuah kotak kuning di atas halaman menyebut bagian serta pesan galatnya, bukan error 500. Bila penyusunan halaman gagal total, `AnalitikController` menampilkan halaman cadangan `analitik/galat.blade.php` (tanpa layout) berisi pesan galat untuk pengguna yang login atau saat `APP_DEBUG=true`, dan mencatat detailnya di `storage/logs/laravel.log`. Jalankan ulang `ganti-analitik-lima-aspek.sh` untuk memasang pembaruan ini.
