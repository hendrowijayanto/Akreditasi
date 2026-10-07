#!/usr/bin/env bash
# =============================================================================
#  SISTEM INFORMASI AKREDITASI PROGRAM STUDI TEKNOLOGI INFORMASI
#  Sekolah Vokasi Universitas Tiga Serangkai  (berbasis LAM Infokom)
#
#  INSTALLER LENGKAP - SATU BERKAS. Memasang seluruh aplikasi dalam satu perintah:
#    1. Kriteria Akreditasi, Isi Kriteria (editor narasi), Detail Dokumen (unggah/link)
#    2. Dashboard capaian, login (baca publik; tambah/ubah/hapus wajib login)
#    3. Tema antarmuka profesional, Kelola Pengguna, Akun Saya
#    4. Data Induk: Dokumen Standar Mutu / Universitas / Fakultas / Tambahan
#    5. Gunakan kembali dokumen yang sudah diunggah, pratinjau dokumen, batas unggah 20 MB
#    6. Tiga tampilan dashboard (Ringkas, Analitik, Panel Admin) + pemilih tampilan
#    7. LKPS LAM Infokom (31 tabel + Identitas UPPS/Prodi + Daftar Dosen Homebase),
#       Lampiran Bukti berkas ATAU link, Impor Excel/CSV per tabel, ekspor Excel
#    8. Analitik lima aspek: Budaya Mutu, Relevansi Pendidikan, Penelitian, PkM, Akuntabilitas
#
#  PEMAKAIAN
#    Proyek baru :  bash akreditasi-lengkap.sh --buat akreditasi
#    Di dalam proyek Laravel 11 yang sudah ada (.env dan database siap):
#                   bash akreditasi-lengkap.sh
#
#  OPSI
#    --buat NAMA      buat proyek Laravel 11 baru di folder NAMA bila belum ada (butuh Composer)
#    --produksi       APP_ENV=production, APP_DEBUG=false, lalu cache konfigurasi/route/view
#    --lewati-server  jangan ubah izin folder / php.ini / Apache (Windows, hosting bersama, tanpa sudo)
#    --paksa          timpa kode aplikasi bila sudah terpasang (data database TIDAK dihapus)
#    --tanpa-excel    jangan pasang PhpSpreadsheet (impor/ekspor .xlsx nonaktif; CSV tetap bisa)
#    --data-induk-db  (opsional) pindahkan metadata Data Induk dari berkas JSON ke database
#    --tanpa-cadangan lewati cadangan database otomatis (hanya bila Anda sudah mencadangkan sendiri)
#    -h, --help       bantuan ini
#
#  KEAMANAN DATA: skrip hanya MENAMBAH. Pada instalasi yang sudah berisi data, database
#  dicadangkan lebih dulu (storage/app/cadangan/), berkas yang diubah dicadangkan *.bak*,
#  dan seluruh tahap aman diulang. Panduan lengkap: README.md
# =============================================================================
set -e

usage() { sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; }

BUAT=""; PRODUKSI=0; LEWATI_SERVER=0; PAKSA=0; TANPA_EXCEL=0; DATA_INDUK_DB=0; TANPA_CADANGAN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --buat) shift; BUAT="${1:-}"; [ -n "$BUAT" ] || { echo "Opsi --buat membutuhkan nama folder."; exit 1; };;
    --produksi) PRODUKSI=1;; --lewati-server) LEWATI_SERVER=1;; --paksa) PAKSA=1;;
    --tanpa-excel) TANPA_EXCEL=1;; --data-induk-db) DATA_INDUK_DB=1;; --tanpa-cadangan) TANPA_CADANGAN=1;;
    -h|--help) usage; exit 0;;
    *) echo "Opsi tidak dikenal: $1"; usage; exit 1;;
  esac
  shift
done

WINDOWS=0
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) WINDOWS=1;; esac
TS=$(date +%Y%m%d-%H%M%S)
ok()   { echo "  OK  $*"; }
gagal(){ echo "  GAGAL: $*"; exit 1; }
envval() { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//'; }

echo "============================================================"
echo " Sistem Informasi Akreditasi Prodi TI - Installer Lengkap"
echo "============================================================"

# ---------- [0] Prasyarat ----------
echo "[0] Memeriksa prasyarat..."
command -v php >/dev/null 2>&1 || gagal "PHP tidak ditemukan di PATH (butuh PHP 8.2 atau lebih baru)."
php -r 'exit(version_compare(PHP_VERSION,"8.2.0",">=")?0:1);' || gagal "dibutuhkan PHP 8.2 atau lebih baru (terpasang: $(php -r 'echo PHP_VERSION;'))."
command -v perl >/dev/null 2>&1 || gagal "perl dibutuhkan (Ubuntu: sudo apt install perl; Windows: pakai Git Bash, perl sudah termasuk)."
PHPMOD=$(php -m 2>/dev/null | tr 'A-Z' 'a-z')
KURANG=""
for e in mbstring xml curl zip fileinfo openssl tokenizer ctype json; do echo "$PHPMOD" | grep -qx "$e" || KURANG="$KURANG $e"; done
[ -z "$KURANG" ] || gagal "ekstensi PHP belum aktif:$KURANG  (Ubuntu: sudo apt install php-mbstring php-xml php-curl php-zip)"
echo "$PHPMOD" | grep -qx gd || echo "  PERINGATAN: ekstensi PHP 'gd' belum aktif (dibutuhkan PhpSpreadsheet untuk .xlsx; CSV tetap bisa)."
ok "PHP $(php -r 'echo PHP_VERSION;')"

# ---------- [1] Proyek Laravel ----------
if [ ! -f artisan ]; then
  if [ -z "$BUAT" ]; then
    echo "Error: file 'artisan' tidak ditemukan. Jalankan di root proyek Laravel 11, atau buat proyek baru:"
    echo "       bash akreditasi-lengkap.sh --buat akreditasi"
    exit 1
  fi
  command -v composer >/dev/null 2>&1 || gagal "Composer tidak ditemukan di PATH (https://getcomposer.org)."
  [ -e "$BUAT" ] && gagal "folder '$BUAT' sudah ada. Pilih nama lain atau masuk ke folder itu lalu jalankan tanpa --buat."
  echo "[1] Membuat proyek Laravel 11 di folder '$BUAT' (beberapa menit)..."
  composer create-project "laravel/laravel:^11.0" "$BUAT" --no-interaction
  cd "$BUAT"
  ok "proyek dibuat: $(pwd)"
else
  echo "[1] Proyek Laravel ditemukan: $(pwd)"
  command -v composer >/dev/null 2>&1 || echo "  PERINGATAN: Composer tidak ditemukan; pemasangan paket (purifier, PhpSpreadsheet) akan gagal."
fi
[ -f .env ] || { [ -f .env.example ] && cp .env.example .env && php artisan key:generate --force >/dev/null 2>&1 || true; }

# ---------- [2] Database ----------
echo "[2] Memeriksa database..."
KONEKSI=$(envval DB_CONNECTION); [ -n "$KONEKSI" ] || KONEKSI=sqlite
if [ "$KONEKSI" = sqlite ]; then
  echo "$PHPMOD" | grep -qx pdo_sqlite || gagal "ekstensi PHP pdo_sqlite belum aktif (Ubuntu: sudo apt install php-sqlite3)."
  DBF=$(envval DB_DATABASE); [ -n "$DBF" ] || DBF=database/database.sqlite
  [ -f "$DBF" ] || { mkdir -p "$(dirname "$DBF")"; : > "$DBF"; ok "berkas SQLite dibuat: $DBF"; }
  ok "database SQLite: $DBF"
else
  echo "$PHPMOD" | grep -qx pdo_mysql || gagal "ekstensi PHP pdo_mysql belum aktif (Ubuntu: sudo apt install php-mysql)."
  php artisan migrate:status >/dev/null 2>&1 || php artisan db:show >/dev/null 2>&1 || gagal "tidak dapat terhubung ke database. Periksa DB_* di .env dan pastikan database sudah dibuat."
  ok "terhubung ke database $KONEKSI ($(envval DB_DATABASE))"
fi

SUDAH_ADA=0
[ -f app/Http/Controllers/KriteriaController.php ] && SUDAH_ADA=1

# ---------- [3] Cadangan database (hanya bila aplikasi sudah terpasang) ----------
if [ "$SUDAH_ADA" = 1 ] && [ "$TANPA_CADANGAN" != 1 ]; then
  echo "[3] Cadangan database sebelum perubahan..."
  mkdir -p storage/app/cadangan
  if [ "$KONEKSI" = sqlite ]; then
    cp "$DBF" "storage/app/cadangan/database-sebelum-$TS.sqlite" && ok "storage/app/cadangan/database-sebelum-$TS.sqlite"
  elif command -v mysqldump >/dev/null 2>&1; then
    MYSQL_PWD="$(envval DB_PASSWORD)" mysqldump -h "$(envval DB_HOST)" -P "$(envval DB_PORT)" -u "$(envval DB_USERNAME)" \
      --single-transaction --no-tablespaces "$(envval DB_DATABASE)" > "storage/app/cadangan/database-sebelum-$TS.sql" 2>/dev/null \
      && [ -s "storage/app/cadangan/database-sebelum-$TS.sql" ] && ok "storage/app/cadangan/database-sebelum-$TS.sql" \
      || { rm -f "storage/app/cadangan/database-sebelum-$TS.sql"; gagal "cadangan database gagal. Tidak ada yang diubah. Cadangkan manual lalu ulangi dengan --tanpa-cadangan."; }
  else
    gagal "mysqldump tidak tersedia. Cadangkan database manual lalu ulangi dengan --tanpa-cadangan."
  fi
else
  echo "[3] Cadangan database: tidak diperlukan (instalasi baru) atau dilewati."
fi

# ---------- [4] Menyiapkan modul ----------
M=$(mktemp -d 2>/dev/null || mktemp -d -t akr)
trap 'rm -rf "$M"' EXIT
echo "[4] Menyiapkan modul pemasangan..."
cat > "$M/01-dasar.sh" <<'EOF_MODUL_DASAR_Q7'
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
EOF_MODUL_DASAR_Q7
cat > "$M/02-lkps.sh" <<'EOF_MODUL_LKPS_Q7'
#!/usr/bin/env bash
# =====================================================================
# MENAMBAHKAN LKPS LAM INFOKOM (Diploma III) KE SISTEM INFORMASI AKREDITASI
# Sekolah Vokasi Universitas Tiga Serangkai
#
# - Menu "LKPS" berada di bawah menu "Data Induk" (sidebar).
# - Lampiran Bukti: unggah berkas ATAU link; Impor Excel/CSV per tabel.
# - 32 tabel LKPS termasuk Daftar Dosen Homebase (CRUD, lampiran bukti, impor/ekspor Excel, isian identitas),
#   bersumber dari skrip buat-lkps-laravel.sh.
# - Kelengkapan LKPS tampil di Dashboard Akreditasi yang sama (angka di kartu
#   utama + bagian "Kelengkapan LKPS").
#
# JAMINAN KEAMANAN (data yang sudah ada tidak dirusak):
#  - Hanya MENAMBAH tabel baru berawalan "lkps_" (dan tabel lkps_isian).
#    Tabel lama (kriteria, dokumen, pengguna, dll.) tidak disentuh.
#  - Hanya migration LKPS yang dijalankan (migration lain tidak ikut).
#  - routes/web.php, layout, dan dashboard TIDAK ditimpa: hanya disisipi blok kecil
#    (dicadangkan sebagai *.bak8). Controller/halaman lama tidak diubah.
#  - Sebelum mengubah apa pun: cadangan database (mysqldump) kecuali --tanpa-dump.
#  - Berkas yang sudah ada tidak ditimpa (config/lkps.php Anda aman) kecuali --timpa.
#  - Impor Excel secara bawaan MENAMBAH (tidak menghapus); mode "ganti" hanya admin.
#  - Aman diulang.
#
# Pemakaian (di root proyek Sistem Informasi Akreditasi):
#   bash tambah-lkps.sh [--tanpa-dump] [--tanpa-excel] [--timpa]
#     --tanpa-dump   lewati mysqldump (hanya bila Anda sudah membuat cadangan sendiri)
#     --tanpa-excel  jangan pasang pustaka PhpSpreadsheet (impor/ekspor Excel nonaktif)
#     --timpa        timpa berkas LKPS yang sudah ada (yang lama dicadangkan *.bak8)
#   Variabel opsional: LKPS_TAHUN_TS=2025/2026  LKPS_TEMPLATE=/path/template.xlsx
# =====================================================================
set -e
if [ ! -f artisan ]; then echo "Error: jalankan di root proyek Laravel."; exit 1; fi

TANPA_DUMP=0; TANPA_EXCEL=0; TIMPA=0
for a in "$@"; do
  case "$a" in
    --tanpa-dump) TANPA_DUMP=1;; --tanpa-excel) TANPA_EXCEL=1;; --timpa) TIMPA=1;;
    -h|--help) sed -n '2,34p' "$0"; exit 0;;
    *) echo "Opsi tidak dikenal: $a"; exit 1;;
  esac
done
LKPS_TAHUN_TS="${LKPS_TAHUN_TS:-2025/2026}"
TS=$(date +%Y%m%d-%H%M%S)
L=resources/views/layout.blade.php
R=routes/web.php
DBV=resources/views/dashboard.blade.php
MIG=database/migrations/2026_10_08_000100_create_lkps_tables.php

echo "[1/7] Pemeriksaan awal..."
[ -f "$R" ] || { echo "Error: $R tidak ditemukan."; exit 1; }
if [ ! -f "$L" ] || ! grep -q "yield('content')" "$L"; then
  echo "Error: layout aplikasi ($L) tidak ditemukan atau tidak memakai @yield('content')."; exit 1
fi
command -v perl >/dev/null 2>&1 || { echo "Error: perl dibutuhkan."; exit 1; }
php -r 'exit(version_compare(PHP_VERSION,"8.2.0",">=")?0:1);' || { echo "Error: dibutuhkan PHP 8.2 atau lebih baru."; exit 1; }
if ! php artisan migrate:status >/dev/null 2>&1; then
  echo "  GAGAL: tidak dapat terhubung ke database. Periksa DB_* pada .env, lalu ulangi."; exit 1
fi
echo "  OK"

# ---------- 2. CADANGAN ----------
echo "[2/7] Cadangan..."
mkdir -p storage/app
envval() { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//'; }
if [ "$TANPA_DUMP" = 1 ]; then
  echo "  --  cadangan database dilewati (--tanpa-dump)"
else
  CONN=$(envval DB_CONNECTION)
  if { [ "$CONN" = mysql ] || [ "$CONN" = mariadb ]; } && command -v mysqldump >/dev/null 2>&1; then
    DUMP="storage/app/cadangan-sebelum-lkps-$TS.sql"
    if MYSQL_PWD="$(envval DB_PASSWORD)" mysqldump -h "$(envval DB_HOST)" -P "$(envval DB_PORT)" -u "$(envval DB_USERNAME)" \
         --single-transaction --no-tablespaces "$(envval DB_DATABASE)" > "$DUMP" 2>/dev/null && [ -s "$DUMP" ]; then
      echo "  OK  database -> $DUMP"
    else
      rm -f "$DUMP"
      echo "  GAGAL membuat cadangan database. Tidak ada yang diubah."
      echo "  Buat cadangan manual (phpMyAdmin > Export, atau mysqldump), lalu ulangi dengan --tanpa-dump."
      exit 1
    fi
  else
    echo "  GAGAL: mysqldump tidak tersedia atau DB_CONNECTION bukan mysql/mariadb. Tidak ada yang diubah."
    echo "  Buat cadangan database manual, lalu ulangi dengan --tanpa-dump."
    exit 1
  fi
fi
for f in "$R" "$L" "$DBV"; do
  if [ -f "$f" ] && ! grep -q "lkps\." "$f"; then cp "$f" "$f.bak8"; echo "  OK  $f -> $f.bak8"; fi
done

# ---------- 3. PUSTAKA EXCEL (opsional) ----------
echo "[3/7] Pustaka Excel (PhpSpreadsheet)..."
if [ "$TANPA_EXCEL" = 1 ]; then
  echo "  --  dilewati (--tanpa-excel); impor/ekspor Excel akan menampilkan petunjuk pemasangan."
elif php -r 'require "vendor/autoload.php"; exit(class_exists("PhpOffice\\PhpSpreadsheet\\IOFactory") ? 0 : 1);' 2>/dev/null; then
  echo "  OK  PhpSpreadsheet sudah terpasang"
elif command -v composer >/dev/null 2>&1; then
  for e in zip gd xml mbstring; do php -m | grep -qi "^$e$" || echo "  PERINGATAN: ekstensi PHP '$e' belum aktif (dibutuhkan PhpSpreadsheet)."; done
  if composer require phpoffice/phpspreadsheet --no-interaction; then echo "  OK  PhpSpreadsheet dipasang";
  else echo "  PERINGATAN: pemasangan PhpSpreadsheet gagal. LKPS tetap berfungsi; impor/ekspor Excel nonaktif sampai: composer require phpoffice/phpspreadsheet"; fi
else
  echo "  PERINGATAN: composer tidak ditemukan. Impor/ekspor Excel nonaktif sampai: composer require phpoffice/phpspreadsheet"
fi

# ---------- 4. BERKAS BARU ----------
echo "[4/7] Menulis berkas LKPS..."
tulis() {   # tulis <path> (isi dari stdin). Berkas yang sudah ada tidak ditimpa kecuali --timpa
  local f="$1"
  if [ -f "$f" ] && [ "$TIMPA" != 1 ]; then cat >/dev/null; echo "  (sudah ada, dilewati) $f"; return 0; fi
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] && cp "$f" "$f.bak8"
  cat > "$f"
  echo "  OK  $f"
}

tulis config/lkps.php <<'EOF'
<?php
/*
|--------------------------------------------------------------------------
| Definisi 31 tabel LKPS LAM Infokom (Program Diploma III)
|--------------------------------------------------------------------------
| Mengikuti template "Data_DKPS_TI-D3_2025_New.xlsx": satu tabel database
| per sheet, kolom dan urutannya sama dengan kolom di template.
|
| Format kolom:  'nama_kolom' => [Label, tipe, aturan_validasi, opsi_select]
|   - Label bertingkat ditulis dengan "|" seperti header Excel bertingkat,
|     mis. 'Jumlah Mahasiswa Baru|Reguler|Diterima'.
|   - Tipe: text, textarea, number, decimal, date, select, check, url, file
|     check = kotak centang, ditampilkan dan diekspor sebagai √
|     url   = tautan/teks (mis. Tugas Pokok dan Fungsi)
|   Setiap tabel otomatis mendapat kolom "Lampiran Bukti" (unggah PDF/gambar,
|   dibuka sebagai pratinjau). Kolom Link Bukti di template Excel diisi dengan
|   link pratinjau lampiran tersebut saat ekspor.
| 'ringkasan' => ['jumlah'] / ['jumlah', 'rata'] menampilkan baris Jumlah
|   (dan Rata-rata) di bawah tabel, seperti di template.
| Setelah mengedit, jalankan:  php artisan lkps:sinkron
*/

$ts3   = ['TS-2', 'TS-1', 'TS'];
$ts4   = ['TS-3', 'TS-2', 'TS-1', 'TS'];
$lni   = ['L', 'N', 'I'];

// Tiga kolom TS-2/TS-1/TS dengan grup header opsional.
$perTs = function (string $grup = '', string $tipe = 'number', string $prefix = '') {
    $g = $grup !== '' ? $grup . '|' : '';
    return [
        $prefix . 'ts2' => [$g . 'TS-2', $tipe, 'nullable'],
        $prefix . 'ts1' => [$g . 'TS-1', $tipe, 'nullable'],
        $prefix . 'ts'  => [$g . 'TS', $tipe, 'nullable'],
    ];
};

$sarpras = [
    'nama_prasarana' => ['Nama Prasarana', 'text', 'required'],
    'daya_tampung'   => ['Daya Tampung', 'number', 'nullable'],
    'luas_ruang'     => ['Luas Ruang (m²)', 'decimal', 'nullable'],
    'kepemilikan'    => ['Milik Sendiri (M)/Sewa (W)', 'select', 'nullable', ['M', 'W']],
    'lisensi'        => ['Berlisensi (L)/Public Domain (P)/Tidak Berlisensi (T)', 'select', 'nullable', ['L', 'P', 'T']],
    'perangkat'      => ['Perangkat', 'textarea', 'nullable'],
];

$hibah = fn (string $ketua, string $judul, string $jenis) => array_merge([
    'nama_dtpr'        => [$ketua, 'text', 'required'],
    'judul'            => [$judul, 'text', 'required'],
    'jumlah_mahasiswa' => ['Jumlah Mahasiswa yang Terlibat', 'number', 'nullable'],
    'jenis_hibah'      => [$jenis, 'text', 'nullable'],
    'sumber'           => ['Sumber|L/N/I', 'select', 'nullable', $lni],
    'durasi'           => ['Durasi (tahun)', 'decimal', 'nullable'],
], $perTs('Pendanaan (Rp juta)', 'decimal', 'dana_'));

$kerjasama = array_merge([
    'judul_kerjasama' => ['Judul Kerja Sama', 'text', 'required'],
    'mitra'           => ['Mitra Kerja Sama', 'text', 'required'],
    'sumber'          => ['Sumber|L/N/I', 'select', 'nullable', $lni],
    'durasi'          => ['Durasi (tahun)', 'text', 'nullable'],
], $perTs('Pendanaan (Rp juta)', 'decimal', 'dana_'));

$hki = array_merge([
    'judul'     => ['Judul', 'text', 'required'],
    'jenis_hki' => ['Jenis HKI', 'text', 'required'],
    'nama_dtpr' => ['Nama DTPR', 'text', 'required'],
], $perTs('Tahun Perolehan (√)', 'check'));

$pl = [];
foreach (range(1, 5) as $i) {
    $pl["pl{$i}"] = ["Profil Lulusan (PL)|PL {$i}", 'check', 'nullable'];
}

return [

    'tahun_ts' => env('LKPS_TAHUN_TS', '2025/2026'),

    'kelompok' => [
        'k0' => 'Identitas UPPS dan Program Studi',
        'k1' => 'Tabel 1: Pimpinan, Keuangan, SDM & SPMI',
        'k2' => 'Tabel 2: Mahasiswa, Pembelajaran & Lulusan',
        'k3' => 'Tabel 3: Penelitian',
        'k4' => 'Tabel 4: Pengabdian kepada Masyarakat',
        'k5' => 'Tabel 5: Tata Kelola & Sarana Pendidikan',
        'k6' => 'Tabel 6: Visi dan Misi',
    ],

    /*
    | Grup pada 'isian' yang tidak lagi ditampilkan di formulir (nilai lamanya tetap tersimpan di
    | tabel lkps_isian dan tetap ikut impor/ekspor Excel). "Jumlah Dosen DTPR" digantikan oleh
    | tabel "Daftar Dosen Homebase".
    */
    'isian_sembunyi' => [
        'Tabel 3.A.3 Jumlah Dosen DTPR',
    ],

    /*
    | Isian di luar tabel: sheet Identitas (formulir "Identitas UPPS dan Program Studi")
    | dan baris "Jumlah Dosen DTPR" Tabel 3.A.3 (kini disembunyikan). Format: kunci => [Label, tipe, sheet, sel].
    */
    'isian' => [
        'Identitas Program Studi' => [
            'perguruan_tinggi'   => ['Perguruan Tinggi', 'text', 'Identitas', 'C6'],
            'upps'               => ['Unit Pengelola Program Studi', 'text', 'Identitas', 'C8'],
            'jenis_program'      => ['Jenis Program', 'text', 'Identitas', 'C10'],
            'nama_ps'            => ['Nama Program Studi', 'text', 'Identitas', 'C12'],
            'alamat'             => ['Alamat', 'text', 'Identitas', 'C14'],
            'telepon'            => ['Nomor Telepon', 'text', 'Identitas', 'C16'],
            'email_web'          => ['E-Mail dan Website', 'text', 'Identitas', 'C18'],
            'sk_pendirian_pt'    => ['Nomor SK Pendirian PT', 'text', 'Identitas', 'G6'],
            'tgl_sk_pendirian'   => ['Tanggal SK Pendirian PT', 'text', 'Identitas', 'G8'],
            'tahun_pertama'      => ['Tahun Pertama Menerima Mahasiswa', 'text', 'Identitas', 'G10'],
            'akreditasi_ps'      => ['Akreditasi PS', 'text', 'Identitas', 'G12'],
            'sk_akreditasi'      => ['Nomor SK BAN-PT/LAM', 'text', 'Identitas', 'G14'],
        ],
        'Tabel 3.A.3 Jumlah Dosen DTPR' => [
            'dtpr_ts2' => ['Jumlah Dosen DTPR TS-2', 'number', 'Tabel 3.A.3', 'C5'],
            'dtpr_ts1' => ['Jumlah Dosen DTPR TS-1', 'number', 'Tabel 3.A.3', 'D5'],
            'dtpr_ts'  => ['Jumlah Dosen DTPR TS', 'number', 'Tabel 3.A.3', 'E5'],
        ],
    ],

    'tabel' => [

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

        // ======================= TABEL 1 =======================
        't1a1_pimpinan' => [
            'judul' => '1.A.1 Tabel Pimpinan dan Tupoksi UPPS dan PS', 'kelompok' => 'k1',
            'kolom' => [
                'unit_kerja'          => ['Unit Kerja', 'text', 'required'],
                'nama_ketua'          => ['Nama Ketua', 'text', 'required'],
                'periode_jabatan'     => ['Periode Jabatan', 'text', 'nullable'],
                'pendidikan_terakhir' => ['Pendidikan Terakhir', 'select', 'nullable', ['Diploma', 'Sarjana', 'Magister', 'Doktor', '-']],
                'jabatan_fungsional'  => ['Jabatan Fungsional', 'select', 'nullable', ['-', 'Tenaga Pengajar', 'Asisten Ahli', 'Lektor', 'Lektor Kepala', 'Guru Besar']],
                'tupoksi'             => ['Tugas Pokok dan Fungsi', 'url', 'nullable'],
            ],
        ],
        't1a2_sumber_dana' => [
            'judul' => '1.A.2 Sumber Pendanaan UPPS/PS', 'kelompok' => 'k1', 'ringkasan' => ['jumlah'],
            'keterangan' => 'Data ditulis dalam jutaan rupiah.',
            'kolom' => array_merge(
                ['sumber_pendanaan' => ['Sumber Pendanaan', 'text', 'required']],
                $perTs('', 'decimal'),
            ),
        ],
        't1a3_penggunaan_dana' => [
            'judul' => '1.A.3 Penggunaan Dana UPPS/PS', 'kelompok' => 'k1', 'ringkasan' => ['jumlah'],
            'keterangan' => 'Data ditulis dalam jutaan rupiah.',
            'kolom' => array_merge(
                ['penggunaan_dana' => ['Penggunaan Dana', 'text', 'required']],
                $perTs('', 'decimal'),
            ),
        ],
        't1a4_ewmp' => [
            'judul' => '1.A.4 Rata-rata Beban DTPR per semester (EWMP) pada TS', 'kelompok' => 'k1',
            'ringkasan' => ['jumlah', 'rata'],
            'kolom' => [
                'nama_dtpr'                => ['Nama DTPR', 'text', 'required'],
                'sks_ps_sendiri'           => ['SKS Pengajaran pada|PS Sendiri', 'decimal', 'nullable'],
                'sks_ps_lain'              => ['SKS Pengajaran pada|PS Lain, PT Sendiri', 'decimal', 'nullable'],
                'sks_pt_lain'              => ['SKS Pengajaran pada|PT Lain', 'decimal', 'nullable'],
                'sks_penelitian'           => ['SKS Penelitian', 'decimal', 'nullable'],
                'sks_pkm'                  => ['SKS Pengabdian kepada Masyarakat', 'decimal', 'nullable'],
                'sks_manajemen_pt_sendiri' => ['SKS Manajemen|PT Sendiri', 'decimal', 'nullable'],
                'sks_manajemen_pt_lain'    => ['SKS Manajemen|PT Lain', 'decimal', 'nullable'],
                'total_sks'                => ['Total SKS', 'decimal', 'nullable'],
            ],
            'total' => ['total_sks' => ['sks_ps_sendiri', 'sks_ps_lain', 'sks_pt_lain', 'sks_penelitian', 'sks_pkm', 'sks_manajemen_pt_sendiri', 'sks_manajemen_pt_lain']],
        ],
        't1a5_tendik' => [
            'judul' => '1.A.5 Kualifikasi Tenaga Kependidikan', 'kelompok' => 'k1', 'ringkasan' => ['jumlah'],
            'kolom' => array_merge(
                ['jenis' => ['Jenis Tenaga Kependidikan', 'select', 'required', ['Pustakawan', 'Laboran/Teknisi', 'Administrasi', 'Lainnya']]],
                (function () {
                    $k = [];
                    foreach (['s3' => 'S3', 's2' => 'S2', 's1' => 'S1', 'd4' => 'D4', 'd3' => 'D3', 'd2' => 'D2', 'd1' => 'D1', 'sma' => 'SMA/SMK/MA', 'smp' => 'SMP', 'sd' => 'SD'] as $n => $l) {
                        $k[$n] = ["Jumlah Tenaga Kependidikan dengan Pendidikan Terakhir|{$l}", 'number', 'nullable'];
                    }
                    return $k;
                })(),
                ['unit_kerja' => ['Unit Kerja', 'textarea', 'nullable']],
            ),
        ],
        't1b_spmi' => [
            'judul' => '1.B Tabel Unit SPMI dan SDM', 'kelompok' => 'k1',
            'kolom' => [
                'unit_spmi'             => ['Unit SPMI', 'select', 'required', ['Universitas/PT', 'UPPS', 'Program Studi']],
                'nama_unit'             => ['Nama Unit SPMI', 'text', 'required'],
                'dokumen_spmi'          => ['Dokumen SPMI', 'textarea', 'nullable'],
                'auditor_internal'      => ['Jumlah Auditor Mutu|Internal', 'number', 'nullable'],
                'auditor_certified'     => ['Jumlah Auditor Mutu|Certified', 'number', 'nullable'],
                'auditor_non_certified' => ['Jumlah Auditor Mutu|Non Certified', 'number', 'nullable'],
                'frekuensi_audit'       => ['Frekuensi Audit/Monev per Tahun', 'text', 'nullable'],
                'bukti_certified'       => ['Bukti Certified Auditor', 'url', 'nullable'],
                'laporan_audit'         => ['Laporan Audit', 'textarea', 'nullable'],
            ],
        ],

        // ======================= TABEL 2 =======================
        't2a1_data_mahasiswa' => [
            'judul' => '2.A.1 Data Mahasiswa', 'kelompok' => 'k2', 'ringkasan' => ['jumlah'],
            'kolom' => [
                'ts'                         => ['TS', 'select', 'required', $ts4],
                'daya_tampung'               => ['Daya Tampung', 'number', 'nullable'],
                'pendaftar'                  => ['Jumlah Calon Mahasiswa|Pendaftar', 'number', 'nullable'],
                'pendaftar_afirmasi'         => ['Jumlah Calon Mahasiswa|Pendaftar Afirmasi', 'number', 'nullable'],
                'pendaftar_kebutuhan_khusus' => ['Jumlah Calon Mahasiswa|Pendaftar Kebutuhan Khusus', 'number', 'nullable'],
                'baru_reguler'               => ['Jumlah Mahasiswa Baru|Reguler|Diterima', 'number', 'nullable'],
                'baru_reguler_afirmasi'      => ['Jumlah Mahasiswa Baru|Reguler|Afirmasi', 'number', 'nullable'],
                'baru_reguler_kk'            => ['Jumlah Mahasiswa Baru|Reguler|Kebutuhan Khusus', 'number', 'nullable'],
                'baru_rpl'                   => ['Jumlah Mahasiswa Baru|RPL|Diterima', 'number', 'nullable'],
                'baru_rpl_afirmasi'          => ['Jumlah Mahasiswa Baru|RPL|Afirmasi', 'number', 'nullable'],
                'baru_rpl_kk'                => ['Jumlah Mahasiswa Baru|RPL|Kebutuhan Khusus', 'number', 'nullable'],
                'aktif_reguler'              => ['Jumlah Mahasiswa Aktif|Reguler|Diterima', 'number', 'nullable'],
                'aktif_reguler_afirmasi'     => ['Jumlah Mahasiswa Aktif|Reguler|Afirmasi', 'number', 'nullable'],
                'aktif_reguler_kk'           => ['Jumlah Mahasiswa Aktif|Reguler|Kebutuhan Khusus', 'number', 'nullable'],
                'aktif_rpl'                  => ['Jumlah Mahasiswa Aktif|RPL|Diterima', 'number', 'nullable'],
                'aktif_rpl_afirmasi'         => ['Jumlah Mahasiswa Aktif|RPL|Afirmasi', 'number', 'nullable'],
                'aktif_rpl_kk'               => ['Jumlah Mahasiswa Aktif|RPL|Kebutuhan Khusus', 'number', 'nullable'],
            ],
        ],
        't2a2_asal_mahasiswa' => [
            'judul' => '2.A.2 Keragaman Asal Mahasiswa', 'kelompok' => 'k2', 'ringkasan' => ['jumlah'],
            'kolom' => array_merge([
                'kategori' => ['Asal Mahasiswa|Kategori', 'select', 'required', ['Kota/Kab sama dengan PS', 'Kota/Kabupaten Lain', 'Provinsi Lain', 'Negara Lain', 'Afirmasi', 'Berkebutuhan Khusus']],
                'asal'     => ['Asal Mahasiswa|Nama Daerah/Negara', 'text', 'nullable'],
            ], $perTs('Jumlah Mahasiswa Baru')),
        ],
        't2a3_kondisi_mahasiswa' => [
            'judul' => '2.A.3 Kondisi Jumlah Mahasiswa', 'kelompok' => 'k2',
            'kolom' => array_merge([
                'kondisi' => ['Kondisi', 'select', 'required', ['Mahasiswa Baru', 'Mahasiswa Aktif pada saat TS', 'Lulus pada saat TS', 'Mengundurkan Diri/DO pada saat TS']],
            ], $perTs(), [
                'jumlah'     => ['Jumlah', 'number', 'nullable'],
            ]),
            'total' => ['jumlah' => ['ts2', 'ts1', 'ts']],
        ],
        't2b1_isi_pembelajaran' => [
            'judul' => '2.B.1 Tabel Isi Pembelajaran', 'kelompok' => 'k2',
            'kolom' => array_merge([
                'kode_mk'  => ['Kode MK', 'text', 'required'],
                'nama_mk'  => ['Mata Kuliah', 'text', 'required'],
                'sks'      => ['SKS', 'number', 'required'],
                'semester' => ['Semester', 'select', 'required', ['I', 'II', 'III', 'IV', 'V', 'VI']],
            ], $pl),
        ],
        't2b2_cpl_pl' => [
            'judul' => '2.B.2 Pemetaan Capaian Pembelajaran Lulusan dan Profil Lulusan', 'kelompok' => 'k2',
            'kolom' => array_merge(['cpl' => ['CPL', 'text', 'required']], array_map(
                fn ($d) => [str_replace('Profil Lulusan (PL)|', '', $d[0]), $d[1], $d[2]], $pl
            )),
        ],
        't2b3_peta_cpl' => [
            'judul' => '2.B.3 Peta Pemenuhan CPL', 'kelompok' => 'k2',
            'kolom' => [
                'cpl'        => ['CPL', 'text', 'required'],
                'cpmk'       => ['CPMK', 'text', 'nullable'],
                'semester_1' => ['Semester 1', 'text', 'nullable'],
                'semester_2' => ['Semester 2', 'text', 'nullable'],
                'semester_3' => ['Semester 3', 'text', 'nullable'],
                'semester_4' => ['Semester 4', 'text', 'nullable'],
                'semester_5' => ['Semester 5', 'text', 'nullable'],
                'semester_6' => ['Semester 6', 'text', 'nullable'],
            ],
        ],
        't2b4_masa_tunggu' => [
            'judul' => '2.B.4 Rata-rata Masa Tunggu Lulusan untuk Bekerja Pertama Kali', 'kelompok' => 'k2',
            'ringkasan' => ['jumlah'],
            'kolom' => [
                'tahun_lulus'      => ['Tahun Lulus', 'select', 'required', $ts3],
                'jumlah_lulusan'   => ['Jumlah Lulusan', 'number', 'required'],
                'terlacak'         => ['Jumlah Lulusan yang Terlacak', 'number', 'required'],
                'rata_masa_tunggu' => ['Rata-rata Waktu Tunggu (Bulan)', 'decimal', 'nullable'],
            ],
        ],
        't2b5_bidang_kerja' => [
            'judul' => '2.B.5 Kesesuaian Bidang Kerja Lulusan', 'kelompok' => 'k2', 'ringkasan' => ['jumlah'],
            'kolom' => [
                'tahun_lulus'          => ['Tahun Lulus', 'select', 'required', $ts3],
                'jumlah_lulusan'       => ['Jumlah Lulusan', 'number', 'required'],
                'terlacak'             => ['Jumlah Lulusan yang Terlacak', 'number', 'required'],
                'profesi_infokom'      => ['Profesi Kerja Bidang Infokom', 'number', 'nullable'],
                'profesi_non_infokom'  => ['Profesi Kerja Bidang Non Infokom', 'number', 'nullable'],
                'tempat_multinasional' => ['Lingkup Tempat Kerja|Multinasional/Internasional', 'number', 'nullable'],
                'tempat_nasional'      => ['Lingkup Tempat Kerja|Nasional', 'number', 'nullable'],
                'tempat_wirausaha'     => ['Lingkup Tempat Kerja|Wirausaha', 'number', 'nullable'],
            ],
        ],
        't2b6_kepuasan_pengguna' => [
            'judul' => '2.B.6 Kepuasan Pengguna Lulusan', 'kelompok' => 'k2', 'ringkasan' => ['jumlah'],
            'kolom' => [
                'jenis_kemampuan' => ['Jenis Kemampuan', 'select', 'required', [
                    'Kerjasama Tim', 'Keahlian di Bidang Prodi', 'Kemampuan Berbahasa Asing (Inggris)',
                    'Kemampuan Berkomunikasi', 'Pengembangan Diri', 'Kepemimpinan', 'Etos Kerja',
                ]],
                'sangat_baik'   => ['Tingkat Kepuasan Pengguna (%)|Sangat Baik', 'decimal', 'nullable'],
                'baik'          => ['Tingkat Kepuasan Pengguna (%)|Baik', 'decimal', 'nullable'],
                'cukup'         => ['Tingkat Kepuasan Pengguna (%)|Cukup', 'decimal', 'nullable'],
                'kurang'        => ['Tingkat Kepuasan Pengguna (%)|Kurang', 'decimal', 'nullable'],
                'tindak_lanjut' => ['Rencana Tindak Lanjut oleh UPPS/PS', 'textarea', 'nullable'],
            ],
        ],
        't2c_fleksibilitas' => [
            'judul' => '2.C Fleksibilitas Dalam Proses Pembelajaran', 'kelompok' => 'k2',
            'kolom' => array_merge([
                'bentuk' => ['Bentuk Pembelajaran', 'select', 'required', [
                    'Jumlah Mahasiswa Aktif', 'Micro-credensial', 'RPL tipe A-2',
                    'Pembelajaran di PS lain', 'Pembelajaran di PT lain', 'CBL/PBL', 'Lainnya',
                ]],
                'keterangan' => ['Keterangan (jika Lainnya)', 'text', 'nullable'],
            ], $perTs('Jumlah Mahasiswa')),
        ],
        't2d_rekognisi_lulusan' => [
            'judul' => '2.D Rekognisi dan Apresiasi Kompetensi Lulusan', 'kelompok' => 'k2', 'ringkasan' => ['jumlah'],
            'kolom' => array_merge([
                'sumber_rekognisi' => ['Sumber Rekognisi', 'select', 'required', ['Masyarakat', 'Dunia Usaha', 'Dunia Industri', 'Dunia Kerja', 'Lainnya']],
                'jenis_pengakuan'  => ['Jenis Pengakuan Lulusan (Rekognisi)', 'text', 'required'],
            ], $perTs('Tahun Akademik')),
        ],

        // ======================= TABEL 3 =======================
        't3a1_sarpras_penelitian' => [
            'judul' => '3.A.1 Sarana dan Prasarana Penelitian', 'kelompok' => 'k3',
            'kolom' => $sarpras,
        ],
        't3a2_penelitian_dtpr' => [
            'judul' => '3.A.2 Penelitian DTPR, Hibah dan Pembiayaan Penelitian', 'kelompok' => 'k3', 'ringkasan' => ['jumlah'],
            'kolom' => $hibah('Nama DTPR (Ketua)', 'Judul Penelitian', 'Jenis Hibah Penelitian'),
        ],
        't3a3_pengembangan_dtpr' => [
            'judul' => '3.A.3 Pengembangan DTPR di Bidang Penelitian', 'kelompok' => 'k3', 'ringkasan' => ['jumlah'],
            'kolom' => array_merge([
                'jenis_pengembangan' => ['Jenis Pengembangan DTPR', 'text', 'required'],
                'nama_dtpr'          => ['Nama DTPR', 'text', 'required'],
            ], $perTs('Tahun Akademik (√)', 'check')),
        ],
        't3c1_kerjasama_penelitian' => [
            'judul' => '3.C.1 Kerjasama Penelitian', 'kelompok' => 'k3', 'ringkasan' => ['jumlah'],
            'kolom' => $kerjasama,
        ],
        't3c2_publikasi' => [
            'judul' => '3.C.2 Publikasi Penelitian', 'kelompok' => 'k3', 'ringkasan' => ['jumlah'],
            'kolom' => array_merge([
                'nama_dtpr'       => ['Nama DTPR', 'text', 'required'],
                'judul_publikasi' => ['Judul Publikasi', 'text', 'required'],
                'jenis_publikasi' => ['Jenis Publikasi (IB/I/S1–S6/T)', 'select', 'required', ['IB', 'I', 'S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'T']],
            ], $perTs('Tahun Terbit (√)', 'check')),
        ],
        't3c3_hki_penelitian' => [
            'judul' => '3.C.3 Perolehan HKI (Granted)', 'kelompok' => 'k3', 'ringkasan' => ['jumlah'],
            'kolom' => $hki,
        ],

        // ======================= TABEL 4 =======================
        't4a1_sarpras_pkm' => [
            'judul' => '4.A.1 Sarana dan Prasarana PkM', 'kelompok' => 'k4',
            'kolom' => $sarpras,
        ],
        't4a2_pkm_dtpr' => [
            'judul' => '4.A.2 PkM DTPR, Hibah dan Pembiayaan PkM', 'kelompok' => 'k4', 'ringkasan' => ['jumlah'],
            'kolom' => $hibah('Nama DTPR (Sebagai Ketua PkM)', 'Judul PkM', 'Jenis Hibah PkM'),
        ],
        't4c1_kerjasama_pkm' => [
            'judul' => '4.C.1 Kerjasama PkM', 'kelompok' => 'k4', 'ringkasan' => ['jumlah'],
            'kolom' => $kerjasama,
        ],
        't4c2_diseminasi_pkm' => [
            'judul' => '4.C.2 Diseminasi Hasil PkM', 'kelompok' => 'k4', 'ringkasan' => ['jumlah'],
            'kolom' => array_merge([
                'nama_dtpr'  => ['Nama DTPR', 'text', 'required'],
                'judul'      => ['Judul', 'text', 'required'],
                'diseminasi' => ['Diseminasi Hasil PkM (L/N/I)', 'select', 'required', $lni],
            ], $perTs('Tahun (√)', 'check')),
        ],
        't4c3_hki_pkm' => [
            'judul' => '4.C.3 Perolehan HKI PkM', 'kelompok' => 'k4', 'ringkasan' => ['jumlah'],
            'kolom' => $hki,
        ],

        // ======================= TABEL 5 =======================
        't5_1_tata_kelola' => [
            'judul' => '5.1 Sistem Tata Kelola', 'kelompok' => 'k5',
            'kolom' => [
                'jenis_tata_kelola' => ['Jenis Tata Kelola', 'text', 'required'],
                'nama_sistem'       => ['Nama Sistem Informasi', 'text', 'required'],
                'akses'             => ['Akses (Lokal/Internet)', 'select', 'nullable', ['Lokal', 'Internet']],
                'unit_pengelola'    => ['Unit Kerja/SDM Pengelola', 'text', 'nullable'],
            ],
        ],
        't5_2_sarpras_pendidikan' => [
            'judul' => '5.2 Sarana dan Prasarana Pendidikan', 'kelompok' => 'k5',
            'kolom' => $sarpras,
        ],

        // ======================= TABEL 6 =======================
        't6_visi_misi' => [
            'judul' => '6 Kesesuaian Visi, Misi', 'kelompok' => 'k6',
            'kolom' => [
                'visi_pt'       => ['Visi PT', 'textarea', 'required'],
                'visi_upps'     => ['Visi UPPS', 'textarea', 'required'],
                'visi_keilmuan' => ['Visi Keilmuan PS', 'textarea', 'required'],
                'misi_pt'       => ['Misi PT', 'textarea', 'nullable'],
                'misi_upps'     => ['Misi UPPS', 'textarea', 'nullable'],
            ],
        ],
    ],
];
EOF

tulis config/lkps_excel.php <<'EOF'
<?php
/*
|--------------------------------------------------------------------------
| Pemetaan tabel LKPS ke template Excel LAM Infokom (Data_DKPS ... .xlsx)
|--------------------------------------------------------------------------
| sheet   : nama sheet di template
| mulai   : baris data pertama
| kolom   : nama_kolom_database => huruf kolom Excel
| no      : kolom nomor urut (opsional)
| kunci   : baris tetap yang dicocokkan berdasarkan label (mis. TS-2, TS-1, TS)
| tetap   : baris khusus untuk satu nilai tertentu (2.C Jumlah Mahasiswa Aktif)
| lainnya : nilai di luar pilihan disimpan sebagai "Lainnya" + keterangan
| mode    : 'asal' (2.A.2, dikelompokkan per kategori) atau 'sel' (Tabel 6)
| lampiran_bukti dipetakan ke kolom "Link Bukti" di template: saat ekspor berisi
| link pratinjau lampiran; saat impor kolom ini dilewati (berkas tidak bisa diimpor).
*/

$sarpras = ['mulai' => 5, 'kolom' => [
    'nama_prasarana' => 'A', 'daya_tampung' => 'B', 'luas_ruang' => 'C', 'kepemilikan' => 'D',
    'lisensi' => 'E', 'perangkat' => 'F', 'lampiran_bukti' => 'H',
]];
$hibah = ['mulai' => 6, 'no' => 'A', 'kolom' => [
    'nama_dtpr' => 'B', 'judul' => 'C', 'jumlah_mahasiswa' => 'D', 'jenis_hibah' => 'E', 'sumber' => 'F',
    'durasi' => 'G', 'dana_ts2' => 'H', 'dana_ts1' => 'I', 'dana_ts' => 'J', 'lampiran_bukti' => 'K',
]];
$kerjasama = ['mulai' => 6, 'no' => 'A', 'kolom' => [
    'judul_kerjasama' => 'B', 'mitra' => 'C', 'sumber' => 'D', 'durasi' => 'E',
    'dana_ts2' => 'F', 'dana_ts1' => 'G', 'dana_ts' => 'H', 'lampiran_bukti' => 'I',
]];
$hki = ['mulai' => 6, 'no' => 'A', 'kolom' => [
    'judul' => 'B', 'jenis_hki' => 'C', 'nama_dtpr' => 'D', 'ts2' => 'E', 'ts1' => 'F', 'ts' => 'G', 'lampiran_bukti' => 'H',
]];

return [
    't1a1_pimpinan' => ['sheet' => 'Tabel 1.A.1', 'mulai' => 6, 'kolom' => [
        'unit_kerja' => 'A', 'nama_ketua' => 'B', 'periode_jabatan' => 'C',
        'pendidikan_terakhir' => 'D', 'jabatan_fungsional' => 'E', 'tupoksi' => 'F',
    ]],
    't1a2_sumber_dana' => ['sheet' => 'Tabel 1.A.2', 'mulai' => 5, 'kolom' => [
        'sumber_pendanaan' => 'A', 'ts2' => 'B', 'ts1' => 'C', 'ts' => 'D', 'lampiran_bukti' => 'E',
    ]],
    't1a3_penggunaan_dana' => ['sheet' => 'Tabel 1.A.3', 'mulai' => 5, 'kolom' => [
        'penggunaan_dana' => 'A', 'ts2' => 'B', 'ts1' => 'C', 'ts' => 'D', 'lampiran_bukti' => 'E',
    ]],
    't1a4_ewmp' => ['sheet' => 'Tabel 1.A.4', 'mulai' => 8, 'no' => 'A', 'kolom' => [
        'nama_dtpr' => 'B', 'sks_ps_sendiri' => 'C', 'sks_ps_lain' => 'D', 'sks_pt_lain' => 'E',
        'sks_penelitian' => 'F', 'sks_pkm' => 'G', 'sks_manajemen_pt_sendiri' => 'H',
        'sks_manajemen_pt_lain' => 'I', 'total_sks' => 'J',
    ]],
    't1a5_tendik' => ['sheet' => 'Tabel 1.A.5', 'mulai' => 7,
        'kunci' => ['field' => 'jenis', 'kolom' => 'B'],
        'kolom' => [
            's3' => 'C', 's2' => 'D', 's1' => 'E', 'd4' => 'F', 'd3' => 'G', 'd2' => 'H', 'd1' => 'I',
            'sma' => 'J', 'smp' => 'K', 'sd' => 'L', 'unit_kerja' => 'M',
        ]],
    't1b_spmi' => ['sheet' => 'Tabel 1.B', 'mulai' => 6, 'kolom' => [
        'unit_spmi' => 'A', 'nama_unit' => 'B', 'dokumen_spmi' => 'C', 'auditor_internal' => 'D',
        'auditor_certified' => 'E', 'auditor_non_certified' => 'F', 'frekuensi_audit' => 'G',
        'bukti_certified' => 'H', 'laporan_audit' => 'I',
    ]],
    't2a1_data_mahasiswa' => ['sheet' => 'Tabel 2.A.1', 'mulai' => 7,
        'kunci' => ['field' => 'ts', 'kolom' => 'A'],
        'kolom' => [
            'daya_tampung' => 'B', 'pendaftar' => 'C', 'pendaftar_afirmasi' => 'D', 'pendaftar_kebutuhan_khusus' => 'E',
            'baru_reguler' => 'F', 'baru_reguler_afirmasi' => 'G', 'baru_reguler_kk' => 'H',
            'baru_rpl' => 'I', 'baru_rpl_afirmasi' => 'J', 'baru_rpl_kk' => 'K',
            'aktif_reguler' => 'L', 'aktif_reguler_afirmasi' => 'M', 'aktif_reguler_kk' => 'N',
            'aktif_rpl' => 'O', 'aktif_rpl_afirmasi' => 'P', 'aktif_rpl_kk' => 'Q',
        ]],
    't2a2_asal_mahasiswa' => ['sheet' => 'Tabel 2.A.2', 'mulai' => 6, 'mode' => 'asal',
        'kolom' => ['ts2' => 'B', 'ts1' => 'C', 'ts' => 'D', 'lampiran_bukti' => 'E']],
    't2a3_kondisi_mahasiswa' => ['sheet' => 'Tabel 2.A.3', 'mulai' => 5,
        'kunci' => ['field' => 'kondisi', 'kolom' => 'A'],
        'kolom' => ['ts2' => 'B', 'ts1' => 'C', 'ts' => 'D', 'jumlah' => 'E', 'lampiran_bukti' => 'F'],
    ],
    't2b1_isi_pembelajaran' => ['sheet' => 'Tabel 2.B.1', 'mulai' => 6, 'kolom' => [
        'kode_mk' => 'A', 'nama_mk' => 'B', 'sks' => 'C', 'semester' => 'D',
        'pl1' => 'E', 'pl2' => 'F', 'pl3' => 'G', 'pl4' => 'H', 'pl5' => 'I',
    ]],
    't2b2_cpl_pl' => ['sheet' => 'Tabel 2.B.2', 'mulai' => 5, 'kolom' => [
        'cpl' => 'A', 'pl1' => 'B', 'pl2' => 'C', 'pl3' => 'D', 'pl4' => 'E', 'pl5' => 'F',
    ]],
    't2b3_peta_cpl' => ['sheet' => 'Tabel 2.B.3', 'mulai' => 5, 'kolom' => [
        'cpl' => 'A', 'cpmk' => 'B', 'semester_1' => 'C', 'semester_2' => 'D', 'semester_3' => 'E',
        'semester_4' => 'F', 'semester_5' => 'G', 'semester_6' => 'H',
    ]],
    't2b4_masa_tunggu' => ['sheet' => 'Tabel 2.B.4', 'mulai' => 5,
        'kunci' => ['field' => 'tahun_lulus', 'kolom' => 'A'],
        'kolom' => ['jumlah_lulusan' => 'B', 'terlacak' => 'C', 'rata_masa_tunggu' => 'D']],
    't2b5_bidang_kerja' => ['sheet' => 'Tabel 2.B.5', 'mulai' => 6,
        'kunci' => ['field' => 'tahun_lulus', 'kolom' => 'A'],
        'kolom' => [
            'jumlah_lulusan' => 'B', 'terlacak' => 'C', 'profesi_infokom' => 'D', 'profesi_non_infokom' => 'E',
            'tempat_multinasional' => 'F', 'tempat_nasional' => 'G', 'tempat_wirausaha' => 'H',
        ]],
    't2b6_kepuasan_pengguna' => ['sheet' => 'Tabel 2.B.6', 'mulai' => 6,
        'kunci' => ['field' => 'jenis_kemampuan', 'kolom' => 'B'],
        'kolom' => ['sangat_baik' => 'C', 'baik' => 'D', 'cukup' => 'E', 'kurang' => 'F', 'tindak_lanjut' => 'G']],
    't2c_fleksibilitas' => ['sheet' => 'Tabel 2.C', 'mulai' => 7,
        'kolom' => ['bentuk' => 'A', 'ts2' => 'B', 'ts1' => 'C', 'ts' => 'D', 'lampiran_bukti' => 'E'],
        'tetap' => ['field' => 'bentuk', 'nilai' => 'Jumlah Mahasiswa Aktif', 'baris' => 5],
        'lainnya' => ['field' => 'bentuk', 'keterangan' => 'keterangan'],
    ],
    't2d_rekognisi_lulusan' => ['sheet' => 'Tabel 2.D', 'mulai' => 6, 'kolom' => [
        'sumber_rekognisi' => 'A', 'jenis_pengakuan' => 'B', 'ts2' => 'C', 'ts1' => 'D', 'ts' => 'E', 'lampiran_bukti' => 'F',
    ]],
    't3a1_sarpras_penelitian' => ['sheet' => 'Tabel 3.A.1'] + $sarpras,
    't3a2_penelitian_dtpr' => ['sheet' => 'Tabel 3.A.2'] + $hibah,
    't3a3_pengembangan_dtpr' => ['sheet' => 'Tabel 3.A.3', 'mulai' => 7,
        'kolom' => ['jenis_pengembangan' => 'A', 'nama_dtpr' => 'B', 'ts2' => 'C', 'ts1' => 'D', 'ts' => 'E', 'lampiran_bukti' => 'F'],
    ],
    't3c1_kerjasama_penelitian' => ['sheet' => 'Tabel 3.C.1'] + $kerjasama,
    't3c2_publikasi' => ['sheet' => 'Tabel 3.C.2', 'mulai' => 6, 'no' => 'A',
        'kolom' => [
            'nama_dtpr' => 'B', 'judul_publikasi' => 'C', 'jenis_publikasi' => 'D',
            'ts2' => 'E', 'ts1' => 'F', 'ts' => 'G', 'lampiran_bukti' => 'H',
        ],
    ],
    't3c3_hki_penelitian' => ['sheet' => 'Tabel 3.C.3'] + $hki,
    't4a1_sarpras_pkm' => ['sheet' => 'Tabel 4.A.1'] + $sarpras,
    't4a2_pkm_dtpr' => ['sheet' => 'Tabel 4.A.2'] + $hibah,
    't4c1_kerjasama_pkm' => ['sheet' => 'Tabel 4.C.1'] + $kerjasama,
    't4c2_diseminasi_pkm' => ['sheet' => 'Tabel 4.C.2', 'mulai' => 5, 'no' => 'A',
        'kolom' => [
            'nama_dtpr' => 'B', 'judul' => 'D', 'diseminasi' => 'E',
            'ts2' => 'F', 'ts1' => 'G', 'ts' => 'H', 'lampiran_bukti' => 'I',
        ],
    ],
    't4c3_hki_pkm' => ['sheet' => 'Tabel 4.C.3'] + $hki,
    't5_1_tata_kelola' => ['sheet' => 'Tabel 5.1', 'mulai' => 5, 'no' => 'A', 'kolom' => [
        'jenis_tata_kelola' => 'B', 'nama_sistem' => 'C', 'akses' => 'D', 'unit_pengelola' => 'E', 'lampiran_bukti' => 'F',
    ]],
    't5_2_sarpras_pendidikan' => ['sheet' => 'Tabel 5.2'] + $sarpras,
    't6_visi_misi' => ['sheet' => 'Tabel 6', 'mode' => 'sel', 'sel' => [
        'visi_pt' => 'A5', 'visi_upps' => 'B5', 'visi_keilmuan' => 'C5', 'misi_pt' => 'A7', 'misi_upps' => 'B7',
    ]],
];
EOF

tulis app/Support/Lkps.php <<'EOF'
<?php

namespace App\Support;

use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\Rule;

class Lkps
{
    /** Disk privat untuk lampiran bukti (storage/app/private); diakses lewat route pratinjau. */
    public const DISK = 'local';

    /** Kolom lampiran yang otomatis ada di setiap tabel LKPS. */
    public const LAMPIRAN = 'lampiran_bukti';

    /** Batas ukuran unggahan lampiran (KB): 20 MB. */
    public const MAKS_LAMPIRAN_KB = 20480;

    /** Batas unggah efektif dari php.ini (MB), untuk peringatan di form. */
    public static function batasServerMb(): float
    {
        $mb = function (string $v): float {
            $v = trim($v);
            $n = (float) $v;
            return match (strtolower(substr($v, -1))) {
                'g' => $n * 1024, 'k' => $n / 1024, 'm' => $n, default => $n / 1048576,
            };
        };

        return min($mb((string) ini_get('upload_max_filesize')), $mb((string) ini_get('post_max_size')));
    }

    public static function tabel(): array
    {
        return config('lkps.tabel', []);
    }

    public static function definisi(string $slug): array
    {
        $def = self::tabel()[$slug] ?? null;
        abort_if($def === null, 404, 'Tabel LKPS tidak ditemukan.');

        return $def;
    }

    public static function namaTabel(string $slug): string
    {
        return 'lkps_' . $slug;
    }

    /** Kolom yang sudah dinormalisasi: label, type, rules, options. */
    public static function kolom(string $slug): array
    {
        $hasil = [];
        foreach (self::definisi($slug)['kolom'] as $nama => $d) {
            $jalur = array_map('trim', explode('|', $d[0]));
            $hasil[$nama] = [
                'label'   => implode(' – ', $jalur),
                'jalur'   => $jalur,
                'type'    => $d[1] ?? 'text',
                'rules'   => $d[2] ?? 'nullable',
                'options' => $d[3] ?? [],
            ];
        }

        // Setiap baris data punya Lampiran Bukti (PDF/gambar) yang dibuka sebagai pratinjau.
        $hasil[self::LAMPIRAN] ??= [
            'label'   => 'Lampiran Bukti',
            'jalur'   => ['Lampiran Bukti'],
            'type'    => 'file',
            'rules'   => 'nullable',
            'options' => [],
        ];

        // Lampiran Bukti berupa link (opsional; boleh bersama berkas atau sebagai pengganti berkas).
        $hasil['lampiran_link'] ??= [
            'label'   => 'Lampiran Bukti (Link)',
            'jalur'   => ['Lampiran Bukti (Link)'],
            'type'    => 'url',
            'rules'   => 'nullable|url|max:500',
            'options' => [],
        ];

        return $hasil;
    }

    /** Link pratinjau lampiran (bukan link unduh). */
    public static function urlLampiran(string $slug, int $id, string $kolom = self::LAMPIRAN): string
    {
        return route('lkps.lampiran.lihat', [$slug, $id, $kolom]);
    }

    public static function namaKelompok(string $slug): string
    {
        $kode = self::definisi($slug)['kelompok'] ?? '';

        return config("lkps.kelompok.$kode", $kode);
    }

    public static function rules(string $slug, bool $ubah = false): array
    {
        $hasil = [];
        foreach (self::kolom($slug) as $nama => $k) {
            $r = array_values(array_filter(explode('|', $k['rules'])));

            // Saat mengubah data, berkas lama tetap dipakai jika tidak diganti.
            if ($k['type'] === 'file' && $ubah) {
                $r = array_map(fn ($x) => $x === 'required' ? 'nullable' : $x, $r);
            }
            if (! in_array('required', $r, true) && ! in_array('nullable', $r, true)) {
                $r[] = 'nullable';
            }

            $tambahan = match ($k['type']) {
                'number'   => ['integer', 'min:0'],
                'decimal'  => ['numeric'],
                'date'     => ['date'],
                'url'      => ['string', 'max:500'],
                'check'    => ['boolean'],
                'file'     => ['file', 'max:' . self::MAKS_LAMPIRAN_KB, 'mimes:pdf,jpg,jpeg,png,webp'],
                'textarea' => ['string'],
                'select'   => [],
                default    => ['string', 'max:255'],
            };
            foreach ($tambahan as $t) {
                $kunci = explode(':', $t)[0];
                $ada = collect($r)->contains(fn ($x) => is_string($x) && explode(':', $x)[0] === $kunci);
                if (! $ada) {
                    $r[] = $t;
                }
            }
            if ($k['type'] === 'select' && $k['options']) {
                $r[] = Rule::in($k['options']);
            }

            $hasil[$nama] = $r;
        }

        return $hasil;
    }

    public static function label(string $slug): array
    {
        return array_map(fn ($k) => $k['label'], self::kolom($slug));
    }

    /**
     * Header tabel bertingkat seperti di Excel, dari label "Grup|Sub|Kolom".
     * Mengembalikan ['depth' => n, 'baris' => [[['label','colspan','rowspan'], ...], ...]].
     */
    public static function header(string $slug): array
    {
        $jalur = array_values(array_map(fn ($k) => $k['jalur'], self::kolom($slug)));
        $n = count($jalur);
        $depth = $n ? max(array_map('count', $jalur)) : 1;
        $baris = [];

        for ($l = 0; $l < $depth; $l++) {
            $row = [];
            $i = 0;
            while ($i < $n) {
                $p = $jalur[$i];
                if (count($p) <= $l) {
                    $i++;
                    continue;
                }
                if ($l === count($p) - 1) {
                    $row[] = ['label' => $p[$l], 'colspan' => 1, 'rowspan' => $depth - $l];
                    $i++;
                    continue;
                }
                $j = $i + 1;
                while ($j < $n && count($jalur[$j]) > $l + 1
                    && array_slice($jalur[$j], 0, $l + 1) === array_slice($p, 0, $l + 1)) {
                    $j++;
                }
                $row[] = ['label' => $p[$l], 'colspan' => $j - $i, 'rowspan' => 1];
                $i = $j;
            }
            $baris[] = $row;
        }

        return ['depth' => $depth, 'baris' => $baris];
    }

    /** Baris Jumlah / Rata-rata di bawah tabel, sesuai 'ringkasan' di config. */
    public static function ringkasan(string $slug, iterable $rows): array
    {
        $jenis = self::definisi($slug)['ringkasan'] ?? [];
        if (! $jenis) {
            return [];
        }
        $kolom = self::kolom($slug);
        $jumlah = [];
        $isi = [];
        foreach ($kolom as $n => $k) {
            if (in_array($k['type'], ['number', 'decimal', 'check'], true)) {
                $jumlah[$n] = 0;
                $isi[$n] = 0;
            }
        }
        foreach ($rows as $r) {
            foreach (array_keys($jumlah) as $n) {
                $v = $r->$n ?? null;
                if ($kolom[$n]['type'] === 'check') {
                    $jumlah[$n] += $v ? 1 : 0;
                } elseif ($v !== null && $v !== '') {
                    $jumlah[$n] += (float) $v;
                    $isi[$n]++;
                }
            }
        }

        $hasil = [];
        if (in_array('jumlah', $jenis, true)) {
            $hasil['Jumlah'] = $jumlah;
        }
        if (in_array('rata', $jenis, true)) {
            $rata = [];
            foreach ($jumlah as $n => $v) {
                $rata[$n] = $kolom[$n]['type'] !== 'check' && $isi[$n] ? $v / $isi[$n] : null;
            }
            $hasil['Rata-rata'] = $rata;
        }

        return $hasil;
    }

    /** Format angka gaya Indonesia, maksimal 2 desimal. */
    public static function angka(mixed $v): string
    {
        if ($v === null || $v === '' || ! is_numeric($v)) {
            return (string) $v;
        }
        $s = number_format((float) $v, 2, ',', '.');

        return str_ends_with($s, ',00') ? substr($s, 0, -3) : rtrim($s, '0');
    }

    /** Menu sidebar & dashboard: tabel dikelompokkan per kriteria. */
    public static function perKelompok(): array
    {
        $grup = [];
        foreach (config('lkps.kelompok', []) as $kode => $nama) {
            $grup[$kode] = ['nama' => $nama, 'tabel' => []];
        }
        foreach (self::tabel() as $slug => $def) {
            if (! empty($def['tersembunyi'])) {
                continue;   // tidak ditampilkan sebagai tabel LKPS (mis. Daftar Dosen Homebase di halaman Identitas)
            }
            $kode = $def['kelompok'] ?? 'lainnya';
            $grup[$kode] ??= ['nama' => ucfirst($kode), 'tabel' => []];
            $grup[$kode]['tabel'][$slug] = $def['judul'];
        }

        return array_filter($grup, fn ($g) => ! empty($g['tabel']));
    }

    /** Buat tabel/kolom yang belum ada. Tidak pernah menghapus data. */
    public static function sinkron(): array
    {
        $log = [];
        foreach (self::tabel() as $slug => $def) {
            $nama = self::namaTabel($slug);
            $kolom = self::kolom($slug);

            if (! Schema::hasTable($nama)) {
                Schema::create($nama, function (Blueprint $t) use ($kolom) {
                    $t->id();
                    foreach ($kolom as $n => $k) {
                        self::buatKolom($t, $n, $k['type']);
                    }
                    $t->unsignedBigInteger('created_by')->nullable();
                    $t->timestamps();
                });
                $log[] = "Tabel {$nama} dibuat.";
                continue;
            }

            foreach ($kolom as $n => $k) {
                if (! Schema::hasColumn($nama, $n)) {
                    Schema::table($nama, fn (Blueprint $t) => self::buatKolom($t, $n, $k['type']));
                    $log[] = "Kolom {$nama}.{$n} ditambahkan.";
                }
            }
        }

        if (! Schema::hasTable('lkps_isian')) {
            Schema::create('lkps_isian', function (Blueprint $t) {
                $t->id();
                $t->string('kunci')->unique();
                $t->text('nilai')->nullable();
                $t->timestamps();
            });
            $log[] = 'Tabel lkps_isian dibuat.';
        }

        return $log ?: ['Semua tabel LKPS sudah sesuai konfigurasi.'];
    }

    private static function buatKolom(Blueprint $t, string $nama, string $type): void
    {
        $kolom = match ($type) {
            'textarea'    => $t->text($nama),
            'number'      => $t->integer($nama),
            'decimal'     => $t->decimal($nama, 15, 2),
            'check'       => $t->boolean($nama)->default(false),
            'date'        => $t->date($nama),
            'file', 'url' => $t->string($nama, 500),
            default       => $t->string($nama),
        };
        $kolom->nullable();
    }
}
EOF

tulis app/Support/LkpsExcel.php <<'EOF'
<?php

namespace App\Support;

use PhpOffice\PhpSpreadsheet\Cell\DataType;
use PhpOffice\PhpSpreadsheet\IOFactory;
use PhpOffice\PhpSpreadsheet\RichText\RichText;
use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Worksheet\Worksheet;

/**
 * Membaca dan menulis 31 tabel LKPS dari/ke template Excel LAM Infokom.
 * Kelas ini tidak menyentuh database: masukan dan keluarannya berupa array
 * [slug_tabel => [ [kolom => nilai], ... ]].
 */
class LkpsExcel
{
    public array $catatan = [];

    /** Isian di luar tabel (sheet Identitas, Jumlah Dosen DTPR) hasil impor terakhir. */
    public array $isian = [];

    private const CENTANG = '√';
    private const PLACEHOLDER = ['link bukti', 'bukti link', 'linik bukti', '…', '...', '-'];
    private const POLA_FOOTER = '/^(jumlah|keterangan|total|rata-rata|persentase|l\s*:\s*lokal|\*)/iu';

    /**
     * @param array $tabel  config('lkps.tabel')
     * @param array $peta   config('lkps_excel')
     * @param array $isian  config('lkps.isian') : [grup => [kunci => [label, tipe, sheet, sel]]]
     */
    public function __construct(private array $tabel, private array $peta, private array $defIsian = [])
    {
    }

    private function semuaIsian(): array
    {
        $hasil = [];
        foreach ($this->defIsian as $daftar) {
            $hasil += $daftar;
        }

        return $hasil;
    }

    // =====================================================================
    // EKSPOR
    // =====================================================================

    public function ekspor(string $template, array $data, array $isian = []): Spreadsheet
    {
        $book = IOFactory::load($template);

        foreach ($this->semuaIsian() as $kunci => [$label, $tipe, $sheet, $sel]) {
            if ($ws = $book->getSheetByName($sheet)) {
                $this->setSel($ws, $sel, $isian[$kunci] ?? null, $tipe);
            }
        }

        foreach ($this->peta as $slug => $p) {
            $ws = $book->getSheetByName($p['sheet']);
            if (! $ws) {
                $this->catatan[] = "Sheet \"{$p['sheet']}\" tidak ada di template, dilewati.";
                continue;
            }
            $rows = array_values($data[$slug] ?? []);

            match ($this->mode($p)) {
                'sel'   => $this->tulisSel($ws, $slug, $p, $rows),
                'kunci' => $this->tulisKunci($ws, $slug, $p, $rows),
                'asal'  => $this->tulisAsal($ws, $slug, $p, $rows),
                default => $this->tulisDaftar($ws, $slug, $p, $rows),
            };
        }

        $book->setActiveSheetIndex(0);

        return $book;
    }

    private function tulisDaftar(Worksheet $ws, string $slug, array $p, array $rows): void
    {
        $kolom = $this->kolom($slug);

        if (isset($p['tetap'])) {
            $t = $p['tetap'];
            foreach ($rows as $i => $r) {
                if (($r[$t['field']] ?? null) === $t['nilai']) {
                    $this->tulisBaris($ws, $t['baris'], $p, $kolom, $r, null, $t['field']);
                    unset($rows[$i]);
                }
            }
            $rows = array_values($rows);
        }

        $lines = array_map(fn ($r) => [null, $r], $rows);
        $this->tulisBlok($ws, $p, $kolom, $lines);
    }

    /** 2.A.2: baris dikelompokkan per kategori asal mahasiswa. */
    private function tulisAsal(Worksheet $ws, string $slug, array $p, array $rows): void
    {
        $kolom = $this->kolom($slug);
        $lines = [];
        foreach ($kolom['kategori']['options'] as $kat) {
            $grup = array_values(array_filter($rows, fn ($r) => ($r['kategori'] ?? '') === $kat));
            $utama = null;
            $anak = [];
            foreach ($grup as $g) {
                if ($utama === null && trim((string) ($g['asal'] ?? '')) === '') {
                    $utama = $g;
                } else {
                    $anak[] = $g;
                }
            }
            $lines[] = [$kat, $utama];
            foreach ($anak as $a) {
                $lines[] = [($a['asal'] ?? '') !== '' ? $a['asal'] : $kat, $a];
            }
        }
        $this->tulisBlok($ws, $p, $kolom, $lines, 'A');
    }

    /** Menulis sekumpulan baris mulai dari $p['mulai'], menyisipkan baris bila perlu. */
    private function tulisBlok(Worksheet $ws, array $p, array $kolom, array $lines, ?string $kolomLabel = null): void
    {
        $mulai = $p['mulai'];
        $n = count($lines);
        $footer = $this->footer($ws, $mulai);

        if ($footer !== null && $n > $footer - $mulai) {
            $sisip = $n - ($footer - $mulai);
            // Sisipkan di atas baris data terakhir agar rumus SUM/AVERAGE ikut melebar.
            $posisi = $footer - 1 > $mulai ? $footer - 1 : $footer;
            $ws->insertNewRowBefore($posisi, $sisip);
            $footer += $sisip;
        }

        $akhir = $footer !== null
            ? $footer - 1
            : max($mulai + $n - 1, $this->barisTerakhirTerisi($ws, $p, $mulai, $kolomLabel));
        $this->kosongkan($ws, $p, $mulai, $akhir, $kolomLabel);

        foreach ($lines as $i => [$label, $r]) {
            $baris = $mulai + $i;
            if ($kolomLabel !== null) {
                $ws->getCell($kolomLabel . $baris)->setValueExplicit((string) $label, DataType::TYPE_STRING);
            }
            if ($r !== null) {
                $this->tulisBaris($ws, $baris, $p, $kolom, $r, $i + 1);
            }
        }
    }

    private function tulisKunci(Worksheet $ws, string $slug, array $p, array $rows): void
    {
        $kolom = $this->kolom($slug);
        $peta = $this->petaLabel($ws, $p);

        foreach ($rows as $r) {
            $label = (string) ($r[$p['kunci']['field']] ?? '');
            $baris = $this->cariLabel($peta, $label);
            if ($baris === null) {
                $this->catatan[] = "{$p['sheet']}: baris \"{$label}\" tidak ada di template, dilewati.";
                continue;
            }
            $this->tulisBaris($ws, $baris, $p, $kolom, $r, null);
        }
    }

    private function tulisSel(Worksheet $ws, string $slug, array $p, array $rows): void
    {
        $kolom = $this->kolom($slug);
        $r = $rows[0] ?? [];
        if (count($rows) > 1) {
            $this->catatan[] = "{$p['sheet']}: hanya baris pertama yang diekspor.";
        }
        foreach ($p['sel'] as $field => $ref) {
            $this->setSel($ws, $ref, $r[$field] ?? null, $kolom[$field]['type'] ?? 'text');
        }
    }

    private function tulisBaris(Worksheet $ws, int $baris, array $p, array $kolom, array $r, ?int $no, ?string $lewati = null): void
    {
        if ($no !== null && isset($p['no'])) {
            $ws->getCell($p['no'] . $baris)->setValue($no);
        }

        foreach ($p['kolom'] as $field => $col) {
            if ($field === $lewati) {
                continue;
            }
            $v = $r[$field] ?? null;
            if (isset($p['lainnya']) && $field === $p['lainnya']['field'] && $v === 'Lainnya'
                && ! empty($r[$p['lainnya']['keterangan']])) {
                $v = $r[$p['lainnya']['keterangan']];
            }
            $this->setSel($ws, $col . $baris, $v, $kolom[$field]['type'] ?? 'text');
        }

        if (isset($p['centang'])) {
            $nilai = $r[$p['centang']['field']] ?? null;
            foreach ($p['centang']['kolom'] as $opsi => $col) {
                $ws->getCell($col . $baris)->setValue($nilai === $opsi ? self::CENTANG : null);
            }
        }

        foreach ($p['jumlah'] ?? [] as $col => $fields) {
            $ada = array_filter($fields, fn ($f) => ($r[$f] ?? null) !== null && $r[$f] !== '');
            $ws->getCell($col . $baris)->setValue(
                $ada ? array_sum(array_map(fn ($f) => (float) ($r[$f] ?? 0), $fields)) : null
            );
        }
    }

    private function setSel(Worksheet $ws, string $ref, mixed $v, string $type): void
    {
        $cell = $ws->getCell($ref);
        if ($type === 'check') {
            $cell->setValue($v ? self::CENTANG : null);
            return;
        }
        if ($v === null || $v === '') {
            $cell->setValue(null);
            return;
        }
        if (in_array($type, ['number', 'decimal'], true) && is_numeric($v)) {
            $cell->setValueExplicit($v + 0, DataType::TYPE_NUMERIC);
            return;
        }
        // Teks selalu ditulis eksplisit agar isian yang diawali "=" tidak menjadi rumus.
        $cell->setValueExplicit((string) $v, DataType::TYPE_STRING);
        if (in_array($type, ['url', 'file'], true) && preg_match('#^https?://\S+$#i', (string) $v)) {
            $cell->getHyperlink()->setUrl((string) $v);
        }
    }

    private function kosongkan(Worksheet $ws, array $p, int $dari, int $sampai, ?string $kolomLabel): void
    {
        $cols = array_values($p['kolom']);
        if (isset($p['no'])) {
            $cols[] = $p['no'];
        }
        if ($kolomLabel) {
            $cols[] = $kolomLabel;
        }
        $cols = array_merge($cols, array_values($p['centang']['kolom'] ?? []), array_keys($p['jumlah'] ?? []));
        for ($r = $dari; $r <= $sampai; $r++) {
            foreach (array_unique($cols) as $c) {
                $ws->getCell($c . $r)->setValue(null);
            }
        }
    }

    private function barisTerakhirTerisi(Worksheet $ws, array $p, int $mulai, ?string $kolomLabel): int
    {
        $cols = array_values($p['kolom']);
        if ($kolomLabel) {
            $cols[] = $kolomLabel;
        }
        $akhir = $mulai - 1;
        $max = min($ws->getHighestDataRow(), $mulai + 5000);
        for ($r = $mulai; $r <= $max; $r++) {
            foreach ($cols as $c) {
                if (trim((string) $this->nilaiMentah($ws, $c . $r)) !== '') {
                    $akhir = $r;
                    break;
                }
            }
        }

        return $akhir;
    }

    // =====================================================================
    // IMPOR
    // =====================================================================

    public function impor(string $file): array
    {
        $reader = IOFactory::createReaderForFile($file);
        $reader->setReadDataOnly(true);
        $book = $reader->load($file);
        $hasil = [];

        $this->isian = [];
        foreach ($this->semuaIsian() as $kunci => [$label, $tipe, $sheet, $sel]) {
            if ($ws = $book->getSheetByName($sheet)) {
                $v = $this->bacaNilai($ws, $sel, $tipe);
                if ($v !== null) {
                    $this->isian[$kunci] = $tipe === 'number' ? $v : (string) $v;
                }
            }
        }

        foreach ($this->peta as $slug => $p) {
            $ws = $book->getSheetByName($p['sheet']);
            if (! $ws) {
                $this->catatan[] = "Sheet \"{$p['sheet']}\" tidak ditemukan di file, dilewati.";
                continue;
            }
            $rows = match ($this->mode($p)) {
                'sel'   => $this->bacaSel($ws, $slug, $p),
                'kunci' => $this->bacaKunci($ws, $slug, $p),
                'asal'  => $this->bacaAsal($ws, $slug, $p),
                default => $this->bacaDaftar($ws, $slug, $p),
            };
            $hasil[$slug] = array_map(fn ($r) => $this->lengkapiKolom($slug, $r), $rows);
        }

        return $hasil;
    }

    private function bacaDaftar(Worksheet $ws, string $slug, array $p): array
    {
        $kolom = $this->kolom($slug);
        $rows = [];

        if (isset($p['tetap'])) {
            $t = $p['tetap'];
            $r = $this->bacaBaris($ws, $t['baris'], $p, $kolom, $t['field']);
            if ($r !== null) {
                $r[$t['field']] = $t['nilai'];
                $rows[] = $r;
            }
        }

        $mulai = $p['mulai'];
        $footer = $this->footer($ws, $mulai);
        $akhir = $footer !== null ? $footer - 1 : min($ws->getHighestDataRow(), $mulai + 5000);
        $kosong = 0;

        for ($b = $mulai; $b <= $akhir; $b++) {
            // Minimal dua isian: baris yang hanya berisi label bawaan template (mis. "Yayasan") dilewati.
            $r = $this->bacaBaris($ws, $b, $p, $kolom, null, 2);
            if ($r === null) {
                if ($footer === null && ++$kosong >= 30) {
                    break;
                }
                continue;
            }
            $kosong = 0;
            if ($this->wajibTerisi($slug, $r, $b, $p['sheet'])) {
                $rows[] = $r;
            }
        }

        return $rows;
    }

    private function bacaKunci(Worksheet $ws, string $slug, array $p): array
    {
        $kolom = $this->kolom($slug);
        $field = $p['kunci']['field'];
        $opsi = [];
        foreach ($kolom[$field]['options'] as $o) {
            $opsi[$this->norm($o)] = $o;
        }

        $rows = [];
        foreach ($this->petaLabel($ws, $p) as $label => $baris) {
            $r = $this->bacaBaris($ws, $baris, $p, $kolom);
            if ($r === null) {
                continue;
            }
            $cocok = $this->cariLabel($opsi, $label);
            $r[$field] = $cocok ?? trim((string) $this->nilaiMentah($ws, $p['kunci']['kolom'] . $baris));
            $rows[] = $r;
        }

        return $rows;
    }

    private function bacaAsal(Worksheet $ws, string $slug, array $p): array
    {
        $kolom = $this->kolom($slug);
        $kategori = [];
        foreach ($kolom['kategori']['options'] as $o) {
            $kategori[$this->norm($o)] = $o;
        }

        $rows = [];
        $sekarang = null;
        $footer = $this->footer($ws, $p['mulai']) ?? $p['mulai'] + 200;
        for ($b = $p['mulai']; $b < $footer; $b++) {
            $label = trim((string) $this->nilaiMentah($ws, 'A' . $b));
            $r = $this->bacaBaris($ws, $b, $p, $kolom);
            $kat = $kategori[$this->norm($label)] ?? null;
            if ($kat !== null) {
                $sekarang = $kat;
                if ($r !== null) {
                    $rows[] = ['kategori' => $kat, 'asal' => null] + $r;
                }
                continue;
            }
            if ($r !== null && $sekarang !== null && ! in_array(mb_strtolower($label), self::PLACEHOLDER, true)) {
                $rows[] = ['kategori' => $sekarang, 'asal' => $label !== '' ? $label : null] + $r;
            }
        }

        return $rows;
    }

    private function bacaSel(Worksheet $ws, string $slug, array $p): array
    {
        $kolom = $this->kolom($slug);
        $r = [];
        foreach ($p['sel'] as $field => $ref) {
            $r[$field] = $this->bacaNilai($ws, $ref, $kolom[$field]['type'] ?? 'text');
        }

        return array_filter($r, fn ($v) => $v !== null) ? [$r] : [];
    }

    /** Mengembalikan null bila semua kolom yang dipetakan kosong. */
    private function bacaBaris(Worksheet $ws, int $baris, array $p, array $kolom, ?string $lewati = null, int $minIsi = 1): ?array
    {
        $r = [];
        $ada = false;
        foreach ($p['kolom'] as $field => $col) {
            if ($field === $lewati || ($kolom[$field]['type'] ?? '') === 'file') {
                continue;
            }
            $v = $this->bacaNilai($ws, $col . $baris, $kolom[$field]['type'] ?? 'text');
            $r[$field] = $v;
            if ($v !== null && $v !== false) {
                $ada = true;
            }
        }

        if (isset($p['centang'])) {
            $r[$p['centang']['field']] = null;
            foreach ($p['centang']['kolom'] as $opsi => $col) {
                if (trim((string) $this->nilaiMentah($ws, $col . $baris)) !== '') {
                    $r[$p['centang']['field']] = $opsi;
                    $ada = true;
                    break;
                }
            }
        }

        // Samakan isian pilihan dengan opsi yang ada (mis. "Universitas / PT" -> "Universitas/PT").
        foreach ($r as $f => $v) {
            $opsi = $kolom[$f]['options'] ?? [];
            if (($kolom[$f]['type'] ?? '') === 'select' && is_string($v) && $opsi && ! in_array($v, $opsi, true)) {
                $cocok = $this->cariLabel(array_combine(array_map(fn ($o) => $this->norm($o), $opsi), $opsi), $v);
                if ($cocok !== null) {
                    $r[$f] = $cocok;
                }
            }
        }

        if (! $ada || count(array_filter($r, fn ($v) => $v !== null && $v !== false && $v !== '')) < $minIsi) {
            return null;
        }

        if (isset($p['lainnya']) && $p['lainnya']['field'] !== $lewati) {
            $f = $p['lainnya']['field'];
            $opsi = $kolom[$f]['options'] ?? [];
            if ($r[$f] !== null && ! in_array($r[$f], $opsi, true)) {
                $cocok = $this->cariLabel(array_combine(array_map(fn ($o) => $this->norm($o), $opsi), $opsi), $this->norm($r[$f]));
                if ($cocok !== null) {
                    $r[$f] = $cocok;
                } else {
                    $r[$p['lainnya']['keterangan']] = $r[$f];
                    $r[$f] = 'Lainnya';
                }
            }
        }

        return $ada ? $r : null;
    }

    private function bacaNilai(Worksheet $ws, string $ref, string $type): mixed
    {
        $v = $this->nilaiMentah($ws, $ref);
        if (is_string($v)) {
            $v = trim($v);
        }
        if ($v === null || $v === '') {
            return $type === 'check' ? false : null;
        }
        if ($type === 'check') {
            return ! in_array(mb_strtolower((string) $v), ['-', '0', 'tidak'], true);
        }
        if (in_array($type, ['number', 'decimal'], true)) {
            if (! is_numeric($v)) {
                $v = str_replace([' ', ','], ['', '.'], (string) $v);
                if (! is_numeric($v)) {
                    return null;
                }
            }
            return $type === 'number' ? (int) round((float) $v) : round((float) $v, 2);
        }
        if (is_float($v) && floor($v) == $v) {
            $v = (int) $v;
        }
        $v = (string) $v;

        return in_array(mb_strtolower($v), self::PLACEHOLDER, true) ? null : $v;
    }

    private function nilaiMentah(Worksheet $ws, string $ref): mixed
    {
        $cell = $ws->getCell($ref);
        $v = $cell->getValue();
        if ($v instanceof RichText) {
            $v = $v->getPlainText();
        }
        if (is_string($v) && str_starts_with($v, '=')) {
            try {
                $v = $cell->getCalculatedValue();
            } catch (\Throwable) {
                $v = null;
            }
        }

        return $v;
    }

    private function wajibTerisi(string $slug, array $r, int $baris, string $sheet): bool
    {
        foreach ($this->kolom($slug) as $n => $k) {
            if (str_contains($k['rules'], 'required') && ! in_array($k['type'], ['file', 'check'], true)
                && (($r[$n] ?? null) === null || $r[$n] === '')) {
                if (array_filter($r, fn ($v) => $v !== null && $v !== false && $v !== '') ) {
                    $this->catatan[] = "{$sheet} baris {$baris}: kolom \"{$k['label']}\" kosong, baris dilewati.";
                }
                return false;
            }
        }

        return true;
    }

    private function lengkapiKolom(string $slug, array $r): array
    {
        $hasil = [];
        foreach ($this->kolom($slug) as $n => $k) {
            $hasil[$n] = $r[$n] ?? ($k['type'] === 'check' ? false : null);
        }
        foreach ($this->tabel[$slug]['total'] ?? [] as $target => $sumber) {
            $hasil[$target] = array_sum(array_map(fn ($c) => (float) ($hasil[$c] ?? 0), $sumber));
        }

        return $hasil;
    }

    // =====================================================================
    // UTILITAS
    // =====================================================================

    private function mode(array $p): string
    {
        return $p['mode'] ?? (isset($p['kunci']) ? 'kunci' : 'daftar');
    }

    private function kolom(string $slug): array
    {
        $hasil = [];
        foreach ($this->tabel[$slug]['kolom'] ?? [] as $n => $d) {
            $hasil[$n] = ['label' => str_replace('|', ' – ', $d[0]), 'type' => $d[1] ?? 'text', 'rules' => $d[2] ?? 'nullable', 'options' => $d[3] ?? []];
        }
        // Lampiran Bukti: saat ekspor berisi link pratinjau, saat impor dilewati.
        $hasil['lampiran_bukti'] ??= ['label' => 'Lampiran Bukti', 'type' => 'file', 'rules' => 'nullable', 'options' => []];

        return $hasil;
    }

    /** Baris pertama (mulai dari $mulai) yang berisi Jumlah/Keterangan/Total di kolom A. */
    private function footer(Worksheet $ws, int $mulai): ?int
    {
        $max = min($ws->getHighestDataRow(), $mulai + 5000);
        for ($r = $mulai; $r <= $max; $r++) {
            $v = trim((string) $this->nilaiMentah($ws, 'A' . $r));
            if ($v !== '' && preg_match(self::POLA_FOOTER, $v)) {
                return $r;
            }
        }

        return null;
    }

    /** [label ternormalisasi => nomor baris] untuk tabel berbaris tetap. */
    private function petaLabel(Worksheet $ws, array $p): array
    {
        $akhir = $this->footer($ws, $p['mulai']) ?? $p['mulai'] + 30;
        $peta = [];
        for ($r = $p['mulai']; $r < $akhir; $r++) {
            $label = $this->norm($this->nilaiMentah($ws, $p['kunci']['kolom'] . $r));
            if ($label !== '' && ! isset($peta[$label])) {
                $peta[$label] = $r;
            }
        }

        return $peta;
    }

    private function cariLabel(array $peta, string $label): mixed
    {
        $label = $this->norm($label);
        if ($label === '') {
            return null;
        }
        if (isset($peta[$label])) {
            return $peta[$label];
        }
        foreach ($peta as $k => $v) {
            if (min(strlen($k), strlen($label)) >= 5 && (str_starts_with($k, $label) || str_starts_with($label, $k))) {
                return $v;
            }
        }

        return null;
    }

    private function norm(mixed $s): string
    {
        return preg_replace('/[^a-z0-9]/', '', mb_strtolower((string) $s)) ?? '';
    }
}
EOF

tulis app/Support/LkpsData.php <<'EOF'
<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;

/** Jembatan antara database dan LkpsExcel. */
class LkpsData
{
    public static function template(): string
    {
        return storage_path('app/lkps/template.xlsx');
    }

    public static function excel(): LkpsExcel
    {
        return new LkpsExcel(config('lkps.tabel', []), config('lkps_excel', []), config('lkps.isian', []));
    }

    /** Isian di luar tabel: [kunci => nilai]. */
    public static function isian(): array
    {
        return Schema::hasTable('lkps_isian')
            ? DB::table('lkps_isian')->pluck('nilai', 'kunci')->all()
            : [];
    }

    public static function simpanIsian(array $nilai): void
    {
        $now = now();
        foreach ($nilai as $kunci => $v) {
            DB::table('lkps_isian')->updateOrInsert(
                ['kunci' => $kunci],
                ['nilai' => $v === '' ? null : $v, 'updated_at' => $now, 'created_at' => $now]
            );
        }
    }

    /** Seluruh isi 31 tabel: [slug => [ [kolom => nilai], ... ]]. */
    public static function semua(bool $linkLampiran = false): array
    {
        $data = [];
        foreach (array_keys(Lkps::tabel()) as $slug) {
            $nama = Lkps::namaTabel($slug);
            $rows = Schema::hasTable($nama)
                ? DB::table($nama)->orderBy('id')->get()->map(fn ($r) => (array) $r)->all()
                : [];

            // Untuk ekspor: path berkas diganti link pratinjau Lampiran Bukti
            // (ditulis ke kolom "Link Bukti" di template).
            if ($linkLampiran) {
                foreach ($rows as &$r) {
                    $r[Lkps::LAMPIRAN] = filled($r[Lkps::LAMPIRAN] ?? null)
                        ? Lkps::urlLampiran($slug, $r['id'])
                        : (filled($r['lampiran_link'] ?? null) ? $r['lampiran_link'] : null);
                }
                unset($r);
            }
            $data[$slug] = $rows;
        }

        return $data;
    }

    /**
     * Simpan hasil impor. Mode ganti: isi lama sebuah tabel dihapus hanya bila
     * file impor berisi data untuk tabel tersebut. Mengembalikan [slug => jumlah baris].
     */
    public static function simpan(array $hasil, bool $tambah, ?int $userId): array
    {
        $ringkas = [];
        DB::transaction(function () use ($hasil, $tambah, $userId, &$ringkas) {
            $now = now();
            foreach ($hasil as $slug => $rows) {
                if (! $rows || ! isset(Lkps::tabel()[$slug])) {
                    continue;
                }
                $nama = Lkps::namaTabel($slug);
                if (! $tambah) {
                    $berkas = array_keys(array_filter(Lkps::kolom($slug), fn ($k) => $k['type'] === 'file'));
                    foreach ($berkas as $kolom) {
                        Storage::disk(Lkps::DISK)->delete(DB::table($nama)->whereNotNull($kolom)->pluck($kolom)->all());
                    }
                    DB::table($nama)->delete();
                }
                foreach (array_chunk($rows, 200) as $potong) {
                    DB::table($nama)->insert(array_map(
                        fn ($r) => $r + ['created_by' => $userId, 'created_at' => $now, 'updated_at' => $now],
                        $potong
                    ));
                }
                $ringkas[$slug] = count($rows);
            }
        });

        return $ringkas;
    }
}
EOF

tulis app/Support/LkpsRingkasan.php <<'EOF'
<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/** Ringkasan kelengkapan LKPS untuk Dashboard Akreditasi dan halaman daftar LKPS. */
class LkpsRingkasan
{
    private static ?array $cache = null;

    /** Hapus hasil hitung yang tersimpan (dipakai setelah data berubah dalam proses yang sama). */
    public static function segarkan(): void
    {
        self::$cache = null;
    }

    /**
     * @return array{tersedia:bool,total:int,terisi:int,persen:int,kelompok:array}
     *  tersedia = tabel LKPS sudah dibuat (migration sudah dijalankan)
     */
    public static function data(): array
    {
        if (self::$cache !== null) {
            return self::$cache;
        }

        $tersedia = false;
        try {
            $tersedia = Schema::hasTable('lkps_isian');
        } catch (\Throwable $e) {
            $tersedia = false;
        }

        $kelompok = [];
        $total = 0;
        $terisi = 0;
        if ($tersedia) {
            foreach (Lkps::perKelompok() as $kode => $grup) {
                $items = [];
                foreach ($grup['tabel'] as $slug => $judul) {
                    $nama = Lkps::namaTabel($slug);
                    $n = Schema::hasTable($nama) ? DB::table($nama)->count() : 0;
                    $items[] = compact('slug', 'judul', 'n');
                    $total++;
                    $terisi += $n > 0 ? 1 : 0;
                }
                $kelompok[] = [
                    'kode'   => $kode,
                    'nama'   => $grup['nama'],
                    'items'  => $items,
                    'terisi' => count(array_filter($items, fn ($i) => $i['n'] > 0)),
                ];
            }
        }

        return self::$cache = [
            'tersedia' => $tersedia,
            'total'    => $total,
            'terisi'   => $terisi,
            'persen'   => $total ? (int) round($terisi / $total * 100) : 0,
            'kelompok' => $kelompok,
        ];
    }
}
EOF

tulis database/migrations/2026_10_08_000100_create_lkps_tables.php <<'EOF'
<?php

use App\Support\Lkps;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

// Hanya MENAMBAH tabel lkps_* baru (dan kolom yang belum ada). Tabel lain tidak disentuh.
return new class extends Migration
{
    public function up(): void
    {
        Lkps::sinkron();
    }

    public function down(): void
    {
        // Pengaman: hanya tabel yang masih KOSONG yang dihapus; tabel berisi data dibiarkan.
        foreach (array_keys(Lkps::tabel()) as $slug) {
            $nama = Lkps::namaTabel($slug);
            if (Schema::hasTable($nama) && DB::table($nama)->count() === 0) {
                Schema::dropIfExists($nama);
            }
        }
        if (Schema::hasTable('lkps_isian') && DB::table('lkps_isian')->count() === 0) {
            Schema::dropIfExists('lkps_isian');
        }
    }
};
EOF

tulis app/Console/Commands/LkpsSinkron.php <<'EOF'
<?php

namespace App\Console\Commands;

use App\Support\Lkps;
use Illuminate\Console\Command;

class LkpsSinkron extends Command
{
    protected $signature = 'lkps:sinkron';
    protected $description = 'Buat tabel/kolom LKPS baru sesuai config/lkps.php tanpa menghapus data';

    public function handle(): int
    {
        foreach (Lkps::sinkron() as $pesan) {
            $this->info($pesan);
        }

        return self::SUCCESS;
    }
}
EOF

tulis app/Console/Commands/LkpsImpor.php <<'EOF'
<?php

namespace App\Console\Commands;

use App\Support\LkpsData;
use Illuminate\Console\Command;

class LkpsImpor extends Command
{
    protected $signature = 'lkps:impor {file : path workbook .xlsx} {--ganti : ganti isi tabel yang ada di file (bawaan: menambahkan)}';
    protected $description = 'Impor workbook LKPS (.xlsx) ke database. Bawaan: menambahkan, tidak menghapus data yang ada';

    public function handle(): int
    {
        if (! class_exists(\PhpOffice\PhpSpreadsheet\IOFactory::class)) {
            $this->error('PhpSpreadsheet belum terpasang. Jalankan: composer require phpoffice/phpspreadsheet');

            return self::FAILURE;
        }
        @ini_set('memory_limit', '1024M');
        $excel = LkpsData::excel();
        $hasil = $excel->impor($this->argument('file'));
        $ringkas = LkpsData::simpan($hasil, ! $this->option('ganti'), null);
        LkpsData::simpanIsian($excel->isian);
        foreach ($ringkas as $slug => $n) {
            $this->line(sprintf('%-30s %4d baris', $slug, $n));
        }
        foreach ($excel->catatan as $c) {
            $this->warn($c);
        }
        $this->info('Impor selesai: ' . array_sum($ringkas) . ' baris.');

        return self::SUCCESS;
    }
}
EOF

tulis app/Console/Commands/LkpsEkspor.php <<'EOF'
<?php

namespace App\Console\Commands;

use App\Support\LkpsData;
use Illuminate\Console\Command;

class LkpsEkspor extends Command
{
    protected $signature = 'lkps:ekspor {tujuan=storage/app/lkps/LKPS_ekspor.xlsx : berkas hasil}';
    protected $description = 'Ekspor seluruh data LKPS ke template Excel';

    public function handle(): int
    {
        if (! class_exists(\PhpOffice\PhpSpreadsheet\IOFactory::class)) {
            $this->error('PhpSpreadsheet belum terpasang. Jalankan: composer require phpoffice/phpspreadsheet');

            return self::FAILURE;
        }
        @ini_set('memory_limit', '1024M');
        $template = LkpsData::template();
        if (! is_file($template)) {
            $this->error('Template belum ada di ' . $template);

            return self::FAILURE;
        }
        $excel = LkpsData::excel();
        $book = $excel->ekspor($template, LkpsData::semua(true), LkpsData::isian());
        @mkdir(dirname($this->argument('tujuan')), 0775, true);
        \PhpOffice\PhpSpreadsheet\IOFactory::createWriter($book, 'Xlsx')->save($this->argument('tujuan'));
        foreach ($excel->catatan as $c) {
            $this->warn($c);
        }
        $this->info('Tersimpan: ' . $this->argument('tujuan'));

        return self::SUCCESS;
    }
}
EOF

tulis app/Http/Controllers/LkpsController.php <<'EOF'
<?php

namespace App\Http\Controllers;

use App\Support\Lkps;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

class LkpsController extends Controller
{
    /** Halaman menu LKPS: daftar tabel per kelompok beserta kelengkapannya. */
    public function daftar()
    {
        return view('lkps.daftar', ['lk' => \App\Support\LkpsRingkasan::data(), 'tahun' => config('lkps.tahun_ts')]);
    }

    public function index(Request $request, string $tabel)
    {
        $def = Lkps::definisi($tabel);
        $kolom = Lkps::kolom($tabel);
        $cari = trim((string) $request->query('q', ''));

        $query = DB::table(Lkps::namaTabel($tabel))
            ->when($cari !== '', function ($q) use ($kolom, $cari) {
                $q->where(function ($w) use ($kolom, $cari) {
                    foreach ($kolom as $n => $k) {
                        if ($k['type'] !== 'file') {
                            $w->orWhere($n, 'like', "%{$cari}%");
                        }
                    }
                });
            })
            ->orderBy('id');
        $ringkasan = Lkps::ringkasan($tabel, (clone $query)->get());
        $rows = $query->paginate(25)->withQueryString();

        return view('lkps.tabel', [
            'tabel'    => $tabel,
            'def'      => $def,
            'kolom'    => $kolom,
            'rows'     => $rows,
            'cari'      => $cari,
            'kelompok'  => Lkps::namaKelompok($tabel),
            'header'    => Lkps::header($tabel),
            'ringkasan' => $ringkasan,
        ]);
    }

    public function create(string $tabel)
    {
        return $this->form($tabel, null);
    }

    public function store(Request $request, string $tabel)
    {
        $data = $this->ambilData($request, $tabel, null);
        $data['created_by'] = $request->user()?->id;
        $data['created_at'] = $data['updated_at'] = now();

        DB::table(Lkps::namaTabel($tabel))->insert($data);

        return $this->kembali($tabel)->with('ok', 'Data ditambahkan.');
    }

    public function edit(string $tabel, int $id)
    {
        return $this->form($tabel, $this->cariBaris($tabel, $id));
    }

    public function update(Request $request, string $tabel, int $id)
    {
        $row = $this->cariBaris($tabel, $id);
        $data = $this->ambilData($request, $tabel, $row);
        $data['updated_at'] = now();

        DB::table(Lkps::namaTabel($tabel))->where('id', $id)->update($data);

        return $this->kembali($tabel)->with('ok', 'Perubahan disimpan.');
    }

    public function destroy(string $tabel, int $id)
    {
        $row = $this->cariBaris($tabel, $id);
        foreach (Lkps::kolom($tabel) as $n => $k) {
            if ($k['type'] === 'file' && $row->$n) {
                Storage::disk(Lkps::DISK)->delete($row->$n);
            }
        }
        DB::table(Lkps::namaTabel($tabel))->where('id', $id)->delete();

        return $this->kembali($tabel)->with('ok', 'Data dihapus.');
    }

    /** Ekspor CSV (pemisah titik koma agar langsung terbaca Excel berlokal Indonesia). */
    public function export(string $tabel)
    {
        $kolom = Lkps::kolom($tabel);
        $nama = Lkps::namaTabel($tabel);

        return response()->streamDownload(function () use ($kolom, $nama, $tabel) {
            $out = fopen('php://output', 'w');
            fwrite($out, "\xEF\xBB\xBF");
            fputcsv($out, array_merge(['No'], array_column($kolom, 'label')), ';');
            $no = 0;
            DB::table($nama)->orderBy('id')->chunk(500, function ($rows) use (&$no, $out, $kolom, $tabel) {
                foreach ($rows as $r) {
                    $baris = [++$no];
                    foreach ($kolom as $n => $k) {
                        $baris[] = match (true) {
                            $k['type'] === 'check' => $r->$n ? '√' : '',
                            $k['type'] === 'file'  => $r->$n ? Lkps::urlLampiran($tabel, $r->id, $n) : '',
                            default                => $r->$n,
                        };
                    }
                    fputcsv($out, $baris, ';');
                }
            });
            fclose($out);
        }, "lkps_{$tabel}_" . date('Ymd') . '.csv', ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    /** Tabel tersembunyi (mis. Daftar Dosen Homebase) kembali ke halaman Identitas; tabel lain ke daftar barisnya. */
    private function kembali(string $tabel)
    {
        return ! empty(Lkps::definisi($tabel)['tersembunyi'])
            ? redirect()->to(route('lkps.isian.index') . '#dosen-homebase')
            : redirect()->route('lkps.tabel.index', $tabel);
    }

    private function form(string $tabel, ?object $row)
    {
        return view('lkps.form', [
            'tabel'    => $tabel,
            'def'      => Lkps::definisi($tabel),
            'kolom'    => Lkps::kolom($tabel),
            'row'      => $row,
            'kelompok' => Lkps::namaKelompok($tabel),
        ]);
    }

    private function cariBaris(string $tabel, int $id): object
    {
        Lkps::definisi($tabel);
        $row = DB::table(Lkps::namaTabel($tabel))->where('id', $id)->first();
        abort_if(! $row, 404, 'Data tidak ditemukan.');

        return $row;
    }

    private function ambilData(Request $request, string $tabel, ?object $row): array
    {
        $data = $request->validate(Lkps::rules($tabel, $row !== null), [], Lkps::label($tabel));

        foreach (Lkps::kolom($tabel) as $n => $k) {
            if ($k['type'] === 'check') {
                $data[$n] = $request->boolean($n);
                continue;
            }
            if ($k['type'] !== 'file') {
                continue;
            }
            if ($request->hasFile($n)) {
                if ($row && $row->$n) {
                    Storage::disk(Lkps::DISK)->delete($row->$n);
                }
                $data[$n] = $request->file($n)->store("lkps/{$tabel}", Lkps::DISK);
            } elseif ($row && $row->$n && $request->boolean("hapus_{$n}")) {
                Storage::disk(Lkps::DISK)->delete($row->$n);
                $data[$n] = null;
            } else {
                unset($data[$n]);
            }
        }

        // Kolom total dihitung otomatis (mis. Total SKS pada EWMP).
        foreach (Lkps::definisi($tabel)['total'] ?? [] as $target => $sumber) {
            $data[$target] = array_sum(array_map(fn ($c) => (float) ($data[$c] ?? 0), $sumber));
        }

        return $data;
    }
}
EOF

tulis app/Http/Controllers/LkpsExcelController.php <<'EOF'
<?php

namespace App\Http\Controllers;

use App\Support\Lkps;
use App\Support\LkpsData;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\File;

class LkpsExcelController extends Controller
{
    /** Pustaka PhpSpreadsheet opsional; tanpa itu halaman ini hanya menampilkan petunjuk pemasangan. */
    private function tersedia(): bool
    {
        return class_exists(\PhpOffice\PhpSpreadsheet\IOFactory::class);
    }

    private function tanpaPustaka()
    {
        return redirect()->route('lkps.excel.index')
            ->with('galat', 'Pustaka PhpSpreadsheet belum terpasang. Jalankan: composer require phpoffice/phpspreadsheet');
    }

    public function index()
    {
        $path = LkpsData::template();

        return view('lkps.excel', [
            'tersedia'      => $this->tersedia(),
            'adaTemplate'   => is_file($path),
            'waktuTemplate' => is_file($path) ? date('d-m-Y H:i', filemtime($path)) : null,
            'judul'         => array_map(fn ($d) => $d['judul'], Lkps::tabel()),
        ]);
    }

    public function ekspor()
    {
        if (! $this->tersedia()) {
            return $this->tanpaPustaka();
        }
        $path = LkpsData::template();
        if (! is_file($path)) {
            return redirect()->route('lkps.excel.index')->with('galat', 'Template Excel belum diunggah. Unggah template terlebih dahulu.');
        }
        $this->longgarkanBatas();

        $excel = LkpsData::excel();
        $book = $excel->ekspor($path, LkpsData::semua(true), LkpsData::isian());
        $tmp = tempnam(sys_get_temp_dir(), 'lkps') . '.xlsx';
        \PhpOffice\PhpSpreadsheet\IOFactory::createWriter($book, 'Xlsx')->save($tmp);

        return response()->download($tmp, 'LKPS_LAM_Infokom_' . date('Ymd_His') . '.xlsx')->deleteFileAfterSend(true);
    }

    public function unggahTemplate(Request $request)
    {
        if (! $this->tersedia()) {
            return $this->tanpaPustaka();
        }
        $request->validate(['template' => ['required', 'file', 'max:20480', $this->harusXlsx()]], [], ['template' => 'template']);
        $this->longgarkanBatas();

        $file = $request->file('template');
        try {
            $sheets = \PhpOffice\PhpSpreadsheet\IOFactory::createReaderForFile($file->getRealPath())->listWorksheetNames($file->getRealPath());
        } catch (\Throwable) {
            return back()->with('galat', 'File tidak bisa dibaca sebagai workbook Excel.');
        }
        $hilang = array_diff(array_column(config('lkps_excel'), 'sheet'), $sheets);
        if ($hilang) {
            return back()->with('galat', 'Template belum sesuai. Sheet yang tidak ditemukan: ' . implode(', ', $hilang) . '.');
        }

        File::ensureDirectoryExists(dirname(LkpsData::template()));
        $file->move(dirname(LkpsData::template()), basename(LkpsData::template()));

        return back()->with('ok', 'Template disimpan. Ekspor berikutnya memakai template ini.');
    }

    public function impor(Request $request)
    {
        if (! $this->tersedia()) {
            return $this->tanpaPustaka();
        }
        $request->validate([
            'file' => ['required', 'file', 'max:20480', $this->harusXlsx()],
            'mode' => ['required', 'in:ganti,tambah'],
        ], [], ['file' => 'file Excel', 'mode' => 'cara impor']);
        $this->longgarkanBatas();

        $excel = LkpsData::excel();
        try {
            $hasil = $excel->impor($request->file('file')->getRealPath());
        } catch (\Throwable $e) {
            return back()->with('galat', 'File tidak bisa dibaca: ' . $e->getMessage());
        }

        $ringkas = LkpsData::simpan($hasil, $request->input('mode') === 'tambah', $request->user()->id);
        LkpsData::simpanIsian($excel->isian);
        $total = array_sum($ringkas);

        return redirect()->route('lkps.excel.index')
            ->with('ok', "Impor selesai: {$total} baris masuk ke " . count($ringkas) . ' tabel, '
                . count($excel->isian) . ' isian identitas/tambahan diperbarui.')
            ->with('ringkas', $ringkas)
            ->with('catatan', $excel->catatan);
    }

    private function harusXlsx(): \Closure
    {
        return function (string $attr, $file, \Closure $fail) {
            if (strtolower($file->getClientOriginalExtension()) !== 'xlsx') {
                $fail('File harus berformat .xlsx.');
            }
        };
    }

    private function longgarkanBatas(): void
    {
        @ini_set('memory_limit', '1024M');
        @set_time_limit(300);
    }
}
EOF

tulis app/Http/Controllers/LkpsIsianController.php <<'EOF'
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

tulis app/Http/Controllers/LkpsLampiranController.php <<'EOF'
<?php

namespace App\Http\Controllers;

use App\Support\Lkps;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

/** Pratinjau lampiran bukti: berkas dibuka di browser (inline), bukan diunduh. */
class LkpsLampiranController extends Controller
{
    public function lihat(string $tabel, int $id, string $kolom = 'lampiran_bukti')
    {
        [$row, $path] = $this->cari($tabel, $id, $kolom);
        $mime = Storage::disk(Lkps::DISK)->mimeType($path) ?: 'application/octet-stream';

        // Ringkasan baris: dua isian teks pertama, sebagai keterangan di halaman pratinjau.
        $ringkas = [];
        foreach (Lkps::kolom($tabel) as $n => $k) {
            if (in_array($k['type'], ['text', 'select'], true) && filled($row->$n ?? null)) {
                $ringkas[] = $row->$n;
            }
            if (count($ringkas) === 2) {
                break;
            }
        }

        return view('lkps.lampiran', [
            'tabel'   => $tabel,
            'def'     => Lkps::definisi($tabel),
            'label'   => Lkps::kolom($tabel)[$kolom]['label'],
            'ringkas' => implode(' – ', $ringkas),
            'mime'    => $mime,
            'src'     => route('lkps.lampiran.berkas', [$tabel, $id, $kolom]),
        ]);
    }

    public function berkas(string $tabel, int $id, string $kolom)
    {
        [, $path] = $this->cari($tabel, $id, $kolom);

        return response()->file(Storage::disk(Lkps::DISK)->path($path), [
            'Content-Disposition'    => 'inline; filename="' . basename($path) . '"',
            'X-Content-Type-Options' => 'nosniff',
            'Cache-Control'          => 'private, max-age=3600',
        ]);
    }

    private function cari(string $tabel, int $id, string $kolom): array
    {
        $kol = Lkps::kolom($tabel);
        abort_if(($kol[$kolom]['type'] ?? null) !== 'file', 404);

        $row = DB::table(Lkps::namaTabel($tabel))->where('id', $id)->first();
        $path = $row->$kolom ?? null;
        abort_if(! $path || ! Storage::disk(Lkps::DISK)->exists($path), 404, 'Lampiran tidak ditemukan.');

        return [$row, $path];
    }
}
EOF

tulis resources/views/lkps/_gaya.blade.php <<'EOF'
<style>
.lk-crumb{color:var(--muted,#667085);font-size:.82rem;margin-bottom:.2rem}
.lk-panel{background:var(--card,#fff);border:1px solid var(--line,#e4e8ef);border-radius:12px;padding:1.1rem 1.2rem;box-shadow:0 1px 2px rgba(16,24,40,.04)}
.lk-wrap{background:var(--card,#fff);border:1px solid var(--line,#e4e8ef);border-radius:12px;overflow:auto}
.lk-wrap table{margin:0;font-size:.86rem}
.lk-wrap thead th{white-space:nowrap;vertical-align:middle;border:1px solid var(--line,#e4e8ef)}
.lk-wrap tfoot th,.lk-wrap tfoot td{background:var(--head,#f7f9fc);font-weight:600;border-top:2px solid var(--line,#e4e8ef)}
.lk-seg{display:flex;gap:4px;margin:.7rem 0 .9rem}
.lk-seg span{flex:1;height:9px;border-radius:3px}
.lk-seg .isi{background:var(--ok,#15803d)}
.lk-seg .kosong{background:#fdeed8;outline:1px solid #e8c995}
.lk-list{list-style:none;padding:0;margin:0}
.lk-list li{display:flex;justify-content:space-between;gap:1rem;padding:.42rem 0;border-top:1px solid var(--line,#e4e8ef)}
.lk-list a{color:var(--text,#1b2536);text-decoration:none}
.lk-list a:hover{color:var(--pri,#1d4ed8);text-decoration:underline}
.lk-status{font-size:.76rem;padding:.1rem .55rem;border-radius:999px;white-space:nowrap}
.lk-status.isi{background:#dcf2e3;color:var(--ok,#15803d)}
.lk-status.kosong{background:#fdeed8;color:var(--warn,#b45309)}
</style>
EOF

tulis resources/views/lkps/daftar.blade.php <<'EOF'
@extends('layout')
@section('title', 'LKPS')

@section('content')
@include('lkps._gaya')
<div class="d-flex flex-wrap justify-content-between align-items-end gap-3 mb-3">
  <div>
    <p class="lk-crumb">Data Induk</p>
    <h1 class="mb-0">LKPS LAM Infokom</h1>
    <p class="small text-secondary mb-0 mt-1">Laporan Kinerja Program Studi Tahun Semester 2023/2024, 2024/2025 dan 2025/2026</p>
  </div>
  <div class="d-flex gap-2">
    <a href="{{ route('lkps.isian.index') }}" class="btn btn-sm btn-warning fw-bold px-3 shadow-sm" style="box-shadow:0 0 0 3px rgba(245,158,11,.35)!important">Identitas UPPS dan Program Studi</a>
    <a href="{{ route('lkps.excel.index') }}" class="btn btn-sm btn-outline-secondary">Impor &amp; ekspor Excel</a>
  </div>
</div>

@if(! $lk['tersedia'])
  <div class="alert alert-warning">Tabel LKPS belum dibuat. Jalankan <code>php artisan lkps:sinkron</code> di folder aplikasi.</div>
@else
  <div class="lk-panel mb-3">
    <div class="mb-2"><strong>{{ $lk['terisi'] }}</strong> dari {{ $lk['total'] }} tabel sudah berisi data</div>
    <div style="max-width:560px">@include('bar', ['v' => $lk['persen']])</div>
  </div>
  <div class="row g-3">
    @foreach($lk['kelompok'] as $g)
      <div class="col-12 col-xl-6">
        <section class="lk-panel h-100">
          <div class="d-flex justify-content-between align-items-baseline gap-2">
            <h2 class="h6 mb-0 fw-semibold">{{ $g['nama'] }}</h2>
            <span class="small text-secondary text-nowrap">{{ $g['terisi'] }}/{{ count($g['items']) }} terisi</span>
          </div>
          <div class="lk-seg" aria-hidden="true">
            @foreach($g['items'] as $i)<span class="{{ $i['n'] > 0 ? 'isi' : 'kosong' }}" title="{{ $i['judul'] }}"></span>@endforeach
          </div>
          <ul class="lk-list">
            @foreach($g['items'] as $i)
              <li>
                <a href="{{ route('lkps.tabel.index', $i['slug']) }}">{{ $i['judul'] }}</a>
                <span class="lk-status {{ $i['n'] > 0 ? 'isi' : 'kosong' }}">{{ $i['n'] > 0 ? $i['n'] . ' baris' : 'Belum diisi' }}</span>
              </li>
            @endforeach
          </ul>
        </section>
      </div>
    @endforeach
  </div>
@endif
@endsection
EOF

tulis resources/views/lkps/dashboard.blade.php <<'EOF'
@php $lk = \App\Support\LkpsRingkasan::data(); @endphp
@if($lk['tersedia'])
@include('lkps._gaya')
<div class="sec" style="margin-top:26px">Kelengkapan LKPS</div>
<div class="lk-panel mb-3">
  <div class="d-flex justify-content-between flex-wrap gap-2 align-items-baseline mb-2">
    <span><strong>{{ $lk['terisi'] }}</strong> dari {{ $lk['total'] }} tabel LKPS sudah berisi data</span>
    <a href="{{ route('lkps.daftar') }}" class="small">Buka LKPS &rarr;</a>
  </div>
  <div style="max-width:560px">@include('bar', ['v' => $lk['persen']])</div>
</div>
<div class="row g-3">
  @foreach($lk['kelompok'] as $g)
    <div class="col-12 col-xl-6">
      <section class="lk-panel h-100">
        <div class="d-flex justify-content-between align-items-baseline gap-2">
          <h2 class="h6 mb-0 fw-semibold">{{ $g['nama'] }}</h2>
          <span class="small text-secondary text-nowrap">{{ $g['terisi'] }}/{{ count($g['items']) }} terisi</span>
        </div>
        <div class="lk-seg" aria-hidden="true">
          @foreach($g['items'] as $i)<span class="{{ $i['n'] > 0 ? 'isi' : 'kosong' }}" title="{{ $i['judul'] }}"></span>@endforeach
        </div>
        <ul class="lk-list">
          @foreach($g['items'] as $i)
            <li>
              <a href="{{ route('lkps.tabel.index', $i['slug']) }}">{{ $i['judul'] }}</a>
              <span class="lk-status {{ $i['n'] > 0 ? 'isi' : 'kosong' }}">{{ $i['n'] > 0 ? $i['n'] . ' baris' : 'Belum diisi' }}</span>
            </li>
          @endforeach
        </ul>
      </section>
    </div>
  @endforeach
</div>
@endif
EOF

tulis resources/views/lkps/excel.blade.php <<'EOF'
@extends('layout')
@section('title', 'Impor & ekspor Excel')

@section('content')
@include('lkps._gaya')
<h1 class="mb-1">Impor & ekspor Excel</h1>
<p class="text-secondary mb-4" style="max-width: 70ch">
    Ekspor mengisi template resmi LKPS (31 sheet) dengan seluruh data aplikasi. Impor membaca workbook
    dengan format yang sama dan memasukkan isinya ke database.
</p>

@if (! $tersedia)
    <div class="alert alert-warning py-2">Pustaka <strong>PhpSpreadsheet</strong> belum terpasang di server, jadi impor dan ekspor Excel belum dapat dipakai. Jalankan di folder aplikasi: <code>composer require phpoffice/phpspreadsheet</code></div>
@endif

@if (session('galat'))
    <div class="alert alert-danger py-2">{{ session('galat') }}</div>
@endif

@if (session('ringkas'))
    <div class="lk-panel mb-3">
        <h2 class="mb-2">Hasil impor</h2>
        <ul class="lk-list">
            @foreach (session('ringkas') as $slug => $n)
                <li><a href="{{ route('lkps.tabel.index', $slug) }}">{{ $judul[$slug] ?? $slug }}</a><span class="lk-status isi">{{ $n }} baris</span></li>
            @endforeach
        </ul>
    </div>
@endif

@if (session('catatan'))
    <div class="alert alert-warning py-2">
        <strong>Catatan:</strong>
        <ul class="mb-0 mt-1">
            @foreach (session('catatan') as $c)
                <li>{{ $c }}</li>
            @endforeach
        </ul>
    </div>
@endif

<div class="row g-3">
    <div class="col-12 col-xl-4">
        <section class="lk-panel h-100">
            <h2 class="mb-2">Ekspor ke template</h2>
            @if ($adaTemplate)
                <p class="small text-secondary">Template terakhir diperbarui {{ $waktuTemplate }}.</p>
                <a href="{{ route('lkps.excel.ekspor') }}" class="btn btn-primary">Unduh LKPS (.xlsx)</a>
            @else
                <p class="small text-secondary mb-0">Template belum ada. Unggah template LKPS terlebih dahulu.</p>
            @endif
        </section>
    </div>

    <div class="col-12 col-xl-4">
        <section class="lk-panel h-100">
            <h2 class="mb-2">Template LKPS</h2>
            <p class="small text-secondary">{{ $adaTemplate ? 'Template sudah tersedia. Unggah lagi untuk mengganti.' : 'Unggah workbook template LKPS LAM Infokom yang kosong.' }}</p>
            @auth
                <form method="POST" action="{{ route('lkps.excel.template') }}" enctype="multipart/form-data">
                    @csrf
                    <label for="template" class="visually-hidden">File template</label>
                    <input id="template" type="file" name="template" accept=".xlsx" required class="form-control form-control-sm mb-2 @error('template') is-invalid @enderror">
                    @error('template') <div class="invalid-feedback d-block mb-2">{{ $message }}</div> @enderror
                    <button class="btn btn-sm btn-outline-secondary">Simpan template</button>
                </form>
            @else
                <a href="{{ route('login') }}" class="btn btn-sm btn-outline-secondary">Masuk untuk mengunggah template</a>
            @endauth
        </section>
    </div>

    <div class="col-12 col-xl-4">
        <section class="lk-panel h-100">
            <h2 class="mb-2">Impor dari Excel</h2>
            @auth
                <form method="POST" action="{{ route('lkps.excel.impor') }}" enctype="multipart/form-data">
                    @csrf
                    <label for="file" class="form-label small fw-semibold">Workbook LKPS yang sudah terisi</label>
                    <input id="file" type="file" name="file" accept=".xlsx" required class="form-control form-control-sm mb-2 @error('file') is-invalid @enderror">
                    @error('file') <div class="invalid-feedback d-block mb-2">{{ $message }}</div> @enderror
                    <div class="form-check small">
                        <input class="form-check-input" type="radio" name="mode" id="mode-ganti" value="ganti">
                        <label class="form-check-label" for="mode-ganti">Ganti isi tabel yang ada di file</label>
                    </div>
                    <div class="form-check small mb-3">
                        <input class="form-check-input" type="radio" name="mode" id="mode-tambah" value="tambah" checked>
                        <label class="form-check-label" for="mode-tambah">Tambahkan ke data yang sudah ada</label>
                    </div>
                    <button class="btn btn-sm btn-primary" onclick="return document.getElementById('mode-tambah').checked || confirm('Isi tabel yang ada di file akan diganti. Lanjutkan?')">Impor</button>
                </form>
            @else
                <a href="{{ route('login') }}" class="btn btn-sm btn-outline-secondary">Masuk untuk mengimpor data</a>
            @endauth
        </section>
    </div>
</div>
@endsection
EOF

tulis resources/views/lkps/form.blade.php <<'EOF'
@extends('layout')
@section('title', ($row ? 'Ubah data' : 'Tambah data') . ' - ' . $def['judul'])

@section('content')
@include('lkps._gaya')
<p class="lk-crumb"><a href="{{ route('lkps.daftar') }}" class="link-secondary">LKPS</a> / {{ $kelompok }} / {{ $def['judul'] }}</p>
<h1 class="mb-3">{{ $row ? 'Ubah data' : 'Tambah data' }}</h1>

<form method="POST" enctype="multipart/form-data" class="lk-panel" style="max-width: 760px"
      action="{{ $row ? route('lkps.tabel.update', [$tabel, $row->id]) : route('lkps.tabel.store', $tabel) }}">
    @csrf
    @if ($row) @method('PUT') @endif

    @foreach ($kolom as $n => $k)
        @php
            $nilai = old($n, data_get($row, $n));
            $wajib = str_contains($k['rules'], 'required') && ! ($k['type'] === 'file' && $row);
            $tipeInput = ['number' => 'number', 'decimal' => 'number', 'date' => 'date', 'url' => 'url'][$k['type']] ?? 'text';
            $otomatis = array_key_exists($n, $def['total'] ?? []);
        @endphp
        @if ($k['type'] === 'check')
            <div class="form-check mb-3">
                <input type="hidden" name="{{ $n }}" value="0">
                <input class="form-check-input" type="checkbox" id="f_{{ $n }}" name="{{ $n }}" value="1" @checked($nilai)>
                <label class="form-check-label fw-semibold" for="f_{{ $n }}">{{ $k['label'] }}</label>
            </div>
            @continue
        @endif
        <div class="mb-3">
            <label for="f_{{ $n }}" class="form-label fw-semibold">
                {{ $k['label'] }} @if ($wajib)<span class="text-danger" aria-hidden="true">*</span>@endif
            </label>

            @if ($k['type'] === 'textarea')
                <textarea id="f_{{ $n }}" name="{{ $n }}" rows="3" @if ($wajib) required @endif
                          class="form-control @error($n) is-invalid @enderror">{{ $nilai }}</textarea>
            @elseif ($k['type'] === 'select')
                <select id="f_{{ $n }}" name="{{ $n }}" @if ($wajib) required @endif
                        class="form-select @error($n) is-invalid @enderror">
                    <option value="">Pilih salah satu</option>
                    @foreach ($k['options'] as $opsi)
                        <option value="{{ $opsi }}" @selected((string) $nilai === (string) $opsi)>{{ $opsi }}</option>
                    @endforeach
                </select>
            @elseif ($k['type'] === 'file')
                <input id="f_{{ $n }}" name="{{ $n }}" type="file" @if ($wajib) required @endif
                       accept=".pdf,.jpg,.jpeg,.png,.webp,application/pdf,image/*"
                       class="form-control @error($n) is-invalid @enderror">
                <div class="form-text">
                    PDF atau gambar (JPG, PNG, WEBP), maksimal {{ \App\Support\Lkps::MAKS_LAMPIRAN_KB / 1024 }} MB.
                    Lampiran dibuka sebagai pratinjau di browser, bukan diunduh.
                </div>
                @if (\App\Support\Lkps::batasServerMb() < \App\Support\Lkps::MAKS_LAMPIRAN_KB / 1024)
                    <div class="form-text text-danger">
                        Pengaturan PHP server saat ini hanya menerima berkas hingga
                        {{ \App\Support\Lkps::angka(\App\Support\Lkps::batasServerMb()) }} MB.
                        Naikkan upload_max_filesize dan post_max_size (lihat README, bagian batas unggah).
                    </div>
                @endif
                @if ($row && data_get($row, $n))
                    <div class="d-flex flex-wrap align-items-center gap-3 mt-2 small">
                        <a href="{{ \App\Support\Lkps::urlLampiran($tabel, $row->id, $n) }}" target="_blank" rel="noopener">
                            Lihat lampiran saat ini
                        </a>
                        <div class="form-check mb-0">
                            <input class="form-check-input" type="checkbox" name="hapus_{{ $n }}" value="1" id="hapus_{{ $n }}">
                            <label class="form-check-label" for="hapus_{{ $n }}">Hapus lampiran</label>
                        </div>
                        <span class="text-secondary">Pilih berkas baru untuk mengganti.</span>
                    </div>
                @endif
            @elseif ($otomatis)
                <input id="f_{{ $n }}" type="text" value="{{ $nilai }}" class="form-control" readonly>
                <div class="form-text">Dihitung otomatis saat data disimpan.</div>
            @else
                <input id="f_{{ $n }}" name="{{ $n }}" type="{{ $tipeInput }}" value="{{ $nilai }}"
                       @if ($k['type'] === 'decimal') step="0.01" @endif
                       @if ($k['type'] === 'number') step="1" min="0" @endif
                       @if ($wajib) required @endif
                       class="form-control @error($n) is-invalid @enderror">
                @if ($n === 'lampiran_link')
                    <div class="form-text">
                        Opsional: tempel link bukti (mis. Google Drive atau situs resmi), diawali http:// atau https://.
                        Boleh diisi bersama berkas lampiran atau sebagai pengganti berkas.
                    </div>
                @endif
            @endif

            @error($n)
                <div class="invalid-feedback d-block">{{ $message }}</div>
            @enderror
        </div>
    @endforeach

    <div class="d-flex gap-2 pt-2">
        <button class="btn btn-primary">{{ $row ? 'Simpan perubahan' : 'Simpan data' }}</button>
        <a href="{{ ! empty($def['tersembunyi']) ? route('lkps.isian.index') : route('lkps.tabel.index', $tabel) }}" class="btn btn-outline-secondary">Batal</a>
    </div>
</form>
@endsection
EOF

tulis app/Support/LkpsImporFile.php <<'EOF'
<?php

namespace App\Support;

/**
 * Pembaca file impor untuk SATU tabel LKPS: CSV (selalu bisa) dan Excel .xlsx/.xls
 * (bila PhpSpreadsheet terpasang). Kelas ini tidak menyentuh database.
 */
class LkpsImporFile
{
    public const MAKS_BARIS = 5000;

    public static function adaXlsx(): bool
    {
        return class_exists(\PhpOffice\PhpSpreadsheet\IOFactory::class);
    }

    /** @return array<int,array<int,mixed>> baris mentah (indeks dari 0); baris kosong = [] */
    public static function baca(string $path, string $ext): array
    {
        return in_array(strtolower($ext), ['xlsx', 'xls'], true) ? self::bacaExcel($path) : self::bacaCsv($path);
    }

    private static function bacaExcel(string $path): array
    {
        if (! self::adaXlsx()) {
            throw new \RuntimeException('Impor .xlsx/.xls membutuhkan pustaka PhpSpreadsheet (composer require phpoffice/phpspreadsheet). Simpan file sebagai CSV, atau pasang pustakanya.');
        }
        $reader = \PhpOffice\PhpSpreadsheet\IOFactory::createReaderForFile($path);
        $reader->setReadDataOnly(true);
        $book = $reader->load($path);
        $ws = $book->getSheetByName('Data') ?? $book->getSheet(0);

        return $ws->toArray(null, true, false, false);
    }

    public static function bacaCsv(string $path): array
    {
        $isi = (string) file_get_contents($path);
        if (str_starts_with($isi, "\xEF\xBB\xBF")) {
            $isi = substr($isi, 3);
        }
        if (! mb_check_encoding($isi, 'UTF-8')) {
            $isi = mb_convert_encoding($isi, 'UTF-8', 'Windows-1252');
        }

        // Pemisah dideteksi dari baris pertama: titik koma (Excel Indonesia), koma, atau tab.
        $pertama = strtok($isi, "\n") ?: '';
        $sep = ';';
        $maks = -1;
        foreach ([';', ',', "\t"] as $c) {
            $n = substr_count($pertama, $c);
            if ($n > $maks) {
                $maks = $n;
                $sep = $c;
            }
        }

        $h = fopen('php://temp', 'r+');
        fwrite($h, $isi);
        rewind($h);
        $hasil = [];
        while (($r = fgetcsv($h, 0, $sep, '"', '')) !== false) {
            $hasil[] = $r === [null] ? [] : $r;
            if (count($hasil) > self::MAKS_BARIS + 2) {
                break;
            }
        }
        fclose($h);

        return $hasil;
    }

    /** Samakan penulisan judul kolom: huruf kecil, tanpa tanda baca pemisah, spasi tunggal. */
    public static function norm(string $s): string
    {
        $s = str_replace(["\xC2\xA0", '–', '—', '-', '|', '_', '*', '(', ')'], ' ', $s);

        return mb_strtolower(preg_replace('/\s+/u', ' ', trim($s)), 'UTF-8');
    }

    /** @return array<int,string> indeks kolom file => nama kolom tabel */
    public static function petaKolom(array $header, array $kolom): array
    {
        $cari = [];
        foreach ($kolom as $n => $k) {
            $cari[self::norm($k['label'])] = $n;
        }
        foreach ($kolom as $n => $k) {
            $cari[self::norm($n)] ??= $n;
        }
        $peta = [];
        foreach ($header as $i => $h) {
            $kunci = self::norm((string) $h);
            if ($kunci !== '' && isset($cari[$kunci]) && ! in_array($cari[$kunci], $peta, true)) {
                $peta[$i] = $cari[$kunci];
            }
        }

        return $peta;
    }

    private static function kosong(array $r): bool
    {
        foreach ($r as $v) {
            if ($v !== null && trim((string) $v) !== '') {
                return false;
            }
        }

        return true;
    }

    /**
     * @param array $baris  hasil baca()
     * @param array $kolom  kolom yang boleh diimpor: nama => [label, type, rules, options]
     * @return array{baris:array<int,array>,abaikan:array<int,string>,kolom:array<int,string>}
     *         baris = [nomor baris di file => [kolom => nilai]]
     * @throws \InvalidArgumentException
     */
    public static function olah(array $baris, array $kolom): array
    {
        $idx = null;
        foreach ($baris as $i => $r) {
            if (! self::kosong($r)) {
                $idx = $i;
                break;
            }
        }
        if ($idx === null) {
            throw new \InvalidArgumentException('File tidak berisi data.');
        }

        $peta = self::petaKolom($baris[$idx], $kolom);
        if (! $peta) {
            throw new \InvalidArgumentException('Judul kolom pada baris pertama tidak dikenali. Unduh templat, lalu isi sesuai kolom di dalamnya.');
        }
        $dikenal = array_values($peta);

        $kurang = [];
        foreach ($kolom as $n => $k) {
            if (in_array('required', explode('|', $k['rules']), true) && ! in_array($n, $dikenal, true)) {
                $kurang[] = $k['label'];
            }
        }
        if ($kurang) {
            throw new \InvalidArgumentException('Kolom wajib tidak ada di file: ' . implode(', ', $kurang) . '.');
        }

        $abaikan = [];
        foreach ($baris[$idx] as $i => $h) {
            if (! isset($peta[$i]) && trim((string) $h) !== '') {
                $abaikan[] = trim((string) $h);
            }
        }

        $hasil = [];
        for ($i = $idx + 1, $n = count($baris); $i < $n; $i++) {
            if (self::kosong($baris[$i])) {
                continue;
            }
            $d = array_fill_keys($dikenal, null);
            foreach ($peta as $c => $nama) {
                $d[$nama] = self::nilai($kolom[$nama], $baris[$i][$c] ?? null);
            }
            $hasil[$i + 1] = $d;
        }

        return ['baris' => $hasil, 'abaikan' => $abaikan, 'kolom' => $dikenal];
    }

    /** Ubah sel mentah menjadi nilai yang sesuai jenis kolom. Nilai yang tidak bisa diubah dibiarkan agar ditolak validasi. */
    public static function nilai(array $k, mixed $v): mixed
    {
        $tipe = $k['type'];
        if ($tipe === 'check') {
            return in_array(mb_strtolower(trim((string) $v), 'UTF-8'), ['1', 'ya', 'y', 'yes', 'true', '√', 'v', 'x', 'ok', 'benar'], true);
        }
        if ($v === null || (is_string($v) && trim($v) === '')) {
            return null;
        }
        if (is_bool($v)) {
            $v = $v ? '1' : '0';
        }

        switch ($tipe) {
            case 'number':
                $a = self::angka($v);
                return (is_float($a) && floor($a) == $a) ? (int) $a : $a;
            case 'decimal':
                return self::angka($v);
            case 'date':
                return self::tanggal($v);
            case 'select':
                $s = trim((string) $v);
                foreach ($k['options'] as $opsi) {
                    if (mb_strtolower((string) $opsi, 'UTF-8') === mb_strtolower($s, 'UTF-8')) {
                        return (string) $opsi;
                    }
                }
                return $s;
            default:
                if (is_float($v) && floor($v) == $v && abs($v) < 1e15) {
                    return sprintf('%.0f', $v);   // NIDN/NUPTK yang terbaca sebagai angka
                }
                return trim((string) $v);
        }
    }

    private static function angka(mixed $v): mixed
    {
        if (is_int($v) || is_float($v)) {
            return $v;
        }
        $s = str_replace([' ', "\xC2\xA0"], '', trim((string) $v));
        if (preg_match('/^-?\d{1,3}(\.\d{3})+(,\d+)?$/', $s)) {            // 1.234,56
            $s = str_replace(['.', ','], ['', '.'], $s);
        } elseif (preg_match('/^-?\d+,\d+$/', $s)) {                        // 12,5
            $s = str_replace(',', '.', $s);
        } elseif (preg_match('/^-?\d{1,3}(,\d{3})+(\.\d+)?$/', $s)) {       // 1,234.56
            $s = str_replace(',', '', $s);
        }

        return is_numeric($s) ? $s + 0 : $v;
    }

    private static function tanggal(mixed $v): mixed
    {
        if (is_int($v) || is_float($v) || (is_string($v) && preg_match('/^\d{5}(\.\d+)?$/', trim($v)))) {
            $hari = (int) floor((float) $v);
            if ($hari > 0 && $hari < 80000) {   // nomor seri tanggal Excel
                return (new \DateTimeImmutable('1899-12-30'))->modify('+' . $hari . ' days')->format('Y-m-d');
            }
        }
        $s = trim((string) $v);
        foreach (['Y-m-d', 'Y-m-d H:i:s', 'd/m/Y', 'd-m-Y', 'd.m.Y', 'j/n/Y', 'j-n-Y'] as $f) {
            $d = \DateTimeImmutable::createFromFormat('!' . $f, $s);
            if ($d && $d->format($f) === $s) {
                return $d->format('Y-m-d');
            }
        }

        return $s;
    }

    // ------------------------------------------------------------------ templat

    private static function jenis(array $k): string
    {
        return match ($k['type']) {
            'number'   => 'Angka bulat',
            'decimal'  => 'Angka (boleh desimal)',
            'date'     => 'Tanggal (YYYY-MM-DD atau DD/MM/YYYY)',
            'check'    => 'Ya atau kosong',
            'select'   => 'Pilihan: ' . implode(', ', $k['options']),
            'url'      => 'Link (diawali http:// atau https://)',
            'textarea' => 'Teks panjang',
            default    => 'Teks',
        };
    }

    public static function templatCsv(array $kolom): string
    {
        $h = fopen('php://temp', 'r+');
        fputcsv($h, array_column($kolom, 'label'), ';', '"', '');
        rewind($h);

        return "\xEF\xBB\xBF" . stream_get_contents($h);
    }

    /** Berkas .xlsx: lembar "Data" (judul kolom) dan lembar "Petunjuk". Hanya dipanggil bila adaXlsx(). */
    public static function templatXlsx(string $judul, array $kolom): string
    {
        $book = new \PhpOffice\PhpSpreadsheet\Spreadsheet();
        $ws = $book->getActiveSheet();
        $ws->setTitle('Data');
        $i = 0;
        foreach ($kolom as $k) {
            $i++;
            $huruf = \PhpOffice\PhpSpreadsheet\Cell\Coordinate::stringFromColumnIndex($i);
            $ws->setCellValue($huruf . '1', $k['label']);
            $ws->getColumnDimension($huruf)->setAutoSize(true);
        }
        if ($i > 0) {
            $akhir = \PhpOffice\PhpSpreadsheet\Cell\Coordinate::stringFromColumnIndex($i);
            $ws->getStyle('A1:' . $akhir . '1')->getFont()->setBold(true);
        }
        $ws->freezePane('A2');

        $p = $book->createSheet();
        $p->setTitle('Petunjuk');
        $p->setCellValue('A1', 'Petunjuk impor: ' . $judul);
        $p->getStyle('A1')->getFont()->setBold(true);
        $p->setCellValue('A2', 'Isi data mulai baris 2 pada lembar "Data". Jangan mengubah judul kolom pada baris 1. Data baru DITAMBAHKAN; baris yang sudah ada tidak diubah.');
        $p->setCellValue('A4', 'Kolom');
        $p->setCellValue('B4', 'Jenis isian');
        $p->setCellValue('C4', 'Wajib');
        $p->getStyle('A4:C4')->getFont()->setBold(true);
        $r = 5;
        foreach ($kolom as $k) {
            $p->setCellValue('A' . $r, $k['label']);
            $p->setCellValue('B' . $r, self::jenis($k));
            $p->setCellValue('C' . $r, in_array('required', explode('|', $k['rules']), true) ? 'Ya' : '');
            $r++;
        }
        foreach (['A', 'B', 'C'] as $c) {
            $p->getColumnDimension($c)->setAutoSize(true);
        }
        $book->setActiveSheetIndex(0);

        $tmp = tempnam(sys_get_temp_dir(), 'lkps');
        try {
            \PhpOffice\PhpSpreadsheet\IOFactory::createWriter($book, 'Xlsx')->save($tmp);

            return (string) file_get_contents($tmp);
        } finally {
            @unlink($tmp);
        }
    }
}
EOF

tulis app/Http/Controllers/LkpsImporController.php <<'EOF'
<?php

namespace App\Http\Controllers;

use App\Support\Lkps;
use App\Support\LkpsImporFile;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

/**
 * Impor data SATU tabel LKPS dari Excel/CSV. Hanya MENAMBAH baris; bila ada satu baris
 * yang tidak valid, tidak ada baris yang disimpan (semua atau tidak sama sekali).
 */
class LkpsImporController extends Controller
{
    /** Kolom yang bisa diisi lewat file: bukan lampiran berkas dan bukan kolom total otomatis. */
    private function kolomImpor(string $tabel): array
    {
        $total = array_keys(Lkps::definisi($tabel)['total'] ?? []);

        return array_filter(
            Lkps::kolom($tabel),
            fn ($k, $n) => $k['type'] !== 'file' && ! in_array($n, $total, true),
            ARRAY_FILTER_USE_BOTH
        );
    }

    public function form(string $tabel)
    {
        return view('lkps.impor', [
            'tabel'    => $tabel,
            'def'      => Lkps::definisi($tabel),
            'kelompok' => Lkps::namaKelompok($tabel),
            'kolom'    => $this->kolomImpor($tabel),
            'xlsx'     => LkpsImporFile::adaXlsx(),
            'maks'     => LkpsImporFile::MAKS_BARIS,
        ]);
    }

    public function templat(Request $request, string $tabel)
    {
        $def = Lkps::definisi($tabel);
        $kolom = $this->kolomImpor($tabel);
        $dasar = 'templat_lkps_' . $tabel;

        if ($request->query('format') !== 'csv' && LkpsImporFile::adaXlsx()) {
            try {
                return response(LkpsImporFile::templatXlsx($def['judul'], $kolom), 200, [
                    'Content-Type'        => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                    'Content-Disposition' => 'attachment; filename="' . $dasar . '.xlsx"',
                ]);
            } catch (\Throwable $e) {
                // gagal membuat .xlsx: lanjut ke CSV
            }
        }

        return response(LkpsImporFile::templatCsv($kolom), 200, [
            'Content-Type'        => 'text/csv; charset=UTF-8',
            'Content-Disposition' => 'attachment; filename="' . $dasar . '.csv"',
        ]);
    }

    public function proses(Request $request, string $tabel)
    {
        $def = Lkps::definisi($tabel);
        $request->validate(['berkas' => ['required', 'file', 'max:' . Lkps::MAKS_LAMPIRAN_KB]], [], ['berkas' => 'File impor']);

        $file = $request->file('berkas');
        $ext = strtolower($file->getClientOriginalExtension());
        if (! in_array($ext, ['xlsx', 'xls', 'csv', 'txt'], true)) {
            return back()->withErrors(['berkas' => 'Format file harus .xlsx, .xls, atau .csv.']);
        }

        $kolom = $this->kolomImpor($tabel);
        try {
            $baris = LkpsImporFile::baca($file->getRealPath(), $ext);
            if (count($baris) > LkpsImporFile::MAKS_BARIS + 1) {
                throw new \InvalidArgumentException('Terlalu banyak baris (maksimal ' . LkpsImporFile::MAKS_BARIS . ' baris data per impor).');
            }
            $hasil = LkpsImporFile::olah($baris, $kolom);
        } catch (\Throwable $e) {
            return back()->withErrors(['berkas' => $e->getMessage()]);
        }
        if (! $hasil['baris']) {
            return back()->withErrors(['berkas' => 'Tidak ada baris data di bawah judul kolom.']);
        }

        // Periksa SEMUA baris dengan aturan yang sama seperti formulir "Tambah data".
        $aturan = array_intersect_key(Lkps::rules($tabel), array_flip($hasil['kolom']));
        $nama = Lkps::label($tabel);
        $galat = [];
        foreach ($hasil['baris'] as $no => $data) {
            $v = Validator::make($data, $aturan, [], $nama);
            if ($v->fails()) {
                $galat[] = "Baris {$no}: " . implode('; ', $v->errors()->all());
                if (count($galat) >= 30) {
                    $galat[] = 'Pemeriksaan dihentikan setelah 30 baris bermasalah.';
                    break;
                }
            }
        }
        if ($galat) {
            return back()
                ->withErrors(['berkas' => 'Tidak ada data yang disimpan karena ada baris yang tidak valid. Perbaiki file lalu unggah ulang.'])
                ->with('impor_galat', $galat);
        }

        $userId = $request->user()?->id;
        $now = now();
        $siap = [];
        foreach ($hasil['baris'] as $data) {
            foreach ($def['total'] ?? [] as $target => $sumber) {
                $data[$target] = array_sum(array_map(fn ($c) => (float) ($data[$c] ?? 0), $sumber));
            }
            $siap[] = $data + ['created_by' => $userId, 'created_at' => $now, 'updated_at' => $now];
        }
        DB::transaction(function () use ($tabel, $siap) {
            foreach (array_chunk($siap, 200) as $bagian) {
                DB::table(Lkps::namaTabel($tabel))->insert($bagian);
            }
        });

        $pesan = count($siap) . ' baris berhasil diimpor.'
            . ($hasil['abaikan'] ? ' Kolom yang tidak dikenali dan diabaikan: ' . implode(', ', $hasil['abaikan']) . '.' : '');
        $tujuan = ! empty($def['tersembunyi'])
            ? redirect()->to(route('lkps.isian.index') . '#dosen-homebase')
            : redirect()->route('lkps.tabel.index', $tabel);

        return $tujuan->with('ok', $pesan);
    }
}
EOF

tulis resources/views/lkps/impor.blade.php <<'EOF'
@extends('layout')
@section('title', 'Impor Excel - ' . $def['judul'])

@section('content')
@include('lkps._gaya')
<p class="lk-crumb">
    <a href="{{ route('lkps.daftar') }}" class="link-secondary">LKPS</a> / {{ $kelompok }} /
    <a href="{{ route('lkps.tabel.index', $tabel) }}" class="link-secondary">{{ $def['judul'] }}</a>
</p>
<h1 class="mb-1">Impor data dari Excel</h1>
<p class="text-secondary mb-4" style="max-width: 75ch">
    Data pada file <strong>ditambahkan</strong> ke tabel ini; baris yang sudah ada tidak diubah atau dihapus.
    Semua baris diperiksa lebih dulu: bila ada satu baris yang tidak valid, tidak ada data yang disimpan.
</p>

<div class="row g-3">
    <div class="col-12 col-lg-5">
        <section class="lk-panel h-100">
            <h2 class="mb-2">1. Unduh templat</h2>
            <p class="small text-secondary">Templat berisi judul kolom tabel ini. Isi mulai baris ke-2 dan jangan mengubah judul kolom.</p>
            <div class="d-flex flex-wrap gap-2 mb-4">
                @if ($xlsx)
                    <a href="{{ route('lkps.tabel.templat', $tabel) }}" class="btn btn-sm btn-outline-primary">Unduh templat Excel (.xlsx)</a>
                @endif
                <a href="{{ route('lkps.tabel.templat', [$tabel, 'format' => 'csv']) }}" class="btn btn-sm btn-outline-secondary">Unduh templat CSV</a>
            </div>
            @unless ($xlsx)
                <div class="alert alert-warning small">
                    Pustaka PhpSpreadsheet belum terpasang, jadi hanya file <strong>CSV</strong> yang bisa diimpor
                    (di Excel: Simpan Sebagai &rarr; CSV). Untuk impor .xlsx jalankan
                    <code>composer require phpoffice/phpspreadsheet</code>.
                </div>
            @endunless

            <h2 class="mb-2">2. Unggah file</h2>
            <form method="POST" action="{{ route('lkps.tabel.impor.proses', $tabel) }}" enctype="multipart/form-data">
                @csrf
                <input type="file" name="berkas" required
                       accept="{{ $xlsx ? '.xlsx,.xls,.csv,.txt' : '.csv,.txt' }}"
                       class="form-control @error('berkas') is-invalid @enderror">
                <div class="form-text">Maksimal {{ $maks }} baris data per impor. Lampiran Bukti berupa berkas tidak bisa diimpor; gunakan kolom link atau unggah dari menu Ubah data.</div>
                <div class="d-flex gap-2 mt-3">
                    <button class="btn btn-primary">Impor data</button>
                    <a href="{{ route('lkps.tabel.index', $tabel) }}" class="btn btn-outline-secondary">Batal</a>
                </div>
            </form>

            @if (session('impor_galat'))
                <div class="alert alert-danger small mt-3 mb-0">
                    <strong>Baris yang perlu diperbaiki:</strong>
                    <ul class="mb-0 mt-1">
                        @foreach (session('impor_galat') as $g)
                            <li>{{ $g }}</li>
                        @endforeach
                    </ul>
                </div>
            @endif
        </section>
    </div>

    <div class="col-12 col-lg-7">
        <section class="lk-panel h-100">
            <h2 class="mb-2">Kolom yang dibaca</h2>
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <thead><tr><th>Judul kolom</th><th>Jenis isian</th><th>Wajib</th></tr></thead>
                    <tbody>
                        @foreach ($kolom as $n => $k)
                            <tr>
                                <td>{{ $k['label'] }}</td>
                                <td class="small text-secondary">
                                    @switch($k['type'])
                                        @case('number') Angka bulat @break
                                        @case('decimal') Angka (boleh desimal) @break
                                        @case('date') Tanggal (YYYY-MM-DD atau DD/MM/YYYY) @break
                                        @case('check') Ya atau kosong @break
                                        @case('select') Pilihan: {{ implode(', ', $k['options']) }} @break
                                        @case('url') Link (diawali http:// atau https://) @break
                                        @case('textarea') Teks panjang @break
                                        @default Teks
                                    @endswitch
                                </td>
                                <td>{{ in_array('required', explode('|', $k['rules']), true) ? 'Ya' : '' }}</td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
        </section>
    </div>
</div>
@endsection
EOF

tulis resources/views/lkps/hero.blade.php <<'EOF'
@php $lkh = \App\Support\LkpsRingkasan::data(); @endphp
@if($lkh['tersedia'])<div><b>{{ $lkh['persen'] }}%</b>Kelengkapan LKPS</div>@endif
EOF

tulis resources/views/lkps/isian.blade.php <<'EOF'
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
                                @endif
                                @if (filled($d->lampiran_link ?? null) && preg_match('#^https?://#i', $d->lampiran_link))
                                    <a href="{{ $d->lampiran_link }}" target="_blank" rel="noopener">Buka link</a>
                                @endif
                                @if (! filled($d->lampiran_bukti ?? null) && ! filled($d->lampiran_link ?? null))
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

tulis resources/views/lkps/lampiran.blade.php <<'EOF'
@extends('layout')
@section('title', $label . ' - ' . $def['judul'])

@section('content')
@include('lkps._gaya')
<div class="d-flex flex-wrap justify-content-between align-items-end gap-3 mb-3">
    <div>
        <p class="lk-crumb">
            <a href="{{ route('lkps.tabel.index', $tabel) }}" class="link-secondary">{{ $def['judul'] }}</a>
        </p>
        <h1>{{ $label }}</h1>
        @if ($ringkas !== '')
            <p class="small text-secondary mb-0 mt-1">{{ $ringkas }}</p>
        @endif
    </div>
    <div class="d-flex gap-2">
        <a href="{{ $src }}" target="_blank" rel="noopener" class="btn btn-sm btn-outline-secondary">
            Buka di tab baru
        </a>
        <a href="{{ route('lkps.tabel.index', $tabel) }}" class="btn btn-sm btn-outline-secondary">Kembali ke tabel</a>
    </div>
</div>

<div class="lk-panel p-2">
    @if (str_starts_with($mime, 'image/'))
        <img src="{{ $src }}" alt="{{ $label }}" class="d-block mx-auto" style="max-width: 100%; max-height: 80vh">
    @elseif ($mime === 'application/pdf')
        <iframe src="{{ $src }}" title="{{ $label }}" style="width: 100%; height: 80vh; border: 0"></iframe>
    @else
        <p class="text-center text-secondary my-5">Jenis berkas ini tidak bisa dipratinjau di browser.</p>
    @endif
</div>
@endsection
EOF

tulis resources/views/lkps/tabel.blade.php <<'EOF'
@extends('layout')
@section('title', $def['judul'])

@section('content')
@include('lkps._gaya')
<div class="d-flex flex-wrap justify-content-between align-items-end gap-3 mb-3">
    <div>
        <p class="lk-crumb"><a href="{{ route('lkps.daftar') }}" class="link-secondary">LKPS</a> / {{ $kelompok }}</p>
        <h1>{{ $def['judul'] }}</h1>
        @if (! empty($def['keterangan']))
            <p class="small text-secondary mb-0 mt-1">{{ $def['keterangan'] }}</p>
        @endif
    </div>
    <div class="d-flex gap-2">
        <a href="{{ route('lkps.tabel.export', $tabel) }}" class="btn btn-sm btn-outline-secondary">
            Ekspor CSV
        </a>
        @auth
            <a href="{{ route('lkps.tabel.create', $tabel) }}" class="btn btn-sm btn-primary">
                Tambah data
            </a>
            <a href="{{ route('lkps.tabel.impor', $tabel) }}" class="btn btn-sm btn-outline-primary">
                Impor Excel
            </a>
        @endauth
    </div>
</div>

<form method="GET" class="d-flex gap-2 mb-3" style="max-width: 420px" role="search">
    <label for="cari" class="visually-hidden">Cari di tabel ini</label>
    <input id="cari" name="q" value="{{ $cari }}" class="form-control form-control-sm" placeholder="Cari di tabel ini">
    <button class="btn btn-sm btn-outline-secondary">Cari</button>
    @if ($cari !== '')
        <a href="{{ route('lkps.tabel.index', $tabel) }}" class="btn btn-sm btn-link">Reset</a>
    @endif
</form>

@if ($rows->isEmpty())
    <div class="lk-panel text-center py-5">
        @if ($cari !== '')
            <p class="mb-0">Tidak ada data yang cocok dengan "{{ $cari }}".</p>
        @else
            <p class="mb-3">Tabel ini belum berisi data.</p>
            @auth
                <a href="{{ route('lkps.tabel.create', $tabel) }}" class="btn btn-primary">Tambah data pertama</a>
            @else
                <a href="{{ route('login') }}" class="btn btn-outline-secondary">Masuk untuk menambah data</a>
            @endauth
        @endif
    </div>
@else
    <div class="lk-wrap table-responsive">
        <table class="table table-hover align-middle">
            <thead>
            @foreach ($header['baris'] as $i => $baris)
                <tr>
                    @if ($i === 0)
                        <th rowspan="{{ $header['depth'] }}">No</th>
                    @endif
                    @foreach ($baris as $c)
                        <th colspan="{{ $c['colspan'] }}" rowspan="{{ $c['rowspan'] }}" @class(['text-center' => $c['colspan'] > 1])>{{ $c['label'] }}</th>
                    @endforeach
                    @if ($i === 0)
                        @auth <th rowspan="{{ $header['depth'] }}" class="text-end">Aksi</th> @endauth
                    @endif
                </tr>
            @endforeach
            </thead>
            <tbody>
            @foreach ($rows as $row)
                <tr>
                    <td>{{ $rows->firstItem() + $loop->index }}</td>
                    @foreach ($kolom as $n => $k)
                        @php $v = $row->$n; @endphp
                        <td>
                            @if ($k['type'] === 'check')
                                {{ $v ? '√' : '' }}
                            @elseif ($v === null || $v === '')
                                <span class="text-secondary">–</span>
                            @elseif ($k['type'] === 'file')
                                <a href="{{ \App\Support\Lkps::urlLampiran($tabel, $row->id, $n) }}" target="_blank" rel="noopener" class="text-nowrap">
                                    Lihat bukti
                                </a>
                            @elseif ($k['type'] === 'url' && preg_match('#^https?://#i', $v))
                                <a href="{{ $v }}" target="_blank" rel="noopener">Buka tautan</a>
                            @elseif ($k['type'] === 'textarea')
                                {{ \Illuminate\Support\Str::limit($v, 80) }}
                            @elseif (in_array($k['type'], ['number', 'decimal'], true))
                                {{ \App\Support\Lkps::angka($v) }}
                            @else
                                {{ $v }}
                            @endif
                        </td>
                    @endforeach
                    @auth
                        <td class="text-end text-nowrap">
                            <a href="{{ route('lkps.tabel.edit', [$tabel, $row->id]) }}" class="btn btn-sm btn-outline-secondary">Ubah</a>
                            <form method="POST" action="{{ route('lkps.tabel.destroy', [$tabel, $row->id]) }}" class="d-inline"
                                  onsubmit="return confirm('Hapus baris ini? Data tidak bisa dikembalikan.')">
                                @csrf
                                @method('DELETE')
                                <button class="btn btn-sm btn-outline-danger">Hapus</button>
                            </form>
                        </td>
                    @endauth
                </tr>
            @endforeach
            </tbody>
            @if ($ringkasan)
                <tfoot>
                @foreach ($ringkasan as $labelRingkasan => $nilai)
                    <tr class="ringkasan">
                        <th>{{ $labelRingkasan }}</th>
                        @foreach ($kolom as $n => $k)
                            <td>{{ array_key_exists($n, $nilai) && $nilai[$n] !== null ? \App\Support\Lkps::angka($nilai[$n]) : '' }}</td>
                        @endforeach
                        @auth <td></td> @endauth
                    </tr>
                @endforeach
                </tfoot>
            @endif
        </table>
    </div>
    <div class="mt-3">{{ $rows->links('pagination::bootstrap-5') }}</div>
@endif
@endsection
EOF

# template Excel opsional (disalin hanya bila belum ada)
if [ -n "$LKPS_TEMPLATE" ]; then
  if [ -f "$LKPS_TEMPLATE" ]; then
    mkdir -p storage/app/lkps
    [ -f storage/app/lkps/template.xlsx ] && [ "$TIMPA" != 1 ] && echo "  (template sudah ada, dilewati)" || { cp "$LKPS_TEMPLATE" storage/app/lkps/template.xlsx; echo "  OK  template Excel disalin"; }
  else echo "  PERINGATAN: LKPS_TEMPLATE '$LKPS_TEMPLATE' tidak ditemukan."; fi
fi
# tahun TS pada .env (hanya ditambah bila belum ada)
if [ -f .env ] && ! grep -q '^LKPS_TAHUN_TS=' .env; then
  printf '\n# Tahun akademik TS untuk LKPS\nLKPS_TAHUN_TS="%s"\n' "$LKPS_TAHUN_TS" >> .env
  echo "  OK  .env: LKPS_TAHUN_TS=$LKPS_TAHUN_TS"
fi
for f in config/lkps.php config/lkps_excel.php app/Support/Lkps.php app/Support/LkpsExcel.php app/Support/LkpsData.php app/Support/LkpsRingkasan.php \
         "$MIG" app/Console/Commands/LkpsSinkron.php app/Console/Commands/LkpsImpor.php app/Console/Commands/LkpsEkspor.php \
         app/Http/Controllers/LkpsController.php app/Http/Controllers/LkpsExcelController.php app/Http/Controllers/LkpsIsianController.php app/Http/Controllers/LkpsLampiranController.php; do
  php -l "$f" >/dev/null || { echo "GAGAL: kesalahan sintaks pada $f"; exit 1; }
done
echo "  OK  sintaks semua berkas PHP"

# ---------- 5. TABEL LKPS (hanya menambah) ----------
echo "[5/7] Membuat tabel lkps_* (hanya migration LKPS yang dijalankan)..."
php artisan config:clear >/dev/null 2>&1 || true
if ! php artisan migrate --force --path="$MIG"; then
  echo ""
  echo "GAGAL membuat tabel. Data Anda tidak berubah dan tampilan aplikasi belum diubah."
  echo "Periksa hak CREATE pada user database, lalu jalankan ulang skrip ini (aman diulang)."
  exit 1
fi
php artisan lkps:sinkron

# ---------- 6. ROUTE, MENU, DASHBOARD (disisipi, bukan ditimpa) ----------
echo "[6/7] Menyisipkan route, menu, dan dashboard..."
if grep -q "Route::prefix(.lkps.)" "$R"; then
  echo "  (route LKPS sudah ada, dilewati)"
else
cat >> "$R" <<'EOF'

// ===== LKPS: baca publik; tambah/ubah/hapus wajib login; impor Excel & unggah template khusus admin =====
Route::prefix('lkps')->name('lkps.')->group(function () {
    $admin = class_exists(\App\Http\Middleware\HanyaAdmin::class) ? ['auth', \App\Http\Middleware\HanyaAdmin::class] : ['auth'];

    Route::get('/', [\App\Http\Controllers\LkpsController::class, 'daftar'])->name('daftar');

    Route::get('/isian', [\App\Http\Controllers\LkpsIsianController::class, 'index'])->name('isian.index');
    Route::post('/isian', [\App\Http\Controllers\LkpsIsianController::class, 'simpan'])->middleware('auth')->name('isian.simpan');

    Route::get('/excel', [\App\Http\Controllers\LkpsExcelController::class, 'index'])->name('excel.index');
    Route::get('/excel/ekspor', [\App\Http\Controllers\LkpsExcelController::class, 'ekspor'])->name('excel.ekspor');
    Route::middleware($admin)->group(function () {
        Route::post('/excel/template', [\App\Http\Controllers\LkpsExcelController::class, 'unggahTemplate'])->name('excel.template');
        Route::post('/excel/impor', [\App\Http\Controllers\LkpsExcelController::class, 'impor'])->name('excel.impor');
    });

    Route::get('/lampiran/{tabel}/{id}/{kolom?}', [\App\Http\Controllers\LkpsLampiranController::class, 'lihat'])
        ->whereNumber('id')->where(['tabel' => '[a-z0-9_]+', 'kolom' => '[a-z0-9_]+'])->name('lampiran.lihat');
    Route::get('/lampiran/{tabel}/{id}/{kolom}/berkas', [\App\Http\Controllers\LkpsLampiranController::class, 'berkas'])
        ->whereNumber('id')->where(['tabel' => '[a-z0-9_]+', 'kolom' => '[a-z0-9_]+'])->name('lampiran.berkas');

    Route::prefix('tabel/{tabel}')->name('tabel.')->where(['tabel' => '[a-z0-9_]+'])->group(function () {
        Route::get('/', [\App\Http\Controllers\LkpsController::class, 'index'])->name('index');
        Route::get('/ekspor', [\App\Http\Controllers\LkpsController::class, 'export'])->name('export');
        Route::middleware('auth')->group(function () {
            Route::get('/tambah', [\App\Http\Controllers\LkpsController::class, 'create'])->name('create');
            Route::post('/', [\App\Http\Controllers\LkpsController::class, 'store'])->name('store');
            Route::get('/{id}/ubah', [\App\Http\Controllers\LkpsController::class, 'edit'])->whereNumber('id')->name('edit');
            Route::put('/{id}', [\App\Http\Controllers\LkpsController::class, 'update'])->whereNumber('id')->name('update');
            Route::delete('/{id}', [\App\Http\Controllers\LkpsController::class, 'destroy'])->whereNumber('id')->name('destroy');
            Route::get('/impor', [\App\Http\Controllers\LkpsImporController::class, 'form'])->name('impor');
            Route::get('/templat', [\App\Http\Controllers\LkpsImporController::class, 'templat'])->name('templat');
            Route::post('/impor', [\App\Http\Controllers\LkpsImporController::class, 'proses'])->name('impor.proses');
        });
    });
});
EOF
  php -l "$R" >/dev/null || { echo "GAGAL: routes/web.php tidak valid. Pulihkan dari $R.bak8"; exit 1; }
  echo "  OK  $R"
fi

# menu "LKPS" di bawah Data Induk (setelah sub menu Data Induk terakhir)
if grep -q "lkps.daftar" "$L"; then
  echo "  (menu LKPS sudah ada, dilewati)"
elif grep -q 'datainduk.index' "$L"; then
  M=$(cat <<'EOF'
      @if(Route::has('lkps.daftar'))
      <a class="mi sub {{ request()->routeIs('lkps.*') ? 'on' : '' }}" href="{{ route('lkps.daftar') }}">LKPS</a>
      @endif
EOF
)
  export M
  perl -0pi -e 's/((?:^[ \t]*<a class="mi sub [^\n]*datainduk\.index[^\n]*<\/a>\n)+)/$1$ENV{M}\n/m' "$L"
  grep -q "lkps.daftar" "$L" && echo "  OK  menu LKPS di bawah Data Induk" || echo "  PERINGATAN: menu tidak terpasang (pola layout berbeda). LKPS tetap dapat dibuka di /lkps."
else
  echo "  PERINGATAN: menu Data Induk tidak ditemukan di layout. Tambahkan tautan ke route('lkps.daftar') secara manual; LKPS dapat dibuka di /lkps."
fi

# Dashboard Akreditasi: angka "Kelengkapan LKPS" di kartu utama + bagian ringkasan
if [ -f "$DBV" ] && ! grep -q "lkps\." "$DBV"; then
  perl -0pi -e 's/(^[ \t]*<div><b>\{\{ \$total\[\x27dokumen\x27\] \}\}%<\/b>Kelengkapan dokumen<\/div>\n)/$1    \@includeIf(\x27lkps.hero\x27)\n/m' "$DBV"
  perl -0pi -e 's/\n\@endsection\s*\z/\n\n\@includeIf(\x27lkps.dashboard\x27)\n\@endsection\n/' "$DBV"
  grep -q "lkps.hero" "$DBV" && echo "  OK  angka LKPS di kartu utama dashboard" || echo "  PERINGATAN: kartu utama dashboard berbeda dari yang diharapkan; angka LKPS pada kartu utama dilewati."
  grep -q "lkps.dashboard" "$DBV" && echo "  OK  bagian Kelengkapan LKPS di dashboard" || echo "  PERINGATAN: bagian LKPS di dashboard tidak terpasang (tambahkan @includeIf('lkps.dashboard') sebelum @endsection)."
elif [ -f "$DBV" ]; then
  echo "  (dashboard sudah memuat LKPS, dilewati)"
else
  echo "  PERINGATAN: $DBV tidak ditemukan; dashboard tidak diubah."
fi

# ---------- 7. SELESAI ----------
echo "[7/7] Membersihkan cache..."
php artisan optimize:clear >/dev/null 2>&1 || true
echo ""
echo "============================================================"
echo " LKPS BERHASIL DITAMBAHKAN"
echo "============================================================"
echo " Menu    : sidebar > Data Induk > LKPS  (alamat: /lkps)"
echo " Dashboard: kelengkapan LKPS tampil di Dashboard Akreditasi"
echo " Hak akses: lihat = publik; tambah/ubah/hapus = login; impor Excel & unggah template = admin"
echo " Excel   : menu LKPS > Impor & ekspor Excel (unggah template resmi LKPS .xlsx lebih dulu)"
echo " Perintah: php artisan lkps:sinkron | lkps:impor file.xlsx [--ganti] | lkps:ekspor [hasil.xlsx]"
echo " Cadangan: *.bak8 dan storage/app/cadangan-sebelum-lkps-*.sql"
echo " Jika memakai cache produksi: php artisan config:cache && php artisan route:cache && php artisan view:cache"
EOF_MODUL_LKPS_Q7
cat > "$M/03-analitik-lima.sh" <<'EOF_MODUL_LIMA_Q7'
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
EOF_MODUL_LIMA_Q7
cat > "$M/04-data-induk-db.sh" <<'EOF_MODUL_DIDB_Q7'
#!/usr/bin/env bash
# =====================================================================
# MIGRASI DATA INDUK KE DATABASE (aman, tidak merusak data yang ada)
# Sistem Informasi Akreditasi Program Studi Teknologi Informasi
# Sekolah Vokasi Universitas Tiga Serangkai
#
# Memindahkan metadata Data Induk (Dokumen Standar Mutu, Universitas, Fakultas,
# Tambahan) dari berkas JSON ke tabel database "data_induk_dokumen".
#
# JAMINAN KEAMANAN:
#  - Hanya MENAMBAH satu tabel baru. Tabel dan data yang ada tidak disentuh.
#  - Berkas unggahan TIDAK dipindah (path tetap sama).
#  - Berkas JSON lama TIDAK dihapus (tetap sebagai cadangan).
#  - Sebelum mengubah apa pun: cadangan database (mysqldump), JSON, dan kode.
#  - Database baru baru dipakai SETELAH impor diverifikasi (penanda berkas).
#    Bila gagal di tengah jalan, aplikasi tetap memakai JSON seperti semula.
#  - Kembali ke JSON kapan saja:  php artisan datainduk:kembali-ke-json
#
# Pemakaian (di root proyek):  bash migrasi-data-induk-db.sh [--tanpa-dump]
#   --tanpa-dump   lewati mysqldump (HANYA bila Anda sudah membuat cadangan sendiri)
# =====================================================================
set -e
if [ ! -f artisan ]; then echo "Error: jalankan di root proyek Laravel."; exit 1; fi

TANPA_DUMP=0
for a in "$@"; do
  case "$a" in
    --tanpa-dump) TANPA_DUMP=1;;
    -h|--help) sed -n '2,21p' "$0"; exit 0;;
    *) echo "Opsi tidak dikenal: $a"; exit 1;;
  esac
done

D=app/Support/DataInduk.php
MIG=database/migrations/2026_10_07_000001_create_data_induk_dokumen_table.php
TS=$(date +%Y%m%d-%H%M%S)

if [ ! -f "$D" ]; then echo "Error: $D tidak ditemukan (menu Data Induk belum terpasang)."; exit 1; fi
if ! grep -q "const KATEGORI" "$D"; then echo "Error: konstanta KATEGORI tidak ditemukan di $D."; exit 1; fi

echo "[1/6] Memeriksa koneksi database..."
if ! php artisan migrate:status >/dev/null 2>&1; then
  echo "  GAGAL: tidak dapat terhubung ke database. Periksa DB_* pada .env, lalu ulangi."
  exit 1
fi
echo "  OK"

# ---------- 2. CADANGAN ----------
echo "[2/6] Membuat cadangan..."
mkdir -p storage/app
envval() { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//'; }
if [ "$TANPA_DUMP" = 1 ]; then
  echo "  --  cadangan database dilewati (--tanpa-dump)"
else
  CONN=$(envval DB_CONNECTION)
  if { [ "$CONN" = mysql ] || [ "$CONN" = mariadb ]; } && command -v mysqldump >/dev/null 2>&1; then
    DUMP="storage/app/cadangan-sebelum-migrasi-datainduk-$TS.sql"
    if MYSQL_PWD="$(envval DB_PASSWORD)" mysqldump -h "$(envval DB_HOST)" -P "$(envval DB_PORT)" -u "$(envval DB_USERNAME)" \
         --single-transaction --no-tablespaces "$(envval DB_DATABASE)" > "$DUMP" 2>/dev/null && [ -s "$DUMP" ]; then
      echo "  OK  database  -> $DUMP"
    else
      rm -f "$DUMP"
      echo "  GAGAL membuat cadangan database. Tidak ada yang diubah."
      echo "  Buat cadangan manual (phpMyAdmin > Export, atau mysqldump), lalu jalankan ulang dengan --tanpa-dump."
      exit 1
    fi
  else
    echo "  GAGAL: mysqldump tidak tersedia atau DB_CONNECTION bukan mysql/mariadb. Tidak ada yang diubah."
    echo "  Buat cadangan database manual, lalu jalankan ulang dengan --tanpa-dump."
    exit 1
  fi
fi
if [ -d storage/app/data-induk ]; then
  cp -a storage/app/data-induk "storage/app/data-induk-cadangan-$TS"
  echo "  OK  JSON      -> storage/app/data-induk-cadangan-$TS"
fi
if grep -q "function pakaiDb" "$D"; then
  echo "  --  kode sudah versi database; cadangan asli ($D.bak7) tidak ditimpa"
else
  cp "$D" "$D.bak7"
  echo "  OK  kode      -> $D.bak7"
fi

# ---------- 3. BERKAS BARU ----------
echo "[3/6] Menulis berkas migration, model, dan perintah..."
mkdir -p app/Models app/Console/Commands database/migrations

cat > "$MIG" <<'EOF'
<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Hanya MENAMBAH tabel baru; tidak mengubah tabel yang sudah ada.
return new class extends Migration {
    public function up(): void {
        if (Schema::hasTable('data_induk_dokumen')) return;
        Schema::create('data_induk_dokumen', function (Blueprint $t) {
            $t->uuid('id')->primary();                    // memakai UUID lama sehingga alamat/tautan lama tetap berlaku
            $t->string('kategori', 40);                   // standar-mutu | universitas | fakultas | stmik-sinus
            $t->string('nama');
            $t->text('keterangan')->nullable();
            $t->string('file_path')->nullable();          // berkas fisik tidak dipindah
            $t->string('nama_file')->nullable();
            $t->unsignedBigInteger('ukuran')->nullable();
            $t->string('link', 500)->nullable();
            $t->foreignId('diunggah_oleh')->nullable()->constrained('users')->nullOnDelete();
            $t->timestamps();
            $t->index(['kategori', 'created_at']);
        });
    }
    public function down(): void {
        // JSON lama tetap ada; aplikasi otomatis kembali memakai JSON bila tabel tidak ada.
        Schema::dropIfExists('data_induk_dokumen');
    }
};
EOF

cat > app/Models/DataIndukDokumen.php <<'EOF'
<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;

class DataIndukDokumen extends Model {
    protected $table = 'data_induk_dokumen';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['id', 'kategori', 'nama', 'keterangan', 'file_path', 'nama_file', 'ukuran', 'link', 'diunggah_oleh'];
    public function pengunggah() { return $this->belongsTo(User::class, 'diunggah_oleh'); }
}
EOF

cat > app/Support/DataIndukMigrasi.php <<'EOF'
<?php
namespace App\Support;
use Illuminate\Support\Facades\DB;

// Logika impor/verifikasi/ekspor antara JSON dan tabel data_induk_dokumen
class DataIndukMigrasi {
    private static function tanggal($v): string {
        $t = is_string($v) ? strtotime($v) : false;
        return $t ? date('Y-m-d H:i:s', $t) : date('Y-m-d H:i:s');
    }

    // JSON -> tabel. Yang id-nya sudah ada di tabel dilewati (tidak ditimpa).
    public static function impor(bool $dry = false): array {
        $hasil = [];
        foreach (array_keys(DataInduk::KATEGORI) as $k) {
            $json = DataInduk::semuaJson($k);
            $baru = $ada = $lewat = 0;
            $rows = [];
            foreach ($json as $x) {
                if (empty($x['id']) || empty($x['nama'])) { $lewat++; continue; }
                if (DB::table(DataInduk::TABEL)->where('id', $x['id'])->exists()) { $ada++; continue; }
                $rows[] = [
                    'id' => $x['id'], 'kategori' => $k, 'nama' => $x['nama'],
                    'keterangan' => $x['keterangan'] ?? null, 'file_path' => $x['file'] ?? null,
                    'nama_file' => $x['nama_file'] ?? null, 'ukuran' => $x['ukuran'] ?? null,
                    'link' => $x['link'] ?? null,
                    'created_at' => self::tanggal($x['dibuat'] ?? null), 'updated_at' => self::tanggal($x['diubah'] ?? null),
                ];
                $baru++;
            }
            if (!$dry && $rows) {
                DB::transaction(function () use ($rows) {
                    foreach (array_chunk($rows, 200) as $c) DB::table(DataInduk::TABEL)->insert($c);
                });
            }
            $hasil[$k] = ['json' => count($json), 'baru' => $baru, 'sudah_ada' => $ada, 'dilewati' => $lewat];
        }
        return $hasil;
    }

    // Setiap id di JSON harus ada di tabel pada kategori yang sama
    public static function verifikasi(): array {
        $hasil = [];
        foreach (array_keys(DataInduk::KATEGORI) as $k) {
            $json = DataInduk::semuaJson($k);
            $idDb = [];
            foreach (DB::table(DataInduk::TABEL)->where('kategori', $k)->get() as $r) $idDb[$r->id] = true;
            $hilang = [];
            foreach ($json as $x) {
                if (empty($x['id']) || empty($x['nama'])) continue;
                if (!isset($idDb[$x['id']])) $hilang[] = $x['id'];
            }
            $hasil[$k] = ['json' => count($json), 'db' => count($idDb), 'hilang' => $hilang];
        }
        return $hasil;
    }

    // Tabel -> JSON (jalan kembali). JSON lama dicadangkan dulu.
    public static function ekspor(): array {
        $hasil = [];
        foreach (array_keys(DataInduk::KATEGORI) as $k) {
            $p = storage_path('app/data-induk/' . $k . '.json');
            if (is_file($p)) copy($p, $p . '.bak-' . date('Ymd-His'));
            $rows = [];
            foreach (DB::table(DataInduk::TABEL)->where('kategori', $k)->orderBy('created_at')->orderBy('id')->get() as $r) {
                $rows[] = DataInduk::dariBaris($r);
            }
            DataInduk::tulisJson($k, $rows);
            $hasil[$k] = count($rows);
        }
        return $hasil;
    }
}
EOF

cat > app/Console/Commands/ImporDataIndukJson.php <<'EOF'
<?php
namespace App\Console\Commands;
use App\Support\DataInduk;
use App\Support\DataIndukMigrasi;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Schema;

class ImporDataIndukJson extends Command {
    protected $signature = 'datainduk:impor-json {--dry-run : hanya tampilkan ringkasan, tidak menulis} {--tanpa-aktifkan : impor saja, jangan aktifkan database} {--paksa : impor ulang walau database sudah aktif}';
    protected $description = 'Impor Data Induk dari JSON ke tabel database (aman, tidak menimpa) dan aktifkan setelah terverifikasi';

    public function handle(): int {
        if (!Schema::hasTable(DataInduk::TABEL)) {
            $this->error('Tabel ' . DataInduk::TABEL . ' belum ada. Jalankan migration terlebih dahulu.');
            return self::FAILURE;
        }
        if (is_file(DataInduk::penanda()) && !$this->option('paksa')) {
            $this->info('Database sudah aktif; impor dilewati. (Impor ulang dapat mengembalikan dokumen yang sudah dihapus; pakai --paksa bila memang perlu.)');
            return self::SUCCESS;
        }
        $dry = (bool) $this->option('dry-run');
        $h = DataIndukMigrasi::impor($dry);
        $this->table(['Kategori', 'Di JSON', 'Diimpor baru', 'Sudah ada', 'Dilewati'],
            collect($h)->map(fn ($r, $k) => [$k, $r['json'], $r['baru'], $r['sudah_ada'], $r['dilewati']])->values()->all());
        if ($dry) { $this->warn('Dry-run: tidak ada data yang ditulis.'); return self::SUCCESS; }

        $ok = true;
        $rows = [];
        foreach (DataIndukMigrasi::verifikasi() as $k => $r) {
            $rows[] = [$k, $r['json'], $r['db'], count($r['hilang'])];
            if ($r['hilang']) { $ok = false; $this->error("Kategori $k: id belum ada di database: " . implode(', ', $r['hilang'])); }
        }
        $this->table(['Kategori', 'JSON', 'Database', 'Hilang'], $rows);
        if (!$ok) {
            $this->error('Verifikasi GAGAL. Database TIDAK diaktifkan; aplikasi tetap memakai JSON.');
            return self::FAILURE;
        }
        if ($this->option('tanpa-aktifkan')) { $this->info('Verifikasi OK. Database belum diaktifkan (--tanpa-aktifkan).'); return self::SUCCESS; }
        @mkdir(dirname(DataInduk::penanda()), 0775, true);
        file_put_contents(DataInduk::penanda(), date('c'));
        $this->info('Verifikasi OK. Data Induk kini memakai database. Berkas JSON lama dipertahankan sebagai cadangan.');
        return self::SUCCESS;
    }
}
EOF

cat > app/Console/Commands/KembaliKeJsonDataInduk.php <<'EOF'
<?php
namespace App\Console\Commands;
use App\Support\DataInduk;
use App\Support\DataIndukMigrasi;
use Illuminate\Console\Command;

class KembaliKeJsonDataInduk extends Command {
    protected $signature = 'datainduk:kembali-ke-json';
    protected $description = 'Ekspor isi database Data Induk ke JSON lalu kembali memakai JSON (jalan kembali)';

    public function handle(): int {
        $h = DataIndukMigrasi::ekspor();
        foreach ($h as $k => $n) $this->line("  $k: $n dokumen ditulis ke JSON");
        if (is_file(DataInduk::penanda())) unlink(DataInduk::penanda());
        $this->info('Selesai. Aplikasi kembali memakai JSON. Tabel database tidak dihapus.');
        return self::SUCCESS;
    }
}
EOF

# ---------- DataInduk.php baru (KATEGORI lama dipertahankan) ----------
if grep -q "function pakaiDb" "$D"; then
  echo "  (DataInduk.php sudah versi database, dilewati)"
else
  KAT=$(perl -0ne 'print $1 if /(const KATEGORI = \[.*?\];)/s' "$D")
  if [ -z "$KAT" ]; then echo "GAGAL membaca KATEGORI dari $D."; exit 1; fi
  cat > "$D.new" <<'EOF'
<?php
namespace App\Support;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class DataInduk {
    __KATEGORI__
    const TABEL = 'data_induk_dokumen';
    private static ?bool $db = null;

    public static function judul(string $k): string {
        return self::KATEGORI[$k] ?? abort(404);
    }

    // Berkas penanda dibuat HANYA setelah impor JSON -> database terverifikasi
    public static function penanda(): string {
        return storage_path('app/data-induk/.db-aktif');
    }
    // Database dipakai bila tabel ada DAN penanda ada; selain itu tetap JSON (perilaku lama)
    public static function pakaiDb(): bool {
        if (self::$db === null) {
            try { self::$db = is_file(self::penanda()) && Schema::hasTable(self::TABEL); }
            catch (\Throwable $e) { self::$db = false; }
        }
        return self::$db;
    }
    public static function segarkan(): void { self::$db = null; }

    // ---------- API (tidak berubah bagi controller) ----------
    public static function semua(string $k): array {
        return self::pakaiDb() ? self::semuaDb($k) : self::semuaJson($k);
    }
    public static function cari(string $k, string $id): ?array {
        if (self::pakaiDb()) {
            $r = DB::table(self::TABEL)->where('kategori', $k)->where('id', $id)->first();
            return $r ? self::dariBaris($r) : null;
        }
        foreach (self::semuaJson($k) as $x) if (($x['id'] ?? null) === $id) return $x;
        return null;
    }
    // Baca-ubah-tulis: $fn menerima array dokumen kategori, mengembalikan array baru
    public static function ubah(string $k, callable $fn): void {
        self::pakaiDb() ? self::ubahDb($k, $fn) : self::ubahJson($k, $fn);
    }

    // ---------- Database ----------
    public static function dariBaris($r): array {
        return [
            'id' => $r->id, 'nama' => $r->nama, 'keterangan' => $r->keterangan,
            'file' => $r->file_path, 'nama_file' => $r->nama_file,
            'ukuran' => $r->ukuran !== null ? (int) $r->ukuran : null,
            'link' => $r->link, 'dibuat' => $r->created_at, 'diubah' => $r->updated_at,
        ];
    }
    private static function keBaris(string $k, array $x): array {
        return [
            'id' => $x['id'], 'kategori' => $k, 'nama' => $x['nama'], 'keterangan' => $x['keterangan'] ?? null,
            'file_path' => $x['file'] ?? null, 'nama_file' => $x['nama_file'] ?? null,
            'ukuran' => $x['ukuran'] ?? null, 'link' => $x['link'] ?? null,
            'created_at' => $x['dibuat'] ?? date('Y-m-d H:i:s'), 'updated_at' => $x['diubah'] ?? date('Y-m-d H:i:s'),
        ];
    }
    private static function semuaDb(string $k): array {
        $out = [];
        foreach (DB::table(self::TABEL)->where('kategori', $k)->orderBy('created_at')->orderBy('id')->get() as $r) {
            $out[] = self::dariBaris($r);
        }
        return $out;
    }
    private static function ubahDb(string $k, callable $fn): void {
        DB::transaction(function () use ($k, $fn) {
            $lama = [];
            foreach (DB::table(self::TABEL)->where('kategori', $k)->lockForUpdate()->get() as $r) {
                $lama[$r->id] = self::dariBaris($r);
            }
            $baru = [];
            foreach ($fn(array_values($lama)) as $x) $baru[$x['id']] = $x;
            $hapus = array_values(array_diff(array_keys($lama), array_keys($baru)));
            if ($hapus) DB::table(self::TABEL)->where('kategori', $k)->whereIn('id', $hapus)->delete();
            foreach ($baru as $id => $x) {
                if (!isset($lama[$id])) {
                    $b = self::keBaris($k, $x);
                    if (function_exists('auth') && auth()->check()) $b['diunggah_oleh'] = auth()->id();
                    DB::table(self::TABEL)->insert($b);
                } elseif ($x != $lama[$id]) {
                    $b = self::keBaris($k, $x);
                    unset($b['id'], $b['kategori']);
                    DB::table(self::TABEL)->where('kategori', $k)->where('id', $id)->update($b);
                }
            }
        });
    }

    // ---------- JSON (cara lama; dipakai sebelum migrasi dan sebagai jalan kembali) ----------
    private static function path(string $k): string {
        return storage_path('app/data-induk/' . $k . '.json');
    }
    public static function semuaJson(string $k): array {
        $p = self::path($k);
        if (!is_file($p)) return [];
        $d = json_decode((string) file_get_contents($p), true);
        return is_array($d) ? $d : [];
    }
    public static function tulisJson(string $k, array $data): void {
        self::ubahJson($k, fn () => $data);
    }
    private static function ubahJson(string $k, callable $fn): void {
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

    // Format ukuran berkas tanpa ekstensi PHP intl
    public static function ukuran($bytes): string {
        $b = (float) $bytes;
        $u = ['B', 'KB', 'MB', 'GB'];
        $i = 0;
        while ($b >= 1024 && $i < 3) { $b /= 1024; $i++; }
        return ($i === 0 ? (string) (int) $b : number_format($b, 1, ',', '.')) . ' ' . $u[$i];
    }
}
EOF
  KAT="$KAT" perl -0pi -e 's/__KATEGORI__/$ENV{KAT}/' "$D.new"
  mv "$D.new" "$D"
  echo "  OK  $D (daftar kategori lama dipertahankan)"
fi
for f in "$MIG" app/Models/DataIndukDokumen.php app/Support/DataIndukMigrasi.php app/Console/Commands/ImporDataIndukJson.php app/Console/Commands/KembaliKeJsonDataInduk.php "$D"; do
  php -l "$f" >/dev/null || { echo "GAGAL: kesalahan sintaks pada $f. Pulihkan dari $D.bak7"; exit 1; }
done
echo "  OK  sintaks semua berkas"

# ---------- 4. MIGRATION (hanya berkas ini) ----------
echo "[4/6] Membuat tabel data_induk_dokumen (hanya migration ini yang dijalankan)..."
php artisan migrate --force --path="$MIG"

# ---------- 5. IMPOR + VERIFIKASI + AKTIFKAN ----------
echo "[5/6] Impor JSON -> database, verifikasi, lalu aktifkan..."
if ! php artisan datainduk:impor-json; then
  echo ""
  echo "Impor/verifikasi GAGAL. Aplikasi TETAP memakai JSON seperti semula (tidak ada data yang hilang)."
  echo "Perbaiki penyebabnya lalu jalankan ulang skrip ini (aman diulang)."
  exit 1
fi

# ---------- 6. SELESAI ----------
echo "[6/6] Membersihkan cache..."
php artisan optimize:clear >/dev/null 2>&1 || true
echo ""
echo "============================================================"
echo " MIGRASI DATA INDUK KE DATABASE SELESAI"
echo "============================================================"
echo " Cek: buka menu Data Induk dan bandingkan jumlah dokumen tiap kategori."
echo " Cadangan: storage/app/data-induk-cadangan-$TS (JSON), $D.bak7 (kode)"
echo " Jalan kembali ke JSON: php artisan datainduk:kembali-ke-json"
echo " Jika memakai cache produksi: php artisan config:cache && php artisan route:cache && php artisan view:cache"
echo " Setelah yakin (beberapa hari), JSON lama boleh dibiarkan sebagai arsip; jangan dihapus terburu-buru."
EOF_MODUL_DIDB_Q7
ok "modul siap"

# ---------- [5] Pemasangan ----------
cd_proyek=$(pwd)
ARG_EXCEL=""; [ "$TANPA_EXCEL" = 1 ] && ARG_EXCEL="--tanpa-excel"

echo ""
echo "[5/9] Aplikasi dasar (Kriteria, Dokumen, Data Induk, Pengguna, tampilan, pengaturan server)..."
if [ "$SUDAH_ADA" = 1 ] && [ "$PAKSA" != 1 ]; then
  echo "  (dilewati: aplikasi dasar sudah terpasang. Kode tidak ditimpa. Pakai --paksa untuk menimpa.)"
else
  ARGS_DASAR="--migrate"
  [ "$LEWATI_SERVER" = 1 ] && ARGS_DASAR="$ARGS_DASAR --lewati-server"
  [ "$PAKSA" = 1 ] && ARGS_DASAR="$ARGS_DASAR --paksa"
  bash "$M/01-dasar.sh" $ARGS_DASAR || gagal "pemasangan aplikasi dasar gagal (lihat pesan di atas)."
fi
[ -f app/Http/Controllers/KriteriaController.php ] || gagal "aplikasi dasar tidak terpasang."

echo ""
echo "[6/9] Migrasi database (tabel yang belum ada ditambahkan; data tidak dihapus)..."
php artisan migrate --force || gagal "migrate gagal. Periksa koneksi database di .env."
ok "database mutakhir"

echo ""
echo "[7/9] LKPS LAM Infokom (31 tabel, Identitas, Dosen Homebase, lampiran berkas/link, impor Excel)..."
bash "$M/02-lkps.sh" --tanpa-dump $ARG_EXCEL || gagal "pemasangan LKPS gagal (lihat pesan di atas). Aplikasi dasar tetap utuh."

echo ""
echo "[8/9] Halaman Analitik lima aspek..."
bash "$M/03-analitik-lima.sh" || gagal "pemasangan Analitik lima aspek gagal (lihat pesan di atas)."

if [ "$DATA_INDUK_DB" = 1 ]; then
  echo ""
  echo "[opsional] Memindahkan Data Induk ke database..."
  bash "$M/04-data-induk-db.sh" --tanpa-dump || gagal "migrasi Data Induk ke database gagal. Aplikasi tetap memakai berkas JSON."
fi

# ---------- [9] Penyelesaian ----------
echo ""
echo "[9/9] Penyelesaian..."
if [ "$WINDOWS" != 1 ]; then
  # berkas baru harus terbaca server web (www-data / php-fpm)
  find app resources routes config database public -type f ! -perm -o=r -exec chmod a+r {} + 2>/dev/null || true
  find app resources routes config database -type d ! -perm -o=x -exec chmod a+rx {} + 2>/dev/null || true
fi
if [ ! -f .env ] || ! grep -q '^ADMIN_EMAILS=' .env; then
  printf '\n# Email admin tambahan (pisahkan koma). Akun id 1 selalu admin.\nADMIN_EMAILS=\n' >> .env
fi
if [ "$PRODUKSI" = 1 ]; then
  sed -i.bak 's/^APP_ENV=.*/APP_ENV=production/; s/^APP_DEBUG=.*/APP_DEBUG=false/' .env && rm -f .env.bak
  ok ".env: APP_ENV=production, APP_DEBUG=false"
fi
if [ "$SUDAH_ADA" != 1 ]; then
  # instalasi baru: berkas cadangan sementara (*.bak*) tidak berguna
  find app resources routes config -name '*.bak*' -type f -delete 2>/dev/null || true
fi
php artisan optimize:clear >/dev/null 2>&1 || true
php artisan storage:link >/dev/null 2>&1 || { [ -e public/storage ] && ok "public/storage sudah ada" || echo "  PERINGATAN: storage:link gagal. Windows: mklink /J public\\storage storage\\app\\public"; }
if [ "$PRODUKSI" = 1 ]; then
  php artisan config:cache && php artisan route:cache && php artisan view:cache && ok "cache produksi dibuat"
fi

echo ""
echo "============================================================"
echo " INSTALASI SELESAI"
echo "============================================================"
echo " Folder proyek : $(pwd)"
echo " Menjalankan   : php artisan serve        (lalu buka http://127.0.0.1:8000)"
echo "                 Server sungguhan: lihat README.md (Nginx/Apache)"
echo " Login awal    : admin@example.com / GantiSandiIni123   (SEGERA ganti lewat menu 'Akun Saya')"
echo " Menu          : Dashboard, Analitik, Panel Admin, Kriteria, Data Induk (+ LKPS), Kelola Pengguna"
echo " Cadangan      : storage/app/cadangan/ (bila ada), berkas *.bak* di app/ resources/ routes/"
echo " Panduan       : README.md"
