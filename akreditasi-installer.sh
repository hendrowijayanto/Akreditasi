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
# 7. PENGATURAN SERVER: izin folder + batas unggah 20 MB (PHP) + Apache
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
echo "== [1/7] Dasar: kriteria, isi kriteria, dokumen, dashboard, login =="
bagian_dasar
echo "== [2/7] Tema antarmuka profesional =="
bagian_tema
echo "== [3/7] Data Induk (Standar Mutu, Universitas, Fakultas, Tambahan) =="
bagian_data_induk
echo "== [4/7] Kelola Pengguna dan Akun Saya =="
bagian_pengguna
echo "== [5/7] Gunakan dokumen yang sudah pernah diunggah =="
bagian_arsip
echo "== [6/7] Lihat/pratinjau dokumen, kategori Dokumen Tambahan =="
bagian_lihat
echo "== [7/7] Pengaturan server dan batas unggah 20 MB =="
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
