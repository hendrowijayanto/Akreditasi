#!/usr/bin/env bash
# =====================================================================
# PEMBARUAN MENU LKPS: IDENTITAS UPPS DAN PROGRAM STUDI + DAFTAR DOSEN HOMEBASE
# (untuk situs yang SUDAH menjalankan tambah-lkps.sh)
#
# Perubahan:
#  1. Halaman LKPS: keterangan "Laporan Kinerja Program Studi Tahun Semester 2023/2024,
#     2024/2025 dan 2025/2026" (menggantikan dua baris subjudul sebelumnya).
#  2. Tombol "Identitas & isian tambahan" -> "Identitas UPPS dan Program Studi"
#     dengan warna sorot (kuning) agar mudah terlihat.
#  3. Pada halaman tersebut, "Tabel 3.A.3 Jumlah Dosen DTPR" disembunyikan dan diganti
#     "Daftar Dosen Homebase": Nama Dosen, NIDN, NUPTK, Golongan, Jabatan Fungsional Akademik, Pendidikan S1/S2/S3, Keilmuan,
#     Golongan, Jabatan Fungsional Akademik, dan Lampiran Bukti (tabel LKPS baru, CRUD + unggah lampiran).
#
# JAMINAN KEAMANAN DATA:
#  - Hanya MENAMBAH satu tabel baru (lkps_dosen_homebase). Tidak ada tabel/kolom yang dihapus.
#  - Nilai lama "Jumlah Dosen DTPR" di tabel lkps_isian TIDAK dihapus (hanya disembunyikan
#    dari formulir; ekspor/impor Excel tetap memakainya).
#  - config/lkps.php hanya disisipi (cadangan *.bak13); berkas tampilan yang diganti
#    juga dicadangkan *.bak13. Cadangan database (mysqldump) dibuat lebih dulu.
#  - Aman diulang.
#
# Pemakaian (root proyek): bash perbarui-lkps-identitas.sh [--tanpa-dump]
# =====================================================================
set -e
if [ ! -f artisan ]; then echo "Error: jalankan di root proyek Laravel."; exit 1; fi
TANPA_DUMP=0
for a in "$@"; do
  case "$a" in
    --tanpa-dump) TANPA_DUMP=1;;
    -h|--help) sed -n '2,24p' "$0"; exit 0;;
    *) echo "Opsi tidak dikenal: $a"; exit 1;;
  esac
done
TS=$(date +%Y%m%d-%H%M%S)
CFG=config/lkps.php
DAF=resources/views/lkps/daftar.blade.php
ISI=resources/views/lkps/isian.blade.php
CTL=app/Http/Controllers/LkpsIsianController.php

echo "[1/5] Pemeriksaan awal..."
for f in "$CFG" "$DAF" "$ISI" "$CTL"; do
  [ -f "$f" ] || { echo "Error: $f tidak ditemukan. Jalankan tambah-lkps.sh lebih dulu."; exit 1; }
done
command -v perl >/dev/null 2>&1 || { echo "Error: perl dibutuhkan."; exit 1; }
php artisan migrate:status >/dev/null 2>&1 || { echo "  GAGAL: tidak dapat terhubung ke database. Periksa DB_* pada .env."; exit 1; }
echo "  OK"

echo "[2/5] Cadangan..."
envval() { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//'; }
if [ "$TANPA_DUMP" = 1 ]; then
  echo "  --  cadangan database dilewati (--tanpa-dump)"
else
  CONN=$(envval DB_CONNECTION)
  if { [ "$CONN" = mysql ] || [ "$CONN" = mariadb ]; } && command -v mysqldump >/dev/null 2>&1; then
    DUMP="storage/app/cadangan-sebelum-identitas-$TS.sql"
    if MYSQL_PWD="$(envval DB_PASSWORD)" mysqldump -h "$(envval DB_HOST)" -P "$(envval DB_PORT)" -u "$(envval DB_USERNAME)" \
         --single-transaction --no-tablespaces "$(envval DB_DATABASE)" > "$DUMP" 2>/dev/null && [ -s "$DUMP" ]; then
      echo "  OK  database -> $DUMP"
    else
      rm -f "$DUMP"; echo "  GAGAL membuat cadangan database. Tidak ada yang diubah. Buat cadangan manual, lalu ulangi dengan --tanpa-dump."; exit 1
    fi
  else
    echo "  GAGAL: mysqldump tidak tersedia atau DB_CONNECTION bukan mysql/mariadb. Tidak ada yang diubah."
    echo "  Buat cadangan manual, lalu ulangi dengan --tanpa-dump."; exit 1
  fi
fi
cadang() { [ -f "$1.bak13" ] || cp "$1" "$1.bak13"; echo "  OK  $1 -> $1.bak13"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/kel.txt" <<'EOF'
        'k0' => 'Identitas UPPS dan Program Studi',
EOF
cat > "$TMP/semb.txt" <<'EOF'
    /*
    | Grup pada 'isian' yang tidak lagi ditampilkan di formulir (nilai lamanya tetap tersimpan di
    | tabel lkps_isian dan tetap ikut impor/ekspor Excel). "Jumlah Dosen DTPR" digantikan oleh
    | tabel "Daftar Dosen Homebase".
    */
    'isian_sembunyi' => [
        'Tabel 3.A.3 Jumlah Dosen DTPR',
    ],

EOF
cat > "$TMP/tab.txt" <<'EOF'

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
EOF
cat > "$TMP/ctrl.php" <<'EOF'
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
cat > "$TMP/isian.blade.php" <<'EOF'
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
                                @else
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

echo "[3/5] Konfigurasi config/lkps.php..."
if grep -q "'dosen_homebase'" "$CFG"; then
  if grep -q "'golongan'" "$CFG"; then echo "  (sudah diperbarui, dilewati)"; else
    cadang "$CFG"
    perl -0pi -e 's/(\n( +)\x27nuptk\x27 +=> \[[^\n]*\],\n)/$1$2\x27golongan\x27   => [\x27Golongan\x27, \x27text\x27, \x27nullable\x27],\n$2\x27jabatan_fungsional\x27 => [\x27Jabatan Fungsional Akademik\x27, \x27select\x27, \x27nullable\x27, [\x27-\x27, \x27Tenaga Pengajar\x27, \x27Asisten Ahli\x27, \x27Lektor\x27, \x27Lektor Kepala\x27, \x27Guru Besar\x27]],\n/' "$CFG"
    grep -q "'golongan'" "$CFG" && php -l "$CFG" >/dev/null || { echo "  GAGAL menambah kolom Golongan/Jabatan; mengembalikan."; cp "$CFG.bak13" "$CFG"; exit 1; }
    echo "  OK  kolom Golongan dan Jabatan Fungsional Akademik ditambahkan"
  fi
else
  grep -q "'kelompok' => \[" "$CFG" && grep -q "^    'tabel' => \[" "$CFG" && grep -q "^    'isian' => \[" "$CFG" \
    || { echo "  GAGAL: struktur config/lkps.php tidak dikenali. Tidak ada yang diubah."; exit 1; }
  cadang "$CFG"
  KEL="$TMP/kel.txt" SEMB="$TMP/semb.txt" TAB="$TMP/tab.txt" perl -0pi -e '
    sub baca { local $/; open my $h, "<", $ENV{$_[0]} or die; my $t = <$h>; close $h; $t }
    my ($k, $s, $t) = (baca("KEL"), baca("SEMB"), baca("TAB"));
    s/(\x27kelompok\x27 => \[\n)/$1$k/;
    s/\n(    \/\*\n    \| Isian di luar[^\n]*\n)/\n$s$1/ or s/\n(    \x27isian\x27 => \[)/\n$s$1/;
    s/(\n    \x27tabel\x27 => \[\n)/$1$t/;
  ' "$CFG"
  php -l "$CFG" >/dev/null || { echo "  GAGAL: sintaks config salah, mengembalikan."; cp "$CFG.bak13" "$CFG"; exit 1; }
  echo "  OK  kelompok, tabel Daftar Dosen Homebase, dan isian_sembunyi ditambahkan"
fi

echo "  Menyembunyikan Daftar Dosen Homebase dari daftar 31 tabel..."
LKP=app/Support/Lkps.php
if grep -q "'dosen_homebase'" "$CFG" && ! grep -q "'tersembunyi'" "$CFG"; then
  cadang "$CFG"
  perl -0pi -e 's/(\x27judul\x27 => \x27Daftar Dosen Homebase\x27, \x27kelompok\x27 => \x27k0\x27,)/$1 \x27tersembunyi\x27 => true,/' "$CFG"
  grep -q "'tersembunyi'" "$CFG" && php -l "$CFG" >/dev/null || { echo "  GAGAL menandai tabel tersembunyi; mengembalikan."; cp "$CFG.bak13" "$CFG"; exit 1; }
  echo "  OK  $CFG (tabel ditandai tersembunyi)"
fi
if [ -f "$LKP" ] && ! grep -q "tersembunyi" "$LKP"; then
  cadang "$LKP"
  perl -0pi -e 's/(foreach \(self::tabel\(\) as \$slug => \$def\) \{\n)(\s+\$kode = \$def\[\x27kelompok\x27\] \?\? \x27lainnya\x27;)/$1            if (! empty(\$def[\x27tersembunyi\x27])) {\n                continue;\n            }\n$2/' "$LKP"
  grep -q "tersembunyi" "$LKP" && php -l "$LKP" >/dev/null || { echo "  GAGAL mengubah $LKP; mengembalikan."; cp "$LKP.bak13" "$LKP"; exit 1; }
  echo "  OK  $LKP"
else echo "  (daftar tabel sudah menyembunyikan Daftar Dosen Homebase, dilewati)"; fi

echo "  Mengarahkan simpan/ubah/hapus Dosen Homebase kembali ke halaman Identitas..."
LKC=app/Http/Controllers/LkpsController.php
FRM=resources/views/lkps/form.blade.php
if [ -f "$LKC" ] && ! grep -q "function kembali" "$LKC"; then
  cadang "$LKC"
  cat > "$TMP/kembali.txt" <<'EOF'
    /** Tabel tersembunyi (mis. Daftar Dosen Homebase) kembali ke halaman Identitas; tabel lain ke daftar barisnya. */
    private function kembali(string $tabel)
    {
        return ! empty(Lkps::definisi($tabel)['tersembunyi'])
            ? redirect()->to(route('lkps.isian.index') . '#dosen-homebase')
            : redirect()->route('lkps.tabel.index', $tabel);
    }

EOF
  KMB="$TMP/kembali.txt" perl -0pi -e '
    sub baca { local $/; open my $h, "<", $ENV{$_[0]} or die; my $t = <$h>; close $h; $t }
    my $k = baca("KMB");
    s/redirect\(\)->route\(\x27lkps\.tabel\.index\x27, \$tabel\)->with\(\x27ok\x27, \x27(Data ditambahkan\.|Perubahan disimpan\.|Data dihapus\.)\x27\)/\$this->kembali(\$tabel)->with(\x27ok\x27, \x27$1\x27)/g;
    s/(    private function form\(string \$tabel, \?object \$row\))/$k$1/;
  ' "$LKC"
  [ "$(grep -c 'this->kembali' "$LKC")" = 3 ] && grep -q "function kembali" "$LKC" && php -l "$LKC" >/dev/null || { echo "  GAGAL mengubah $LKC; mengembalikan."; cp "$LKC.bak13" "$LKC"; exit 1; }
  echo "  OK  $LKC"
else echo "  (controller tabel sudah diperbarui, dilewati)"; fi
if [ -f "$FRM" ] && ! grep -q "isian.index" "$FRM"; then
  cadang "$FRM"
  perl -0pi -e 's/<a href="\{\{ route\(\x27lkps\.tabel\.index\x27, \$tabel\) \}\}" class="btn btn-outline-secondary">Batal<\/a>/<a href="{{ ! empty(\$def[\x27tersembunyi\x27]) ? route(\x27lkps.isian.index\x27) : route(\x27lkps.tabel.index\x27, \$tabel) }}" class="btn btn-outline-secondary">Batal<\/a>/' "$FRM"
  echo "  OK  $FRM"
fi

echo "[4/5] Tampilan dan controller..."
if grep -q "Hapus dosen ini" "$ISI"; then echo "  (halaman identitas sudah diperbarui, dilewati)"; else
  cadang "$ISI"; cp "$TMP/isian.blade.php" "$ISI"; echo "  OK  $ISI"; fi
if grep -q "isian_sembunyi" "$CTL"; then echo "  (controller sudah diperbarui, dilewati)"; else
  cadang "$CTL"; cp "$TMP/ctrl.php" "$CTL"; php -l "$CTL" >/dev/null; echo "  OK  $CTL"; fi
if grep -q "Tahun Semester 2023/2024" "$DAF" && grep -q "Identitas UPPS dan Program Studi" "$DAF"; then echo "  (halaman daftar sudah diperbarui, dilewati)"; else
  cadang "$DAF"
  BTN='<a href="{{ route('"'"'lkps.isian.index'"'"') }}" class="btn btn-sm btn-warning fw-bold px-3 shadow-sm" style="box-shadow:0 0 0 3px rgba(245,158,11,.35)!important">Identitas UPPS dan Program Studi</a>' \
  SUBB='    <p class="small text-secondary mb-0 mt-1">Laporan Kinerja Program Studi Tahun Semester 2023/2024, 2024/2025 dan 2025/2026</p>' \
  perl -0pi -e '
    s{[ ]*<p class="small text-secondary mb-0 mt-1">Laporan Kinerja Program Studi &middot; Tahun TS \{\{ \$tahun \}\}</p>\n(?:[ ]*<p class="small text-secondary mb-0">Laporan Kinerja Program Studi Tahun 2023/2024, 2024/2025 dan 2025/2026</p>\n)?}{$ENV{SUBB}\n};
    s{<a href="\{\{ route\(\x27lkps\.isian\.index\x27\) \}\}" class="[^"]*">Identitas (?:&amp; isian tambahan|UPPS dan Program Studi)</a>}{$ENV{BTN}};
  ' "$DAF"
  grep -q "Tahun Semester 2023/2024" "$DAF" && grep -q "Identitas UPPS dan Program Studi" "$DAF" || echo "  PERINGATAN: sebagian teks pada $DAF tidak cocok (sudah Anda ubah?). Periksa manual; cadangan: $DAF.bak13"
  echo "  OK  $DAF"
fi

echo "[5/5] Sinkron tabel dan bersihkan cache..."
php artisan lkps:sinkron
php artisan view:clear >/dev/null 2>&1 || true
php artisan config:clear >/dev/null 2>&1 || true
php artisan route:clear >/dev/null 2>&1 || true
echo
echo "Selesai. Buka menu Data Induk > LKPS. Jika memakai cache: php artisan config:cache && php artisan view:cache"
echo "Mengembalikan: salin kembali berkas *.bak13 (tabel lkps_dosen_homebase boleh dibiarkan)."
