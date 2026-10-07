#!/usr/bin/env bash
# =====================================================================
#  SISTEM INFORMASI AKREDITASI PROGRAM STUDI TEKNOLOGI INFORMASI
#  Sekolah Vokasi Universitas Tiga Serangkai
#  (berbasis Lembaga Akreditasi Mandiri Infokom / LAM Infokom)
#
#  INSTALLER TUNGGAL untuk Laravel 11 - Ubuntu/Linux, Windows (Git Bash), macOS.
#  Memasang SEMUA fitur dalam satu perintah:
#    1. Kriteria Akreditasi, Isi Kriteria (editor narasi TinyMCE), Detail Dokumen
#    2. Dashboard capaian, login (baca publik; tambah/ubah/hapus wajib login)
#    3. Tema antarmuka profesional (sidebar, header, dashboard)
#    4. Data Induk: Dokumen Standar Mutu / Universitas / Fakultas (tanpa tabel DB)
#    5. Kelola Pengguna (admin) dan Akun Saya
#    6. Gunakan kembali dokumen yang sudah pernah diunggah
#    7. Batas unggah dokumen 20 MB per berkas (Laravel + PHP + Apache)
#    8. Tautan "Lihat" (pratinjau PDF/gambar/Office, tanpa unduh langsung)
#    9. Data Induk: Dokumen Standar Mutu, Universitas, Fakultas, Tambahan
#   10. Dashboard grafik vektor (SVG): gauge, cincin KPI, radar, batang capaian
#   11. Halaman Analitik: sorotan otomatis, tren aktivitas, peta panas, corong, butir prioritas
#   12. Panel Admin: kartu statistik, grafik area/radial, aktivitas terbaru, dokumen terbaru
#   13. Pemilih tampilan Dashboard: ganti-ganti Ringkas / Analitik / Panel (diingat per browser)
#
#  Pemakaian (dari root proyek Laravel 11 YANG BARU, .env sudah diisi):
#    bash akreditasi-installer.sh [--migrate] [--produksi] [--lewati-server] [--paksa]
#  Panduan lengkap: README.md
# =====================================================================
set -e

usage() {
cat <<'USG'
Pemakaian: bash akreditasi-installer.sh [opsi]
  --migrate         jalankan migrate, buat akun admin awal, dan storage:link
                    (database di .env harus sudah dibuat)
  --produksi        APP_ENV=production, APP_DEBUG=false, lalu cache konfigurasi
  --lewati-server   jangan ubah izin folder / pengaturan PHP / restart Apache
                    (pakai di Windows, hosting bersama, atau bila tanpa sudo)
  --paksa           izinkan menimpa instalasi yang sudah ada (HATI-HATI)
  -h, --help        bantuan ini
Variabel lingkungan: SKIP_COMPOSER=1 (lewati composer require)
USG
}

MIGRATE=0; PRODUKSI=0; LEWATI_SERVER=0; PAKSA=0
for a in "$@"; do
  case "$a" in
    --migrate) MIGRATE=1;; --produksi) PRODUKSI=1;; --lewati-server) LEWATI_SERVER=1;; --paksa) PAKSA=1;;
    -h|--help) usage; exit 0;;
    *) echo "Opsi tidak dikenal: $a"; usage; exit 1;;
  esac
done

WINDOWS=0
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) WINDOWS=1;; esac

# ---------- Pemeriksaan awal ----------
if [ ! -f artisan ]; then
  echo "Error: jalankan skrip ini di root proyek Laravel (file 'artisan' tidak ditemukan)."
  echo "Buat dulu:  composer create-project \"laravel/laravel:^11.0\" akreditasi && cd akreditasi"
  exit 1
fi
command -v php >/dev/null 2>&1 || { echo "Error: PHP tidak ditemukan di PATH."; exit 1; }
php -r 'exit(version_compare(PHP_VERSION,"8.2.0",">=")?0:1);' || { echo "Error: dibutuhkan PHP 8.2 atau lebih baru (terpasang: $(php -r 'echo PHP_VERSION;'))."; exit 1; }
command -v perl >/dev/null 2>&1 || { echo "Error: perl dibutuhkan (Ubuntu: sudo apt install perl; Windows: pakai Git Bash)."; exit 1; }
if [ -z "$SKIP_COMPOSER" ]; then
  command -v composer >/dev/null 2>&1 || { echo "Error: Composer tidak ditemukan di PATH."; exit 1; }
fi
if ! php artisan --version 2>/dev/null | grep -q "Framework 11"; then
  echo "PERINGATAN: skrip dirancang untuk Laravel 11 (terdeteksi: $(php artisan --version 2>/dev/null || echo tidak diketahui))."
  echo "            Disarankan: composer create-project \"laravel/laravel:^11.0\" akreditasi"
fi
if [ -f app/Http/Controllers/KriteriaController.php ] && [ "$PAKSA" != 1 ]; then
  echo "Instalasi Akreditasi SUDAH ada di folder ini. Menjalankan ulang akan MENIMPA kode (data database tidak dihapus)."
  echo "Untuk mengubah fungsi, edit berkas langsung (lihat README, bagian 'Mengubah dan menambah fungsi')."
  echo "Jika benar-benar ingin menimpa: tambahkan opsi --paksa"
  exit 1
fi

# =====================================================================

# ---------------------------------------------------------------------
# 1. DASAR
# ---------------------------------------------------------------------
bagian_dasar() {
echo "Memasang mews/purifier (sanitasi HTML narasi)..."
if [ -z "$SKIP_COMPOSER" ]; then composer require mews/purifier --no-interaction; else echo "  (SKIP_COMPOSER: composer dilewati)"; fi

mkdir -p app/Http/Controllers resources/views/{kriteria,isi,dokumen} database/migrations

# ---------- MIGRATIONS ----------
cat > database/migrations/2026_01_01_000001_create_akreditasi_tables.php <<'EOF'
<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('kriterias', function (Blueprint $t) {
            $t->id();
            $t->string('kode', 20)->unique();
            $t->string('nama');
            $t->timestamps();
        });
        Schema::create('isi_kriteria', function (Blueprint $t) {
            $t->id();
            $t->foreignId('kriteria_id')->constrained('kriterias')->cascadeOnDelete();
            $t->string('butir', 50);
            $t->text('elemen_penilaian');
            $t->longText('narasi')->nullable();
            $t->unsignedTinyInteger('persentase')->default(0);
            $t->timestamps();
        });
        Schema::create('dokumen', function (Blueprint $t) {
            $t->id();
            $t->foreignId('isi_kriteria_id')->constrained('isi_kriteria')->cascadeOnDelete();
            $t->string('nama');
            $t->string('file_path')->nullable();
            $t->string('link')->nullable();
            $t->timestamps();
        });
    }
    public function down(): void {
        Schema::dropIfExists('dokumen');
        Schema::dropIfExists('isi_kriteria');
        Schema::dropIfExists('kriterias');
    }
};
EOF

# ---------- MODELS ----------
cat > app/Models/Kriteria.php <<'EOF'
<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;

class Kriteria extends Model {
    protected $table = 'kriterias';
    protected $fillable = ['kode', 'nama'];
    public function isi() { return $this->hasMany(IsiKriteria::class, 'kriteria_id'); }
    // Persentase Isian kriteria = rata-rata persentase seluruh butir di dalamnya
    public function getPersentaseAttribute(): int {
        return (int) round($this->isi->avg('persentase') ?? 0);
    }
}
EOF
cat > app/Models/IsiKriteria.php <<'EOF'
<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;

class IsiKriteria extends Model {
    protected $table = 'isi_kriteria';
    protected $fillable = ['kriteria_id', 'butir', 'elemen_penilaian', 'narasi', 'persentase'];
    // Tag HTML narasi yang diizinkan (editor TinyMCE); selain ini dibuang demi keamanan (XSS)
    const PURIFY = [
        'HTML.Allowed' => 'p,br,strong,b,em,i,u,s,sub,sup,blockquote,pre,code,h2,h3,h4,ul,ol,li,a[href|title],img[src|alt|width|height],table[border],thead,tbody,tr,th[colspan|rowspan],td[colspan|rowspan]',
        'AutoFormat.RemoveEmpty' => false,
    ];
    public function kriteria() { return $this->belongsTo(Kriteria::class); }
    public function dokumen() { return $this->hasMany(Dokumen::class, 'isi_kriteria_id'); }
}
EOF
cat > app/Models/Dokumen.php <<'EOF'
<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;

class Dokumen extends Model {
    protected $table = 'dokumen';
    protected $fillable = ['isi_kriteria_id', 'nama', 'file_path', 'link'];
    public function isi() { return $this->belongsTo(IsiKriteria::class, 'isi_kriteria_id'); }
}
EOF

# ---------- CONTROLLERS ----------
cat > app/Http/Controllers/DashboardController.php <<'EOF'
<?php
namespace App\Http\Controllers;
use App\Models\Kriteria;

class DashboardController extends Controller {
    public function index() {
        $rows = Kriteria::with('isi.dokumen')->orderBy('kode')->get()->map(function ($k) {
            $n = $k->isi->count();
            $pct = fn ($c) => $n ? (int) round($c / $n * 100) : 0;
            return [
                'kriteria' => $k,
                'jumlah'   => $n,
                'isian'    => $k->persentase,
                'narasi'   => $pct($k->isi->filter(fn ($i) => filled($i->narasi))->count()),
                'dokumen'  => $pct($k->isi->filter(fn ($i) => $i->dokumen->isNotEmpty())->count()),
            ];
        });
        $total = [
            'isian'   => (int) round($rows->avg('isian') ?? 0),
            'narasi'  => (int) round($rows->avg('narasi') ?? 0),
            'dokumen' => (int) round($rows->avg('dokumen') ?? 0),
        ];
        return view('dashboard', compact('rows', 'total'));
    }
}
EOF
cat > app/Http/Controllers/KriteriaController.php <<'EOF'
<?php
namespace App\Http\Controllers;
use App\Models\Kriteria;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class KriteriaController extends Controller {
    private function rules(?Kriteria $k = null): array {
        return [
            'kode' => ['required', 'max:20', Rule::unique('kriterias', 'kode')->ignore($k)],
            'nama' => 'required|max:255',
        ];
    }
    public function index() {
        return view('kriteria.index', ['items' => Kriteria::with('isi')->orderBy('kode')->paginate(15)]);
    }
    public function create() { return view('kriteria.form', ['kriteria' => new Kriteria]); }
    public function store(Request $r) {
        Kriteria::create($r->validate($this->rules()));
        return redirect()->route('kriteria.index')->with('ok', 'Kriteria ditambahkan.');
    }
    public function show(Kriteria $kriteria) {
        $kriteria->load('isi.dokumen');
        return view('kriteria.show', compact('kriteria'));
    }
    public function edit(Kriteria $kriteria) { return view('kriteria.form', compact('kriteria')); }
    public function update(Request $r, Kriteria $kriteria) {
        $kriteria->update($r->validate($this->rules($kriteria)));
        return redirect()->route('kriteria.index')->with('ok', 'Kriteria diperbarui.');
    }
    public function destroy(Kriteria $kriteria) {
        $kriteria->load('isi.dokumen');
        foreach ($kriteria->isi as $i) foreach ($i->dokumen as $d) app(DokumenController::class)->hapusFile($d);
        $kriteria->delete();
        return redirect()->route('kriteria.index')->with('ok', 'Kriteria dihapus.');
    }
}
EOF
cat > app/Http/Controllers/IsiKriteriaController.php <<'EOF'
<?php
namespace App\Http\Controllers;
use App\Models\{IsiKriteria, Kriteria};
use Illuminate\Http\Request;

class IsiKriteriaController extends Controller {
    private array $rules = [
        'kriteria_id'      => 'required|exists:kriterias,id',
        'butir'            => 'required|max:50',
        'elemen_penilaian' => 'required',
        'narasi'           => 'nullable',
        'persentase'       => 'required|integer|min:0|max:100',
    ];
    // Validasi + bersihkan HTML narasi; narasi kosong disimpan NULL agar dihitung "belum terisi"
    private function data(Request $r): array {
        $d = $r->validate($this->rules);
        $html = clean($d['narasi'] ?? '', IsiKriteria::PURIFY);
        if (trim(strip_tags($html)) === '' && !preg_match('/<(img|table)/i', $html)) $html = null;
        $d['narasi'] = $html;
        return $d;
    }
    // Endpoint unggah gambar untuk editor narasi (TinyMCE)
    public function unggahGambar(Request $r) {
        $r->validate(['file' => 'required|image|mimes:jpg,jpeg,png,gif,webp|max:4096']);
        $path = $r->file('file')->store('narasi-gambar', 'public');
        return response()->json(['location' => '/storage/'.$path]);
    }
    public function create(Request $r) {
        $isi = new IsiKriteria(['kriteria_id' => $r->query('kriteria_id'), 'persentase' => 0]);
        return view('isi.form', ['isi' => $isi, 'kriterias' => Kriteria::orderBy('kode')->get()]);
    }
    public function store(Request $r) {
        $isi = IsiKriteria::create($this->data($r));
        return redirect()->route('kriteria.show', $isi->kriteria_id)->with('ok', 'Isi kriteria ditambahkan.');
    }
    public function show(IsiKriteria $isi) {
        $isi->load('kriteria', 'dokumen');
        return view('isi.show', compact('isi'));
    }
    public function edit(IsiKriteria $isi) {
        return view('isi.form', ['isi' => $isi, 'kriterias' => Kriteria::orderBy('kode')->get()]);
    }
    public function update(Request $r, IsiKriteria $isi) {
        $isi->update($this->data($r));
        return redirect()->route('isi.show', $isi)->with('ok', 'Isi kriteria diperbarui.');
    }
    public function destroy(IsiKriteria $isi) {
        $isi->load('dokumen');
        foreach ($isi->dokumen as $d) app(DokumenController::class)->hapusFile($d);
        $kid = $isi->kriteria_id;
        $isi->delete();
        return redirect()->route('kriteria.show', $kid)->with('ok', 'Isi kriteria dihapus.');
    }
}
EOF
cat > app/Http/Controllers/DokumenController.php <<'EOF'
<?php
namespace App\Http\Controllers;
use App\Models\{Dokumen, IsiKriteria};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class DokumenController extends Controller {
    private function rules(): array {
        return [
            'isi_kriteria_id' => 'required|exists:isi_kriteria,id',
            'nama'            => 'required|max:255',
            'file'            => 'nullable|file|max:20480|mimes:pdf,doc,docx,xls,xlsx,ppt,pptx,zip,jpg,png',
            'link'            => 'nullable|url|max:500',
        ];
    }
    public function hapusFile(Dokumen $d): void {
        if ($d->file_path) Storage::disk('public')->delete($d->file_path);
    }
    public function create(Request $r) {
        $dokumen = new Dokumen(['isi_kriteria_id' => $r->query('isi_id')]);
        return view('dokumen.form', ['dokumen' => $dokumen, 'isi' => IsiKriteria::with('kriteria')->findOrFail($r->query('isi_id'))]);
    }
    public function store(Request $r) {
        $data = $r->validate($this->rules());
        if (!$r->hasFile('file') && blank($data['link'] ?? null)) {
            return back()->withInput()->withErrors(['file' => 'Unggah berkas atau isi link dokumen.']);
        }
        if ($r->hasFile('file')) $data['file_path'] = $r->file('file')->store('dokumen-akreditasi', 'public');
        unset($data['file']);
        $d = Dokumen::create($data);
        return redirect()->route('isi.show', $d->isi_kriteria_id)->with('ok', 'Dokumen ditambahkan.');
    }
    public function edit(Dokumen $dokumen) {
        return view('dokumen.form', ['dokumen' => $dokumen, 'isi' => $dokumen->isi->load('kriteria')]);
    }
    public function update(Request $r, Dokumen $dokumen) {
        $data = $r->validate($this->rules());
        if ($r->hasFile('file')) {
            $this->hapusFile($dokumen);
            $data['file_path'] = $r->file('file')->store('dokumen-akreditasi', 'public');
        }
        unset($data['file']);
        if (blank($data['file_path'] ?? $dokumen->file_path) && blank($data['link'] ?? null)) {
            return back()->withInput()->withErrors(['file' => 'Dokumen harus berupa berkas atau link.']);
        }
        $dokumen->update($data);
        return redirect()->route('isi.show', $dokumen->isi_kriteria_id)->with('ok', 'Dokumen diperbarui.');
    }
    public function destroy(Dokumen $dokumen) {
        $this->hapusFile($dokumen);
        $id = $dokumen->isi_kriteria_id;
        $dokumen->delete();
        return redirect()->route('isi.show', $id)->with('ok', 'Dokumen dihapus.');
    }
}
EOF

# ---------- ROUTES ----------
cat > routes/web.php <<'EOF'
<?php
use App\Http\Controllers\{DashboardController, KriteriaController, IsiKriteriaController, DokumenController};
use Illuminate\Support\Facades\Route;

// Tambahkan middleware('auth') bila memakai Breeze/Fortify.
Route::get('/', [DashboardController::class, 'index'])->name('dashboard');
Route::resource('kriteria', KriteriaController::class)->parameters(['kriteria' => 'kriteria']);
Route::resource('isi', IsiKriteriaController::class)->except('index')->parameters(['isi' => 'isi']);
Route::resource('dokumen', DokumenController::class)->only(['create', 'store', 'edit', 'update', 'destroy'])->parameters(['dokumen' => 'dokumen']);
Route::post('/unggah-gambar', [IsiKriteriaController::class, 'unggahGambar'])->name('unggah.gambar');
EOF

# ---------- VIEWS ----------
cat > resources/views/layout.blade.php <<'EOF'
<!doctype html>
<html lang="id">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>@yield('title', 'Dokumen Akreditasi') - Sistem Informasi Akreditasi</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
<style>.elemen{font-size:.82rem;line-height:1.5}</style>
</head>
<body class="bg-light">
<header class="bg-white border-bottom py-3">
  <div class="container">
    <a href="{{ route('dashboard') }}" class="fs-5 fw-semibold text-decoration-none text-dark">Sistem Informasi Akreditasi Program Studi Teknologi Informasi<br><small class="fw-normal text-muted">Sekolah Vokasi Universitas Tiga Serangkai</small></a>
  </div>
</header>
<nav class="navbar navbar-expand navbar-dark bg-primary mb-4">
  <div class="container">
    <div class="navbar-nav">
      <a class="nav-link" href="{{ route('dashboard') }}">Dashboard</a>
      <a class="nav-link" href="{{ route('kriteria.index') }}">Kriteria</a>
    </div>
  </div>
</nav>
<main class="container pb-5">
  @if(session('ok'))<div class="alert alert-success">{{ session('ok') }}</div>@endif
  @if($errors->any())<div class="alert alert-danger"><ul class="mb-0">@foreach($errors->all() as $e)<li>{{ $e }}</li>@endforeach</ul></div>@endif
  @yield('content')
</main>
</body>
</html>
EOF

cat > resources/views/bar.blade.php <<'EOF'
@php $v = (int) $v; $c = $v >= 80 ? 'bg-success' : ($v >= 50 ? 'bg-warning' : 'bg-danger'); @endphp
<div class="progress" style="height:20px"><div class="progress-bar {{ $c }}" style="width:{{ $v }}%">{{ $v }}%</div></div>
EOF

cat > resources/views/dashboard.blade.php <<'EOF'
@extends('layout')
@section('title', 'Dashboard')
@section('content')
<h4 class="mb-3">Dashboard capaian</h4>
<div class="row g-3 mb-4">
  @foreach(['isian' => 'Isian kriteria', 'narasi' => 'Isian narasi', 'dokumen' => 'Kelengkapan dokumen'] as $k => $label)
  <div class="col-md-4"><div class="card"><div class="card-body">
    <div class="text-muted small">{{ $label }} (rata-rata semua kriteria)</div>
    <div class="display-6 mb-2">{{ $total[$k] }}%</div>
    @include('bar', ['v' => $total[$k]])
  </div></div></div>
  @endforeach
</div>
<div class="card"><div class="table-responsive">
<table class="table align-middle mb-0">
  <thead><tr><th>Kriteria</th><th class="text-center">Butir</th><th style="width:20%">Isian</th><th style="width:20%">Narasi</th><th style="width:20%">Dokumen</th></tr></thead>
  <tbody>
  @forelse($rows as $r)
    <tr>
      <td><a href="{{ route('kriteria.show', $r['kriteria']) }}">{{ $r['kriteria']->kode }} - {{ $r['kriteria']->nama }}</a></td>
      <td class="text-center">{{ $r['jumlah'] }}</td>
      <td>@include('bar', ['v' => $r['isian']])</td>
      <td>@include('bar', ['v' => $r['narasi']])</td>
      <td>@include('bar', ['v' => $r['dokumen']])</td>
    </tr>
  @empty
    <tr><td colspan="5" class="text-center text-muted py-4">Belum ada kriteria. <a href="{{ route('kriteria.create') }}">Tambah kriteria</a></td></tr>
  @endforelse
  </tbody>
</table></div></div>
<p class="text-muted small mt-2">Narasi = butir yang narasinya sudah terisi. Dokumen = butir yang memiliki minimal satu dokumen/link.</p>
@endsection
EOF

cat > resources/views/kriteria/index.blade.php <<'EOF'
@extends('layout')
@section('title', 'Kriteria Akreditasi')
@section('content')
<div class="d-flex justify-content-between mb-3"><h4>Kriteria Akreditasi</h4><a href="{{ route('kriteria.create') }}" class="btn btn-primary">Tambah kriteria</a></div>
<div class="card"><table class="table align-middle mb-0">
  <thead><tr><th>Kode</th><th>Nama kriteria</th><th style="width:20%">Persentase isian</th><th class="text-end">Aksi</th></tr></thead>
  <tbody>
  @forelse($items as $k)
    <tr>
      <td>{{ $k->kode }}</td><td>{{ $k->nama }}</td>
      <td>@include('bar', ['v' => $k->persentase])</td>
      <td class="text-end">
        <a href="{{ route('kriteria.show', $k) }}" class="btn btn-sm btn-outline-primary">Isi kriteria</a>
        <a href="{{ route('kriteria.edit', $k) }}" class="btn btn-sm btn-outline-secondary">Ubah</a>
        <form action="{{ route('kriteria.destroy', $k) }}" method="post" class="d-inline" onsubmit="return confirm('Hapus kriteria beserta isi dan dokumennya?')">@csrf @method('DELETE')<button class="btn btn-sm btn-outline-danger">Hapus</button></form>
      </td>
    </tr>
  @empty
    <tr><td colspan="4" class="text-center text-muted py-4">Belum ada kriteria.</td></tr>
  @endforelse
  </tbody>
</table></div>
<div class="mt-3">{{ $items->links() }}</div>
@endsection
EOF

cat > resources/views/kriteria/form.blade.php <<'EOF'
@extends('layout')
@section('title', $kriteria->exists ? 'Ubah Kriteria' : 'Tambah Kriteria')
@section('content')
<h4 class="mb-3">{{ $kriteria->exists ? 'Ubah' : 'Tambah' }} kriteria</h4>
<form method="post" class="card card-body" action="{{ $kriteria->exists ? route('kriteria.update', $kriteria) : route('kriteria.store') }}">
  @csrf @if($kriteria->exists) @method('PUT') @endif
  <div class="mb-3"><label class="form-label">Kode kriteria</label><input name="kode" class="form-control" value="{{ old('kode', $kriteria->kode) }}" required></div>
  <div class="mb-3"><label class="form-label">Nama kriteria</label><input name="nama" class="form-control" value="{{ old('nama', $kriteria->nama) }}" required></div>
  <p class="text-muted small">Persentase isian dihitung otomatis dari rata-rata persentase butir di dalam kriteria.</p>
  <div><button class="btn btn-primary">Simpan</button> <a href="{{ route('kriteria.index') }}" class="btn btn-link">Batal</a></div>
</form>
@endsection
EOF

cat > resources/views/kriteria/show.blade.php <<'EOF'
@extends('layout')
@section('title', $kriteria->kode)
@section('content')
<div class="d-flex justify-content-between mb-2">
  <h4>{{ $kriteria->kode }} - {{ $kriteria->nama }}</h4>
  <a href="{{ route('isi.create', ['kriteria_id' => $kriteria->id]) }}" class="btn btn-primary">Tambah isi kriteria</a>
</div>
<div class="mb-3" style="max-width:400px">@include('bar', ['v' => $kriteria->persentase])</div>
<div class="card"><table class="table align-middle mb-0">
  <thead><tr><th>Butir</th><th>Elemen penilaian</th><th>Narasi</th><th style="width:15%">Isian</th><th class="text-center">Dokumen</th><th class="text-end">Aksi</th></tr></thead>
  <tbody>
  @forelse($kriteria->isi as $i)
    <tr>
      <td>{{ $i->butir }}</td>
      <td class="elemen" style="min-width:260px">{!! nl2br(e($i->elemen_penilaian)) !!}</td>
      <td style="min-width:240px">
        @if(filled($i->narasi))
          {{ \Illuminate\Support\Str::limit(trim(preg_replace('/\s+/', ' ', html_entity_decode(strip_tags($i->narasi)))) ?: '[Narasi berisi gambar/tabel]', 140) }}
          <a href="{{ route('isi.show', $i) }}">Read more</a>
        @else
          <span class="badge text-bg-secondary">Kosong</span>
        @endif
      </td>
      <td>@include('bar', ['v' => $i->persentase])</td>
      <td class="text-center">{{ $i->dokumen->count() }}</td>
      <td class="text-end">
        <a href="{{ route('isi.show', $i) }}" class="btn btn-sm btn-outline-primary">Detail</a>
        <a href="{{ route('isi.edit', $i) }}" class="btn btn-sm btn-outline-secondary">Ubah</a>
        <form action="{{ route('isi.destroy', $i) }}" method="post" class="d-inline" onsubmit="return confirm('Hapus butir ini beserta dokumennya?')">@csrf @method('DELETE')<button class="btn btn-sm btn-outline-danger">Hapus</button></form>
      </td>
    </tr>
  @empty
    <tr><td colspan="6" class="text-center text-muted py-4">Belum ada isi kriteria.</td></tr>
  @endforelse
  </tbody>
</table></div>
<a href="{{ route('kriteria.index') }}" class="btn btn-link mt-2">Kembali</a>
@endsection
EOF

cat > resources/views/isi/form.blade.php <<'EOF'
@extends('layout')
@section('title', $isi->exists ? 'Ubah Isi Kriteria' : 'Tambah Isi Kriteria')
@section('content')
<h4 class="mb-3">{{ $isi->exists ? 'Ubah' : 'Tambah' }} isi kriteria</h4>
<form method="post" class="card card-body" action="{{ $isi->exists ? route('isi.update', $isi) : route('isi.store') }}">
  @csrf @if($isi->exists) @method('PUT') @endif
  <div class="mb-3"><label class="form-label">Kriteria</label>
    <select name="kriteria_id" class="form-select" required>
      @foreach($kriterias as $k)<option value="{{ $k->id }}" @selected(old('kriteria_id', $isi->kriteria_id) == $k->id)>{{ $k->kode }} - {{ $k->nama }}</option>@endforeach
    </select></div>
  <div class="mb-3"><label class="form-label">Butir</label><input name="butir" class="form-control" value="{{ old('butir', $isi->butir) }}" required></div>
  <div class="mb-3"><label class="form-label">Elemen penilaian</label><textarea name="elemen_penilaian" rows="3" class="form-control" required>{{ old('elemen_penilaian', $isi->elemen_penilaian) }}</textarea></div>
  <div class="mb-3"><label class="form-label">Narasi</label><textarea name="narasi" id="narasi" rows="12" class="form-control">{{ old('narasi', $isi->narasi) }}</textarea></div>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/tinymce/6.8.3/tinymce.min.js" referrerpolicy="origin"></script>
  <script>
    tinymce.init({
      selector: '#narasi',
      height: 460,
      branding: false,
      promotion: false,
      menubar: 'edit insert format table',
      plugins: 'table image lists link code autoresize',
      toolbar: 'undo redo | blocks | bold italic underline | alignleft aligncenter alignright | bullist numlist | table image link | removeformat code',
      relative_urls: false,
      convert_urls: false,
      automatic_uploads: true,
      paste_data_images: true,
      image_title: true,
      file_picker_types: 'image',
      images_upload_handler: function (blobInfo) {
        return new Promise(function (resolve, reject) {
          var fd = new FormData();
          fd.append('file', blobInfo.blob(), blobInfo.filename());
          fetch("{{ route('unggah.gambar') }}", { method: 'POST', headers: { 'X-CSRF-TOKEN': '{{ csrf_token() }}', 'Accept': 'application/json' }, body: fd })
            .then(function (r) { return r.ok ? r.json() : Promise.reject(); })
            .then(function (j) { resolve(j.location); })
            .catch(function () { reject('Gagal mengunggah gambar (maks. 4 MB; jpg, png, gif, webp).'); });
        });
      },
      file_picker_callback: function (cb, value, meta) {
        if (meta.filetype !== 'image') return;
        var i = document.createElement('input'); i.type = 'file'; i.accept = 'image/*';
        i.onchange = function () {
          var f = i.files[0], r = new FileReader();
          r.onload = function () {
            var bc = tinymce.activeEditor.editorUpload.blobCache, bi = bc.create('blob' + Date.now(), f, r.result.split(',')[1]);
            bc.add(bi); cb(bi.blobUri(), { title: f.name });
          };
          r.readAsDataURL(f);
        };
        i.click();
      }
    });
  </script>
  <div class="mb-3"><label class="form-label">Persentase isian (0-100)</label><input type="number" min="0" max="100" name="persentase" class="form-control" value="{{ old('persentase', $isi->persentase) }}" required></div>
  <div><button class="btn btn-primary">Simpan</button> <a href="{{ url()->previous() }}" class="btn btn-link">Batal</a></div>
</form>
@endsection
EOF

cat > resources/views/isi/show.blade.php <<'EOF'
@extends('layout')
@section('title', 'Butir '.$isi->butir)
@section('content')
<p class="mb-1"><a href="{{ route('kriteria.show', $isi->kriteria) }}">&larr; {{ $isi->kriteria->kode }} - {{ $isi->kriteria->nama }}</a></p>
<h4>Butir {{ $isi->butir }}</h4>
<div class="card card-body mb-4">
  <h6>Elemen penilaian</h6><p class="elemen">{!! nl2br(e($isi->elemen_penilaian)) !!}</p>
  <style>
    .narasi img{max-width:100%;height:auto}
    .narasi table{border-collapse:collapse;width:100%;margin-bottom:1rem}
    .narasi td,.narasi th{border:1px solid #dee2e6;padding:.4rem .6rem}
    .narasi.clamp{max-height:160px;overflow:hidden;-webkit-mask-image:linear-gradient(#000 55%,transparent);mask-image:linear-gradient(#000 55%,transparent)}
  </style>
  <h6>Narasi</h6>
  @if(filled($isi->narasi))
    <div class="narasi clamp" id="narasi-box">{!! clean($isi->narasi, \App\Models\IsiKriteria::PURIFY) !!}</div>
    <button type="button" class="btn btn-link p-0 mb-3 d-none" id="narasi-toggle">Read more</button>
    <script>
      (function () {
        var b = document.getElementById('narasi-box'), t = document.getElementById('narasi-toggle');
        function cek() { if (b.classList.contains('clamp') && b.scrollHeight > b.clientHeight + 4) t.classList.remove('d-none'); }
        t.onclick = function () { var tutup = b.classList.toggle('clamp'); t.textContent = tutup ? 'Read more' : 'Read less'; };
        cek(); window.addEventListener('load', cek);
      })();
    </script>
  @else
    <div class="mb-3 text-muted">Narasi belum diisi.</div>
  @endif
  <h6>Persentase isian</h6><div style="max-width:400px">@include('bar', ['v' => $isi->persentase])</div>
  <div class="mt-3"><a href="{{ route('isi.edit', $isi) }}" class="btn btn-sm btn-outline-secondary">Ubah isi</a></div>
</div>
<div class="d-flex justify-content-between mb-2"><h5>Detail dokumen</h5><a href="{{ route('dokumen.create', ['isi_id' => $isi->id]) }}" class="btn btn-primary btn-sm">Tambah dokumen</a></div>
<div class="card"><table class="table align-middle mb-0">
  <thead><tr><th>Butir</th><th>Nama dokumen</th><th>Dokumen / link</th><th class="text-end">Aksi</th></tr></thead>
  <tbody>
  @forelse($isi->dokumen as $d)
    <tr>
      <td>{{ $isi->butir }}</td><td>{{ $d->nama }}</td>
      <td>
        @if($d->file_path)<a href="{{ asset('storage/'.$d->file_path) }}" target="_blank">Unduh berkas</a>@endif
        @if($d->file_path && $d->link) &nbsp;|&nbsp; @endif
        @if($d->link)<a href="{{ $d->link }}" target="_blank" rel="noopener">Buka link</a>@endif
      </td>
      <td class="text-end">
        <a href="{{ route('dokumen.edit', $d) }}" class="btn btn-sm btn-outline-secondary">Ubah</a>
        <form action="{{ route('dokumen.destroy', $d) }}" method="post" class="d-inline" onsubmit="return confirm('Hapus dokumen ini?')">@csrf @method('DELETE')<button class="btn btn-sm btn-outline-danger">Hapus</button></form>
      </td>
    </tr>
  @empty
    <tr><td colspan="4" class="text-center text-muted py-4">Belum ada dokumen.</td></tr>
  @endforelse
  </tbody>
</table></div>
@endsection
EOF

cat > resources/views/dokumen/form.blade.php <<'EOF'
@extends('layout')
@section('title', $dokumen->exists ? 'Ubah Dokumen' : 'Tambah Dokumen')
@section('content')
<h4 class="mb-3">{{ $dokumen->exists ? 'Ubah' : 'Tambah' }} dokumen - Butir {{ $isi->butir }}</h4>
<form method="post" enctype="multipart/form-data" class="card card-body" action="{{ $dokumen->exists ? route('dokumen.update', $dokumen) : route('dokumen.store') }}">
  @csrf @if($dokumen->exists) @method('PUT') @endif
  <input type="hidden" name="isi_kriteria_id" value="{{ $isi->id }}">
  <div class="mb-3"><label class="form-label">Nama dokumen</label><input name="nama" class="form-control" value="{{ old('nama', $dokumen->nama) }}" required></div>
  <div class="mb-3"><label class="form-label">Berkas (PDF, Office, ZIP, gambar; maks. 20 MB)</label>
    <input type="file" name="file" class="form-control">
    @if($dokumen->file_path)<div class="form-text">Berkas saat ini: <a href="{{ asset('storage/'.$dokumen->file_path) }}" target="_blank">unduh</a>. Unggah berkas baru untuk menggantinya.</div>@endif</div>
  <div class="mb-3"><label class="form-label">Atau link dokumen</label><input type="url" name="link" class="form-control" placeholder="https://" value="{{ old('link', $dokumen->link) }}"></div>
  <div><button class="btn btn-primary">Simpan</button> <a href="{{ route('isi.show', $isi) }}" class="btn btn-link">Batal</a></div>
</form>
@endsection
EOF

php artisan storage:link 2>/dev/null || true
mkdir -p resources/views/auth database/seeders

# ---------- AUTH CONTROLLER ----------
cat > app/Http/Controllers/AuthController.php <<'EOF'
<?php
namespace App\Http\Controllers;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class AuthController extends Controller {
    public function showLogin() { return view('auth.login'); }

    public function login(Request $r) {
        $cred = $r->validate(['email' => 'required|email', 'password' => 'required']);
        if (Auth::attempt($cred, $r->boolean('remember'))) {
            $r->session()->regenerate();
            return redirect()->intended(route('dashboard'));
        }
        return back()->withInput($r->only('email'))->withErrors(['email' => 'Email atau kata sandi salah.']);
    }

    public function logout(Request $r) {
        Auth::logout();
        $r->session()->invalidate();
        $r->session()->regenerateToken();
        return redirect()->route('dashboard');
    }
}
EOF

# ---------- ROUTES ----------
cat > routes/web.php <<'EOF'
<?php
use App\Http\Controllers\{AuthController, DashboardController, KriteriaController, IsiKriteriaController, DokumenController};
use Illuminate\Support\Facades\Route;

// Login / logout
Route::middleware('guest')->group(function () {
    Route::get('/login', [AuthController::class, 'showLogin'])->name('login');
    Route::post('/login', [AuthController::class, 'login'])->middleware('throttle:5,1');
});
Route::post('/logout', [AuthController::class, 'logout'])->middleware('auth')->name('logout');

// Wajib login: tambah, ubah, hapus (HARUS dideklarasikan sebelum rute publik agar /create tidak tertangkap {param})
Route::middleware('auth')->group(function () {
    Route::resource('kriteria', KriteriaController::class)->except(['index', 'show'])->parameters(['kriteria' => 'kriteria']);
    Route::resource('isi', IsiKriteriaController::class)->except(['index', 'show'])->parameters(['isi' => 'isi']);
    Route::resource('dokumen', DokumenController::class)->only(['create', 'store', 'edit', 'update', 'destroy'])->parameters(['dokumen' => 'dokumen']);
    Route::post('/unggah-gambar', [IsiKriteriaController::class, 'unggahGambar'])->name('unggah.gambar');
});

// Publik: hanya baca
Route::get('/', [DashboardController::class, 'index'])->name('dashboard');
Route::resource('kriteria', KriteriaController::class)->only(['index', 'show'])->parameters(['kriteria' => 'kriteria']);
Route::resource('isi', IsiKriteriaController::class)->only(['show'])->parameters(['isi' => 'isi']);
EOF

# ---------- VIEWS ----------
cat > resources/views/layout.blade.php <<'EOF'
<!doctype html>
<html lang="id">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>@yield('title', 'Dokumen Akreditasi') - Sistem Informasi Akreditasi</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
<style>.elemen{font-size:.82rem;line-height:1.5}</style>
</head>
<body class="bg-light">
<header class="bg-white border-bottom py-3">
  <div class="container">
    <a href="{{ route('dashboard') }}" class="fs-5 fw-semibold text-decoration-none text-dark">Sistem Informasi Akreditasi Program Studi Teknologi Informasi<br><small class="fw-normal text-muted">Sekolah Vokasi Universitas Tiga Serangkai</small></a>
  </div>
</header>
<nav class="navbar navbar-expand navbar-dark bg-primary mb-4">
  <div class="container">
    <div class="navbar-nav me-auto">
      <a class="nav-link" href="{{ route('dashboard') }}">Dashboard</a>
      <a class="nav-link" href="{{ route('kriteria.index') }}">Kriteria</a>
    </div>
    <div class="navbar-nav align-items-center">
      @auth
        <span class="navbar-text me-3">{{ auth()->user()->name }}</span>
        <form action="{{ route('logout') }}" method="post" class="d-inline">@csrf<button class="btn btn-sm btn-light">Keluar</button></form>
      @else
        <a class="btn btn-sm btn-light" href="{{ route('login') }}">Masuk</a>
      @endauth
    </div>
  </div>
</nav>
<main class="container pb-5">
  @if(session('ok'))<div class="alert alert-success">{{ session('ok') }}</div>@endif
  @if($errors->any())<div class="alert alert-danger"><ul class="mb-0">@foreach($errors->all() as $e)<li>{{ $e }}</li>@endforeach</ul></div>@endif
  @yield('content')
</main>
</body>
</html>
EOF

cat > resources/views/auth/login.blade.php <<'EOF'
@extends('layout')
@section('title', 'Masuk')
@section('content')
<div class="row justify-content-center"><div class="col-md-5">
  <h4 class="mb-3">Masuk</h4>
  <p class="text-muted">Login diperlukan untuk menambah, mengubah, dan menghapus data.</p>
  <form method="post" action="{{ route('login') }}" class="card card-body">
    @csrf
    <div class="mb-3"><label class="form-label">Email</label><input type="email" name="email" class="form-control" value="{{ old('email') }}" required autofocus></div>
    <div class="mb-3"><label class="form-label">Kata sandi</label><input type="password" name="password" class="form-control" required></div>
    <div class="form-check mb-3"><input type="checkbox" name="remember" value="1" class="form-check-input" id="remember"><label for="remember" class="form-check-label">Ingat saya</label></div>
    <button class="btn btn-primary">Masuk</button>
  </form>
</div></div>
@endsection
EOF

# Sembunyikan tombol tambah/ubah/hapus dari pengunjung (tamu) pada view yang sudah ada
for f in resources/views/dashboard.blade.php resources/views/kriteria/index.blade.php resources/views/kriteria/show.blade.php resources/views/isi/show.blade.php; do
  grep -q '@auth' "$f" && continue   # lewati jika sudah pernah diproses
  perl -0pi -e '
    s{(<a [^<]*?route\(\x27(?:kriteria|isi|dokumen)\.(?:create|edit)\x27[^<]*</a>)}{\@auth $1 \@endauth}g;
    s{(<form [^<]*?route\(\x27(?:kriteria|isi|dokumen)\.destroy\x27.*?</form>)}{\@auth $1 \@endauth}g;
  ' "$f"
done

# ---------- SEEDER PENGGUNA ----------
cat > database/seeders/AdminSeeder.php <<'EOF'
<?php
namespace Database\Seeders;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class AdminSeeder extends Seeder {
    public function run(): void {
        User::updateOrCreate(
            ['email' => 'admin@example.com'],
            ['name' => 'Administrator', 'password' => Hash::make('GantiSandiIni123')]
        );
    }
}
EOF
}

# ---------------------------------------------------------------------
# 2. TEMA ANTARMUKA
# ---------------------------------------------------------------------
bagian_tema() {
mkdir -p public/css
for f in resources/views/layout.blade.php resources/views/dashboard.blade.php resources/views/bar.blade.php; do
  [ -f "$f" ] && cp "$f" "$f.bak"
done

cat > public/css/tema.css <<'EOF'
:root{--bg:#f3f5f9;--card:#fff;--text:#1b2536;--muted:#667085;--line:#e4e8ef;--head:#f7f9fc;--pri:#1d4ed8;--ok:#15803d;--warn:#b45309;--bad:#b91c1c;--sb:#0c2340}
body{background:var(--bg);color:var(--text)}
/* ===== TEMA PROFESIONAL ===== */
body{font-family:Inter,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;-webkit-font-smoothing:antialiased}
.shell{display:flex;min-height:100vh}
.sb{width:256px;flex:none;background:var(--sb);color:#cbd6e6;display:flex;flex-direction:column;padding:20px 14px;position:sticky;top:0;height:100vh;overflow-y:auto}
.brand{display:flex;gap:11px;align-items:center;padding:2px 6px 18px;margin-bottom:14px;border-bottom:1px solid rgba(255,255,255,.1);text-decoration:none;cursor:pointer}
.logo{width:40px;height:40px;flex:none;border-radius:11px;background:linear-gradient(135deg,#3b82f6,#14b8a6);display:grid;place-items:center;color:#fff;font-weight:700;font-size:14px}
.brand b{display:block;color:#fff;font-size:13px;line-height:1.3;font-weight:600}
.brand small{display:block;color:#93a4bd;font-size:11.5px;line-height:1.3;margin-top:2px}
.mlabel{font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:#7f92ae;padding:6px 12px}
.mi{display:flex;gap:11px;align-items:center;padding:10px 12px;border-radius:9px;color:#cbd6e6;cursor:pointer;margin-bottom:3px;font-size:14.5px;text-decoration:none}
.mi:hover{background:rgba(255,255,255,.08);color:#fff}
.mi.on{background:rgba(255,255,255,.15);color:#fff;font-weight:600}
.mi svg{width:18px;height:18px;flex:none}
.sfoot{margin-top:auto;padding:12px 8px 0;font-size:12px;color:#7f92ae;border-top:1px solid rgba(255,255,255,.1)}
.mn{flex:1;min-width:0}
.top{display:flex;align-items:center;gap:12px;padding:12px 28px;background:var(--card);border-bottom:1px solid var(--line);position:sticky;top:0;z-index:5}
.crumb{font-size:14px;color:var(--muted)}.crumb b{color:var(--text);font-weight:600}
.top .sp{flex:1}.chip{font-size:13px;padding:4px 11px;border-radius:999px;background:var(--head);border:1px solid var(--line)}
.content{max-width:1120px;margin:0 auto;padding:26px 28px 56px}
h1{font-size:22px;font-weight:650;letter-spacing:-.01em}
.card{border:1px solid var(--line);border-radius:12px;box-shadow:0 1px 2px rgba(16,24,40,.04);overflow:hidden}
.hero{background:linear-gradient(120deg,#0c2340,#1d4ed8);color:#fff;border-radius:14px;padding:22px 26px;display:flex;gap:24px;align-items:center;flex-wrap:wrap;margin-bottom:18px}
.hero .hx{font-size:48px;font-weight:700;line-height:1}.hero .hl{opacity:.8;font-size:13px;margin-bottom:6px}
.hero .hs{display:flex;gap:30px;flex-wrap:wrap;margin-left:auto}.hero .hs div{font-size:12.5px;opacity:.9}.hero .hs b{display:block;font-size:22px}
.sec{font-size:12px;letter-spacing:.06em;text-transform:uppercase;color:var(--muted);font-weight:600;margin:6px 0 8px}
th{font-size:11.5px!important;letter-spacing:.05em;text-transform:uppercase;font-weight:600!important;color:var(--muted)!important;background:var(--head)!important}
tbody tr:hover>*{background:var(--head)}
.bw{display:flex;align-items:center;gap:9px}.bw span{font-size:12.5px;font-weight:600;min-width:38px;text-align:right}
.bar{flex:1;height:8px;background:#e6ebf3;border-radius:999px;overflow:hidden;min-width:70px}
.fill{height:100%;border-radius:999px;min-width:0;padding:0}
.g{background:var(--ok)}.y{background:var(--warn)}.rd{background:var(--bad)}
@media(max-width:860px){.shell{display:block}.sb{position:static;width:auto;height:auto;flex-direction:row;flex-wrap:wrap;padding:12px 14px}.brand{flex:1 1 100%;border:0;margin:0;padding:0 0 10px}.sb .menu{display:flex;gap:6px}.mlabel,.sfoot{display:none}.top{padding:10px 14px}.content{padding:18px 14px 44px}.hero .hs{margin-left:0}}

/* Penyesuaian Bootstrap */
.btn{border-radius:8px;font-weight:500}
.btn-primary{--bs-btn-bg:var(--pri);--bs-btn-border-color:var(--pri);--bs-btn-hover-bg:#1a43b8;--bs-btn-hover-border-color:#1a43b8}
.btn-outline-primary{--bs-btn-color:var(--pri);--bs-btn-border-color:var(--pri);--bs-btn-hover-bg:var(--pri)}
.form-control,.form-select{border-radius:8px;border-color:#d5dbe5}
.form-control:focus,.form-select:focus{border-color:var(--pri);box-shadow:0 0 0 .2rem rgba(29,78,216,.15)}
.table>:not(caption)>*>*{padding:.8rem 1rem}
.alert{border-radius:10px}
a{color:var(--pri)}
/* data-induk */
.mi.grp{margin-top:12px;color:#fff;font-weight:600;cursor:default}.mi.grp:hover{background:none}
.mi.sub{padding:8px 12px 8px 40px;font-size:13.5px}
.hd2{background:var(--card);border-bottom:1px solid var(--line);border-left:4px solid var(--pri);padding:14px 28px}
.hd2 .t1{font-size:17px;font-weight:650;line-height:1.3;letter-spacing:-.01em}
.hd2 .t2{font-size:13px;color:var(--muted);margin-top:2px}
.elemen,.el{font-size:.82rem;line-height:1.5}
@media(max-width:860px){.hd2{padding:12px 14px}.hd2 .t1{font-size:15px}}
EOF

cat > resources/views/bar.blade.php <<'EOF'
@php $v = (int) $v; $c = $v >= 80 ? 'g' : ($v >= 50 ? 'y' : 'rd'); @endphp
<div class="bw"><div class="bar"><div class="fill {{ $c }}" style="width:{{ $v }}%"></div></div><span>{{ $v }}%</span></div>
EOF

cat > resources/views/layout.blade.php <<'EOF'
<!doctype html>
<html lang="id">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>@yield('title', 'Dokumen Akreditasi') - Sistem Informasi Akreditasi</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
  <link href="{{ asset('css/tema.css') }}?v={{ filemtime(public_path('css/tema.css')) }}" rel="stylesheet">
</head>
<body>
<div class="shell">
  <aside class="sb">
    <a class="brand" href="{{ route('dashboard') }}">
      <span class="logo">SIA</span>
      <span><b>SIA Prodi Teknologi Informasi</b><small>Sekolah Vokasi Universitas Tiga Serangkai</small></span>
    </a>
    <div class="mlabel">Menu</div>
    <div class="menu">
      <a class="mi {{ request()->routeIs('dashboard') ? 'on' : '' }}" href="{{ route('dashboard') }}">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="7" height="9" rx="1"/><rect x="14" y="3" width="7" height="5" rx="1"/><rect x="14" y="12" width="7" height="9" rx="1"/><rect x="3" y="16" width="7" height="5" rx="1"/></svg>Dashboard
      </a>
      <a class="mi {{ request()->routeIs('kriteria.*', 'isi.*', 'dokumen.*') ? 'on' : '' }}" href="{{ route('kriteria.index') }}">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/></svg>Kriteria
      </a>
      @if(Route::has('datainduk.index'))
      <div class="mi grp"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>Data Induk</div>
      <a class="mi sub {{ request()->is('data-induk/standar-mutu*') ? 'on' : '' }}" href="{{ route('datainduk.index', 'standar-mutu') }}">Dokumen Standar Mutu</a>
      <a class="mi sub {{ request()->is('data-induk/universitas*') ? 'on' : '' }}" href="{{ route('datainduk.index', 'universitas') }}">Dokumen Universitas</a>
      <a class="mi sub {{ request()->is('data-induk/fakultas*') ? 'on' : '' }}" href="{{ route('datainduk.index', 'fakultas') }}">Dokumen Fakultas</a>
      @endif
      @if(Route::has('pengguna.index') && auth()->check() && \App\Http\Middleware\HanyaAdmin::adalahAdmin(auth()->user()))
      <div class="mi grp"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/></svg>Administrasi</div>
      <a class="mi sub {{ request()->routeIs('pengguna.*') ? 'on' : '' }}" href="{{ route('pengguna.index') }}">Kelola Pengguna</a>
      @endif
    </div>
    <div class="sfoot">Berbasis standar LAM Infokom</div>
  </aside>
  <div class="mn">
    <header class="hd2"><div class="t1">Sistem Informasi Akreditasi Program Studi Teknologi Informasi</div><div class="t2">Sekolah Vokasi Universitas Tiga Serangkai</div></header>
    <div class="top">
      <span class="crumb">Akreditasi / <b>@yield('title')</b></span>
      <span class="sp"></span>
      @auth
        @if(Route::has('akun.edit'))<a class="chip text-decoration-none" href="{{ route('akun.edit') }}" title="Akun saya">{{ auth()->user()->name }}</a>@else<span class="chip">{{ auth()->user()->name }}</span>@endif
        <form action="{{ route('logout') }}" method="post" class="d-inline">@csrf<button class="btn btn-sm btn-outline-secondary">Keluar</button></form>
      @else
        <a class="btn btn-sm btn-primary" href="{{ route('login') }}">Masuk</a>
      @endauth
    </div>
    <main class="content">
      @if(session('ok'))<div class="alert alert-success">{{ session('ok') }}</div>@endif
      @if($errors->any())<div class="alert alert-danger"><ul class="mb-0">@foreach($errors->all() as $e)<li>{{ $e }}</li>@endforeach</ul></div>@endif
      @yield('content')
    </main>
  </div>
</div>
</body>
</html>
EOF

cat > resources/views/dashboard.blade.php <<'EOF'
@extends('layout')
@section('title', 'Dashboard')
@section('content')
@php $overall = (int) round(($total['isian'] + $total['narasi'] + $total['dokumen']) / 3); @endphp
<div class="hero">
  <div><div class="hl">Kesiapan akreditasi (rata-rata)</div><div class="hx">{{ $overall }}%</div></div>
  <div class="hs">
    <div><b>{{ $total['isian'] }}%</b>Isian kriteria</div>
    <div><b>{{ $total['narasi'] }}%</b>Isian narasi</div>
    <div><b>{{ $total['dokumen'] }}%</b>Kelengkapan dokumen</div>
  </div>
</div>
<div class="sec">Capaian per kriteria</div>
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

# Elemen penilaian: tampil menyeluruh (tanpa dipotong) dengan font kecil
K=resources/views/kriteria/show.blade.php
I=resources/views/isi/show.blade.php
if [ -f "$K" ]; then cp "$K" "$K.bak"; perl -0pi -e 's{<td>\{\{ \\Illuminate\\Support\\Str::limit\(\$i->elemen_penilaian, \d+\) \}\}</td>}{<td class="elemen" style="min-width:260px">{!! nl2br(e(\$i->elemen_penilaian)) !!}</td>}' "$K"; fi
if [ -f "$I" ]; then cp "$I" "$I.bak"; perl -0pi -e 's{<h6>Elemen penilaian</h6><p>\{\{ \$isi->elemen_penilaian \}\}</p>}{<h6>Elemen penilaian</h6><p class="elemen">{!! nl2br(e(\$isi->elemen_penilaian)) !!}</p>}' "$I"; fi
grep -q 'class="elemen"' "$K" && echo "OK: elemen penilaian pada $K sudah diubah" || echo "PERINGATAN: $K tidak cocok dengan pola; ubah manual baris elemen_penilaian."

php artisan view:clear >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------
# 3. DATA INDUK
# ---------------------------------------------------------------------
bagian_data_induk() {
mkdir -p app/Support app/Http/Controllers resources/views/datainduk

# ---------- PENYIMPANAN (JSON, tanpa DB) ----------
cat > app/Support/DataInduk.php <<'EOF'
<?php
namespace App\Support;

class DataInduk {
    const KATEGORI = [
        'standar-mutu' => 'Dokumen Standar Mutu',
        'universitas'  => 'Dokumen Universitas',
        'fakultas'     => 'Dokumen Fakultas',
    ];

    public static function judul(string $k): string {
        return self::KATEGORI[$k] ?? abort(404);
    }
    private static function path(string $k): string {
        return storage_path('app/data-induk/' . $k . '.json');
    }
    public static function semua(string $k): array {
        $p = self::path($k);
        if (!is_file($p)) return [];
        $d = json_decode((string) file_get_contents($p), true);
        return is_array($d) ? $d : [];
    }
    public static function cari(string $k, string $id): ?array {
        foreach (self::semua($k) as $x) if (($x['id'] ?? null) === $id) return $x;
        return null;
    }
    // Baca-ubah-tulis dengan kunci berkas agar dua pengguna tidak saling menimpa
    public static function ubah(string $k, callable $fn): void {
        $p = self::path($k);
        if (!is_dir(dirname($p))) mkdir(dirname($p), 0775, true);
        $f = fopen($p, 'c+');
        flock($f, LOCK_EX);
        $d = json_decode((string) stream_get_contents($f), true);
        $d = $fn(is_array($d) ? $d : []);
        ftruncate($f, 0);
        rewind($f);
        fwrite($f, json_encode(array_values($d), JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
        fflush($f);
        flock($f, LOCK_UN);
        fclose($f);
    }

    // Format ukuran berkas tanpa ekstensi PHP intl (Number::fileSize Laravel membutuhkan intl)
    public static function ukuran($bytes): string {
        $b = (float) $bytes;
        $u = ['B', 'KB', 'MB', 'GB'];
        $i = 0;
        while ($b >= 1024 && $i < 3) { $b /= 1024; $i++; }
        return ($i === 0 ? (string) (int) $b : number_format($b, 1, ',', '.')) . ' ' . $u[$i];
    }
}
EOF

# ---------- CONTROLLER ----------
cat > app/Http/Controllers/DataIndukController.php <<'EOF'
<?php
namespace App\Http\Controllers;
use App\Support\DataInduk;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class DataIndukController extends Controller {
    private function rules(): array {
        return [
            'nama'       => 'required|max:255',
            'keterangan' => 'nullable|max:1000',
            'file'       => 'nullable|file|max:20480|mimes:pdf,doc,docx,xls,xlsx,ppt,pptx,zip,jpg,png',
            'link'       => 'nullable|url:http,https|max:500',
        ];
    }
    private function simpanFile(Request $r, string $kategori): ?array {
        if (!$r->hasFile('file')) return null;
        $f = $r->file('file');
        return [
            'file'      => $f->store('data-induk/' . $kategori, 'public'),
            'nama_file' => $f->getClientOriginalName(),
            'ukuran'    => $f->getSize(),
        ];
    }

    public function index(Request $r, string $kategori) {
        $judul = DataInduk::judul($kategori);
        $q = trim((string) $r->query('q', ''));
        $items = collect(DataInduk::semua($kategori))->sortByDesc('diubah')->values();
        if ($q !== '') {
            $items = $items->filter(fn ($d) => Str::contains(Str::lower($d['nama'] . ' ' . ($d['keterangan'] ?? '')), Str::lower($q)))->values();
        }
        return view('datainduk.index', compact('kategori', 'judul', 'items', 'q'));
    }

    public function create(string $kategori) {
        return view('datainduk.form', ['kategori' => $kategori, 'judul' => DataInduk::judul($kategori), 'dok' => null]);
    }

    public function store(Request $r, string $kategori) {
        DataInduk::judul($kategori);
        $data = $r->validate($this->rules());
        if (!$r->hasFile('file') && blank($data['link'] ?? null)) {
            return back()->withInput()->withErrors(['file' => 'Unggah berkas atau isi link dokumen.']);
        }
        $rec = [
            'id' => (string) Str::uuid(), 'nama' => $data['nama'], 'keterangan' => $data['keterangan'] ?? null,
            'file' => null, 'nama_file' => null, 'ukuran' => null, 'link' => $data['link'] ?? null,
            'dibuat' => now()->toDateTimeString(), 'diubah' => now()->toDateTimeString(),
        ];
        $rec = array_merge($rec, $this->simpanFile($r, $kategori) ?? []);
        DataInduk::ubah($kategori, function ($d) use ($rec) { $d[] = $rec; return $d; });
        return redirect()->route('datainduk.index', $kategori)->with('ok', 'Dokumen ditambahkan.');
    }

    public function edit(string $kategori, string $id) {
        $dok = DataInduk::cari($kategori, $id) ?? abort(404);
        return view('datainduk.form', ['kategori' => $kategori, 'judul' => DataInduk::judul($kategori), 'dok' => $dok]);
    }

    public function update(Request $r, string $kategori, string $id) {
        DataInduk::judul($kategori);
        $ada = DataInduk::cari($kategori, $id) ?? abort(404);
        $data = $r->validate($this->rules());
        if (!$r->hasFile('file') && empty($ada['file']) && blank($data['link'] ?? null)) {
            return back()->withInput()->withErrors(['file' => 'Dokumen harus berupa berkas atau link.']);
        }
        $baru = $this->simpanFile($r, $kategori);
        DataInduk::ubah($kategori, function ($d) use ($id, $data, $baru) {
            foreach ($d as &$x) {
                if (($x['id'] ?? null) === $id) {
                    $x['nama'] = $data['nama'];
                    $x['keterangan'] = $data['keterangan'] ?? null;
                    $x['link'] = $data['link'] ?? null;
                    $x['diubah'] = now()->toDateTimeString();
                    if ($baru) $x = array_merge($x, $baru);
                }
            }
            unset($x);
            return $d;
        });
        if ($baru && !empty($ada['file'])) Storage::disk('public')->delete($ada['file']);
        return redirect()->route('datainduk.index', $kategori)->with('ok', 'Dokumen diperbarui.');
    }

    public function destroy(string $kategori, string $id) {
        DataInduk::judul($kategori);
        $ada = DataInduk::cari($kategori, $id) ?? abort(404);
        DataInduk::ubah($kategori, fn ($d) => array_values(array_filter($d, fn ($x) => ($x['id'] ?? null) !== $id)));
        if (!empty($ada['file'])) Storage::disk('public')->delete($ada['file']);
        return redirect()->route('datainduk.index', $kategori)->with('ok', 'Dokumen dihapus.');
    }
}
EOF

# ---------- VIEWS ----------
cat > resources/views/datainduk/index.blade.php <<'EOF'
@extends('layout')
@section('title', $judul)
@section('content')
<div class="d-flex justify-content-between align-items-start flex-wrap gap-2 mb-3">
  <div><h1 class="mb-0">{{ $judul }}</h1><div class="text-muted small">Data Induk &middot; {{ $items->count() }} dokumen</div></div>
  @auth<a href="{{ route('datainduk.create', $kategori) }}" class="btn btn-primary">Tambah dokumen</a>@endauth
</div>
<form method="get" class="mb-3"><input type="search" name="q" value="{{ $q }}" class="form-control" style="max-width:380px" placeholder="Cari nama atau keterangan dokumen..."></form>
<div class="card"><div class="table-responsive"><table class="table align-middle mb-0">
  <thead><tr><th style="width:48px">No</th><th>Nama dokumen</th><th>Keterangan</th><th>Berkas / link</th><th>Diperbarui</th>@auth<th class="text-end">Aksi</th>@endauth</tr></thead>
  <tbody>
  @forelse($items as $i => $d)
    <tr>
      <td>{{ $i + 1 }}</td>
      <td class="fw-medium">{{ $d['nama'] }}</td>
      <td class="elemen" style="min-width:220px">{{ ($d['keterangan'] ?? '') ?: '-' }}</td>
      <td>
        @if(!empty($d['file']))<a href="{{ asset('storage/'.$d['file']) }}" download="{{ $d['nama_file'] }}">Unduh</a> <span class="text-muted small">({{ \App\Support\DataInduk::ukuran($d['ukuran'] ?? 0) }})</span>@endif
        @if(!empty($d['file']) && !empty($d['link']))<br>@endif
        @if(!empty($d['link']))<a href="{{ $d['link'] }}" target="_blank" rel="noopener">Buka link</a>@endif
      </td>
      <td class="small text-muted">{{ \Illuminate\Support\Carbon::parse($d['diubah'])->format('d/m/Y') }}</td>
      @auth
      <td class="text-end text-nowrap">
        <a href="{{ route('datainduk.edit', [$kategori, $d['id']]) }}" class="btn btn-sm btn-outline-secondary">Ubah</a>
        <form action="{{ route('datainduk.destroy', [$kategori, $d['id']]) }}" method="post" class="d-inline" onsubmit="return confirm('Hapus dokumen ini?')">@csrf @method('DELETE')<button class="btn btn-sm btn-outline-danger">Hapus</button></form>
      </td>
      @endauth
    </tr>
  @empty
    <tr><td colspan="6" class="text-center text-muted py-4">Belum ada dokumen.</td></tr>
  @endforelse
  </tbody>
</table></div></div>
@endsection
EOF

cat > resources/views/datainduk/form.blade.php <<'EOF'
@extends('layout')
@section('title', $dok ? 'Ubah Dokumen' : 'Tambah Dokumen')
@section('content')
<h1 class="mb-3">{{ $dok ? 'Ubah' : 'Tambah' }} dokumen &ndash; {{ $judul }}</h1>
<form method="post" enctype="multipart/form-data" class="card card-body" style="max-width:680px"
      action="{{ $dok ? route('datainduk.update', [$kategori, $dok['id']]) : route('datainduk.store', $kategori) }}">
  @csrf @if($dok) @method('PUT') @endif
  <div class="mb-3"><label class="form-label">Nama dokumen</label><input name="nama" class="form-control" value="{{ old('nama', $dok['nama'] ?? '') }}" required></div>
  <div class="mb-3"><label class="form-label">Keterangan</label><textarea name="keterangan" rows="3" class="form-control">{{ old('keterangan', $dok['keterangan'] ?? '') }}</textarea></div>
  <div class="mb-3"><label class="form-label">Berkas (PDF, Office, ZIP, gambar; maks. 20 MB)</label>
    <input type="file" name="file" class="form-control">
    @if(!empty($dok['file']))<div class="form-text">Berkas saat ini: <a href="{{ asset('storage/'.$dok['file']) }}" download="{{ $dok['nama_file'] }}">{{ $dok['nama_file'] }}</a>. Unggah berkas baru untuk menggantinya.</div>@endif</div>
  <div class="mb-3"><label class="form-label">Atau link dokumen</label><input type="url" name="link" class="form-control" placeholder="https://" value="{{ old('link', $dok['link'] ?? '') }}"></div>
  <div><button class="btn btn-primary">Simpan</button> <a href="{{ route('datainduk.index', $kategori) }}" class="btn btn-link">Batal</a></div>
</form>
@endsection
EOF

# ---------- ROUTE (ditambahkan sekali) ----------
if ! grep -q "datainduk.index" routes/web.php; then
cat >> routes/web.php <<'EOF'

// ===== Data Induk: baca publik, tambah/ubah/hapus wajib login =====
Route::redirect('/data-induk', '/data-induk/standar-mutu');
Route::prefix('data-induk')->where(['kategori' => 'standar-mutu|universitas|fakultas', 'id' => '[0-9a-fA-F-]{36}'])->group(function () {
    Route::middleware('auth')->group(function () {
        Route::get('{kategori}/create', [\App\Http\Controllers\DataIndukController::class, 'create'])->name('datainduk.create');
        Route::post('{kategori}', [\App\Http\Controllers\DataIndukController::class, 'store'])->name('datainduk.store');
        Route::get('{kategori}/{id}/edit', [\App\Http\Controllers\DataIndukController::class, 'edit'])->name('datainduk.edit');
        Route::put('{kategori}/{id}', [\App\Http\Controllers\DataIndukController::class, 'update'])->name('datainduk.update');
        Route::delete('{kategori}/{id}', [\App\Http\Controllers\DataIndukController::class, 'destroy'])->name('datainduk.destroy');
    });
    Route::get('{kategori}', [\App\Http\Controllers\DataIndukController::class, 'index'])->name('datainduk.index');
});
EOF
echo "Route Data Induk ditambahkan."
else echo "Route Data Induk sudah ada (dilewati)."; fi

# ---------- MENU SIDEBAR ----------
L=resources/views/layout.blade.php
if grep -q "datainduk.index" "$L"; then
  echo "Menu Data Induk sudah ada di layout (dilewati)."
elif grep -q 'class="sfoot"' "$L"; then
  cp "$L" "$L.bak2"
  M=$(mktemp)
  cat > "$M" <<'EOF'
      @if(Route::has('datainduk.index'))
      <div class="mi grp"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>Data Induk</div>
      <a class="mi sub {{ request()->is('data-induk/standar-mutu*') ? 'on' : '' }}" href="{{ route('datainduk.index', 'standar-mutu') }}">Dokumen Standar Mutu</a>
      <a class="mi sub {{ request()->is('data-induk/universitas*') ? 'on' : '' }}" href="{{ route('datainduk.index', 'universitas') }}">Dokumen Universitas</a>
      <a class="mi sub {{ request()->is('data-induk/fakultas*') ? 'on' : '' }}" href="{{ route('datainduk.index', 'fakultas') }}">Dokumen Fakultas</a>
      @endif
EOF
  M="$M" perl -0pi -e 'BEGIN{ local $/; open(F, "<", $ENV{M}) or die; $m = <F>; close F } s/\n    <\/div>\n    <div class="sfoot">/\n$m    <\/div>\n    <div class="sfoot">/' "$L"
  rm -f "$M"
  grep -q "datainduk.index" "$L" && echo "Menu Data Induk ditambahkan ke sidebar." || echo "PERINGATAN: pola layout tidak cocok; tambahkan menu secara manual."
else
  echo "PERINGATAN: layout tidak memakai sidebar (jalankan ui-profesional.sh dulu)."
fi

# ---------- CSS ----------
if [ -f public/css/tema.css ] && ! grep -q "data-induk" public/css/tema.css; then
cat >> public/css/tema.css <<'EOF'

/* data-induk */
.mi.grp{margin-top:12px;color:#fff;font-weight:600;cursor:default}.mi.grp:hover{background:none}
.mi.sub{padding:8px 12px 8px 40px;font-size:13.5px}
EOF
fi

php artisan storage:link >/dev/null 2>&1 || true
php artisan optimize:clear >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------
# 4. PENGGUNA
# ---------------------------------------------------------------------
bagian_pengguna() {
mkdir -p app/Http/Middleware app/Http/Controllers config resources/views/pengguna resources/views/akun

# ---------- 1. DOKUMEN FAKULTAS ----------
if [ -f app/Support/DataInduk.php ]; then
  if ! grep -q "'fakultas'" app/Support/DataInduk.php; then
    perl -0pi -e "s/(\s*'universitas'\s*=> 'Dokumen Universitas',\n)/\$1        'fakultas'     => 'Dokumen Fakultas',\n/" app/Support/DataInduk.php
    echo "Kategori Dokumen Fakultas ditambahkan."
  else echo "Kategori Dokumen Fakultas sudah ada (dilewati)."; fi
  if ! grep -q "|fakultas" routes/web.php; then
    sed -i "s#standar-mutu|universitas'#standar-mutu|universitas|fakultas'#" routes/web.php
  fi
else
  echo "PERINGATAN: app/Support/DataInduk.php tidak ada. Jalankan tambah-data-induk.sh dulu."
fi

# ---------- 2. PENGGUNA ----------
cat > config/akreditasi.php <<'EOF'
<?php
return [
    // Email admin tambahan (pisahkan dengan koma), diatur lewat ADMIN_EMAILS di .env.
    // Akun dengan id 1 selalu menjadi admin.
    'admin_emails' => env('ADMIN_EMAILS', ''),
];
EOF

cat > app/Http/Middleware/HanyaAdmin.php <<'EOF'
<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Http\Request;

class HanyaAdmin {
    public static function adalahAdmin($u): bool {
        if (!$u) return false;
        $emails = array_filter(array_map(
            fn ($e) => strtolower(trim($e)),
            explode(',', (string) config('akreditasi.admin_emails', ''))
        ));
        return (int) $u->id === 1 || in_array(strtolower((string) $u->email), $emails, true);
    }
    public function handle(Request $request, Closure $next) {
        abort_unless(self::adalahAdmin($request->user()), 403, 'Hanya admin yang dapat mengelola pengguna.');
        return $next($request);
    }
}
EOF

cat > app/Http/Controllers/PenggunaController.php <<'EOF'
<?php
namespace App\Http\Controllers;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;

class PenggunaController extends Controller {
    public function index(Request $r) {
        $q = trim((string) $r->query('q', ''));
        $users = User::query()
            ->when($q !== '', fn ($x) => $x->where(fn ($w) => $w->where('name', 'like', "%$q%")->orWhere('email', 'like', "%$q%")))
            ->orderBy('name')->get();
        return view('pengguna.index', compact('users', 'q'));
    }
    public function create() { return view('pengguna.form', ['u' => new User]); }

    public function store(Request $r) {
        $d = $r->validate([
            'name'     => 'required|max:255',
            'email'    => 'required|email|max:255|unique:users,email',
            'password' => 'required|min:8|confirmed',
        ]);
        User::create(['name' => $d['name'], 'email' => $d['email'], 'password' => Hash::make($d['password'])]);
        return redirect()->route('pengguna.index')->with('ok', 'Pengguna ditambahkan.');
    }

    public function edit(User $pengguna) { return view('pengguna.form', ['u' => $pengguna]); }

    public function update(Request $r, User $pengguna) {
        $d = $r->validate([
            'name'     => 'required|max:255',
            'email'    => ['required', 'email', 'max:255', Rule::unique('users', 'email')->ignore($pengguna->id)],
            'password' => 'nullable|min:8|confirmed',
        ]);
        $pengguna->name = $d['name'];
        $pengguna->email = $d['email'];
        if (!empty($d['password'])) $pengguna->password = Hash::make($d['password']);
        $pengguna->save();
        return redirect()->route('pengguna.index')->with('ok', 'Pengguna diperbarui.');
    }

    public function destroy(User $pengguna) {
        if ($pengguna->id == auth()->id()) {
            return back()->withErrors(['hapus' => 'Anda tidak dapat menghapus akun Anda sendiri.']);
        }
        if ($pengguna->id == 1) {
            return back()->withErrors(['hapus' => 'Akun admin utama tidak dapat dihapus.']);
        }
        $pengguna->delete();
        return redirect()->route('pengguna.index')->with('ok', 'Pengguna dihapus.');
    }
}
EOF

cat > app/Http/Controllers/AkunController.php <<'EOF'
<?php
namespace App\Http\Controllers;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;

class AkunController extends Controller {
    public function edit(Request $r) { return view('akun.edit', ['u' => $r->user()]); }

    public function update(Request $r) {
        $u = $r->user();
        $d = $r->validate([
            'name'           => 'required|max:255',
            'email'          => ['required', 'email', 'max:255', Rule::unique('users', 'email')->ignore($u->id)],
            'password_lama'  => 'nullable|required_with:password|current_password',
            'password'       => 'nullable|min:8|confirmed',
        ], ['password_lama.current_password' => 'Kata sandi lama tidak sesuai.']);
        $u->name = $d['name'];
        $u->email = $d['email'];
        if (!empty($d['password'])) $u->password = Hash::make($d['password']);
        $u->save();
        return redirect()->route('akun.edit')->with('ok', 'Akun diperbarui.');
    }
}
EOF

cat > resources/views/pengguna/index.blade.php <<'EOF'
@extends('layout')
@section('title', 'Kelola Pengguna')
@section('content')
<div class="d-flex justify-content-between align-items-start flex-wrap gap-2 mb-3">
  <div><h1 class="mb-0">Kelola Pengguna</h1><div class="text-muted small">Administrasi &middot; {{ $users->count() }} akun</div></div>
  <a href="{{ route('pengguna.create') }}" class="btn btn-primary">Tambah pengguna</a>
</div>
<form method="get" class="mb-3"><input type="search" name="q" value="{{ $q }}" class="form-control" style="max-width:380px" placeholder="Cari nama atau email..."></form>
<div class="card"><div class="table-responsive"><table class="table align-middle mb-0">
  <thead><tr><th>Nama</th><th>Email</th><th>Peran</th><th>Dibuat</th><th class="text-end">Aksi</th></tr></thead>
  <tbody>
  @forelse($users as $u)
    <tr>
      <td class="fw-medium">{{ $u->name }} @if($u->id == auth()->id())<span class="badge text-bg-light border">Anda</span>@endif</td>
      <td>{{ $u->email }}</td>
      <td>@if(\App\Http\Middleware\HanyaAdmin::adalahAdmin($u))<span class="badge text-bg-primary">Admin</span>@else<span class="badge text-bg-secondary">Pengguna</span>@endif</td>
      <td class="small text-muted">{{ optional($u->created_at)->format('d/m/Y') }}</td>
      <td class="text-end text-nowrap">
        <a href="{{ route('pengguna.edit', $u) }}" class="btn btn-sm btn-outline-secondary">Ubah</a>
        @if($u->id != auth()->id() && $u->id != 1)
        <form action="{{ route('pengguna.destroy', $u) }}" method="post" class="d-inline" onsubmit="return confirm('Hapus pengguna ini?')">@csrf @method('DELETE')<button class="btn btn-sm btn-outline-danger">Hapus</button></form>
        @endif
      </td>
    </tr>
  @empty
    <tr><td colspan="5" class="text-center text-muted py-4">Tidak ada pengguna.</td></tr>
  @endforelse
  </tbody>
</table></div></div>
<p class="text-muted small mt-2">Admin = akun utama (id 1) dan email yang terdaftar pada ADMIN_EMAILS di berkas .env. Hanya admin yang melihat menu ini.</p>
@endsection
EOF

cat > resources/views/pengguna/form.blade.php <<'EOF'
@extends('layout')
@section('title', $u->exists ? 'Ubah Pengguna' : 'Tambah Pengguna')
@section('content')
<h1 class="mb-3">{{ $u->exists ? 'Ubah' : 'Tambah' }} pengguna</h1>
<form method="post" class="card card-body" style="max-width:560px" autocomplete="off"
      action="{{ $u->exists ? route('pengguna.update', $u) : route('pengguna.store') }}">
  @csrf @if($u->exists) @method('PUT') @endif
  <div class="mb-3"><label class="form-label">Nama</label><input name="name" class="form-control" value="{{ old('name', $u->name) }}" required></div>
  <div class="mb-3"><label class="form-label">Email</label><input type="email" name="email" class="form-control" value="{{ old('email', $u->email) }}" required></div>
  <div class="mb-3"><label class="form-label">Kata sandi{{ $u->exists ? ' baru' : '' }}</label><input type="password" name="password" class="form-control" minlength="8" autocomplete="new-password" {{ $u->exists ? '' : 'required' }}>
    @if($u->exists)<div class="form-text">Kosongkan jika tidak ingin mengganti kata sandi.</div>@else<div class="form-text">Minimal 8 karakter.</div>@endif</div>
  <div class="mb-3"><label class="form-label">Ulangi kata sandi</label><input type="password" name="password_confirmation" class="form-control" autocomplete="new-password"></div>
  <div><button class="btn btn-primary">Simpan</button> <a href="{{ route('pengguna.index') }}" class="btn btn-link">Batal</a></div>
</form>
@endsection
EOF

cat > resources/views/akun/edit.blade.php <<'EOF'
@extends('layout')
@section('title', 'Akun Saya')
@section('content')
<h1 class="mb-3">Akun saya</h1>
<form method="post" action="{{ route('akun.update') }}" class="card card-body" style="max-width:560px" autocomplete="off">
  @csrf @method('PUT')
  <div class="mb-3"><label class="form-label">Nama</label><input name="name" class="form-control" value="{{ old('name', $u->name) }}" required></div>
  <div class="mb-3"><label class="form-label">Email</label><input type="email" name="email" class="form-control" value="{{ old('email', $u->email) }}" required></div>
  <hr>
  <p class="text-muted small mb-2">Ganti kata sandi (kosongkan jika tidak ingin mengganti).</p>
  <div class="mb-3"><label class="form-label">Kata sandi lama</label><input type="password" name="password_lama" class="form-control" autocomplete="current-password"></div>
  <div class="mb-3"><label class="form-label">Kata sandi baru</label><input type="password" name="password" class="form-control" minlength="8" autocomplete="new-password"></div>
  <div class="mb-3"><label class="form-label">Ulangi kata sandi baru</label><input type="password" name="password_confirmation" class="form-control" autocomplete="new-password"></div>
  <div><button class="btn btn-primary">Simpan</button> <a href="{{ route('dashboard') }}" class="btn btn-link">Batal</a></div>
</form>
@endsection
EOF

# ---------- ROUTE ----------
if ! grep -q "pengguna.index\|'pengguna'" routes/web.php; then
cat >> routes/web.php <<'EOF'

// ===== Akun saya (semua pengguna login) & Kelola Pengguna (khusus admin) =====
Route::middleware('auth')->group(function () {
    Route::get('/akun', [\App\Http\Controllers\AkunController::class, 'edit'])->name('akun.edit');
    Route::put('/akun', [\App\Http\Controllers\AkunController::class, 'update'])->name('akun.update');
});
Route::middleware(['auth', \App\Http\Middleware\HanyaAdmin::class])
    ->resource('pengguna', \App\Http\Controllers\PenggunaController::class)
    ->except('show')->parameters(['pengguna' => 'pengguna']);
EOF
echo "Route pengguna ditambahkan."
else echo "Route pengguna sudah ada (dilewati)."; fi

# ---------- MENU SIDEBAR & TOPBAR ----------
L=resources/views/layout.blade.php
if [ ! -f "$L" ] || ! grep -q 'class="sfoot"' "$L"; then
  echo "PERINGATAN: layout sidebar tidak ditemukan (jalankan ui-profesional.sh dulu). Menu belum dipasang."
else
  cp "$L" "$L.bak3"
  if ! grep -q "data-induk/fakultas" "$L"; then
    F=$(cat <<'EOF'
      <a class="mi sub {{ request()->is('data-induk/fakultas*') ? 'on' : '' }}" href="{{ route('datainduk.index', 'fakultas') }}">Dokumen Fakultas</a>
EOF
)
    export F
    perl -0pi -e 's/(^[ \t]*<a class="mi sub [^\n]*Dokumen Universitas<\/a>\n)/$1$ENV{F}\n/m' "$L"
  fi
  if ! grep -q "pengguna.index" "$L"; then
    M=$(mktemp)
    cat > "$M" <<'EOF'
      @if(Route::has('pengguna.index') && auth()->check() && \App\Http\Middleware\HanyaAdmin::adalahAdmin(auth()->user()))
      <div class="mi grp"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/></svg>Administrasi</div>
      <a class="mi sub {{ request()->routeIs('pengguna.*') ? 'on' : '' }}" href="{{ route('pengguna.index') }}">Kelola Pengguna</a>
      @endif
EOF
    M="$M" perl -0pi -e 'BEGIN{ local $/; open(F, "<", $ENV{M}) or die; $m = <F>; close F } s/\n    <\/div>\n    <div class="sfoot">/\n$m    <\/div>\n    <div class="sfoot">/' "$L"
    rm -f "$M"
  fi
  if ! grep -q "akun.edit" "$L"; then
    perl -0pi -e 's|<span class="chip">\{\{ auth\(\)->user\(\)->name \}\}</span>|<a class="chip text-decoration-none" href="{{ route(\x27akun.edit\x27) }}" title="Akun saya">{{ auth()->user()->name }}</a>|' "$L"
  fi
  grep -q "data-induk/fakultas" "$L" && echo "Menu Dokumen Fakultas: OK" || echo "PERINGATAN: menu Dokumen Fakultas belum terpasang (pola layout berbeda)."
  grep -q "pengguna.index" "$L" && echo "Menu Kelola Pengguna: OK" || echo "PERINGATAN: menu Kelola Pengguna belum terpasang."
  grep -q "akun.edit" "$L" && echo "Tautan Akun Saya: OK" || echo "PERINGATAN: tautan Akun Saya belum terpasang."
fi

php artisan optimize:clear >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------
# 5. ARSIP DOKUMEN
# ---------------------------------------------------------------------
bagian_arsip() {
F=resources/views/dokumen/form.blade.php
if [ ! -f "$F" ]; then echo "Error: $F tidak ditemukan."; exit 1; fi
mkdir -p app/Support app/Http/Controllers

cat > app/Support/SumberDokumen.php <<'EOF'
<?php
namespace App\Support;
use App\Models\Dokumen;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class SumberDokumen {
    // Daftar dokumen yang bisa dipakai ulang (tanpa dokumen milik butir yang sedang dibuka)
    public static function daftar(int $kecualiIsi = 0): array {
        $out = [];
        if (class_exists(DataInduk::class)) {
            foreach (DataInduk::KATEGORI as $k => $judul) {
                foreach (DataInduk::semua($k) as $d) {
                    if (empty($d['file']) && empty($d['link'])) continue;
                    $out[] = ['kunci' => "di:$k:" . $d['id'], 'grup' => 'Data Induk - ' . $judul,
                              'nama' => $d['nama'], 'jenis' => !empty($d['file']) ? 'Berkas' : 'Link'];
                }
            }
        }
        $rows = Dokumen::with('isi.kriteria')->where('isi_kriteria_id', '!=', $kecualiIsi)->orderBy('nama')->get();
        foreach ($rows as $x) {
            if (!$x->isi || !$x->isi->kriteria) continue;
            $out[] = ['kunci' => 'dk:' . $x->id, 'grup' => 'Kriteria ' . $x->isi->kriteria->kode . ' - Butir ' . $x->isi->butir,
                      'nama' => $x->nama, 'jenis' => $x->file_path ? 'Berkas' : 'Link'];
        }
        return $out;
    }

    // Ambil data sumber dari kunci "di:<kategori>:<id>" atau "dk:<id dokumen>"
    public static function ambil(string $kunci): ?array {
        if (str_starts_with($kunci, 'di:') && class_exists(DataInduk::class)) {
            $p = explode(':', $kunci, 3);
            if (count($p) !== 3 || !isset(DataInduk::KATEGORI[$p[1]])) return null;
            $d = DataInduk::cari($p[1], $p[2]);
            return $d ? ['nama' => $d['nama'], 'file' => $d['file'] ?? null, 'link' => $d['link'] ?? null] : null;
        }
        if (str_starts_with($kunci, 'dk:')) {
            $x = Dokumen::find((int) substr($kunci, 3));
            return $x ? ['nama' => $x->nama, 'file' => $x->file_path, 'link' => $x->link] : null;
        }
        return null;
    }

    // Salin berkas fisik ke nama baru
    public static function salinFile(?string $path): ?string {
        if (!$path) return null;
        $disk = Storage::disk('public');
        if (!$disk->exists($path)) return null;
        $ext = pathinfo($path, PATHINFO_EXTENSION);
        $baru = 'dokumen-akreditasi/' . Str::uuid() . ($ext ? '.' . $ext : '');
        $disk->copy($path, $baru);
        return $baru;
    }
}
EOF

cat > app/Http/Controllers/DokumenArsipController.php <<'EOF'
<?php
namespace App\Http\Controllers;
use App\Models\Dokumen;
use App\Support\SumberDokumen;
use Illuminate\Http\Request;

class DokumenArsipController extends Controller {
    public function store(Request $r) {
        $d = $r->validate([
            'isi_kriteria_id' => 'required|exists:isi_kriteria,id',
            'rujukan'         => 'required|string|max:200',
            'nama'            => 'required|max:255',
        ], ['rujukan.required' => 'Pilih salah satu dokumen yang sudah ada.']);

        $s = SumberDokumen::ambil($d['rujukan']);
        if (!$s) return back()->withInput()->withErrors(['rujukan' => 'Dokumen sumber tidak ditemukan atau sudah dihapus.']);

        $file = null;
        if (!empty($s['file'])) {
            $file = SumberDokumen::salinFile($s['file']);
            if (!$file && blank($s['link'] ?? null)) {
                return back()->withInput()->withErrors(['rujukan' => 'Berkas sumber tidak ditemukan di penyimpanan.']);
            }
        }
        Dokumen::create([
            'isi_kriteria_id' => $d['isi_kriteria_id'],
            'nama'            => $d['nama'],
            'file_path'       => $file,
            'link'            => $s['link'] ?? null,
        ]);
        return redirect()->route('isi.show', $d['isi_kriteria_id'])->with('ok', 'Dokumen ditambahkan dari dokumen yang sudah ada.');
    }
}
EOF

if ! grep -q "dokumen.arsip" routes/web.php; then
cat >> routes/web.php <<'EOF'

// ===== Gunakan dokumen yang sudah pernah diunggah (wajib login) =====
Route::post('/dokumen-dari-arsip', [\App\Http\Controllers\DokumenArsipController::class, 'store'])
    ->middleware('auth')->name('dokumen.arsip');
EOF
echo "Route ditambahkan."
else echo "Route sudah ada (dilewati)."; fi

if grep -q "dokumen.arsip" "$F"; then
  echo "Form dokumen sudah memuat fasilitas ini (dilewati)."
else
  cp "$F" "$F.bak"
  M=$(mktemp)
  cat > "$M" <<'EOF'
@unless($dokumen->exists)
@php $grupArsip = collect(\App\Support\SumberDokumen::daftar($isi->id))->groupBy('grup'); @endphp
<div class="card card-body mt-4" id="arsip" style="max-width:680px">
  <h2 class="h6 mb-1">Atau gunakan dokumen yang sudah pernah diunggah</h2>
  <p class="text-muted small">Pilih dari Data Induk atau dokumen pada kriteria lain. Berkas akan disalin, sehingga dokumen ini berdiri sendiri (menghapus salah satunya tidak memengaruhi yang lain).</p>
  <form method="post" action="{{ route('dokumen.arsip') }}">
    @csrf
    <input type="hidden" name="isi_kriteria_id" value="{{ $isi->id }}">
    <input type="search" id="cari-arsip" class="form-control mb-2" placeholder="Cari nama dokumen...">
    <div class="border rounded" style="max-height:280px;overflow:auto" id="daftar-arsip">
      @forelse($grupArsip as $judulGrup => $items)
        <div class="px-3 py-1 bg-light small fw-semibold text-muted grup-arsip">{{ $judulGrup }}</div>
        @foreach($items as $it)
          <label class="d-flex gap-2 align-items-center px-3 py-2 border-top item-arsip" style="cursor:pointer;margin:0">
            <input type="radio" name="rujukan" value="{{ $it['kunci'] }}" data-nama="{{ $it['nama'] }}" @checked(old('rujukan') === $it['kunci'])>
            <span class="flex-grow-1">{{ $it['nama'] }}</span>
            <span class="badge text-bg-light border">{{ $it['jenis'] }}</span>
          </label>
        @endforeach
      @empty
        <div class="p-3 text-muted small">Belum ada dokumen yang dapat dipilih.</div>
      @endforelse
    </div>
    <div class="mt-3"><label class="form-label">Nama dokumen pada butir ini</label>
      <input name="nama" id="nama-arsip" class="form-control" value="{{ old('nama') }}" required></div>
    <div class="mt-3"><button class="btn btn-primary">Gunakan dokumen ini</button></div>
  </form>
  <script>
    (function () {
      var q = document.getElementById('cari-arsip'), nm = document.getElementById('nama-arsip'), auto = '';
      q.addEventListener('input', function () {
        var t = q.value.toLowerCase();
        document.querySelectorAll('#daftar-arsip .item-arsip').forEach(function (el) {
          el.style.display = el.textContent.toLowerCase().indexOf(t) > -1 ? '' : 'none';
        });
        document.querySelectorAll('#daftar-arsip .grup-arsip').forEach(function (g) {
          var n = g.nextElementSibling, ada = false;
          while (n && n.classList.contains('item-arsip')) { if (n.style.display !== 'none') ada = true; n = n.nextElementSibling; }
          g.style.display = ada ? '' : 'none';
        });
      });
      document.querySelectorAll('#daftar-arsip input[type=radio]').forEach(function (r) {
        r.addEventListener('change', function () {
          if (nm.value === '' || nm.value === auto) { nm.value = r.dataset.nama; auto = r.dataset.nama; }
        });
      });
    })();
  </script>
</div>
@endunless
EOF
  M="$M" perl -0pi -e 'BEGIN{ local $/; open(F, "<", $ENV{M}) or die; $m = <F>; close F } s/\n\@endsection\s*\z/\n$m\@endsection\n/' "$F"
  rm -f "$M"
  grep -q "dokumen.arsip" "$F" && echo "Form Tambah Dokumen diperbarui." || echo "PERINGATAN: form tidak cocok pola; tempel blok secara manual."
fi

php -l app/Support/SumberDokumen.php
php -l app/Http/Controllers/DokumenArsipController.php
php artisan optimize:clear >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------
# 6. LIHAT/PRATINJAU DOKUMEN, HAPUS "DIPERBARUI", KATEGORI "DOKUMEN TAMBAHAN"
# ---------------------------------------------------------------------
bagian_lihat() {
D=app/Support/DataInduk.php
R=routes/web.php
L=resources/views/layout.blade.php
IDX=resources/views/datainduk/index.blade.php
FRM=resources/views/datainduk/form.blade.php
ISI=resources/views/isi/show.blade.php
DOK=resources/views/dokumen/form.blade.php
if [ ! -f "$D" ] || [ ! -f "$R" ]; then echo "Error: menu Data Induk belum terpasang (jalankan akreditasi-installer.sh atau tambah-data-induk.sh dulu)."; exit 1; fi
mkdir -p app/Http/Controllers resources/views

# ---------- A. Kategori baru: Dokumen Tambahan ----------
echo "[A] Kategori Dokumen Tambahan"
if grep -q "'stmik-sinus'" "$D"; then
  echo "  (sudah ada, dilewati)"
else
  cp "$D" "$D.bak5"
  perl -0pi -e "s/(\n[ \t]*'fakultas'[ \t]*=>[ \t]*'Dokumen Fakultas',)/\$1\n        'stmik-sinus'  => 'Dokumen Tambahan',/" "$D"
  grep -q "'stmik-sinus'" "$D" && echo "  OK  $D" || echo "  PERINGATAN: kategori fakultas tidak ditemukan di $D; tambahkan baris 'stmik-sinus' => 'Dokumen Tambahan' manual."
fi
# pola rute kategori dibuat dinamis, mengikuti daftar kategori di DataInduk
if grep -qF 'DataInduk::KATEGORI))' "$R"; then
  echo "  (rute sudah dinamis, dilewati)"
else
  cp "$R" "$R.bak5"
  perl -0pi -e 's/\x27kategori\x27\s*=>\s*\x27standar-mutu[^\x27]*\x27/\x27kategori\x27 => implode(\x27|\x27, array_keys(\\App\\Support\\DataInduk::KATEGORI))/' "$R"
  grep -qF 'DataInduk::KATEGORI))' "$R" && echo "  OK  pola rute kategori diperbarui" || echo "  PERINGATAN: pola rute kategori di $R tidak ditemukan; ubah manual."
fi
# menu sidebar
if [ -f "$L" ]; then
  if grep -q "data-induk/stmik-sinus" "$L"; then
    echo "  (menu sudah ada, dilewati)"
  else
    cp "$L" "$L.bak5"
    S=$(cat <<'EOF'
      <a class="mi sub {{ request()->is('data-induk/stmik-sinus*') ? 'on' : '' }}" href="{{ route('datainduk.index', 'stmik-sinus') }}">Dokumen Tambahan</a>
EOF
)
    export S
    perl -0pi -e 's/(^[ \t]*<a class="mi sub [^\n]*Dokumen Fakultas<\/a>\n)/$1$ENV{S}\n/m' "$L"
    grep -q "data-induk/stmik-sinus" "$L" && echo "  OK  menu sidebar" || echo "  PERINGATAN: menu tidak terpasang (pola layout berbeda); tambahkan tautan manual."
  fi
fi

# ---------- B. Hapus kolom "Diperbarui" ----------
echo "[B] Hapus informasi tanggal Diperbarui"
if [ -f "$IDX" ] && grep -q "Diperbarui" "$IDX"; then
  cp "$IDX" "$IDX.bak5"
  perl -ni -e 'print unless /Carbon::parse\(\$d\[\x27diubah\x27\]\)/' "$IDX"
  perl -pi -e 's~<th>Diperbarui</th>~~g; s~colspan="6"~colspan="5"~g' "$IDX"
  grep -q "Diperbarui" "$IDX" && echo "  PERINGATAN: masih ada teks Diperbarui di $IDX" || echo "  OK  $IDX"
else
  echo "  (sudah bersih atau berkas tidak ada, dilewati)"
fi

# ---------- C. Link Unduh -> Lihat ----------
echo "[C] Link Unduh menjadi Lihat (pratinjau)"
if [ -f "$IDX" ] && grep -q 'download="{{ $d\[' "$IDX"; then
  perl -pi -e 's~<a href="\{\{ asset\(\x27storage/\x27\.\$d\[\x27file\x27\]\) \}\}" download="\{\{ \$d\[\x27nama_file\x27\] \}\}">Unduh</a>~<a href="{{ route(\x27lihat.datainduk\x27, [\$kategori, \$d[\x27id\x27]]) }}" target="_blank" rel="noopener">Lihat</a>~g' "$IDX"
  echo "  OK  $IDX"
fi
if [ -f "$FRM" ] && grep -q 'download="{{ $dok\[' "$FRM"; then
  cp "$FRM" "$FRM.bak5"
  perl -pi -e 's~<a href="\{\{ asset\(\x27storage/\x27\.\$dok\[\x27file\x27\]\) \}\}" download="\{\{ \$dok\[\x27nama_file\x27\] \}\}">~<a href="{{ route(\x27lihat.datainduk\x27, [\$kategori, \$dok[\x27id\x27]]) }}" target="_blank" rel="noopener">~g' "$FRM"
  echo "  OK  $FRM"
fi
if [ -f "$ISI" ] && grep -q 'Unduh berkas' "$ISI"; then
  cp "$ISI" "$ISI.bak5"
  perl -pi -e 's~<a href="\{\{ asset\(\x27storage/\x27\.\$d->file_path\) \}\}" target="_blank">Unduh berkas</a>~<a href="{{ route(\x27lihat.dokumen\x27, \$d) }}" target="_blank" rel="noopener">Lihat</a>~g' "$ISI"
  echo "  OK  $ISI"
fi
if [ -f "$DOK" ] && grep -q '>unduh</a>' "$DOK"; then
  cp "$DOK" "$DOK.bak5"
  perl -pi -e 's~<a href="\{\{ asset\(\x27storage/\x27\.\$dokumen->file_path\) \}\}" target="_blank">unduh</a>~<a href="{{ route(\x27lihat.dokumen\x27, \$dokumen) }}" target="_blank" rel="noopener">lihat</a>~g' "$DOK"
  echo "  OK  $DOK"
fi

# ---------- E. Situs lama: ganti label "Dokumen STMIK SiNus" menjadi "Dokumen Tambahan" ----------
echo "[E] Label kategori: Dokumen Tambahan"
for f in "$D" "$L"; do
  if [ -f "$f" ] && grep -q "Dokumen STMIK SiNus" "$f"; then
    cp "$f" "$f.bak6"
    sed -i 's/Dokumen STMIK SiNus/Dokumen Tambahan/g' "$f"
    echo "  OK  $f"
  fi
done

# ---------- D. Halaman Lihat (pratinjau) ----------
echo "[D] Halaman pratinjau dokumen"
cat > app/Http/Controllers/LihatController.php <<'EOF'
<?php
namespace App\Http\Controllers;
use App\Models\Dokumen;
use App\Support\DataInduk;
use Illuminate\Support\Facades\Storage;

class LihatController extends Controller {
    private const GAMBAR = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
    private const OFFICE = ['doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'];

    public function dataInduk(string $kategori, string $id) {
        $judulKat = DataInduk::judul($kategori);
        $d = DataInduk::cari($kategori, $id) ?? abort(404);
        return $this->tampil($d['nama'], 'Data Induk - ' . $judulKat, $d['file'] ?? null, $d['link'] ?? null, route('datainduk.index', $kategori));
    }

    public function dokumen(int $id) {
        $x = Dokumen::with('isi.kriteria')->findOrFail($id);
        $sub = ($x->isi && $x->isi->kriteria) ? 'Kriteria ' . $x->isi->kriteria->kode . ' - Butir ' . $x->isi->butir : '';
        $kembali = $x->isi ? route('isi.show', $x->isi) : route('dashboard');
        return $this->tampil($x->nama, $sub, $x->file_path, $x->link, $kembali);
    }

    private function tampil(string $judul, string $sub, ?string $file, ?string $link, string $kembali) {
        if (!$file) return $link ? redirect()->away($link) : abort(404);
        abort_unless(Storage::disk('public')->exists($file), 404, 'Berkas tidak ditemukan di penyimpanan.');
        $ext = strtolower(pathinfo($file, PATHINFO_EXTENSION));
        $tipe = $ext === 'pdf' ? 'pdf'
            : (in_array($ext, self::GAMBAR, true) ? 'gambar'
            : (in_array($ext, self::OFFICE, true) ? 'office' : 'lain'));
        $url = asset('storage/' . $file);
        $officeUrl = null;
        if ($tipe === 'office' && $this->publik(url('storage/' . $file))) {
            $officeUrl = 'https://view.officeapps.live.com/op/embed.aspx?src=' . rawurlencode(url('storage/' . $file));
        }
        return view('lihat', compact('judul', 'sub', 'url', 'ext', 'tipe', 'officeUrl', 'kembali'));
    }

    // Pratinjau Office memakai layanan Microsoft: hanya berfungsi bila situs dapat dijangkau publik lewat HTTPS
    private function publik(string $url): bool {
        $p = parse_url($url);
        if (($p['scheme'] ?? '') !== 'https') return false;
        $h = strtolower($p['host'] ?? '');
        if ($h === '' || $h === 'localhost') return false;
        if (preg_match('/\.(test|local|lan|localhost|internal)$/', $h)) return false;
        if (filter_var($h, FILTER_VALIDATE_IP) && !filter_var($h, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE)) return false;
        return true;
    }
}
EOF

cat > resources/views/lihat.blade.php <<'EOF'
@extends('layout')
@section('title', 'Lihat Dokumen')
@section('content')
<div class="d-flex justify-content-between align-items-start flex-wrap gap-2 mb-3">
  <div><h1 class="mb-0 h4">{{ $judul }}</h1>@if($sub)<div class="text-muted small">{{ $sub }}</div>@endif</div>
  <a href="{{ $kembali }}" class="btn btn-outline-secondary btn-sm">&larr; Kembali</a>
</div>
<div class="card">
  @if($tipe === 'pdf')
    <iframe src="{{ $url }}" title="{{ $judul }}" style="width:100%;height:80vh;border:0"></iframe>
  @elseif($tipe === 'gambar')
    <div class="p-3 text-center"><img src="{{ $url }}" alt="{{ $judul }}" style="max-width:100%;height:auto"></div>
  @elseif($tipe === 'office' && $officeUrl)
    <iframe src="{{ $officeUrl }}" title="{{ $judul }}" style="width:100%;height:80vh;border:0"></iframe>
  @else
    <div class="p-4 text-center">
      @if($tipe === 'office')
        <p class="mb-1 fw-medium">Dokumen Office tidak dapat dipratinjau di server ini.</p>
        <p class="text-muted small">Pratinjau Office memerlukan situs yang dapat diakses publik lewat HTTPS.</p>
      @else
        <p class="mb-1 fw-medium">Format .{{ $ext }} tidak dapat dipratinjau di browser.</p>
      @endif
      <a class="btn btn-primary" href="{{ $url }}" download>Unduh berkas</a>
    </div>
  @endif
</div>
@endsection
EOF

if ! grep -q "lihat.datainduk" "$R"; then
cat >> "$R" <<'EOF'

// ===== Lihat / pratinjau dokumen (publik) =====
Route::get('/lihat/data-induk/{kategori}/{id}', [\App\Http\Controllers\LihatController::class, 'dataInduk'])
    ->where(['kategori' => implode('|', array_keys(\App\Support\DataInduk::KATEGORI)), 'id' => '[0-9a-fA-F-]{36}'])
    ->name('lihat.datainduk');
Route::get('/lihat/dokumen/{id}', [\App\Http\Controllers\LihatController::class, 'dokumen'])
    ->whereNumber('id')->name('lihat.dokumen');
EOF
echo "  OK  rute lihat ditambahkan"
else echo "  (rute lihat sudah ada)"; fi
php -l app/Http/Controllers/LihatController.php

php artisan optimize:clear >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------
# 7. DASHBOARD GRAFIK VEKTOR (SVG)
# ---------------------------------------------------------------------
bagian_dashboard() {
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
}

# ---------------------------------------------------------------------
# 8. HALAMAN ANALITIK (dashboard data analytic)
# ---------------------------------------------------------------------
bagian_analitik() {
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
}

# ---------------------------------------------------------------------
# 9. PANEL ADMIN (dashboard visualisasi gaya admin)
# ---------------------------------------------------------------------
bagian_panel() {
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
}

# ---------------------------------------------------------------------
# 10. PEMILIH TAMPILAN DASHBOARD (ganti-ganti dashboard)
# ---------------------------------------------------------------------
bagian_tampilan() {
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
}

# ---------------------------------------------------------------------
# 11. PENGATURAN SERVER: izin folder + batas unggah 20 MB (PHP) + Apache
# ---------------------------------------------------------------------
bagian_server() {
  if [ "$LEWATI_SERVER" = 1 ]; then
    echo "  (dilewati: --lewati-server). Atur manual: upload_max_filesize=20M, post_max_size=25M, memory_limit=256M"
    return 0
  fi
  if [ "$WINDOWS" = 1 ]; then
    echo "  Windows terdeteksi. Ubah php.ini secara manual (lihat README, bagian Windows):"
    echo "      upload_max_filesize = 20M"
    echo "      post_max_size = 25M"
    echo "      memory_limit = 256M"
    echo "      max_execution_time = 120"
    echo "  php.ini yang dipakai CLI:"; php --ini 2>/dev/null | sed 's/^/      /' | head -3
    echo "  Lalu restart Apache (Laragon: Stop All, Start All)."
    return 0
  fi
  ETC="${PHP_ETC:-/etc/php}"
  SUDO="${SUDO_CMD-sudo}"

  # izin folder agar Apache (www-data) dapat menulis
  if getent group www-data >/dev/null 2>&1; then
    $SUDO chgrp -R www-data storage bootstrap/cache 2>/dev/null || true
    $SUDO chmod -R ug+rwX storage bootstrap/cache 2>/dev/null || true
    $SUDO find storage bootstrap/cache -type d -exec chmod 2775 {} \; 2>/dev/null || true
    echo "  OK  izin folder storage dan bootstrap/cache"
  fi

  # batas unggah PHP (berkas drop-in; php.ini asli tidak disentuh)
  INI=$(cat <<'EOF'
; Batas unggah Sistem Informasi Akreditasi (20 MB per berkas)
upload_max_filesize = 20M
post_max_size = 25M
memory_limit = 256M
max_file_uploads = 20
max_execution_time = 120
max_input_time = 120
EOF
)
  DITULIS=0
  for D in "$ETC"/*/apache2/conf.d "$ETC"/*/fpm/conf.d; do
    if [ -d "$D" ]; then
      printf '%s\n' "$INI" | $SUDO tee "$D/99-akreditasi-upload.ini" >/dev/null
      echo "  OK  $D/99-akreditasi-upload.ini"
      DITULIS=1
    fi
  done
  [ "$DITULIS" = 0 ] && echo "  PERINGATAN: folder conf.d PHP tidak ditemukan di $ETC. Ubah upload_max_filesize dan post_max_size manual di php.ini."

  # Apache
  if [ -d /etc/apache2 ] && grep -rIn "LimitRequestBody" /etc/apache2 2>/dev/null; then
    echo "  PERINGATAN: LimitRequestBody di atas membatasi unggahan. Hapus atau naikkan ke 26214400 (25 MB)."
  fi
  if [ -z "$SKIP_RESTART" ]; then
    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files apache2.service >/dev/null 2>&1; then
      $SUDO systemctl restart apache2 && echo "  OK  apache2 di-restart"
    fi
    for s in $(systemctl list-units --type=service --no-legend 'php*-fpm.service' 2>/dev/null | awk '{print $1}'); do
      $SUDO systemctl restart "$s" && echo "  OK  $s di-restart"
    done
  fi
}

# =====================================================================
#  PELAKSANAAN
# =====================================================================
echo "== [1/11] Dasar: kriteria, isi kriteria, dokumen, dashboard, login =="
bagian_dasar
echo "== [2/11] Tema antarmuka profesional =="
bagian_tema
echo "== [3/11] Data Induk (Standar Mutu, Universitas, Fakultas, Tambahan) =="
bagian_data_induk
echo "== [4/11] Kelola Pengguna dan Akun Saya =="
bagian_pengguna
echo "== [5/11] Gunakan dokumen yang sudah pernah diunggah =="
bagian_arsip
echo "== [6/11] Lihat/pratinjau dokumen, kategori Dokumen Tambahan =="
bagian_lihat
echo "== [7/11] Dashboard grafik vektor (SVG) =="
bagian_dashboard
echo "== [8/11] Halaman Analitik (dashboard data analytic) =="
bagian_analitik
echo "== [9/11] Panel Admin (dashboard visualisasi) =="
bagian_panel
echo "== [10/11] Pemilih tampilan dashboard =="
bagian_tampilan
echo "== [11/11] Pengaturan server dan batas unggah 20 MB =="
bagian_server

# catatan admin tambahan di .env
if [ -f .env ] && ! grep -q '^ADMIN_EMAILS=' .env; then
  printf '\n# Email admin tambahan (pisahkan koma). Akun id 1 selalu admin.\nADMIN_EMAILS=\n' >> .env
fi

if [ "$PRODUKSI" = 1 ] && [ -f .env ]; then
  sed -i 's/^APP_ENV=.*/APP_ENV=production/; s/^APP_DEBUG=.*/APP_DEBUG=false/' .env
  echo "  OK  .env: APP_ENV=production, APP_DEBUG=false"
fi

# instalasi baru: buang berkas cadangan (*.bak*) yang hanya berisi versi sementara; mode --paksa: dipertahankan
if [ "$PAKSA" != 1 ]; then
  find app resources routes config public/css -name '*.bak*' -type f -delete 2>/dev/null || true
fi

php artisan optimize:clear >/dev/null 2>&1 || true

echo "== Penautan storage (agar berkas unggahan dapat diunduh) =="
if ! php artisan storage:link >/dev/null 2>&1; then
  if [ -e public/storage ]; then echo "  OK  public/storage sudah ada";
  else
    echo "  PERINGATAN: storage:link gagal."
    [ "$WINDOWS" = 1 ] && echo "  Windows: buka Command Prompt di folder proyek, jalankan:  mklink /J public\\storage storage\\app\\public"
  fi
else echo "  OK  public/storage"; fi

if [ "$MIGRATE" = 1 ]; then
  echo "== Database: migrate dan akun admin awal =="
  if php artisan migrate --force && php artisan db:seed --class=AdminSeeder --force; then
    echo "  OK  database siap"
  else
    echo "  GAGAL: periksa DB_* pada .env dan pastikan database sudah dibuat, lalu ulangi:"
    echo "         php artisan migrate --force && php artisan db:seed --class=AdminSeeder --force"
    exit 1
  fi
fi

if [ "$PRODUKSI" = 1 ]; then
  php artisan config:cache && php artisan route:cache && php artisan view:cache && echo "  OK  cache produksi dibuat"
fi

echo ""
echo "============================================================"
echo " INSTALASI SELESAI"
echo "============================================================"
if [ "$MIGRATE" != 1 ]; then
  echo " Langkah berikutnya (setelah database dibuat dan .env diisi):"
  echo "   php artisan migrate --force"
  echo "   php artisan db:seed --class=AdminSeeder --force"
fi
echo " Login awal : admin@example.com / GantiSandiIni123   (SEGERA GANTI lewat menu 'Akun Saya')"
echo " Admin lain : isi ADMIN_EMAILS di .env, lalu php artisan config:cache"
echo " Batas unggah: 20 MB per berkas (Laravel); pastikan PHP: upload_max_filesize=20M, post_max_size=25M"
echo " Panduan    : README.md"
