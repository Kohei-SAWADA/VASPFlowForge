#!/usr/bin/env bash
# fake_vasp.sh - Minimal VASP emulator for pipeline tests. NOT a physics code.
# It runs inside a stage directory (like real VASP), reads INCAR to decide
# whether the stage is a relaxation or a static run, and fabricates the output
# files the pipeline inspects (OUTCAR, CONTCAR, OSZICAR, WAVECAR/DOSCAR...).
#
# Controlled by the FAKE_VASP_MODE environment variable:
#   ok (default)               all stages succeed
#   unconverged_in:<substr>    stage dirs whose path contains <substr> finish
#                              WITHOUT "reached required accuracy" (exit 0,
#                              like real VASP when NSW is exhausted)
#   crash_in:<substr>          stage dirs whose path contains <substr> leave a
#                              truncated OUTCAR and exit non-zero

set -u
mode="${FAKE_VASP_MODE:-ok}"
here="$(pwd)"

is_static=0
grep -Eq '^[[:space:]]*NSW[[:space:]]*=[[:space:]]*0([^0-9]|$)' INCAR 2>/dev/null && is_static=1
grep -Eq '^[[:space:]]*IBRION[[:space:]]*=[[:space:]]*-1' INCAR 2>/dev/null && is_static=1

variant="ok"
case "$mode" in
  unconverged_in:*)
    pat="${mode#unconverged_in:}"
    case "$here" in *"$pat"*) variant="unconverged" ;; esac ;;
  crash_in:*)
    pat="${mode#crash_in:}"
    case "$here" in *"$pat"*) variant="crash" ;; esac ;;
esac

if [ "$variant" = "crash" ]; then
  {
    echo " fake OUTCAR: run aborted before completion"
    echo " some early output..."
  } > OUTCAR
  echo "fake_vasp: simulated crash" >&2
  exit 137
fi

# Real VASP always writes CONTCAR during/after ionic steps; emulate with a copy.
cp POSCAR CONTCAR 2>/dev/null || true

{
  echo " fake vasp executed in $(basename "$here") (static=$is_static, variant=$variant)"
  if [ "$is_static" -eq 0 ] && [ "$variant" = "ok" ]; then
    echo " reached required accuracy - stopping structural energy minimisation"
  fi
  echo " General timing and accounting informations for this job:"
  echo "                  Elapsed time (sec):       12.345"
} > OUTCAR

echo "  1 F= -.10000000E+02 E0= -.10000000E+02" > OSZICAR

if [ "$is_static" -eq 1 ]; then
  echo "fake DOSCAR" > DOSCAR
  echo "<modeling>fake vasprun</modeling>" > vasprun.xml
else
  echo "FAKE WAVECAR placeholder" > WAVECAR
fi

exit 0
