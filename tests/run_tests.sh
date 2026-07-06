#!/usr/bin/env bash
# run_tests.sh - Self-contained test suite. Requires bash + coreutils only;
# VASP itself is NOT needed (a fake VASP fabricates outputs).
#
# Usage:  bash tests/run_tests.sh
# Exit:   0 all tests passed / 1 otherwise
#
# Covers:
#   - check_vasp_done.sh exit codes against fake OUTCARs (testdata/)
#   - promote_contcar.sh CONTCAR -> POSCAR handoff and validation
#   - full pipeline run with a fake VASP (success, WAVECAR-reuse variant,
#     unconverged stop, crash stop, resume contract, preflight, dry run)

set -u

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
SCRIPTS="$REPO_DIR/scripts"
TD="$TESTS_DIR/testdata"
TMP="$TESTS_DIR/tmp"
FAKE_VASP="$TESTS_DIR/bin/fake_vasp.sh"
PIPELINE="$SCRIPTS/run_pbe_hse_dos_pipeline.sh"

rm -rf "$TMP"
mkdir -p "$TMP"

n=0; pass=0; fail=0
ok()  { n=$((n+1)); pass=$((pass+1)); echo "ok $n - $1"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo "NOT OK $n - $1"; }

# assert_rc DESC EXPECTED_RC CMD...
assert_rc() {
  local desc="$1" want="$2"; shift 2
  "$@" >/dev/null 2>&1
  local got=$?
  if [ "$got" -eq "$want" ]; then ok "$desc"; else bad "$desc (want rc=$want, got rc=$got)"; fi
}
# assert_true DESC CMD...
assert_true() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}
# assert_false DESC CMD...
assert_false() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then bad "$desc"; else ok "$desc"; fi
}

# ---------------------------------------------------------------------------
echo "== unit: check_vasp_done.sh =="
# ---------------------------------------------------------------------------
mk_calc() { # DIR OUTCAR_EXAMPLE [CONTCAR_EXAMPLE]
  mkdir -p "$1"
  cp "$TD/$2" "$1/OUTCAR"
  if [ -n "${3:-}" ]; then cp "$TD/$3" "$1/CONTCAR"; fi
}

d="$TMP/u1"; mk_calc "$d" OUTCAR_relax_converged.example CONTCAR_valid.example
assert_rc "relax converged + CONTCAR -> 0" 0 "$SCRIPTS/check_vasp_done.sh" --quiet --mode relax "$d"

d="$TMP/u2"; mk_calc "$d" OUTCAR_relax_converged.example
assert_rc "relax converged but CONTCAR missing -> 3" 3 "$SCRIPTS/check_vasp_done.sh" --quiet --mode relax "$d"

d="$TMP/u3"; mk_calc "$d" OUTCAR_relax_unconverged.example CONTCAR_valid.example
assert_rc "relax finished but unconverged -> 2" 2 "$SCRIPTS/check_vasp_done.sh" --quiet --mode relax "$d"

d="$TMP/u4"; mk_calc "$d" OUTCAR_incomplete.example
assert_rc "incomplete OUTCAR (no footer) -> 1" 1 "$SCRIPTS/check_vasp_done.sh" --quiet --mode relax "$d"

d="$TMP/u5"; mkdir -p "$d"
assert_rc "missing OUTCAR -> 3" 3 "$SCRIPTS/check_vasp_done.sh" --quiet --mode relax "$d"

d="$TMP/u6"; mk_calc "$d" OUTCAR_static_ok.example
assert_rc "static finished -> 0" 0 "$SCRIPTS/check_vasp_done.sh" --quiet --mode static "$d"

d="$TMP/u7"; mk_calc "$d" OUTCAR_incomplete.example
assert_rc "static incomplete -> 1" 1 "$SCRIPTS/check_vasp_done.sh" --quiet --mode static "$d"

assert_rc "usage error -> 3" 3 "$SCRIPTS/check_vasp_done.sh" --mode bogus "$TMP/u1"

# ---------------------------------------------------------------------------
echo "== unit: promote_contcar.sh =="
# ---------------------------------------------------------------------------
src="$TMP/p1_src"; dst="$TMP/p1_dst"; mkdir -p "$src" "$dst"
cp "$TD/CONTCAR_valid.example" "$src/CONTCAR"
assert_rc "valid CONTCAR promoted -> 0" 0 "$SCRIPTS/promote_contcar.sh" "$src" "$dst"
assert_true "POSCAR identical to CONTCAR" cmp -s "$src/CONTCAR" "$dst/POSCAR"
assert_true "provenance file written" test -s "$dst/POSCAR.provenance.txt"

src="$TMP/p2_src"; dst="$TMP/p2_dst"; mkdir -p "$src" "$dst"
: > "$src/CONTCAR"
assert_rc "empty CONTCAR rejected -> 1" 1 "$SCRIPTS/promote_contcar.sh" "$src" "$dst"
assert_false "no POSCAR written on rejection" test -e "$dst/POSCAR"

src="$TMP/p3_src"; dst="$TMP/p3_dst"; mkdir -p "$src" "$dst"
assert_rc "missing CONTCAR rejected -> 1" 1 "$SCRIPTS/promote_contcar.sh" "$src" "$dst"

# ---------------------------------------------------------------------------
echo "== integration: pipeline with fake VASP =="
# ---------------------------------------------------------------------------
write_fake_potcar() { # FILE  (contains NO pseudopotential data; TITEL lines only)
  cat > "$1" <<'EOF'
FAKE POTCAR FOR PIPELINE TESTS ONLY - contains no pseudopotential data
   TITEL  = PAW_PBE Sr_sv 00Jan0000 (fake)
   TITEL  = PAW_PBE Ti 00Jan0000 (fake)
   TITEL  = PAW_PBE O 00Jan0000 (fake)
End of fake dataset
EOF
}

mk_case() { # CASE_DIR
  mkdir -p "$1/00_input"
  cp "$REPO_DIR/examples/STO/00_input/POSCAR" "$1/00_input/POSCAR"
  local s
  for s in 01_pbe_relax 02_hse_relax 03_hse_dos; do
    cp "$REPO_DIR/examples/STO/00_input/INCAR.$s"   "$1/00_input/INCAR.$s"
    cp "$REPO_DIR/examples/STO/00_input/KPOINTS.$s" "$1/00_input/KPOINTS.$s"
  done
  write_fake_potcar "$1/00_input/POTCAR"
  {
    printf 'VASP_CMD="\\"%s\\""\n' "$FAKE_VASP"
    printf 'REUSE_WAVECAR_FOR_DOS="auto"\n'
  } > "$1/pipeline.conf"
}

unset FAKE_VASP_MODE || true

# --- dry run creates nothing
case1="$TMP/case_dryrun"; mk_case "$case1"
assert_rc "dry run exits 0" 0 bash "$PIPELINE" --dry-run "$case1"
assert_false "dry run created no stage dir" test -d "$case1/01_pbe_relax"
assert_false "dry run created no status file" test -e "$case1/pipeline_status.tsv"

# --- full successful run (STO KPOINTS: stage02 != stage03 -> no WAVECAR reuse)
case2="$TMP/case_ok"; mk_case "$case2"
assert_rc "full pipeline run exits 0" 0 bash "$PIPELINE" "$case2"
assert_true "stage 01 OUTCAR exists" test -s "$case2/01_pbe_relax/OUTCAR"
assert_true "stage 02 OUTCAR exists" test -s "$case2/02_hse_relax/OUTCAR"
assert_true "stage 03 OUTCAR exists" test -s "$case2/03_hse_dos/OUTCAR"
assert_true "02 POSCAR == 01 CONTCAR" cmp -s "$case2/01_pbe_relax/CONTCAR" "$case2/02_hse_relax/POSCAR"
assert_true "03 POSCAR == 02 CONTCAR" cmp -s "$case2/02_hse_relax/CONTCAR" "$case2/03_hse_dos/POSCAR"
assert_true "provenance recorded in 02" test -s "$case2/02_hse_relax/POSCAR.provenance.txt"
assert_true "pipeline DONE recorded" grep -q "pipeline	DONE" "$case2/pipeline_status.tsv"
assert_true "DOS from scratch (ISTART = 0) since KPOINTS differ" \
  grep -Eq '^ISTART = 0' "$case2/03_hse_dos/INCAR"
assert_false "no WAVECAR link in 03" test -e "$case2/03_hse_dos/WAVECAR"

# --- rerun skips everything
assert_rc "rerun of finished case exits 0" 0 bash "$PIPELINE" "$case2"
skipped=$(grep -c "SKIPPED" "$case2/pipeline_status.tsv")
if [ "$skipped" -ge 3 ]; then ok "rerun skipped all three stages"; else bad "rerun skipped only $skipped stages"; fi

# --- WAVECAR reuse variant: make stage03 KPOINTS identical to stage02
case3="$TMP/case_wavecar"; mk_case "$case3"
cp "$case3/00_input/KPOINTS.02_hse_relax" "$case3/00_input/KPOINTS.03_hse_dos"
assert_rc "pipeline (identical 02/03 KPOINTS) exits 0" 0 bash "$PIPELINE" "$case3"
assert_true "WAVECAR linked into 03" test -e "$case3/03_hse_dos/WAVECAR"
assert_true "ISTART switched to 1 for reuse" grep -Eq '^ISTART = 1' "$case3/03_hse_dos/INCAR"
assert_true "ICHARG switched to 0 for reuse" grep -Eq '^ICHARG = 0' "$case3/03_hse_dos/INCAR"

# --- failure in stage 02 stops the chain before stage 03
case4="$TMP/case_fail02"; mk_case "$case4"
export FAKE_VASP_MODE="unconverged_in:02_hse_relax"
assert_rc "unconverged stage 02 -> pipeline exits 1" 1 bash "$PIPELINE" "$case4"
unset FAKE_VASP_MODE
assert_false "stage 03 never created after failure" test -d "$case4/03_hse_dos"
assert_true "FAILED recorded for stage 02" grep -q "02_hse_relax	FAILED" "$case4/pipeline_status.tsv"

# --- resume contract: bad OUTCAR blocks rerun until the user removes the dir
assert_rc "rerun with stale failed stage still exits 1" 1 bash "$PIPELINE" "$case4"
rm -rf "$case4/02_hse_relax"
assert_rc "after removing failed stage, pipeline completes" 0 bash "$PIPELINE" "$case4"
assert_true "stage 01 was skipped on resume" grep -q "01_pbe_relax	SKIPPED" "$case4/pipeline_status.tsv"
assert_true "stage 03 completed on resume" test -s "$case4/03_hse_dos/OUTCAR"

# --- crash (non-zero VASP exit) stops the chain
case5="$TMP/case_crash"; mk_case "$case5"
export FAKE_VASP_MODE="crash_in:01_pbe_relax"
assert_rc "crash in stage 01 -> pipeline exits 1" 1 bash "$PIPELINE" "$case5"
unset FAKE_VASP_MODE
assert_false "stage 02 never created after crash" test -d "$case5/02_hse_relax"

# --- preflight: missing POTCAR refuses to run
case6="$TMP/case_nopotcar"; mk_case "$case6"
rm -f "$case6/00_input/POTCAR"
assert_rc "missing POTCAR -> preflight failure (rc=2)" 2 bash "$PIPELINE" "$case6"
assert_false "nothing was run without POTCAR" test -d "$case6/01_pbe_relax"

# --- dry run without POTCAR: plan is shown but exit code reports the problem
case6b="$TMP/case_dry_nopotcar"; mk_case "$case6b"
rm -f "$case6b/00_input/POTCAR"
assert_rc "dry run without POTCAR -> rc=2" 2 bash "$PIPELINE" --dry-run "$case6b"
out="$(bash "$PIPELINE" --dry-run "$case6b" 2>&1 || true)"
case "$out" in
  *"dry run: plan"*) ok "dry run still prints the plan without POTCAR" ;;
  *) bad "dry run did not print the plan without POTCAR" ;;
esac
assert_false "dry run without POTCAR created nothing" test -d "$case6b/01_pbe_relax"

# --- preflight: element-order mismatch refuses to run
case7="$TMP/case_badorder"; mk_case "$case7"
cat > "$case7/00_input/POTCAR" <<'EOF'
FAKE POTCAR FOR PIPELINE TESTS ONLY - wrong element order on purpose
   TITEL  = PAW_PBE Ti 00Jan0000 (fake)
   TITEL  = PAW_PBE Sr_sv 00Jan0000 (fake)
   TITEL  = PAW_PBE O 00Jan0000 (fake)
EOF
assert_rc "POSCAR/POTCAR order mismatch -> rc=2" 2 bash "$PIPELINE" "$case7"

# ---------------------------------------------------------------------------
echo "== summary: $pass passed, $fail failed, $n total =="
# ---------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
  exit 0
else
  exit 1
fi
