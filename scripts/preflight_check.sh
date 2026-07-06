#!/usr/bin/env bash
# preflight_check.sh - Validate a case directory BEFORE any VASP run.
# No files are created or modified; read-only.
#
# Usage:
#   preflight_check.sh CASE_DIR
#
# A valid case directory looks like:
#   CASE_DIR/
#     pipeline.conf          (optional here; the pipeline checks VASP_CMD itself)
#     00_input/
#       POSCAR               initial structure
#       POTCAR               concatenated by the USER from their licensed VASP
#                            pseudopotential library (never distributed here)
#       INCAR.01_pbe_relax    KPOINTS.01_pbe_relax
#       INCAR.02_hse_relax    KPOINTS.02_hse_relax
#       INCAR.03_hse_dos      KPOINTS.03_hse_dos
#
# Checks:
#   - all required input files exist and are non-empty
#   - POTCAR element order (TITEL lines) matches POSCAR line 6
#     (skipped with a warning for VASP4-style POSCAR without symbols)
#
# Exit codes: 0 all good / 1 validation failure / 3 usage error

set -u

STAGES="01_pbe_relax 02_hse_relax 03_hse_dos"

if [ $# -ne 1 ]; then
  echo "usage: preflight_check.sh CASE_DIR" >&2
  exit 3
fi

CASE_DIR="$1"
INPUT_DIR="$CASE_DIR/00_input"
errors=0

fail() { echo "PREFLIGHT FAIL: $*" >&2; errors=$((errors + 1)); }
note() { echo "preflight: $*"; }

[ -d "$CASE_DIR" ]  || { echo "PREFLIGHT FAIL: case directory not found: $CASE_DIR" >&2; exit 1; }
[ -d "$INPUT_DIR" ] || { echo "PREFLIGHT FAIL: $INPUT_DIR not found (see README: inputs live in 00_input/)" >&2; exit 1; }

# --- required files ----------------------------------------------------------
[ -s "$INPUT_DIR/POSCAR" ] || fail "$INPUT_DIR/POSCAR is missing or empty"

if [ ! -s "$INPUT_DIR/POTCAR" ]; then
  fail "$INPUT_DIR/POTCAR is missing or empty.
  POTCAR is licensed material and is NOT distributed with this repository.
  Build it from YOUR VASP pseudopotential library; see 00_input/POTCAR.spec
  (if present) and docs/potcar_policy.md for the required potentials and order."
fi

for s in $STAGES; do
  [ -s "$INPUT_DIR/INCAR.$s" ]   || fail "$INPUT_DIR/INCAR.$s is missing or empty"
  [ -s "$INPUT_DIR/KPOINTS.$s" ] || fail "$INPUT_DIR/KPOINTS.$s is missing or empty"
done

# --- POSCAR vs POTCAR element order -------------------------------------------
if [ -s "$INPUT_DIR/POSCAR" ] && [ -s "$INPUT_DIR/POTCAR" ]; then
  poscar_elems=$(sed -n '6p' "$INPUT_DIR/POSCAR" | tr -s ' \t' ' ' | sed 's/^ //;s/ $//')
  case "$poscar_elems" in
    *[A-Za-z]*)
      potcar_elems=$(grep -E '^[[:space:]]*TITEL' "$INPUT_DIR/POTCAR" \
                     | awk '{print $4}' | cut -d_ -f1 | tr '\n' ' ' | sed 's/ $//')
      if [ -z "$potcar_elems" ]; then
        fail "no TITEL lines found in $INPUT_DIR/POTCAR; is it a valid PAW POTCAR?"
      elif [ "$poscar_elems" != "$potcar_elems" ]; then
        fail "element order mismatch:
  POSCAR line 6 : $poscar_elems
  POTCAR TITEL  : $potcar_elems
  The POTCAR concatenation order MUST match the POSCAR element order."
      else
        note "element order OK: $poscar_elems"
      fi
      ;;
    *)
      note "WARNING: POSCAR line 6 has no element symbols (VASP4 style?); skipping POTCAR order check. Verify manually."
      ;;
  esac
fi

if [ "$errors" -gt 0 ]; then
  echo "preflight: $errors problem(s) found in $CASE_DIR" >&2
  exit 1
fi

note "all checks passed for $CASE_DIR"
exit 0
