#!/usr/bin/env bash
# =====================================================================
# PANEL ADMIN (dashboard visualisasi gaya admin klasik, berbasis grafik vektor SVG)
# Sistem Informasi Akreditasi Program Studi Teknologi Informasi
# Sekolah Vokasi Universitas Tiga Serangkai
#
# Menambah menu "Panel Admin" (di bawah Dashboard) berisi:
#   - 4 kartu statistik berikon + sparkline (kriteria, butir, dokumen, pengguna/Data Induk)
#   - Tren aktivitas 12 bulan (grafik area), kelengkapan (grafik radial)
#   - Progres per kriteria, dokumen Data Induk per kategori
#   - Aktivitas terbaru (linimasa), dokumen terbaru, dan daftar "Perlu perhatian"
#   - Tombol aksi cepat (untuk yang sudah login)
#
# AMAN: hanya MEMBACA data. Tidak ada tabel baru, migration, atau perubahan data.
# routes/web.php dan layout hanya disisipi blok kecil (cadangan *.bak11).
# Data Induk dan LKPS dibaca otomatis bila terpasang. Aman diulang.
# Halaman ini memakai kelas Analitik (ikut dipasang bila belum ada).
#
# Pemakaian (di root proyek):  bash tambah-panel.sh [--timpa]
#   --timpa   timpa berkas Panel yang sudah ada (yang lama dicadangkan *.bak11)
# =====================================================================
set -e
if [ ! -f artisan ]; then echo "Error: jalankan di root proyek Laravel."; exit 1; fi
TIMPA=0
for a in "$@"; do
  case "$a" in --timpa) TIMPA=1;; -h|--help) sed -n '2,22p' "$0"; exit 0;; *) echo "Opsi tidak dikenal: $a"; exit 1;; esac
done
R=routes/web.php
L=resources/views/layout.blade.php

echo "[1/3] Pemeriksaan..."
[ -f "$R" ] || { echo "Error: $R tidak ditemukan."; exit 1; }
if [ ! -f "$L" ] || ! grep -q "yield('content')" "$L"; then echo "Error: layout aplikasi tidak ditemukan atau tidak memakai @yield('content')."; exit 1; fi
command -v perl >/dev/null 2>&1 || { echo "Error: perl dibutuhkan."; exit 1; }
if ! grep -rqs "isi_kriteria" database/migrations; then echo "PERINGATAN: migration tabel isi_kriteria tidak ditemukan; Panel Admin membutuhkan tabel kriterias, isi_kriteria, dan dokumen."; fi
if ! grep -q "'isi'" "$R"; then echo "PERINGATAN: route isi.show tidak terdeteksi; tautan 'Buka' pada daftar Perlu perhatian mungkin tidak berfungsi."; fi
echo "  OK"

tulis() {   # tulis <path> (isi dari stdin). Berkas yang sudah ada tidak ditimpa kecuali --timpa
  local f="$1"
  if [ -f "$f" ] && [ "$TIMPA" != 1 ]; then cat >/dev/null; echo "  (sudah ada, dilewati) $f"; return 0; fi
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] && cp "$f" "$f.bak11"
  cat > "$f"
  echo "  OK  $f"
}

echo "[2/3] Menulis berkas Panel Admin..."
tulis app/Support/Analitik.php <<'EOF'
<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Pengolahan data untuk halaman Analitik. Hanya MEMBACA data yang sudah ada
 * (tabel kriterias, isi_kriteria, dokumen, Data Induk, dan tabel LKPS bila terpasang).
 */
class Analitik
{
    private const BULAN = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    private const PERIODE = [3, 6, 12];

    /** Narasi dianggap terisi bila ada teks, gambar, atau tabel. */
    public static function narasiTerisi($narasi): bool
    {
        $n = (string) $narasi;

        return trim(strip_tags($n)) !== '' || (bool) preg_match('/<(img|table)/i', $n);
    }

    public static function jenis(?string $file, ?string $link): string
    {
        if ($file) {
            $e = strtolower(pathinfo($file, PATHINFO_EXTENSION));

            return match (true) {
                $e === 'pdf'                                  => 'PDF',
                in_array($e, ['doc', 'docx'], true)           => 'Word',
                in_array($e, ['xls', 'xlsx', 'csv'], true)    => 'Excel',
                in_array($e, ['ppt', 'pptx'], true)           => 'PowerPoint',
                in_array($e, ['jpg', 'jpeg', 'png', 'gif', 'webp'], true) => 'Gambar',
                $e === 'zip'                                  => 'Arsip',
                default                                       => 'Lainnya',
            };
        }

        return $link ? 'Tautan' : 'Lainnya';
    }

    public static function data(int $bulan = 12, ?int $sekarang = null): array
    {
        $bulan = in_array($bulan, self::PERIODE, true) ? $bulan : 12;
        $now = $sekarang ?? time();

        $kriteria = DB::table('kriterias')->orderBy('kode')->get();
        $butirAll = DB::table('isi_kriteria')->get();
        $dokumen = DB::table('dokumen')->get();

        $jmlDok = [];
        foreach ($dokumen as $d) {
            $jmlDok[$d->isi_kriteria_id] = ($jmlDok[$d->isi_kriteria_id] ?? 0) + 1;
        }

        // ---------- per butir & per kriteria ----------
        $butir = [];
        foreach ($butirAll as $b) {
            $narasi = self::narasiTerisi($b->narasi);
            $nd = $jmlDok[$b->id] ?? 0;
            $p = max(0, min(100, (int) $b->persentase));
            $status = ($narasi && $nd > 0 && $p >= 80) ? 'siap' : ((! $narasi && $nd === 0 && $p === 0) ? 'belum' : 'sebagian');
            $butir[] = [
                'id' => $b->id, 'kriteria_id' => $b->kriteria_id, 'butir' => $b->butir, 'persen' => $p,
                'narasi' => $narasi, 'dok' => $nd, 'status' => $status,
                'gap' => (100 - $p) + ($narasi ? 0 : 30) + ($nd > 0 ? 0 : 30),
            ];
        }
        $per = [];
        foreach ($kriteria as $k) {
            $mine = array_values(array_filter($butir, fn ($b) => $b['kriteria_id'] === $k->id));
            $n = count($mine);
            $pct = fn (int $c) => $n ? (int) round($c / $n * 100) : 0;
            $per[] = [
                'id' => $k->id, 'kode' => $k->kode, 'nama' => $k->nama, 'n' => $n,
                'isian'   => $n ? (int) round(array_sum(array_column($mine, 'persen')) / $n) : 0,
                'narasi'  => $pct(count(array_filter($mine, fn ($b) => $b['narasi']))),
                'dokumen' => $pct(count(array_filter($mine, fn ($b) => $b['dok'] > 0))),
            ];
        }
        $avg = fn (string $f) => $per ? (int) round(array_sum(array_column($per, $f)) / count($per)) : 0;
        $total = ['isian' => $avg('isian'), 'narasi' => $avg('narasi'), 'dokumen' => $avg('dokumen')];
        $kesiapan = (int) round(($total['isian'] + $total['narasi'] + $total['dokumen']) / 3);

        $nB = count($butir);
        $siap = count(array_filter($butir, fn ($b) => $b['status'] === 'siap'));
        $belum = count(array_filter($butir, fn ($b) => $b['status'] === 'belum'));
        $status = ['siap' => $siap, 'sebagian' => $nB - $siap - $belum, 'belum' => $belum];
        $bernarasi = count(array_filter($butir, fn ($b) => $b['narasi']));
        $narasiDok = count(array_filter($butir, fn ($b) => $b['narasi'] && $b['dok'] > 0));
        $corong = [$nB, $bernarasi, $narasiDok, $siap];
        $tanpaDok = count(array_filter($butir, fn ($b) => $b['dok'] === 0));
        $tanpaNarasi = $nB - $bernarasi;

        // ---------- butir prioritas ----------
        $kode = array_column($per, 'kode', 'id');
        $pr = array_values(array_filter($butir, fn ($b) => $b['gap'] > 0));
        usort($pr, fn ($a, $b) => [$b['gap'], $kode[$a['kriteria_id']] ?? '', $a['butir']] <=> [$a['gap'], $kode[$b['kriteria_id']] ?? '', $b['butir']]);
        $prioritas = array_map(fn ($b) => $b + ['kode' => $kode[$b['kriteria_id']] ?? '-'], array_slice($pr, 0, 8));

        // ---------- kejadian bertanggal (untuk aktivitas) ----------
        $ts = fn ($v) => $v ? (int) strtotime((string) $v) : 0;
        $ev = ['dokumen' => [], 'datainduk' => [], 'lkps' => [], 'butir' => []];
        foreach ($dokumen as $d) { if ($t = $ts($d->created_at ?? null)) { $ev['dokumen'][] = $t; } }
        foreach ($butirAll as $b) { if ($t = $ts($b->updated_at ?? null)) { $ev['butir'][] = $t; } }

        // ---------- Data Induk (JSON atau tabel, lewat DataInduk) ----------
        $jenis = [];
        $tambahJenis = function (string $j) use (&$jenis) { $jenis[$j] = ($jenis[$j] ?? 0) + 1; };
        foreach ($dokumen as $d) { $tambahJenis(self::jenis($d->file_path, $d->link)); }
        $sebaran = [];
        if (class_exists(DataInduk::class)) {
            foreach (DataInduk::KATEGORI as $kode2 => $nama) {
                $docs = DataInduk::semua($kode2);
                $sebaran[] = ['label' => $nama, 'n' => count($docs)];
                foreach ($docs as $x) {
                    $tambahJenis(self::jenis($x['file'] ?? null, $x['link'] ?? null));
                    if ($t = $ts($x['dibuat'] ?? null)) { $ev['datainduk'][] = $t; }
                }
            }
        }
        $totalDok = array_sum($jenis);
        arsort($jenis);

        // ---------- LKPS (opsional) ----------
        $lkps = null;
        if (class_exists(LkpsRingkasan::class)) {
            $r = LkpsRingkasan::data();
            if ($r['tersedia']) {
                $lkps = ['persen' => $r['persen'], 'terisi' => $r['terisi'], 'total' => $r['total']];
                foreach (array_keys(Lkps::tabel()) as $slug) {
                    $nama = Lkps::namaTabel($slug);
                    if (Schema::hasTable($nama)) {
                        foreach (DB::table($nama)->pluck('created_at') as $v) { if ($t = $ts($v)) { $ev['lkps'][] = $t; } }
                    }
                }
            }
        }

        // ---------- aktivitas bulanan ----------
        $y0 = (int) date('Y', $now); $m0 = (int) date('n', $now) - ($bulan - 1);
        while ($m0 < 1) { $m0 += 12; $y0--; }
        $labels = [];
        for ($i = 0; $i < $bulan; $i++) { $labels[] = self::BULAN[(($m0 - 1 + $i) % 12)]; }
        $seri = [
            'dokumen'   => ['name' => 'Dokumen kriteria', 'color' => '#2563eb'],
            'datainduk' => ['name' => 'Data Induk',       'color' => '#7c3aed'],
            'lkps'      => ['name' => 'LKPS',             'color' => '#0d9488'],
            'butir'     => ['name' => 'Butir diperbarui', 'color' => '#d97706'],
        ];
        if ($lkps === null) { unset($seri['lkps']); }
        foreach ($seri as $k => &$s) {
            $s['vals'] = array_fill(0, $bulan, 0);
            foreach ($ev[$k] as $t) {
                // indeks bulan relatif terhadap bulan pertama jendela
                $i = ((int) date('Y', $t) - $y0) * 12 + (int) date('n', $t) - $m0;
                if ($i >= 0 && $i < $bulan) { $s['vals'][$i]++; }
            }
        }
        unset($s);

        // ---------- 12 minggu terakhir & 30 hari ----------
        $semua = array_merge(...array_values($ev));
        $hari = 86400;
        $mingguan = []; $kumDok = [];
        $tsDok = array_merge($ev['dokumen'], $ev['datainduk']);
        for ($w = 0; $w < 12; $w++) {
            $akhir = $now - (11 - $w) * 7 * $hari; $awal = $akhir - 7 * $hari;
            $mingguan[] = count(array_filter($semua, fn ($t) => $t > $awal && $t <= $akhir));
            $kumDok[] = count(array_filter($tsDok, fn ($t) => $t <= $akhir));
        }
        $a30 = count(array_filter($semua, fn ($t) => $t > $now - 30 * $hari && $t <= $now));
        $p30 = count(array_filter($semua, fn ($t) => $t > $now - 60 * $hari && $t <= $now - 30 * $hari));
        $delta = $p30 > 0 ? (int) round(($a30 - $p30) / $p30 * 100) : null;

        // ---------- sorotan (insight) ----------
        $sorotan = [];
        if ($per && $nB) {
            $rata = fn ($k) => (int) round(($k['isian'] + $k['narasi'] + $k['dokumen']) / 3);
            $urut = $per; usort($urut, fn ($a, $b) => $rata($a) <=> $rata($b));
            $rendah = $urut[0]; $tinggi = end($urut);
            $sorotan[] = ['ikon' => 'target', 'warna' => '#e11d48', 'judul' => 'Fokus: ' . $rendah['kode'] . ' (' . $rata($rendah) . '%)',
                'teks' => $rendah['kode'] . ' - ' . $rendah['nama'] . ' memiliki capaian terendah. Prioritaskan pengisian di sini.'];
            if ($tanpaDok > 0 || $tanpaNarasi > 0) {
                $sorotan[] = ['ikon' => 'alert', 'warna' => '#d97706', 'judul' => $tanpaDok . ' butir tanpa dokumen',
                    'teks' => $tanpaNarasi . ' butir belum bernarasi dan ' . $tanpaDok . ' butir belum memiliki dokumen pendukung.'];
            }
            if (count($per) > 1) {
                $sorotan[] = ['ikon' => 'trophy', 'warna' => '#059669', 'judul' => 'Terbaik: ' . $tinggi['kode'] . ' (' . $rata($tinggi) . '%)',
                    'teks' => $tinggi['kode'] . ' - ' . $tinggi['nama'] . ' menjadi kriteria dengan capaian tertinggi.'];
            }
        }
        $sorotan[] = ['ikon' => 'trend', 'warna' => '#2563eb',
            'judul' => $delta === null ? ($a30 > 0 ? 'Aktivitas dimulai' : 'Belum ada aktivitas') : ('Aktivitas ' . ($delta > 0 ? 'naik ' : ($delta < 0 ? 'turun ' : 'stabil ')) . ($delta !== 0 ? abs($delta) . '%' : '')),
            'teks' => $a30 . ' perubahan dalam 30 hari terakhir' . ($delta === null ? '.' : ' dibanding ' . $p30 . ' pada 30 hari sebelumnya.')];
        if ($lkps && count($sorotan) < 5) {
            $sorotan[] = ['ikon' => 'grid', 'warna' => '#7c3aed', 'judul' => ($lkps['total'] - $lkps['terisi']) . ' tabel LKPS kosong',
                'teks' => $lkps['terisi'] . ' dari ' . $lkps['total'] . ' tabel LKPS sudah berisi data.'];
        }

        return [
            'bulan' => $bulan, 'labels' => $labels, 'seri' => array_values($seri),
            'kesiapan' => $kesiapan, 'total' => $total, 'kriteria' => $per,
            'butir_total' => $nB, 'butir_siap' => $siap, 'status' => $status, 'corong' => $corong,
            'tanpa_dok' => $tanpaDok, 'tanpa_narasi' => $tanpaNarasi,
            'dokumen_total' => $totalDok, 'jenis' => $jenis, 'sebaran' => $sebaran,
            'mingguan' => $mingguan, 'kum_dok' => $kumDok, 'a30' => $a30, 'p30' => $p30, 'delta' => $delta,
            'prioritas' => $prioritas, 'sorotan' => $sorotan, 'lkps' => $lkps,
        ];
    }
}
EOF

tulis app/Support/Panel.php <<'EOF'
<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Data untuk Panel Admin (dashboard visualisasi). Hanya MEMBACA data yang sudah ada.
 * Memakai App\Support\Analitik untuk metrik bersama (kriteria, butir prioritas, aktivitas bulanan).
 */
class Panel
{
    private const BULAN = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

    public static function tanggal(int $ts): string
    {
        return (int) date('j', $ts) . ' ' . self::BULAN[(int) date('n', $ts) - 1] . ' ' . date('Y', $ts);
    }

    public static function relatif(int $ts, int $now): string
    {
        $d = $now - $ts;
        if ($d < 60) {
            return 'baru saja';
        }
        if ($d < 3600) {
            return intdiv($d, 60) . ' menit lalu';
        }
        if ($d < 86400) {
            return intdiv($d, 3600) . ' jam lalu';
        }
        if ($d < 7 * 86400) {
            return intdiv($d, 86400) . ' hari lalu';
        }

        return self::tanggal($ts);
    }

    private static function stamps(string $tabel, string $kolom = 'created_at'): array
    {
        if (! Schema::hasTable($tabel)) {
            return [];
        }
        $o = [];
        foreach (DB::table($tabel)->pluck($kolom) as $v) {
            if ($v && ($t = strtotime((string) $v))) {
                $o[] = (int) $t;
            }
        }

        return $o;
    }

    /** Jumlah kumulatif pada akhir tiap bulan, 12 bulan terakhir. */
    private static function kumulatif(array $ts, int $now): array
    {
        $y = (int) date('Y', $now);
        $m = (int) date('n', $now);
        $out = [];
        for ($i = 11; $i >= 0; $i--) {
            $akhir = mktime(0, 0, 0, $m - $i + 1, 1, $y) - 1;
            $out[] = count(array_filter($ts, fn ($t) => $t <= $akhir));
        }

        return $out;
    }

    public static function data(?int $sekarang = null): array
    {
        $now = $sekarang ?? time();
        $a = Analitik::data(12, $now);
        $y = (int) date('Y', $now);
        $m = (int) date('n', $now);
        $awalIni = mktime(0, 0, 0, $m, 1, $y);
        $awalLalu = mktime(0, 0, 0, $m - 1, 1, $y);

        // ---------- sumber bertanggal ----------
        $kriteria = DB::table('kriterias')->get()->keyBy('id');
        $butir = DB::table('isi_kriteria')->get()->keyBy('id');
        $kode = fn ($isiId) => ($butir[$isiId] ?? null) ? ($kriteria[$butir[$isiId]->kriteria_id]->kode ?? '-') : '-';

        $docsDI = [];   // dokumen Data Induk bertanggal
        if (class_exists(DataInduk::class)) {
            foreach (DataInduk::KATEGORI as $kat => $nama) {
                foreach (DataInduk::semua($kat) as $x) {
                    $t = isset($x['dibuat']) ? (int) strtotime((string) $x['dibuat']) : 0;
                    $docsDI[] = ['ts' => $t, 'nama' => $x['nama'], 'kat' => $kat, 'kat_nama' => $nama, 'id' => $x['id'],
                                 'file' => $x['file'] ?? null, 'link' => $x['link'] ?? null];
                }
            }
        }
        $tsDI = array_values(array_filter(array_column($docsDI, 'ts')));
        $tsDok = self::stamps('dokumen');

        // ---------- kartu statistik ----------
        $spek = [
            'kriteria'  => ['Kriteria',            self::stamps('kriterias'),       count($kriteria),            ['#6366f1', '#3b82f6'], 'folder'],
            'butir'     => ['Butir penilaian',     self::stamps('isi_kriteria'),    count($butir),               ['#10b981', '#14b8a6'], 'list'],
            'dokumen'   => ['Dokumen',             array_merge($tsDok, $tsDI),      $a['dokumen_total'],         ['#f59e0b', '#f97316'], 'file'],
            'pengguna'  => ['Pengguna',            self::stamps('users'),           Schema::hasTable('users') ? DB::table('users')->count() : 0, ['#ec4899', '#f43f5e'], 'users'],
            'datainduk' => ['Dokumen Data Induk',  $tsDI,                           count($docsDI),              ['#0ea5e9', '#6366f1'], 'folder'],
        ];
        $kartu = [];
        foreach ($spek as $kunci => [$label, $ts, $n, $grad, $ikon]) {
            $ini = count(array_filter($ts, fn ($t) => $t >= $awalIni && $t <= $now));
            $lalu = count(array_filter($ts, fn ($t) => $t >= $awalLalu && $t < $awalIni));
            $kartu[$kunci] = [
                'label' => $label, 'n' => $n, 'ini' => $ini, 'lalu' => $lalu,
                'delta' => $lalu > 0 ? (int) round(($ini - $lalu) / $lalu * 100) : null,
                'spark' => self::kumulatif($ts, $now), 'warna' => $grad[0], 'grad' => $grad, 'ikon' => $ikon,
            ];
        }

        // ---------- tren (3 seri) ----------
        $sr = array_column($a['seri'], null, 'name');
        $gabung = array_map(fn ($p, $q) => $p + $q, $sr['Dokumen kriteria']['vals'], $sr['Data Induk']['vals']);
        $seri = [
            ['name' => 'Dokumen',          'color' => '#6366f1', 'vals' => $gabung],
            ['name' => 'Butir diperbarui', 'color' => '#10b981', 'vals' => $sr['Butir diperbarui']['vals']],
        ];
        if (isset($sr['LKPS'])) {
            $seri[] = ['name' => 'LKPS', 'color' => '#f59e0b', 'vals' => $sr['LKPS']['vals']];
        }

        // ---------- radial ----------
        $radial = [
            ['label' => 'Isian',   'v' => $a['total']['isian'],   'color' => '#6366f1'],
            ['label' => 'Narasi',  'v' => $a['total']['narasi'],  'color' => '#10b981'],
            ['label' => 'Dokumen', 'v' => $a['total']['dokumen'], 'color' => '#f59e0b'],
        ];
        if ($a['lkps']) {
            $radial[] = ['label' => 'LKPS', 'v' => $a['lkps']['persen'], 'color' => '#ec4899'];
        }

        // ---------- progres per kriteria ----------
        $progres = array_map(fn ($k) => ['kode' => $k['kode'], 'nama' => $k['nama'], 'v' => (int) round(($k['isian'] + $k['narasi'] + $k['dokumen']) / 3)], $a['kriteria']);

        // ---------- sebaran Data Induk ----------
        $warna = ['#6366f1', '#10b981', '#f59e0b', '#ec4899', '#0ea5e9'];
        $sebaran = [];
        foreach (array_values($a['sebaran']) as $i => $s) {
            $sebaran[] = ['label' => $s['label'], 'v' => $s['n'], 'color' => $warna[$i % count($warna)]];
        }

        // ---------- aktivitas terbaru ----------
        $ev = [];
        foreach (DB::table('dokumen')->orderByDesc('created_at')->limit(8)->get() as $d) {
            if ($t = (int) strtotime((string) $d->created_at)) {
                $ev[] = ['tipe' => 'dokumen', 'ts' => $t, 'judul' => $d->nama, 'sub' => 'Dokumen · ' . $kode($d->isi_kriteria_id) . ' · Butir ' . (($butir[$d->isi_kriteria_id]->butir ?? '-'))];
            }
        }
        foreach (DB::table('isi_kriteria')->orderByDesc('updated_at')->limit(8)->get() as $b) {
            if ($t = (int) strtotime((string) $b->updated_at)) {
                $ev[] = ['tipe' => 'butir', 'ts' => $t, 'judul' => 'Butir ' . $b->butir . ' diperbarui', 'sub' => ($kriteria[$b->kriteria_id]->kode ?? '-') . ' · isian ' . (int) $b->persentase . '%'];
            }
        }
        foreach ($docsDI as $x) {
            if ($x['ts']) {
                $ev[] = ['tipe' => 'datainduk', 'ts' => $x['ts'], 'judul' => $x['nama'], 'sub' => 'Data Induk · ' . $x['kat_nama']];
            }
        }
        if ($a['lkps'] && class_exists(Lkps::class)) {
            foreach (Lkps::tabel() as $slug => $def) {
                $nama = Lkps::namaTabel($slug);
                if (Schema::hasTable($nama)) {
                    foreach (DB::table($nama)->orderByDesc('created_at')->limit(2)->pluck('created_at') as $v) {
                        if ($t = (int) strtotime((string) $v)) {
                            $ev[] = ['tipe' => 'lkps', 'ts' => $t, 'judul' => 'Data baru di ' . $def['judul'], 'sub' => 'LKPS'];
                        }
                    }
                }
            }
        }
        usort($ev, fn ($p, $q) => $q['ts'] <=> $p['ts']);
        $feed = array_map(fn ($e) => $e + ['waktu' => self::relatif($e['ts'], $now)], array_slice($ev, 0, 8));

        // ---------- dokumen terbaru ----------
        $tb = [];
        foreach (DB::table('dokumen')->orderByDesc('created_at')->limit(6)->get() as $d) {
            $tb[] = ['ts' => (int) strtotime((string) $d->created_at), 'nama' => $d->nama,
                     'sumber' => 'Kriteria ' . $kode($d->isi_kriteria_id) . ' · Butir ' . ($butir[$d->isi_kriteria_id]->butir ?? '-'),
                     'jenis' => Analitik::jenis($d->file_path, $d->link), 'tipe' => 'k', 'id' => $d->id, 'kat' => null,
                     'file' => (bool) $d->file_path, 'link' => $d->link];
        }
        foreach ($docsDI as $x) {
            $tb[] = ['ts' => $x['ts'], 'nama' => $x['nama'], 'sumber' => 'Data Induk · ' . $x['kat_nama'],
                     'jenis' => Analitik::jenis($x['file'], $x['link']), 'tipe' => 'd', 'id' => $x['id'], 'kat' => $x['kat'],
                     'file' => (bool) $x['file'], 'link' => $x['link']];
        }
        usort($tb, fn ($p, $q) => $q['ts'] <=> $p['ts']);
        $terbaru = array_map(fn ($r) => $r + ['tanggal' => $r['ts'] ? self::tanggal($r['ts']) : '-'], array_slice($tb, 0, 6));

        return [
            'labels' => $a['labels'], 'kartu' => $kartu, 'seri' => $seri, 'radial' => $radial, 'progres' => $progres,
            'sebaran' => $sebaran, 'feed' => $feed, 'terbaru' => $terbaru,
            'prioritas' => array_slice($a['prioritas'], 0, 5), 'kesiapan' => $a['kesiapan'], 'lkps' => $a['lkps'],
        ];
    }
}
EOF

tulis app/Http/Controllers/PanelController.php <<'EOF'
<?php

namespace App\Http\Controllers;

use App\Support\Panel;

class PanelController extends Controller
{
    public function index()
    {
        return view('panel.index', ['p' => Panel::data()]);
    }
}
EOF

tulis resources/views/panel/_gaya.blade.php <<'EOF'
<style>
.pn-top{display:flex;justify-content:space-between;align-items:flex-end;flex-wrap:wrap;gap:14px;margin-bottom:18px}
.pn-top h1{font-size:26px;font-weight:700;letter-spacing:-.02em;margin:0}
.pn-top p{margin:3px 0 0;color:var(--muted,#667085);font-size:13.5px}
.pn-act{display:flex;gap:8px;flex-wrap:wrap}
.pn-btn{display:inline-flex;align-items:center;gap:7px;padding:8px 14px;border-radius:10px;font-size:13px;font-weight:600;text-decoration:none;border:1px solid var(--line,#e4e8ef);background:var(--card,#fff);color:var(--text,#1b2536)}
.pn-btn:hover{border-color:var(--pri,#1d4ed8);color:var(--pri,#1d4ed8)}
.pn-btn.p{background:linear-gradient(135deg,#6366f1,#3b82f6);border-color:transparent;color:#fff}
.pn-btn.p:hover{color:#fff;filter:brightness(1.06)}
.pn-btn svg{width:16px;height:16px}
.pn-stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(235px,1fr));gap:14px;margin-bottom:16px}
.pn-stat{display:flex;align-items:center;gap:14px;padding:16px 18px;background:var(--card,#fff);border:1px solid var(--line,#e4e8ef);border-radius:16px;box-shadow:0 1px 2px rgba(16,24,40,.04)}
.pn-tile{flex:none;width:52px;height:52px;border-radius:14px;display:grid;place-items:center;color:#fff;box-shadow:0 8px 16px -8px var(--c)}
.pn-tile svg{width:24px;height:24px}
.pn-stat .pn-mid{flex:1;min-width:0}
.pn-stat small{display:block;color:var(--muted,#667085);font-size:12.5px}
.pn-stat strong{display:block;font-size:30px;font-weight:700;letter-spacing:-.02em;line-height:1.15}
.pn-chip{display:inline-block;font-size:11px;font-weight:700;padding:2px 9px;border-radius:999px;color:var(--c);position:relative;overflow:hidden;margin-top:3px}
.pn-chip::before{content:"";position:absolute;inset:0;background:var(--c);opacity:.12}
.pn-chip.n{color:var(--muted,#667085)}
.pn-chip.n::before{background:#94a3b8}
.pn-chip span{position:relative}
.pn-spark{flex:none}
.pn-g2{display:grid;grid-template-columns:minmax(0,2fr) minmax(0,1fr);gap:14px;margin-bottom:14px}
.pn-g3{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:14px;margin-bottom:14px}
@media(max-width:980px){.pn-g2{grid-template-columns:minmax(0,1fr)}}
.pn-card{background:var(--card,#fff);border:1px solid var(--line,#e4e8ef);border-radius:16px;padding:18px 20px;box-shadow:0 1px 2px rgba(16,24,40,.04)}
.pn-ch{display:flex;justify-content:space-between;align-items:flex-start;gap:10px;margin-bottom:10px}
.pn-ch h2{font-size:16px;font-weight:700;margin:0;letter-spacing:-.01em}
.pn-ch small{display:block;color:var(--muted,#667085);font-size:12px;margin-top:2px}
.pn-ch a{font-size:12.5px;text-decoration:none;white-space:nowrap}
.pn-area,.pn-hbar{display:block;width:100%;height:auto}
.pn-radial{display:block;width:100%;max-width:290px;margin:0 auto;height:auto}
.pn-lg{display:flex;gap:16px;flex-wrap:wrap;font-size:12.5px;color:var(--muted,#667085);margin-bottom:6px}
.pn-lg i{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:6px;vertical-align:-1px}
.pn-pr{list-style:none;margin:0;padding:0}
.pn-pr li{padding:7px 0}
.pn-pr .r{display:flex;justify-content:space-between;gap:8px;font-size:13px;margin-bottom:5px}
.pn-pr .r a{color:var(--text,#1b2536);text-decoration:none;font-weight:600}
.pn-pr .r a:hover{color:var(--pri,#1d4ed8)}
.pn-pr .r span{color:var(--muted,#667085);font-weight:600}
.pn-pr svg{display:block;width:100%;height:8px}
.pn-feed{list-style:none;margin:0;padding:0}
.pn-feed li{display:flex;gap:12px;padding:9px 0;position:relative}
.pn-feed li:not(:last-child)::after{content:"";position:absolute;left:15px;top:42px;bottom:-6px;width:2px;background:var(--line,#e4e8ef)}
.pn-dot{flex:none;position:relative;width:32px;height:32px;border-radius:50%;display:grid;place-items:center;color:var(--c);overflow:hidden}
.pn-dot::before{content:"";position:absolute;inset:0;background:var(--c);opacity:.14}
.pn-dot svg{position:relative;width:16px;height:16px}
.pn-feed b{display:block;font-size:13px;line-height:1.35;overflow-wrap:anywhere}
.pn-feed small{color:var(--muted,#667085);font-size:11.5px}
.pn-tb{width:100%;border-collapse:collapse;font-size:13.5px}
.pn-tb th{font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:var(--muted,#667085);text-align:left;padding:8px 10px;border-bottom:1px solid var(--line,#e4e8ef)}
.pn-tb td{padding:10px;border-bottom:1px solid var(--line,#e4e8ef);vertical-align:middle}
.pn-tb tr:last-child td{border-bottom:0}
.pn-tb small{display:block;color:var(--muted,#667085);font-size:11.5px}
.pn-tag{display:inline-block;font-size:11.5px;font-weight:700;padding:2px 9px;border-radius:999px;background:#eef2ff;color:#4338ca}
.pn-todo{list-style:none;margin:0;padding:0}
.pn-todo li{display:flex;gap:10px;align-items:flex-start;padding:9px 0;border-top:1px solid var(--line,#e4e8ef);font-size:13px}
.pn-todo li:first-child{border-top:0}
.pn-todo i{flex:none;width:16px;height:16px;border:2px solid #cbd5e1;border-radius:5px;margin-top:2px}
.pn-todo b{display:block}
.pn-todo small{color:var(--muted,#667085)}
.pn-todo a{margin-left:auto;font-size:12.5px;text-decoration:none;white-space:nowrap}
.pn-kosong{color:var(--muted,#667085);font-size:13.5px;margin:6px 0 0}
@keyframes pnh{from{transform:scaleX(0)}}
.pn-hb{transform-box:fill-box;transform-origin:left center;animation:pnh .9s ease-out both}
@keyframes pnd{from{stroke-dasharray:0 700}}
.pn-radial circle:nth-of-type(even){animation:pnd 1s ease-out both}
@media(prefers-reduced-motion:reduce){.pn-hb,.pn-radial circle{animation:none}}
</style>
EOF

tulis resources/views/panel/index.blade.php <<'EOF'
@extends('layout')
@section('title', 'Panel Admin')
@section('content')
@includeIf('dash._pilih', ['aktif' => 'panel'])
@include('panel._gaya')
@php
    $K = $p['kartu'];
    $stat = [$K['kriteria'], $K['butir'], $K['dokumen'], auth()->check() ? $K['pengguna'] : $K['datainduk']];
    $jenisWarna = ['PDF' => '#e11d48', 'Word' => '#2563eb', 'Excel' => '#059669', 'PowerPoint' => '#d97706', 'Gambar' => '#7c3aed', 'Arsip' => '#64748b', 'Tautan' => '#0ea5e9', 'Lainnya' => '#94a3b8'];
    $feedStyle = ['dokumen' => ['#6366f1', 'file'], 'butir' => ['#10b981', 'check'], 'datainduk' => ['#f59e0b', 'folder'], 'lkps' => ['#ec4899', 'grid']];
    $ts = date('j') . ' ' . ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'][(int) date('n') - 1] . ' ' . date('Y');
@endphp

<div class="pn-top">
  <div>
    <h1>{{ auth()->check() ? 'Halo, ' . auth()->user()->name : 'Selamat datang' }}</h1>
    <p>Ringkasan Sistem Informasi Akreditasi &middot; {{ $ts }} &middot; kesiapan keseluruhan <strong>{{ $p['kesiapan'] }}%</strong></p>
  </div>
  <div class="pn-act">
    @auth
      <a class="pn-btn p" href="{{ route('kriteria.index') }}">@include('vk.ikonp', ['n' => 'plus'])Kelola kriteria</a>
      @if(Route::has('datainduk.create'))<a class="pn-btn" href="{{ route('datainduk.create', 'standar-mutu') }}">@include('vk.ikonp', ['n' => 'file'])Unggah Data Induk</a>@endif
    @else
      <a class="pn-btn p" href="{{ route('login') }}">Masuk untuk mengelola data</a>
    @endauth
    @if(Route::has('lkps.daftar'))<a class="pn-btn" href="{{ route('lkps.daftar') }}">@include('vk.ikonp', ['n' => 'grid'])LKPS</a>@endif
    @if(Route::has('analitik'))<a class="pn-btn" href="{{ route('analitik') }}">@include('vk.ikonp', ['n' => 'chart'])Analitik</a>@endif
  </div>
</div>

<section class="pn-stats">
  @foreach($stat as $s)
    <div class="pn-stat">
      <span class="pn-tile" style="--c:{{ $s['warna'] }};background:linear-gradient(135deg,{{ $s['grad'][0] }},{{ $s['grad'][1] }})">@include('vk.ikonp', ['n' => $s['ikon']])</span>
      <div class="pn-mid">
        <small>{{ $s['label'] }}</small><strong>{{ $s['n'] }}</strong>
        <span class="pn-chip {{ $s['ini'] > 0 ? '' : 'n' }}" style="--c:{{ $s['warna'] }}" title="Bulan lalu: {{ $s['lalu'] }}"><span>{{ $s['ini'] > 0 ? '▲ +' . $s['ini'] . ' bulan ini' : '— belum ada bulan ini' }}</span></span>
      </div>
      @include('vk.spark', ['vals' => $s['spark'], 'color' => $s['warna'], 'w' => 70, 'h' => 34])
    </div>
  @endforeach
</section>

<div class="pn-g2">
  <section class="pn-card">
    <div class="pn-ch"><div><h2>Tren aktivitas</h2><small>12 bulan terakhir</small></div></div>
    <div class="pn-lg">@foreach($p['seri'] as $s)<span><i style="background:{{ $s['color'] }}"></i>{{ $s['name'] }}</span>@endforeach</div>
    @include('vk.area', ['labels' => $p['labels'], 'series' => $p['seri']])
  </section>
  <section class="pn-card">
    <div class="pn-ch"><div><h2>Kelengkapan</h2><small>{{ $p['lkps'] ? 'Isian, narasi, dokumen, LKPS' : 'Isian, narasi, dokumen' }}</small></div></div>
    @include('vk.radial', ['items' => $p['radial']])
  </section>
</div>

<div class="pn-g3">
  <section class="pn-card">
    <div class="pn-ch"><div><h2>Progres per kriteria</h2><small>rata-rata isian, narasi, dokumen</small></div></div>
    @if(count($p['progres']))
      <ul class="pn-pr">
        @foreach($p['progres'] as $r)
          <li><div class="r"><a href="{{ route('kriteria.index') }}" title="{{ $r['nama'] }}">{{ $r['kode'] }} &middot; {{ \Illuminate\Support\Str::limit($r['nama'], 28) }}</a><span>{{ $r['v'] }}%</span></div>
            <svg viewBox="0 0 100 8" preserveAspectRatio="none" aria-hidden="true"><rect width="100" height="8" rx="4" fill="var(--line)"/><rect width="{{ $r['v'] }}" height="8" rx="4" fill="{{ $r['v'] >= 80 ? '#10b981' : ($r['v'] >= 50 ? '#f59e0b' : '#ef4444') }}"/></svg></li>
        @endforeach
      </ul>
    @else<p class="pn-kosong">Belum ada kriteria.</p>@endif
  </section>
  <section class="pn-card">
    <div class="pn-ch"><div><h2>Dokumen Data Induk</h2><small>per kategori</small></div>@if(Route::has('datainduk.index'))<a href="{{ route('datainduk.index', 'standar-mutu') }}">Buka &rarr;</a>@endif</div>
    @if(count($p['sebaran']))@include('vk.hbar', ['rows' => $p['sebaran']])@else<p class="pn-kosong">Data Induk belum terpasang.</p>@endif
  </section>
  <section class="pn-card">
    <div class="pn-ch"><div><h2>Aktivitas terbaru</h2><small>perubahan data paling akhir</small></div></div>
    @if(count($p['feed']))
      <ul class="pn-feed">
        @foreach($p['feed'] as $e)
          @php [$wr, $ik] = $feedStyle[$e['tipe']] ?? ['#6366f1', 'file']; @endphp
          <li><span class="pn-dot" style="--c:{{ $wr }}">@include('vk.ikonp', ['n' => $ik])</span><div><b>{{ $e['judul'] }}</b><small>{{ $e['sub'] }} &middot; {{ $e['waktu'] }}</small></div></li>
        @endforeach
      </ul>
    @else<p class="pn-kosong">Belum ada aktivitas.</p>@endif
  </section>
</div>

<div class="pn-g2">
  <section class="pn-card">
    <div class="pn-ch"><div><h2>Dokumen terbaru</h2><small>kriteria dan Data Induk</small></div></div>
    @if(count($p['terbaru']))
      <div class="table-responsive"><table class="pn-tb">
        <thead><tr><th>Dokumen</th><th>Jenis</th><th>Tanggal</th><th></th></tr></thead>
        <tbody>
        @foreach($p['terbaru'] as $d)
          <tr>
            <td><strong>{{ $d['nama'] }}</strong><small>{{ $d['sumber'] }}</small></td>
            <td><span class="pn-tag" style="background:{{ $jenisWarna[$d['jenis']] ?? '#94a3b8' }}1f;color:{{ $jenisWarna[$d['jenis']] ?? '#475569' }}">{{ $d['jenis'] }}</span></td>
            <td>{{ $d['tanggal'] }}</td>
            <td class="text-end">
              @if($d['file'] && $d['tipe'] === 'k' && Route::has('lihat.dokumen'))<a href="{{ route('lihat.dokumen', $d['id']) }}" target="_blank" rel="noopener" class="text-decoration-none">Lihat</a>
              @elseif($d['file'] && $d['tipe'] === 'd' && Route::has('lihat.datainduk'))<a href="{{ route('lihat.datainduk', [$d['kat'], $d['id']]) }}" target="_blank" rel="noopener" class="text-decoration-none">Lihat</a>
              @elseif($d['link'])<a href="{{ $d['link'] }}" target="_blank" rel="noopener" class="text-decoration-none">Buka</a>@endif
            </td>
          </tr>
        @endforeach
        </tbody>
      </table></div>
    @else<p class="pn-kosong">Belum ada dokumen.</p>@endif
  </section>
  <section class="pn-card">
    <div class="pn-ch"><div><h2>Perlu perhatian</h2><small>butir dengan celah terbesar</small></div>@if(Route::has('analitik'))<a href="{{ route('analitik') }}">Analitik &rarr;</a>@endif</div>
    @if(count($p['prioritas']))
      <ul class="pn-todo">
        @foreach($p['prioritas'] as $b)
          <li><i></i><div><b>{{ $b['kode'] }} &middot; Butir {{ $b['butir'] }}</b><small>{{ trim(($b['narasi'] ? '' : 'Narasi kosong · ') . ($b['dok'] === 0 ? 'Tanpa dokumen · ' : '') . 'isian ' . $b['persen'] . '%') }}</small></div><a href="{{ route('isi.show', $b['id']) }}">Buka</a></li>
        @endforeach
      </ul>
    @else<p class="pn-kosong">Semua butir sudah lengkap.</p>@endif
  </section>
</div>
@endsection
EOF

tulis resources/views/vk/spark.blade.php <<'EOF'
@php
    $w = $w ?? 120; $h = $h ?? 38; $color = $color ?? '#2563eb';
    $id = 'sp' . bin2hex(random_bytes(3));
    $vals = array_values($vals); $n = count($vals);
    $f1 = fn ($x) => number_format($x, 1, '.', '');
    if ($n >= 2) {
        $mx = max($vals); $mn = min($vals); $rg = ($mx - $mn) ?: 1; $pts = [];
        foreach ($vals as $i => $v) { $pts[] = [2 + $i * ($w - 4) / max(1, $n - 1), $h - 5 - ($mx == $mn ? 0.35 * ($h - 12) : ($v - $mn) / $rg * ($h - 12))]; }
        $d = 'M' . $f1($pts[0][0]) . ',' . $f1($pts[0][1]);
        for ($i = 0; $i < $n - 1; $i++) {
            $p0 = $pts[$i - 1] ?? $pts[$i]; $p1 = $pts[$i]; $p2 = $pts[$i + 1]; $p3 = $pts[$i + 2] ?? $p2;
            $d .= ' C' . $f1($p1[0] + ($p2[0] - $p0[0]) / 6) . ',' . $f1($p1[1] + ($p2[1] - $p0[1]) / 6) . ' ' . $f1($p2[0] - ($p3[0] - $p1[0]) / 6) . ',' . $f1($p2[1] - ($p3[1] - $p1[1]) / 6) . ' ' . $f1($p2[0]) . ',' . $f1($p2[1]);
        }
        $last = $pts[$n - 1];
    }
@endphp
@if($n >= 2)<svg class="an-spark" viewBox="0 0 {{ $w }} {{ $h }}" width="{{ $w }}" height="{{ $h }}" aria-hidden="true"><defs><linearGradient id="{{ $id }}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{{ $color }}" stop-opacity=".28"/><stop offset="1" stop-color="{{ $color }}" stop-opacity="0"/></linearGradient></defs><path d="{{ $d }} L{{ $f1($last[0]) }},{{ $h }} L{{ $f1($pts[0][0]) }},{{ $h }} Z" fill="url(#{{ $id }})"/><path d="{{ $d }}" fill="none" stroke="{{ $color }}" stroke-width="2" stroke-linecap="round"/><circle cx="{{ $f1($last[0]) }}" cy="{{ $f1($last[1]) }}" r="3" fill="#fff" stroke="{{ $color }}" stroke-width="2"/></svg>@endif
EOF

tulis resources/views/vk/area.blade.php <<'EOF'
@php
    // $labels: ['Okt', ...]; $series: [['name' => , 'color' => , 'vals' => [...]], ...]
    $W = 640; $H = 260; $L = 34; $B = 28; $T = 14; $R = 12; $pw = $W - $L - $R; $ph = $H - $T - $B; $n = count($labels);
    $f1 = fn ($x) => number_format($x, 1, '.', '');
    $mx0 = max(1, ...array_merge(...array_column($series, 'vals')));
    $st = 1000; foreach ([1, 2, 5, 10, 20, 25, 50, 100, 200, 500, 1000] as $c) { if ($mx0 / $c <= 5) { $st = $c; break; } }
    $mx = (int) ceil($mx0 / $st) * $st; $nk = (int) ($mx / $st);
    $id = 'ar' . bin2hex(random_bytes(3));
    $xs = fn ($i) => $L + ($n > 1 ? $i * $pw / ($n - 1) : $pw / 2);
    $jalur = function ($pts) use ($f1) {
        $d = 'M' . $f1($pts[0][0]) . ',' . $f1($pts[0][1]); $m = count($pts);
        for ($i = 0; $i < $m - 1; $i++) {
            $p0 = $pts[$i - 1] ?? $pts[$i]; $p1 = $pts[$i]; $p2 = $pts[$i + 1]; $p3 = $pts[$i + 2] ?? $p2;
            $d .= ' C' . $f1($p1[0] + ($p2[0] - $p0[0]) / 6) . ',' . $f1($p1[1] + ($p2[1] - $p0[1]) / 6) . ' ' . $f1($p2[0] - ($p3[0] - $p1[0]) / 6) . ',' . $f1($p2[1] - ($p3[1] - $p1[1]) / 6) . ' ' . $f1($p2[0]) . ',' . $f1($p2[1]);
        }
        return $d;
    };
@endphp
<svg class="pn-area" viewBox="0 0 {{ $W }} {{ $H }}" role="img" aria-label="Tren aktivitas"><title>Tren aktivitas</title><defs>@foreach($series as $j => $s)<linearGradient id="{{ $id }}{{ $j }}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{{ $s['color'] }}" stop-opacity=".16"/><stop offset="1" stop-color="{{ $s['color'] }}" stop-opacity="0"/></linearGradient>@endforeach</defs>@for($k = 0; $k <= $nk; $k++)@php $v = $k * $st; $y = $T + $ph - $ph * $v / $mx; @endphp<line x1="{{ $L }}" y1="{{ $f1($y) }}" x2="{{ $W - $R }}" y2="{{ $f1($y) }}" stroke="var(--line)" stroke-dasharray="{{ $k ? '3 4' : '0' }}"/><text x="{{ $L - 8 }}" y="{{ $f1($y + 3.5) }}" text-anchor="end" font-size="10" fill="var(--muted)">{{ $v }}</text>@endfor
@foreach(array_reverse(array_keys($series)) as $j)@php $s = $series[$j]; $pts = []; foreach ($s['vals'] as $i => $v) { $pts[] = [$xs($i), $T + $ph - $ph * $v / $mx]; } $d = $jalur($pts); @endphp<path d="{{ $d }} L{{ $f1($pts[$n - 1][0]) }},{{ $T + $ph }} L{{ $f1($pts[0][0]) }},{{ $T + $ph }} Z" fill="url(#{{ $id }}{{ $j }})"/><path d="{{ $d }}" fill="none" stroke="{{ $s['color'] }}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>@foreach($pts as $i => $p)<circle cx="{{ $f1($p[0]) }}" cy="{{ $f1($p[1]) }}" r="3" fill="#fff" stroke="{{ $s['color'] }}" stroke-width="2"><title>{{ $labels[$i] }}: {{ $s['name'] }} {{ $s['vals'][$i] }}</title></circle>@endforeach @endforeach
@foreach($labels as $i => $t)<text x="{{ $f1($xs($i)) }}" y="{{ $H - 9 }}" text-anchor="middle" font-size="10.5" fill="var(--muted)">{{ $t }}</text>@endforeach</svg>
EOF

tulis resources/views/vk/radial.blade.php <<'EOF'
@php $cx = 110; $cy = 110; $sw = 11; $f1 = fn ($x) => number_format($x, 1, '.', ''); @endphp
<svg class="pn-radial" viewBox="0 0 220 220" role="img" aria-label="Kelengkapan"><title>Kelengkapan</title>@foreach($items as $i => $it)@php $r = 88 - $i * 17; $C = 2 * M_PI * $r; $v = max(0, min(100, (int) round($it['v']))); @endphp<circle cx="{{ $cx }}" cy="{{ $cy }}" r="{{ $r }}" fill="none" stroke="var(--line)" stroke-width="{{ $sw }}" stroke-linecap="round" stroke-dasharray="{{ number_format(.75 * $C, 2, '.', '') }} {{ number_format($C, 2, '.', '') }}" transform="rotate(-90 {{ $cx }} {{ $cy }})" opacity=".7"/>@if($v > 0)<circle cx="{{ $cx }}" cy="{{ $cy }}" r="{{ $r }}" fill="none" stroke="{{ $it['color'] }}" stroke-width="{{ $sw }}" stroke-linecap="round" stroke-dasharray="{{ number_format($v / 100 * .75 * $C, 2, '.', '') }} {{ number_format($C, 2, '.', '') }}" transform="rotate(-90 {{ $cx }} {{ $cy }})"><title>{{ $it['label'] }}: {{ $v }}%</title></circle>@endif<text x="{{ $cx - 8 }}" y="{{ $f1($cy - $r + 4) }}" text-anchor="end" font-size="10.5" font-weight="600" fill="var(--text)">{{ $it['label'] }} <tspan fill="{{ $it['color'] }}">{{ $v }}%</tspan></text>@endforeach</svg>
EOF

tulis resources/views/vk/hbar.blade.php <<'EOF'
@php
    // $rows: [['label' => , 'v' => , 'color' => ], ...]
    $W = 420; $rh = 40; $mx = max(1, ...array_column($rows, 'v')); $id = 'hb' . bin2hex(random_bytes(3));
    $f1 = fn ($x) => number_format($x, 1, '.', '');
@endphp
<svg class="pn-hbar" viewBox="0 0 {{ $W }} {{ count($rows) * $rh }}" role="img" aria-label="Dokumen per kategori"><title>Dokumen per kategori</title><defs>@foreach($rows as $i => $r)<linearGradient id="{{ $id }}{{ $i }}" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{{ $r['color'] }}"/><stop offset="1" stop-color="{{ $r['color'] }}" stop-opacity=".62"/></linearGradient>@endforeach</defs>@foreach($rows as $i => $r)@php $y = $i * $rh; $w = max($r['v'] > 0 ? 8 : 0, $r['v'] / $mx * ($W - 46)); @endphp<text x="0" y="{{ $y + 12 }}" font-size="12" fill="var(--text)">{{ $r['label'] }}</text><rect x="0" y="{{ $y + 18 }}" width="{{ $W - 40 }}" height="10" rx="5" fill="var(--line)" opacity=".7"/>@if($w > 0)<rect class="pn-hb" x="0" y="{{ $y + 18 }}" width="{{ $f1($w * ($W - 40) / ($W - 46)) }}" height="10" rx="5" fill="url(#{{ $id }}{{ $i }})"/>@endif<text x="{{ $W - 30 }}" y="{{ $y + 27 }}" font-size="12" font-weight="700" fill="var(--text)">{{ $r['v'] }}</text>@endforeach</svg>
EOF

tulis resources/views/vk/ikonp.blade.php <<'EOF'
@php $paths = [
    'folder' => '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
    'list'   => '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
    'file'   => '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>',
    'users'  => '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>',
    'check'  => '<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><path d="M22 4 12 14.01l-3-3"/>',
    'grid'   => '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
    'clock'  => '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    'plus'   => '<path d="M12 5v14M5 12h14"/>',
    'chart'  => '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
]; @endphp
<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{!! $paths[$n] ?? $paths['grid'] !!}</svg>
EOF

for f in app/Support/Analitik.php app/Support/Panel.php app/Http/Controllers/PanelController.php; do
  php -l "$f" >/dev/null || { echo "GAGAL: kesalahan sintaks pada $f"; exit 1; }
done
echo "  OK  sintaks berkas PHP"

echo "[3/3] Menyisipkan route dan menu..."
if grep -q "PanelController" "$R"; then
  echo "  (route Panel sudah ada, dilewati)"
else
  cp "$R" "$R.bak11"
  cat >> "$R" <<'EOF'

// ===== Panel Admin (baca publik; aksi cepat hanya tampil bagi yang login) =====
Route::get('/panel', [\App\Http\Controllers\PanelController::class, 'index'])->name('panel');
EOF
  php -l "$R" >/dev/null || { echo "GAGAL: routes/web.php tidak valid. Pulihkan dari $R.bak11"; exit 1; }
  echo "  OK  $R"
fi

if grep -q "route('panel')" "$L"; then
  echo "  (menu Panel Admin sudah ada, dilewati)"
elif grep -q "route('kriteria.index')" "$L"; then
  cp "$L" "$L.bak11"
  M=$(cat <<'EOF'
      @if(Route::has('panel'))
      <a class="mi {{ request()->routeIs('panel') ? 'on' : '' }}" href="{{ route('panel') }}">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></svg>Panel Admin
      </a>
      @endif
EOF
)
  export M
  perl -0pi -e 's/(^[ \t]*<a class="mi [^\n]*route\(\x27kriteria\.index\x27\)[^\n]*>\n)/$ENV{M}\n$1/m' "$L"
  grep -q "route('panel')" "$L" && echo "  OK  menu Panel Admin (di bawah Dashboard/Analitik)" || echo "  PERINGATAN: menu tidak terpasang (pola layout berbeda). Halaman tetap dapat dibuka di /panel."
else
  echo "  PERINGATAN: tautan menu Kriteria tidak ditemukan di layout. Tambahkan tautan ke route('panel') secara manual; halaman dapat dibuka di /panel."
fi

php artisan optimize:clear >/dev/null 2>&1 || true
echo ""
echo "Selesai. Buka menu Panel Admin di sidebar (alamat: /panel)."
echo "Hak akses: dapat dilihat publik; tombol aksi cepat dan kartu Pengguna hanya tampil bagi yang sudah login. Tidak ada data yang diubah."
echo "Jika memakai cache produksi: php artisan config:cache && php artisan route:cache && php artisan view:cache"
