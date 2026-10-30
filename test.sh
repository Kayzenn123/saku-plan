#!/usr/bin/env bash
# test.sh — tes saku-plan.sh tanpa dependensi. Keluar 0 jika semua lolos.
set -uo pipefail
BIN="./saku-plan.sh"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf 'GAGAL %s\n  %s\n' "$1" "$2"; }

# jumlahkan kolom ALOKASI dari baris tabel saja (baris tabel diakhiri % atau "% < min")
sum_alloc() {
  grep -v '^profil:' | grep -E '[0-9]+%( < min)?$' | grep -oE 'Rp[0-9.]+' | tr -d 'Rp.' | awk '{s+=$1} END {print s+0}'
}

# 1. alokasi normal: jumlah semua pos == total
out="$("$BIN" -t 3000000 -p kos --no-color)"
s="$(printf '%s' "$out" | sum_alloc)"
[ "$s" = "3000000" ] && ok "1 jumlah alokasi == total (kos 3jt)" || no "1 jumlah alokasi" "dapat $s"

# 2. jatah harian = (makan+jajan)/days
daily="$(printf '%s' "$out" | grep -oE 'Rp[0-9.]+/hari' | tr -d 'Rp./hari')"
[ "$daily" = "37000" ] && ok "2 jatah harian 37000" || no "2 jatah harian" "dapat $daily"

# 3. format "3.000.000" dan "Rp" diterima
out2="$("$BIN" --total "Rp 2.500.000" --profile ortu --no-color)"
s2="$(printf '%s' "$out2" | sum_alloc)"
[ "$s2" = "2500000" ] && ok "3 parsing format Rp 2.500.000" || no "3 parsing format" "dapat $s2"

# 4. mode defisit: ada penanda + jumlah tetap == total
out3="$("$BIN" -t 800000 -p kos --no-color)"
s3="$(printf '%s' "$out3" | sum_alloc)"
echo "$out3" | grep -q "MODE DEFISIT" && [ "$s3" = "800000" ] \
  && ok "4 mode defisit (800rb kos)" || no "4 mode defisit" "sum=$s3"

# 5. floor minimum: makan tidak boleh di bawah 20000*days
makan="$(printf '%s' "$out2" | grep -E '^Makan' | grep -oE 'Rp[0-9.]+' | tr -d 'Rp.')"
[ "$makan" = "600000" ] && ok "5 floor makan 600rb ditegakkan" || no "5 floor makan" "dapat $makan"

# 6. --json valid dan field benar
j="$("$BIN" -t 1500000 -p ortu --json)"
printf '%s' "$j" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['total'] == 1500000 and d['profile'] == 'ortu', 'field salah'
assert sum(a['amount'] for a in d['allocations']) == 1500000, 'jumlah alloc != total'
assert d['deficit'] is False and isinstance(d['daily_allowance'], int)
print('json-ok')
" >/dev/null 2>&1 && ok "6 --json valid, jumlah pas" || no "6 --json" "tidak valid / jumlah salah"

# 7. profil tidak dikenal -> exit 2
"$BIN" -t 1000000 -p bogus >/dev/null 2>&1
[ $? -eq 2 ] && ok "7 profil bogus -> exit 2" || no "7 profil bogus" "exit=$?"

# 8. total negatif -> exit 2
"$BIN" -t -5 -p kos >/dev/null 2>&1
[ $? -eq 2 ] && ok "8 total negatif -> exit 2" || no "8 total negatif" "exit=$?"

# 9. NO_COLOR menghilangkan escape ANSI
c="$(NO_COLOR=1 "$BIN" -t 3000000 -p kos | grep -c $'\033' || true)"
[ "$c" = "0" ] && ok "9 NO_COLOR tanpa ANSI" || no "9 NO_COLOR" "$c baris ber-ANSI"

# 10. baca total dari stdin
s4="$(echo 2500000 | "$BIN" -p kos --no-color | sum_alloc)"
[ "$s4" = "2500000" ] && ok "10 total via stdin" || no "10 stdin" "dapat $s4"

# 11. --list-profiles memuat kedua profil, exit 0
lp="$("$BIN" --list-profiles)"; rc=$?
echo "$lp" | grep -q '^kos' && echo "$lp" | grep -q '^ortu' && [ "$rc" -eq 0 ] \
  && ok "11 --list-profiles" || no "11 --list-profiles" "rc=$rc"

# 12. end-to-end: target tabungan tidak tercapai -> ada saran
out4="$("$BIN" -t 1200000 -p kos --save 20 --no-color)"
echo "$out4" | grep -q "belum tercapai" && echo "$out4" | grep -q "Catatan:" \
  && ok "12 saran saat target tabungan gagal" || no "12 saran tabungan" "tidak ada saran"

printf '\n%d lolos, %d gagal\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
