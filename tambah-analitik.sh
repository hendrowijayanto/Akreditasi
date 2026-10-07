#!/usr/bin/env bash
# =====================================================================
# HALAMAN ANALITIK AKREDITASI (dashboard data analytic berbasis grafik vektor SVG)
# Sistem Informasi Akreditasi Program Studi Teknologi Informasi
# Sekolah Vokasi Universitas Tiga Serangkai
#
# Menambah menu "Analitik" (di bawah Dashboard) berisi analisis dari data yang ada:
#   - Sorotan otomatis (kriteria terendah/terbaik, butir tanpa dokumen, tren aktivitas, LKPS)
#   - 4 KPI dengan sparkline (kesiapan, butir siap, total dokumen, aktivitas 30 hari)
#   - Aktivitas pengisian per bulan (3/6/12 bulan), status butir, peta panas
#     kriteria x ukuran, corong kelengkapan, jenis dokumen, dan butir prioritas
#
# AMAN: hanya MEMBACA data. Tidak ada tabel baru, tidak ada migration, tidak ada
# perubahan data. routes/web.php dan layout hanya disisipi blok kecil (cadangan *.bak10).
# LKPS dan Data Induk dibaca otomatis bila terpasang. Aman diulang.
#
# Pemakaian (di root proyek):  bash tambah-analitik.sh [--timpa]
#   --timpa   timpa berkas Analitik yang sudah ada (yang lama dicadangkan *.bak10)
# =====================================================================
set -e
if [ ! -f artisan ]; then echo "Error: jalankan di root proyek Laravel."; exit 1; fi
TIMPA=0
for a in "$@"; do
  case "$a" in --timpa) TIMPA=1;; -h|--help) sed -n '2,20p' "$0"; exit 0;; *) echo "Opsi tidak dikenal: $a"; exit 1;; esac
done
R=routes/web.php
L=resources/views/layout.blade.php

echo "[1/3] Pemeriksaan..."
[ -f "$R" ] || { echo "Error: $R tidak ditemukan."; exit 1; }
if [ ! -f "$L" ] || ! grep -q "yield('content')" "$L"; then echo "Error: layout aplikasi tidak ditemukan atau tidak memakai @yield('content')."; exit 1; fi
command -v perl >/dev/null 2>&1 || { echo "Error: perl dibutuhkan."; exit 1; }
if ! grep -rqs "isi_kriteria" database/migrations; then echo "PERINGATAN: migration tabel isi_kriteria tidak ditemukan; halaman Analitik membutuhkan tabel kriterias, isi_kriteria, dan dokumen."; fi
if ! grep -q "'isi'" "$R"; then echo "PERINGATAN: route isi.show tidak terdeteksi; tautan 'Buka' pada Butir Prioritas mungkin tidak berfungsi."; fi
echo "  OK"

tulis() {   # tulis <path> (isi dari stdin). Berkas yang sudah ada tidak ditimpa kecuali --timpa
  local f="$1"
  if [ -f "$f" ] && [ "$TIMPA" != 1 ]; then cat >/dev/null; echo "  (sudah ada, dilewati) $f"; return 0; fi
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] && cp "$f" "$f.bak10"
  cat > "$f"
  echo "  OK  $f"
}

echo "[2/3] Menulis berkas Analitik..."
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

tulis app/Http/Controllers/AnalitikController.php <<'EOF'
<?php

namespace App\Http\Controllers;

use App\Support\Analitik;
use Illuminate\Http\Request;

class AnalitikController extends Controller
{
    public function index(Request $request)
    {
        return view('analitik.index', ['a' => Analitik::data((int) $request->query('periode', 12))]);
    }
}
EOF

tulis resources/views/analitik/_gaya.blade.php <<'EOF'
<style>
.an-head{display:flex;justify-content:space-between;align-items:flex-end;flex-wrap:wrap;gap:12px;margin-bottom:16px}
.an-head h1{font-size:27px;font-weight:700;letter-spacing:-.02em;margin:2px 0 0}
.an-head p{margin:3px 0 0;color:var(--muted,#667085);font-size:13.5px}
.an-ey{font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:var(--muted,#667085);font-weight:600}
.an-pill{display:inline-flex;background:var(--head,#f7f9fc);border:1px solid var(--line,#e4e8ef);border-radius:999px;padding:3px}
.an-pill a{padding:5px 15px;border-radius:999px;font-size:13px;color:var(--muted,#667085);text-decoration:none;font-weight:600}
.an-pill a.on{background:var(--card,#fff);color:var(--pri,#1d4ed8);box-shadow:0 1px 3px rgba(16,24,40,.14)}
.an-ins{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:12px;margin-bottom:14px}
.an-in{display:flex;gap:12px;padding:14px 16px;background:var(--card,#fff);border:1px solid var(--line,#e4e8ef);border-left:4px solid var(--c);border-radius:14px}
.an-ic{position:relative;flex:none;width:36px;height:36px;border-radius:10px;display:grid;place-items:center;color:var(--c);overflow:hidden}
.an-ic::before{content:"";position:absolute;inset:0;background:var(--c);opacity:.12}
.an-ic svg{position:relative;width:20px;height:20px}
.an-in b{display:block;font-size:14px}
.an-in p{margin:2px 0 0;font-size:12.5px;color:var(--muted,#667085);line-height:1.45}
.an-kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(235px,1fr));gap:14px;margin-bottom:14px}
.an-kpi,.an-card{position:relative;background:var(--card,#fff);border:1px solid var(--line,#e4e8ef);border-radius:16px;padding:16px 18px;box-shadow:0 1px 2px rgba(16,24,40,.04)}
.an-kpi::before{content:"";position:absolute;left:0;top:16px;bottom:16px;width:4px;border-radius:0 4px 4px 0;background:var(--c)}
.an-big{font-size:32px;font-weight:700;letter-spacing:-.02em;line-height:1.1;margin-top:6px}
.an-sub{font-size:12.5px;font-weight:600;color:var(--c);margin-top:4px}
.an-kr{display:flex;justify-content:space-between;align-items:flex-end;gap:10px}
.an-pgs{display:block;width:100%;height:6px;margin-top:12px}
.an-g2{display:grid;grid-template-columns:minmax(0,2fr) minmax(0,1fr);gap:14px;margin-bottom:14px}
.an-g3{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:14px;margin-bottom:14px}
@media(max-width:980px){.an-g2{grid-template-columns:minmax(0,1fr)}}
.an-card h2{font-size:17px;font-weight:700;margin:2px 0 10px;letter-spacing:-.01em}
.an-spark{display:block;flex:none}
.an-tumpuk,.an-heat,.an-corong{display:block;width:100%;height:auto}
.an-heat{max-width:430px}
.an-lg{display:flex;gap:16px;flex-wrap:wrap;font-size:12.5px;color:var(--muted,#667085);margin-bottom:6px}
.an-lg i{display:inline-block;width:10px;height:10px;border-radius:3px;margin-right:6px;vertical-align:-1px}
.an-lg b{color:var(--text,#1b2536);margin-left:4px}
.an-dw{display:flex;align-items:center;gap:16px;flex-wrap:wrap}
.an-leg{list-style:none;margin:0;padding:0;flex:1;min-width:150px}
.an-leg li{display:flex;align-items:center;gap:8px;padding:6px 0;font-size:13px;border-top:1px solid var(--line,#e4e8ef)}
.an-leg li:first-child{border-top:0}
.an-leg i{width:10px;height:10px;border-radius:50%;flex:none}
.an-leg span{margin-left:auto;font-weight:700}
.an-leg small{color:var(--muted,#667085);margin-left:6px;font-weight:400}
.an-skala{display:flex;align-items:center;gap:8px;font-size:11px;color:var(--muted,#667085);margin-top:8px}
.an-skala i{flex:1;max-width:200px;height:8px;border-radius:4px;background:linear-gradient(90deg,#fca5a5,#fde68a,#6ee7b7)}
.an-tb{width:100%;border-collapse:collapse;font-size:13.5px}
.an-tb th{font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:var(--muted,#667085);text-align:left;padding:8px 10px;border-bottom:1px solid var(--line,#e4e8ef)}
.an-tb td{padding:10px;border-bottom:1px solid var(--line,#e4e8ef);vertical-align:middle}
.an-tb tr:last-child td{border-bottom:0}
.an-chip{display:inline-block;font-size:11.5px;font-weight:600;padding:2px 9px;border-radius:999px;margin:0 4px 4px 0;background:#fdeed8;color:#b45309}
.an-chip.rose{background:#fde4e1;color:#be123c}
.an-kosong{color:var(--muted,#667085);font-size:13.5px;margin:6px 0 0}
@keyframes anb{from{transform:scaleY(0)}}
.an-tumpuk rect,.an-tumpuk path{transform-box:fill-box;transform-origin:bottom;animation:anb .8s ease-out both}
@media(prefers-reduced-motion:reduce){.an-tumpuk rect,.an-tumpuk path{animation:none}}
</style>
EOF

tulis resources/views/analitik/index.blade.php <<'EOF'
@extends('layout')
@section('title', 'Analitik')
@section('content')
@includeIf('dash._pilih', ['aktif' => 'analitik'])
@include('analitik._gaya')
@php
    $bln = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    $warnaJenis = ['PDF' => '#e11d48', 'Word' => '#2563eb', 'Excel' => '#059669', 'PowerPoint' => '#d97706', 'Gambar' => '#7c3aed', 'Arsip' => '#64748b', 'Tautan' => '#0ea5e9', 'Lainnya' => '#94a3b8'];
    $nB = $a['butir_total'];
    $persenSiap = $nB ? (int) round($a['butir_siap'] / $nB * 100) : 0;
    $baru4 = $a['kum_dok'][11] - $a['kum_dok'][7];
    $statusDef = [['siap', 'Siap (narasi, dokumen, ≥80%)', '#10b981'], ['sebagian', 'Sebagian terisi', '#f59e0b'], ['belum', 'Belum dimulai', '#ef4444']];
@endphp

<div class="an-head">
  <div>
    <div class="an-ey">Analitik</div>
    <h1>Analitik Akreditasi</h1>
    <p>Analisis kesiapan, kelengkapan, dan aktivitas pengisian &middot; data per {{ date('j') . ' ' . $bln[(int) date('n') - 1] . ' ' . date('Y, H:i') }}</p>
  </div>
  <nav class="an-pill" aria-label="Periode aktivitas">
    @foreach([3, 6, 12] as $p)<a href="{{ route('analitik', ['periode' => $p]) }}" class="{{ $a['bulan'] == $p ? 'on' : '' }}">{{ $p }} bulan</a>@endforeach
  </nav>
</div>

<section class="an-ins" aria-label="Sorotan">
  @foreach($a['sorotan'] as $s)
    <article class="an-in" style="--c: {{ $s['warna'] }}"><span class="an-ic">@include('vk.ikon', ['n' => $s['ikon']])</span><div><b>{{ $s['judul'] }}</b><p>{{ $s['teks'] }}</p></div></article>
  @endforeach
</section>

<section class="an-kpis">
  <div class="an-kpi" style="--c:#2563eb">
    <div class="an-ey">Kesiapan keseluruhan</div><div class="an-big">{{ $a['kesiapan'] }}%</div><div class="an-sub">rata-rata isian, narasi, dokumen</div>
    <svg class="an-pgs" viewBox="0 0 100 6" preserveAspectRatio="none" aria-hidden="true"><rect width="100" height="6" rx="3" fill="var(--line)"/><rect width="{{ max(0, min(100, $a['kesiapan'])) }}" height="6" rx="3" fill="#2563eb"/></svg>
  </div>
  <div class="an-kpi" style="--c:#7c3aed">
    <div class="an-ey">Butir siap</div><div class="an-big">{{ $a['butir_siap'] }} <span style="font-size:18px;font-weight:600;color:var(--muted)">/ {{ $nB }}</span></div><div class="an-sub">{{ $persenSiap }}% butir sudah siap</div>
    <svg class="an-pgs" viewBox="0 0 100 6" preserveAspectRatio="none" aria-hidden="true"><rect width="100" height="6" rx="3" fill="var(--line)"/><rect width="{{ $persenSiap }}" height="6" rx="3" fill="#7c3aed"/></svg>
  </div>
  <div class="an-kpi" style="--c:#0d9488"><div class="an-kr"><div>
    <div class="an-ey">Total dokumen</div><div class="an-big">{{ $a['dokumen_total'] }}</div><div class="an-sub">+{{ $baru4 }} dalam 4 minggu</div></div>
    @include('vk.spark', ['vals' => $a['kum_dok'], 'color' => '#0d9488', 'w' => 110, 'h' => 44])</div>
  </div>
  <div class="an-kpi" style="--c:#d97706"><div class="an-kr"><div>
    <div class="an-ey">Aktivitas 30 hari</div><div class="an-big">{{ $a['a30'] }}</div>
    <div class="an-sub">@if($a['delta'] === null){{ $a['a30'] > 0 ? 'mulai aktif' : 'belum ada aktivitas' }}@else{{ $a['delta'] > 0 ? '▲ ' : ($a['delta'] < 0 ? '▼ ' : '') }}{{ $a['delta'] === 0 ? 'stabil' : abs($a['delta']) . '% vs 30 hari lalu' }}@endif</div></div>
    @include('vk.spark', ['vals' => $a['mingguan'], 'color' => '#d97706', 'w' => 110, 'h' => 44])</div>
  </div>
</section>

<div class="an-g2">
  <section class="an-card">
    <div class="an-ey">Aktivitas pengisian</div><h2>Per bulan, {{ $a['bulan'] }} bulan terakhir</h2>
    <div class="an-lg">@foreach($a['seri'] as $s)<span><i style="background:{{ $s['color'] }}"></i>{{ $s['name'] }}<b>{{ array_sum($s['vals']) }}</b></span>@endforeach</div>
    @include('vk.tumpuk', ['labels' => $a['labels'], 'series' => $a['seri']])
  </section>
  <section class="an-card">
    <div class="an-ey">Status butir</div><h2>Sebaran kesiapan</h2>
    @if($nB)
      <div class="an-dw">
        @include('vk.donat', ['segs' => array_map(fn ($d) => ['label' => $d[1], 'v' => $a['status'][$d[0]], 'color' => $d[2]], $statusDef), 'size' => 150, 'pusat' => (string) $nB, 'sub' => 'BUTIR', 'label' => 'Status butir'])
        <ul class="an-leg">@foreach($statusDef as $d)<li><i style="background:{{ $d[2] }}"></i>{{ $d[1] }}<span>{{ $a['status'][$d[0]] }}<small>{{ (int) round($a['status'][$d[0]] / $nB * 100) }}%</small></span></li>@endforeach</ul>
      </div>
    @else
      <p class="an-kosong">Belum ada butir. @auth<a href="{{ route('kriteria.index') }}">Mulai dari Kriteria</a>@endauth</p>
    @endif
  </section>
</div>

<div class="an-g3">
  <section class="an-card">
    <div class="an-ey">Peta panas</div><h2>Capaian kriteria &times; ukuran</h2>
    @if(count($a['kriteria']))
      @include('vk.peta', ['cols' => ['Isian', 'Narasi', 'Dokumen'], 'rows' => array_map(fn ($k) => ['k' => $k['kode'], 't' => $k['kode'] . ' - ' . $k['nama'], 'v' => [$k['isian'], $k['narasi'], $k['dokumen']]], $a['kriteria'])])
      <div class="an-skala"><span>rendah</span><i></i><span>tinggi</span></div>
    @else<p class="an-kosong">Belum ada kriteria.</p>@endif
  </section>
  <section class="an-card">
    <div class="an-ey">Corong</div><h2>Dari butir sampai siap</h2>
    @if($nB)
      @include('vk.corong', ['stages' => array_map(fn ($l, $n, $c) => ['label' => $l, 'n' => $n, 'color' => $c], ['Seluruh butir', 'Narasi terisi', 'Narasi + dokumen', 'Siap (≥80%)'], $a['corong'], ['#2563eb', '#3b6fe0', '#6d5bd6', '#10b981'])])
    @else<p class="an-kosong">Belum ada butir.</p>@endif
  </section>
  <section class="an-card">
    <div class="an-ey">Jenis dokumen</div><h2>Seluruh berkas dan tautan</h2>
    @if($a['dokumen_total'])
      <div class="an-dw">
        @include('vk.donat', ['segs' => array_map(fn ($j, $n) => ['label' => $j, 'v' => $n, 'color' => $warnaJenis[$j] ?? '#94a3b8'], array_keys($a['jenis']), array_values($a['jenis'])), 'size' => 140, 'pusat' => (string) $a['dokumen_total'], 'sub' => 'DOKUMEN', 'label' => 'Jenis dokumen'])
        <ul class="an-leg">@foreach($a['jenis'] as $j => $n)<li><i style="background:{{ $warnaJenis[$j] ?? '#94a3b8' }}"></i>{{ $j }}<span>{{ $n }}<small>{{ (int) round($n / $a['dokumen_total'] * 100) }}%</small></span></li>@endforeach</ul>
      </div>
    @else<p class="an-kosong">Belum ada dokumen.</p>@endif
  </section>
</div>

<section class="an-card">
  <div class="an-ey">Butir prioritas</div><h2>Celah terbesar yang perlu segera dilengkapi</h2>
  @if(count($a['prioritas']))
    <div class="table-responsive"><table class="an-tb">
      <thead><tr><th>Butir</th><th>Kekurangan</th><th style="width:26%">Isian</th><th></th></tr></thead>
      <tbody>
      @foreach($a['prioritas'] as $b)
        <tr>
          <td><strong>{{ $b['kode'] }}</strong> &middot; {{ $b['butir'] }}</td>
          <td>@if(! $b['narasi'])<span class="an-chip rose">Narasi kosong</span>@endif @if($b['dok'] === 0)<span class="an-chip">Tanpa dokumen</span>@endif @if($b['persen'] < 80)<span class="an-chip">Isian {{ $b['persen'] }}%</span>@endif</td>
          <td><svg viewBox="0 0 100 8" preserveAspectRatio="none" width="100%" height="8" aria-hidden="true"><rect width="100" height="8" rx="4" fill="var(--line)"/><rect width="{{ $b['persen'] }}" height="8" rx="4" fill="{{ $b['persen'] >= 80 ? '#10b981' : ($b['persen'] >= 50 ? '#f59e0b' : '#ef4444') }}"/></svg></td>
          <td class="text-end"><a href="{{ route('isi.show', $b['id']) }}" class="text-decoration-none">Buka &rarr;</a></td>
        </tr>
      @endforeach
      </tbody>
    </table></div>
  @else
    <p class="an-kosong">Semua butir sudah lengkap. Tidak ada celah yang perlu ditindaklanjuti.</p>
  @endif
</section>

<p class="text-muted small mt-3" style="max-width:80ch">Definisi: butir <strong>siap</strong> bila narasi terisi, memiliki minimal satu dokumen, dan isian &ge; 80%. Aktivitas dihitung dari tanggal tambah/ubah data (dokumen, Data Induk{{ $a['lkps'] ? ', LKPS' : '' }}, dan pembaruan butir). Seluruh angka dibaca langsung dari data yang ada; tidak ada data yang diubah.</p>
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

tulis resources/views/vk/donat.blade.php <<'EOF'
@php
    $size = $size ?? 170; $pusat = $pusat ?? ''; $sub = $sub ?? ''; $sw = $sw ?? 15; $label = $label ?? '';
    $tot = array_sum(array_column($segs, 'v')); $C = 263.89; $cum = 0;
    $aktif = count(array_filter($segs, fn ($s) => $s['v'] > 0));
@endphp
<svg class="an-donut" viewBox="0 0 100 100" width="{{ $size }}" height="{{ $size }}" role="img" aria-label="{{ $label }}"><title>{{ $label }}</title><circle cx="50" cy="50" r="42" fill="none" stroke="var(--line)" stroke-width="{{ $sw }}" opacity=".6"/>@foreach($segs as $s)@if($s['v'] > 0 && $tot > 0)@php $L = max(0, $s['v'] / $tot * $C - ($aktif > 1 ? 2.2 : 0)); $off = $cum > 0 ? -$cum : 0; @endphp<circle cx="50" cy="50" r="42" fill="none" stroke="{{ $s['color'] }}" stroke-width="{{ $sw }}" stroke-dasharray="{{ number_format($L, 2, '.', '') }} {{ $C }}" stroke-dashoffset="{{ number_format($off, 2, '.', '') }}" transform="rotate(-90 50 50)"><title>{{ $s['label'] }}: {{ $s['v'] }}</title></circle>@php $cum += $s['v'] / $tot * $C; @endphp @endif @endforeach<text x="50" y="{{ $sub ? 52 : 57 }}" text-anchor="middle" font-size="22" font-weight="700" fill="var(--text)">{{ $pusat }}</text>@if($sub)<text x="50" y="64" text-anchor="middle" font-size="7.2" fill="var(--muted)" letter-spacing=".06em">{{ $sub }}</text>@endif</svg>
EOF

tulis resources/views/vk/tumpuk.blade.php <<'EOF'
@php
    // $labels: ['Okt', ...]; $series: [['name' => , 'color' => , 'vals' => [...]], ...]
    $W = 640; $H = 250; $L = 34; $B = 28; $T = 14; $R = 8; $pw = $W - $L - $R; $ph = $H - $T - $B; $n = count($labels);
    $f1 = fn ($x) => number_format($x, 1, '.', '');
    $tot = []; foreach ($labels as $i => $_) { $tot[$i] = array_sum(array_map(fn ($s) => $s['vals'][$i], $series)); }
    $mx0 = max(1, ...$tot);
    $st = 1000; foreach ([1, 2, 5, 10, 20, 25, 50, 100, 200, 500, 1000] as $c) { if ($mx0 / $c <= 5) { $st = $c; break; } }
    $mx = (int) ceil($mx0 / $st) * $st; $nk = (int) ($mx / $st);
    $bw = min(34, $pw / $n * 0.56);
@endphp
<svg class="an-tumpuk" viewBox="0 0 {{ $W }} {{ $H }}" role="img" aria-label="Aktivitas pengisian per bulan"><title>Aktivitas pengisian per bulan</title>@for($k = 0; $k <= $nk; $k++)@php $v = $k * $st; $y = $T + $ph - $ph * $v / $mx; @endphp<line x1="{{ $L }}" y1="{{ $f1($y) }}" x2="{{ $W - $R }}" y2="{{ $f1($y) }}" stroke="var(--line)" stroke-dasharray="{{ $k ? '3 4' : '0' }}"/><text x="{{ $L - 8 }}" y="{{ $f1($y + 3.5) }}" text-anchor="end" font-size="10" fill="var(--muted)">{{ $v }}</text>@endfor
@foreach($labels as $i => $lb)@php
    $cx = $L + $pw / $n * ($i + .5); $x = $cx - $bw / 2; $y = $T + $ph;
    $idx = []; foreach ($series as $j => $s) { if ($s['vals'][$i] > 0) { $idx[] = $j; } }
    $top = $idx ? end($idx) : -1;
@endphp @foreach($series as $j => $s)@if($s['vals'][$i] > 0)@php $v = $s['vals'][$i]; $h = $ph * $v / $mx; $y -= $h; @endphp @if($j === $top)<path d="M{{ $f1($x) }},{{ $f1($y + $h) }} L{{ $f1($x) }},{{ $f1($y + 4) }} Q{{ $f1($x) }},{{ $f1($y) }} {{ $f1($x + 4) }},{{ $f1($y) }} L{{ $f1($x + $bw - 4) }},{{ $f1($y) }} Q{{ $f1($x + $bw) }},{{ $f1($y) }} {{ $f1($x + $bw) }},{{ $f1($y + 4) }} L{{ $f1($x + $bw) }},{{ $f1($y + $h) }} Z" fill="{{ $s['color'] }}"><title>{{ $lb }}: {{ $s['name'] }} {{ $v }}</title></path>@else<rect x="{{ $f1($x) }}" y="{{ $f1($y) }}" width="{{ $f1($bw) }}" height="{{ $f1($h) }}" fill="{{ $s['color'] }}"><title>{{ $lb }}: {{ $s['name'] }} {{ $v }}</title></rect>@endif @endif @endforeach @if($tot[$i] > 0)<text x="{{ $f1($cx) }}" y="{{ $f1($y - 6) }}" text-anchor="middle" font-size="10.5" font-weight="600" fill="var(--text)">{{ $tot[$i] }}</text>@endif<text x="{{ $f1($cx) }}" y="{{ $H - 9 }}" text-anchor="middle" font-size="10.5" fill="var(--muted)">{{ $lb }}</text>@endforeach</svg>
EOF

tulis resources/views/vk/peta.blade.php <<'EOF'
@php
    // $rows: [['k' => 'K1', 't' => 'K1 - Visi', 'v' => [isian, narasi, dokumen]], ...]; $cols: ['Isian', 'Narasi', 'Dokumen']
    $lw = 46; $cw = 92; $ch = 40; $gp = 6; $W = $lw + count($cols) * ($cw + $gp); $H = 26 + count($rows) * ($ch + $gp);
    $hex = fn ($h) => [hexdec(substr($h, 1, 2)), hexdec(substr($h, 3, 2)), hexdec(substr($h, 5, 2))];
    $skala = function ($v) use ($hex) {
        $v = max(0, min(100, $v)); $S = [[0, '#fca5a5'], [50, '#fde68a'], [100, '#6ee7b7']];
        for ($i = 0; $i < 2; $i++) {
            [$a, $ca] = $S[$i]; [$b, $cb] = $S[$i + 1];
            if ($v <= $b) { $t = ($v - $a) / ($b - $a); $A = $hex($ca); $B = $hex($cb); $o = '#';
                foreach ([0, 1, 2] as $k) { $o .= str_pad(dechex((int) round($A[$k] + ($B[$k] - $A[$k]) * $t)), 2, '0', STR_PAD_LEFT); } return $o; }
        }
    };
@endphp
<svg class="an-heat" viewBox="0 0 {{ $W }} {{ $H }}" role="img" aria-label="Peta panas capaian"><title>Peta panas capaian per kriteria</title>@foreach($cols as $j => $c)<text x="{{ $lw + $j * ($cw + $gp) + $cw / 2 }}" y="14" text-anchor="middle" font-size="11" font-weight="600" fill="var(--muted)">{{ $c }}</text>@endforeach
@foreach($rows as $i => $r)@php $y = 26 + $i * ($ch + $gp); @endphp<text x="0" y="{{ $y + $ch / 2 + 4 }}" font-size="12.5" font-weight="700" fill="var(--text)">{{ $r['k'] }}<title>{{ $r['t'] ?? $r['k'] }}</title></text>@foreach($r['v'] as $j => $v)@php $x = $lw + $j * ($cw + $gp); @endphp<rect x="{{ $x }}" y="{{ $y }}" width="{{ $cw }}" height="{{ $ch }}" rx="9" fill="{{ $skala($v) }}"><title>{{ $r['k'] }} - {{ $cols[$j] }}: {{ $v }}%</title></rect><text x="{{ $x + $cw / 2 }}" y="{{ $y + $ch / 2 + 4.5 }}" text-anchor="middle" font-size="13" font-weight="700" fill="#1f2937">{{ $v }}%</text>@endforeach @endforeach</svg>
EOF

tulis resources/views/vk/corong.blade.php <<'EOF'
@php
    // $stages: [['label' => , 'n' => , 'color' => ], ...] (tahap pertama = total)
    $W = 420; $rh = 54; $tot = max(1, $stages[0]['n']); $f1 = fn ($x) => number_format($x, 1, '.', '');
@endphp
<svg class="an-corong" viewBox="0 0 {{ $W }} {{ count($stages) * $rh + 4 }}" role="img" aria-label="Corong kelengkapan butir"><title>Corong kelengkapan butir</title>@foreach($stages as $i => $s)@php $w = 120 + ($W - 120) * $s['n'] / $tot; $x = ($W - $w) / 2; $y = $i * $rh + 4; $pc = (int) round($s['n'] / $tot * 100); @endphp<rect x="{{ $f1($x) }}" y="{{ $y }}" width="{{ $f1($w) }}" height="38" rx="10" fill="{{ $s['color'] }}" fill-opacity="{{ number_format(1 - $i * 0.12, 2, '.', '') }}"><title>{{ $s['label'] }}: {{ $s['n'] }}</title></rect><text x="{{ $W / 2 }}" y="{{ $y + 17 }}" text-anchor="middle" font-size="12" font-weight="600" fill="#fff">{{ $s['label'] }}</text><text x="{{ $W / 2 }}" y="{{ $y + 31 }}" text-anchor="middle" font-size="11" fill="#fff" fill-opacity=".9">{{ $s['n'] }} butir &#183; {{ $pc }}%</text>@endforeach</svg>
EOF

tulis resources/views/vk/ikon.blade.php <<'EOF'
@php $paths = [
    'target' => '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="4.5"/><circle cx="12" cy="12" r="1" fill="currentColor"/>',
    'alert'  => '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>',
    'trophy' => '<path d="M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0V4z"/><path d="M7 6H4a3 3 0 0 0 3 4M17 6h3a3 3 0 0 1-3 4"/>',
    'trend'  => '<path d="m3 17 6-6 4 4 8-8"/><path d="M14 7h7v7"/>',
    'grid'   => '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
]; @endphp
<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{!! $paths[$n] ?? $paths['grid'] !!}</svg>
EOF

for f in app/Support/Analitik.php app/Http/Controllers/AnalitikController.php; do
  php -l "$f" >/dev/null || { echo "GAGAL: kesalahan sintaks pada $f"; exit 1; }
done
echo "  OK  sintaks berkas PHP"

echo "[3/3] Menyisipkan route dan menu..."
if grep -q "AnalitikController" "$R"; then
  echo "  (route Analitik sudah ada, dilewati)"
else
  cp "$R" "$R.bak10"
  cat >> "$R" <<'EOF'

// ===== Analitik (baca publik) =====
Route::get('/analitik', [\App\Http\Controllers\AnalitikController::class, 'index'])->name('analitik');
EOF
  php -l "$R" >/dev/null || { echo "GAGAL: routes/web.php tidak valid. Pulihkan dari $R.bak10"; exit 1; }
  echo "  OK  $R"
fi

if grep -q "route('analitik')" "$L"; then
  echo "  (menu Analitik sudah ada, dilewati)"
elif grep -q "route('kriteria.index')" "$L"; then
  cp "$L" "$L.bak10"
  M=$(cat <<'EOF'
      @if(Route::has('analitik'))
      <a class="mi {{ request()->routeIs('analitik') ? 'on' : '' }}" href="{{ route('analitik') }}">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/></svg>Analitik
      </a>
      @endif
EOF
)
  export M
  perl -0pi -e 's/(^[ \t]*<a class="mi [^\n]*route\(\x27kriteria\.index\x27\)[^\n]*>\n)/$ENV{M}\n$1/m' "$L"
  grep -q "route('analitik')" "$L" && echo "  OK  menu Analitik (di bawah Dashboard)" || echo "  PERINGATAN: menu tidak terpasang (pola layout berbeda). Halaman tetap dapat dibuka di /analitik."
else
  echo "  PERINGATAN: tautan menu Kriteria tidak ditemukan di layout. Tambahkan tautan ke route('analitik') secara manual; halaman dapat dibuka di /analitik."
fi

php artisan optimize:clear >/dev/null 2>&1 || true
echo ""
echo "Selesai. Buka menu Analitik di sidebar (alamat: /analitik)."
echo "Hak akses: dapat dilihat publik, sama seperti Dashboard. Tidak ada data yang diubah."
echo "Jika memakai cache produksi: php artisan config:cache && php artisan route:cache && php artisan view:cache"
