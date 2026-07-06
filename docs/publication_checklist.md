# Publication Checklist

<p align="right">
  <strong>English</strong> |
  <a href="publication_checklist_ja.md">日本語</a>
</p>

Run this checklist from the repository root immediately before `git init`,
`git add`, `git commit`, or `git push`.

## 1. Confirm that licensed materials are absent

```bash
# This should print no real POTCAR files.
find . -name 'POTCAR' -o -name 'POTCAR.[0-9]*'

# This should print nothing. It catches fragments of real PAW datasets.
grep -rIl "End of Dataset" --exclude-dir=tests --exclude='publication_checklist*.md' .
```

- [ ] No real `POTCAR` file exists anywhere in the tree.
- [ ] Example cases include only `POTCAR.spec`, not pseudopotential data.

## 2. Confirm that personal or environment-specific data is absent

```bash
# These should print nothing.
grep -rn "/Users/" --exclude-dir=tests/tmp --exclude='publication_checklist*.md' .
grep -rnE "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}" --exclude-dir=tests/tmp --exclude='publication_checklist*.md' .
```

- [ ] No personal absolute paths are present.
- [ ] No email addresses are present.
- [ ] No institution-specific host names, account names, or scheduler settings
      are present.
- [ ] No unpublished material systems, compositions, or calculation results are
      present.

## 3. Validate `.gitignore`

```bash
# Check ignore behavior in a temporary copy. Do not initialize git in this tree.
tmp=$(mktemp -d) && cp -r . "$tmp/repo" && cd "$tmp/repo" && git init -q
touch POTCAR WAVECAR OUTCAR examples/STO/00_input/POTCAR
git check-ignore POTCAR WAVECAR OUTCAR examples/STO/00_input/POTCAR
git check-ignore -v examples/STO/00_input/POTCAR.spec || echo "POTCAR.spec is tracked (OK)"
cd - && rm -rf "$tmp"
```

- [ ] `POTCAR`, `POTCAR.*`, and major VASP outputs such as `WAVECAR`, `CHGCAR`,
      `OUTCAR`, `OSZICAR`, `vasprun.xml`, `DOSCAR`, `EIGENVAL`, `PROCAR`, and
      `XDATCAR` are ignored.
- [ ] `POTCAR.spec` is not ignored.

## 4. Run tests

```bash
bash tests/run_tests.sh
rm -rf tests/tmp
```

- [ ] All tests pass.
- [ ] `tests/tmp` is removed after the test run so generated fake VASP files
      are not present in a source archive.
- [ ] `bash scripts/run_pbe_hse_dos_pipeline.sh --dry-run examples/STO` shows
      the three-stage plan. If `POTCAR` has not been created locally, preflight
      failure with exit code 2 is expected.

## 5. Review release settings

- [ ] Confirm that the documented CPU/GPU module commands match the target
      environment:
      `module load intel; module load impi; module load vasp` for CPU VASP
      6.4.3, and `module load nvidia; module load nvompi; module load vasp-gpu`
      for GPU VASP-GPU 6.4.3.
- [ ] Review `CONVERGENCE_REQUIRED` and `USER_CHECK_REQUIRED` notes in
      `templates/` and `examples/`, especially cutoff and k-mesh convergence
      notes.
- [ ] Preferably run the full STO example on a real licensed VASP environment.
      At minimum, confirm that the PBE stage runs.

## 6. Git publication steps

Only after all checks above pass:

```bash
git init
git add .
git status
git commit -m "Initial public release"
# After creating the GitHub repository:
git remote add origin <URL>
git push -u origin main
```

Before committing, visually confirm that no `POTCAR`, licensed material, large
VASP output, test scratch output, or private data is staged.
