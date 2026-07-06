# 公開前チェックリスト

<p align="right">
  <a href="publication_checklist.md">English</a> |
  <strong>日本語</strong>
</p>

`git init`、`git add`、`git commit`、`git push` を行う直前に、リポジトリルートで
このチェックリストを実行してください。

## 1. ライセンス資材が含まれていないことを確認する

```bash
# 実在のPOTCARが出力されないこと。
find . -name 'POTCAR' -o -name 'POTCAR.[0-9]*'

# 実在のPAWデータ断片が出力されないこと。
grep -rIl "End of Dataset" --exclude-dir=tests --exclude='publication_checklist*.md' .
```

- [ ] 実在の `POTCAR` ファイルがツリー内に存在しない
- [ ] サンプルケースには `POTCAR.spec` だけがあり、擬ポテンシャル本文はない

## 2. 個人情報・環境依存情報が含まれていないことを確認する

```bash
# どちらも出力されないこと。
grep -rn "/Users/" --exclude-dir=tests/tmp --exclude='publication_checklist*.md' .
grep -rnE "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}" --exclude-dir=tests/tmp --exclude='publication_checklist*.md' .
```

- [ ] 個人の絶対パスがない
- [ ] メールアドレスがない
- [ ] 所属機関固有のホスト名、アカウント名、スケジューラ設定がない
- [ ] 未公開の材料系、組成、計算結果がない

## 3. `.gitignore` を確認する

```bash
# 一時コピーでignore挙動を確認する。この作業ツリーではgit initしない。
tmp=$(mktemp -d) && cp -r . "$tmp/repo" && cd "$tmp/repo" && git init -q
touch POTCAR WAVECAR OUTCAR examples/STO/00_input/POTCAR
git check-ignore POTCAR WAVECAR OUTCAR examples/STO/00_input/POTCAR
git check-ignore -v examples/STO/00_input/POTCAR.spec || echo "POTCAR.spec is tracked (OK)"
cd - && rm -rf "$tmp"
```

- [ ] `POTCAR`、`POTCAR.*`、主要なVASP出力である `WAVECAR`、`CHGCAR`、
      `OUTCAR`、`OSZICAR`、`vasprun.xml`、`DOSCAR`、`EIGENVAL`、`PROCAR`、
      `XDATCAR` がignoreされる
- [ ] `POTCAR.spec` はignoreされない

## 4. テストを実行する

```bash
bash tests/run_tests.sh
rm -rf tests/tmp
```

- [ ] すべてのテストが成功する
- [ ] テスト後に `tests/tmp` を削除し、生成されたfake VASPファイルをソース
      アーカイブに含めない
- [ ] `bash scripts/run_pbe_hse_dos_pipeline.sh --dry-run examples/STO` で3段階の
      計画が表示される。ローカルで `POTCAR` を作っていない場合、preflight失敗と
      exit code 2 は正常な検出動作です

## 5. 公開設定を確認する

- [ ] 記載済みのCPU/GPU moduleコマンドが公開先の環境に合っていることを確認する。
      CPU版 VASP 6.4.3 は `module load intel; module load impi; module load vasp`、
      GPU版 VASP-GPU 6.4.3 は
      `module load nvidia; module load nvompi; module load vasp-gpu`
- [ ] `templates/` と `examples/` 内の `CONVERGENCE_REQUIRED` と
      `USER_CHECK_REQUIRED` を確認する。特にカットオフやk-meshの収束確認メモを
      見直す
- [ ] 可能なら実際のライセンス済みVASP環境でSTOサンプルを最後まで実行する。
      少なくともPBE段階の実行確認を推奨します

## 6. GitHub公開手順

上記をすべて確認してから実行します。

```bash
git init
git add .
git status
git commit -m "Initial public release"
# GitHubでリポジトリ作成後:
git remote add origin <URL>
git push -u origin main
```

commit前に、`POTCAR`、ライセンス資材、大容量VASP出力、テスト生成物、個人情報が
stageされていないことを目視確認してください。
