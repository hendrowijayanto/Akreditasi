#!/usr/bin/env bash
# =====================================================================
# PEMILIH TAMPILAN DASHBOARD (ganti-ganti dashboard)
# Sistem Informasi Akreditasi Program Studi Teknologi Informasi
# Sekolah Vokasi Universitas Tiga Serangkai
#
# Memungkinkan pengguna mengganti model Dashboard kapan saja:
#   Ringkas (Dashboard bawaan) | Analitik | Panel Admin
#  - Pemilih (pilihan segmen) tampil di atas ketiga halaman.
#  - Pilihan diingat per browser (cookie 1 tahun); halaman Dashboard utama ("/")
#    langsung menampilkan model yang dipilih, tanpa pindah alamat.
#  - Admin dapat menetapkan model bawaan untuk pengunjung baru lewat
#    DASHBOARD_DEFAULT di .env (ringkas | analitik | panel).
#  - Model yang belum terpasang otomatis tidak muncul; bila hanya satu model
#    yang terpasang, pemilih disembunyikan.
#
# AMAN: hanya tampilan dan pengalihan. Tidak ada tabel, migration, atau perubahan data.
# routes/web.php dan view hanya disisipi baris kecil (cadangan *.bak12). Aman diulang.
#
# Pemakaian (di root proyek):  bash tambah-tampilan.sh [--timpa]
#   --timpa   timpa berkas pemilih yang sudah ada (yang lama dicadangkan *.bak12)
# =====================================================================
set -e
if [ ! -f artisan ]; then echo "Error: jalankan di root proyek Laravel."; exit 1; fi
TIMPA=0
for a in "$@"; do
  case "$a" in --timpa) TIMPA=1;; -h|--help) sed -n '2,24p' "$0"; exit 0;; *) echo "Opsi tidak dikenal: $a"; exit 1;; esac
done
R=routes/web.php

echo "[1/4] Pemeriksaan..."
[ -f "$R" ] || { echo "Error: $R tidak ditemukan."; exit 1; }
command -v perl >/dev/null 2>&1 || { echo "Error: perl dibutuhkan."; exit 1; }
if ! grep -q "name('dashboard')" "$R"; then echo "PERINGATAN: route bernama 'dashboard' tidak ditemukan di $R; pengalihan halaman utama harus dipasang manual."; fi
MODEL=1
[ -f app/Http/Controllers/AnalitikController.php ] && MODEL=$((MODEL+1))
[ -f app/Http/Controllers/PanelController.php ] && MODEL=$((MODEL+1))
echo "  OK  model dashboard terpasang: $MODEL (ringkas${MODEL:+, }$( [ -f app/Http/Controllers/AnalitikController.php ] && echo -n 'analitik ' )$( [ -f app/Http/Controllers/PanelController.php ] && echo -n 'panel' ))"
if [ "$MODEL" -lt 2 ]; then echo "  CATATAN: baru satu model terpasang; pemilih baru tampil setelah tambah-analitik.sh atau tambah-panel.sh dipasang."; fi

tulis() {   # tulis <path> (isi dari stdin). Berkas yang sudah ada tidak ditimpa kecuali --timpa
  local f="$1"
  if [ -f "$f" ] && [ "$TIMPA" != 1 ]; then cat >/dev/null; echo "  (sudah ada, dilewati) $f"; return 0; fi
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] && cp "$f" "$f.bak12"
  cat > "$f"
  echo "  OK  $f"
}

echo "[2/4] Menulis berkas pemilih..."
tulis app/Http/Middleware/PilihDashboard.php <<'EOF'
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

/**
 * Memilih model Dashboard yang tampil di halaman utama ("/"):
 *   ringkas  = Dashboard bawaan (kartu kesiapan)
 *   analitik = halaman Analitik
 *   panel    = Panel Admin
 * Urutan penentu: pilihan pengguna (cookie "dash") > DASHBOARD_DEFAULT di .env > ringkas.
 * Model yang belum terpasang otomatis diabaikan.
 */
class PilihDashboard
{
    public const COOKIE = 'dash';

    /** Model yang benar-benar terpasang di aplikasi ini. */
    public static function tersedia(): array
    {
        $o = ['ringkas'];
        if (class_exists(\App\Http\Controllers\AnalitikController::class) && Route::has('analitik')) {
            $o[] = 'analitik';
        }
        if (class_exists(\App\Http\Controllers\PanelController::class) && Route::has('panel')) {
            $o[] = 'panel';
        }

        return $o;
    }

    public static function pilihan(?string $cookie): string
    {
        $tersedia = self::tersedia();
        foreach ([$cookie, (string) config('tampilan.default', 'ringkas')] as $m) {
            if ($m && in_array($m, $tersedia, true)) {
                return $m;
            }
        }

        return 'ringkas';
    }

    public function handle(Request $request, Closure $next)
    {
        $m = self::pilihan($request->cookie(self::COOKIE));
        $controller = match ($m) {
            'analitik' => \App\Http\Controllers\AnalitikController::class,
            'panel'    => \App\Http\Controllers\PanelController::class,
            default    => null,
        };
        if ($controller === null) {
            return $next($request);
        }
        $hasil = app()->call([app($controller), 'index']);

        return $hasil instanceof \Symfony\Component\HttpFoundation\Response ? $hasil : response($hasil);
    }
}
EOF

tulis app/Http/Controllers/TampilanController.php <<'EOF'
<?php

namespace App\Http\Controllers;

use App\Http\Middleware\PilihDashboard;

class TampilanController extends Controller
{
    /** Simpan pilihan model dashboard pengguna (cookie 1 tahun), lalu buka Dashboard. */
    public function pilih(string $model)
    {
        abort_unless(in_array($model, PilihDashboard::tersedia(), true), 404);

        return redirect()->route('dashboard')->withCookie(cookie(PilihDashboard::COOKIE, $model, 60 * 24 * 365));
    }
}
EOF

tulis config/tampilan.php <<'EOF'
<?php

return [
    // Model Dashboard bawaan untuk pengunjung yang belum memilih: ringkas | analitik | panel
    // (atur lewat DASHBOARD_DEFAULT di .env; pilihan pengguna di browsernya tetap diutamakan)
    'default' => env('DASHBOARD_DEFAULT', 'ringkas'),
];
EOF

tulis resources/views/dash/_pilih.blade.php <<'EOF'
@php
    $aktif = $aktif ?? 'ringkas';
    $labelDash = ['ringkas' => 'Ringkas', 'analitik' => 'Analitik', 'panel' => 'Panel'];
    $modelDash = \App\Http\Middleware\PilihDashboard::tersedia();
@endphp
@if(count($modelDash) > 1 && Route::has('dashboard.tampilan'))
<style>
.dh-sw{display:flex;justify-content:flex-end;align-items:center;gap:10px;margin:0 0 12px;font-size:12.5px;color:var(--muted,#667085)}
.dh-seg{display:inline-flex;background:var(--head,#f7f9fc);border:1px solid var(--line,#e4e8ef);border-radius:999px;padding:3px}
.dh-seg a{padding:5px 14px;border-radius:999px;font-size:12.5px;font-weight:600;color:var(--muted,#667085);text-decoration:none}
.dh-seg a:hover{color:var(--pri,#1d4ed8)}
.dh-seg a.on{background:var(--card,#fff);color:var(--pri,#1d4ed8);box-shadow:0 1px 3px rgba(16,24,40,.14)}
</style>
<nav class="dh-sw" aria-label="Tampilan dashboard"><span>Tampilan dashboard</span>
  <div class="dh-seg">@foreach($modelDash as $m)<a href="{{ route('dashboard.tampilan', $m) }}" class="{{ $aktif === $m ? 'on' : '' }}" @if($aktif === $m) aria-current="true" @endif>{{ $labelDash[$m] }}</a>@endforeach</div>
</nav>
@endif
EOF

for f in app/Http/Middleware/PilihDashboard.php app/Http/Controllers/TampilanController.php config/tampilan.php; do
  php -l "$f" >/dev/null || { echo "GAGAL: kesalahan sintaks pada $f"; exit 1; }
done
echo "  OK  sintaks berkas PHP"

echo "[3/4] Menyisipkan route dan pemilih pada halaman..."
# (a) route penyimpan pilihan
if grep -q "TampilanController" "$R"; then
  echo "  (route pemilih sudah ada, dilewati)"
else
  [ -f "$R.bak12" ] || cp "$R" "$R.bak12"
  cat >> "$R" <<'EOF'

// ===== Pemilih tampilan Dashboard (menyimpan pilihan di cookie, lalu membuka Dashboard) =====
Route::get('/dashboard/tampilan/{model}', [\App\Http\Controllers\TampilanController::class, 'pilih'])
    ->where('model', 'ringkas|analitik|panel')->name('dashboard.tampilan');
EOF
  echo "  OK  route /dashboard/tampilan/{model}"
fi
# (b) halaman utama memakai middleware pemilih
if grep -q "PilihDashboard" "$R"; then
  echo "  (halaman utama sudah memakai pemilih, dilewati)"
else
  [ -f "$R.bak12" ] || cp "$R" "$R.bak12"
  perl -pi -e 'if (/Route::get\(\x27\/\x27,/ && !/PilihDashboard/) { s/->name\(\x27dashboard\x27\)/->middleware(\\App\\Http\\Middleware\\PilihDashboard::class)->name(\x27dashboard\x27)/ }' "$R"
  if grep -q "PilihDashboard" "$R"; then echo "  OK  halaman utama (/) kini mengikuti pilihan tampilan"
  else echo "  PERINGATAN: baris route halaman utama tidak cocok. Tambahkan manual: ->middleware(\\App\\Http\\Middleware\\PilihDashboard::class) pada Route::get('/', ...)->name('dashboard')"; fi
fi
php -l "$R" >/dev/null || { echo "GAGAL: $R tidak valid. Pulihkan dari $R.bak12"; exit 1; }
# (c) pemilih pada tiap halaman dashboard
sisip() {   # sisip <berkas> <model>
  local f="$1" m="$2"
  [ -f "$f" ] || return 0
  if grep -q "dash._pilih" "$f"; then echo "  (pemilih sudah ada, dilewati) $f"; return 0; fi
  cp "$f" "$f.bak12"
  M="$m" perl -0pi -e 's/(\@section\(\x27content\x27\)\n)/$1\@includeIf(\x27dash._pilih\x27, [\x27aktif\x27 => \x27$ENV{M}\x27])\n/' "$f"
  if grep -q "dash._pilih" "$f"; then echo "  OK  $f"; else echo "  PERINGATAN: @section('content') tidak ditemukan di $f; tambahkan manual: @includeIf('dash._pilih', ['aktif' => '$m'])"; fi
}
sisip resources/views/dashboard.blade.php ringkas
sisip resources/views/analitik/index.blade.php analitik
sisip resources/views/panel/index.blade.php panel

echo "[4/4] Pengaturan bawaan..."
if [ -f .env ] && ! grep -q '^DASHBOARD_DEFAULT=' .env; then
  printf '\n# Model Dashboard bawaan bagi pengunjung yang belum memilih: ringkas | analitik | panel\nDASHBOARD_DEFAULT=ringkas\n' >> .env
  echo "  OK  .env: DASHBOARD_DEFAULT=ringkas"
fi
php artisan config:clear >/dev/null 2>&1 || true
php artisan optimize:clear >/dev/null 2>&1 || true
echo ""
echo "Selesai. Buka Dashboard: pemilih \"Tampilan dashboard\" tampil di kanan atas halaman."
echo "Pilihan tiap pengguna diingat di browsernya. Model bawaan: DASHBOARD_DEFAULT di .env (lalu: php artisan config:cache)."
echo "Jika memakai cache produksi: php artisan config:cache && php artisan route:cache && php artisan view:cache"
