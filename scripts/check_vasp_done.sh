#!/usr/bin/env bash
# check_vasp_done.sh - Judge whether a VASP run in CALC_DIR finished normally
# (and, for relaxations, converged). Standalone; usable inside or outside the
# pipeline. No VASP required.
#
# Usage:
#   check_vasp_done.sh --mode relax|static [--quiet] CALC_DIR
#
# Judgment criteria (inherited from a production PBE -> HSE06 -> HSE06-DOS
# chain workflow; grep targets are literal strings VASP prints in OUTCAR):
#   finished  : OUTCAR is non-empty
#               AND contains "General timing and accounting informations for this job"
#               AND contains "Elapsed time"
#   converged : (relax mode only)
#               OUTCAR contains "reached required accuracy"
#               AND CONTCAR exists and is non-empty
#
# Exit codes (any non-zero means: do NOT proceed to the next stage):
#   0  finished (and, in relax mode, converged)
#   1  not finished (no timing footer: still running, killed, or never completed)
#   2  finished but NOT converged (relax mode: NSW exhausted etc.)
#   3  abnormal (OUTCAR missing/empty, CONTCAR missing/empty in relax mode,
#      or bad usage)

set -u

MODE=""
QUIET=0
DIR=""

msg() { [ "$QUIET" -eq 1 ] || echo "$@"; }

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)  MODE="${2:-}"; shift ;;
    --quiet) QUIET=1 ;;
    -h|--help) usage; exit 3 ;;
    -*) echo "check_vasp_done.sh: unknown option: $1" >&2; exit 3 ;;
    *) DIR="$1" ;;
  esac
  shift
done

if [ -z "$DIR" ] || { [ "$MODE" != "relax" ] && [ "$MODE" != "static" ]; }; then
  echo "check_vasp_done.sh: usage error (need --mode relax|static and CALC_DIR)" >&2
  exit 3
fi

OUTCAR="$DIR/OUTCAR"
CONTCAR="$DIR/CONTCAR"

# --- abnormal: OUTCAR missing or empty -------------------------------------
if [ ! -s "$OUTCAR" ]; then
  msg "ABNORMAL: $OUTCAR is missing or empty"
  exit 3
fi

# --- finished? --------------------------------------------------------------
if ! grep -q "General timing and accounting informations for this job" "$OUTCAR" \
   || ! grep -q "Elapsed time" "$OUTCAR"; then
  msg "NOT FINISHED: $OUTCAR has no timing footer (job still running or aborted)"
  exit 1
fi

if [ "$MODE" = "static" ]; then
  msg "OK: static run in $DIR finished normally"
  exit 0
fi

# --- relax mode: converged? ---------------------------------------------------
if ! grep -q "reached required accuracy" "$OUTCAR"; then
  msg "NOT CONVERGED: $DIR finished but 'reached required accuracy' is absent"
  msg "  (ionic loop probably exhausted NSW; inspect OSZICAR / OUTCAR)"
  exit 2
fi

if [ ! -s "$CONTCAR" ]; then
  msg "ABNORMAL: $DIR converged but CONTCAR is missing or empty"
  exit 3
fi

msg "OK: relaxation in $DIR finished and converged"
exit 0
