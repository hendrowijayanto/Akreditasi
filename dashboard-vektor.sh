#!/usr/bin/env bash
# =====================================================================
# DASHBOARD GRAFIK VEKTOR (SVG) - tampilan lebih profesional dan elegan
# Sistem Informasi Akreditasi Program Studi Teknologi Informasi
# Sekolah Vokasi Universitas Tiga Serangkai
#
# Mengganti tampilan Dashboard dengan grafik vektor (SVG) tanpa pustaka JavaScript:
#   - gauge besar "Kesiapan Akreditasi" + 4 cincin KPI (isian, narasi, dokumen, LKPS)
#   - diagram radar profil capaian semua kriteria
#   - batang capaian per kriteria (isian / narasi / dokumen)
#   - cincin dan segmen kelengkapan LKPS (otomatis tampil bila LKPS terpasang)
#   - tabel rincian per kriteria tetap ada (angka persis, ramah pembaca layar)
#
# Aman: hanya mengubah tampilan (Blade). Tidak menyentuh controller, route, database,
# maupun data. dashboard.blade.php lama dicadangkan sebagai dashboard.blade.php.bak9.
# Aman diulang. Membutuhkan tema sidebar (partial 'bar' dan layout 'layout').
#
# Pemakaian (di root proyek):  bash dashboard-vektor.sh [--timpa]
#   --timpa   timpa juga partial grafik yang sudah ada (vk/*.blade.php)
# Kembali ke tampilan lama: salin dashboard.blade.php.bak9 ke dashboard.blade.php
# =====================================================================
set -e
if [ ! -f artisan ]; then echo "Error: jalankan di root proyek Laravel."; exit 1; fi
TIMPA=0
for a in "$@"; do
  case "$a" in --timpa) TIMPA=1;; -h|--help) sed -n '2,23p' "$0"; exit 0;; *) echo "Opsi tidak dikenal: $a"; exit 1;; esac
done
DBV=resources/views/dashboard.blade.php
L=resources/views/layout.blade.php

echo "[1/3] Pemeriksaan..."
if [ ! -f "$L" ] || ! grep -q "yield('content')" "$L"; then echo "Error: layout aplikasi tidak ditemukan atau tidak memakai @yield('content')."; exit 1; fi
if [ ! -f resources/views/bar.blade.php ]; then echo "PERINGATAN: partial 'bar' tidak ada (tema sidebar belum terpasang); tabel rincian mungkin tidak tampil benar."; fi
if [ -f app/Http/Controllers/DashboardController.php ] && ! grep -q "'narasi'" app/Http/Controllers/DashboardController.php; then
  echo "PERINGATAN: DashboardController tidak menyediakan data 'narasi'/'dokumen' seperti yang diharapkan."
fi
echo "  OK"

tulis() {   # tulis <path> (isi dari stdin). Berkas yang sudah ada tidak ditimpa kecuali --timpa
  local f="$1"
  if [ -f "$f" ] && [ "$TIMPA" != 1 ]; then cat >/dev/null; echo "  (sudah ada, dilewati) $f"; return 0; fi
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] && cp "$f" "$f.bak9"
  cat > "$f"
  echo "  OK  $f"
}

echo "[2/3] Menulis partial grafik vektor..."
tulis resources/views/vk/_gaya.blade.php <<'EOF'
<style>
.vk-hero{position:relative;overflow:hidden;display:flex;gap:30px;align-items:center;flex-wrap:wrap;padding:26px 30px;border-radius:20px;color:#fff;margin-bottom:18px;background:linear-gradient(135deg,#0b1f3a 0%,#123a73 55%,#1d4ed8 100%);box-shadow:0 10px 30px -12px rgba(18,58,115,.55)}
.vk-deko{position:absolute;right:-40px;top:-60px;width:360px;height:360px;pointer-events:none}
.vk-gw{position:relative;width:220px;flex:none}
.vk-gauge{display:block;width:100%;height:auto}
.vk-ht{position:relative;flex:1;min-width:280px}
.vk-eyebrow{font-size:11.5px;letter-spacing:.14em;text-transform:uppercase;color:#9db6dd;font-weight:600}
.vk-ht h1{font-size:28px;font-weight:700;letter-spacing:-.02em;margin:4px 0 4px;color:#fff}
.vk-ht p{margin:0;color:#cfe0ff;font-size:14px}
.vk-kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:12px;margin-top:20px}
.vk-kpi{display:flex;align-items:center;gap:12px;padding:12px 14px;border-radius:14px;background:rgba(255,255,255,.09);border:1px solid rgba(255,255,255,.15);backdrop-filter:blur(2px)}
.vk-kpi span{display:block;font-size:12.5px;color:#cfe0ff;line-height:1.25}
.vk-kpi b{display:block;font-size:14px;font-weight:600;color:#fff;margin-top:2px}
.vk-g2{display:grid;grid-template-columns:minmax(0,5fr) minmax(0,6fr);gap:16px;margin:0 0 16px}
@media(max-width:980px){.vk-g2{grid-template-columns:minmax(0,1fr)}.vk-gw{margin:0 auto}}
.vk-card{background:var(--card,#fff);border:1px solid var(--line,#e4e8ef);border-radius:16px;padding:18px 20px;box-shadow:0 1px 2px rgba(16,24,40,.04)}
.vk-ey{font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:var(--muted,#667085);font-weight:600}
.vk-card h2{font-size:17px;font-weight:700;margin:2px 0 10px;letter-spacing:-.01em}
.vk-leg{display:flex;gap:16px;flex-wrap:wrap;font-size:12.5px;color:var(--muted,#667085);margin-bottom:8px}
.vk-leg i{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:6px;vertical-align:-1px}
.vk-radar,.vk-bars{display:block;width:100%;height:auto;max-height:360px}
.vk-lk{display:flex;gap:26px;align-items:center;flex-wrap:wrap}
.vk-lkr{display:flex;align-items:center;gap:16px}
.vk-lkr strong{display:block;font-size:16px}
.vk-lkr small{color:var(--muted,#667085)}
.vk-lkg{flex:1;min-width:300px;display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px 26px}
.vk-lkg a{display:flex;justify-content:space-between;gap:10px;font-size:12.5px;color:var(--text,#1b2536);text-decoration:none;margin-bottom:5px}
.vk-lkg a:hover{color:var(--pri,#1d4ed8)}
.vk-lkg a span{color:var(--muted,#667085);white-space:nowrap}
.vk-ring text,.vk-radar text,.vk-bars text{font-family:inherit}
@keyframes vkd{from{stroke-dasharray:0 600}}
@keyframes vkb{from{transform:scaleX(0)}}
.vk-fg{animation:vkd 1s ease-out both}
.vk-bar{transform-box:fill-box;transform-origin:left center;animation:vkb .9s ease-out both}
@media(prefers-reduced-motion:reduce){.vk-fg,.vk-bar{animation:none}}
</style>
EOF

tulis resources/views/vk/ring.blade.php <<'EOF'
@php
    $v = max(0, min(100, (int) round($v)));
    $size = $size ?? 64; $c1 = $c1 ?? '#2563eb'; $c2 = $c2 ?? '#60a5fa';
    $track = $track ?? 'var(--line)'; $txt = $txt ?? 'currentColor'; $fs = $fs ?? 24; $sw = $sw ?? 9;
    $id = 'vr' . bin2hex(random_bytes(3));
@endphp
<svg class="vk-ring" viewBox="0 0 100 100" width="{{ $size }}" height="{{ $size }}" role="img" aria-label="{{ $label }}: {{ $v }}%"><title>{{ $label }}: {{ $v }}%</title><defs><linearGradient id="{{ $id }}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{{ $c1 }}"/><stop offset="1" stop-color="{{ $c2 }}"/></linearGradient></defs><circle cx="50" cy="50" r="42" fill="none" stroke="{{ $track }}" stroke-width="{{ $sw }}"/>@if($v > 0)<circle class="vk-fg" cx="50" cy="50" r="42" fill="none" stroke="url(#{{ $id }})" stroke-width="{{ $sw }}" stroke-linecap="round" stroke-dasharray="{{ number_format($v / 100 * 263.89, 2, '.', '') }} 263.89" transform="rotate(-90 50 50)"/>@endif<text x="50" y="{{ number_format(50 + $fs * 0.36, 1, '.', '') }}" text-anchor="middle" font-size="{{ $fs }}" font-weight="700" fill="{{ $txt }}">{{ $v }}<tspan font-size="{{ number_format($fs * 0.55, 1, '.', '') }}" font-weight="600">%</tspan></text></svg>
EOF

tulis resources/views/vk/gauge.blade.php <<'EOF'
@php
    $v = max(0, min(100, (int) round($v)));
    $id = 'vg' . bin2hex(random_bytes(3));
    $arc = number_format($v / 100 * 386.42, 2, '.', '');
@endphp
<svg class="vk-gauge" viewBox="0 0 220 220" role="img" aria-label="{{ $label }}: {{ $v }}%"><title>{{ $label }}: {{ $v }}%</title><defs><linearGradient id="{{ $id }}" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="#5eead4"/><stop offset="1" stop-color="#93c5fd"/></linearGradient><filter id="{{ $id }}b" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="5"/></filter></defs>@for($i = 0; $i <= 10; $i++)@php $a = deg2rad(135 + $i * 27); $besar = $i % 5 == 0; @endphp<line x1="{{ number_format(110 + 95 * cos($a), 1, '.', '') }}" y1="{{ number_format(110 + 95 * sin($a), 1, '.', '') }}" x2="{{ number_format(110 + ($besar ? 105 : 101) * cos($a), 1, '.', '') }}" y2="{{ number_format(110 + ($besar ? 105 : 101) * sin($a), 1, '.', '') }}" stroke="rgba(255,255,255,{{ $besar ? '.55' : '.28' }})" stroke-width="{{ $besar ? 2 : 1.4 }}" stroke-linecap="round"/>@endfor<circle cx="110" cy="110" r="82" fill="none" stroke="rgba(255,255,255,.13)" stroke-width="14" stroke-linecap="round" stroke-dasharray="386.42 515.22" transform="rotate(135 110 110)"/>@if($v > 0)<circle cx="110" cy="110" r="82" fill="none" stroke="#5eead4" stroke-opacity=".5" stroke-width="14" stroke-linecap="round" stroke-dasharray="{{ $arc }} 515.22" transform="rotate(135 110 110)" filter="url(#{{ $id }}b)"/><circle class="vk-fg" cx="110" cy="110" r="82" fill="none" stroke="url(#{{ $id }})" stroke-width="14" stroke-linecap="round" stroke-dasharray="{{ $arc }} 515.22" transform="rotate(135 110 110)"/>@endif<text x="110" y="{{ $v >= 100 ? 120 : 122 }}" text-anchor="middle" font-size="{{ $v >= 100 ? 50 : 58 }}" font-weight="700" fill="#fff" letter-spacing="-1">{{ $v }}<tspan font-size="24" font-weight="600" dx="2">%</tspan></text><text x="110" y="146" text-anchor="middle" font-size="12.5" fill="#cfe0ff" letter-spacing=".08em">KESIAPAN</text><text x="48" y="188" text-anchor="middle" font-size="10.5" fill="#9db6dd">0</text><text x="172" y="188" text-anchor="middle" font-size="10.5" fill="#9db6dd">100</text></svg>
EOF

tulis resources/views/vk/radar.blade.php <<'EOF'
@php
    // $labels: ['K1', ...]; $series: [['color' => '#2563eb', 'vals' => [..]], ...]
    $n = count($labels); $cx = 180; $cy = 158; $R = 100;
    $pt = function ($i, $r) use ($n, $cx, $cy) { $a = deg2rad(-90 + $i * 360 / $n); return [$cx + $r * cos($a), $cy + $r * sin($a)]; };
    $f = fn ($p) => number_format($p[0], 1, '.', '') . ',' . number_format($p[1], 1, '.', '');
    $k = fn ($v) => max(0, min(100, (int) round($v)));
@endphp
<svg class="vk-radar" viewBox="0 0 360 316" role="img" aria-label="Profil capaian per kriteria"><title>Profil capaian per kriteria</title>@foreach([25, 50, 75, 100] as $l)<polygon points="{{ implode(' ', array_map(fn ($i) => $f($pt($i, $R * $l / 100)), array_keys($labels))) }}" fill="{{ $l == 100 ? 'var(--head)' : 'none' }}" stroke="var(--line)" stroke-width="1"/><text x="{{ $cx + 3 }}" y="{{ number_format($cy - $R * $l / 100 + 10, 1, '.', '') }}" font-size="8.5" fill="var(--muted)">{{ $l }}</text>@endforeach
@foreach($labels as $i => $t)@php [$x, $y] = $pt($i, $R); [$lx, $ly] = $pt($i, $R + 17); @endphp<line x1="{{ $cx }}" y1="{{ $cy }}" x2="{{ number_format($x, 1, '.', '') }}" y2="{{ number_format($y, 1, '.', '') }}" stroke="var(--line)"/>@endforeach
@foreach($series as $s)@php $pts = array_map(fn ($v, $i) => $pt($i, $R * $k($v) / 100), $s['vals'], array_keys($s['vals'])); @endphp<polygon points="{{ implode(' ', array_map($f, $pts)) }}" fill="{{ $s['color'] }}" fill-opacity=".14" stroke="{{ $s['color'] }}" stroke-width="2" stroke-linejoin="round"/>@foreach($pts as $p)<circle cx="{{ number_format($p[0], 1, '.', '') }}" cy="{{ number_format($p[1], 1, '.', '') }}" r="3.2" fill="#fff" stroke="{{ $s['color'] }}" stroke-width="2"/>@endforeach @endforeach
@foreach($labels as $i => $t)@php [$lx, $ly] = $pt($i, $R + 17); @endphp<text x="{{ number_format($lx, 1, '.', '') }}" y="{{ number_format($ly + 4, 1, '.', '') }}" text-anchor="{{ $lx < $cx - 8 ? 'end' : ($lx > $cx + 8 ? 'start' : 'middle') }}" font-size="12" font-weight="600" fill="var(--text)">{{ $t }}</text>@endforeach</svg>
EOF

tulis resources/views/vk/batang.blade.php <<'EOF'
@php
    // $rows: [['k' => 'K1', 't' => 'K1 - Visi', 'v' => [isian, narasi, dokumen]], ...]; $warna: ['#2563eb', ...]
    $H = count($rows) * 50 + 8;
    $k = fn ($v) => max(0, min(100, (int) round($v)));
@endphp
<svg class="vk-bars" viewBox="0 0 520 {{ $H }}" role="img" aria-label="Capaian per kriteria"><title>Capaian per kriteria</title>@foreach($rows as $i => $r)@php $y = 8 + $i * 50; @endphp<text x="0" y="{{ $y + 19 }}" font-size="12.5" font-weight="700" fill="var(--text)">{{ $r['k'] }}<title>{{ $r['t'] ?? $r['k'] }}</title></text>@foreach($warna as $j => $c)@php $by = $y + $j * 12; $w = $k($r['v'][$j]) * 4.2; @endphp<rect x="46" y="{{ $by }}" width="420" height="8" rx="4" fill="var(--line)" opacity=".7"/>@if($w > 0)<rect class="vk-bar" x="46" y="{{ $by }}" width="{{ number_format($w, 1, '.', '') }}" height="8" rx="4" fill="{{ $c }}"/>@endif<text x="474" y="{{ $by + 7.5 }}" font-size="10.5" font-weight="600" fill="var(--muted)">{{ $k($r['v'][$j]) }}%</text>@endforeach @endforeach</svg>
EOF

tulis resources/views/vk/segmen.blade.php <<'EOF'
@php $w = 14; $g = 3; $W = max(1, count($items) * ($w + $g) - $g); @endphp
<svg class="vk-seg" viewBox="0 0 {{ $W }} 10" preserveAspectRatio="none" width="100%" height="10" aria-hidden="true">@foreach($items as $i => $t)<rect x="{{ $i * ($w + $g) }}" y="0" width="{{ $w }}" height="10" rx="3" fill="{{ $t['n'] > 0 ? '#10b981' : '#fbd9a5' }}"><title>{{ $t['judul'] }}</title></rect>@endforeach</svg>
EOF

echo "[3/3] Memasang dashboard baru..."
if [ -f "$DBV" ] && grep -q "vk._gaya" "$DBV"; then
  echo "  (dashboard sudah memakai grafik vektor, dilewati)"
else
  [ -f "$DBV" ] && cp "$DBV" "$DBV.bak9" && echo "  OK  cadangan -> $DBV.bak9"
  cat > "$DBV" <<'EOF'
@extends('layout')
@section('title', 'Dashboard')
@section('content')
@includeIf('dash._pilih', ['aktif' => 'ringkas'])
@include('vk._gaya')
@php
    $overall = (int) round(($total['isian'] + $total['narasi'] + $total['dokumen']) / 3);
    $lk = class_exists(\App\Support\LkpsRingkasan::class) ? \App\Support\LkpsRingkasan::data() : null;
    $lk = ($lk && $lk['tersedia'] && Route::has('lkps.daftar')) ? $lk : null;   // LKPS tampil hanya bila sudah terpasang
    $nKriteria = count($rows);
    $kpi = [
        ['Isian kriteria',       $total['isian'],   ['#2563eb', '#60a5fa'], 'rata-rata ' . $nKriteria . ' kriteria'],
        ['Isian narasi',         $total['narasi'],  ['#7c3aed', '#a78bfa'], 'rata-rata ' . $nKriteria . ' kriteria'],
        ['Kelengkapan dokumen',  $total['dokumen'], ['#059669', '#34d399'], 'rata-rata ' . $nKriteria . ' kriteria'],
    ];
    if ($lk) { $kpi[] = ['Kelengkapan LKPS', $lk['persen'], ['#d97706', '#fbbf24'], $lk['terisi'] . ' dari ' . $lk['total'] . ' tabel']; }
    $seri = [['Isian', '#2563eb'], ['Narasi', '#7c3aed'], ['Dokumen', '#059669']];
    $kode = $rows->pluck('kriteria.kode')->all();
@endphp

<section class="vk-hero">
  <svg class="vk-deko" viewBox="0 0 360 360" aria-hidden="true"><g fill="none" stroke="#fff" stroke-opacity=".08"><circle cx="230" cy="130" r="90"/><circle cx="230" cy="130" r="140"/><circle cx="230" cy="130" r="190"/></g></svg>
  <div class="vk-gw">@include('vk.gauge', ['v' => $overall, 'label' => 'Kesiapan akreditasi'])</div>
  <div class="vk-ht">
    <div class="vk-eyebrow">Program Studi Teknologi Informasi</div>
    <h1>Kesiapan Akreditasi</h1>
    <p>Rata-rata isian kriteria, isian narasi, dan kelengkapan dokumen{{ $lk ? '; LKPS ditampilkan terpisah' : '' }}</p>
    <div class="vk-kpis">
      @foreach($kpi as [$label, $nilai, $w, $cap])
        <div class="vk-kpi">
          @include('vk.ring', ['v' => $nilai, 'label' => $label, 'size' => 56, 'c1' => $w[0], 'c2' => $w[1], 'track' => 'rgba(255,255,255,.18)', 'txt' => '#fff', 'fs' => 25])
          <div><span>{{ $label }}</span><b>{{ $cap }}</b></div>
        </div>
      @endforeach
    </div>
  </div>
</section>

<div class="vk-g2">
  <section class="vk-card">
    <div class="vk-ey">Profil capaian</div>
    <h2>Seluruh kriteria sekilas</h2>
    @if($nKriteria >= 3)
      <div class="vk-leg">@foreach($seri as [$nm, $c])<span><i style="background:{{ $c }}"></i>{{ $nm }}</span>@endforeach</div>
      @include('vk.radar', ['labels' => $kode, 'series' => array_map(fn ($s, $j) => ['color' => $s[1], 'vals' => $rows->map(fn ($r) => [$r['isian'], $r['narasi'], $r['dokumen']][$j])->all()], $seri, array_keys($seri))])
    @else
      <p class="text-muted small mb-0">Diagram radar tampil bila ada minimal 3 kriteria.</p>
    @endif
  </section>
  <section class="vk-card">
    <div class="vk-ey">Capaian per kriteria</div>
    <h2>Isian, narasi, dan dokumen</h2>
    <div class="vk-leg">@foreach($seri as [$nm, $c])<span><i style="background:{{ $c }}"></i>{{ $nm }}</span>@endforeach</div>
    @if($nKriteria)
      @include('vk.batang', ['rows' => $rows->map(fn ($r) => ['k' => $r['kriteria']->kode, 't' => $r['kriteria']->kode . ' - ' . $r['kriteria']->nama, 'v' => [$r['isian'], $r['narasi'], $r['dokumen']]])->all(), 'warna' => array_column($seri, 1)])
    @else
      <p class="text-muted small mb-0">Belum ada kriteria. @auth<a href="{{ route('kriteria.create') }}">Tambah kriteria</a>@endauth</p>
    @endif
  </section>
</div>

@if($lk)
<section class="vk-card vk-lk mb-3">
  <div class="vk-lkr">
    @include('vk.ring', ['v' => $lk['persen'], 'label' => 'Kelengkapan LKPS', 'size' => 96, 'c1' => '#d97706', 'c2' => '#fbbf24', 'fs' => 26])
    <div><div class="vk-ey">Kelengkapan LKPS</div><strong>{{ $lk['terisi'] }} dari {{ $lk['total'] }} tabel</strong><small>sudah berisi data &middot; <a href="{{ route('lkps.daftar') }}">Buka LKPS</a></small></div>
  </div>
  <div class="vk-lkg">
    @foreach($lk['kelompok'] as $g)
      <div>
        <a href="{{ route('lkps.daftar') }}"><b>{{ \Illuminate\Support\Str::before($g['nama'], ':') }}</b><span>{{ $g['terisi'] }}/{{ count($g['items']) }} terisi</span></a>
        @include('vk.segmen', ['items' => $g['items']])
      </div>
    @endforeach
  </div>
</section>
@endif

<div class="vk-ey mb-2" style="margin-top:6px">Rincian per kriteria</div>
<div class="card"><div class="table-responsive">
<table class="table align-middle mb-0">
  <thead><tr><th>Kriteria</th><th class="text-center">Butir</th><th style="width:20%">Isian</th><th style="width:20%">Narasi</th><th style="width:20%">Dokumen</th></tr></thead>
  <tbody>
  @forelse($rows as $r)
    <tr>
      <td><a href="{{ route('kriteria.show', $r['kriteria']) }}" class="text-decoration-none fw-medium">{{ $r['kriteria']->kode }} - {{ $r['kriteria']->nama }}</a></td>
      <td class="text-center">{{ $r['jumlah'] }}</td>
      <td>@include('bar', ['v' => $r['isian']])</td>
      <td>@include('bar', ['v' => $r['narasi']])</td>
      <td>@include('bar', ['v' => $r['dokumen']])</td>
    </tr>
  @empty
    <tr><td colspan="5" class="text-center text-muted py-4">Belum ada kriteria. @auth<a href="{{ route('kriteria.create') }}">Tambah kriteria</a>@endauth</td></tr>
  @endforelse
  </tbody>
</table></div></div>
<p class="text-muted small mt-2">Narasi = butir yang narasinya sudah terisi. Dokumen = butir yang memiliki minimal satu dokumen/link.</p>
@endsection
EOF
  echo "  OK  $DBV"
fi

php artisan view:clear >/dev/null 2>&1 || true
echo ""
echo "Selesai. Muat ulang halaman Dashboard (Ctrl+F5)."
echo "LKPS tampil otomatis bila fasilitas LKPS terpasang (tambah-lkps.sh); tanpa itu, dashboard hanya menampilkan data akreditasi."
echo "Kembali ke tampilan lama: cp $DBV.bak9 $DBV && php artisan view:clear"
echo "Jika memakai cache produksi: php artisan view:cache"
