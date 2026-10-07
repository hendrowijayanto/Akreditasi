#!/usr/bin/env bash
# =====================================================================
# PEMBARUAN LKPS: LAMPIRAN BUKTI BERUPA LINK + IMPOR EXCEL PER TABEL
# (untuk situs yang SUDAH menjalankan tambah-lkps.sh)
#
# Perubahan:
#  1. "Tambah data" / "Ubah data" pada semua tabel LKPS: selain unggah berkas, tersedia
#     kolom "Lampiran Bukti (Link)". Boleh keduanya, salah satu, atau tidak ada.
#  2. Setiap tabel LKPS mendapat tombol "Impor Excel": unduh templat (.xlsx, atau .csv),
#     isi, lalu unggah. Data DITAMBAHKAN (baris lama tidak diubah); semua baris diperiksa
#     dulu, bila ada yang tidak valid tidak ada yang disimpan.
#
# JAMINAN KEAMANAN DATA:
#  - Hanya MENAMBAH satu kolom kosong (lampiran_link) pada tabel lkps_*; tidak ada kolom,
#    tabel, atau data yang dihapus atau diubah.
#  - Berkas yang diubah dicadangkan *.bak14; database dicadangkan (mysqldump) lebih dulu.
#  - Aman diulang. Berkas yang sudah Anda ubah dan tidak cocok TIDAK ditimpa (dilaporkan).
#
# Pemakaian (root proyek): bash perbarui-lkps-link-impor.sh [--tanpa-dump]
# Impor .xlsx membutuhkan PhpSpreadsheet (composer require phpoffice/phpspreadsheet);
# tanpa itu impor tetap bisa memakai file CSV.
# =====================================================================
set -e
if [ ! -f artisan ]; then echo "Error: jalankan di root proyek Laravel."; exit 1; fi
TANPA_DUMP=0
for a in "$@"; do
  case "$a" in
    --tanpa-dump) TANPA_DUMP=1;;
    -h|--help) sed -n '2,23p' "$0"; exit 0;;
    *) echo "Opsi tidak dikenal: $a"; exit 1;;
  esac
done
TS=$(date +%Y%m%d-%H%M%S)
BAK=bak14

echo "[1/4] Pemeriksaan awal..."
for f in app/Support/Lkps.php app/Http/Controllers/LkpsController.php routes/web.php resources/views/lkps/form.blade.php resources/views/lkps/tabel.blade.php; do
  [ -f "$f" ] || { echo "Error: $f tidak ditemukan. Jalankan tambah-lkps.sh lebih dulu."; exit 1; }
done
command -v php >/dev/null 2>&1 || { echo "Error: php dibutuhkan."; exit 1; }
php artisan migrate:status >/dev/null 2>&1 || { echo "  GAGAL: tidak dapat terhubung ke database. Periksa DB_* pada .env."; exit 1; }
echo "  OK"

echo "[2/4] Cadangan..."
envval() { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//'; }
if [ "$TANPA_DUMP" = 1 ]; then
  echo "  --  cadangan database dilewati (--tanpa-dump)"
else
  CONN=$(envval DB_CONNECTION)
  if { [ "$CONN" = mysql ] || [ "$CONN" = mariadb ]; } && command -v mysqldump >/dev/null 2>&1; then
    DUMP="storage/app/cadangan-sebelum-link-impor-$TS.sql"
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

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/spec.json" <<'EOFSPEC'
[
 {
  "aksi": "tulis",
  "file": "app/Support/LkpsImporFile.php",
  "isi": "<?php\n\nnamespace App\\Support;\n\n/**\n * Pembaca file impor untuk SATU tabel LKPS: CSV (selalu bisa) dan Excel .xlsx/.xls\n * (bila PhpSpreadsheet terpasang). Kelas ini tidak menyentuh database.\n */\nclass LkpsImporFile\n{\n    public const MAKS_BARIS = 5000;\n\n    public static function adaXlsx(): bool\n    {\n        return class_exists(\\PhpOffice\\PhpSpreadsheet\\IOFactory::class);\n    }\n\n    /** @return array<int,array<int,mixed>> baris mentah (indeks dari 0); baris kosong = [] */\n    public static function baca(string $path, string $ext): array\n    {\n        return in_array(strtolower($ext), ['xlsx', 'xls'], true) ? self::bacaExcel($path) : self::bacaCsv($path);\n    }\n\n    private static function bacaExcel(string $path): array\n    {\n        if (! self::adaXlsx()) {\n            throw new \\RuntimeException('Impor .xlsx/.xls membutuhkan pustaka PhpSpreadsheet (composer require phpoffice/phpspreadsheet). Simpan file sebagai CSV, atau pasang pustakanya.');\n        }\n        $reader = \\PhpOffice\\PhpSpreadsheet\\IOFactory::createReaderForFile($path);\n        $reader->setReadDataOnly(true);\n        $book = $reader->load($path);\n        $ws = $book->getSheetByName('Data') ?? $book->getSheet(0);\n\n        return $ws->toArray(null, true, false, false);\n    }\n\n    public static function bacaCsv(string $path): array\n    {\n        $isi = (string) file_get_contents($path);\n        if (str_starts_with($isi, \"\\xEF\\xBB\\xBF\")) {\n            $isi = substr($isi, 3);\n        }\n        if (! mb_check_encoding($isi, 'UTF-8')) {\n            $isi = mb_convert_encoding($isi, 'UTF-8', 'Windows-1252');\n        }\n\n        // Pemisah dideteksi dari baris pertama: titik koma (Excel Indonesia), koma, atau tab.\n        $pertama = strtok($isi, \"\\n\") ?: '';\n        $sep = ';';\n        $maks = -1;\n        foreach ([';', ',', \"\\t\"] as $c) {\n            $n = substr_count($pertama, $c);\n            if ($n > $maks) {\n                $maks = $n;\n                $sep = $c;\n            }\n        }\n\n        $h = fopen('php://temp', 'r+');\n        fwrite($h, $isi);\n        rewind($h);\n        $hasil = [];\n        while (($r = fgetcsv($h, 0, $sep, '\"', '')) !== false) {\n            $hasil[] = $r === [null] ? [] : $r;\n            if (count($hasil) > self::MAKS_BARIS + 2) {\n                break;\n            }\n        }\n        fclose($h);\n\n        return $hasil;\n    }\n\n    /** Samakan penulisan judul kolom: huruf kecil, tanpa tanda baca pemisah, spasi tunggal. */\n    public static function norm(string $s): string\n    {\n        $s = str_replace([\"\\xC2\\xA0\", '–', '—', '-', '|', '_', '*', '(', ')'], ' ', $s);\n\n        return mb_strtolower(preg_replace('/\\s+/u', ' ', trim($s)), 'UTF-8');\n    }\n\n    /** @return array<int,string> indeks kolom file => nama kolom tabel */\n    public static function petaKolom(array $header, array $kolom): array\n    {\n        $cari = [];\n        foreach ($kolom as $n => $k) {\n            $cari[self::norm($k['label'])] = $n;\n        }\n        foreach ($kolom as $n => $k) {\n            $cari[self::norm($n)] ??= $n;\n        }\n        $peta = [];\n        foreach ($header as $i => $h) {\n            $kunci = self::norm((string) $h);\n            if ($kunci !== '' && isset($cari[$kunci]) && ! in_array($cari[$kunci], $peta, true)) {\n                $peta[$i] = $cari[$kunci];\n            }\n        }\n\n        return $peta;\n    }\n\n    private static function kosong(array $r): bool\n    {\n        foreach ($r as $v) {\n            if ($v !== null && trim((string) $v) !== '') {\n                return false;\n            }\n        }\n\n        return true;\n    }\n\n    /**\n     * @param array $baris  hasil baca()\n     * @param array $kolom  kolom yang boleh diimpor: nama => [label, type, rules, options]\n     * @return array{baris:array<int,array>,abaikan:array<int,string>,kolom:array<int,string>}\n     *         baris = [nomor baris di file => [kolom => nilai]]\n     * @throws \\InvalidArgumentException\n     */\n    public static function olah(array $baris, array $kolom): array\n    {\n        $idx = null;\n        foreach ($baris as $i => $r) {\n            if (! self::kosong($r)) {\n                $idx = $i;\n                break;\n            }\n        }\n        if ($idx === null) {\n            throw new \\InvalidArgumentException('File tidak berisi data.');\n        }\n\n        $peta = self::petaKolom($baris[$idx], $kolom);\n        if (! $peta) {\n            throw new \\InvalidArgumentException('Judul kolom pada baris pertama tidak dikenali. Unduh templat, lalu isi sesuai kolom di dalamnya.');\n        }\n        $dikenal = array_values($peta);\n\n        $kurang = [];\n        foreach ($kolom as $n => $k) {\n            if (in_array('required', explode('|', $k['rules']), true) && ! in_array($n, $dikenal, true)) {\n                $kurang[] = $k['label'];\n            }\n        }\n        if ($kurang) {\n            throw new \\InvalidArgumentException('Kolom wajib tidak ada di file: ' . implode(', ', $kurang) . '.');\n        }\n\n        $abaikan = [];\n        foreach ($baris[$idx] as $i => $h) {\n            if (! isset($peta[$i]) && trim((string) $h) !== '') {\n                $abaikan[] = trim((string) $h);\n            }\n        }\n\n        $hasil = [];\n        for ($i = $idx + 1, $n = count($baris); $i < $n; $i++) {\n            if (self::kosong($baris[$i])) {\n                continue;\n            }\n            $d = array_fill_keys($dikenal, null);\n            foreach ($peta as $c => $nama) {\n                $d[$nama] = self::nilai($kolom[$nama], $baris[$i][$c] ?? null);\n            }\n            $hasil[$i + 1] = $d;\n        }\n\n        return ['baris' => $hasil, 'abaikan' => $abaikan, 'kolom' => $dikenal];\n    }\n\n    /** Ubah sel mentah menjadi nilai yang sesuai jenis kolom. Nilai yang tidak bisa diubah dibiarkan agar ditolak validasi. */\n    public static function nilai(array $k, mixed $v): mixed\n    {\n        $tipe = $k['type'];\n        if ($tipe === 'check') {\n            return in_array(mb_strtolower(trim((string) $v), 'UTF-8'), ['1', 'ya', 'y', 'yes', 'true', '√', 'v', 'x', 'ok', 'benar'], true);\n        }\n        if ($v === null || (is_string($v) && trim($v) === '')) {\n            return null;\n        }\n        if (is_bool($v)) {\n            $v = $v ? '1' : '0';\n        }\n\n        switch ($tipe) {\n            case 'number':\n                $a = self::angka($v);\n                return (is_float($a) && floor($a) == $a) ? (int) $a : $a;\n            case 'decimal':\n                return self::angka($v);\n            case 'date':\n                return self::tanggal($v);\n            case 'select':\n                $s = trim((string) $v);\n                foreach ($k['options'] as $opsi) {\n                    if (mb_strtolower((string) $opsi, 'UTF-8') === mb_strtolower($s, 'UTF-8')) {\n                        return (string) $opsi;\n                    }\n                }\n                return $s;\n            default:\n                if (is_float($v) && floor($v) == $v && abs($v) < 1e15) {\n                    return sprintf('%.0f', $v);   // NIDN/NUPTK yang terbaca sebagai angka\n                }\n                return trim((string) $v);\n        }\n    }\n\n    private static function angka(mixed $v): mixed\n    {\n        if (is_int($v) || is_float($v)) {\n            return $v;\n        }\n        $s = str_replace([' ', \"\\xC2\\xA0\"], '', trim((string) $v));\n        if (preg_match('/^-?\\d{1,3}(\\.\\d{3})+(,\\d+)?$/', $s)) {            // 1.234,56\n            $s = str_replace(['.', ','], ['', '.'], $s);\n        } elseif (preg_match('/^-?\\d+,\\d+$/', $s)) {                        // 12,5\n            $s = str_replace(',', '.', $s);\n        } elseif (preg_match('/^-?\\d{1,3}(,\\d{3})+(\\.\\d+)?$/', $s)) {       // 1,234.56\n            $s = str_replace(',', '', $s);\n        }\n\n        return is_numeric($s) ? $s + 0 : $v;\n    }\n\n    private static function tanggal(mixed $v): mixed\n    {\n        if (is_int($v) || is_float($v) || (is_string($v) && preg_match('/^\\d{5}(\\.\\d+)?$/', trim($v)))) {\n            $hari = (int) floor((float) $v);\n            if ($hari > 0 && $hari < 80000) {   // nomor seri tanggal Excel\n                return (new \\DateTimeImmutable('1899-12-30'))->modify('+' . $hari . ' days')->format('Y-m-d');\n            }\n        }\n        $s = trim((string) $v);\n        foreach (['Y-m-d', 'Y-m-d H:i:s', 'd/m/Y', 'd-m-Y', 'd.m.Y', 'j/n/Y', 'j-n-Y'] as $f) {\n            $d = \\DateTimeImmutable::createFromFormat('!' . $f, $s);\n            if ($d && $d->format($f) === $s) {\n                return $d->format('Y-m-d');\n            }\n        }\n\n        return $s;\n    }\n\n    // ------------------------------------------------------------------ templat\n\n    private static function jenis(array $k): string\n    {\n        return match ($k['type']) {\n            'number'   => 'Angka bulat',\n            'decimal'  => 'Angka (boleh desimal)',\n            'date'     => 'Tanggal (YYYY-MM-DD atau DD/MM/YYYY)',\n            'check'    => 'Ya atau kosong',\n            'select'   => 'Pilihan: ' . implode(', ', $k['options']),\n            'url'      => 'Link (diawali http:// atau https://)',\n            'textarea' => 'Teks panjang',\n            default    => 'Teks',\n        };\n    }\n\n    public static function templatCsv(array $kolom): string\n    {\n        $h = fopen('php://temp', 'r+');\n        fputcsv($h, array_column($kolom, 'label'), ';', '\"', '');\n        rewind($h);\n\n        return \"\\xEF\\xBB\\xBF\" . stream_get_contents($h);\n    }\n\n    /** Berkas .xlsx: lembar \"Data\" (judul kolom) dan lembar \"Petunjuk\". Hanya dipanggil bila adaXlsx(). */\n    public static function templatXlsx(string $judul, array $kolom): string\n    {\n        $book = new \\PhpOffice\\PhpSpreadsheet\\Spreadsheet();\n        $ws = $book->getActiveSheet();\n        $ws->setTitle('Data');\n        $i = 0;\n        foreach ($kolom as $k) {\n            $i++;\n            $huruf = \\PhpOffice\\PhpSpreadsheet\\Cell\\Coordinate::stringFromColumnIndex($i);\n            $ws->setCellValue($huruf . '1', $k['label']);\n            $ws->getColumnDimension($huruf)->setAutoSize(true);\n        }\n        if ($i > 0) {\n            $akhir = \\PhpOffice\\PhpSpreadsheet\\Cell\\Coordinate::stringFromColumnIndex($i);\n            $ws->getStyle('A1:' . $akhir . '1')->getFont()->setBold(true);\n        }\n        $ws->freezePane('A2');\n\n        $p = $book->createSheet();\n        $p->setTitle('Petunjuk');\n        $p->setCellValue('A1', 'Petunjuk impor: ' . $judul);\n        $p->getStyle('A1')->getFont()->setBold(true);\n        $p->setCellValue('A2', 'Isi data mulai baris 2 pada lembar \"Data\". Jangan mengubah judul kolom pada baris 1. Data baru DITAMBAHKAN; baris yang sudah ada tidak diubah.');\n        $p->setCellValue('A4', 'Kolom');\n        $p->setCellValue('B4', 'Jenis isian');\n        $p->setCellValue('C4', 'Wajib');\n        $p->getStyle('A4:C4')->getFont()->setBold(true);\n        $r = 5;\n        foreach ($kolom as $k) {\n            $p->setCellValue('A' . $r, $k['label']);\n            $p->setCellValue('B' . $r, self::jenis($k));\n            $p->setCellValue('C' . $r, in_array('required', explode('|', $k['rules']), true) ? 'Ya' : '');\n            $r++;\n        }\n        foreach (['A', 'B', 'C'] as $c) {\n            $p->getColumnDimension($c)->setAutoSize(true);\n        }\n        $book->setActiveSheetIndex(0);\n\n        $tmp = tempnam(sys_get_temp_dir(), 'lkps');\n        try {\n            \\PhpOffice\\PhpSpreadsheet\\IOFactory::createWriter($book, 'Xlsx')->save($tmp);\n\n            return (string) file_get_contents($tmp);\n        } finally {\n            @unlink($tmp);\n        }\n    }\n}\n"
 },
 {
  "aksi": "tulis",
  "file": "app/Http/Controllers/LkpsImporController.php",
  "isi": "<?php\n\nnamespace App\\Http\\Controllers;\n\nuse App\\Support\\Lkps;\nuse App\\Support\\LkpsImporFile;\nuse Illuminate\\Http\\Request;\nuse Illuminate\\Support\\Facades\\DB;\nuse Illuminate\\Support\\Facades\\Validator;\n\n/**\n * Impor data SATU tabel LKPS dari Excel/CSV. Hanya MENAMBAH baris; bila ada satu baris\n * yang tidak valid, tidak ada baris yang disimpan (semua atau tidak sama sekali).\n */\nclass LkpsImporController extends Controller\n{\n    /** Kolom yang bisa diisi lewat file: bukan lampiran berkas dan bukan kolom total otomatis. */\n    private function kolomImpor(string $tabel): array\n    {\n        $total = array_keys(Lkps::definisi($tabel)['total'] ?? []);\n\n        return array_filter(\n            Lkps::kolom($tabel),\n            fn ($k, $n) => $k['type'] !== 'file' && ! in_array($n, $total, true),\n            ARRAY_FILTER_USE_BOTH\n        );\n    }\n\n    public function form(string $tabel)\n    {\n        return view('lkps.impor', [\n            'tabel'    => $tabel,\n            'def'      => Lkps::definisi($tabel),\n            'kelompok' => Lkps::namaKelompok($tabel),\n            'kolom'    => $this->kolomImpor($tabel),\n            'xlsx'     => LkpsImporFile::adaXlsx(),\n            'maks'     => LkpsImporFile::MAKS_BARIS,\n        ]);\n    }\n\n    public function templat(Request $request, string $tabel)\n    {\n        $def = Lkps::definisi($tabel);\n        $kolom = $this->kolomImpor($tabel);\n        $dasar = 'templat_lkps_' . $tabel;\n\n        if ($request->query('format') !== 'csv' && LkpsImporFile::adaXlsx()) {\n            try {\n                return response(LkpsImporFile::templatXlsx($def['judul'], $kolom), 200, [\n                    'Content-Type'        => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',\n                    'Content-Disposition' => 'attachment; filename=\"' . $dasar . '.xlsx\"',\n                ]);\n            } catch (\\Throwable $e) {\n                // gagal membuat .xlsx: lanjut ke CSV\n            }\n        }\n\n        return response(LkpsImporFile::templatCsv($kolom), 200, [\n            'Content-Type'        => 'text/csv; charset=UTF-8',\n            'Content-Disposition' => 'attachment; filename=\"' . $dasar . '.csv\"',\n        ]);\n    }\n\n    public function proses(Request $request, string $tabel)\n    {\n        $def = Lkps::definisi($tabel);\n        $request->validate(['berkas' => ['required', 'file', 'max:' . Lkps::MAKS_LAMPIRAN_KB]], [], ['berkas' => 'File impor']);\n\n        $file = $request->file('berkas');\n        $ext = strtolower($file->getClientOriginalExtension());\n        if (! in_array($ext, ['xlsx', 'xls', 'csv', 'txt'], true)) {\n            return back()->withErrors(['berkas' => 'Format file harus .xlsx, .xls, atau .csv.']);\n        }\n\n        $kolom = $this->kolomImpor($tabel);\n        try {\n            $baris = LkpsImporFile::baca($file->getRealPath(), $ext);\n            if (count($baris) > LkpsImporFile::MAKS_BARIS + 1) {\n                throw new \\InvalidArgumentException('Terlalu banyak baris (maksimal ' . LkpsImporFile::MAKS_BARIS . ' baris data per impor).');\n            }\n            $hasil = LkpsImporFile::olah($baris, $kolom);\n        } catch (\\Throwable $e) {\n            return back()->withErrors(['berkas' => $e->getMessage()]);\n        }\n        if (! $hasil['baris']) {\n            return back()->withErrors(['berkas' => 'Tidak ada baris data di bawah judul kolom.']);\n        }\n\n        // Periksa SEMUA baris dengan aturan yang sama seperti formulir \"Tambah data\".\n        $aturan = array_intersect_key(Lkps::rules($tabel), array_flip($hasil['kolom']));\n        $nama = Lkps::label($tabel);\n        $galat = [];\n        foreach ($hasil['baris'] as $no => $data) {\n            $v = Validator::make($data, $aturan, [], $nama);\n            if ($v->fails()) {\n                $galat[] = \"Baris {$no}: \" . implode('; ', $v->errors()->all());\n                if (count($galat) >= 30) {\n                    $galat[] = 'Pemeriksaan dihentikan setelah 30 baris bermasalah.';\n                    break;\n                }\n            }\n        }\n        if ($galat) {\n            return back()\n                ->withErrors(['berkas' => 'Tidak ada data yang disimpan karena ada baris yang tidak valid. Perbaiki file lalu unggah ulang.'])\n                ->with('impor_galat', $galat);\n        }\n\n        $userId = $request->user()?->id;\n        $now = now();\n        $siap = [];\n        foreach ($hasil['baris'] as $data) {\n            foreach ($def['total'] ?? [] as $target => $sumber) {\n                $data[$target] = array_sum(array_map(fn ($c) => (float) ($data[$c] ?? 0), $sumber));\n            }\n            $siap[] = $data + ['created_by' => $userId, 'created_at' => $now, 'updated_at' => $now];\n        }\n        DB::transaction(function () use ($tabel, $siap) {\n            foreach (array_chunk($siap, 200) as $bagian) {\n                DB::table(Lkps::namaTabel($tabel))->insert($bagian);\n            }\n        });\n\n        $pesan = count($siap) . ' baris berhasil diimpor.'\n            . ($hasil['abaikan'] ? ' Kolom yang tidak dikenali dan diabaikan: ' . implode(', ', $hasil['abaikan']) . '.' : '');\n        $tujuan = ! empty($def['tersembunyi'])\n            ? redirect()->to(route('lkps.isian.index') . '#dosen-homebase')\n            : redirect()->route('lkps.tabel.index', $tabel);\n\n        return $tujuan->with('ok', $pesan);\n    }\n}\n"
 },
 {
  "aksi": "tulis",
  "file": "resources/views/lkps/impor.blade.php",
  "isi": "@extends('layout')\n@section('title', 'Impor Excel - ' . $def['judul'])\n\n@section('content')\n@include('lkps._gaya')\n<p class=\"lk-crumb\">\n    <a href=\"{{ route('lkps.daftar') }}\" class=\"link-secondary\">LKPS</a> / {{ $kelompok }} /\n    <a href=\"{{ route('lkps.tabel.index', $tabel) }}\" class=\"link-secondary\">{{ $def['judul'] }}</a>\n</p>\n<h1 class=\"mb-1\">Impor data dari Excel</h1>\n<p class=\"text-secondary mb-4\" style=\"max-width: 75ch\">\n    Data pada file <strong>ditambahkan</strong> ke tabel ini; baris yang sudah ada tidak diubah atau dihapus.\n    Semua baris diperiksa lebih dulu: bila ada satu baris yang tidak valid, tidak ada data yang disimpan.\n</p>\n\n<div class=\"row g-3\">\n    <div class=\"col-12 col-lg-5\">\n        <section class=\"lk-panel h-100\">\n            <h2 class=\"mb-2\">1. Unduh templat</h2>\n            <p class=\"small text-secondary\">Templat berisi judul kolom tabel ini. Isi mulai baris ke-2 dan jangan mengubah judul kolom.</p>\n            <div class=\"d-flex flex-wrap gap-2 mb-4\">\n                @if ($xlsx)\n                    <a href=\"{{ route('lkps.tabel.templat', $tabel) }}\" class=\"btn btn-sm btn-outline-primary\">Unduh templat Excel (.xlsx)</a>\n                @endif\n                <a href=\"{{ route('lkps.tabel.templat', [$tabel, 'format' => 'csv']) }}\" class=\"btn btn-sm btn-outline-secondary\">Unduh templat CSV</a>\n            </div>\n            @unless ($xlsx)\n                <div class=\"alert alert-warning small\">\n                    Pustaka PhpSpreadsheet belum terpasang, jadi hanya file <strong>CSV</strong> yang bisa diimpor\n                    (di Excel: Simpan Sebagai &rarr; CSV). Untuk impor .xlsx jalankan\n                    <code>composer require phpoffice/phpspreadsheet</code>.\n                </div>\n            @endunless\n\n            <h2 class=\"mb-2\">2. Unggah file</h2>\n            <form method=\"POST\" action=\"{{ route('lkps.tabel.impor.proses', $tabel) }}\" enctype=\"multipart/form-data\">\n                @csrf\n                <input type=\"file\" name=\"berkas\" required\n                       accept=\"{{ $xlsx ? '.xlsx,.xls,.csv,.txt' : '.csv,.txt' }}\"\n                       class=\"form-control @error('berkas') is-invalid @enderror\">\n                <div class=\"form-text\">Maksimal {{ $maks }} baris data per impor. Lampiran Bukti berupa berkas tidak bisa diimpor; gunakan kolom link atau unggah dari menu Ubah data.</div>\n                <div class=\"d-flex gap-2 mt-3\">\n                    <button class=\"btn btn-primary\">Impor data</button>\n                    <a href=\"{{ route('lkps.tabel.index', $tabel) }}\" class=\"btn btn-outline-secondary\">Batal</a>\n                </div>\n            </form>\n\n            @if (session('impor_galat'))\n                <div class=\"alert alert-danger small mt-3 mb-0\">\n                    <strong>Baris yang perlu diperbaiki:</strong>\n                    <ul class=\"mb-0 mt-1\">\n                        @foreach (session('impor_galat') as $g)\n                            <li>{{ $g }}</li>\n                        @endforeach\n                    </ul>\n                </div>\n            @endif\n        </section>\n    </div>\n\n    <div class=\"col-12 col-lg-7\">\n        <section class=\"lk-panel h-100\">\n            <h2 class=\"mb-2\">Kolom yang dibaca</h2>\n            <div class=\"table-responsive\">\n                <table class=\"table table-sm align-middle mb-0\">\n                    <thead><tr><th>Judul kolom</th><th>Jenis isian</th><th>Wajib</th></tr></thead>\n                    <tbody>\n                        @foreach ($kolom as $n => $k)\n                            <tr>\n                                <td>{{ $k['label'] }}</td>\n                                <td class=\"small text-secondary\">\n                                    @switch($k['type'])\n                                        @case('number') Angka bulat @break\n                                        @case('decimal') Angka (boleh desimal) @break\n                                        @case('date') Tanggal (YYYY-MM-DD atau DD/MM/YYYY) @break\n                                        @case('check') Ya atau kosong @break\n                                        @case('select') Pilihan: {{ implode(', ', $k['options']) }} @break\n                                        @case('url') Link (diawali http:// atau https://) @break\n                                        @case('textarea') Teks panjang @break\n                                        @default Teks\n                                    @endswitch\n                                </td>\n                                <td>{{ in_array('required', explode('|', $k['rules']), true) ? 'Ya' : '' }}</td>\n                            </tr>\n                        @endforeach\n                    </tbody>\n                </table>\n            </div>\n        </section>\n    </div>\n</div>\n@endsection\n"
 },
 {
  "aksi": "ganti",
  "file": "app/Support/Lkps.php",
  "tanda": "lampiran_link",
  "lama": "            'type'    => 'file',\n            'rules'   => 'nullable',\n            'options' => [],\n        ];\n\n        return $hasil;",
  "baru": "            'type'    => 'file',\n            'rules'   => 'nullable',\n            'options' => [],\n        ];\n\n        // Lampiran Bukti berupa link (opsional; boleh bersama berkas atau sebagai pengganti berkas).\n        $hasil['lampiran_link'] ??= [\n            'label'   => 'Lampiran Bukti (Link)',\n            'jalur'   => ['Lampiran Bukti (Link)'],\n            'type'    => 'url',\n            'rules'   => 'nullable|url|max:500',\n            'options' => [],\n        ];\n\n        return $hasil;"
 },
 {
  "aksi": "ganti",
  "file": "app/Support/LkpsData.php",
  "tanda": "lampiran_link",
  "lama": "                    $r[Lkps::LAMPIRAN] = filled($r[Lkps::LAMPIRAN] ?? null)\n                        ? Lkps::urlLampiran($slug, $r['id'])\n                        : null;",
  "baru": "                    $r[Lkps::LAMPIRAN] = filled($r[Lkps::LAMPIRAN] ?? null)\n                        ? Lkps::urlLampiran($slug, $r['id'])\n                        : (filled($r['lampiran_link'] ?? null) ? $r['lampiran_link'] : null);"
 },
 {
  "aksi": "ganti",
  "file": "resources/views/lkps/form.blade.php",
  "tanda": "'url' => 'url'",
  "lama": "['number' => 'number', 'decimal' => 'number', 'date' => 'date'][$k['type']] ?? 'text'",
  "baru": "['number' => 'number', 'decimal' => 'number', 'date' => 'date', 'url' => 'url'][$k['type']] ?? 'text'"
 },
 {
  "aksi": "ganti",
  "file": "resources/views/lkps/form.blade.php",
  "tanda": "Opsional: tempel link bukti",
  "lama": "                       class=\"form-control @error($n) is-invalid @enderror\">\n            @endif\n\n            @error($n)",
  "baru": "                       class=\"form-control @error($n) is-invalid @enderror\">\n                @if ($n === 'lampiran_link')\n                    <div class=\"form-text\">\n                        Opsional: tempel link bukti (mis. Google Drive atau situs resmi), diawali http:// atau https://.\n                        Boleh diisi bersama berkas lampiran atau sebagai pengganti berkas.\n                    </div>\n                @endif\n            @endif\n\n            @error($n)"
 },
 {
  "aksi": "ganti",
  "file": "resources/views/lkps/tabel.blade.php",
  "tanda": "lkps.tabel.impor",
  "lama": "            <a href=\"{{ route('lkps.tabel.create', $tabel) }}\" class=\"btn btn-sm btn-primary\">\n                Tambah data\n            </a>",
  "baru": "            <a href=\"{{ route('lkps.tabel.create', $tabel) }}\" class=\"btn btn-sm btn-primary\">\n                Tambah data\n            </a>\n            <a href=\"{{ route('lkps.tabel.impor', $tabel) }}\" class=\"btn btn-sm btn-outline-primary\">\n                Impor Excel\n            </a>"
 },
 {
  "aksi": "ganti",
  "file": "routes/web.php",
  "tanda": "LkpsImporController",
  "lama": "            Route::delete('/{id}', [\\App\\Http\\Controllers\\LkpsController::class, 'destroy'])->whereNumber('id')->name('destroy');",
  "baru": "            Route::delete('/{id}', [\\App\\Http\\Controllers\\LkpsController::class, 'destroy'])->whereNumber('id')->name('destroy');\n            Route::get('/impor', [\\App\\Http\\Controllers\\LkpsImporController::class, 'form'])->name('impor');\n            Route::get('/templat', [\\App\\Http\\Controllers\\LkpsImporController::class, 'templat'])->name('templat');\n            Route::post('/impor', [\\App\\Http\\Controllers\\LkpsImporController::class, 'proses'])->name('impor.proses');"
 },
 {
  "aksi": "ganti",
  "file": "resources/views/lkps/isian.blade.php",
  "tanda": "Buka link",
  "lama": "                                @if (filled($d->lampiran_bukti ?? null))\n                                    <a href=\"{{ \\App\\Support\\Lkps::urlLampiran($slugDosen, (int) $d->id) }}\" target=\"_blank\" rel=\"noopener\">Lihat</a>\n                                @else\n                                    –\n                                @endif",
  "baru": "                                @if (filled($d->lampiran_bukti ?? null))\n                                    <a href=\"{{ \\App\\Support\\Lkps::urlLampiran($slugDosen, (int) $d->id) }}\" target=\"_blank\" rel=\"noopener\">Lihat</a>\n                                @endif\n                                @if (filled($d->lampiran_link ?? null) && preg_match('#^https?://#i', $d->lampiran_link))\n                                    <a href=\"{{ $d->lampiran_link }}\" target=\"_blank\" rel=\"noopener\">Buka link</a>\n                                @endif\n                                @if (! filled($d->lampiran_bukti ?? null) && ! filled($d->lampiran_link ?? null))\n                                    –\n                                @endif"
 }
]
EOFSPEC
cat > "$TMP/terapkan.php" <<'EOFPHP'
<?php
// terapkan.php <spec.json> <akhiran-cadangan>
$spec = json_decode(file_get_contents($argv[1]), true);
$bak = $argv[2];
$gagal = 0;
foreach ($spec as $e) {
    $f = $e['file'];
    if ($e['aksi'] === 'tulis') {
        if (is_file($f) && file_get_contents($f) === $e['isi']) { echo "  (sudah terbaru) $f\n"; continue; }
        if (is_file($f) && ! is_file("$f.$bak")) { copy($f, "$f.$bak"); }
        if (! is_dir(dirname($f))) { mkdir(dirname($f), 0775, true); }
        file_put_contents($f, $e['isi']);
        echo "  OK  $f\n";
        continue;
    }
    if (! is_file($f)) { echo "  GAGAL: $f tidak ditemukan\n"; $gagal++; continue; }
    $s = file_get_contents($f);
    if (str_contains($s, $e['tanda'])) { echo "  (sudah diperbarui) $f\n"; continue; }
    if (substr_count($s, $e['lama']) !== 1) { echo "  GAGAL: bagian yang akan diubah pada $f tidak ditemukan persis satu kali (berkas sudah Anda ubah?)\n"; $gagal++; continue; }
    if (! is_file("$f.$bak")) { copy($f, "$f.$bak"); }
    file_put_contents($f, str_replace($e['lama'], $e['baru'], $s));
    echo "  OK  $f\n";
}
exit($gagal ? 1 : 0);
EOFPHP

echo "[3/4] Menerapkan perubahan..."
if ! php "$TMP/terapkan.php" "$TMP/spec.json" "$BAK"; then
  echo "  Sebagian perubahan tidak dapat diterapkan (lihat pesan GAGAL di atas)."
  echo "  Berkas yang sudah berubah dicadangkan *.$BAK. Hubungi pengembang atau terapkan manual."
  exit 1
fi
for f in app/Support/Lkps.php app/Support/LkpsData.php app/Support/LkpsImporFile.php app/Http/Controllers/LkpsImporController.php routes/web.php; do
  if [ -f "$f" ] && ! php -l "$f" >/dev/null 2>&1; then
    echo "  GAGAL: sintaks $f salah. Mengembalikan semua berkas dari cadangan *.$BAK."
    for g in $(find app routes resources -name "*.$BAK" 2>/dev/null); do cp "$g" "${g%.$BAK}"; done
    exit 1
  fi
done

echo "[4/4] Menambah kolom link, membersihkan cache..."
php artisan lkps:sinkron
php artisan view:clear >/dev/null 2>&1 || true
php artisan route:clear >/dev/null 2>&1 || true
php artisan config:clear >/dev/null 2>&1 || true
echo
echo "Selesai. Buka tabel LKPS mana pun: Tambah data (ada kolom Lampiran Bukti (Link)) dan tombol Impor Excel."
echo "Jika memakai cache: php artisan route:cache && php artisan view:cache"
if ! php -r 'require "vendor/autoload.php"; exit(class_exists("PhpOffice\\PhpSpreadsheet\\IOFactory")?0:1);' 2>/dev/null; then
  echo "Catatan: PhpSpreadsheet belum terpasang; impor memakai CSV. Untuk .xlsx: composer require phpoffice/phpspreadsheet"
fi
echo "Mengembalikan: salin kembali berkas *.$BAK (kolom lampiran_link yang kosong boleh dibiarkan)."
