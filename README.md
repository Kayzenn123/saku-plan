# saku-plan

> Monthly budget planner for Indonesian students: splits pocket money into realistic spending posts. Daily Tools #24.

## Why

Most student "budget calculators" are generic percentage splitters with no
sense of real costs. The closest GitHub match,
[ignacymilocha/studget](https://github.com/ignacymilocha/studget), describes
itself as "not complete at all" and is abandoned. `saku-plan` is finished
and tested: it ships two cost profiles tuned for Indonesian students
(`kos` vs living with parents `ortu`), enforces realistic monthly minimums
(floors) per category, redistributes rounding overages proportionally, and —
instead of silently producing impossible numbers — switches to a deficit
mode that fills categories by priority and suggests concrete cuts when the
money is not enough.

## Install

```bash
git clone https://github.com/Kayzenn123/saku-plan.git
cd saku-plan
chmod +x saku-plan.sh
# no dependencies — one bash file, stdlib only
```

Requires: Bash 4+ (Linux, macOS, Windows via Git Bash/WSL, Termux).

## Usage

```bash
./saku-plan.sh --total 3000000 --profile kos
./saku-plan.sh --total 1500000 --profile ortu --days 26 --save 15
echo 3000000 | ./saku-plan.sh --profile kos   # total via stdin
./saku-plan.sh --total 3000000 --profile kos --json
./saku-plan.sh --list-profiles
```

| Flag | Function | Default |
| --- | --- | --- |
| `-t, --total N` | monthly money in Rp (accepts `3.000.000`, `Rp 3.000.000`) | stdin |
| `-p, --profile P` | cost profile: `kos` or `ortu` | required |
| `-d, --days N` | active days in the month | 30 |
| `--save PCT` | savings target, percent of total | 10 |
| `--json` | machine-readable JSON output | off |
| `--list-profiles` | show profiles and their weights | — |
| `--no-color` | disable colors (`NO_COLOR` env also respected) | auto-off when not a TTY |
| `--version`, `-h/--help` | version / help | — |

Exit codes: 0 success, 1 runtime error, 2 argument misuse.

## Example output

Command:

```bash
./saku-plan.sh -t 2750000 -p kos --no-color
```

Output (real, copied from an actual run):

```text
Saku-Plan 1.0.0 — anggaran bulanan
profil: kos | total: Rp2.750.000 | 30 hari aktif | target tabungan: 10%

POS                      ALOKASI      %
------------------ ------------- ------
Kos / kontrakan        Rp825.000    30%
Makan                  Rp687.500    25%
Transport              Rp275.000    10%
Kuliah & print         Rp137.500     5%
Pulsa & kuota           Rp82.500     3%
Tabungan               Rp275.000    10%
Dana darurat           Rp137.500     5%
Jajan & hiburan        Rp330.000    12%

Jatah harian (makan+jajan): Rp33.916/hari
Tabungan: Rp275.000 (10%) — target tabungan 10% tercapai
```

Deficit mode (Rp1.000.000 for a `kos` profile) fills categories by priority
and prints actionable notes instead of impossible numbers:

```text
!! MODE DEFISIT: uang tidak cukup untuk kebutuhan minimum.
...
Catatan:
  - Total Rp1.000.000 di bawah kebutuhan minimum Rp1.225.000 — alokasi mengikuti urutan prioritas.
  - Transport: hanya Rp0 dari minimum Rp150.000 — pertimbangkan: masak sendiri, cari kos lebih murah / patungan, kurangi jajan.
```

## How it works

1. Pick the category list and weight table for the profile (`kos`: 8
   categories incl. rent; `ortu`: 7 categories, no rent).
2. Compute base allocation = `total × weight / 100`, then fix integer
   rounding so the allocations sum to exactly `total`.
3. Enforce monthly floors (e.g. food ≥ Rp20.000 × days, rent ≥ Rp400.000);
   any overage is taken back proportionally from categories above their
   floor.
4. If the total is below the sum of floors, switch to deficit mode:
   fill categories in priority order until the money runs out, mark
   under-funded posts, and print cut suggestions.
5. Derive daily allowance (`(makan + jajan) / days`) and check the savings
   target. Output a human table or `--json`.

Files: `saku-plan.sh` (tool, ~330 lines), `test.sh` (12 tests).

## Limitations

- Floors and weights are rough Indonesian averages (2026), not personalized
  financial advice; adjust with `--days`/`--save` to taste.
- Integer rupiah only; no cents, no multi-currency.
- Deficit suggestions are generic heuristics, not a financial plan.
- Weights are fixed per profile; custom weight tables are not supported yet.

## Development

```bash
bash test.sh   # 12 tests, no dependencies
```

## License

MIT

---
Ringkasan (Bahasa Indonesia): saku-plan membagi uang saku bulanan mahasiswa
ke pos pengeluaran realistis (profil kos vs tinggal dengan orang tua),
dengan batas minimum per pos, hitungan jatah harian, target tabungan, dan
mode defisit yang memberi saran pemangkasan saat uang tidak cukup. Satu file
bash tanpa dependensi, jalan di Linux/macOS/Windows/Termux. Batasan utama:
bobot dan batas minimum adalah rata-rata kasar, bukan nasihat finansial
pribadi.
