# Workflow Details

<p align="right">
  <strong>English</strong> |
  <a href="workflow_ja.md">日本語</a>
</p>

This document describes the three-stage chain executed by
`scripts/run_pbe_hse_dos_pipeline.sh`. The workflow generalizes a practical
PBE relax -> HSE06 relax -> HSE06 DOS automation pattern with strict
completion checks and explicit structure handoff between stages.

## Stage Layout

| Stage | Directory | Check mode | POSCAR source |
|---|---|---|---|
| PBE structural relaxation | `01_pbe_relax/` | relax | `00_input/POSCAR` |
| HSE06 structural relaxation | `02_hse_relax/` | relax | `01_pbe_relax/CONTCAR` |
| HSE06 DOS | `03_hse_dos/` | static | `02_hse_relax/CONTCAR` |

Each stage receives its own `INCAR` and `KPOINTS` from `00_input/`:
`INCAR.<stage>` becomes `INCAR`, and `KPOINTS.<stage>` becomes `KPOINTS`.
The same user-provided `POTCAR` is copied into all three stage directories.
VASP is launched inside each stage directory through `VASP_CMD`. Standard
output is written to `vasp.out`, and standard error is written to `vasp.err`.

The reference module environments are CPU VASP 6.4.3:

```bash
module load intel
module load impi
module load vasp
```

and GPU VASP-GPU 6.4.3:

```bash
module load nvidia
module load nvompi
module load vasp-gpu
```

Set `VASP_CMD` to the executable exposed by the loaded module, for example
`mpirun -np 16 vasp_std` for a CPU run. Replace `vasp_std` if your environment
uses a different executable name.

## Completion and Convergence Checks

`scripts/check_vasp_done.sh` checks `OUTCAR` content rather than trusting the
process exit code alone. VASP can finish with exit code 0 even when an ionic
relaxation did not converge, so the pipeline uses conservative text gates.

Common completion requirements:

- `OUTCAR` exists and is not empty.
- `OUTCAR` contains `General timing and accounting informations for this job`.
- `OUTCAR` contains `Elapsed time`.

Additional relaxation requirements:

- `OUTCAR` contains `reached required accuracy`.
- `CONTCAR` exists and is not empty.

Exit codes:

| Code | Meaning | Pipeline behavior |
|---|---|---|
| 0 | Complete. Relaxation also passed convergence checks. | Continue |
| 1 | Incomplete. Timing footer was not found. | Stop |
| 2 | Finished but not converged, for example after exhausting `NSW`. | Stop |
| 3 | Invalid or missing required file, such as empty `OUTCAR` or `CONTCAR`. | Stop |

If the VASP process itself returns a nonzero exit code, the pipeline stops
before evaluating the next stage.

## CONTCAR-to-POSCAR Promotion

`scripts/promote_contcar.sh` enforces the stage handoff rule.

- The source `CONTCAR` must exist, be non-empty, and contain at least 8 lines.
- The script copies the source `CONTCAR` to the destination `POSCAR`.
- It writes `POSCAR.provenance.txt` with the source path, timestamp, and
  SHA-256 checksum.
- The next stage `POSCAR` must come from the previous stage `CONTCAR`.

Manual replacement of a promoted `POSCAR` breaks the reproducibility contract
of this workflow.

## DOS WAVECAR Reuse Rule

When `REUSE_WAVECAR_FOR_DOS="auto"`:

1. The pipeline compares the HSE relaxation and DOS `KPOINTS` files. The first
   comment line is ignored and whitespace is normalized.
2. If the files match exactly and `02_hse_relax/WAVECAR` is non-empty,
   `03_hse_dos/WAVECAR` is linked to it and the DOS `INCAR` is set to
   `ISTART = 1` and `ICHARG = 0`.
3. Otherwise, the DOS stage starts from scratch with `ISTART = 0` and
   `ICHARG = 2`.

Reusing an incompatible `WAVECAR` can corrupt the calculation. Ambiguous cases
therefore fall back to the safer no-reuse path. Set
`REUSE_WAVECAR_FOR_DOS="never"` to disable reuse completely.

## Resume Behavior

- If an existing stage has an `OUTCAR` that passes the required check, the
  stage is recorded as `SKIPPED`.
- If an existing stage has an `OUTCAR` that fails the required check, the
  pipeline stops there.
- The pipeline intentionally does not auto-retry failed calculations. Inspect
  the cause, remove the failed stage directory, and rerun the pipeline.

This design keeps failed physical or numerical conditions visible instead of
hiding them behind automatic retries.

## Status Log

`pipeline_status.tsv` is an append-only TSV file with:

```text
timestamp / stage / state / detail
```

States are `PREPARED`, `RUNNING`, `DONE`, `FAILED`, and `SKIPPED`. The file is
never overwritten, so it preserves the calculation history.

## Troubleshooting

| Symptom | Common cause | Action |
|---|---|---|
| Stops with `rc=2` | Relaxation did not converge, `NSW` was too small, initial structure was poor, or `EDIFFG` was too strict. | Inspect `OSZICAR`, adjust the input, remove the failed stage, and rerun. |
| Stops with `rc=1` | Job was interrupted, wall time expired, or the node failed. | Check `vasp.err`, scheduler logs, and rerun if appropriate. |
| VASP exits nonzero | MPI setup, memory, library, `POTCAR`, or `POSCAR` problem. | Check `vasp.err` and rerun `preflight_check.sh`. |
| Preflight reports element-order mismatch | `POTCAR` was concatenated in the wrong order. | Rebuild `POTCAR` following `POTCAR.spec`. |
| HSE06 is very slow | Hybrid-functional calculations are expensive. | Use a lighter validated k-mesh and tune `KPAR` or `NCORE`. |

## Scheduler Environments

This pipeline is designed to run VASP synchronously on a workstation. On
SLURM, PBS, or similar cluster systems, the simplest approach is to submit the
whole pipeline as one scheduler job after allocating the required resources.

```bash
# Example inside a SLURM job script:
module load intel
module load impi
module load vasp
VASP_CMD="srun vasp_std" bash scripts/run_pbe_hse_dos_pipeline.sh my_case
```

Asynchronous submission where each stage becomes a separate scheduler job is
outside the scope of this repository.
