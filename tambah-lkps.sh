#!/usr/bin/env bash
# =====================================================================
# MENAMBAHKAN LKPS LAM INFOKOM (Diploma III) KE SISTEM INFORMASI AKREDITASI
# Sekolah Vokasi Universitas Tiga Serangkai
#
# - Menu "LKPS" berada di bawah menu "Data Induk" (sidebar).
# - Lampiran Bukti: unggah berkas ATAU link; Impor Excel/CSV per tabel.
# - 32 tabel LKPS termasuk Daftar Dosen Homebase (CRUD, lampiran bukti, impor/ekspor Excel, isian identitas),
#   bersumber dari skrip buat-lkps-laravel.sh.
# - Kelengkapan LKPS tampil di Dashboard Akreditasi yang sama (angka di kartu
#   utama + bagian "Kelengkapan LKPS").
#
# JAMINAN KEAMANAN (data yang sudah ada tidak dirusak):
#  - Hanya MENAMBAH tabel baru berawalan "lkps_" (dan tabel lkps_isian).
#    Tabel lama (kriteria, dokumen, pengguna, dll.) tidak disentuh.
#  - Hanya migration LKPS yang dijalankan (migration lain tidak ikut).
#  - routes/web.php, layout, dan dashboard TIDAK ditimpa: hanya disisipi blok kecil
#    (dicadangkan sebagai *.bak8). Controller/halaman lama tidak diubah.
#  - Sebelum mengubah apa pun: cadangan database (mysqldump) kecuali --tanpa-dump.
#  - Berkas yang sudah ada tidak ditimpa (config/lkps.php Anda aman) kecuali --timpa.
#  - Impor Excel secara bawaan MENAMBAH (tidak menghapus); mode "ganti" hanya admin.
#  - Aman diulang.
#
# Pemakaian (di root proyek Sistem Informasi Akreditasi):
#   bash tambah-lkps.sh [--tanpa-dump] [--tanpa-excel] [--timpa]
#     --tanpa-dump   lewati mysqldump (hanya bila Anda sudah membuat cadangan sendiri)
#     --tanpa-excel  jangan pasang pustaka PhpSpreadsheet (impor/ekspor Excel nonaktif)
#     --timpa        timpa berkas LKPS yang sudah ada (yang lama dicadangkan *.bak8)
#   Variabel opsional: LKPS_TAHUN_TS=2025/2026  LKPS_TEMPLATE=/path/template.xlsx
# =====================================================================
set -e
if [ ! -f artisan ]; then echo "Error: jalankan di root proyek Laravel."; exit 1; fi

TANPA_DUMP=0; TANPA_EXCEL=0; TIMPA=0
for a in "$@"; do
  case "$a" in
    --tanpa-dump) TANPA_DUMP=1;; --tanpa-excel) TANPA_EXCEL=1;; --timpa) TIMPA=1;;
    -h|--help) sed -n '2,34p' "$0"; exit 0;;
    *) echo "Opsi tidak dikenal: $a"; exit 1;;
  esac
done
LKPS_TAHUN_TS="${LKPS_TAHUN_TS:-2025/2026}"
TS=$(date +%Y%m%d-%H%M%S)
L=resources/views/layout.blade.php
R=routes/web.php
DBV=resources/views/dashboard.blade.php
MIG=database/migrations/2026_10_08_000100_create_lkps_tables.php

echo "[1/7] Pemeriksaan awal..."
[ -f "$R" ] || { echo "Error: $R tidak ditemukan."; exit 1; }
if [ ! -f "$L" ] || ! grep -q "yield('content')" "$L"; then
  echo "Error: layout aplikasi ($L) tidak ditemukan atau tidak memakai @yield('content')."; exit 1
fi
command -v perl >/dev/null 2>&1 || { echo "Error: perl dibutuhkan."; exit 1; }
php -r 'exit(version_compare(PHP_VERSION,"8.2.0",">=")?0:1);' || { echo "Error: dibutuhkan PHP 8.2 atau lebih baru."; exit 1; }
if ! php artisan migrate:status >/dev/null 2>&1; then
  echo "  GAGAL: tidak dapat terhubung ke database. Periksa DB_* pada .env, lalu ulangi."; exit 1
fi
echo "  OK"

# ---------- 2. CADANGAN ----------
echo "[2/7] Cadangan..."
mkdir -p storage/app
envval() { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//'; }
if [ "$TANPA_DUMP" = 1 ]; then
  echo "  --  cadangan database dilewati (--tanpa-dump)"
else
  CONN=$(envval DB_CONNECTION)
  if { [ "$CONN" = mysql ] || [ "$CONN" = mariadb ]; } && command -v mysqldump >/dev/null 2>&1; then
    DUMP="storage/app/cadangan-sebelum-lkps-$TS.sql"
    if MYSQL_PWD="$(envval DB_PASSWORD)" mysqldump -h "$(envval DB_HOST)" -P "$(envval DB_PORT)" -u "$(envval DB_USERNAME)" \
         --single-transaction --no-tablespaces "$(envval DB_DATABASE)" > "$DUMP" 2>/dev/null && [ -s "$DUMP" ]; then
      echo "  OK  database -> $DUMP"
    else
      rm -f "$DUMP"
      echo "  GAGAL membuat cadangan database. Tidak ada yang diubah."
      echo "  Buat cadangan manual (phpMyAdmin > Export, atau mysqldump), lalu ulangi dengan --tanpa-dump."
      exit 1
    fi
  else
    echo "  GAGAL: mysqldump tidak tersedia atau DB_CONNECTION bukan mysql/mariadb. Tidak ada yang diubah."
    echo "  Buat cadangan database manual, lalu ulangi dengan --tanpa-dump."
    exit 1
  fi
fi
for f in "$R" "$L" "$DBV"; do
  if [ -f "$f" ] && ! grep -q "lkps\." "$f"; then cp "$f" "$f.bak8"; echo "  OK  $f -> $f.bak8"; fi
done

# ---------- 3. PUSTAKA EXCEL (opsional) ----------
echo "[3/7] Pustaka Excel (PhpSpreadsheet)..."
if [ "$TANPA_EXCEL" = 1 ]; then
  echo "  --  dilewati (--tanpa-excel); impor/ekspor Excel akan menampilkan petunjuk pemasangan."
elif php -r 'require "vendor/autoload.php"; exit(class_exists("PhpOffice\\PhpSpreadsheet\\IOFactory") ? 0 : 1);' 2>/dev/null; then
  echo "  OK  PhpSpreadsheet sudah terpasang"
elif command -v composer >/dev/null 2>&1; then
  for e in zip gd xml mbstring; do php -m | grep -qi "^$e$" || echo "  PERINGATAN: ekstensi PHP '$e' belum aktif (dibutuhkan PhpSpreadsheet)."; done
  if composer require phpoffice/phpspreadsheet --no-interaction; then echo "  OK  PhpSpreadsheet dipasang";
  else echo "  PERINGATAN: pemasangan PhpSpreadsheet gagal. LKPS tetap berfungsi; impor/ekspor Excel nonaktif sampai: composer require phpoffice/phpspreadsheet"; fi
else
  echo "  PERINGATAN: composer tidak ditemukan. Impor/ekspor Excel nonaktif sampai: composer require phpoffice/phpspreadsheet"
fi

# ---------- 4. BERKAS BARU ----------
echo "[4/7] Menulis berkas LKPS..."
tulis() {   # tulis <path> (isi dari stdin). Berkas yang sudah ada tidak ditimpa kecuali --timpa
  local f="$1"
  if [ -f "$f" ] && [ "$TIMPA" != 1 ]; then cat >/dev/null; echo "  (sudah ada, dilewati) $f"; return 0; fi
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] && cp "$f" "$f.bak8"
  cat > "$f"
  echo "  OK  $f"
}

tulis config/lkps.php <<'EOF'
<?php
/*
|--------------------------------------------------------------------------
| Definisi 31 tabel LKPS LAM Infokom (Program Diploma III)
|--------------------------------------------------------------------------
| Mengikuti template "Data_DKPS_TI-D3_2025_New.xlsx": satu tabel database
| per sheet, kolom dan urutannya sama dengan kolom di template.
|
| Format kolom:  'nama_kolom' => [Label, tipe, aturan_validasi, opsi_select]
|   - Label bertingkat ditulis dengan "|" seperti header Excel bertingkat,
|     mis. 'Jumlah Mahasiswa Baru|Reguler|Diterima'.
|   - Tipe: text, textarea, number, decimal, date, select, check, url, file
|     check = kotak centang, ditampilkan dan diekspor sebagai √
|     url   = tautan/teks (mis. Tugas Pokok dan Fungsi)
|   Setiap tabel otomatis mendapat kolom "Lampiran Bukti" (unggah PDF/gambar,
|   dibuka sebagai pratinjau). Kolom Link Bukti di template Excel diisi dengan
|   link pratinjau lampiran tersebut saat ekspor.
| 'ringkasan' => ['jumlah'] / ['jumlah', 'rata'] menampilkan baris Jumlah
|   (dan Rata-rata) di bawah tabel, seperti di template.
| Setelah mengedit, jalankan:  php artisan lkps:sinkron
*/

$ts3   = ['TS-2', 'TS-1', 'TS'];
$ts4   = ['TS-3', 'TS-2', 'TS-1', 'TS'];
$lni   = ['L', 'N', 'I'];

// Tiga kolom TS-2/TS-1/TS dengan grup header opsional.
$perTs = function (string $grup = '', string $tipe = 'number', string $prefix = '') {
    $g = $grup !== '' ? $grup . '|' : '';
    return [
        $prefix . 'ts2' => [$g . 'TS-2', $tipe, 'nullable'],
        $prefix . 'ts1' => [$g . 'TS-1', $tipe, 'nullable'],
        $prefix . 'ts'  => [$g . 'TS', $tipe, 'nullable'],
    ];
};

$sarpras = [
    'nama_prasarana' => ['Nama Prasarana', 'text', 'required'],
    'daya_tampung'   => ['Daya Tampung', 'number', 'nullable'],
    'luas_ruang'     => ['Luas Ruang (m²)', 'decimal', 'nullable'],
    'kepemilikan'    => ['Milik Sendiri (M)/Sewa (W)', 'select', 'nullable', ['M', 'W']],
    'lisensi'        => ['Berlisensi (L)/Public Domain (P)/Tidak Berlisensi (T)', 'select', 'nullable', ['L', 'P', 'T']],
    'perangkat'      => ['Perangkat', 'textarea', 'nullable'],
];

$hibah = fn (string $ketua, string $judul, string $jenis) => array_merge([
    'nama_dtpr'        => [$ketua, 'text', 'required'],
    'judul'            => [$judul, 'text', 'required'],
    'jumlah_mahasiswa' => ['Jumlah Mahasiswa yang Terlibat', 'number', 'nullable'],
    'jenis_hibah'      => [$jenis, 'text', 'nullable'],
    'sumber'           => ['Sumber|L/N/I', 'select', 'nullable', $lni],
    'durasi'           => ['Durasi (tahun)', 'decimal', 'nullable'],
], $perTs('Pendanaan (Rp juta)', 'decimal', 'dana_'));

$kerjasama = array_merge([
    'judul_kerjasama' => ['Judul Kerja Sama', 'text', 'required'],
    'mitra'           => ['Mitra Kerja Sama', 'text', 'required'],
    'sumber'          => ['Sumber|L/N/I', 'select', 'nullable', $lni],
    'durasi'          => ['Durasi (tahun)', 'text', 'nullable'],
], $perTs('Pendanaan (Rp juta)', 'decimal', 'dana_'));

$hki = array_merge([
    'judul'     => ['Judul', 'text', 'required'],
    'jenis_hki' => ['Jenis HKI', 'text', 'required'],
    'nama_dtpr' => ['Nama DTPR', 'text', 'required'],
], $perTs('Tahun Perolehan (√)', 'check'));

$pl = [];
foreach (range(1, 5) as $i) {
    $pl["pl{$i}"] = ["Profil Lulusan (PL)|PL {$i}", 'check', 'nullable'];
}

return [

    'tahun_ts' => env('LKPS_TAHUN_TS', '2025/2026'),

    'kelompok' => [
        'k0' => 'Identitas UPPS dan Program Studi',
        'k1' => 'Tabel 1: Pimpinan, Keuangan, SDM & SPMI',
        'k2' => 'Tabel 2: Mahasiswa, Pembelajaran & Lulusan',
        'k3' => 'Tabel 3: Penelitian',
        'k4' => 'Tabel 4: Pengabdian kepada Masyarakat',
        'k5' => 'Tabel 5: Tata Kelola & Sarana Pendidikan',
        'k6' => 'Tabel 6: Visi dan Misi',
    ],

    /*
    | Grup pada 'isian' yang tidak lagi ditampilkan di formulir (nilai lamanya tetap tersimpan di
    | tabel lkps_isian dan tetap ikut impor/ekspor Excel). "Jumlah Dosen DTPR" digantikan oleh
    | tabel "Daftar Dosen Homebase".
    */
    'isian_sembunyi' => [
        'Tabel 3.A.3 Jumlah Dosen DTPR',
    ],

    /*
    | Isian di luar tabel: sheet Identitas (formulir "Identitas UPPS dan Program Studi")
    | dan baris "Jumlah Dosen DTPR" Tabel 3.A.3 (kini disembunyikan). Format: kunci => [Label, tipe, sheet, sel].
    */
    'isian' => [
        'Identitas Program Studi' => [
            'perguruan_tinggi'   => ['Perguruan Tinggi', 'text', 'Identitas', 'C6'],
            'upps'               => ['Unit Pengelola Program Studi', 'text', 'Identitas', 'C8'],
            'jenis_program'      => ['Jenis Program', 'text', 'Identitas', 'C10'],
            'nama_ps'            => ['Nama Program Studi', 'text', 'Identitas', 'C12'],
            'alamat'             => ['Alamat', 'text', 'Identitas', 'C14'],
            'telepon'            => ['Nomor Telepon', 'text', 'Identitas', 'C16'],
            'email_web'          => ['E-Mail dan Website', 'text', 'Identitas', 'C18'],
            'sk_pendirian_pt'    => ['Nomor SK Pendirian PT', 'text', 'Identitas', 'G6'],
            'tgl_sk_pendirian'   => ['Tanggal SK Pendirian PT', 'text', 'Identitas', 'G8'],
            'tahun_pertama'      => ['Tahun Pertama Menerima Mahasiswa', 'text', 'Identitas', 'G10'],
            'akreditasi_ps'      => ['Akreditasi PS', 'text', 'Identitas', 'G12'],
            'sk_akreditasi'      => ['Nomor SK BAN-PT/LAM', 'text', 'Identitas', 'G14'],
        ],
        'Tabel 3.A.3 Jumlah Dosen DTPR' => [
            'dtpr_ts2' => ['Jumlah Dosen DTPR TS-2', 'number', 'Tabel 3.A.3', 'C5'],
            'dtpr_ts1' => ['Jumlah Dosen DTPR TS-1', 'number', 'Tabel 3.A.3', 'D5'],
            'dtpr_ts'  => ['Jumlah Dosen DTPR TS', 'number', 'Tabel 3.A.3', 'E5'],
        ],
    ],

    'tabel' => [

        // ================= IDENTITAS: DAFTAR DOSEN HOMEBASE =================
        'dosen_homebase' => [
            'judul' => 'Daftar Dosen Homebase', 'kelompok' => 'k0', 'tersembunyi' => true,
            'kolom' => [
                'nama_dosen' => ['Nama Dosen', 'text', 'required'],
                'nidn'       => ['NIDN', 'text', 'nullable'],
                'nuptk'      => ['NUPTK', 'text', 'nullable'],
                'golongan'   => ['Golongan', 'text', 'nullable'],
                'jabatan_fungsional' => ['Jabatan Fungsional Akademik', 'select', 'nullable', ['-', 'Tenaga Pengajar', 'Asisten Ahli', 'Lektor', 'Lektor Kepala', 'Guru Besar']],
                'pend_s1'    => ['Pendidikan S1', 'text', 'nullable'],
                'pend_s2'    => ['Pendidikan S2', 'text', 'nullable'],
                'pend_s3'    => ['Pendidikan S3', 'text', 'nullable'],
                'keilmuan'   => ['Keilmuan', 'text', 'nullable'],
            ],
        ],

        // ======================= TABEL 1 =======================
        't1a1_pimpinan' => [
            'judul' => '1.A.1 Tabel Pimpinan dan Tupoksi UPPS dan PS', 'kelompok' => 'k1',
            'kolom' => [
                'unit_kerja'          => ['Unit Kerja', 'text', 'required'],
                'nama_ketua'          => ['Nama Ketua', 'text', 'required'],
                'periode_jabatan'     => ['Periode Jabatan', 'text', 'nullable'],
                'pendidikan_terakhir' => ['Pendidikan Terakhir', 'select', 'nullable', ['Diploma', 'Sarjana', 'Magister', 'Doktor', '-']],
                'jabatan_fungsional'  => ['Jabatan Fungsional', 'select', 'nullable', ['-', 'Tenaga Pengajar', 'Asisten Ahli', 'Lektor', 'Lektor Kepala', 'Guru Besar']],
                'tupoksi'             => ['Tugas Pokok dan Fungsi', 'url', 'nullable'],
            ],
        ],
        't1a2_sumber_dana' => [
            'judul' => '1.A.2 Sumber Pendanaan UPPS/PS', 'kelompok' => 'k1', 'ringkasan' => ['jumlah'],
            'keterangan' => 'Data ditulis dalam jutaan rupiah.',
            'kolom' => array_merge(
                ['sumber_pendanaan' => ['Sumber Pendanaan', 'text', 'required']],
                $perTs('', 'decimal'),
            ),
        ],
        't1a3_penggunaan_dana' => [
            'judul' => '1.A.3 Penggunaan Dana UPPS/PS', 'kelompok' => 'k1', 'ringkasan' => ['jumlah'],
            'keterangan' => 'Data ditulis dalam jutaan rupiah.',
            'kolom' => array_merge(
                ['penggunaan_dana' => ['Penggunaan Dana', 'text', 'required']],
                $perTs('', 'decimal'),
            ),
        ],
        't1a4_ewmp' => [
            'judul' => '1.A.4 Rata-rata Beban DTPR per semester (EWMP) pada TS', 'kelompok' => 'k1',
            'ringkasan' => ['jumlah', 'rata'],
            'kolom' => [
                'nama_dtpr'                => ['Nama DTPR', 'text', 'required'],
                'sks_ps_sendiri'           => ['SKS Pengajaran pada|PS Sendiri', 'decimal', 'nullable'],
                'sks_ps_lain'              => ['SKS Pengajaran pada|PS Lain, PT Sendiri', 'decimal', 'nullable'],
                'sks_pt_lain'              => ['SKS Pengajaran pada|PT Lain', 'decimal', 'nullable'],
                'sks_penelitian'           => ['SKS Penelitian', 'decimal', 'nullable'],
                'sks_pkm'                  => ['SKS Pengabdian kepada Masyarakat', 'decimal', 'nullable'],
                'sks_manajemen_pt_sendiri' => ['SKS Manajemen|PT Sendiri', 'decimal', 'nullable'],
                'sks_manajemen_pt_lain'    => ['SKS Manajemen|PT Lain', 'decimal', 'nullable'],
                'total_sks'                => ['Total SKS', 'decimal', 'nullable'],
            ],
            'total' => ['total_sks' => ['sks_ps_sendiri', 'sks_ps_lain', 'sks_pt_lain', 'sks_penelitian', 'sks_pkm', 'sks_manajemen_pt_sendiri', 'sks_manajemen_pt_lain']],
        ],
        't1a5_tendik' => [
            'judul' => '1.A.5 Kualifikasi Tenaga Kependidikan', 'kelompok' => 'k1', 'ringkasan' => ['jumlah'],
            'kolom' => array_merge(
                ['jenis' => ['Jenis Tenaga Kependidikan', 'select', 'required', ['Pustakawan', 'Laboran/Teknisi', 'Administrasi', 'Lainnya']]],
                (function () {
                    $k = [];
                    foreach (['s3' => 'S3', 's2' => 'S2', 's1' => 'S1', 'd4' => 'D4', 'd3' => 'D3', 'd2' => 'D2', 'd1' => 'D1', 'sma' => 'SMA/SMK/MA', 'smp' => 'SMP', 'sd' => 'SD'] as $n => $l) {
                        $k[$n] = ["Jumlah Tenaga Kependidikan dengan Pendidikan Terakhir|{$l}", 'number', 'nullable'];
                    }
                    return $k;
                })(),
                ['unit_kerja' => ['Unit Kerja', 'textarea', 'nullable']],
            ),
        ],
        't1b_spmi' => [
            'judul' => '1.B Tabel Unit SPMI dan SDM', 'kelompok' => 'k1',
            'kolom' => [
                'unit_spmi'             => ['Unit SPMI', 'select', 'required', ['Universitas/PT', 'UPPS', 'Program Studi']],
                'nama_unit'             => ['Nama Unit SPMI', 'text', 'required'],
                'dokumen_spmi'          => ['Dokumen SPMI', 'textarea', 'nullable'],
                'auditor_internal'      => ['Jumlah Auditor Mutu|Internal', 'number', 'nullable'],
                'auditor_certified'     => ['Jumlah Auditor Mutu|Certified', 'number', 'nullable'],
                'auditor_non_certified' => ['Jumlah Auditor Mutu|Non Certified', 'number', 'nullable'],
                'frekuensi_audit'       => ['Frekuensi Audit/Monev per Tahun', 'text', 'nullable'],
                'bukti_certified'       => ['Bukti Certified Auditor', 'url', 'nullable'],
                'laporan_audit'         => ['Laporan Audit', 'textarea', 'nullable'],
            ],
        ],

        // ======================= TABEL 2 =======================
        't2a1_data_mahasiswa' => [
            'judul' => '2.A.1 Data Mahasiswa', 'kelompok' => 'k2', 'ringkasan' => ['jumlah'],
            'kolom' => [
                'ts'                         => ['TS', 'select', 'required', $ts4],
                'daya_tampung'               => ['Daya Tampung', 'number', 'nullable'],
                'pendaftar'                  => ['Jumlah Calon Mahasiswa|Pendaftar', 'number', 'nullable'],
                'pendaftar_afirmasi'         => ['Jumlah Calon Mahasiswa|Pendaftar Afirmasi', 'number', 'nullable'],
                'pendaftar_kebutuhan_khusus' => ['Jumlah Calon Mahasiswa|Pendaftar Kebutuhan Khusus', 'number', 'nullable'],
                'baru_reguler'               => ['Jumlah Mahasiswa Baru|Reguler|Diterima', 'number', 'nullable'],
                'baru_reguler_afirmasi'      => ['Jumlah Mahasiswa Baru|Reguler|Afirmasi', 'number', 'nullable'],
                'baru_reguler_kk'            => ['Jumlah Mahasiswa Baru|Reguler|Kebutuhan Khusus', 'number', 'nullable'],
                'baru_rpl'                   => ['Jumlah Mahasiswa Baru|RPL|Diterima', 'number', 'nullable'],
                'baru_rpl_afirmasi'          => ['Jumlah Mahasiswa Baru|RPL|Afirmasi', 'number', 'nullable'],
                'baru_rpl_kk'                => ['Jumlah Mahasiswa Baru|RPL|Kebutuhan Khusus', 'number', 'nullable'],
                'aktif_reguler'              => ['Jumlah Mahasiswa Aktif|Reguler|Diterima', 'number', 'nullable'],
                'aktif_reguler_afirmasi'     => ['Jumlah Mahasiswa Aktif|Reguler|Afirmasi', 'number', 'nullable'],
                'aktif_reguler_kk'           => ['Jumlah Mahasiswa Aktif|Reguler|Kebutuhan Khusus', 'number', 'nullable'],
                'aktif_rpl'                  => ['Jumlah Mahasiswa Aktif|RPL|Diterima', 'number', 'nullable'],
                'aktif_rpl_afirmasi'         => ['Jumlah Mahasiswa Aktif|RPL|Afirmasi', 'number', 'nullable'],
                'aktif_rpl_kk'               => ['Jumlah Mahasiswa Aktif|RPL|Kebutuhan Khusus', 'number', 'nullable'],
            ],
        ],
        't2a2_asal_mahasiswa' => [
            'judul' => '2.A.2 Keragaman Asal Mahasiswa', 'kelompok' => 'k2', 'ringkasan' => ['jumlah'],
            'kolom' => array_merge([
                'kategori' => ['Asal Mahasiswa|Kategori', 'select', 'required', ['Kota/Kab sama dengan PS', 'Kota/Kabupaten Lain', 'Provinsi Lain', 'Negara Lain', 'Afirmasi', 'Berkebutuhan Khusus']],
                'asal'     => ['Asal Mahasiswa|Nama Daerah/Negara', 'text', 'nullable'],
            ], $perTs('Jumlah Mahasiswa Baru')),
        ],
        't2a3_kondisi_mahasiswa' => [
            'judul' => '2.A.3 Kondisi Jumlah Mahasiswa', 'kelompok' => 'k2',
            'kolom' => array_merge([
                'kondisi' => ['Kondisi', 'select', 'required', ['Mahasiswa Baru', 'Mahasiswa Aktif pada saat TS', 'Lulus pada saat TS', 'Mengundurkan Diri/DO pada saat TS']],
            ], $perTs(), [
                'jumlah'     => ['Jumlah', 'number', 'nullable'],
            ]),
            'total' => ['jumlah' => ['ts2', 'ts1', 'ts']],
        ],
        't2b1_isi_pembelajaran' => [
            'judul' => '2.B.1 Tabel Isi Pembelajaran', 'kelompok' => 'k2',
            'kolom' => array_merge([
                'kode_mk'  => ['Kode MK', 'text', 'required'],
                'nama_mk'  => ['Mata Kuliah', 'text', 'required'],
                'sks'      => ['SKS', 'number', 'required'],
                'semester' => ['Semester', 'select', 'required', ['I', 'II', 'III', 'IV', 'V', 'VI']],
            ], $pl),
        ],
        't2b2_cpl_pl' => [
            'judul' => '2.B.2 Pemetaan Capaian Pembelajaran Lulusan dan Profil Lulusan', 'kelompok' => 'k2',
            'kolom' => array_merge(['cpl' => ['CPL', 'text', 'required']], array_map(
                fn ($d) => [str_replace('Profil Lulusan (PL)|', '', $d[0]), $d[1], $d[2]], $pl
            )),
        ],
        't2b3_peta_cpl' => [
            'judul' => '2.B.3 Peta Pemenuhan CPL', 'kelompok' => 'k2',
            'kolom' => [
                'cpl'        => ['CPL', 'text', 'required'],
                'cpmk'       => ['CPMK', 'text', 'nullable'],
                'semester_1' => ['Semester 1', 'text', 'nullable'],
                'semester_2' => ['Semester 2', 'text', 'nullable'],
                'semester_3' => ['Semester 3', 'text', 'nullable'],
                'semester_4' => ['Semester 4', 'text', 'nullable'],
                'semester_5' => ['Semester 5', 'text', 'nullable'],
                'semester_6' => ['Semester 6', 'text', 'nullable'],
            ],
        ],
        't2b4_masa_tunggu' => [
            'judul' => '2.B.4 Rata-rata Masa Tunggu Lulusan untuk Bekerja Pertama Kali', 'kelompok' => 'k2',
            'ringkasan' => ['jumlah'],
            'kolom' => [
                'tahun_lulus'      => ['Tahun Lulus', 'select', 'required', $ts3],
                'jumlah_lulusan'   => ['Jumlah Lulusan', 'number', 'required'],
                'terlacak'         => ['Jumlah Lulusan yang Terlacak', 'number', 'required'],
                'rata_masa_tunggu' => ['Rata-rata Waktu Tunggu (Bulan)', 'decimal', 'nullable'],
            ],
        ],
        't2b5_bidang_kerja' => [
            'judul' => '2.B.5 Kesesuaian Bidang Kerja Lulusan', 'kelompok' => 'k2', 'ringkasan' => ['jumlah'],
            'kolom' => [
                'tahun_lulus'          => ['Tahun Lulus', 'select', 'required', $ts3],
                'jumlah_lulusan'       => ['Jumlah Lulusan', 'number', 'required'],
                'terlacak'             => ['Jumlah Lulusan yang Terlacak', 'number', 'required'],
                'profesi_infokom'      => ['Profesi Kerja Bidang Infokom', 'number', 'nullable'],
                'profesi_non_infokom'  => ['Profesi Kerja Bidang Non Infokom', 'number', 'nullable'],
                'tempat_multinasional' => ['Lingkup Tempat Kerja|Multinasional/Internasional', 'number', 'nullable'],
                'tempat_nasional'      => ['Lingkup Tempat Kerja|Nasional', 'number', 'nullable'],
                'tempat_wirausaha'     => ['Lingkup Tempat Kerja|Wirausaha', 'number', 'nullable'],
            ],
        ],
        't2b6_kepuasan_pengguna' => [
            'judul' => '2.B.6 Kepuasan Pengguna Lulusan', 'kelompok' => 'k2', 'ringkasan' => ['jumlah'],
            'kolom' => [
                'jenis_kemampuan' => ['Jenis Kemampuan', 'select', 'required', [
                    'Kerjasama Tim', 'Keahlian di Bidang Prodi', 'Kemampuan Berbahasa Asing (Inggris)',
                    'Kemampuan Berkomunikasi', 'Pengembangan Diri', 'Kepemimpinan', 'Etos Kerja',
                ]],
                'sangat_baik'   => ['Tingkat Kepuasan Pengguna (%)|Sangat Baik', 'decimal', 'nullable'],
                'baik'          => ['Tingkat Kepuasan Pengguna (%)|Baik', 'decimal', 'nullable'],
                'cukup'         => ['Tingkat Kepuasan Pengguna (%)|Cukup', 'decimal', 'nullable'],
                'kurang'        => ['Tingkat Kepuasan Pengguna (%)|Kurang', 'decimal', 'nullable'],
                'tindak_lanjut' => ['Rencana Tindak Lanjut oleh UPPS/PS', 'textarea', 'nullable'],
            ],
        ],
        't2c_fleksibilitas' => [
            'judul' => '2.C Fleksibilitas Dalam Proses Pembelajaran', 'kelompok' => 'k2',
            'kolom' => array_merge([
                'bentuk' => ['Bentuk Pembelajaran', 'select', 'required', [
                    'Jumlah Mahasiswa Aktif', 'Micro-credensial', 'RPL tipe A-2',
                    'Pembelajaran di PS lain', 'Pembelajaran di PT lain', 'CBL/PBL', 'Lainnya',
                ]],
                'keterangan' => ['Keterangan (jika Lainnya)', 'text', 'nullable'],
            ], $perTs('Jumlah Mahasiswa')),
        ],
        't2d_rekognisi_lulusan' => [
            'judul' => '2.D Rekognisi dan Apresiasi Kompetensi Lulusan', 'kelompok' => 'k2', 'ringkasan' => ['jumlah'],
            'kolom' => array_merge([
                'sumber_rekognisi' => ['Sumber Rekognisi', 'select', 'required', ['Masyarakat', 'Dunia Usaha', 'Dunia Industri', 'Dunia Kerja', 'Lainnya']],
                'jenis_pengakuan'  => ['Jenis Pengakuan Lulusan (Rekognisi)', 'text', 'required'],
            ], $perTs('Tahun Akademik')),
        ],

        // ======================= TABEL 3 =======================
        't3a1_sarpras_penelitian' => [
            'judul' => '3.A.1 Sarana dan Prasarana Penelitian', 'kelompok' => 'k3',
            'kolom' => $sarpras,
        ],
        't3a2_penelitian_dtpr' => [
            'judul' => '3.A.2 Penelitian DTPR, Hibah dan Pembiayaan Penelitian', 'kelompok' => 'k3', 'ringkasan' => ['jumlah'],
            'kolom' => $hibah('Nama DTPR (Ketua)', 'Judul Penelitian', 'Jenis Hibah Penelitian'),
        ],
        't3a3_pengembangan_dtpr' => [
            'judul' => '3.A.3 Pengembangan DTPR di Bidang Penelitian', 'kelompok' => 'k3', 'ringkasan' => ['jumlah'],
            'kolom' => array_merge([
                'jenis_pengembangan' => ['Jenis Pengembangan DTPR', 'text', 'required'],
                'nama_dtpr'          => ['Nama DTPR', 'text', 'required'],
            ], $perTs('Tahun Akademik (√)', 'check')),
        ],
        't3c1_kerjasama_penelitian' => [
            'judul' => '3.C.1 Kerjasama Penelitian', 'kelompok' => 'k3', 'ringkasan' => ['jumlah'],
            'kolom' => $kerjasama,
        ],
        't3c2_publikasi' => [
            'judul' => '3.C.2 Publikasi Penelitian', 'kelompok' => 'k3', 'ringkasan' => ['jumlah'],
            'kolom' => array_merge([
                'nama_dtpr'       => ['Nama DTPR', 'text', 'required'],
                'judul_publikasi' => ['Judul Publikasi', 'text', 'required'],
                'jenis_publikasi' => ['Jenis Publikasi (IB/I/S1–S6/T)', 'select', 'required', ['IB', 'I', 'S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'T']],
            ], $perTs('Tahun Terbit (√)', 'check')),
        ],
        't3c3_hki_penelitian' => [
            'judul' => '3.C.3 Perolehan HKI (Granted)', 'kelompok' => 'k3', 'ringkasan' => ['jumlah'],
            'kolom' => $hki,
        ],

        // ======================= TABEL 4 =======================
        't4a1_sarpras_pkm' => [
            'judul' => '4.A.1 Sarana dan Prasarana PkM', 'kelompok' => 'k4',
            'kolom' => $sarpras,
        ],
        't4a2_pkm_dtpr' => [
            'judul' => '4.A.2 PkM DTPR, Hibah dan Pembiayaan PkM', 'kelompok' => 'k4', 'ringkasan' => ['jumlah'],
            'kolom' => $hibah('Nama DTPR (Sebagai Ketua PkM)', 'Judul PkM', 'Jenis Hibah PkM'),
        ],
        't4c1_kerjasama_pkm' => [
            'judul' => '4.C.1 Kerjasama PkM', 'kelompok' => 'k4', 'ringkasan' => ['jumlah'],
            'kolom' => $kerjasama,
        ],
        't4c2_diseminasi_pkm' => [
            'judul' => '4.C.2 Diseminasi Hasil PkM', 'kelompok' => 'k4', 'ringkasan' => ['jumlah'],
            'kolom' => array_merge([
                'nama_dtpr'  => ['Nama DTPR', 'text', 'required'],
                'judul'      => ['Judul', 'text', 'required'],
                'diseminasi' => ['Diseminasi Hasil PkM (L/N/I)', 'select', 'required', $lni],
            ], $perTs('Tahun (√)', 'check')),
        ],
        't4c3_hki_pkm' => [
            'judul' => '4.C.3 Perolehan HKI PkM', 'kelompok' => 'k4', 'ringkasan' => ['jumlah'],
            'kolom' => $hki,
        ],

        // ======================= TABEL 5 =======================
        't5_1_tata_kelola' => [
            'judul' => '5.1 Sistem Tata Kelola', 'kelompok' => 'k5',
            'kolom' => [
                'jenis_tata_kelola' => ['Jenis Tata Kelola', 'text', 'required'],
                'nama_sistem'       => ['Nama Sistem Informasi', 'text', 'required'],
                'akses'             => ['Akses (Lokal/Internet)', 'select', 'nullable', ['Lokal', 'Internet']],
                'unit_pengelola'    => ['Unit Kerja/SDM Pengelola', 'text', 'nullable'],
            ],
        ],
        't5_2_sarpras_pendidikan' => [
            'judul' => '5.2 Sarana dan Prasarana Pendidikan', 'kelompok' => 'k5',
            'kolom' => $sarpras,
        ],

        // ======================= TABEL 6 =======================
        't6_visi_misi' => [
            'judul' => '6 Kesesuaian Visi, Misi', 'kelompok' => 'k6',
            'kolom' => [
                'visi_pt'       => ['Visi PT', 'textarea', 'required'],
                'visi_upps'     => ['Visi UPPS', 'textarea', 'required'],
                'visi_keilmuan' => ['Visi Keilmuan PS', 'textarea', 'required'],
                'misi_pt'       => ['Misi PT', 'textarea', 'nullable'],
                'misi_upps'     => ['Misi UPPS', 'textarea', 'nullable'],
            ],
        ],
    ],
];
EOF

tulis config/lkps_excel.php <<'EOF'
<?php
/*
|--------------------------------------------------------------------------
| Pemetaan tabel LKPS ke template Excel LAM Infokom (Data_DKPS ... .xlsx)
|--------------------------------------------------------------------------
| sheet   : nama sheet di template
| mulai   : baris data pertama
| kolom   : nama_kolom_database => huruf kolom Excel
| no      : kolom nomor urut (opsional)
| kunci   : baris tetap yang dicocokkan berdasarkan label (mis. TS-2, TS-1, TS)
| tetap   : baris khusus untuk satu nilai tertentu (2.C Jumlah Mahasiswa Aktif)
| lainnya : nilai di luar pilihan disimpan sebagai "Lainnya" + keterangan
| mode    : 'asal' (2.A.2, dikelompokkan per kategori) atau 'sel' (Tabel 6)
| lampiran_bukti dipetakan ke kolom "Link Bukti" di template: saat ekspor berisi
| link pratinjau lampiran; saat impor kolom ini dilewati (berkas tidak bisa diimpor).
*/

$sarpras = ['mulai' => 5, 'kolom' => [
    'nama_prasarana' => 'A', 'daya_tampung' => 'B', 'luas_ruang' => 'C', 'kepemilikan' => 'D',
    'lisensi' => 'E', 'perangkat' => 'F', 'lampiran_bukti' => 'H',
]];
$hibah = ['mulai' => 6, 'no' => 'A', 'kolom' => [
    'nama_dtpr' => 'B', 'judul' => 'C', 'jumlah_mahasiswa' => 'D', 'jenis_hibah' => 'E', 'sumber' => 'F',
    'durasi' => 'G', 'dana_ts2' => 'H', 'dana_ts1' => 'I', 'dana_ts' => 'J', 'lampiran_bukti' => 'K',
]];
$kerjasama = ['mulai' => 6, 'no' => 'A', 'kolom' => [
    'judul_kerjasama' => 'B', 'mitra' => 'C', 'sumber' => 'D', 'durasi' => 'E',
    'dana_ts2' => 'F', 'dana_ts1' => 'G', 'dana_ts' => 'H', 'lampiran_bukti' => 'I',
]];
$hki = ['mulai' => 6, 'no' => 'A', 'kolom' => [
    'judul' => 'B', 'jenis_hki' => 'C', 'nama_dtpr' => 'D', 'ts2' => 'E', 'ts1' => 'F', 'ts' => 'G', 'lampiran_bukti' => 'H',
]];

return [
    't1a1_pimpinan' => ['sheet' => 'Tabel 1.A.1', 'mulai' => 6, 'kolom' => [
        'unit_kerja' => 'A', 'nama_ketua' => 'B', 'periode_jabatan' => 'C',
        'pendidikan_terakhir' => 'D', 'jabatan_fungsional' => 'E', 'tupoksi' => 'F',
    ]],
    't1a2_sumber_dana' => ['sheet' => 'Tabel 1.A.2', 'mulai' => 5, 'kolom' => [
        'sumber_pendanaan' => 'A', 'ts2' => 'B', 'ts1' => 'C', 'ts' => 'D', 'lampiran_bukti' => 'E',
    ]],
    't1a3_penggunaan_dana' => ['sheet' => 'Tabel 1.A.3', 'mulai' => 5, 'kolom' => [
        'penggunaan_dana' => 'A', 'ts2' => 'B', 'ts1' => 'C', 'ts' => 'D', 'lampiran_bukti' => 'E',
    ]],
    't1a4_ewmp' => ['sheet' => 'Tabel 1.A.4', 'mulai' => 8, 'no' => 'A', 'kolom' => [
        'nama_dtpr' => 'B', 'sks_ps_sendiri' => 'C', 'sks_ps_lain' => 'D', 'sks_pt_lain' => 'E',
        'sks_penelitian' => 'F', 'sks_pkm' => 'G', 'sks_manajemen_pt_sendiri' => 'H',
        'sks_manajemen_pt_lain' => 'I', 'total_sks' => 'J',
    ]],
    't1a5_tendik' => ['sheet' => 'Tabel 1.A.5', 'mulai' => 7,
        'kunci' => ['field' => 'jenis', 'kolom' => 'B'],
        'kolom' => [
            's3' => 'C', 's2' => 'D', 's1' => 'E', 'd4' => 'F', 'd3' => 'G', 'd2' => 'H', 'd1' => 'I',
            'sma' => 'J', 'smp' => 'K', 'sd' => 'L', 'unit_kerja' => 'M',
        ]],
    't1b_spmi' => ['sheet' => 'Tabel 1.B', 'mulai' => 6, 'kolom' => [
        'unit_spmi' => 'A', 'nama_unit' => 'B', 'dokumen_spmi' => 'C', 'auditor_internal' => 'D',
        'auditor_certified' => 'E', 'auditor_non_certified' => 'F', 'frekuensi_audit' => 'G',
        'bukti_certified' => 'H', 'laporan_audit' => 'I',
    ]],
    't2a1_data_mahasiswa' => ['sheet' => 'Tabel 2.A.1', 'mulai' => 7,
        'kunci' => ['field' => 'ts', 'kolom' => 'A'],
        'kolom' => [
            'daya_tampung' => 'B', 'pendaftar' => 'C', 'pendaftar_afirmasi' => 'D', 'pendaftar_kebutuhan_khusus' => 'E',
            'baru_reguler' => 'F', 'baru_reguler_afirmasi' => 'G', 'baru_reguler_kk' => 'H',
            'baru_rpl' => 'I', 'baru_rpl_afirmasi' => 'J', 'baru_rpl_kk' => 'K',
            'aktif_reguler' => 'L', 'aktif_reguler_afirmasi' => 'M', 'aktif_reguler_kk' => 'N',
            'aktif_rpl' => 'O', 'aktif_rpl_afirmasi' => 'P', 'aktif_rpl_kk' => 'Q',
        ]],
    't2a2_asal_mahasiswa' => ['sheet' => 'Tabel 2.A.2', 'mulai' => 6, 'mode' => 'asal',
        'kolom' => ['ts2' => 'B', 'ts1' => 'C', 'ts' => 'D', 'lampiran_bukti' => 'E']],
    't2a3_kondisi_mahasiswa' => ['sheet' => 'Tabel 2.A.3', 'mulai' => 5,
        'kunci' => ['field' => 'kondisi', 'kolom' => 'A'],
        'kolom' => ['ts2' => 'B', 'ts1' => 'C', 'ts' => 'D', 'jumlah' => 'E', 'lampiran_bukti' => 'F'],
    ],
    't2b1_isi_pembelajaran' => ['sheet' => 'Tabel 2.B.1', 'mulai' => 6, 'kolom' => [
        'kode_mk' => 'A', 'nama_mk' => 'B', 'sks' => 'C', 'semester' => 'D',
        'pl1' => 'E', 'pl2' => 'F', 'pl3' => 'G', 'pl4' => 'H', 'pl5' => 'I',
    ]],
    't2b2_cpl_pl' => ['sheet' => 'Tabel 2.B.2', 'mulai' => 5, 'kolom' => [
        'cpl' => 'A', 'pl1' => 'B', 'pl2' => 'C', 'pl3' => 'D', 'pl4' => 'E', 'pl5' => 'F',
    ]],
    't2b3_peta_cpl' => ['sheet' => 'Tabel 2.B.3', 'mulai' => 5, 'kolom' => [
        'cpl' => 'A', 'cpmk' => 'B', 'semester_1' => 'C', 'semester_2' => 'D', 'semester_3' => 'E',
        'semester_4' => 'F', 'semester_5' => 'G', 'semester_6' => 'H',
    ]],
    't2b4_masa_tunggu' => ['sheet' => 'Tabel 2.B.4', 'mulai' => 5,
        'kunci' => ['field' => 'tahun_lulus', 'kolom' => 'A'],
        'kolom' => ['jumlah_lulusan' => 'B', 'terlacak' => 'C', 'rata_masa_tunggu' => 'D']],
    't2b5_bidang_kerja' => ['sheet' => 'Tabel 2.B.5', 'mulai' => 6,
        'kunci' => ['field' => 'tahun_lulus', 'kolom' => 'A'],
        'kolom' => [
            'jumlah_lulusan' => 'B', 'terlacak' => 'C', 'profesi_infokom' => 'D', 'profesi_non_infokom' => 'E',
            'tempat_multinasional' => 'F', 'tempat_nasional' => 'G', 'tempat_wirausaha' => 'H',
        ]],
    't2b6_kepuasan_pengguna' => ['sheet' => 'Tabel 2.B.6', 'mulai' => 6,
        'kunci' => ['field' => 'jenis_kemampuan', 'kolom' => 'B'],
        'kolom' => ['sangat_baik' => 'C', 'baik' => 'D', 'cukup' => 'E', 'kurang' => 'F', 'tindak_lanjut' => 'G']],
    't2c_fleksibilitas' => ['sheet' => 'Tabel 2.C', 'mulai' => 7,
        'kolom' => ['bentuk' => 'A', 'ts2' => 'B', 'ts1' => 'C', 'ts' => 'D', 'lampiran_bukti' => 'E'],
        'tetap' => ['field' => 'bentuk', 'nilai' => 'Jumlah Mahasiswa Aktif', 'baris' => 5],
        'lainnya' => ['field' => 'bentuk', 'keterangan' => 'keterangan'],
    ],
    't2d_rekognisi_lulusan' => ['sheet' => 'Tabel 2.D', 'mulai' => 6, 'kolom' => [
        'sumber_rekognisi' => 'A', 'jenis_pengakuan' => 'B', 'ts2' => 'C', 'ts1' => 'D', 'ts' => 'E', 'lampiran_bukti' => 'F',
    ]],
    't3a1_sarpras_penelitian' => ['sheet' => 'Tabel 3.A.1'] + $sarpras,
    't3a2_penelitian_dtpr' => ['sheet' => 'Tabel 3.A.2'] + $hibah,
    't3a3_pengembangan_dtpr' => ['sheet' => 'Tabel 3.A.3', 'mulai' => 7,
        'kolom' => ['jenis_pengembangan' => 'A', 'nama_dtpr' => 'B', 'ts2' => 'C', 'ts1' => 'D', 'ts' => 'E', 'lampiran_bukti' => 'F'],
    ],
    't3c1_kerjasama_penelitian' => ['sheet' => 'Tabel 3.C.1'] + $kerjasama,
    't3c2_publikasi' => ['sheet' => 'Tabel 3.C.2', 'mulai' => 6, 'no' => 'A',
        'kolom' => [
            'nama_dtpr' => 'B', 'judul_publikasi' => 'C', 'jenis_publikasi' => 'D',
            'ts2' => 'E', 'ts1' => 'F', 'ts' => 'G', 'lampiran_bukti' => 'H',
        ],
    ],
    't3c3_hki_penelitian' => ['sheet' => 'Tabel 3.C.3'] + $hki,
    't4a1_sarpras_pkm' => ['sheet' => 'Tabel 4.A.1'] + $sarpras,
    't4a2_pkm_dtpr' => ['sheet' => 'Tabel 4.A.2'] + $hibah,
    't4c1_kerjasama_pkm' => ['sheet' => 'Tabel 4.C.1'] + $kerjasama,
    't4c2_diseminasi_pkm' => ['sheet' => 'Tabel 4.C.2', 'mulai' => 5, 'no' => 'A',
        'kolom' => [
            'nama_dtpr' => 'B', 'judul' => 'D', 'diseminasi' => 'E',
            'ts2' => 'F', 'ts1' => 'G', 'ts' => 'H', 'lampiran_bukti' => 'I',
        ],
    ],
    't4c3_hki_pkm' => ['sheet' => 'Tabel 4.C.3'] + $hki,
    't5_1_tata_kelola' => ['sheet' => 'Tabel 5.1', 'mulai' => 5, 'no' => 'A', 'kolom' => [
        'jenis_tata_kelola' => 'B', 'nama_sistem' => 'C', 'akses' => 'D', 'unit_pengelola' => 'E', 'lampiran_bukti' => 'F',
    ]],
    't5_2_sarpras_pendidikan' => ['sheet' => 'Tabel 5.2'] + $sarpras,
    't6_visi_misi' => ['sheet' => 'Tabel 6', 'mode' => 'sel', 'sel' => [
        'visi_pt' => 'A5', 'visi_upps' => 'B5', 'visi_keilmuan' => 'C5', 'misi_pt' => 'A7', 'misi_upps' => 'B7',
    ]],
];
EOF

tulis app/Support/Lkps.php <<'EOF'
<?php

namespace App\Support;

use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\Rule;

class Lkps
{
    /** Disk privat untuk lampiran bukti (storage/app/private); diakses lewat route pratinjau. */
    public const DISK = 'local';

    /** Kolom lampiran yang otomatis ada di setiap tabel LKPS. */
    public const LAMPIRAN = 'lampiran_bukti';

    /** Batas ukuran unggahan lampiran (KB): 20 MB. */
    public const MAKS_LAMPIRAN_KB = 20480;

    /** Batas unggah efektif dari php.ini (MB), untuk peringatan di form. */
    public static function batasServerMb(): float
    {
        $mb = function (string $v): float {
            $v = trim($v);
            $n = (float) $v;
            return match (strtolower(substr($v, -1))) {
                'g' => $n * 1024, 'k' => $n / 1024, 'm' => $n, default => $n / 1048576,
            };
        };

        return min($mb((string) ini_get('upload_max_filesize')), $mb((string) ini_get('post_max_size')));
    }

    public static function tabel(): array
    {
        return config('lkps.tabel', []);
    }

    public static function definisi(string $slug): array
    {
        $def = self::tabel()[$slug] ?? null;
        abort_if($def === null, 404, 'Tabel LKPS tidak ditemukan.');

        return $def;
    }

    public static function namaTabel(string $slug): string
    {
        return 'lkps_' . $slug;
    }

    /** Kolom yang sudah dinormalisasi: label, type, rules, options. */
    public static function kolom(string $slug): array
    {
        $hasil = [];
        foreach (self::definisi($slug)['kolom'] as $nama => $d) {
            $jalur = array_map('trim', explode('|', $d[0]));
            $hasil[$nama] = [
                'label'   => implode(' – ', $jalur),
                'jalur'   => $jalur,
                'type'    => $d[1] ?? 'text',
                'rules'   => $d[2] ?? 'nullable',
                'options' => $d[3] ?? [],
            ];
        }

        // Setiap baris data punya Lampiran Bukti (PDF/gambar) yang dibuka sebagai pratinjau.
        $hasil[self::LAMPIRAN] ??= [
            'label'   => 'Lampiran Bukti',
            'jalur'   => ['Lampiran Bukti'],
            'type'    => 'file',
            'rules'   => 'nullable',
            'options' => [],
        ];

        // Lampiran Bukti berupa link (opsional; boleh bersama berkas atau sebagai pengganti berkas).
        $hasil['lampiran_link'] ??= [
            'label'   => 'Lampiran Bukti (Link)',
            'jalur'   => ['Lampiran Bukti (Link)'],
            'type'    => 'url',
            'rules'   => 'nullable|url|max:500',
            'options' => [],
        ];

        return $hasil;
    }

    /** Link pratinjau lampiran (bukan link unduh). */
    public static function urlLampiran(string $slug, int $id, string $kolom = self::LAMPIRAN): string
    {
        return route('lkps.lampiran.lihat', [$slug, $id, $kolom]);
    }

    public static function namaKelompok(string $slug): string
    {
        $kode = self::definisi($slug)['kelompok'] ?? '';

        return config("lkps.kelompok.$kode", $kode);
    }

    public static function rules(string $slug, bool $ubah = false): array
    {
        $hasil = [];
        foreach (self::kolom($slug) as $nama => $k) {
            $r = array_values(array_filter(explode('|', $k['rules'])));

            // Saat mengubah data, berkas lama tetap dipakai jika tidak diganti.
            if ($k['type'] === 'file' && $ubah) {
                $r = array_map(fn ($x) => $x === 'required' ? 'nullable' : $x, $r);
            }
            if (! in_array('required', $r, true) && ! in_array('nullable', $r, true)) {
                $r[] = 'nullable';
            }

            $tambahan = match ($k['type']) {
                'number'   => ['integer', 'min:0'],
                'decimal'  => ['numeric'],
                'date'     => ['date'],
                'url'      => ['string', 'max:500'],
                'check'    => ['boolean'],
                'file'     => ['file', 'max:' . self::MAKS_LAMPIRAN_KB, 'mimes:pdf,jpg,jpeg,png,webp'],
                'textarea' => ['string'],
                'select'   => [],
                default    => ['string', 'max:255'],
            };
            foreach ($tambahan as $t) {
                $kunci = explode(':', $t)[0];
                $ada = collect($r)->contains(fn ($x) => is_string($x) && explode(':', $x)[0] === $kunci);
                if (! $ada) {
                    $r[] = $t;
                }
            }
            if ($k['type'] === 'select' && $k['options']) {
                $r[] = Rule::in($k['options']);
            }

            $hasil[$nama] = $r;
        }

        return $hasil;
    }

    public static function label(string $slug): array
    {
        return array_map(fn ($k) => $k['label'], self::kolom($slug));
    }

    /**
     * Header tabel bertingkat seperti di Excel, dari label "Grup|Sub|Kolom".
     * Mengembalikan ['depth' => n, 'baris' => [[['label','colspan','rowspan'], ...], ...]].
     */
    public static function header(string $slug): array
    {
        $jalur = array_values(array_map(fn ($k) => $k['jalur'], self::kolom($slug)));
        $n = count($jalur);
        $depth = $n ? max(array_map('count', $jalur)) : 1;
        $baris = [];

        for ($l = 0; $l < $depth; $l++) {
            $row = [];
            $i = 0;
            while ($i < $n) {
                $p = $jalur[$i];
                if (count($p) <= $l) {
                    $i++;
                    continue;
                }
                if ($l === count($p) - 1) {
                    $row[] = ['label' => $p[$l], 'colspan' => 1, 'rowspan' => $depth - $l];
                    $i++;
                    continue;
                }
                $j = $i + 1;
                while ($j < $n && count($jalur[$j]) > $l + 1
                    && array_slice($jalur[$j], 0, $l + 1) === array_slice($p, 0, $l + 1)) {
                    $j++;
                }
                $row[] = ['label' => $p[$l], 'colspan' => $j - $i, 'rowspan' => 1];
                $i = $j;
            }
            $baris[] = $row;
        }

        return ['depth' => $depth, 'baris' => $baris];
    }

    /** Baris Jumlah / Rata-rata di bawah tabel, sesuai 'ringkasan' di config. */
    public static function ringkasan(string $slug, iterable $rows): array
    {
        $jenis = self::definisi($slug)['ringkasan'] ?? [];
        if (! $jenis) {
            return [];
        }
        $kolom = self::kolom($slug);
        $jumlah = [];
        $isi = [];
        foreach ($kolom as $n => $k) {
            if (in_array($k['type'], ['number', 'decimal', 'check'], true)) {
                $jumlah[$n] = 0;
                $isi[$n] = 0;
            }
        }
        foreach ($rows as $r) {
            foreach (array_keys($jumlah) as $n) {
                $v = $r->$n ?? null;
                if ($kolom[$n]['type'] === 'check') {
                    $jumlah[$n] += $v ? 1 : 0;
                } elseif ($v !== null && $v !== '') {
                    $jumlah[$n] += (float) $v;
                    $isi[$n]++;
                }
            }
        }

        $hasil = [];
        if (in_array('jumlah', $jenis, true)) {
            $hasil['Jumlah'] = $jumlah;
        }
        if (in_array('rata', $jenis, true)) {
            $rata = [];
            foreach ($jumlah as $n => $v) {
                $rata[$n] = $kolom[$n]['type'] !== 'check' && $isi[$n] ? $v / $isi[$n] : null;
            }
            $hasil['Rata-rata'] = $rata;
        }

        return $hasil;
    }

    /** Format angka gaya Indonesia, maksimal 2 desimal. */
    public static function angka(mixed $v): string
    {
        if ($v === null || $v === '' || ! is_numeric($v)) {
            return (string) $v;
        }
        $s = number_format((float) $v, 2, ',', '.');

        return str_ends_with($s, ',00') ? substr($s, 0, -3) : rtrim($s, '0');
    }

    /** Menu sidebar & dashboard: tabel dikelompokkan per kriteria. */
    public static function perKelompok(): array
    {
        $grup = [];
        foreach (config('lkps.kelompok', []) as $kode => $nama) {
            $grup[$kode] = ['nama' => $nama, 'tabel' => []];
        }
        foreach (self::tabel() as $slug => $def) {
            if (! empty($def['tersembunyi'])) {
                continue;   // tidak ditampilkan sebagai tabel LKPS (mis. Daftar Dosen Homebase di halaman Identitas)
            }
            $kode = $def['kelompok'] ?? 'lainnya';
            $grup[$kode] ??= ['nama' => ucfirst($kode), 'tabel' => []];
            $grup[$kode]['tabel'][$slug] = $def['judul'];
        }

        return array_filter($grup, fn ($g) => ! empty($g['tabel']));
    }

    /** Buat tabel/kolom yang belum ada. Tidak pernah menghapus data. */
    public static function sinkron(): array
    {
        $log = [];
        foreach (self::tabel() as $slug => $def) {
            $nama = self::namaTabel($slug);
            $kolom = self::kolom($slug);

            if (! Schema::hasTable($nama)) {
                Schema::create($nama, function (Blueprint $t) use ($kolom) {
                    $t->id();
                    foreach ($kolom as $n => $k) {
                        self::buatKolom($t, $n, $k['type']);
                    }
                    $t->unsignedBigInteger('created_by')->nullable();
                    $t->timestamps();
                });
                $log[] = "Tabel {$nama} dibuat.";
                continue;
            }

            foreach ($kolom as $n => $k) {
                if (! Schema::hasColumn($nama, $n)) {
                    Schema::table($nama, fn (Blueprint $t) => self::buatKolom($t, $n, $k['type']));
                    $log[] = "Kolom {$nama}.{$n} ditambahkan.";
                }
            }
        }

        if (! Schema::hasTable('lkps_isian')) {
            Schema::create('lkps_isian', function (Blueprint $t) {
                $t->id();
                $t->string('kunci')->unique();
                $t->text('nilai')->nullable();
                $t->timestamps();
            });
            $log[] = 'Tabel lkps_isian dibuat.';
        }

        return $log ?: ['Semua tabel LKPS sudah sesuai konfigurasi.'];
    }

    private static function buatKolom(Blueprint $t, string $nama, string $type): void
    {
        $kolom = match ($type) {
            'textarea'    => $t->text($nama),
            'number'      => $t->integer($nama),
            'decimal'     => $t->decimal($nama, 15, 2),
            'check'       => $t->boolean($nama)->default(false),
            'date'        => $t->date($nama),
            'file', 'url' => $t->string($nama, 500),
            default       => $t->string($nama),
        };
        $kolom->nullable();
    }
}
EOF

tulis app/Support/LkpsExcel.php <<'EOF'
<?php

namespace App\Support;

use PhpOffice\PhpSpreadsheet\Cell\DataType;
use PhpOffice\PhpSpreadsheet\IOFactory;
use PhpOffice\PhpSpreadsheet\RichText\RichText;
use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Worksheet\Worksheet;

/**
 * Membaca dan menulis 31 tabel LKPS dari/ke template Excel LAM Infokom.
 * Kelas ini tidak menyentuh database: masukan dan keluarannya berupa array
 * [slug_tabel => [ [kolom => nilai], ... ]].
 */
class LkpsExcel
{
    public array $catatan = [];

    /** Isian di luar tabel (sheet Identitas, Jumlah Dosen DTPR) hasil impor terakhir. */
    public array $isian = [];

    private const CENTANG = '√';
    private const PLACEHOLDER = ['link bukti', 'bukti link', 'linik bukti', '…', '...', '-'];
    private const POLA_FOOTER = '/^(jumlah|keterangan|total|rata-rata|persentase|l\s*:\s*lokal|\*)/iu';

    /**
     * @param array $tabel  config('lkps.tabel')
     * @param array $peta   config('lkps_excel')
     * @param array $isian  config('lkps.isian') : [grup => [kunci => [label, tipe, sheet, sel]]]
     */
    public function __construct(private array $tabel, private array $peta, private array $defIsian = [])
    {
    }

    private function semuaIsian(): array
    {
        $hasil = [];
        foreach ($this->defIsian as $daftar) {
            $hasil += $daftar;
        }

        return $hasil;
    }

    // =====================================================================
    // EKSPOR
    // =====================================================================

    public function ekspor(string $template, array $data, array $isian = []): Spreadsheet
    {
        $book = IOFactory::load($template);

        foreach ($this->semuaIsian() as $kunci => [$label, $tipe, $sheet, $sel]) {
            if ($ws = $book->getSheetByName($sheet)) {
                $this->setSel($ws, $sel, $isian[$kunci] ?? null, $tipe);
            }
        }

        foreach ($this->peta as $slug => $p) {
            $ws = $book->getSheetByName($p['sheet']);
            if (! $ws) {
                $this->catatan[] = "Sheet \"{$p['sheet']}\" tidak ada di template, dilewati.";
                continue;
            }
            $rows = array_values($data[$slug] ?? []);

            match ($this->mode($p)) {
                'sel'   => $this->tulisSel($ws, $slug, $p, $rows),
                'kunci' => $this->tulisKunci($ws, $slug, $p, $rows),
                'asal'  => $this->tulisAsal($ws, $slug, $p, $rows),
                default => $this->tulisDaftar($ws, $slug, $p, $rows),
            };
        }

        $book->setActiveSheetIndex(0);

        return $book;
    }

    private function tulisDaftar(Worksheet $ws, string $slug, array $p, array $rows): void
    {
        $kolom = $this->kolom($slug);

        if (isset($p['tetap'])) {
            $t = $p['tetap'];
            foreach ($rows as $i => $r) {
                if (($r[$t['field']] ?? null) === $t['nilai']) {
                    $this->tulisBaris($ws, $t['baris'], $p, $kolom, $r, null, $t['field']);
                    unset($rows[$i]);
                }
            }
            $rows = array_values($rows);
        }

        $lines = array_map(fn ($r) => [null, $r], $rows);
        $this->tulisBlok($ws, $p, $kolom, $lines);
    }

    /** 2.A.2: baris dikelompokkan per kategori asal mahasiswa. */
    private function tulisAsal(Worksheet $ws, string $slug, array $p, array $rows): void
    {
        $kolom = $this->kolom($slug);
        $lines = [];
        foreach ($kolom['kategori']['options'] as $kat) {
            $grup = array_values(array_filter($rows, fn ($r) => ($r['kategori'] ?? '') === $kat));
            $utama = null;
            $anak = [];
            foreach ($grup as $g) {
                if ($utama === null && trim((string) ($g['asal'] ?? '')) === '') {
                    $utama = $g;
                } else {
                    $anak[] = $g;
                }
            }
            $lines[] = [$kat, $utama];
            foreach ($anak as $a) {
                $lines[] = [($a['asal'] ?? '') !== '' ? $a['asal'] : $kat, $a];
            }
        }
        $this->tulisBlok($ws, $p, $kolom, $lines, 'A');
    }

    /** Menulis sekumpulan baris mulai dari $p['mulai'], menyisipkan baris bila perlu. */
    private function tulisBlok(Worksheet $ws, array $p, array $kolom, array $lines, ?string $kolomLabel = null): void
    {
        $mulai = $p['mulai'];
        $n = count($lines);
        $footer = $this->footer($ws, $mulai);

        if ($footer !== null && $n > $footer - $mulai) {
            $sisip = $n - ($footer - $mulai);
            // Sisipkan di atas baris data terakhir agar rumus SUM/AVERAGE ikut melebar.
            $posisi = $footer - 1 > $mulai ? $footer - 1 : $footer;
            $ws->insertNewRowBefore($posisi, $sisip);
            $footer += $sisip;
        }

        $akhir = $footer !== null
            ? $footer - 1
            : max($mulai + $n - 1, $this->barisTerakhirTerisi($ws, $p, $mulai, $kolomLabel));
        $this->kosongkan($ws, $p, $mulai, $akhir, $kolomLabel);

        foreach ($lines as $i => [$label, $r]) {
            $baris = $mulai + $i;
            if ($kolomLabel !== null) {
                $ws->getCell($kolomLabel . $baris)->setValueExplicit((string) $label, DataType::TYPE_STRING);
            }
            if ($r !== null) {
                $this->tulisBaris($ws, $baris, $p, $kolom, $r, $i + 1);
            }
        }
    }

    private function tulisKunci(Worksheet $ws, string $slug, array $p, array $rows): void
    {
        $kolom = $this->kolom($slug);
        $peta = $this->petaLabel($ws, $p);

        foreach ($rows as $r) {
            $label = (string) ($r[$p['kunci']['field']] ?? '');
            $baris = $this->cariLabel($peta, $label);
            if ($baris === null) {
                $this->catatan[] = "{$p['sheet']}: baris \"{$label}\" tidak ada di template, dilewati.";
                continue;
            }
            $this->tulisBaris($ws, $baris, $p, $kolom, $r, null);
        }
    }

    private function tulisSel(Worksheet $ws, string $slug, array $p, array $rows): void
    {
        $kolom = $this->kolom($slug);
        $r = $rows[0] ?? [];
        if (count($rows) > 1) {
            $this->catatan[] = "{$p['sheet']}: hanya baris pertama yang diekspor.";
        }
        foreach ($p['sel'] as $field => $ref) {
            $this->setSel($ws, $ref, $r[$field] ?? null, $kolom[$field]['type'] ?? 'text');
        }
    }

    private function tulisBaris(Worksheet $ws, int $baris, array $p, array $kolom, array $r, ?int $no, ?string $lewati = null): void
    {
        if ($no !== null && isset($p['no'])) {
            $ws->getCell($p['no'] . $baris)->setValue($no);
        }

        foreach ($p['kolom'] as $field => $col) {
            if ($field === $lewati) {
                continue;
            }
            $v = $r[$field] ?? null;
            if (isset($p['lainnya']) && $field === $p['lainnya']['field'] && $v === 'Lainnya'
                && ! empty($r[$p['lainnya']['keterangan']])) {
                $v = $r[$p['lainnya']['keterangan']];
            }
            $this->setSel($ws, $col . $baris, $v, $kolom[$field]['type'] ?? 'text');
        }

        if (isset($p['centang'])) {
            $nilai = $r[$p['centang']['field']] ?? null;
            foreach ($p['centang']['kolom'] as $opsi => $col) {
                $ws->getCell($col . $baris)->setValue($nilai === $opsi ? self::CENTANG : null);
            }
        }

        foreach ($p['jumlah'] ?? [] as $col => $fields) {
            $ada = array_filter($fields, fn ($f) => ($r[$f] ?? null) !== null && $r[$f] !== '');
            $ws->getCell($col . $baris)->setValue(
                $ada ? array_sum(array_map(fn ($f) => (float) ($r[$f] ?? 0), $fields)) : null
            );
        }
    }

    private function setSel(Worksheet $ws, string $ref, mixed $v, string $type): void
    {
        $cell = $ws->getCell($ref);
        if ($type === 'check') {
            $cell->setValue($v ? self::CENTANG : null);
            return;
        }
        if ($v === null || $v === '') {
            $cell->setValue(null);
            return;
        }
        if (in_array($type, ['number', 'decimal'], true) && is_numeric($v)) {
            $cell->setValueExplicit($v + 0, DataType::TYPE_NUMERIC);
            return;
        }
        // Teks selalu ditulis eksplisit agar isian yang diawali "=" tidak menjadi rumus.
        $cell->setValueExplicit((string) $v, DataType::TYPE_STRING);
        if (in_array($type, ['url', 'file'], true) && preg_match('#^https?://\S+$#i', (string) $v)) {
            $cell->getHyperlink()->setUrl((string) $v);
        }
    }

    private function kosongkan(Worksheet $ws, array $p, int $dari, int $sampai, ?string $kolomLabel): void
    {
        $cols = array_values($p['kolom']);
        if (isset($p['no'])) {
            $cols[] = $p['no'];
        }
        if ($kolomLabel) {
            $cols[] = $kolomLabel;
        }
        $cols = array_merge($cols, array_values($p['centang']['kolom'] ?? []), array_keys($p['jumlah'] ?? []));
        for ($r = $dari; $r <= $sampai; $r++) {
            foreach (array_unique($cols) as $c) {
                $ws->getCell($c . $r)->setValue(null);
            }
        }
    }

    private function barisTerakhirTerisi(Worksheet $ws, array $p, int $mulai, ?string $kolomLabel): int
    {
        $cols = array_values($p['kolom']);
        if ($kolomLabel) {
            $cols[] = $kolomLabel;
        }
        $akhir = $mulai - 1;
        $max = min($ws->getHighestDataRow(), $mulai + 5000);
        for ($r = $mulai; $r <= $max; $r++) {
            foreach ($cols as $c) {
                if (trim((string) $this->nilaiMentah($ws, $c . $r)) !== '') {
                    $akhir = $r;
                    break;
                }
            }
        }

        return $akhir;
    }

    // =====================================================================
    // IMPOR
    // =====================================================================

    public function impor(string $file): array
    {
        $reader = IOFactory::createReaderForFile($file);
        $reader->setReadDataOnly(true);
        $book = $reader->load($file);
        $hasil = [];

        $this->isian = [];
        foreach ($this->semuaIsian() as $kunci => [$label, $tipe, $sheet, $sel]) {
            if ($ws = $book->getSheetByName($sheet)) {
                $v = $this->bacaNilai($ws, $sel, $tipe);
                if ($v !== null) {
                    $this->isian[$kunci] = $tipe === 'number' ? $v : (string) $v;
                }
            }
        }

        foreach ($this->peta as $slug => $p) {
            $ws = $book->getSheetByName($p['sheet']);
            if (! $ws) {
                $this->catatan[] = "Sheet \"{$p['sheet']}\" tidak ditemukan di file, dilewati.";
                continue;
            }
            $rows = match ($this->mode($p)) {
                'sel'   => $this->bacaSel($ws, $slug, $p),
                'kunci' => $this->bacaKunci($ws, $slug, $p),
                'asal'  => $this->bacaAsal($ws, $slug, $p),
                default => $this->bacaDaftar($ws, $slug, $p),
            };
            $hasil[$slug] = array_map(fn ($r) => $this->lengkapiKolom($slug, $r), $rows);
        }

        return $hasil;
    }

    private function bacaDaftar(Worksheet $ws, string $slug, array $p): array
    {
        $kolom = $this->kolom($slug);
        $rows = [];

        if (isset($p['tetap'])) {
            $t = $p['tetap'];
            $r = $this->bacaBaris($ws, $t['baris'], $p, $kolom, $t['field']);
            if ($r !== null) {
                $r[$t['field']] = $t['nilai'];
                $rows[] = $r;
            }
        }

        $mulai = $p['mulai'];
        $footer = $this->footer($ws, $mulai);
        $akhir = $footer !== null ? $footer - 1 : min($ws->getHighestDataRow(), $mulai + 5000);
        $kosong = 0;

        for ($b = $mulai; $b <= $akhir; $b++) {
            // Minimal dua isian: baris yang hanya berisi label bawaan template (mis. "Yayasan") dilewati.
            $r = $this->bacaBaris($ws, $b, $p, $kolom, null, 2);
            if ($r === null) {
                if ($footer === null && ++$kosong >= 30) {
                    break;
                }
                continue;
            }
            $kosong = 0;
            if ($this->wajibTerisi($slug, $r, $b, $p['sheet'])) {
                $rows[] = $r;
            }
        }

        return $rows;
    }

    private function bacaKunci(Worksheet $ws, string $slug, array $p): array
    {
        $kolom = $this->kolom($slug);
        $field = $p['kunci']['field'];
        $opsi = [];
        foreach ($kolom[$field]['options'] as $o) {
            $opsi[$this->norm($o)] = $o;
        }

        $rows = [];
        foreach ($this->petaLabel($ws, $p) as $label => $baris) {
            $r = $this->bacaBaris($ws, $baris, $p, $kolom);
            if ($r === null) {
                continue;
            }
            $cocok = $this->cariLabel($opsi, $label);
            $r[$field] = $cocok ?? trim((string) $this->nilaiMentah($ws, $p['kunci']['kolom'] . $baris));
            $rows[] = $r;
        }

        return $rows;
    }

    private function bacaAsal(Worksheet $ws, string $slug, array $p): array
    {
        $kolom = $this->kolom($slug);
        $kategori = [];
        foreach ($kolom['kategori']['options'] as $o) {
            $kategori[$this->norm($o)] = $o;
        }

        $rows = [];
        $sekarang = null;
        $footer = $this->footer($ws, $p['mulai']) ?? $p['mulai'] + 200;
        for ($b = $p['mulai']; $b < $footer; $b++) {
            $label = trim((string) $this->nilaiMentah($ws, 'A' . $b));
            $r = $this->bacaBaris($ws, $b, $p, $kolom);
            $kat = $kategori[$this->norm($label)] ?? null;
            if ($kat !== null) {
                $sekarang = $kat;
                if ($r !== null) {
                    $rows[] = ['kategori' => $kat, 'asal' => null] + $r;
                }
                continue;
            }
            if ($r !== null && $sekarang !== null && ! in_array(mb_strtolower($label), self::PLACEHOLDER, true)) {
                $rows[] = ['kategori' => $sekarang, 'asal' => $label !== '' ? $label : null] + $r;
            }
        }

        return $rows;
    }

    private function bacaSel(Worksheet $ws, string $slug, array $p): array
    {
        $kolom = $this->kolom($slug);
        $r = [];
        foreach ($p['sel'] as $field => $ref) {
            $r[$field] = $this->bacaNilai($ws, $ref, $kolom[$field]['type'] ?? 'text');
        }

        return array_filter($r, fn ($v) => $v !== null) ? [$r] : [];
    }

    /** Mengembalikan null bila semua kolom yang dipetakan kosong. */
    private function bacaBaris(Worksheet $ws, int $baris, array $p, array $kolom, ?string $lewati = null, int $minIsi = 1): ?array
    {
        $r = [];
        $ada = false;
        foreach ($p['kolom'] as $field => $col) {
            if ($field === $lewati || ($kolom[$field]['type'] ?? '') === 'file') {
                continue;
            }
            $v = $this->bacaNilai($ws, $col . $baris, $kolom[$field]['type'] ?? 'text');
            $r[$field] = $v;
            if ($v !== null && $v !== false) {
                $ada = true;
            }
        }

        if (isset($p['centang'])) {
            $r[$p['centang']['field']] = null;
            foreach ($p['centang']['kolom'] as $opsi => $col) {
                if (trim((string) $this->nilaiMentah($ws, $col . $baris)) !== '') {
                    $r[$p['centang']['field']] = $opsi;
                    $ada = true;
                    break;
                }
            }
        }

        // Samakan isian pilihan dengan opsi yang ada (mis. "Universitas / PT" -> "Universitas/PT").
        foreach ($r as $f => $v) {
            $opsi = $kolom[$f]['options'] ?? [];
            if (($kolom[$f]['type'] ?? '') === 'select' && is_string($v) && $opsi && ! in_array($v, $opsi, true)) {
                $cocok = $this->cariLabel(array_combine(array_map(fn ($o) => $this->norm($o), $opsi), $opsi), $v);
                if ($cocok !== null) {
                    $r[$f] = $cocok;
                }
            }
        }

        if (! $ada || count(array_filter($r, fn ($v) => $v !== null && $v !== false && $v !== '')) < $minIsi) {
            return null;
        }

        if (isset($p['lainnya']) && $p['lainnya']['field'] !== $lewati) {
            $f = $p['lainnya']['field'];
            $opsi = $kolom[$f]['options'] ?? [];
            if ($r[$f] !== null && ! in_array($r[$f], $opsi, true)) {
                $cocok = $this->cariLabel(array_combine(array_map(fn ($o) => $this->norm($o), $opsi), $opsi), $this->norm($r[$f]));
                if ($cocok !== null) {
                    $r[$f] = $cocok;
                } else {
                    $r[$p['lainnya']['keterangan']] = $r[$f];
                    $r[$f] = 'Lainnya';
                }
            }
        }

        return $ada ? $r : null;
    }

    private function bacaNilai(Worksheet $ws, string $ref, string $type): mixed
    {
        $v = $this->nilaiMentah($ws, $ref);
        if (is_string($v)) {
            $v = trim($v);
        }
        if ($v === null || $v === '') {
            return $type === 'check' ? false : null;
        }
        if ($type === 'check') {
            return ! in_array(mb_strtolower((string) $v), ['-', '0', 'tidak'], true);
        }
        if (in_array($type, ['number', 'decimal'], true)) {
            if (! is_numeric($v)) {
                $v = str_replace([' ', ','], ['', '.'], (string) $v);
                if (! is_numeric($v)) {
                    return null;
                }
            }
            return $type === 'number' ? (int) round((float) $v) : round((float) $v, 2);
        }
        if (is_float($v) && floor($v) == $v) {
            $v = (int) $v;
        }
        $v = (string) $v;

        return in_array(mb_strtolower($v), self::PLACEHOLDER, true) ? null : $v;
    }

    private function nilaiMentah(Worksheet $ws, string $ref): mixed
    {
        $cell = $ws->getCell($ref);
        $v = $cell->getValue();
        if ($v instanceof RichText) {
            $v = $v->getPlainText();
        }
        if (is_string($v) && str_starts_with($v, '=')) {
            try {
                $v = $cell->getCalculatedValue();
            } catch (\Throwable) {
                $v = null;
            }
        }

        return $v;
    }

    private function wajibTerisi(string $slug, array $r, int $baris, string $sheet): bool
    {
        foreach ($this->kolom($slug) as $n => $k) {
            if (str_contains($k['rules'], 'required') && ! in_array($k['type'], ['file', 'check'], true)
                && (($r[$n] ?? null) === null || $r[$n] === '')) {
                if (array_filter($r, fn ($v) => $v !== null && $v !== false && $v !== '') ) {
                    $this->catatan[] = "{$sheet} baris {$baris}: kolom \"{$k['label']}\" kosong, baris dilewati.";
                }
                return false;
            }
        }

        return true;
    }

    private function lengkapiKolom(string $slug, array $r): array
    {
        $hasil = [];
        foreach ($this->kolom($slug) as $n => $k) {
            $hasil[$n] = $r[$n] ?? ($k['type'] === 'check' ? false : null);
        }
        foreach ($this->tabel[$slug]['total'] ?? [] as $target => $sumber) {
            $hasil[$target] = array_sum(array_map(fn ($c) => (float) ($hasil[$c] ?? 0), $sumber));
        }

        return $hasil;
    }

    // =====================================================================
    // UTILITAS
    // =====================================================================

    private function mode(array $p): string
    {
        return $p['mode'] ?? (isset($p['kunci']) ? 'kunci' : 'daftar');
    }

    private function kolom(string $slug): array
    {
        $hasil = [];
        foreach ($this->tabel[$slug]['kolom'] ?? [] as $n => $d) {
            $hasil[$n] = ['label' => str_replace('|', ' – ', $d[0]), 'type' => $d[1] ?? 'text', 'rules' => $d[2] ?? 'nullable', 'options' => $d[3] ?? []];
        }
        // Lampiran Bukti: saat ekspor berisi link pratinjau, saat impor dilewati.
        $hasil['lampiran_bukti'] ??= ['label' => 'Lampiran Bukti', 'type' => 'file', 'rules' => 'nullable', 'options' => []];

        return $hasil;
    }

    /** Baris pertama (mulai dari $mulai) yang berisi Jumlah/Keterangan/Total di kolom A. */
    private function footer(Worksheet $ws, int $mulai): ?int
    {
        $max = min($ws->getHighestDataRow(), $mulai + 5000);
        for ($r = $mulai; $r <= $max; $r++) {
            $v = trim((string) $this->nilaiMentah($ws, 'A' . $r));
            if ($v !== '' && preg_match(self::POLA_FOOTER, $v)) {
                return $r;
            }
        }

        return null;
    }

    /** [label ternormalisasi => nomor baris] untuk tabel berbaris tetap. */
    private function petaLabel(Worksheet $ws, array $p): array
    {
        $akhir = $this->footer($ws, $p['mulai']) ?? $p['mulai'] + 30;
        $peta = [];
        for ($r = $p['mulai']; $r < $akhir; $r++) {
            $label = $this->norm($this->nilaiMentah($ws, $p['kunci']['kolom'] . $r));
            if ($label !== '' && ! isset($peta[$label])) {
                $peta[$label] = $r;
            }
        }

        return $peta;
    }

    private function cariLabel(array $peta, string $label): mixed
    {
        $label = $this->norm($label);
        if ($label === '') {
            return null;
        }
        if (isset($peta[$label])) {
            return $peta[$label];
        }
        foreach ($peta as $k => $v) {
            if (min(strlen($k), strlen($label)) >= 5 && (str_starts_with($k, $label) || str_starts_with($label, $k))) {
                return $v;
            }
        }

        return null;
    }

    private function norm(mixed $s): string
    {
        return preg_replace('/[^a-z0-9]/', '', mb_strtolower((string) $s)) ?? '';
    }
}
EOF

tulis app/Support/LkpsData.php <<'EOF'
<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;

/** Jembatan antara database dan LkpsExcel. */
class LkpsData
{
    public static function template(): string
    {
        return storage_path('app/lkps/template.xlsx');
    }

    public static function excel(): LkpsExcel
    {
        return new LkpsExcel(config('lkps.tabel', []), config('lkps_excel', []), config('lkps.isian', []));
    }

    /** Isian di luar tabel: [kunci => nilai]. */
    public static function isian(): array
    {
        return Schema::hasTable('lkps_isian')
            ? DB::table('lkps_isian')->pluck('nilai', 'kunci')->all()
            : [];
    }

    public static function simpanIsian(array $nilai): void
    {
        $now = now();
        foreach ($nilai as $kunci => $v) {
            DB::table('lkps_isian')->updateOrInsert(
                ['kunci' => $kunci],
                ['nilai' => $v === '' ? null : $v, 'updated_at' => $now, 'created_at' => $now]
            );
        }
    }

    /** Seluruh isi 31 tabel: [slug => [ [kolom => nilai], ... ]]. */
    public static function semua(bool $linkLampiran = false): array
    {
        $data = [];
        foreach (array_keys(Lkps::tabel()) as $slug) {
            $nama = Lkps::namaTabel($slug);
            $rows = Schema::hasTable($nama)
                ? DB::table($nama)->orderBy('id')->get()->map(fn ($r) => (array) $r)->all()
                : [];

            // Untuk ekspor: path berkas diganti link pratinjau Lampiran Bukti
            // (ditulis ke kolom "Link Bukti" di template).
            if ($linkLampiran) {
                foreach ($rows as &$r) {
                    $r[Lkps::LAMPIRAN] = filled($r[Lkps::LAMPIRAN] ?? null)
                        ? Lkps::urlLampiran($slug, $r['id'])
                        : (filled($r['lampiran_link'] ?? null) ? $r['lampiran_link'] : null);
                }
                unset($r);
            }
            $data[$slug] = $rows;
        }

        return $data;
    }

    /**
     * Simpan hasil impor. Mode ganti: isi lama sebuah tabel dihapus hanya bila
     * file impor berisi data untuk tabel tersebut. Mengembalikan [slug => jumlah baris].
     */
    public static function simpan(array $hasil, bool $tambah, ?int $userId): array
    {
        $ringkas = [];
        DB::transaction(function () use ($hasil, $tambah, $userId, &$ringkas) {
            $now = now();
            foreach ($hasil as $slug => $rows) {
                if (! $rows || ! isset(Lkps::tabel()[$slug])) {
                    continue;
                }
                $nama = Lkps::namaTabel($slug);
                if (! $tambah) {
                    $berkas = array_keys(array_filter(Lkps::kolom($slug), fn ($k) => $k['type'] === 'file'));
                    foreach ($berkas as $kolom) {
                        Storage::disk(Lkps::DISK)->delete(DB::table($nama)->whereNotNull($kolom)->pluck($kolom)->all());
                    }
                    DB::table($nama)->delete();
                }
                foreach (array_chunk($rows, 200) as $potong) {
                    DB::table($nama)->insert(array_map(
                        fn ($r) => $r + ['created_by' => $userId, 'created_at' => $now, 'updated_at' => $now],
                        $potong
                    ));
                }
                $ringkas[$slug] = count($rows);
            }
        });

        return $ringkas;
    }
}
EOF

tulis app/Support/LkpsRingkasan.php <<'EOF'
<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/** Ringkasan kelengkapan LKPS untuk Dashboard Akreditasi dan halaman daftar LKPS. */
class LkpsRingkasan
{
    private static ?array $cache = null;

    /** Hapus hasil hitung yang tersimpan (dipakai setelah data berubah dalam proses yang sama). */
    public static function segarkan(): void
    {
        self::$cache = null;
    }

    /**
     * @return array{tersedia:bool,total:int,terisi:int,persen:int,kelompok:array}
     *  tersedia = tabel LKPS sudah dibuat (migration sudah dijalankan)
     */
    public static function data(): array
    {
        if (self::$cache !== null) {
            return self::$cache;
        }

        $tersedia = false;
        try {
            $tersedia = Schema::hasTable('lkps_isian');
        } catch (\Throwable $e) {
            $tersedia = false;
        }

        $kelompok = [];
        $total = 0;
        $terisi = 0;
        if ($tersedia) {
            foreach (Lkps::perKelompok() as $kode => $grup) {
                $items = [];
                foreach ($grup['tabel'] as $slug => $judul) {
                    $nama = Lkps::namaTabel($slug);
                    $n = Schema::hasTable($nama) ? DB::table($nama)->count() : 0;
                    $items[] = compact('slug', 'judul', 'n');
                    $total++;
                    $terisi += $n > 0 ? 1 : 0;
                }
                $kelompok[] = [
                    'kode'   => $kode,
                    'nama'   => $grup['nama'],
                    'items'  => $items,
                    'terisi' => count(array_filter($items, fn ($i) => $i['n'] > 0)),
                ];
            }
        }

        return self::$cache = [
            'tersedia' => $tersedia,
            'total'    => $total,
            'terisi'   => $terisi,
            'persen'   => $total ? (int) round($terisi / $total * 100) : 0,
            'kelompok' => $kelompok,
        ];
    }
}
EOF

tulis database/migrations/2026_10_08_000100_create_lkps_tables.php <<'EOF'
<?php

use App\Support\Lkps;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

// Hanya MENAMBAH tabel lkps_* baru (dan kolom yang belum ada). Tabel lain tidak disentuh.
return new class extends Migration
{
    public function up(): void
    {
        Lkps::sinkron();
    }

    public function down(): void
    {
        // Pengaman: hanya tabel yang masih KOSONG yang dihapus; tabel berisi data dibiarkan.
        foreach (array_keys(Lkps::tabel()) as $slug) {
            $nama = Lkps::namaTabel($slug);
            if (Schema::hasTable($nama) && DB::table($nama)->count() === 0) {
                Schema::dropIfExists($nama);
            }
        }
        if (Schema::hasTable('lkps_isian') && DB::table('lkps_isian')->count() === 0) {
            Schema::dropIfExists('lkps_isian');
        }
    }
};
EOF

tulis app/Console/Commands/LkpsSinkron.php <<'EOF'
<?php

namespace App\Console\Commands;

use App\Support\Lkps;
use Illuminate\Console\Command;

class LkpsSinkron extends Command
{
    protected $signature = 'lkps:sinkron';
    protected $description = 'Buat tabel/kolom LKPS baru sesuai config/lkps.php tanpa menghapus data';

    public function handle(): int
    {
        foreach (Lkps::sinkron() as $pesan) {
            $this->info($pesan);
        }

        return self::SUCCESS;
    }
}
EOF

tulis app/Console/Commands/LkpsImpor.php <<'EOF'
<?php

namespace App\Console\Commands;

use App\Support\LkpsData;
use Illuminate\Console\Command;

class LkpsImpor extends Command
{
    protected $signature = 'lkps:impor {file : path workbook .xlsx} {--ganti : ganti isi tabel yang ada di file (bawaan: menambahkan)}';
    protected $description = 'Impor workbook LKPS (.xlsx) ke database. Bawaan: menambahkan, tidak menghapus data yang ada';

    public function handle(): int
    {
        if (! class_exists(\PhpOffice\PhpSpreadsheet\IOFactory::class)) {
            $this->error('PhpSpreadsheet belum terpasang. Jalankan: composer require phpoffice/phpspreadsheet');

            return self::FAILURE;
        }
        @ini_set('memory_limit', '1024M');
        $excel = LkpsData::excel();
        $hasil = $excel->impor($this->argument('file'));
        $ringkas = LkpsData::simpan($hasil, ! $this->option('ganti'), null);
        LkpsData::simpanIsian($excel->isian);
        foreach ($ringkas as $slug => $n) {
            $this->line(sprintf('%-30s %4d baris', $slug, $n));
        }
        foreach ($excel->catatan as $c) {
            $this->warn($c);
        }
        $this->info('Impor selesai: ' . array_sum($ringkas) . ' baris.');

        return self::SUCCESS;
    }
}
EOF

tulis app/Console/Commands/LkpsEkspor.php <<'EOF'
<?php

namespace App\Console\Commands;

use App\Support\LkpsData;
use Illuminate\Console\Command;

class LkpsEkspor extends Command
{
    protected $signature = 'lkps:ekspor {tujuan=storage/app/lkps/LKPS_ekspor.xlsx : berkas hasil}';
    protected $description = 'Ekspor seluruh data LKPS ke template Excel';

    public function handle(): int
    {
        if (! class_exists(\PhpOffice\PhpSpreadsheet\IOFactory::class)) {
            $this->error('PhpSpreadsheet belum terpasang. Jalankan: composer require phpoffice/phpspreadsheet');

            return self::FAILURE;
        }
        @ini_set('memory_limit', '1024M');
        $template = LkpsData::template();
        if (! is_file($template)) {
            $this->error('Template belum ada di ' . $template);

            return self::FAILURE;
        }
        $excel = LkpsData::excel();
        $book = $excel->ekspor($template, LkpsData::semua(true), LkpsData::isian());
        @mkdir(dirname($this->argument('tujuan')), 0775, true);
        \PhpOffice\PhpSpreadsheet\IOFactory::createWriter($book, 'Xlsx')->save($this->argument('tujuan'));
        foreach ($excel->catatan as $c) {
            $this->warn($c);
        }
        $this->info('Tersimpan: ' . $this->argument('tujuan'));

        return self::SUCCESS;
    }
}
EOF

tulis app/Http/Controllers/LkpsController.php <<'EOF'
<?php

namespace App\Http\Controllers;

use App\Support\Lkps;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

class LkpsController extends Controller
{
    /** Halaman menu LKPS: daftar tabel per kelompok beserta kelengkapannya. */
    public function daftar()
    {
        return view('lkps.daftar', ['lk' => \App\Support\LkpsRingkasan::data(), 'tahun' => config('lkps.tahun_ts')]);
    }

    public function index(Request $request, string $tabel)
    {
        $def = Lkps::definisi($tabel);
        $kolom = Lkps::kolom($tabel);
        $cari = trim((string) $request->query('q', ''));

        $query = DB::table(Lkps::namaTabel($tabel))
            ->when($cari !== '', function ($q) use ($kolom, $cari) {
                $q->where(function ($w) use ($kolom, $cari) {
                    foreach ($kolom as $n => $k) {
                        if ($k['type'] !== 'file') {
                            $w->orWhere($n, 'like', "%{$cari}%");
                        }
                    }
                });
            })
            ->orderBy('id');
        $ringkasan = Lkps::ringkasan($tabel, (clone $query)->get());
        $rows = $query->paginate(25)->withQueryString();

        return view('lkps.tabel', [
            'tabel'    => $tabel,
            'def'      => $def,
            'kolom'    => $kolom,
            'rows'     => $rows,
            'cari'      => $cari,
            'kelompok'  => Lkps::namaKelompok($tabel),
            'header'    => Lkps::header($tabel),
            'ringkasan' => $ringkasan,
        ]);
    }

    public function create(string $tabel)
    {
        return $this->form($tabel, null);
    }

    public function store(Request $request, string $tabel)
    {
        $data = $this->ambilData($request, $tabel, null);
        $data['created_by'] = $request->user()?->id;
        $data['created_at'] = $data['updated_at'] = now();

        DB::table(Lkps::namaTabel($tabel))->insert($data);

        return $this->kembali($tabel)->with('ok', 'Data ditambahkan.');
    }

    public function edit(string $tabel, int $id)
    {
        return $this->form($tabel, $this->cariBaris($tabel, $id));
    }

    public function update(Request $request, string $tabel, int $id)
    {
        $row = $this->cariBaris($tabel, $id);
        $data = $this->ambilData($request, $tabel, $row);
        $data['updated_at'] = now();

        DB::table(Lkps::namaTabel($tabel))->where('id', $id)->update($data);

        return $this->kembali($tabel)->with('ok', 'Perubahan disimpan.');
    }

    public function destroy(string $tabel, int $id)
    {
        $row = $this->cariBaris($tabel, $id);
        foreach (Lkps::kolom($tabel) as $n => $k) {
            if ($k['type'] === 'file' && $row->$n) {
                Storage::disk(Lkps::DISK)->delete($row->$n);
            }
        }
        DB::table(Lkps::namaTabel($tabel))->where('id', $id)->delete();

        return $this->kembali($tabel)->with('ok', 'Data dihapus.');
    }

    /** Ekspor CSV (pemisah titik koma agar langsung terbaca Excel berlokal Indonesia). */
    public function export(string $tabel)
    {
        $kolom = Lkps::kolom($tabel);
        $nama = Lkps::namaTabel($tabel);

        return response()->streamDownload(function () use ($kolom, $nama, $tabel) {
            $out = fopen('php://output', 'w');
            fwrite($out, "\xEF\xBB\xBF");
            fputcsv($out, array_merge(['No'], array_column($kolom, 'label')), ';');
            $no = 0;
            DB::table($nama)->orderBy('id')->chunk(500, function ($rows) use (&$no, $out, $kolom, $tabel) {
                foreach ($rows as $r) {
                    $baris = [++$no];
                    foreach ($kolom as $n => $k) {
                        $baris[] = match (true) {
                            $k['type'] === 'check' => $r->$n ? '√' : '',
                            $k['type'] === 'file'  => $r->$n ? Lkps::urlLampiran($tabel, $r->id, $n) : '',
                            default                => $r->$n,
                        };
                    }
                    fputcsv($out, $baris, ';');
                }
            });
            fclose($out);
        }, "lkps_{$tabel}_" . date('Ymd') . '.csv', ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    /** Tabel tersembunyi (mis. Daftar Dosen Homebase) kembali ke halaman Identitas; tabel lain ke daftar barisnya. */
    private function kembali(string $tabel)
    {
        return ! empty(Lkps::definisi($tabel)['tersembunyi'])
            ? redirect()->to(route('lkps.isian.index') . '#dosen-homebase')
            : redirect()->route('lkps.tabel.index', $tabel);
    }

    private function form(string $tabel, ?object $row)
    {
        return view('lkps.form', [
            'tabel'    => $tabel,
            'def'      => Lkps::definisi($tabel),
            'kolom'    => Lkps::kolom($tabel),
            'row'      => $row,
            'kelompok' => Lkps::namaKelompok($tabel),
        ]);
    }

    private function cariBaris(string $tabel, int $id): object
    {
        Lkps::definisi($tabel);
        $row = DB::table(Lkps::namaTabel($tabel))->where('id', $id)->first();
        abort_if(! $row, 404, 'Data tidak ditemukan.');

        return $row;
    }

    private function ambilData(Request $request, string $tabel, ?object $row): array
    {
        $data = $request->validate(Lkps::rules($tabel, $row !== null), [], Lkps::label($tabel));

        foreach (Lkps::kolom($tabel) as $n => $k) {
            if ($k['type'] === 'check') {
                $data[$n] = $request->boolean($n);
                continue;
            }
            if ($k['type'] !== 'file') {
                continue;
            }
            if ($request->hasFile($n)) {
                if ($row && $row->$n) {
                    Storage::disk(Lkps::DISK)->delete($row->$n);
                }
                $data[$n] = $request->file($n)->store("lkps/{$tabel}", Lkps::DISK);
            } elseif ($row && $row->$n && $request->boolean("hapus_{$n}")) {
                Storage::disk(Lkps::DISK)->delete($row->$n);
                $data[$n] = null;
            } else {
                unset($data[$n]);
            }
        }

        // Kolom total dihitung otomatis (mis. Total SKS pada EWMP).
        foreach (Lkps::definisi($tabel)['total'] ?? [] as $target => $sumber) {
            $data[$target] = array_sum(array_map(fn ($c) => (float) ($data[$c] ?? 0), $sumber));
        }

        return $data;
    }
}
EOF

tulis app/Http/Controllers/LkpsExcelController.php <<'EOF'
<?php

namespace App\Http\Controllers;

use App\Support\Lkps;
use App\Support\LkpsData;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\File;

class LkpsExcelController extends Controller
{
    /** Pustaka PhpSpreadsheet opsional; tanpa itu halaman ini hanya menampilkan petunjuk pemasangan. */
    private function tersedia(): bool
    {
        return class_exists(\PhpOffice\PhpSpreadsheet\IOFactory::class);
    }

    private function tanpaPustaka()
    {
        return redirect()->route('lkps.excel.index')
            ->with('galat', 'Pustaka PhpSpreadsheet belum terpasang. Jalankan: composer require phpoffice/phpspreadsheet');
    }

    public function index()
    {
        $path = LkpsData::template();

        return view('lkps.excel', [
            'tersedia'      => $this->tersedia(),
            'adaTemplate'   => is_file($path),
            'waktuTemplate' => is_file($path) ? date('d-m-Y H:i', filemtime($path)) : null,
            'judul'         => array_map(fn ($d) => $d['judul'], Lkps::tabel()),
        ]);
    }

    public function ekspor()
    {
        if (! $this->tersedia()) {
            return $this->tanpaPustaka();
        }
        $path = LkpsData::template();
        if (! is_file($path)) {
            return redirect()->route('lkps.excel.index')->with('galat', 'Template Excel belum diunggah. Unggah template terlebih dahulu.');
        }
        $this->longgarkanBatas();

        $excel = LkpsData::excel();
        $book = $excel->ekspor($path, LkpsData::semua(true), LkpsData::isian());
        $tmp = tempnam(sys_get_temp_dir(), 'lkps') . '.xlsx';
        \PhpOffice\PhpSpreadsheet\IOFactory::createWriter($book, 'Xlsx')->save($tmp);

        return response()->download($tmp, 'LKPS_LAM_Infokom_' . date('Ymd_His') . '.xlsx')->deleteFileAfterSend(true);
    }

    public function unggahTemplate(Request $request)
    {
        if (! $this->tersedia()) {
            return $this->tanpaPustaka();
        }
        $request->validate(['template' => ['required', 'file', 'max:20480', $this->harusXlsx()]], [], ['template' => 'template']);
        $this->longgarkanBatas();

        $file = $request->file('template');
        try {
            $sheets = \PhpOffice\PhpSpreadsheet\IOFactory::createReaderForFile($file->getRealPath())->listWorksheetNames($file->getRealPath());
        } catch (\Throwable) {
            return back()->with('galat', 'File tidak bisa dibaca sebagai workbook Excel.');
        }
        $hilang = array_diff(array_column(config('lkps_excel'), 'sheet'), $sheets);
        if ($hilang) {
            return back()->with('galat', 'Template belum sesuai. Sheet yang tidak ditemukan: ' . implode(', ', $hilang) . '.');
        }

        File::ensureDirectoryExists(dirname(LkpsData::template()));
        $file->move(dirname(LkpsData::template()), basename(LkpsData::template()));

        return back()->with('ok', 'Template disimpan. Ekspor berikutnya memakai template ini.');
    }

    public function impor(Request $request)
    {
        if (! $this->tersedia()) {
            return $this->tanpaPustaka();
        }
        $request->validate([
            'file' => ['required', 'file', 'max:20480', $this->harusXlsx()],
            'mode' => ['required', 'in:ganti,tambah'],
        ], [], ['file' => 'file Excel', 'mode' => 'cara impor']);
        $this->longgarkanBatas();

        $excel = LkpsData::excel();
        try {
            $hasil = $excel->impor($request->file('file')->getRealPath());
        } catch (\Throwable $e) {
            return back()->with('galat', 'File tidak bisa dibaca: ' . $e->getMessage());
        }

        $ringkas = LkpsData::simpan($hasil, $request->input('mode') === 'tambah', $request->user()->id);
        LkpsData::simpanIsian($excel->isian);
        $total = array_sum($ringkas);

        return redirect()->route('lkps.excel.index')
            ->with('ok', "Impor selesai: {$total} baris masuk ke " . count($ringkas) . ' tabel, '
                . count($excel->isian) . ' isian identitas/tambahan diperbarui.')
            ->with('ringkas', $ringkas)
            ->with('catatan', $excel->catatan);
    }

    private function harusXlsx(): \Closure
    {
        return function (string $attr, $file, \Closure $fail) {
            if (strtolower($file->getClientOriginalExtension()) !== 'xlsx') {
                $fail('File harus berformat .xlsx.');
            }
        };
    }

    private function longgarkanBatas(): void
    {
        @ini_set('memory_limit', '1024M');
        @set_time_limit(300);
    }
}
EOF

tulis app/Http/Controllers/LkpsIsianController.php <<'EOF'
<?php

namespace App\Http\Controllers;

use App\Support\Lkps;
use App\Support\LkpsData;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class LkpsIsianController extends Controller
{
    /** Tabel LKPS yang ditampilkan sebagai "Daftar Dosen Homebase" pada halaman ini. */
    private const TABEL_DOSEN = 'dosen_homebase';

    /** Grup isian yang tampil di formulir (grup pada 'isian_sembunyi' tetap tersimpan, hanya tidak ditampilkan). */
    private function grupAktif(): array
    {
        return array_diff_key(config('lkps.isian', []), array_flip(config('lkps.isian_sembunyi', [])));
    }

    public function index()
    {
        $slug = self::TABEL_DOSEN;
        $ada = isset(config('lkps.tabel', [])[$slug]) && Schema::hasTable(Lkps::namaTabel($slug));

        return view('lkps.isian', [
            'grup'      => $this->grupAktif(),
            'nilai'     => LkpsData::isian(),
            'slugDosen' => $slug,
            'dosenAda'  => $ada,
            'dosen'     => $ada ? DB::table(Lkps::namaTabel($slug))->orderBy('nama_dosen')->orderBy('id')->get() : collect(),
        ]);
    }

    public function simpan(Request $request)
    {
        $rules = [];
        $label = [];
        foreach ($this->grupAktif() as $daftar) {
            foreach ($daftar as $kunci => [$lbl, $tipe]) {
                $rules[$kunci] = $tipe === 'number' ? ['nullable', 'integer', 'min:0'] : ['nullable', 'string', 'max:255'];
                $label[$kunci] = $lbl;
            }
        }
        $data = $request->validate($rules, [], $label);
        LkpsData::simpanIsian(array_map(fn ($v) => $v ?? '', $data + array_fill_keys(array_keys($rules), null)));

        return back()->with('ok', 'Isian disimpan.');
    }
}
EOF

tulis app/Http/Controllers/LkpsLampiranController.php <<'EOF'
<?php

namespace App\Http\Controllers;

use App\Support\Lkps;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

/** Pratinjau lampiran bukti: berkas dibuka di browser (inline), bukan diunduh. */
class LkpsLampiranController extends Controller
{
    public function lihat(string $tabel, int $id, string $kolom = 'lampiran_bukti')
    {
        [$row, $path] = $this->cari($tabel, $id, $kolom);
        $mime = Storage::disk(Lkps::DISK)->mimeType($path) ?: 'application/octet-stream';

        // Ringkasan baris: dua isian teks pertama, sebagai keterangan di halaman pratinjau.
        $ringkas = [];
        foreach (Lkps::kolom($tabel) as $n => $k) {
            if (in_array($k['type'], ['text', 'select'], true) && filled($row->$n ?? null)) {
                $ringkas[] = $row->$n;
            }
            if (count($ringkas) === 2) {
                break;
            }
        }

        return view('lkps.lampiran', [
            'tabel'   => $tabel,
            'def'     => Lkps::definisi($tabel),
            'label'   => Lkps::kolom($tabel)[$kolom]['label'],
            'ringkas' => implode(' – ', $ringkas),
            'mime'    => $mime,
            'src'     => route('lkps.lampiran.berkas', [$tabel, $id, $kolom]),
        ]);
    }

    public function berkas(string $tabel, int $id, string $kolom)
    {
        [, $path] = $this->cari($tabel, $id, $kolom);

        return response()->file(Storage::disk(Lkps::DISK)->path($path), [
            'Content-Disposition'    => 'inline; filename="' . basename($path) . '"',
            'X-Content-Type-Options' => 'nosniff',
            'Cache-Control'          => 'private, max-age=3600',
        ]);
    }

    private function cari(string $tabel, int $id, string $kolom): array
    {
        $kol = Lkps::kolom($tabel);
        abort_if(($kol[$kolom]['type'] ?? null) !== 'file', 404);

        $row = DB::table(Lkps::namaTabel($tabel))->where('id', $id)->first();
        $path = $row->$kolom ?? null;
        abort_if(! $path || ! Storage::disk(Lkps::DISK)->exists($path), 404, 'Lampiran tidak ditemukan.');

        return [$row, $path];
    }
}
EOF

tulis resources/views/lkps/_gaya.blade.php <<'EOF'
<style>
.lk-crumb{color:var(--muted,#667085);font-size:.82rem;margin-bottom:.2rem}
.lk-panel{background:var(--card,#fff);border:1px solid var(--line,#e4e8ef);border-radius:12px;padding:1.1rem 1.2rem;box-shadow:0 1px 2px rgba(16,24,40,.04)}
.lk-wrap{background:var(--card,#fff);border:1px solid var(--line,#e4e8ef);border-radius:12px;overflow:auto}
.lk-wrap table{margin:0;font-size:.86rem}
.lk-wrap thead th{white-space:nowrap;vertical-align:middle;border:1px solid var(--line,#e4e8ef)}
.lk-wrap tfoot th,.lk-wrap tfoot td{background:var(--head,#f7f9fc);font-weight:600;border-top:2px solid var(--line,#e4e8ef)}
.lk-seg{display:flex;gap:4px;margin:.7rem 0 .9rem}
.lk-seg span{flex:1;height:9px;border-radius:3px}
.lk-seg .isi{background:var(--ok,#15803d)}
.lk-seg .kosong{background:#fdeed8;outline:1px solid #e8c995}
.lk-list{list-style:none;padding:0;margin:0}
.lk-list li{display:flex;justify-content:space-between;gap:1rem;padding:.42rem 0;border-top:1px solid var(--line,#e4e8ef)}
.lk-list a{color:var(--text,#1b2536);text-decoration:none}
.lk-list a:hover{color:var(--pri,#1d4ed8);text-decoration:underline}
.lk-status{font-size:.76rem;padding:.1rem .55rem;border-radius:999px;white-space:nowrap}
.lk-status.isi{background:#dcf2e3;color:var(--ok,#15803d)}
.lk-status.kosong{background:#fdeed8;color:var(--warn,#b45309)}
</style>
EOF

tulis resources/views/lkps/daftar.blade.php <<'EOF'
@extends('layout')
@section('title', 'LKPS')

@section('content')
@include('lkps._gaya')
<div class="d-flex flex-wrap justify-content-between align-items-end gap-3 mb-3">
  <div>
    <p class="lk-crumb">Data Induk</p>
    <h1 class="mb-0">LKPS LAM Infokom</h1>
    <p class="small text-secondary mb-0 mt-1">Laporan Kinerja Program Studi Tahun Semester 2023/2024, 2024/2025 dan 2025/2026</p>
  </div>
  <div class="d-flex gap-2">
    <a href="{{ route('lkps.isian.index') }}" class="btn btn-sm btn-warning fw-bold px-3 shadow-sm" style="box-shadow:0 0 0 3px rgba(245,158,11,.35)!important">Identitas UPPS dan Program Studi</a>
    <a href="{{ route('lkps.excel.index') }}" class="btn btn-sm btn-outline-secondary">Impor &amp; ekspor Excel</a>
  </div>
</div>

@if(! $lk['tersedia'])
  <div class="alert alert-warning">Tabel LKPS belum dibuat. Jalankan <code>php artisan lkps:sinkron</code> di folder aplikasi.</div>
@else
  <div class="lk-panel mb-3">
    <div class="mb-2"><strong>{{ $lk['terisi'] }}</strong> dari {{ $lk['total'] }} tabel sudah berisi data</div>
    <div style="max-width:560px">@include('bar', ['v' => $lk['persen']])</div>
  </div>
  <div class="row g-3">
    @foreach($lk['kelompok'] as $g)
      <div class="col-12 col-xl-6">
        <section class="lk-panel h-100">
          <div class="d-flex justify-content-between align-items-baseline gap-2">
            <h2 class="h6 mb-0 fw-semibold">{{ $g['nama'] }}</h2>
            <span class="small text-secondary text-nowrap">{{ $g['terisi'] }}/{{ count($g['items']) }} terisi</span>
          </div>
          <div class="lk-seg" aria-hidden="true">
            @foreach($g['items'] as $i)<span class="{{ $i['n'] > 0 ? 'isi' : 'kosong' }}" title="{{ $i['judul'] }}"></span>@endforeach
          </div>
          <ul class="lk-list">
            @foreach($g['items'] as $i)
              <li>
                <a href="{{ route('lkps.tabel.index', $i['slug']) }}">{{ $i['judul'] }}</a>
                <span class="lk-status {{ $i['n'] > 0 ? 'isi' : 'kosong' }}">{{ $i['n'] > 0 ? $i['n'] . ' baris' : 'Belum diisi' }}</span>
              </li>
            @endforeach
          </ul>
        </section>
      </div>
    @endforeach
  </div>
@endif
@endsection
EOF

tulis resources/views/lkps/dashboard.blade.php <<'EOF'
@php $lk = \App\Support\LkpsRingkasan::data(); @endphp
@if($lk['tersedia'])
@include('lkps._gaya')
<div class="sec" style="margin-top:26px">Kelengkapan LKPS</div>
<div class="lk-panel mb-3">
  <div class="d-flex justify-content-between flex-wrap gap-2 align-items-baseline mb-2">
    <span><strong>{{ $lk['terisi'] }}</strong> dari {{ $lk['total'] }} tabel LKPS sudah berisi data</span>
    <a href="{{ route('lkps.daftar') }}" class="small">Buka LKPS &rarr;</a>
  </div>
  <div style="max-width:560px">@include('bar', ['v' => $lk['persen']])</div>
</div>
<div class="row g-3">
  @foreach($lk['kelompok'] as $g)
    <div class="col-12 col-xl-6">
      <section class="lk-panel h-100">
        <div class="d-flex justify-content-between align-items-baseline gap-2">
          <h2 class="h6 mb-0 fw-semibold">{{ $g['nama'] }}</h2>
          <span class="small text-secondary text-nowrap">{{ $g['terisi'] }}/{{ count($g['items']) }} terisi</span>
        </div>
        <div class="lk-seg" aria-hidden="true">
          @foreach($g['items'] as $i)<span class="{{ $i['n'] > 0 ? 'isi' : 'kosong' }}" title="{{ $i['judul'] }}"></span>@endforeach
        </div>
        <ul class="lk-list">
          @foreach($g['items'] as $i)
            <li>
              <a href="{{ route('lkps.tabel.index', $i['slug']) }}">{{ $i['judul'] }}</a>
              <span class="lk-status {{ $i['n'] > 0 ? 'isi' : 'kosong' }}">{{ $i['n'] > 0 ? $i['n'] . ' baris' : 'Belum diisi' }}</span>
            </li>
          @endforeach
        </ul>
      </section>
    </div>
  @endforeach
</div>
@endif
EOF

tulis resources/views/lkps/excel.blade.php <<'EOF'
@extends('layout')
@section('title', 'Impor & ekspor Excel')

@section('content')
@include('lkps._gaya')
<h1 class="mb-1">Impor & ekspor Excel</h1>
<p class="text-secondary mb-4" style="max-width: 70ch">
    Ekspor mengisi template resmi LKPS (31 sheet) dengan seluruh data aplikasi. Impor membaca workbook
    dengan format yang sama dan memasukkan isinya ke database.
</p>

@if (! $tersedia)
    <div class="alert alert-warning py-2">Pustaka <strong>PhpSpreadsheet</strong> belum terpasang di server, jadi impor dan ekspor Excel belum dapat dipakai. Jalankan di folder aplikasi: <code>composer require phpoffice/phpspreadsheet</code></div>
@endif

@if (session('galat'))
    <div class="alert alert-danger py-2">{{ session('galat') }}</div>
@endif

@if (session('ringkas'))
    <div class="lk-panel mb-3">
        <h2 class="mb-2">Hasil impor</h2>
        <ul class="lk-list">
            @foreach (session('ringkas') as $slug => $n)
                <li><a href="{{ route('lkps.tabel.index', $slug) }}">{{ $judul[$slug] ?? $slug }}</a><span class="lk-status isi">{{ $n }} baris</span></li>
            @endforeach
        </ul>
    </div>
@endif

@if (session('catatan'))
    <div class="alert alert-warning py-2">
        <strong>Catatan:</strong>
        <ul class="mb-0 mt-1">
            @foreach (session('catatan') as $c)
                <li>{{ $c }}</li>
            @endforeach
        </ul>
    </div>
@endif

<div class="row g-3">
    <div class="col-12 col-xl-4">
        <section class="lk-panel h-100">
            <h2 class="mb-2">Ekspor ke template</h2>
            @if ($adaTemplate)
                <p class="small text-secondary">Template terakhir diperbarui {{ $waktuTemplate }}.</p>
                <a href="{{ route('lkps.excel.ekspor') }}" class="btn btn-primary">Unduh LKPS (.xlsx)</a>
            @else
                <p class="small text-secondary mb-0">Template belum ada. Unggah template LKPS terlebih dahulu.</p>
            @endif
        </section>
    </div>

    <div class="col-12 col-xl-4">
        <section class="lk-panel h-100">
            <h2 class="mb-2">Template LKPS</h2>
            <p class="small text-secondary">{{ $adaTemplate ? 'Template sudah tersedia. Unggah lagi untuk mengganti.' : 'Unggah workbook template LKPS LAM Infokom yang kosong.' }}</p>
            @auth
                <form method="POST" action="{{ route('lkps.excel.template') }}" enctype="multipart/form-data">
                    @csrf
                    <label for="template" class="visually-hidden">File template</label>
                    <input id="template" type="file" name="template" accept=".xlsx" required class="form-control form-control-sm mb-2 @error('template') is-invalid @enderror">
                    @error('template') <div class="invalid-feedback d-block mb-2">{{ $message }}</div> @enderror
                    <button class="btn btn-sm btn-outline-secondary">Simpan template</button>
                </form>
            @else
                <a href="{{ route('login') }}" class="btn btn-sm btn-outline-secondary">Masuk untuk mengunggah template</a>
            @endauth
        </section>
    </div>

    <div class="col-12 col-xl-4">
        <section class="lk-panel h-100">
            <h2 class="mb-2">Impor dari Excel</h2>
            @auth
                <form method="POST" action="{{ route('lkps.excel.impor') }}" enctype="multipart/form-data">
                    @csrf
                    <label for="file" class="form-label small fw-semibold">Workbook LKPS yang sudah terisi</label>
                    <input id="file" type="file" name="file" accept=".xlsx" required class="form-control form-control-sm mb-2 @error('file') is-invalid @enderror">
                    @error('file') <div class="invalid-feedback d-block mb-2">{{ $message }}</div> @enderror
                    <div class="form-check small">
                        <input class="form-check-input" type="radio" name="mode" id="mode-ganti" value="ganti">
                        <label class="form-check-label" for="mode-ganti">Ganti isi tabel yang ada di file</label>
                    </div>
                    <div class="form-check small mb-3">
                        <input class="form-check-input" type="radio" name="mode" id="mode-tambah" value="tambah" checked>
                        <label class="form-check-label" for="mode-tambah">Tambahkan ke data yang sudah ada</label>
                    </div>
                    <button class="btn btn-sm btn-primary" onclick="return document.getElementById('mode-tambah').checked || confirm('Isi tabel yang ada di file akan diganti. Lanjutkan?')">Impor</button>
                </form>
            @else
                <a href="{{ route('login') }}" class="btn btn-sm btn-outline-secondary">Masuk untuk mengimpor data</a>
            @endauth
        </section>
    </div>
</div>
@endsection
EOF

tulis resources/views/lkps/form.blade.php <<'EOF'
@extends('layout')
@section('title', ($row ? 'Ubah data' : 'Tambah data') . ' - ' . $def['judul'])

@section('content')
@include('lkps._gaya')
<p class="lk-crumb"><a href="{{ route('lkps.daftar') }}" class="link-secondary">LKPS</a> / {{ $kelompok }} / {{ $def['judul'] }}</p>
<h1 class="mb-3">{{ $row ? 'Ubah data' : 'Tambah data' }}</h1>

<form method="POST" enctype="multipart/form-data" class="lk-panel" style="max-width: 760px"
      action="{{ $row ? route('lkps.tabel.update', [$tabel, $row->id]) : route('lkps.tabel.store', $tabel) }}">
    @csrf
    @if ($row) @method('PUT') @endif

    @foreach ($kolom as $n => $k)
        @php
            $nilai = old($n, data_get($row, $n));
            $wajib = str_contains($k['rules'], 'required') && ! ($k['type'] === 'file' && $row);
            $tipeInput = ['number' => 'number', 'decimal' => 'number', 'date' => 'date', 'url' => 'url'][$k['type']] ?? 'text';
            $otomatis = array_key_exists($n, $def['total'] ?? []);
        @endphp
        @if ($k['type'] === 'check')
            <div class="form-check mb-3">
                <input type="hidden" name="{{ $n }}" value="0">
                <input class="form-check-input" type="checkbox" id="f_{{ $n }}" name="{{ $n }}" value="1" @checked($nilai)>
                <label class="form-check-label fw-semibold" for="f_{{ $n }}">{{ $k['label'] }}</label>
            </div>
            @continue
        @endif
        <div class="mb-3">
            <label for="f_{{ $n }}" class="form-label fw-semibold">
                {{ $k['label'] }} @if ($wajib)<span class="text-danger" aria-hidden="true">*</span>@endif
            </label>

            @if ($k['type'] === 'textarea')
                <textarea id="f_{{ $n }}" name="{{ $n }}" rows="3" @if ($wajib) required @endif
                          class="form-control @error($n) is-invalid @enderror">{{ $nilai }}</textarea>
            @elseif ($k['type'] === 'select')
                <select id="f_{{ $n }}" name="{{ $n }}" @if ($wajib) required @endif
                        class="form-select @error($n) is-invalid @enderror">
                    <option value="">Pilih salah satu</option>
                    @foreach ($k['options'] as $opsi)
                        <option value="{{ $opsi }}" @selected((string) $nilai === (string) $opsi)>{{ $opsi }}</option>
                    @endforeach
                </select>
            @elseif ($k['type'] === 'file')
                <input id="f_{{ $n }}" name="{{ $n }}" type="file" @if ($wajib) required @endif
                       accept=".pdf,.jpg,.jpeg,.png,.webp,application/pdf,image/*"
                       class="form-control @error($n) is-invalid @enderror">
                <div class="form-text">
                    PDF atau gambar (JPG, PNG, WEBP), maksimal {{ \App\Support\Lkps::MAKS_LAMPIRAN_KB / 1024 }} MB.
                    Lampiran dibuka sebagai pratinjau di browser, bukan diunduh.
                </div>
                @if (\App\Support\Lkps::batasServerMb() < \App\Support\Lkps::MAKS_LAMPIRAN_KB / 1024)
                    <div class="form-text text-danger">
                        Pengaturan PHP server saat ini hanya menerima berkas hingga
                        {{ \App\Support\Lkps::angka(\App\Support\Lkps::batasServerMb()) }} MB.
                        Naikkan upload_max_filesize dan post_max_size (lihat README, bagian batas unggah).
                    </div>
                @endif
                @if ($row && data_get($row, $n))
                    <div class="d-flex flex-wrap align-items-center gap-3 mt-2 small">
                        <a href="{{ \App\Support\Lkps::urlLampiran($tabel, $row->id, $n) }}" target="_blank" rel="noopener">
                            Lihat lampiran saat ini
                        </a>
                        <div class="form-check mb-0">
                            <input class="form-check-input" type="checkbox" name="hapus_{{ $n }}" value="1" id="hapus_{{ $n }}">
                            <label class="form-check-label" for="hapus_{{ $n }}">Hapus lampiran</label>
                        </div>
                        <span class="text-secondary">Pilih berkas baru untuk mengganti.</span>
                    </div>
                @endif
            @elseif ($otomatis)
                <input id="f_{{ $n }}" type="text" value="{{ $nilai }}" class="form-control" readonly>
                <div class="form-text">Dihitung otomatis saat data disimpan.</div>
            @else
                <input id="f_{{ $n }}" name="{{ $n }}" type="{{ $tipeInput }}" value="{{ $nilai }}"
                       @if ($k['type'] === 'decimal') step="0.01" @endif
                       @if ($k['type'] === 'number') step="1" min="0" @endif
                       @if ($wajib) required @endif
                       class="form-control @error($n) is-invalid @enderror">
                @if ($n === 'lampiran_link')
                    <div class="form-text">
                        Opsional: tempel link bukti (mis. Google Drive atau situs resmi), diawali http:// atau https://.
                        Boleh diisi bersama berkas lampiran atau sebagai pengganti berkas.
                    </div>
                @endif
            @endif

            @error($n)
                <div class="invalid-feedback d-block">{{ $message }}</div>
            @enderror
        </div>
    @endforeach

    <div class="d-flex gap-2 pt-2">
        <button class="btn btn-primary">{{ $row ? 'Simpan perubahan' : 'Simpan data' }}</button>
        <a href="{{ ! empty($def['tersembunyi']) ? route('lkps.isian.index') : route('lkps.tabel.index', $tabel) }}" class="btn btn-outline-secondary">Batal</a>
    </div>
</form>
@endsection
EOF

tulis app/Support/LkpsImporFile.php <<'EOF'
<?php

namespace App\Support;

/**
 * Pembaca file impor untuk SATU tabel LKPS: CSV (selalu bisa) dan Excel .xlsx/.xls
 * (bila PhpSpreadsheet terpasang). Kelas ini tidak menyentuh database.
 */
class LkpsImporFile
{
    public const MAKS_BARIS = 5000;

    public static function adaXlsx(): bool
    {
        return class_exists(\PhpOffice\PhpSpreadsheet\IOFactory::class);
    }

    /** @return array<int,array<int,mixed>> baris mentah (indeks dari 0); baris kosong = [] */
    public static function baca(string $path, string $ext): array
    {
        return in_array(strtolower($ext), ['xlsx', 'xls'], true) ? self::bacaExcel($path) : self::bacaCsv($path);
    }

    private static function bacaExcel(string $path): array
    {
        if (! self::adaXlsx()) {
            throw new \RuntimeException('Impor .xlsx/.xls membutuhkan pustaka PhpSpreadsheet (composer require phpoffice/phpspreadsheet). Simpan file sebagai CSV, atau pasang pustakanya.');
        }
        $reader = \PhpOffice\PhpSpreadsheet\IOFactory::createReaderForFile($path);
        $reader->setReadDataOnly(true);
        $book = $reader->load($path);
        $ws = $book->getSheetByName('Data') ?? $book->getSheet(0);

        return $ws->toArray(null, true, false, false);
    }

    public static function bacaCsv(string $path): array
    {
        $isi = (string) file_get_contents($path);
        if (str_starts_with($isi, "\xEF\xBB\xBF")) {
            $isi = substr($isi, 3);
        }
        if (! mb_check_encoding($isi, 'UTF-8')) {
            $isi = mb_convert_encoding($isi, 'UTF-8', 'Windows-1252');
        }

        // Pemisah dideteksi dari baris pertama: titik koma (Excel Indonesia), koma, atau tab.
        $pertama = strtok($isi, "\n") ?: '';
        $sep = ';';
        $maks = -1;
        foreach ([';', ',', "\t"] as $c) {
            $n = substr_count($pertama, $c);
            if ($n > $maks) {
                $maks = $n;
                $sep = $c;
            }
        }

        $h = fopen('php://temp', 'r+');
        fwrite($h, $isi);
        rewind($h);
        $hasil = [];
        while (($r = fgetcsv($h, 0, $sep, '"', '')) !== false) {
            $hasil[] = $r === [null] ? [] : $r;
            if (count($hasil) > self::MAKS_BARIS + 2) {
                break;
            }
        }
        fclose($h);

        return $hasil;
    }

    /** Samakan penulisan judul kolom: huruf kecil, tanpa tanda baca pemisah, spasi tunggal. */
    public static function norm(string $s): string
    {
        $s = str_replace(["\xC2\xA0", '–', '—', '-', '|', '_', '*', '(', ')'], ' ', $s);

        return mb_strtolower(preg_replace('/\s+/u', ' ', trim($s)), 'UTF-8');
    }

    /** @return array<int,string> indeks kolom file => nama kolom tabel */
    public static function petaKolom(array $header, array $kolom): array
    {
        $cari = [];
        foreach ($kolom as $n => $k) {
            $cari[self::norm($k['label'])] = $n;
        }
        foreach ($kolom as $n => $k) {
            $cari[self::norm($n)] ??= $n;
        }
        $peta = [];
        foreach ($header as $i => $h) {
            $kunci = self::norm((string) $h);
            if ($kunci !== '' && isset($cari[$kunci]) && ! in_array($cari[$kunci], $peta, true)) {
                $peta[$i] = $cari[$kunci];
            }
        }

        return $peta;
    }

    private static function kosong(array $r): bool
    {
        foreach ($r as $v) {
            if ($v !== null && trim((string) $v) !== '') {
                return false;
            }
        }

        return true;
    }

    /**
     * @param array $baris  hasil baca()
     * @param array $kolom  kolom yang boleh diimpor: nama => [label, type, rules, options]
     * @return array{baris:array<int,array>,abaikan:array<int,string>,kolom:array<int,string>}
     *         baris = [nomor baris di file => [kolom => nilai]]
     * @throws \InvalidArgumentException
     */
    public static function olah(array $baris, array $kolom): array
    {
        $idx = null;
        foreach ($baris as $i => $r) {
            if (! self::kosong($r)) {
                $idx = $i;
                break;
            }
        }
        if ($idx === null) {
            throw new \InvalidArgumentException('File tidak berisi data.');
        }

        $peta = self::petaKolom($baris[$idx], $kolom);
        if (! $peta) {
            throw new \InvalidArgumentException('Judul kolom pada baris pertama tidak dikenali. Unduh templat, lalu isi sesuai kolom di dalamnya.');
        }
        $dikenal = array_values($peta);

        $kurang = [];
        foreach ($kolom as $n => $k) {
            if (in_array('required', explode('|', $k['rules']), true) && ! in_array($n, $dikenal, true)) {
                $kurang[] = $k['label'];
            }
        }
        if ($kurang) {
            throw new \InvalidArgumentException('Kolom wajib tidak ada di file: ' . implode(', ', $kurang) . '.');
        }

        $abaikan = [];
        foreach ($baris[$idx] as $i => $h) {
            if (! isset($peta[$i]) && trim((string) $h) !== '') {
                $abaikan[] = trim((string) $h);
            }
        }

        $hasil = [];
        for ($i = $idx + 1, $n = count($baris); $i < $n; $i++) {
            if (self::kosong($baris[$i])) {
                continue;
            }
            $d = array_fill_keys($dikenal, null);
            foreach ($peta as $c => $nama) {
                $d[$nama] = self::nilai($kolom[$nama], $baris[$i][$c] ?? null);
            }
            $hasil[$i + 1] = $d;
        }

        return ['baris' => $hasil, 'abaikan' => $abaikan, 'kolom' => $dikenal];
    }

    /** Ubah sel mentah menjadi nilai yang sesuai jenis kolom. Nilai yang tidak bisa diubah dibiarkan agar ditolak validasi. */
    public static function nilai(array $k, mixed $v): mixed
    {
        $tipe = $k['type'];
        if ($tipe === 'check') {
            return in_array(mb_strtolower(trim((string) $v), 'UTF-8'), ['1', 'ya', 'y', 'yes', 'true', '√', 'v', 'x', 'ok', 'benar'], true);
        }
        if ($v === null || (is_string($v) && trim($v) === '')) {
            return null;
        }
        if (is_bool($v)) {
            $v = $v ? '1' : '0';
        }

        switch ($tipe) {
            case 'number':
                $a = self::angka($v);
                return (is_float($a) && floor($a) == $a) ? (int) $a : $a;
            case 'decimal':
                return self::angka($v);
            case 'date':
                return self::tanggal($v);
            case 'select':
                $s = trim((string) $v);
                foreach ($k['options'] as $opsi) {
                    if (mb_strtolower((string) $opsi, 'UTF-8') === mb_strtolower($s, 'UTF-8')) {
                        return (string) $opsi;
                    }
                }
                return $s;
            default:
                if (is_float($v) && floor($v) == $v && abs($v) < 1e15) {
                    return sprintf('%.0f', $v);   // NIDN/NUPTK yang terbaca sebagai angka
                }
                return trim((string) $v);
        }
    }

    private static function angka(mixed $v): mixed
    {
        if (is_int($v) || is_float($v)) {
            return $v;
        }
        $s = str_replace([' ', "\xC2\xA0"], '', trim((string) $v));
        if (preg_match('/^-?\d{1,3}(\.\d{3})+(,\d+)?$/', $s)) {            // 1.234,56
            $s = str_replace(['.', ','], ['', '.'], $s);
        } elseif (preg_match('/^-?\d+,\d+$/', $s)) {                        // 12,5
            $s = str_replace(',', '.', $s);
        } elseif (preg_match('/^-?\d{1,3}(,\d{3})+(\.\d+)?$/', $s)) {       // 1,234.56
            $s = str_replace(',', '', $s);
        }

        return is_numeric($s) ? $s + 0 : $v;
    }

    private static function tanggal(mixed $v): mixed
    {
        if (is_int($v) || is_float($v) || (is_string($v) && preg_match('/^\d{5}(\.\d+)?$/', trim($v)))) {
            $hari = (int) floor((float) $v);
            if ($hari > 0 && $hari < 80000) {   // nomor seri tanggal Excel
                return (new \DateTimeImmutable('1899-12-30'))->modify('+' . $hari . ' days')->format('Y-m-d');
            }
        }
        $s = trim((string) $v);
        foreach (['Y-m-d', 'Y-m-d H:i:s', 'd/m/Y', 'd-m-Y', 'd.m.Y', 'j/n/Y', 'j-n-Y'] as $f) {
            $d = \DateTimeImmutable::createFromFormat('!' . $f, $s);
            if ($d && $d->format($f) === $s) {
                return $d->format('Y-m-d');
            }
        }

        return $s;
    }

    // ------------------------------------------------------------------ templat

    private static function jenis(array $k): string
    {
        return match ($k['type']) {
            'number'   => 'Angka bulat',
            'decimal'  => 'Angka (boleh desimal)',
            'date'     => 'Tanggal (YYYY-MM-DD atau DD/MM/YYYY)',
            'check'    => 'Ya atau kosong',
            'select'   => 'Pilihan: ' . implode(', ', $k['options']),
            'url'      => 'Link (diawali http:// atau https://)',
            'textarea' => 'Teks panjang',
            default    => 'Teks',
        };
    }

    public static function templatCsv(array $kolom): string
    {
        $h = fopen('php://temp', 'r+');
        fputcsv($h, array_column($kolom, 'label'), ';', '"', '');
        rewind($h);

        return "\xEF\xBB\xBF" . stream_get_contents($h);
    }

    /** Berkas .xlsx: lembar "Data" (judul kolom) dan lembar "Petunjuk". Hanya dipanggil bila adaXlsx(). */
    public static function templatXlsx(string $judul, array $kolom): string
    {
        $book = new \PhpOffice\PhpSpreadsheet\Spreadsheet();
        $ws = $book->getActiveSheet();
        $ws->setTitle('Data');
        $i = 0;
        foreach ($kolom as $k) {
            $i++;
            $huruf = \PhpOffice\PhpSpreadsheet\Cell\Coordinate::stringFromColumnIndex($i);
            $ws->setCellValue($huruf . '1', $k['label']);
            $ws->getColumnDimension($huruf)->setAutoSize(true);
        }
        if ($i > 0) {
            $akhir = \PhpOffice\PhpSpreadsheet\Cell\Coordinate::stringFromColumnIndex($i);
            $ws->getStyle('A1:' . $akhir . '1')->getFont()->setBold(true);
        }
        $ws->freezePane('A2');

        $p = $book->createSheet();
        $p->setTitle('Petunjuk');
        $p->setCellValue('A1', 'Petunjuk impor: ' . $judul);
        $p->getStyle('A1')->getFont()->setBold(true);
        $p->setCellValue('A2', 'Isi data mulai baris 2 pada lembar "Data". Jangan mengubah judul kolom pada baris 1. Data baru DITAMBAHKAN; baris yang sudah ada tidak diubah.');
        $p->setCellValue('A4', 'Kolom');
        $p->setCellValue('B4', 'Jenis isian');
        $p->setCellValue('C4', 'Wajib');
        $p->getStyle('A4:C4')->getFont()->setBold(true);
        $r = 5;
        foreach ($kolom as $k) {
            $p->setCellValue('A' . $r, $k['label']);
            $p->setCellValue('B' . $r, self::jenis($k));
            $p->setCellValue('C' . $r, in_array('required', explode('|', $k['rules']), true) ? 'Ya' : '');
            $r++;
        }
        foreach (['A', 'B', 'C'] as $c) {
            $p->getColumnDimension($c)->setAutoSize(true);
        }
        $book->setActiveSheetIndex(0);

        $tmp = tempnam(sys_get_temp_dir(), 'lkps');
        try {
            \PhpOffice\PhpSpreadsheet\IOFactory::createWriter($book, 'Xlsx')->save($tmp);

            return (string) file_get_contents($tmp);
        } finally {
            @unlink($tmp);
        }
    }
}
EOF

tulis app/Http/Controllers/LkpsImporController.php <<'EOF'
<?php

namespace App\Http\Controllers;

use App\Support\Lkps;
use App\Support\LkpsImporFile;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

/**
 * Impor data SATU tabel LKPS dari Excel/CSV. Hanya MENAMBAH baris; bila ada satu baris
 * yang tidak valid, tidak ada baris yang disimpan (semua atau tidak sama sekali).
 */
class LkpsImporController extends Controller
{
    /** Kolom yang bisa diisi lewat file: bukan lampiran berkas dan bukan kolom total otomatis. */
    private function kolomImpor(string $tabel): array
    {
        $total = array_keys(Lkps::definisi($tabel)['total'] ?? []);

        return array_filter(
            Lkps::kolom($tabel),
            fn ($k, $n) => $k['type'] !== 'file' && ! in_array($n, $total, true),
            ARRAY_FILTER_USE_BOTH
        );
    }

    public function form(string $tabel)
    {
        return view('lkps.impor', [
            'tabel'    => $tabel,
            'def'      => Lkps::definisi($tabel),
            'kelompok' => Lkps::namaKelompok($tabel),
            'kolom'    => $this->kolomImpor($tabel),
            'xlsx'     => LkpsImporFile::adaXlsx(),
            'maks'     => LkpsImporFile::MAKS_BARIS,
        ]);
    }

    public function templat(Request $request, string $tabel)
    {
        $def = Lkps::definisi($tabel);
        $kolom = $this->kolomImpor($tabel);
        $dasar = 'templat_lkps_' . $tabel;

        if ($request->query('format') !== 'csv' && LkpsImporFile::adaXlsx()) {
            try {
                return response(LkpsImporFile::templatXlsx($def['judul'], $kolom), 200, [
                    'Content-Type'        => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                    'Content-Disposition' => 'attachment; filename="' . $dasar . '.xlsx"',
                ]);
            } catch (\Throwable $e) {
                // gagal membuat .xlsx: lanjut ke CSV
            }
        }

        return response(LkpsImporFile::templatCsv($kolom), 200, [
            'Content-Type'        => 'text/csv; charset=UTF-8',
            'Content-Disposition' => 'attachment; filename="' . $dasar . '.csv"',
        ]);
    }

    public function proses(Request $request, string $tabel)
    {
        $def = Lkps::definisi($tabel);
        $request->validate(['berkas' => ['required', 'file', 'max:' . Lkps::MAKS_LAMPIRAN_KB]], [], ['berkas' => 'File impor']);

        $file = $request->file('berkas');
        $ext = strtolower($file->getClientOriginalExtension());
        if (! in_array($ext, ['xlsx', 'xls', 'csv', 'txt'], true)) {
            return back()->withErrors(['berkas' => 'Format file harus .xlsx, .xls, atau .csv.']);
        }

        $kolom = $this->kolomImpor($tabel);
        try {
            $baris = LkpsImporFile::baca($file->getRealPath(), $ext);
            if (count($baris) > LkpsImporFile::MAKS_BARIS + 1) {
                throw new \InvalidArgumentException('Terlalu banyak baris (maksimal ' . LkpsImporFile::MAKS_BARIS . ' baris data per impor).');
            }
            $hasil = LkpsImporFile::olah($baris, $kolom);
        } catch (\Throwable $e) {
            return back()->withErrors(['berkas' => $e->getMessage()]);
        }
        if (! $hasil['baris']) {
            return back()->withErrors(['berkas' => 'Tidak ada baris data di bawah judul kolom.']);
        }

        // Periksa SEMUA baris dengan aturan yang sama seperti formulir "Tambah data".
        $aturan = array_intersect_key(Lkps::rules($tabel), array_flip($hasil['kolom']));
        $nama = Lkps::label($tabel);
        $galat = [];
        foreach ($hasil['baris'] as $no => $data) {
            $v = Validator::make($data, $aturan, [], $nama);
            if ($v->fails()) {
                $galat[] = "Baris {$no}: " . implode('; ', $v->errors()->all());
                if (count($galat) >= 30) {
                    $galat[] = 'Pemeriksaan dihentikan setelah 30 baris bermasalah.';
                    break;
                }
            }
        }
        if ($galat) {
            return back()
                ->withErrors(['berkas' => 'Tidak ada data yang disimpan karena ada baris yang tidak valid. Perbaiki file lalu unggah ulang.'])
                ->with('impor_galat', $galat);
        }

        $userId = $request->user()?->id;
        $now = now();
        $siap = [];
        foreach ($hasil['baris'] as $data) {
            foreach ($def['total'] ?? [] as $target => $sumber) {
                $data[$target] = array_sum(array_map(fn ($c) => (float) ($data[$c] ?? 0), $sumber));
            }
            $siap[] = $data + ['created_by' => $userId, 'created_at' => $now, 'updated_at' => $now];
        }
        DB::transaction(function () use ($tabel, $siap) {
            foreach (array_chunk($siap, 200) as $bagian) {
                DB::table(Lkps::namaTabel($tabel))->insert($bagian);
            }
        });

        $pesan = count($siap) . ' baris berhasil diimpor.'
            . ($hasil['abaikan'] ? ' Kolom yang tidak dikenali dan diabaikan: ' . implode(', ', $hasil['abaikan']) . '.' : '');
        $tujuan = ! empty($def['tersembunyi'])
            ? redirect()->to(route('lkps.isian.index') . '#dosen-homebase')
            : redirect()->route('lkps.tabel.index', $tabel);

        return $tujuan->with('ok', $pesan);
    }
}
EOF

tulis resources/views/lkps/impor.blade.php <<'EOF'
@extends('layout')
@section('title', 'Impor Excel - ' . $def['judul'])

@section('content')
@include('lkps._gaya')
<p class="lk-crumb">
    <a href="{{ route('lkps.daftar') }}" class="link-secondary">LKPS</a> / {{ $kelompok }} /
    <a href="{{ route('lkps.tabel.index', $tabel) }}" class="link-secondary">{{ $def['judul'] }}</a>
</p>
<h1 class="mb-1">Impor data dari Excel</h1>
<p class="text-secondary mb-4" style="max-width: 75ch">
    Data pada file <strong>ditambahkan</strong> ke tabel ini; baris yang sudah ada tidak diubah atau dihapus.
    Semua baris diperiksa lebih dulu: bila ada satu baris yang tidak valid, tidak ada data yang disimpan.
</p>

<div class="row g-3">
    <div class="col-12 col-lg-5">
        <section class="lk-panel h-100">
            <h2 class="mb-2">1. Unduh templat</h2>
            <p class="small text-secondary">Templat berisi judul kolom tabel ini. Isi mulai baris ke-2 dan jangan mengubah judul kolom.</p>
            <div class="d-flex flex-wrap gap-2 mb-4">
                @if ($xlsx)
                    <a href="{{ route('lkps.tabel.templat', $tabel) }}" class="btn btn-sm btn-outline-primary">Unduh templat Excel (.xlsx)</a>
                @endif
                <a href="{{ route('lkps.tabel.templat', [$tabel, 'format' => 'csv']) }}" class="btn btn-sm btn-outline-secondary">Unduh templat CSV</a>
            </div>
            @unless ($xlsx)
                <div class="alert alert-warning small">
                    Pustaka PhpSpreadsheet belum terpasang, jadi hanya file <strong>CSV</strong> yang bisa diimpor
                    (di Excel: Simpan Sebagai &rarr; CSV). Untuk impor .xlsx jalankan
                    <code>composer require phpoffice/phpspreadsheet</code>.
                </div>
            @endunless

            <h2 class="mb-2">2. Unggah file</h2>
            <form method="POST" action="{{ route('lkps.tabel.impor.proses', $tabel) }}" enctype="multipart/form-data">
                @csrf
                <input type="file" name="berkas" required
                       accept="{{ $xlsx ? '.xlsx,.xls,.csv,.txt' : '.csv,.txt' }}"
                       class="form-control @error('berkas') is-invalid @enderror">
                <div class="form-text">Maksimal {{ $maks }} baris data per impor. Lampiran Bukti berupa berkas tidak bisa diimpor; gunakan kolom link atau unggah dari menu Ubah data.</div>
                <div class="d-flex gap-2 mt-3">
                    <button class="btn btn-primary">Impor data</button>
                    <a href="{{ route('lkps.tabel.index', $tabel) }}" class="btn btn-outline-secondary">Batal</a>
                </div>
            </form>

            @if (session('impor_galat'))
                <div class="alert alert-danger small mt-3 mb-0">
                    <strong>Baris yang perlu diperbaiki:</strong>
                    <ul class="mb-0 mt-1">
                        @foreach (session('impor_galat') as $g)
                            <li>{{ $g }}</li>
                        @endforeach
                    </ul>
                </div>
            @endif
        </section>
    </div>

    <div class="col-12 col-lg-7">
        <section class="lk-panel h-100">
            <h2 class="mb-2">Kolom yang dibaca</h2>
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <thead><tr><th>Judul kolom</th><th>Jenis isian</th><th>Wajib</th></tr></thead>
                    <tbody>
                        @foreach ($kolom as $n => $k)
                            <tr>
                                <td>{{ $k['label'] }}</td>
                                <td class="small text-secondary">
                                    @switch($k['type'])
                                        @case('number') Angka bulat @break
                                        @case('decimal') Angka (boleh desimal) @break
                                        @case('date') Tanggal (YYYY-MM-DD atau DD/MM/YYYY) @break
                                        @case('check') Ya atau kosong @break
                                        @case('select') Pilihan: {{ implode(', ', $k['options']) }} @break
                                        @case('url') Link (diawali http:// atau https://) @break
                                        @case('textarea') Teks panjang @break
                                        @default Teks
                                    @endswitch
                                </td>
                                <td>{{ in_array('required', explode('|', $k['rules']), true) ? 'Ya' : '' }}</td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
        </section>
    </div>
</div>
@endsection
EOF

tulis resources/views/lkps/hero.blade.php <<'EOF'
@php $lkh = \App\Support\LkpsRingkasan::data(); @endphp
@if($lkh['tersedia'])<div><b>{{ $lkh['persen'] }}%</b>Kelengkapan LKPS</div>@endif
EOF

tulis resources/views/lkps/isian.blade.php <<'EOF'
@extends('layout')
@section('title', 'Identitas UPPS dan Program Studi')

@section('content')
@include('lkps._gaya')
<p class="lk-crumb"><a href="{{ route('lkps.daftar') }}" class="link-secondary">LKPS</a></p>
<h1 class="mb-1">Identitas UPPS dan Program Studi</h1>
<p class="text-secondary mb-4" style="max-width: 70ch">
    Isian di luar 31 tabel: sheet Identitas pada template, ditambah Daftar Dosen Homebase.
    Nilai identitas ikut diekspor dan diimpor bersama data tabel.
</p>

<form method="POST" action="{{ route('lkps.isian.simpan') }}">
    @csrf
    <div class="row g-3">
        @foreach ($grup as $judulGrup => $daftar)
            <div class="col-12">
                <section class="lk-panel h-100">
                    <h2 class="mb-3">{{ $judulGrup }}</h2>
                    <div class="row g-2">
                    @foreach ($daftar as $kunci => [$label, $tipe])
                        <div class="col-12 col-md-6">
                            <label for="i_{{ $kunci }}" class="form-label small fw-semibold mb-1">{{ $label }}</label>
                            @auth
                                <input id="i_{{ $kunci }}" name="{{ $kunci }}" type="{{ $tipe === 'number' ? 'number' : 'text' }}"
                                       @if ($tipe === 'number') min="0" step="1" @endif
                                       value="{{ old($kunci, $nilai[$kunci] ?? '') }}"
                                       class="form-control form-control-sm @error($kunci) is-invalid @enderror">
                                @error($kunci) <div class="invalid-feedback">{{ $message }}</div> @enderror
                            @else
                                <div id="i_{{ $kunci }}" class="form-control form-control-sm bg-light">{{ ($nilai[$kunci] ?? '') !== '' ? $nilai[$kunci] : '–' }}</div>
                            @endauth
                        </div>
                    @endforeach
                    </div>
                </section>
            </div>
        @endforeach
    </div>
    @auth
        <div class="mt-3"><button class="btn btn-primary">Simpan isian</button></div>
    @endauth
</form>

<section class="lk-panel mt-4" id="dosen-homebase">
    <div class="d-flex flex-wrap justify-content-between align-items-center gap-2 mb-3">
        <h2 class="mb-0">Daftar Dosen Homebase</h2>
        @if ($dosenAda)
            <div class="d-flex gap-2">
                <a href="{{ route('lkps.tabel.index', $slugDosen) }}" class="btn btn-sm btn-outline-secondary">Kelola daftar</a>
                @auth
                    <a href="{{ route('lkps.tabel.create', $slugDosen) }}" class="btn btn-sm btn-primary">Tambah dosen</a>
                @endauth
            </div>
        @endif
    </div>

    @if (! $dosenAda)
        <div class="alert alert-warning mb-0">Tabel Daftar Dosen Homebase belum dibuat. Jalankan <code>php artisan lkps:sinkron</code> di folder aplikasi.</div>
    @else
        <div class="table-responsive">
            <table class="table table-sm align-middle mb-0">
                <thead>
                    <tr>
                        <th style="width:3rem">No</th>
                        <th>Nama Dosen</th><th>NIDN</th><th>NUPTK</th><th>Golongan</th><th>Jabatan Fungsional Akademik</th>
                        <th>Pendidikan S1</th><th>Pendidikan S2</th><th>Pendidikan S3</th>
                        <th>Keilmuan</th><th>Lampiran Bukti</th>
                        @auth<th class="text-end">Aksi</th>@endauth
                    </tr>
                </thead>
                <tbody>
                    @forelse ($dosen as $i => $d)
                        <tr>
                            <td>{{ $i + 1 }}</td>
                            <td class="fw-semibold">{{ $d->nama_dosen }}</td>
                            <td>{{ $d->nidn ?: '–' }}</td>
                            <td>{{ $d->nuptk ?: '–' }}</td>
                            <td>{{ $d->golongan ?: '–' }}</td>
                            <td>{{ $d->jabatan_fungsional ?: '–' }}</td>
                            <td>{{ $d->pend_s1 ?: '–' }}</td>
                            <td>{{ $d->pend_s2 ?: '–' }}</td>
                            <td>{{ $d->pend_s3 ?: '–' }}</td>
                            <td>{{ $d->keilmuan ?: '–' }}</td>
                            <td>
                                @if (filled($d->lampiran_bukti ?? null))
                                    <a href="{{ \App\Support\Lkps::urlLampiran($slugDosen, (int) $d->id) }}" target="_blank" rel="noopener">Lihat</a>
                                @endif
                                @if (filled($d->lampiran_link ?? null) && preg_match('#^https?://#i', $d->lampiran_link))
                                    <a href="{{ $d->lampiran_link }}" target="_blank" rel="noopener">Buka link</a>
                                @endif
                                @if (! filled($d->lampiran_bukti ?? null) && ! filled($d->lampiran_link ?? null))
                                    –
                                @endif
                            </td>
                            @auth
                                <td class="text-end text-nowrap">
                                    <a href="{{ route('lkps.tabel.edit', [$slugDosen, $d->id]) }}" class="btn btn-sm btn-outline-secondary">Ubah</a>
                                    <form method="POST" action="{{ route('lkps.tabel.destroy', [$slugDosen, $d->id]) }}" class="d-inline"
                                          onsubmit="return confirm('Hapus dosen ini? Data dan lampirannya tidak bisa dikembalikan.')">
                                        @csrf
                                        @method('DELETE')
                                        <button class="btn btn-sm btn-outline-danger">Hapus</button>
                                    </form>
                                </td>
                            @endauth
                        </tr>
                    @empty
                        <tr><td colspan="{{ auth()->check() ? 12 : 11 }}" class="text-secondary text-center py-3">Belum ada dosen homebase.@auth Klik &ldquo;Tambah dosen&rdquo; untuk mengisi.@endauth</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    @endif
</section>
@endsection
EOF

tulis resources/views/lkps/lampiran.blade.php <<'EOF'
@extends('layout')
@section('title', $label . ' - ' . $def['judul'])

@section('content')
@include('lkps._gaya')
<div class="d-flex flex-wrap justify-content-between align-items-end gap-3 mb-3">
    <div>
        <p class="lk-crumb">
            <a href="{{ route('lkps.tabel.index', $tabel) }}" class="link-secondary">{{ $def['judul'] }}</a>
        </p>
        <h1>{{ $label }}</h1>
        @if ($ringkas !== '')
            <p class="small text-secondary mb-0 mt-1">{{ $ringkas }}</p>
        @endif
    </div>
    <div class="d-flex gap-2">
        <a href="{{ $src }}" target="_blank" rel="noopener" class="btn btn-sm btn-outline-secondary">
            Buka di tab baru
        </a>
        <a href="{{ route('lkps.tabel.index', $tabel) }}" class="btn btn-sm btn-outline-secondary">Kembali ke tabel</a>
    </div>
</div>

<div class="lk-panel p-2">
    @if (str_starts_with($mime, 'image/'))
        <img src="{{ $src }}" alt="{{ $label }}" class="d-block mx-auto" style="max-width: 100%; max-height: 80vh">
    @elseif ($mime === 'application/pdf')
        <iframe src="{{ $src }}" title="{{ $label }}" style="width: 100%; height: 80vh; border: 0"></iframe>
    @else
        <p class="text-center text-secondary my-5">Jenis berkas ini tidak bisa dipratinjau di browser.</p>
    @endif
</div>
@endsection
EOF

tulis resources/views/lkps/tabel.blade.php <<'EOF'
@extends('layout')
@section('title', $def['judul'])

@section('content')
@include('lkps._gaya')
<div class="d-flex flex-wrap justify-content-between align-items-end gap-3 mb-3">
    <div>
        <p class="lk-crumb"><a href="{{ route('lkps.daftar') }}" class="link-secondary">LKPS</a> / {{ $kelompok }}</p>
        <h1>{{ $def['judul'] }}</h1>
        @if (! empty($def['keterangan']))
            <p class="small text-secondary mb-0 mt-1">{{ $def['keterangan'] }}</p>
        @endif
    </div>
    <div class="d-flex gap-2">
        <a href="{{ route('lkps.tabel.export', $tabel) }}" class="btn btn-sm btn-outline-secondary">
            Ekspor CSV
        </a>
        @auth
            <a href="{{ route('lkps.tabel.create', $tabel) }}" class="btn btn-sm btn-primary">
                Tambah data
            </a>
            <a href="{{ route('lkps.tabel.impor', $tabel) }}" class="btn btn-sm btn-outline-primary">
                Impor Excel
            </a>
        @endauth
    </div>
</div>

<form method="GET" class="d-flex gap-2 mb-3" style="max-width: 420px" role="search">
    <label for="cari" class="visually-hidden">Cari di tabel ini</label>
    <input id="cari" name="q" value="{{ $cari }}" class="form-control form-control-sm" placeholder="Cari di tabel ini">
    <button class="btn btn-sm btn-outline-secondary">Cari</button>
    @if ($cari !== '')
        <a href="{{ route('lkps.tabel.index', $tabel) }}" class="btn btn-sm btn-link">Reset</a>
    @endif
</form>

@if ($rows->isEmpty())
    <div class="lk-panel text-center py-5">
        @if ($cari !== '')
            <p class="mb-0">Tidak ada data yang cocok dengan "{{ $cari }}".</p>
        @else
            <p class="mb-3">Tabel ini belum berisi data.</p>
            @auth
                <a href="{{ route('lkps.tabel.create', $tabel) }}" class="btn btn-primary">Tambah data pertama</a>
            @else
                <a href="{{ route('login') }}" class="btn btn-outline-secondary">Masuk untuk menambah data</a>
            @endauth
        @endif
    </div>
@else
    <div class="lk-wrap table-responsive">
        <table class="table table-hover align-middle">
            <thead>
            @foreach ($header['baris'] as $i => $baris)
                <tr>
                    @if ($i === 0)
                        <th rowspan="{{ $header['depth'] }}">No</th>
                    @endif
                    @foreach ($baris as $c)
                        <th colspan="{{ $c['colspan'] }}" rowspan="{{ $c['rowspan'] }}" @class(['text-center' => $c['colspan'] > 1])>{{ $c['label'] }}</th>
                    @endforeach
                    @if ($i === 0)
                        @auth <th rowspan="{{ $header['depth'] }}" class="text-end">Aksi</th> @endauth
                    @endif
                </tr>
            @endforeach
            </thead>
            <tbody>
            @foreach ($rows as $row)
                <tr>
                    <td>{{ $rows->firstItem() + $loop->index }}</td>
                    @foreach ($kolom as $n => $k)
                        @php $v = $row->$n; @endphp
                        <td>
                            @if ($k['type'] === 'check')
                                {{ $v ? '√' : '' }}
                            @elseif ($v === null || $v === '')
                                <span class="text-secondary">–</span>
                            @elseif ($k['type'] === 'file')
                                <a href="{{ \App\Support\Lkps::urlLampiran($tabel, $row->id, $n) }}" target="_blank" rel="noopener" class="text-nowrap">
                                    Lihat bukti
                                </a>
                            @elseif ($k['type'] === 'url' && preg_match('#^https?://#i', $v))
                                <a href="{{ $v }}" target="_blank" rel="noopener">Buka tautan</a>
                            @elseif ($k['type'] === 'textarea')
                                {{ \Illuminate\Support\Str::limit($v, 80) }}
                            @elseif (in_array($k['type'], ['number', 'decimal'], true))
                                {{ \App\Support\Lkps::angka($v) }}
                            @else
                                {{ $v }}
                            @endif
                        </td>
                    @endforeach
                    @auth
                        <td class="text-end text-nowrap">
                            <a href="{{ route('lkps.tabel.edit', [$tabel, $row->id]) }}" class="btn btn-sm btn-outline-secondary">Ubah</a>
                            <form method="POST" action="{{ route('lkps.tabel.destroy', [$tabel, $row->id]) }}" class="d-inline"
                                  onsubmit="return confirm('Hapus baris ini? Data tidak bisa dikembalikan.')">
                                @csrf
                                @method('DELETE')
                                <button class="btn btn-sm btn-outline-danger">Hapus</button>
                            </form>
                        </td>
                    @endauth
                </tr>
            @endforeach
            </tbody>
            @if ($ringkasan)
                <tfoot>
                @foreach ($ringkasan as $labelRingkasan => $nilai)
                    <tr class="ringkasan">
                        <th>{{ $labelRingkasan }}</th>
                        @foreach ($kolom as $n => $k)
                            <td>{{ array_key_exists($n, $nilai) && $nilai[$n] !== null ? \App\Support\Lkps::angka($nilai[$n]) : '' }}</td>
                        @endforeach
                        @auth <td></td> @endauth
                    </tr>
                @endforeach
                </tfoot>
            @endif
        </table>
    </div>
    <div class="mt-3">{{ $rows->links('pagination::bootstrap-5') }}</div>
@endif
@endsection
EOF

# template Excel opsional (disalin hanya bila belum ada)
if [ -n "$LKPS_TEMPLATE" ]; then
  if [ -f "$LKPS_TEMPLATE" ]; then
    mkdir -p storage/app/lkps
    [ -f storage/app/lkps/template.xlsx ] && [ "$TIMPA" != 1 ] && echo "  (template sudah ada, dilewati)" || { cp "$LKPS_TEMPLATE" storage/app/lkps/template.xlsx; echo "  OK  template Excel disalin"; }
  else echo "  PERINGATAN: LKPS_TEMPLATE '$LKPS_TEMPLATE' tidak ditemukan."; fi
fi
# tahun TS pada .env (hanya ditambah bila belum ada)
if [ -f .env ] && ! grep -q '^LKPS_TAHUN_TS=' .env; then
  printf '\n# Tahun akademik TS untuk LKPS\nLKPS_TAHUN_TS="%s"\n' "$LKPS_TAHUN_TS" >> .env
  echo "  OK  .env: LKPS_TAHUN_TS=$LKPS_TAHUN_TS"
fi
for f in config/lkps.php config/lkps_excel.php app/Support/Lkps.php app/Support/LkpsExcel.php app/Support/LkpsData.php app/Support/LkpsRingkasan.php \
         "$MIG" app/Console/Commands/LkpsSinkron.php app/Console/Commands/LkpsImpor.php app/Console/Commands/LkpsEkspor.php \
         app/Http/Controllers/LkpsController.php app/Http/Controllers/LkpsExcelController.php app/Http/Controllers/LkpsIsianController.php app/Http/Controllers/LkpsLampiranController.php; do
  php -l "$f" >/dev/null || { echo "GAGAL: kesalahan sintaks pada $f"; exit 1; }
done
echo "  OK  sintaks semua berkas PHP"

# ---------- 5. TABEL LKPS (hanya menambah) ----------
echo "[5/7] Membuat tabel lkps_* (hanya migration LKPS yang dijalankan)..."
php artisan config:clear >/dev/null 2>&1 || true
if ! php artisan migrate --force --path="$MIG"; then
  echo ""
  echo "GAGAL membuat tabel. Data Anda tidak berubah dan tampilan aplikasi belum diubah."
  echo "Periksa hak CREATE pada user database, lalu jalankan ulang skrip ini (aman diulang)."
  exit 1
fi
php artisan lkps:sinkron

# ---------- 6. ROUTE, MENU, DASHBOARD (disisipi, bukan ditimpa) ----------
echo "[6/7] Menyisipkan route, menu, dan dashboard..."
if grep -q "Route::prefix(.lkps.)" "$R"; then
  echo "  (route LKPS sudah ada, dilewati)"
else
cat >> "$R" <<'EOF'

// ===== LKPS: baca publik; tambah/ubah/hapus wajib login; impor Excel & unggah template khusus admin =====
Route::prefix('lkps')->name('lkps.')->group(function () {
    $admin = class_exists(\App\Http\Middleware\HanyaAdmin::class) ? ['auth', \App\Http\Middleware\HanyaAdmin::class] : ['auth'];

    Route::get('/', [\App\Http\Controllers\LkpsController::class, 'daftar'])->name('daftar');

    Route::get('/isian', [\App\Http\Controllers\LkpsIsianController::class, 'index'])->name('isian.index');
    Route::post('/isian', [\App\Http\Controllers\LkpsIsianController::class, 'simpan'])->middleware('auth')->name('isian.simpan');

    Route::get('/excel', [\App\Http\Controllers\LkpsExcelController::class, 'index'])->name('excel.index');
    Route::get('/excel/ekspor', [\App\Http\Controllers\LkpsExcelController::class, 'ekspor'])->name('excel.ekspor');
    Route::middleware($admin)->group(function () {
        Route::post('/excel/template', [\App\Http\Controllers\LkpsExcelController::class, 'unggahTemplate'])->name('excel.template');
        Route::post('/excel/impor', [\App\Http\Controllers\LkpsExcelController::class, 'impor'])->name('excel.impor');
    });

    Route::get('/lampiran/{tabel}/{id}/{kolom?}', [\App\Http\Controllers\LkpsLampiranController::class, 'lihat'])
        ->whereNumber('id')->where(['tabel' => '[a-z0-9_]+', 'kolom' => '[a-z0-9_]+'])->name('lampiran.lihat');
    Route::get('/lampiran/{tabel}/{id}/{kolom}/berkas', [\App\Http\Controllers\LkpsLampiranController::class, 'berkas'])
        ->whereNumber('id')->where(['tabel' => '[a-z0-9_]+', 'kolom' => '[a-z0-9_]+'])->name('lampiran.berkas');

    Route::prefix('tabel/{tabel}')->name('tabel.')->where(['tabel' => '[a-z0-9_]+'])->group(function () {
        Route::get('/', [\App\Http\Controllers\LkpsController::class, 'index'])->name('index');
        Route::get('/ekspor', [\App\Http\Controllers\LkpsController::class, 'export'])->name('export');
        Route::middleware('auth')->group(function () {
            Route::get('/tambah', [\App\Http\Controllers\LkpsController::class, 'create'])->name('create');
            Route::post('/', [\App\Http\Controllers\LkpsController::class, 'store'])->name('store');
            Route::get('/{id}/ubah', [\App\Http\Controllers\LkpsController::class, 'edit'])->whereNumber('id')->name('edit');
            Route::put('/{id}', [\App\Http\Controllers\LkpsController::class, 'update'])->whereNumber('id')->name('update');
            Route::delete('/{id}', [\App\Http\Controllers\LkpsController::class, 'destroy'])->whereNumber('id')->name('destroy');
            Route::get('/impor', [\App\Http\Controllers\LkpsImporController::class, 'form'])->name('impor');
            Route::get('/templat', [\App\Http\Controllers\LkpsImporController::class, 'templat'])->name('templat');
            Route::post('/impor', [\App\Http\Controllers\LkpsImporController::class, 'proses'])->name('impor.proses');
        });
    });
});
EOF
  php -l "$R" >/dev/null || { echo "GAGAL: routes/web.php tidak valid. Pulihkan dari $R.bak8"; exit 1; }
  echo "  OK  $R"
fi

# menu "LKPS" di bawah Data Induk (setelah sub menu Data Induk terakhir)
if grep -q "lkps.daftar" "$L"; then
  echo "  (menu LKPS sudah ada, dilewati)"
elif grep -q 'datainduk.index' "$L"; then
  M=$(cat <<'EOF'
      @if(Route::has('lkps.daftar'))
      <a class="mi sub {{ request()->routeIs('lkps.*') ? 'on' : '' }}" href="{{ route('lkps.daftar') }}">LKPS</a>
      @endif
EOF
)
  export M
  perl -0pi -e 's/((?:^[ \t]*<a class="mi sub [^\n]*datainduk\.index[^\n]*<\/a>\n)+)/$1$ENV{M}\n/m' "$L"
  grep -q "lkps.daftar" "$L" && echo "  OK  menu LKPS di bawah Data Induk" || echo "  PERINGATAN: menu tidak terpasang (pola layout berbeda). LKPS tetap dapat dibuka di /lkps."
else
  echo "  PERINGATAN: menu Data Induk tidak ditemukan di layout. Tambahkan tautan ke route('lkps.daftar') secara manual; LKPS dapat dibuka di /lkps."
fi

# Dashboard Akreditasi: angka "Kelengkapan LKPS" di kartu utama + bagian ringkasan
if [ -f "$DBV" ] && ! grep -q "lkps\." "$DBV"; then
  perl -0pi -e 's/(^[ \t]*<div><b>\{\{ \$total\[\x27dokumen\x27\] \}\}%<\/b>Kelengkapan dokumen<\/div>\n)/$1    \@includeIf(\x27lkps.hero\x27)\n/m' "$DBV"
  perl -0pi -e 's/\n\@endsection\s*\z/\n\n\@includeIf(\x27lkps.dashboard\x27)\n\@endsection\n/' "$DBV"
  grep -q "lkps.hero" "$DBV" && echo "  OK  angka LKPS di kartu utama dashboard" || echo "  PERINGATAN: kartu utama dashboard berbeda dari yang diharapkan; angka LKPS pada kartu utama dilewati."
  grep -q "lkps.dashboard" "$DBV" && echo "  OK  bagian Kelengkapan LKPS di dashboard" || echo "  PERINGATAN: bagian LKPS di dashboard tidak terpasang (tambahkan @includeIf('lkps.dashboard') sebelum @endsection)."
elif [ -f "$DBV" ]; then
  echo "  (dashboard sudah memuat LKPS, dilewati)"
else
  echo "  PERINGATAN: $DBV tidak ditemukan; dashboard tidak diubah."
fi

# ---------- 7. SELESAI ----------
echo "[7/7] Membersihkan cache..."
php artisan optimize:clear >/dev/null 2>&1 || true
echo ""
echo "============================================================"
echo " LKPS BERHASIL DITAMBAHKAN"
echo "============================================================"
echo " Menu    : sidebar > Data Induk > LKPS  (alamat: /lkps)"
echo " Dashboard: kelengkapan LKPS tampil di Dashboard Akreditasi"
echo " Hak akses: lihat = publik; tambah/ubah/hapus = login; impor Excel & unggah template = admin"
echo " Excel   : menu LKPS > Impor & ekspor Excel (unggah template resmi LKPS .xlsx lebih dulu)"
echo " Perintah: php artisan lkps:sinkron | lkps:impor file.xlsx [--ganti] | lkps:ekspor [hasil.xlsx]"
echo " Cadangan: *.bak8 dan storage/app/cadangan-sebelum-lkps-*.sql"
echo " Jika memakai cache produksi: php artisan config:cache && php artisan route:cache && php artisan view:cache"
