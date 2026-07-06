#!/usr/bin/env bash
# run_pbe_hse_dos_pipeline.sh
#
# One-shot batch pipeline for a Linux workstation:
#
#   01_pbe_relax  : PBE structural relaxation
#   02_hse_relax  : HSE06 structural relaxation (POSCAR <- 01 CONTCAR)
#   03_hse_dos    : HSE06 DOS                  (POSCAR <- 02 CONTCAR)
#
# The user runs this script once; stages proceed automatically. After every
# stage the OUTCAR is checked for normal termination (and, for relaxations,
# ionic convergence). If a check fails, the pipeline STOPS and later stages
# are never touched. Re-running the script skips stages that already passed.
#
# Usage:
#   run_pbe_hse_dos_pipeline.sh [--dry-run] [--config FILE] CASE_DIR
#
#   CASE_DIR must contain 00_input/ with:
#     POSCAR, POTCAR (user-supplied, licensed - never distributed here),
#     INCAR.<stage> and KPOINTS.<stage> for each of the three stages.
#
# Configuration (sourced from CASE_DIR/pipeline.conf, or --config FILE,
# or plain environment variables):
#   VASP_CMD               how to launch VASP, e.g. "mpirun -np 16 vasp_std"
#                          Reference modules:
#                            CPU VASP 6.4.3:
#                              module load intel
#                              module load impi
#                              module load vasp
#                            GPU VASP-GPU 6.4.3:
#                              module load nvidia
#                              module load nvompi
#                              module load vasp-gpu
#   REUSE_WAVECAR_FOR_DOS  "auto" (default) or "never"; "auto" reuses the
#                          stage-02 WAVECAR for the DOS stage only when the
#                          KPOINTS of stages 02 and 03 are identical, and
#                          then sets ISTART=1 / ICHARG=0 in the DOS INCAR.
#                          Otherwise the DOS starts from scratch
#                          (ISTART=0 / ICHARG=2), which is always safe.
#
# Exit codes: 0 all stages done / 1 stage failed / 2 preflight failed / 3 usage

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGES="01_pbe_relax 02_hse_relax 03_hse_dos"

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; }

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

record_status() { # stage state detail
  printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" "$2" "$3" >> "$STATUS_FILE"
}

stage_mode() { # relax stages need ionic convergence; DOS is a static run
  case "$1" in
    03_hse_dos) echo "static" ;;
    *)          echo "relax"  ;;
  esac
}

# Portable in-place INCAR tag edit (GNU/BSD safe): replace "TAG = ..." or append.
set_incar_tag() { # FILE TAG VALUE
  local f="$1" tag="$2" val="$3" tmp="$1.tmp.$$"
  awk -v tag="$tag" -v val="$val" '
    BEGIN { done = 0; re = "^[[:space:]]*" tag "[[:space:]]*=" }
    $0 ~ re && !done { print tag " = " val; done = 1; next }
    { print }
    END { if (!done) print tag " = " val }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
}

# Compare two KPOINTS files ignoring the first (comment) line and whitespace.
kpoints_body_equal() { # FILE1 FILE2
  local a b
  a="$(tail -n +2 "$1" | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//')"
  b="$(tail -n +2 "$2" | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//')"
  [ "$a" = "$b" ]
}

show_diagnostics() { # STAGE_DIR
  local d="$1"
  echo "---- diagnostics: $d ----" >&2
  if [ -f "$d/vasp.err" ] && [ -s "$d/vasp.err" ]; then
    echo "* tail vasp.err:" >&2; tail -n 15 "$d/vasp.err" >&2
  fi
  if [ -f "$d/OSZICAR" ]; then
    echo "* tail OSZICAR:" >&2; tail -n 5 "$d/OSZICAR" >&2
  fi
  if [ -f "$d/OUTCAR" ]; then
    echo "* tail OUTCAR:" >&2; tail -n 10 "$d/OUTCAR" >&2
  fi
  echo "-------------------------------" >&2
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
DRY_RUN=0
CONFIG_FILE=""
CASE_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --config)  CONFIG_FILE="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 3 ;;
    *)  CASE_DIR="$1" ;;
  esac
  shift
done

if [ -z "$CASE_DIR" ]; then
  usage >&2
  exit 3
fi
CASE_DIR="$(cd "$CASE_DIR" 2>/dev/null && pwd)" || { echo "case directory not found" >&2; exit 3; }
INPUT_DIR="$CASE_DIR/00_input"
STATUS_FILE="$CASE_DIR/pipeline_status.tsv"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
if [ -z "$CONFIG_FILE" ] && [ -f "$CASE_DIR/pipeline.conf" ]; then
  CONFIG_FILE="$CASE_DIR/pipeline.conf"
fi
if [ -n "$CONFIG_FILE" ]; then
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "config file not found: $CONFIG_FILE" >&2
    exit 3
  fi
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
  log "config loaded: $CONFIG_FILE"
fi
REUSE_WAVECAR_FOR_DOS="${REUSE_WAVECAR_FOR_DOS:-auto}"

# ---------------------------------------------------------------------------
# Preflight (read-only)
# ---------------------------------------------------------------------------
PREFLIGHT_OK=1
if ! "$SCRIPT_DIR/preflight_check.sh" "$CASE_DIR"; then
  PREFLIGHT_OK=0
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "pipeline: preflight failed (details above); showing the plan anyway (dry run)." >&2
  else
    echo "pipeline: preflight failed; nothing was run." >&2
    exit 2
  fi
fi

if [ -z "${VASP_CMD:-}" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    log "WARNING: VASP_CMD is not set (required for a real run). Load VASP modules, then set VASP_CMD."
  else
    echo "pipeline: VASP_CMD is not set. Set it in $CASE_DIR/pipeline.conf or the environment." >&2
    echo "  CPU modules: module load intel; module load impi; module load vasp" >&2
    echo "  GPU modules: module load nvidia; module load nvompi; module load vasp-gpu" >&2
    echo "  example VASP_CMD: VASP_CMD=\"mpirun -np 16 vasp_std\"" >&2
    exit 2
  fi
fi

# ---------------------------------------------------------------------------
# Dry run: report the plan and current state, create/modify nothing, then exit
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
  echo "== dry run: plan for case $CASE_DIR =="
  echo "  VASP_CMD              : ${VASP_CMD:-<NOT SET>}"
  echo "  REUSE_WAVECAR_FOR_DOS : $REUSE_WAVECAR_FOR_DOS"
  prev="00_input/POSCAR"
  for stage in $STAGES; do
    mode="$(stage_mode "$stage")"
    state="not run yet"
    if [ -f "$CASE_DIR/$stage/OUTCAR" ]; then
      if "$SCRIPT_DIR/check_vasp_done.sh" --quiet --mode "$mode" "$CASE_DIR/$stage"; then
        state="DONE (will be skipped)"
      else
        state="FAILED/INCOMPLETE (pipeline will stop here; inspect or remove the directory)"
      fi
    fi
    echo "  stage $stage  mode=$mode  POSCAR <- $prev  [$state]"
    prev="$stage/CONTCAR"
  done
  if [ "$PREFLIGHT_OK" -eq 1 ]; then
    echo "== dry run: inputs valid; no files were created or modified =="
    exit 0
  else
    echo "== dry run: preflight FAILED (fix inputs before a real run); no files were created or modified ==" >&2
    exit 2
  fi
fi

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
[ -f "$STATUS_FILE" ] || printf 'timestamp\tstage\tstate\tdetail\n' > "$STATUS_FILE"
log "pipeline start: $CASE_DIR"

prev=""
for stage in $STAGES; do
  sdir="$CASE_DIR/$stage"
  mode="$(stage_mode "$stage")"

  # ---- resume logic: a stage with an OUTCAR is either done (skip) or bad (stop)
  if [ -f "$sdir/OUTCAR" ]; then
    if "$SCRIPT_DIR/check_vasp_done.sh" --quiet --mode "$mode" "$sdir"; then
      log "SKIP  $stage (already finished; check passed)"
      record_status "$stage" "SKIPPED" "already complete"
      prev="$sdir"
      continue
    else
      rc=$?
      record_status "$stage" "FAILED" "existing OUTCAR does not pass check (rc=$rc)"
      show_diagnostics "$sdir"
      echo "pipeline: $stage contains an OUTCAR that does not pass the completion check (rc=$rc)." >&2
      echo "  Inspect $sdir, fix the cause, then remove the stage directory to redo it:" >&2
      echo "    rm -rf '$sdir'   (also remove later stage directories if present)" >&2
      exit 1
    fi
  fi

  # ---- prepare inputs
  log "PREP  $stage"
  mkdir -p "$sdir"
  cp "$INPUT_DIR/INCAR.$stage"   "$sdir/INCAR"
  cp "$INPUT_DIR/KPOINTS.$stage" "$sdir/KPOINTS"
  cp "$INPUT_DIR/POTCAR"         "$sdir/POTCAR"

  if [ -z "$prev" ]; then
    cp "$INPUT_DIR/POSCAR" "$sdir/POSCAR"
  else
    if ! "$SCRIPT_DIR/promote_contcar.sh" "$prev" "$sdir"; then
      record_status "$stage" "FAILED" "CONTCAR -> POSCAR handoff failed"
      echo "pipeline: could not hand the structure over from $prev to $stage." >&2
      exit 1
    fi
  fi

  # ---- DOS stage: decide WAVECAR reuse (safe fallback is always from-scratch)
  if [ "$stage" = "03_hse_dos" ]; then
    reuse=0
    if [ "$REUSE_WAVECAR_FOR_DOS" != "never" ] && [ -n "$prev" ] \
       && [ -s "$prev/WAVECAR" ] && kpoints_body_equal "$prev/KPOINTS" "$sdir/KPOINTS"; then
      reuse=1
    fi
    if [ "$reuse" -eq 1 ]; then
      ln -sf "../$(basename "$prev")/WAVECAR" "$sdir/WAVECAR"
      set_incar_tag "$sdir/INCAR" "ISTART" "1"
      set_incar_tag "$sdir/INCAR" "ICHARG" "0"
      log "DOS: reusing WAVECAR from $(basename "$prev") (identical KPOINTS) -> ISTART=1, ICHARG=0"
      record_status "$stage" "PREPARED" "WAVECAR reuse enabled (ISTART=1 ICHARG=0)"
    else
      rm -f "$sdir/WAVECAR"
      set_incar_tag "$sdir/INCAR" "ISTART" "0"
      set_incar_tag "$sdir/INCAR" "ICHARG" "2"
      log "DOS: starting from scratch (ISTART=0, ICHARG=2)"
      record_status "$stage" "PREPARED" "from scratch (ISTART=0 ICHARG=2)"
    fi
  else
    record_status "$stage" "PREPARED" "inputs staged"
  fi

  # ---- run VASP
  log "RUN   $stage: $VASP_CMD"
  record_status "$stage" "RUNNING" "$VASP_CMD"
  ( cd "$sdir" && eval "$VASP_CMD" > vasp.out 2> vasp.err )
  vasp_rc=$?
  if [ "$vasp_rc" -ne 0 ]; then
    record_status "$stage" "FAILED" "VASP exited with code $vasp_rc"
    show_diagnostics "$sdir"
    echo "pipeline: $stage: VASP exited with non-zero status $vasp_rc. Stopping." >&2
    exit 1
  fi

  # ---- judge completion / convergence
  if "$SCRIPT_DIR/check_vasp_done.sh" --mode "$mode" "$sdir"; then
    log "DONE  $stage"
    record_status "$stage" "DONE" "check passed (mode=$mode)"
  else
    rc=$?
    record_status "$stage" "FAILED" "completion check failed (rc=$rc mode=$mode)"
    show_diagnostics "$sdir"
    echo "pipeline: $stage failed the completion/convergence check (rc=$rc). Stopping; later stages were not touched." >&2
    exit 1
  fi

  prev="$sdir"
done

record_status "pipeline" "DONE" "all stages complete"
log "ALL STAGES COMPLETE"
log "results:"
log "  relaxed PBE structure   : $CASE_DIR/01_pbe_relax/CONTCAR"
log "  relaxed HSE06 structure : $CASE_DIR/02_hse_relax/CONTCAR"
log "  DOS outputs             : $CASE_DIR/03_hse_dos/{DOSCAR,vasprun.xml}"
log "  status history          : $STATUS_FILE"
exit 0
