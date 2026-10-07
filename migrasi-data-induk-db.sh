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
