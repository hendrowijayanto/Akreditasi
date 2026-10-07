#!/usr/bin/env bash
# =====================================================================
# Pembaruan: (1) link "Unduh" menjadi "Lihat" (pratinjau, tidak langsung terunduh)
#            (2) hapus informasi tanggal "Diperbarui" di Data Induk
#            (3) sub menu baru Data Induk: "Dokumen Tambahan"
# Sistem Informasi Akreditasi Program Studi Teknologi Informasi
# Sekolah Vokasi Universitas Tiga Serangkai
# Tanpa mengubah database. Aman dijalankan ulang (bagian yang sudah terpasang dilewati).
# Jalankan di root proyek:  bash perbarui-lihat-stmik.sh
# =====================================================================
set -e
if [ ! -f artisan ]; then echo "Error: jalankan di root proyek Laravel."; exit 1; fi
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
echo "Selesai. Muat ulang browser (Ctrl+F5). Jika memakai cache produksi: php artisan config:cache && php artisan route:cache && php artisan view:cache"
