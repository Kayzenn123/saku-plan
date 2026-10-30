#!/usr/bin/env bash
# saku-plan — perencana anggaran bulanan mahasiswa.
# Bagi total uang saku ke pos pengeluaran realistis (profil kos/ortu),
# lengkap dengan floor minimum, jatah harian, target tabungan, dan
# mode defisit berisi saran pemangkasan. Satu file, nol dependensi.
set -uo pipefail

VERSION="1.0.0"
PROG="saku-plan"

# ---------------------------------------------------------------- warna
USE_COLOR=1
color() { # $1=kode, $2..=teks
  local code="$1"; shift
  if [ "$USE_COLOR" -eq 1 ]; then printf '\033[%sm%s\033[0m' "$code" "$*";
  else printf '%s' "$*"; fi
}
green() { color 32 "$@"; }
yellow() { color 33 "$@"; }
red()   { color 31 "$@"; }
bold()  { color 1 "$@"; }

# ---------------------------------------------------------------- util
die()  { printf '%s: %s\n' "$PROG" "$2" >&2; exit "$1"; }

# 3000000 -> 3.000.000 (murni bash)
fmt_rp() {
  local n="$1" out=""
  [ -z "$n" ] && { printf '0'; return; }
  while [ "${#n}" -gt 3 ]; do out=".${n: -3}${out}"; n="${n:0:${#n}-3}"; done
  printf '%s%s' "$n" "$out"
}
rp() { printf 'Rp%s' "$(fmt_rp "$1")"; }

# normalisasi "Rp 3.000.000" / "3,000,000" -> 3000000 ; gagal -> ""
num() {
  local s="$1" d
  d="${s//[^0-9]/}"
  [ -n "$d" ] && printf '%s' "$d" || printf ''
}

usage() {
  cat <<EOF
$PROG $VERSION — perencana anggaran bulanan mahasiswa.

Pakai:
  $PROG --total 3000000 --profile kos
  $PROG --total 1500000 --profile ortu --days 26 --save 15
  echo 3000000 | $PROG --profile kos
  $PROG --total 3000000 --profile kos --json
  $PROG --list-profiles

Opsi:
  -t, --total N       total uang saku sebulan (Rp). Boleh format "3.000.000".
                      Kalau tidak diisi, dibaca dari stdin (satu baris).
  -p, --profile P     profil tempat tinggal: kos | ortu  (wajib)
  -d, --days N        hari aktif dalam sebulan (default 30, 1-31)
      --save PCT      target tabungan, persen dari total (default 10, 0-100)
      --json          keluarkan hasil sebagai JSON (untuk skrip)
      --list-profiles tampilkan profil dan bobot alokasinya
      --no-color      matikan warna (juga dihormati via env NO_COLOR)
      --version       tampilkan versi
  -h, --help          tampilkan bantuan ini

Kode keluar: 0 sukses, 1 galat runtime, 2 salah pakai argumen.

Contoh:
  $PROG -t 2500000 -p kos
EOF
}

# ---------------------------------------------------------------- profil
# Urutan kategori = urutan prioritas saat dana tidak cukup (mode defisit).
CATS_KOS=(kos makan transport kuliah pulsa tabungan darurat jajan)
CATS_ORTU=(makan transport kuliah pulsa tabungan darurat jajan)
# Bobot persen per profil (jumlah = 100)
W_KOS=(30 25 10 5 3 10 5 12)
W_ORTU=(22 14 6 4 12 6 36)

label() {
  case "$1" in
    kos) printf 'Kos / kontrakan';; makan) printf 'Makan';; transport) printf 'Transport';;
    kuliah) printf 'Kuliah & print';; pulsa) printf 'Pulsa & kuota';;
    tabungan) printf 'Tabungan';; darurat) printf 'Dana darurat';; jajan) printf 'Jajan & hiburan';;
  esac
}

list_profiles() {
  printf 'Profil yang tersedia:\n\n'
  printf 'kos  (tinggal di kos/kontrakan)\n'
  local i
  for i in "${!CATS_KOS[@]}"; do
    printf '  %-18s %s%%\n' "$(label "${CATS_KOS[$i]}")" "${W_KOS[$i]}"
  done
  printf '\nortu (tinggal dengan orang tua)\n'
  for i in "${!CATS_ORTU[@]}"; do
    printf '  %-18s %s%%\n' "$(label "${CATS_ORTU[$i]}")" "${W_ORTU[$i]}"
  done
}

# ---------------------------------------------------------------- argumen
TOTAL="" PROFILE="" DAYS=30 SAVE=10 JSON=0 LIST=0

while [ $# -gt 0 ]; do
  case "$1" in
    -t|--total)   [ $# -ge 2 ] || die 2 "opsi $1 butuh nilai"
                  case "$2" in -*) die 2 "--total harus bilangan bulat positif, dapat: '$2'";; esac
                  TOTAL="$(num "$2")"
                  [ -n "$TOTAL" ] || die 2 "--total harus berupa angka, dapat: '$2'"
                  shift 2;;
    -p|--profile) [ $# -ge 2 ] || die 2 "opsi $1 butuh nilai"
                  PROFILE="$2"; shift 2;;
    -d|--days)    [ $# -ge 2 ] || die 2 "opsi $1 butuh nilai"
                  case "$2" in -*) die 2 "--days harus 1-31, dapat: '$2'";; esac
                  DAYS="$(num "$2")"
                  [ -n "$DAYS" ] || die 2 "--days harus berupa angka, dapat: '$2'"
                  shift 2;;
    --save)       [ $# -ge 2 ] || die 2 "opsi $1 butuh nilai"
                  case "$2" in -*) die 2 "--save harus 0-100, dapat: '$2'";; esac
                  SAVE="$(num "$2")"
                  [ -n "$SAVE" ] || die 2 "--save harus berupa angka, dapat: '$2'"
                  shift 2;;
    --json) JSON=1; shift;;
    --list-profiles) LIST=1; shift;;
    --no-color) USE_COLOR=0; shift;;
    --version) printf '%s %s\n' "$PROG" "$VERSION"; exit 0;;
    -h|--help) usage; exit 0;;
    --) shift; break;;
    -*) die 2 "opsi tidak dikenal: '$1' (lihat --help)";;
    *)  die 2 "argumen tak terduga: '$1' (lihat --help)";;
  esac
done

[ -n "${NO_COLOR:-}" ] && USE_COLOR=0
[ -t 1 ] || USE_COLOR=0

[ "$LIST" -eq 1 ] && { list_profiles; exit 0; }

# total dari stdin kalau --total tidak diisi
if [ -z "$TOTAL" ]; then
  if [ -t 0 ]; then
    die 2 "--total wajib diisi (atau kirim lewat stdin)"
  fi
  IFS= read -r line || die 1 "gagal membaca stdin"
  case "$line" in -*) die 2 "stdin harus berisi angka total positif (Rp)";; esac
  TOTAL="$(num "$line")"
  [ -n "$TOTAL" ] || die 2 "stdin harus berisi angka total (Rp)"
fi

[ "$TOTAL" -gt 0 ] 2>/dev/null || die 2 "--total harus bilangan bulat positif"
case "$PROFILE" in
  kos|ortu) ;;
  "") die 2 "--profile wajib diisi: kos | ortu";;
  *)  die 2 "--profile tidak dikenal: '$PROFILE' (pilih: kos | ortu)";;
esac
{ [ "$DAYS" -ge 1 ] && [ "$DAYS" -le 31 ]; } 2>/dev/null || die 2 "--days harus 1-31"
{ [ "$SAVE" -ge 0 ] && [ "$SAVE" -le 100 ]; } 2>/dev/null || die 2 "--save harus 0-100"

# ---------------------------------------------------------------- data
if [ "$PROFILE" = kos ]; then
  CATS=("${CATS_KOS[@]}"); W=("${W_KOS[@]}")
else
  CATS=("${CATS_ORTU[@]}"); W=("${W_ORTU[@]}")
fi
N=${#CATS[@]}

# floor minimum realistis (Rp/bulan)
floor_of() {
  case "$1" in
    kos) printf '400000';;
    makan) printf '%d' $((20000 * DAYS));;
    transport) printf '%d' $((5000 * DAYS));;
    kuliah) printf '50000';; pulsa) printf '25000';;
    *) printf '0';;
  esac
}

declare -a FLOOR ALLOC
SUMFLOOR=0
for i in $(seq 0 $((N-1))); do
  FLOOR[$i]="$(floor_of "${CATS[$i]}")"
  SUMFLOOR=$((SUMFLOOR + FLOOR[$i]))
done

DEFICIT=0
declare -a NOTES=()

# ---------------------------------------------------------------- alokasi
if [ "$TOTAL" -lt "$SUMFLOOR" ]; then
  # MODE DEFISIT: isi sesuai urutan prioritas sampai uang habis.
  DEFICIT=1
  REM=$TOTAL
  for i in $(seq 0 $((N-1))); do
    if [ "$REM" -ge "${FLOOR[$i]}" ]; then ALLOC[$i]="${FLOOR[$i]}"; REM=$((REM - FLOOR[$i]))
    elif [ "$REM" -gt 0 ]; then ALLOC[$i]="$REM"; REM=0
    else ALLOC[$i]=0; fi
  done
  NOTES+=("Total $(rp "$TOTAL") di bawah kebutuhan minimum $(rp "$SUMFLOOR") — alokasi mengikuti urutan prioritas.")
  for i in $(seq 0 $((N-1))); do
    if [ "${ALLOC[$i]}" -lt "${FLOOR[$i]}" ]; then
      NOTES+=("$(label "${CATS[$i]}"): hanya $(rp "${ALLOC[$i]}") dari minimum $(rp "${FLOOR[$i]}") — pertimbangkan: masak sendiri, cari kos lebih murah / patungan, kurangi jajan.")
      break
    fi
  done
else
  # MODE NORMAL: bobot -> koreksi floor -> redistribusi overage proporsional.
  SUM=0
  for i in $(seq 0 $((N-1))); do
    ALLOC[$i]=$((TOTAL * W[$i] / 100)); SUM=$((SUM + ALLOC[$i]))
  done
  # rapikan pembulatan ke kategori terbesar (jajan/makan)
  DIFF=$((TOTAL - SUM))
  BIG=0; for i in $(seq 0 $((N-1))); do [ "${ALLOC[$i]}" -gt "${ALLOC[$BIG]}" ] && BIG=$i; done
  ALLOC[$BIG]=$((ALLOC[$BIG] + DIFF))

  OVER=0
  for i in $(seq 0 $((N-1))); do
    if [ "${ALLOC[$i]}" -lt "${FLOOR[$i]}" ]; then
      OVER=$((OVER + FLOOR[$i] - ALLOC[$i])); ALLOC[$i]="${FLOOR[$i]}"
    fi
  done
  if [ "$OVER" -gt 0 ]; then
    ABOVE=0
    for i in $(seq 0 $((N-1))); do
      [ "${ALLOC[$i]}" -gt "${FLOOR[$i]}" ] && ABOVE=$((ABOVE + ALLOC[$i] - FLOOR[$i]))
    done
    if [ "$ABOVE" -le 0 ]; then
      DEFICIT=1
      NOTES+=("Alokasi mentok di batas minimum semua pos.")
    else
      TAKEN=0
      for i in $(seq 0 $((N-1))); do
        if [ "${ALLOC[$i]}" -gt "${FLOOR[$i]}" ]; then
          T=$((OVER * (ALLOC[$i] - FLOOR[$i]) / ABOVE))
          ALLOC[$i]=$((ALLOC[$i] - T)); TAKEN=$((TAKEN + T))
        fi
      done
      # sisa pembulatan: kurangi dari kategori terbesar yang masih di atas floor
      R=$((OVER - TAKEN))
      while [ "$R" -gt 0 ]; do
        BIG=-1
        for i in $(seq 0 $((N-1))); do
          if [ "${ALLOC[$i]}" -gt "${FLOOR[$i]}" ] && { [ "$BIG" -eq -1 ] || [ "${ALLOC[$i]}" -gt "${ALLOC[$BIG]}" ]; }; then BIG=$i; fi
        done
        [ "$BIG" -eq -1 ] && break
        ALLOC[$BIG]=$((ALLOC[$BIG] - 1)); R=$((R - 1))
      done
    fi
  fi
  # pastikan jumlah pas
  SUM=0; for i in $(seq 0 $((N-1))); do SUM=$((SUM + ALLOC[$i])); done
  DIFF=$((TOTAL - SUM))
  if [ "$DIFF" -ne 0 ]; then
    BIG=0; for i in $(seq 0 $((N-1))); do [ "${ALLOC[$i]}" -gt "${ALLOC[$BIG]}" ] && BIG=$i; done
    ALLOC[$BIG]=$((ALLOC[$BIG] + DIFF))
  fi
fi

# ---------------------------------------------------------------- turunan
idx() { # index kategori berdasarkan nama
  local k="$1" i
  for i in $(seq 0 $((N-1))); do [ "${CATS[$i]}" = "$k" ] && { printf '%s' "$i"; return; }; done
  printf '-1'
}
get() { local i; i="$(idx "$1")"; [ "$i" -ge 0 ] && printf '%s' "${ALLOC[$i]}" || printf '0'; }

MAKAN="$(get makan)"; JAJAN="$(get jajan)"; TAB="$(get tabungan)"
DAILY=$(((MAKAN + JAJAN) / DAYS))
SAVEPCT=$((TAB * 100 / TOTAL))
if [ "$SAVEPCT" -ge "$SAVE" ]; then
  SAVENOTE="target tabungan ${SAVE}% tercapai"
else
  SAVENOTE="target tabungan ${SAVE}% belum tercapai — coba naikkan dengan memangkas jajan"
  NOTES+=("Untuk mencapai target tabungan ${SAVE}%, pangkas pos jajan & hiburan dulu.")
fi

# ---------------------------------------------------------------- output
if [ "$JSON" -eq 1 ]; then
  {
    printf '{\n  "tool": "%s", "version": "%s",\n' "$PROG" "$VERSION"
    printf '  "profile": "%s", "total": %s, "days": %s, "deficit": %s,\n' \
      "$PROFILE" "$TOTAL" "$DAYS" "$([ "$DEFICIT" -eq 1 ] && printf true || printf false)"
    printf '  "allocations": [\n'
    for i in $(seq 0 $((N-1))); do
      PCT=$((ALLOC[$i] * 100 / TOTAL))
      SEP=","; [ "$i" -eq $((N-1)) ] && SEP=""
      printf '    {"pos": "%s", "label": "%s", "amount": %s, "percent": %s, "floor": %s}%s\n' \
        "${CATS[$i]}" "$(label "${CATS[$i]}")" "${ALLOC[$i]}" "$PCT" "${FLOOR[$i]}" "$SEP"
    done
    printf '  ],\n'
    printf '  "daily_allowance": %s,\n' "$DAILY"
    printf '  "savings": {"amount": %s, "percent": %s, "target_percent": %s, "met": %s},\n' \
      "$TAB" "$SAVEPCT" "$SAVE" "$([ "$SAVEPCT" -ge "$SAVE" ] && printf true || printf false)"
    printf '  "notes": ['
    NI=0
    for note in "${NOTES[@]:-}"; do
      [ "$NI" -gt 0 ] && printf ', '
      printf '"%s"' "$(printf '%s' "$note" | sed 's/"/\\"/g')"
      NI=$((NI+1))
    done
    printf ']\n}\n'
  }
  exit 0
fi

# tabel manusia
TITLE="Saku-Plan $VERSION — anggaran bulanan"
SUB="profil: $PROFILE | total: $(rp "$TOTAL") | $DAYS hari aktif | target tabungan: ${SAVE}%"
printf '%s\n' "$(bold "$TITLE")"
printf '%s\n\n' "$SUB"
if [ "$DEFICIT" -eq 1 ]; then
  printf '%s\n\n' "$(red "!! MODE DEFISIT: uang tidak cukup untuk kebutuhan minimum.")"
fi
printf '%-18s %13s %6s\n' "POS" "ALOKASI" "%"
printf '%-18s %13s %6s\n' "------------------" "-------------" "------"
for i in $(seq 0 $((N-1))); do
  PCT=$((ALLOC[$i] * 100 / TOTAL))
  MARK=""
  [ "${ALLOC[$i]}" -lt "${FLOOR[$i]}" ] && MARK=" $(yellow "< min")"
  printf '%-18s %13s %5s%%%s\n' "$(label "${CATS[$i]}")" "$(rp "${ALLOC[$i]}")" "$PCT" "$MARK"
done
printf '\n'
printf 'Jatah harian (makan+jajan): %s/hari\n' "$(rp "$DAILY")"
if [ "$SAVEPCT" -ge "$SAVE" ]; then
  printf 'Tabungan: %s (%s%%) — %s\n' "$(rp "$TAB")" "$SAVEPCT" "$(green "$SAVENOTE")"
else
  printf 'Tabungan: %s (%s%%) — %s\n' "$(rp "$TAB")" "$SAVEPCT" "$(yellow "$SAVENOTE")"
fi
if [ "${#NOTES[@]}" -gt 0 ]; then
  printf '\nCatatan:\n'
  for note in "${NOTES[@]}"; do printf '  - %s\n' "$note"; done
fi
exit 0
