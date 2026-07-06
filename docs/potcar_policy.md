# POTCAR Policy

<p align="right">
  <strong>English</strong> |
  <a href="potcar_policy_ja.md">日本語</a>
</p>

## Policy

**This repository does not include `POTCAR` files.**

- `POTCAR` files contain PAW pseudopotential data distributed under the VASP
  license. They are paid, licensed materials and must not be redistributed on
  GitHub or through this repository.
- The repository may include only public metadata about the required
  pseudopotentials:
  - potential labels, for example `Sr_sv`, `Ti`, and `O`
  - concatenation order, matching the element order in `POSCAR`
  - example commands for local concatenation
- `.gitignore` excludes `POTCAR` and `POTCAR.*` unconditionally. The only
  allowed exception is `POTCAR.spec`, which is a plain-text specification and
  contains no pseudopotential data.

## Relation to Tests

The automated tests generate a fake `POTCAR` at runtime. It contains only
minimal `TITEL` lines and no pseudopotential data. The repository itself does
not need, and must not contain, a real file named `POTCAR`.
