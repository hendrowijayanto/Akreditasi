#!/usr/bin/env bash
# =====================================================================
# Sistem Informasi Akreditasi Sekolah Vokasi Universitas Tiga Serangkai
# Berbasis Lembaga Akreditasi Mandiri Infokom (LAM Infokom) - Laravel 11, satu skrip lengkap
#   - CRUD Kriteria Akreditasi, Isi Kriteria, Detail Dokumen (upload/link)
#   - Dashboard capaian (isian, narasi, kelengkapan dokumen)
#   - Baca publik; tambah/ubah/hapus wajib login
# Pemakaian: jalankan di root proyek Laravel 11 (.env + database sudah diatur):
#   bash akreditasi-lengkap.sh && php artisan migrate && php artisan db:seed --class=AdminSeeder
# =====================================================================
set -e
if [ ! -f artisan ]; then
  echo "Error: jalankan skrip ini di root proyek Laravel (file 'artisan' tidak ditemukan)."
  echo "Buat dulu: composer create-project laravel/laravel akreditasi && cd akreditasi"
  exit 1
fi
echo "Memasang mews/purifier (sanitasi HTML narasi)..."
composer require mews/purifier --no-interaction

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
            'file'            => 'nullable|file|max:10240|mimes:pdf,doc,docx,xls,xlsx,ppt,pptx,zip,jpg,png',
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
</head>
<body class="bg-light">
<header class="bg-white border-bottom py-3">
  <div class="container">
    <a href="{{ route('dashboard') }}" class="fs-5 fw-semibold text-decoration-none text-dark">Sistem Informasi Akreditasi Sekolah Vokasi Universitas Tiga Serangkai</a>
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
      <td>{{ \Illuminate\Support\Str::limit($i->elemen_penilaian, 80) }}</td>
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
  <h6>Elemen penilaian</h6><p>{{ $isi->elemen_penilaian }}</p>
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
  <div class="mb-3"><label class="form-label">Berkas (PDF, Office, ZIP, gambar; maks. 10 MB)</label>
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
</head>
<body class="bg-light">
<header class="bg-white border-bottom py-3">
  <div class="container">
    <a href="{{ route('dashboard') }}" class="fs-5 fw-semibold text-decoration-none text-dark">Sistem Informasi Akreditasi Sekolah Vokasi Universitas Tiga Serangkai</a>
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

echo "Selesai. Jalankan: php artisan migrate && php artisan db:seed --class=AdminSeeder"
echo "Login awal: admin@example.com / GantiSandiIni123 (segera ganti)."
