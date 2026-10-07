#!/usr/bin/env bash
# =============================================================================
#  ganti-analitik-lima-aspek.sh
#  Mengganti isi halaman ANALITIK dengan lima aspek:
#   1. Budaya Mutu            (Kriteria C1 + Dokumen Standar Mutu)
#   2. Relevansi Pendidikan   (Dosen Homebase: gelar & jabatan, beban DTPR, masa tunggu, kondisi mahasiswa)
#   3. Relevansi Penelitian   (Publikasi + HKI)
#   4. Relevansi PkM          (Kerja sama, diseminasi, HKI PkM)
#   5. Akuntabilitas          (Tata kelola + Sarana prasarana)
#  Tulisan "Analisis kesiapan, kelengkapan, dan aktivitas pengisian - data per ..." dihapus.
#
#  AMAN: hanya membaca data; tidak ada tabel/kolom/data yang diubah. Berkas lama
#  (AnalitikController.php, analitik/index.blade.php) dicadangkan *.bak15. Aman diulang.
#  Prasyarat: tambah-analitik.sh sudah dijalankan. LKPS (tambah-lkps.sh) opsional:
#  tanpa LKPS, panel terkait menampilkan "Belum ada data".
#  Pakai:  bash ganti-analitik-lima-aspek.sh        (di root proyek Laravel)
# =============================================================================
set -u
if [ ! -f artisan ]; then echo "Error: jalankan di root proyek Laravel."; exit 1; fi
for f in app/Support/Analitik.php resources/views/vk/donat.blade.php resources/views/analitik/_gaya.blade.php app/Http/Controllers/AnalitikController.php; do
  [ -f "$f" ] || { echo "Error: $f tidak ada. Jalankan tambah-analitik.sh lebih dulu."; exit 1; }
done
MARK="ANALITIK-LIMA-ASPEK"
echo "[1/3] Menulis berkas Analitik lima aspek..."
tulis() {   # tulis <path>  (isi dari stdin): menimpa hanya bila versi lama belum bertanda; cadangan *.bak15
  local f="$1" tmp; tmp=$(mktemp); cat > "$tmp"
  if [ -f "$f" ] && grep -q "$MARK" "$f" && cmp -s "$tmp" "$f"; then rm -f "$tmp"; chmod 644 "$f" 2>/dev/null || true; echo "  (sudah terbaru) $f"; return 0; fi
  mkdir -p "$(dirname "$f")"
  if [ -f "$f" ] && ! grep -q "$MARK" "$f"; then cp "$f" "$f.bak15"; fi
  cp "$tmp" "$f"; rm -f "$tmp"; chmod 644 "$f" 2>/dev/null || true   # mktemp membuat berkas 0600: server web harus bisa membacanya
  echo "  OK  $f"
}

tulis app/Support/AnalitikLima.php <<'EOFLIMA'
<?php
// ANALITIK-LIMA-ASPEK

namespace App\Support;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Data halaman Analitik lima aspek (hanya MEMBACA data yang sudah ada):
 *  1. Budaya Mutu            : Kriteria C1 Budaya Mutu + Dokumen Standar Mutu
 *  2. Relevansi Pendidikan   : Dosen Homebase (gelar, jabatan), EWMP, masa tunggu, kondisi mahasiswa
 *  3. Relevansi Penelitian   : Publikasi penelitian + HKI penelitian
 *  4. Relevansi PkM          : Kerja sama PkM, diseminasi PkM, HKI PkM
 *  5. Akuntabilitas          : Tata kelola + sarana prasarana pendidikan
 * Fungsi-fungsi murni (hitung*) tidak mengakses database sehingga mudah diuji.
 */
class AnalitikLima
{
    public const TS = ['ts2' => 'TS-2', 'ts1' => 'TS-1', 'ts' => 'TS'];
    public const JABATAN = ['Tenaga Pengajar', 'Asisten Ahli', 'Lektor', 'Lektor Kepala', 'Guru Besar'];

    // ---------------------------------------------------------------- akses data
    /** Pesan galat per bagian (agar satu sumber yang bermasalah tidak membuat seluruh halaman error 500). */
    public static array $galat = [];

    private static function lkps(string $slug): array
    {
        try {
            if (! class_exists(Lkps::class)) {
                return [];
            }
            $t = Lkps::namaTabel($slug);
            if (! Schema::hasTable($t)) {
                return [];
            }

            return DB::table($t)->get()->map(fn ($r) => (array) $r)->all();
        } catch (\Throwable $e) {
            self::catat('tabel ' . $slug, $e);

            return [];
        }
    }

    private static function catat(string $bagian, \Throwable $e): void
    {
        try {
            report($e);
        } catch (\Throwable $x) {
            // abaikan
        }
        self::$galat[$bagian] = get_class($e) . ': ' . $e->getMessage() . ' (' . basename($e->getFile()) . ':' . $e->getLine() . ')';
    }

    private static function aman(string $bagian, callable $fn, callable $kosong): array
    {
        try {
            return $fn();
        } catch (\Throwable $e) {
            self::catat($bagian, $e);

            return $kosong();
        }
    }

    public static function data(): array
    {
        self::$galat = [];
        $a = [
            'mutu' => self::aman('Budaya Mutu', fn () => self::mutu(), fn () => self::hitungMutu(null, [], [])),
            'pendidikan' => self::aman('Relevansi Pendidikan', fn () => self::hitungPendidikan(
                self::lkps('dosen_homebase'), self::lkps('t1a4_ewmp'),
                self::lkps('t2b4_masa_tunggu'), self::lkps('t2a3_kondisi_mahasiswa')
            ), fn () => self::hitungPendidikan([], [], [], [])),
            'penelitian' => self::aman('Relevansi Penelitian', fn () => self::hitungPenelitian(
                self::lkps('t3c2_publikasi'), self::lkps('t3c3_hki_penelitian')
            ), fn () => self::hitungPenelitian([], [])),
            'pkm' => self::aman('Relevansi PkM', fn () => self::hitungPkm(
                self::lkps('t4c1_kerjasama_pkm'), self::lkps('t4c2_diseminasi_pkm'), self::lkps('t4c3_hki_pkm')
            ), fn () => self::hitungPkm([], [], [])),
            'akuntabilitas' => self::aman('Akuntabilitas', fn () => self::hitungAkuntabilitas(
                self::lkps('t5_1_tata_kelola'), self::lkps('t5_2_sarpras_pendidikan')
            ), fn () => self::hitungAkuntabilitas([], [])),
        ];
        $a['galat'] = self::$galat;

        return $a;
    }

    private static function mutu(): array
    {
        $k = DB::table('kriterias')->whereRaw('UPPER(TRIM(kode)) = ?', ['C1'])->first()
            ?? DB::table('kriterias')->whereRaw('LOWER(nama) LIKE ?', ['%budaya mutu%'])->first();
        $butir = [];
        if ($k) {
            $rows = DB::table('isi_kriteria')->where('kriteria_id', $k->id)->orderBy('id')->get();
            $nd = $rows->isEmpty() ? [] : DB::table('dokumen')->whereIn('isi_kriteria_id', $rows->pluck('id'))
                ->selectRaw('isi_kriteria_id, COUNT(*) AS n')->groupBy('isi_kriteria_id')->pluck('n', 'isi_kriteria_id')->all();
            foreach ($rows as $r) {
                $butir[] = [
                    'butir' => (string) $r->butir, 'persen' => (int) $r->persentase,
                    'narasi' => Analitik::narasiTerisi($r->narasi), 'dok' => (int) ($nd[$r->id] ?? 0),
                ];
            }
        }
        $sm = [];
        if (class_exists(DataInduk::class)) {
            foreach (DataInduk::semua('standar-mutu') as $x) {
                $sm[] = ['file' => $x['file'] ?? null, 'link' => $x['link'] ?? null];
            }
        }

        return self::hitungMutu($k ? ['kode' => $k->kode, 'nama' => $k->nama] : null, $butir, $sm);
    }

    // ---------------------------------------------------------------- hitung (murni)
    public static function hitungMutu(?array $kriteria, array $butir, array $standarMutu): array
    {
        $n = count($butir);
        $pct = fn (int $c) => $n ? (int) round($c / $n * 100) : 0;
        $siap = count(array_filter($butir, fn ($b) => $b['narasi'] && $b['dok'] > 0 && $b['persen'] >= 80));
        $isian = $n ? (int) round(array_sum(array_column($butir, 'persen')) / $n) : 0;
        $narasi = $pct(count(array_filter($butir, fn ($b) => $b['narasi'])));
        $dok = $pct(count(array_filter($butir, fn ($b) => $b['dok'] > 0)));
        $jenis = [];
        foreach ($standarMutu as $x) {
            $j = Analitik::jenis($x['file'] ?? null, $x['link'] ?? null);
            $jenis[$j] = ($jenis[$j] ?? 0) + 1;
        }
        arsort($jenis);

        return [
            'kriteria' => $kriteria, 'butir' => $butir, 'n' => $n, 'siap' => $siap,
            'isian' => $isian, 'narasi' => $narasi, 'dokumen' => $dok,
            'kesiapan' => (int) round(($isian + $narasi + $dok) / 3),
            'sm_total' => count($standarMutu), 'sm_jenis' => $jenis,
        ];
    }

    private static function angka($v): float
    {
        return is_numeric($v) ? (float) $v : 0.0;
    }

    private static function hitungTs(array $rows, string $prefix = ''): array
    {
        $o = [];
        foreach (self::TS as $k => $lb) {
            $o[$lb] = count(array_filter($rows, fn ($r) => ! empty($r[$prefix . $k])));
        }

        return $o;
    }

    private static function hitungPer(array $rows, string $kol, array $urut = [], string $kosong = 'Belum diisi'): array
    {
        $o = [];
        foreach ($urut as $u) {
            $o[$u] = 0;
        }
        foreach ($rows as $r) {
            $v = trim((string) ($r[$kol] ?? ''));
            if ($v === '' || $v === '-') {
                $v = $kosong;
            }
            $o[$v] = ($o[$v] ?? 0) + 1;
        }
        foreach ($urut as $u) {
            if ($o[$u] === 0) {
                unset($o[$u]);
            }
        }

        return $o;
    }

    public static function hitungPendidikan(array $dosen, array $ewmp, array $tunggu, array $kondisi): array
    {
        // gelar tertinggi: S3 terisi => Doktor; S2 terisi => Magister; selain itu Lainnya
        $gelar = ['Doktor' => 0, 'Magister' => 0, 'Lainnya' => 0];
        foreach ($dosen as $d) {
            if (trim((string) ($d['pend_s3'] ?? '')) !== '') {
                $gelar['Doktor']++;
            } elseif (trim((string) ($d['pend_s2'] ?? '')) !== '') {
                $gelar['Magister']++;
            } else {
                $gelar['Lainnya']++;
            }
        }
        $jabatan = self::hitungPer($dosen, 'jabatan_fungsional', self::JABATAN, 'Belum ada jabatan');

        $komp = ['sks_ps_sendiri' => 'Mengajar PS sendiri', 'sks_ps_lain' => 'Mengajar PS lain', 'sks_pt_lain' => 'Mengajar PT lain',
            'sks_penelitian' => 'Penelitian', 'sks_pkm' => 'PkM', 'sks_manajemen_pt_sendiri' => 'Manaj. PT sendiri', 'sks_manajemen_pt_lain' => 'Manaj. PT lain'];
        $ne = count($ewmp);
        $rk = [];
        $tot = 0.0;
        foreach ($komp as $k => $lb) {
            $rk[$lb] = $ne ? round(array_sum(array_map(fn ($r) => self::angka($r[$k] ?? 0), $ewmp)) / $ne, 2) : 0.0;
        }
        foreach ($ewmp as $r) {
            $t = self::angka($r['total_sks'] ?? 0);
            $tot += $t > 0 ? $t : array_sum(array_map(fn ($k) => self::angka($r[$k] ?? 0), array_keys($komp)));
        }

        $urut = array_flip(['TS-2', 'TS-1', 'TS']);
        usort($tunggu, fn ($a, $b) => ($urut[$a['tahun_lulus'] ?? ''] ?? 9) <=> ($urut[$b['tahun_lulus'] ?? ''] ?? 9));
        $mt = [];
        $sumW = 0.0; $sumT = 0.0; $lulus = 0; $lacak = 0;
        foreach ($tunggu as $r) {
            $t = self::angka($r['terlacak'] ?? 0);
            $mt[] = ['label' => (string) ($r['tahun_lulus'] ?? '-'), 'v' => self::angka($r['rata_masa_tunggu'] ?? 0)];
            $sumW += self::angka($r['rata_masa_tunggu'] ?? 0) * $t;
            $sumT += $t;
            $lulus += (int) self::angka($r['jumlah_lulusan'] ?? 0);
            $lacak += (int) $t;
        }
        $rataTunggu = $sumT > 0 ? round($sumW / $sumT, 1) : ($mt ? round(array_sum(array_column($mt, 'v')) / count($mt), 1) : null);

        $kon = [];
        foreach ($kondisi as $r) {
            $kon[] = ['label' => (string) ($r['kondisi'] ?? '-'), 'vals' => array_map(fn ($k) => (int) self::angka($r[$k] ?? 0), array_keys(self::TS))];
        }

        return [
            'dosen' => count($dosen), 'gelar' => $gelar, 'jabatan' => $jabatan,
            'ewmp_n' => $ne, 'ewmp_rata' => $ne ? round($tot / $ne, 2) : null, 'ewmp_komp' => $rk,
            'tunggu' => $mt, 'tunggu_rata' => $rataTunggu, 'lulusan' => $lulus, 'terlacak' => $lacak,
            'kondisi' => $kon,
        ];
    }

    public static function hitungPenelitian(array $publikasi, array $hki): array
    {
        return [
            'pub_total' => count($publikasi),
            'pub_jenis' => self::hitungPer($publikasi, 'jenis_publikasi', ['IB', 'I', 'S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'T']),
            'pub_ts' => self::hitungTs($publikasi),
            'hki_total' => count($hki), 'hki_ts' => self::hitungTs($hki),
            'hki_jenis' => self::hitungPer($hki, 'jenis_hki', [], 'Belum diisi'),
        ];
    }

    public static function hitungPkm(array $kerjasama, array $diseminasi, array $hki): array
    {
        $dana = [];
        foreach (self::TS as $k => $lb) {
            $dana[$lb] = round(array_sum(array_map(fn ($r) => self::angka($r['dana_' . $k] ?? 0), $kerjasama)), 2);
        }

        return [
            'ks_total' => count($kerjasama), 'ks_sumber' => self::hitungPer($kerjasama, 'sumber', ['L', 'N', 'I'], 'Belum diisi'), 'ks_dana' => $dana,
            'ds_total' => count($diseminasi), 'ds_level' => self::hitungPer($diseminasi, 'diseminasi', ['L', 'N', 'I'], 'Belum diisi'), 'ds_ts' => self::hitungTs($diseminasi),
            'hki_total' => count($hki), 'hki_ts' => self::hitungTs($hki),
        ];
    }

    public static function hitungAkuntabilitas(array $tata, array $sarpras): array
    {
        return [
            'tk_total' => count($tata),
            'tk_akses' => self::hitungPer($tata, 'akses', ['Lokal', 'Internet']),
            'tk_daftar' => array_map(fn ($r) => ['jenis' => (string) ($r['jenis_tata_kelola'] ?? '-'), 'sistem' => (string) ($r['nama_sistem'] ?? '-')], array_slice($tata, 0, 8)),
            'sp_total' => count($sarpras),
            'sp_daya' => (int) array_sum(array_map(fn ($r) => self::angka($r['daya_tampung'] ?? 0), $sarpras)),
            'sp_luas' => round(array_sum(array_map(fn ($r) => self::angka($r['luas_ruang'] ?? 0), $sarpras)), 1),
            'sp_milik' => self::hitungPer($sarpras, 'kepemilikan', ['M', 'W']),
            'sp_lisensi' => self::hitungPer($sarpras, 'lisensi', ['L', 'P', 'T']),
        ];
    }
}
EOFLIMA

tulis app/Http/Controllers/AnalitikController.php <<'EOFLIMA'
<?php
// ANALITIK-LIMA-ASPEK

namespace App\Http\Controllers;

use App\Support\AnalitikLima;

class AnalitikController extends Controller
{
    public function index()
    {
        try {
            $html = view('analitik.index', ['a' => AnalitikLima::data()])->render();

            return response($html);
        } catch (\Throwable $e) {
            report($e);
            $rinci = config('app.debug') || auth()->check();

            return response()->view('analitik.galat', [
                'pesan' => $rinci ? get_class($e) . ': ' . $e->getMessage() . ' (' . basename($e->getFile()) . ':' . $e->getLine() . ')' : null,
            ], 500);
        }
    }
}
EOFLIMA

tulis resources/views/analitik/index.blade.php <<'EOFLIMA'
{{-- ANALITIK-LIMA-ASPEK --}}
@extends('layout')
@section('title', 'Analitik')
@section('content')
@includeIf('dash._pilih', ['aktif' => 'analitik'])
@include('analitik._gaya')
@include('analitik._gaya_lima')
@php
    $m = $a['mutu']; $p = $a['pendidikan']; $r = $a['penelitian']; $k = $a['pkm']; $u = $a['akuntabilitas'];
    $ada = fn ($rute, $param = []) => \Illuminate\Support\Facades\Route::has($rute) ? route($rute, $param) : '#';
    $lk = fn ($slug) => $ada('lkps.tabel.index', ['tabel' => $slug]);
    $warna = ['#2563eb', '#7c3aed', '#0d9488', '#d97706', '#e11d48', '#059669'];
    $cTs = ['TS-2', 'TS-1', 'TS'];
    $seg = fn (array $arr, array $pal) => array_map(fn ($lb, $v, $c) => ['label' => $lb, 'v' => $v, 'color' => $c], array_keys($arr), array_values($arr), array_slice(array_merge($pal, $pal, $pal), 0, count($arr)));
    $legend = function (array $segs, int $tot) {
        $o = '<ul class="an-leg">';
        foreach ($segs as $s) { $o .= '<li><i style="background:' . e($s['color']) . '"></i>' . e($s['label']) . '<span>' . $s['v'] . '<small>' . ($tot ? (int) round($s['v'] / $tot * 100) : 0) . '%</small></span></li>'; }
        return $o . '</ul>';
    };
    $dokSm = $m['sm_total'];
    $kosongLkps = fn ($slug, $nama) => '<p class="am-kosong">Belum ada data. Isi tabel <a href="' . e($lk($slug)) . '">' . e($nama) . '</a> pada menu LKPS.</p>';
@endphp

@if(! empty($a['galat']))
  <div class="alert alert-warning" role="alert" style="font-size:13.5px"><b>Sebagian data tidak dapat dibaca:</b>
    <ul style="margin:6px 0 0 18px;padding:0">@foreach($a['galat'] as $bagian => $pesan)<li>{{ $bagian }}: {{ $pesan }}</li>@endforeach</ul></div>
@endif

<div class="an-head">
  <div>
    <div class="an-ey">Analitik</div>
    <h1>Analitik Akreditasi</h1>
  </div>
</div>

<div class="am-nav" role="navigation" aria-label="Lima aspek analitik">
  <a class="am-tile" href="#budaya-mutu" style="--c:#2563eb"><div class="an-ey">1. Budaya Mutu</div><div class="an-big">{{ $m['n'] ? $m['kesiapan'] . '%' : '-' }}</div><small>kesiapan C1 &middot; {{ $dokSm }} dokumen standar mutu</small></a>
  <a class="am-tile" href="#relevansi-pendidikan" style="--c:#7c3aed"><div class="an-ey">2. Relevansi Pendidikan</div><div class="an-big">{{ $p['dosen'] }}</div><small>dosen homebase &middot; {{ $p['gelar']['Doktor'] }} Doktor, {{ $p['gelar']['Magister'] }} Magister</small></a>
  <a class="am-tile" href="#relevansi-penelitian" style="--c:#0d9488"><div class="an-ey">3. Relevansi Penelitian</div><div class="an-big">{{ $r['pub_total'] + $r['hki_total'] }}</div><small>{{ $r['pub_total'] }} publikasi &middot; {{ $r['hki_total'] }} HKI</small></a>
  <a class="am-tile" href="#relevansi-pkm" style="--c:#d97706"><div class="an-ey">4. Relevansi PkM</div><div class="an-big">{{ $k['ks_total'] + $k['ds_total'] + $k['hki_total'] }}</div><small>{{ $k['ks_total'] }} kerja sama &middot; {{ $k['ds_total'] }} diseminasi &middot; {{ $k['hki_total'] }} HKI</small></a>
  <a class="am-tile" href="#akuntabilitas" style="--c:#e11d48"><div class="an-ey">5. Akuntabilitas</div><div class="an-big">{{ $u['tk_total'] + $u['sp_total'] }}</div><small>{{ $u['tk_total'] }} tata kelola &middot; {{ $u['sp_total'] }} sarana prasarana</small></a>
</div>

{{-- ============ 1. BUDAYA MUTU ============ --}}
<header class="am-sec" id="budaya-mutu" style="--c:#2563eb"><h2><i></i>1. Budaya Mutu</h2><p>Dari Kriteria C1 Budaya Mutu dan Dokumen Standar Mutu.</p></header>
<div class="an-g3">
  <section class="an-card">
    <div class="an-ey">Kriteria C1</div><h2>Kesiapan Budaya Mutu</h2>
    @if($m['n'])
      <div class="am-mini"><div><b>{{ $m['kesiapan'] }}%</b><span>kesiapan</span></div><div><b>{{ $m['siap'] }} / {{ $m['n'] }}</b><span>butir siap</span></div></div>
      @include('analitik._batang', ['items' => [['label' => 'Isian', 'v' => $m['isian']], ['label' => 'Narasi terisi', 'v' => $m['narasi']], ['label' => 'Memiliki dokumen', 'v' => $m['dokumen']]], 'color' => '#2563eb', 'satuan' => '%', 'judul' => 'Kesiapan Kriteria C1'])
    @else
      <p class="am-kosong">Kriteria dengan kode <b>C1</b> (Budaya Mutu) belum ada atau belum memiliki butir. @auth<a href="{{ $ada('kriteria.index') }}">Buka Kriteria</a>@endauth</p>
    @endif
  </section>
  <section class="an-card">
    <div class="an-ey">Kriteria C1</div><h2>Isian per butir</h2>
    @if($m['n'])
      @include('analitik._batang', ['items' => array_map(fn ($b) => ['label' => 'Butir ' . $b['butir'], 'v' => $b['persen'], 'color' => $b['persen'] >= 80 ? '#10b981' : ($b['persen'] >= 40 ? '#f59e0b' : '#ef4444')], $m['butir']), 'satuan' => '%', 'judul' => 'Persentase isian per butir C1'])
    @else<p class="am-kosong">Belum ada butir.</p>@endif
  </section>
  <section class="an-card">
    <div class="an-ey">Data Induk</div><h2>Dokumen Standar Mutu</h2>
    @if($dokSm)
      @php $sg = $seg($m['sm_jenis'], ['#e11d48', '#2563eb', '#059669', '#d97706', '#7c3aed', '#0ea5e9', '#64748b']); @endphp
      <div class="an-dw">@include('vk.donat', ['segs' => $sg, 'size' => 140, 'pusat' => (string) $dokSm, 'sub' => 'DOKUMEN', 'label' => 'Jenis Dokumen Standar Mutu']){!! $legend($sg, $dokSm) !!}</div>
    @else<p class="am-kosong">Belum ada Dokumen Standar Mutu. @auth<a href="{{ $ada('datainduk.index', ['kategori' => 'standar-mutu']) }}">Tambah dokumen</a>@endauth</p>@endif
  </section>
</div>

{{-- ============ 2. RELEVANSI PENDIDIKAN ============ --}}
<header class="am-sec" id="relevansi-pendidikan" style="--c:#7c3aed"><h2><i></i>2. Relevansi Pendidikan</h2><p>Dosen homebase (gelar akademik dan jabatan fungsional), rata-rata beban DTPR, masa tunggu lulusan, dan kondisi jumlah mahasiswa.</p></header>
<div class="an-g3">
  <section class="an-card">
    <div class="an-ey">Dosen homebase</div><h2>Gelar akademik</h2>
    @if($p['dosen'])
      @php $sg = $seg($p['gelar'], ['#7c3aed', '#2563eb', '#94a3b8']); @endphp
      <div class="an-dw">@include('vk.donat', ['segs' => $sg, 'size' => 140, 'pusat' => (string) $p['dosen'], 'sub' => 'DOSEN', 'label' => 'Gelar akademik dosen homebase']){!! $legend($sg, $p['dosen']) !!}</div>
      <p class="an-kosong" style="padding:8px 0 0">Doktor bila Pendidikan S3 terisi; Magister bila S2 terisi.</p>
    @else<p class="am-kosong">Belum ada dosen homebase. @auth<a href="{{ $ada('lkps.isian.index') }}#dosen-homebase">Tambah dosen</a>@endauth</p>@endif
  </section>
  <section class="an-card">
    <div class="an-ey">Dosen homebase</div><h2>Jabatan fungsional akademik</h2>
    @if($p['dosen'])
      @include('analitik._batang', ['items' => array_map(fn ($lb, $v) => ['label' => $lb, 'v' => $v], array_keys($p['jabatan']), array_values($p['jabatan'])), 'color' => '#7c3aed', 'satuan' => 'dosen', 'judul' => 'Jabatan fungsional dosen homebase'])
    @else<p class="am-kosong">Belum ada data.</p>@endif
  </section>
  <section class="an-card">
    <div class="an-ey">Tabel 1.A.4</div><h2>Rata-rata beban DTPR</h2>
    @if($p['ewmp_n'])
      <div class="am-mini"><div><b>{{ number_format($p['ewmp_rata'], 2, ',', '.') }}</b><span>SKS per semester (rata-rata {{ $p['ewmp_n'] }} DTPR)</span></div></div>
      @include('analitik._batang', ['items' => array_map(fn ($lb, $v) => ['label' => $lb, 'v' => $v], array_keys($p['ewmp_komp']), array_values($p['ewmp_komp'])), 'color' => '#7c3aed', 'des' => 2, 'satuan' => 'SKS', 'judul' => 'Rata-rata SKS per komponen'])
    @else{!! $kosongLkps('t1a4_ewmp', '1.A.4 Rata-rata Beban DTPR') !!}@endif
  </section>
  <section class="an-card">
    <div class="an-ey">Tabel 2.B.4</div><h2>Rata-rata masa tunggu lulusan</h2>
    @if(count($p['tunggu']))
      <div class="am-mini"><div><b>{{ $p['tunggu_rata'] !== null ? number_format($p['tunggu_rata'], 1, ',', '.') : '-' }}</b><span>bulan (rata-rata tertimbang) &middot; {{ $p['terlacak'] }} dari {{ $p['lulusan'] }} lulusan terlacak</span></div></div>
      @include('analitik._kolom', ['cats' => array_column($p['tunggu'], 'label'), 'series' => [['name' => 'Masa tunggu (bulan)', 'color' => '#0d9488', 'vals' => array_column($p['tunggu'], 'v')]], 'des' => 1, 'judul' => 'Masa tunggu lulusan per tahun lulus'])
    @else{!! $kosongLkps('t2b4_masa_tunggu', '2.B.4 Masa Tunggu Lulusan') !!}@endif
  </section>
  <section class="an-card">
    <div class="an-ey">Tabel 2.A.3</div><h2>Kondisi jumlah mahasiswa</h2>
    @if(count($p['kondisi']))
      <div class="an-lg">@foreach($p['kondisi'] as $i => $c)<span><i style="background:{{ $warna[$i % 6] }}"></i>{{ $c['label'] }}</span>@endforeach</div>
      @include('analitik._kolom', ['cats' => $cTs, 'series' => array_map(fn ($c, $i) => ['name' => $c['label'], 'color' => $warna[$i % 6], 'vals' => $c['vals']], $p['kondisi'], array_keys($p['kondisi'])), 'judul' => 'Kondisi jumlah mahasiswa per tahun'])
    @else{!! $kosongLkps('t2a3_kondisi_mahasiswa', '2.A.3 Kondisi Jumlah Mahasiswa') !!}@endif
  </section>
</div>

{{-- ============ 3. RELEVANSI PENELITIAN ============ --}}
<header class="am-sec" id="relevansi-penelitian" style="--c:#0d9488"><h2><i></i>3. Relevansi Penelitian</h2><p>Dari Publikasi Penelitian (3.C.2) dan Perolehan HKI (3.C.3).</p></header>
<div class="an-g3">
  <section class="an-card">
    <div class="an-ey">Tabel 3.C.2</div><h2>Publikasi per jenis</h2>
    @if($r['pub_total'])
      <div class="am-mini"><div><b>{{ $r['pub_total'] }}</b><span>publikasi</span></div></div>
      @include('analitik._batang', ['items' => array_map(fn ($lb, $v) => ['label' => $lb, 'v' => $v], array_keys($r['pub_jenis']), array_values($r['pub_jenis'])), 'color' => '#0d9488', 'judul' => 'Publikasi per jenis'])
    @else{!! $kosongLkps('t3c2_publikasi', '3.C.2 Publikasi Penelitian') !!}@endif
  </section>
  <section class="an-card">
    <div class="an-ey">Publikasi dan HKI</div><h2>Perkembangan per tahun</h2>
    @if($r['pub_total'] || $r['hki_total'])
      <div class="an-lg"><span><i style="background:#0d9488"></i>Publikasi<b>{{ $r['pub_total'] }}</b></span><span><i style="background:#d97706"></i>HKI<b>{{ $r['hki_total'] }}</b></span></div>
      @include('analitik._kolom', ['cats' => $cTs, 'series' => [['name' => 'Publikasi', 'color' => '#0d9488', 'vals' => array_values($r['pub_ts'])], ['name' => 'HKI', 'color' => '#d97706', 'vals' => array_values($r['hki_ts'])]], 'judul' => 'Publikasi dan HKI penelitian per tahun'])
    @else<p class="am-kosong">Belum ada data publikasi atau HKI.</p>@endif
  </section>
  <section class="an-card">
    <div class="an-ey">Tabel 3.C.3</div><h2>Perolehan HKI</h2>
    @if($r['hki_total'])
      <div class="am-mini"><div><b>{{ $r['hki_total'] }}</b><span>HKI granted</span></div></div>
      @include('analitik._batang', ['items' => array_map(fn ($lb, $v) => ['label' => $lb, 'v' => $v], array_keys($r['hki_jenis']), array_values($r['hki_jenis'])), 'color' => '#d97706', 'judul' => 'HKI penelitian per jenis'])
    @else{!! $kosongLkps('t3c3_hki_penelitian', '3.C.3 Perolehan HKI') !!}@endif
  </section>
</div>

{{-- ============ 4. RELEVANSI PkM ============ --}}
<header class="am-sec" id="relevansi-pkm" style="--c:#d97706"><h2><i></i>4. Relevansi Pengabdian kepada Masyarakat</h2><p>Dari Kerja Sama PkM (4.C.1), Diseminasi Hasil PkM (4.C.2), dan Perolehan HKI PkM (4.C.3). L = Lokal/Wilayah, N = Nasional, I = Internasional.</p></header>
<div class="an-g3">
  <section class="an-card">
    <div class="an-ey">Tabel 4.C.1</div><h2>Kerja sama PkM</h2>
    @if($k['ks_total'])
      @php $sg = $seg($k['ks_sumber'], ['#d97706', '#2563eb', '#059669', '#94a3b8']); @endphp
      <div class="an-dw">@include('vk.donat', ['segs' => $sg, 'size' => 130, 'pusat' => (string) $k['ks_total'], 'sub' => 'KERJA SAMA', 'label' => 'Kerja sama PkM menurut sumber']){!! $legend($sg, $k['ks_total']) !!}</div>
      @if(array_sum($k['ks_dana']) > 0)<p class="an-kosong" style="padding:8px 0 0">Pendanaan (Rp juta): @foreach($k['ks_dana'] as $lb => $v){{ $lb }} {{ number_format($v, 1, ',', '.') }}{{ $loop->last ? '' : ' · ' }}@endforeach</p>@endif
    @else{!! $kosongLkps('t4c1_kerjasama_pkm', '4.C.1 Kerjasama PkM') !!}@endif
  </section>
  <section class="an-card">
    <div class="an-ey">Tabel 4.C.2</div><h2>Diseminasi hasil PkM</h2>
    @if($k['ds_total'])
      <div class="am-mini"><div><b>{{ $k['ds_total'] }}</b><span>diseminasi</span></div></div>
      @include('analitik._batang', ['items' => array_map(fn ($lb, $v) => ['label' => $lb, 'v' => $v], array_keys($k['ds_level']), array_values($k['ds_level'])), 'color' => '#d97706', 'judul' => 'Diseminasi PkM menurut tingkat'])
    @else{!! $kosongLkps('t4c2_diseminasi_pkm', '4.C.2 Diseminasi Hasil PkM') !!}@endif
  </section>
  <section class="an-card">
    <div class="an-ey">Diseminasi dan HKI PkM</div><h2>Perkembangan per tahun</h2>
    @if($k['ds_total'] || $k['hki_total'])
      <div class="an-lg"><span><i style="background:#d97706"></i>Diseminasi<b>{{ $k['ds_total'] }}</b></span><span><i style="background:#7c3aed"></i>HKI PkM<b>{{ $k['hki_total'] }}</b></span></div>
      @include('analitik._kolom', ['cats' => $cTs, 'series' => [['name' => 'Diseminasi', 'color' => '#d97706', 'vals' => array_values($k['ds_ts'])], ['name' => 'HKI PkM', 'color' => '#7c3aed', 'vals' => array_values($k['hki_ts'])]], 'judul' => 'Diseminasi dan HKI PkM per tahun'])
    @else<p class="am-kosong">Belum ada data diseminasi atau HKI PkM. @auth<a href="{{ $lk('t4c3_hki_pkm') }}">Isi 4.C.3</a>@endauth</p>@endif
  </section>
</div>

{{-- ============ 5. AKUNTABILITAS ============ --}}
<header class="am-sec" id="akuntabilitas" style="--c:#e11d48"><h2><i></i>5. Akuntabilitas</h2><p>Dari Sistem Tata Kelola (5.1) dan Sarana Prasarana Pendidikan (5.2).</p></header>
<div class="an-g3">
  <section class="an-card">
    <div class="an-ey">Tabel 5.1</div><h2>Sistem tata kelola</h2>
    @if($u['tk_total'])
      @php $sg = $seg($u['tk_akses'], ['#e11d48', '#2563eb', '#94a3b8']); @endphp
      <div class="an-dw">@include('vk.donat', ['segs' => $sg, 'size' => 130, 'pusat' => (string) $u['tk_total'], 'sub' => 'SISTEM', 'label' => 'Sistem tata kelola menurut akses']){!! $legend($sg, $u['tk_total']) !!}</div>
      <ul class="am-list">@foreach($u['tk_daftar'] as $t)<li><b>{{ $t['jenis'] }}</b><span>{{ $t['sistem'] }}</span></li>@endforeach</ul>
    @else{!! $kosongLkps('t5_1_tata_kelola', '5.1 Sistem Tata Kelola') !!}@endif
  </section>
  <section class="an-card">
    <div class="an-ey">Tabel 5.2</div><h2>Sarana dan prasarana</h2>
    @if($u['sp_total'])
      <div class="am-mini"><div><b>{{ $u['sp_total'] }}</b><span>prasarana</span></div><div><b>{{ number_format($u['sp_daya'], 0, ',', '.') }}</b><span>daya tampung</span></div><div><b>{{ number_format($u['sp_luas'], 1, ',', '.') }}</b><span>m&sup2; luas ruang</span></div></div>
      @include('analitik._batang', ['items' => array_map(fn ($lb, $v) => ['label' => ['M' => 'Milik sendiri', 'W' => 'Sewa'][$lb] ?? $lb, 'v' => $v], array_keys($u['sp_milik']), array_values($u['sp_milik'])), 'color' => '#e11d48', 'judul' => 'Kepemilikan prasarana'])
    @else{!! $kosongLkps('t5_2_sarpras_pendidikan', '5.2 Sarana dan Prasarana Pendidikan') !!}@endif
  </section>
  <section class="an-card">
    <div class="an-ey">Tabel 5.2</div><h2>Status lisensi perangkat lunak</h2>
    @if($u['sp_total'])
      @php $sg = $seg(array_combine(array_map(fn ($x) => ['L' => 'Berlisensi', 'P' => 'Public domain', 'T' => 'Tidak berlisensi'][$x] ?? $x, array_keys($u['sp_lisensi'])), array_values($u['sp_lisensi'])), ['#059669', '#2563eb', '#ef4444', '#94a3b8']); @endphp
      <div class="an-dw">@include('vk.donat', ['segs' => $sg, 'size' => 130, 'pusat' => (string) array_sum($u['sp_lisensi']), 'sub' => 'ITEM', 'label' => 'Status lisensi']){!! $legend($sg, array_sum($u['sp_lisensi'])) !!}</div>
    @else<p class="am-kosong">Belum ada data sarana prasarana.</p>@endif
  </section>
</div>

<p class="text-muted small mt-3" style="max-width:80ch">Seluruh angka dihitung langsung dari data yang sudah diinput: Kriteria C1, Data Induk (Dokumen Standar Mutu), dan tabel LKPS. Halaman ini hanya membaca data, tidak mengubahnya.</p>
@endsection
EOFLIMA

tulis resources/views/analitik/galat.blade.php <<'EOFLIMA'
{{-- ANALITIK-LIMA-ASPEK : halaman cadangan berdiri sendiri (tanpa layout) bila Analitik gagal ditampilkan --}}
<!doctype html>
<html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Analitik tidak dapat ditampilkan</title>
<style>body{font:15px system-ui,sans-serif;margin:0;background:#f4f6fa;color:#1b2536}main{max-width:720px;margin:12vh auto;padding:0 20px}.k{background:#fff;border:1px solid #e4e8ef;border-radius:14px;padding:22px 24px}code{display:block;background:#f7f9fc;border:1px solid #e4e8ef;border-radius:8px;padding:10px 12px;margin-top:12px;font-size:13px;word-break:break-word}</style></head>
<body><main><div class="k"><h1 style="font-size:20px;margin:0 0 8px">Analitik tidak dapat ditampilkan</h1>
<p style="margin:0;color:#667085">Terjadi kesalahan saat menyusun halaman. Dashboard dan menu lain tetap dapat dipakai. Detail kesalahan sudah dicatat di <b>storage/logs/laravel.log</b>.</p>
@if(! empty($pesan))<code>{{ $pesan }}</code>@else<p style="margin:12px 0 0;color:#667085">Untuk melihat detailnya: masuk (login) lalu muat ulang halaman ini, atau buka baris <b>ERROR</b> terakhir di <b>storage/logs/laravel.log</b>.</p>@endif
<p style="margin:14px 0 0"><a href="{{ url('/') }}">Kembali ke Dashboard</a></p></div></main></body></html>
EOFLIMA

tulis resources/views/analitik/_gaya_lima.blade.php <<'EOFLIMA'
{{-- ANALITIK-LIMA-ASPEK --}}
<style>
.am-nav{display:grid;grid-template-columns:repeat(auto-fit,minmax(165px,1fr));gap:12px;margin-bottom:18px}
.am-tile{display:block;text-decoration:none;color:inherit;background:var(--card,#fff);border:1px solid var(--line,#e4e8ef);border-top:4px solid var(--c);border-radius:14px;padding:12px 14px;transition:box-shadow .15s,transform .15s}
.am-tile:hover{box-shadow:0 4px 14px rgba(16,24,40,.12);transform:translateY(-1px)}
.am-tile:focus-visible{outline:2px solid var(--c);outline-offset:2px}
.am-tile .an-big{font-size:28px;color:var(--c)}
.am-tile small{display:block;color:var(--muted,#667085);font-size:12px;margin-top:2px}
.am-sec{margin:26px 0 8px;scroll-margin-top:12px}
.am-sec h2{font-size:20px;font-weight:700;letter-spacing:-.01em;margin:0;display:flex;align-items:center;gap:10px}
.am-sec h2 i{display:inline-block;width:6px;height:22px;border-radius:3px;background:var(--c)}
.am-sec p{margin:4px 0 0;font-size:13px;color:var(--muted,#667085)}
.am-batang,.am-kolom{display:block;width:100%;height:auto}
.am-kosong{padding:18px 4px;color:var(--muted,#667085);font-size:13.5px}
.am-kosong a{font-weight:600}
.am-mini{display:flex;gap:18px;flex-wrap:wrap;margin:2px 0 10px}
.am-mini div b{display:block;font-size:22px;line-height:1.15}
.am-mini div span{font-size:12px;color:var(--muted,#667085)}
.am-list{margin:6px 0 0;padding:0;list-style:none;font-size:13px}
.am-list li{display:flex;justify-content:space-between;gap:10px;padding:6px 0;border-top:1px solid var(--line,#e4e8ef)}
.am-list li:first-child{border-top:0}
.am-list span{color:var(--muted,#667085)}
</style>
EOFLIMA

tulis resources/views/analitik/_batang.blade.php <<'EOFLIMA'
{{-- ANALITIK-LIMA-ASPEK; Batang mendatar SVG. $items: [['label'=>, 'v'=>], ...]  $color  $des (desimal)  $satuan --}}
@php
    $color = $color ?? '#2563eb'; $des = $des ?? 0; $satuan = $satuan ?? ''; $judul = $judul ?? 'Diagram batang';
    $n = count($items); $W = 360; $lw = 128; $vw = 62; $rh = 30; $H = max(1, $n) * $rh + 4;
    $mx = max(1, ...array_map(fn ($i) => (float) $i['v'], $items ?: [['v' => 1]]));
    $aw = $W - $lw - $vw; $f1 = fn ($x) => number_format($x, 1, '.', '');
@endphp
<svg class="am-batang" viewBox="0 0 {{ $W }} {{ $H }}" role="img" aria-label="{{ $judul }}"><title>{{ $judul }}</title>
@foreach($items as $i => $it)@php $y = $i * $rh + 2; $w = $it['v'] > 0 ? max(3, $aw * $it['v'] / $mx) : 0; $lb = mb_strlen($it["label"]) > 19 ? mb_substr($it["label"], 0, 18) . '…' : $it['label']; @endphp
<text x="0" y="{{ $y + 17 }}" font-size="12.5" fill="var(--text)">{{ $lb }}<title>{{ $it['label'] }}</title></text>
<rect x="{{ $lw }}" y="{{ $y + 5 }}" width="{{ $aw }}" height="16" rx="4" fill="var(--line)" opacity=".55"/>
@if($w > 0)<rect x="{{ $lw }}" y="{{ $y + 5 }}" width="{{ $f1($w) }}" height="16" rx="4" fill="{{ $it['color'] ?? $color }}"><title>{{ $it['label'] }}: {{ number_format($it['v'], $des, ',', '.') }} {{ $satuan }}</title></rect>@endif
<text x="{{ $W }}" y="{{ $y + 17 }}" text-anchor="end" font-size="13" font-weight="700" fill="var(--text)">{{ number_format($it['v'], $des, ',', '.') }}{{ $satuan ? ' ' . $satuan : '' }}</text>
@endforeach
</svg>
EOFLIMA

tulis resources/views/analitik/_kolom.blade.php <<'EOFLIMA'
{{-- ANALITIK-LIMA-ASPEK; Kolom berkelompok SVG. $cats: ['TS-2','TS-1','TS']  $series: [['name'=>,'color'=>,'vals'=>[...]]]  $des --}}
@php
    $judul = $judul ?? 'Diagram kolom'; $des = $des ?? 0;
    $W = 360; $H = 210; $L = 36; $B = 28; $T = 16; $R = 8; $pw = $W - $L - $R; $ph = $H - $T - $B; $nc = count($cats); $ns = max(1, count($series));
    $f1 = fn ($x) => number_format($x, 1, '.', '');
    $mx0 = max(1, ...array_merge([1], ...array_map(fn ($s) => $s['vals'], $series ?: [['vals' => [1]]])));
    $st = 1; foreach ([1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000] as $c) { $st = $c; if ($mx0 / $c <= 5) { break; } }
    $mx = (int) ceil($mx0 / $st) * $st; $nk = (int) ($mx / $st);
    $gw = $pw / max(1, $nc); $bw = min(30, $gw * 0.78 / $ns);
@endphp
<svg class="am-kolom" viewBox="0 0 {{ $W }} {{ $H }}" role="img" aria-label="{{ $judul }}"><title>{{ $judul }}</title>
@for($k = 0; $k <= $nk; $k++)@php $v = $k * $st; $y = $T + $ph - $ph * $v / $mx; @endphp
<line x1="{{ $L }}" x2="{{ $W - $R }}" y1="{{ $f1($y) }}" y2="{{ $f1($y) }}" stroke="var(--line)" stroke-width="1"/><text x="{{ $L - 6 }}" y="{{ $f1($y + 4) }}" text-anchor="end" font-size="11" fill="var(--muted)">{{ number_format($v, 0, ',', '.') }}</text>
@endfor
@foreach($cats as $i => $c)@php $cx = $L + $gw * ($i + .5); $x0 = $cx - $bw * $ns / 2; @endphp
@foreach($series as $j => $s)@php $v = $s['vals'][$i] ?? 0; $h = $ph * $v / $mx; @endphp
@if($v > 0)<rect x="{{ $f1($x0 + $j * $bw + 1) }}" y="{{ $f1($T + $ph - $h) }}" width="{{ $f1(max(2, $bw - 2)) }}" height="{{ $f1($h) }}" rx="3" fill="{{ $s['color'] }}"><title>{{ $s['name'] }}, {{ $c }}: {{ number_format($v, $des, ',', '.') }}</title></rect>@endif
@endforeach
<text x="{{ $f1($cx) }}" y="{{ $H - 8 }}" text-anchor="middle" font-size="12" fill="var(--muted)">{{ $c }}</text>
@endforeach
</svg>
EOFLIMA

echo "[2/3] Memeriksa sintaks PHP..."
for f in app/Support/AnalitikLima.php app/Http/Controllers/AnalitikController.php; do
  if ! php -l "$f" >/dev/null; then
    echo "GAGAL: sintaks salah di $f. Memulihkan dari cadangan..."
    [ -f "$f.bak15" ] && cp "$f.bak15" "$f"
    exit 1
  fi
done
echo "  OK"
echo "[3/3] Membersihkan cache..."
php artisan view:clear >/dev/null 2>&1 || true
php artisan optimize:clear >/dev/null 2>&1 || true
echo
echo "Selesai. Buka menu Analitik (/analitik): lima aspek dengan diagram."
echo "Data dihitung langsung dari Kriteria C1 (kode kriteria 'C1' atau nama memuat 'Budaya Mutu'),"
echo "Dokumen Standar Mutu, dan tabel LKPS. Mengembalikan tampilan lama: salin *.bak15 ke nama aslinya."
