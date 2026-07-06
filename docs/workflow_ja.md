# ワークフロー詳細

<p align="right">
  <a href="workflow.md">English</a> |
  <strong>日本語</strong>
</p>

この文書では、`scripts/run_pbe_hse_dos_pipeline.sh` が実行する3段階チェーンの
仕様を説明します。このワークフローは、実務でよく使う
`PBE relax -> HSE06 relax -> HSE06 DOS` の流れを、完了判定と構造引き継ぎを
明示した形に整理したものです。

## ステージ構成

| ステージ | ディレクトリ | 判定モード | POSCARの由来 |
|---|---|---|---|
| PBE構造緩和 | `01_pbe_relax/` | relax | `00_input/POSCAR` |
| HSE06構造緩和 | `02_hse_relax/` | relax | `01_pbe_relax/CONTCAR` |
| HSE06 DOS | `03_hse_dos/` | static | `02_hse_relax/CONTCAR` |

各ステージでは、`00_input/` 内の `INCAR.<stage>` が `INCAR` に、
`KPOINTS.<stage>` が `KPOINTS` にコピーされます。ユーザーが用意した
`POTCAR` は3段階すべてで共通に使われます。VASPは各ステージディレクトリ内で
`VASP_CMD` により起動され、標準出力は `vasp.out`、標準エラーは `vasp.err`
に保存されます。

基準とするmodule環境は、CPU版 VASP 6.4.3 では以下です。

```bash
module load intel
module load impi
module load vasp
```

GPU版 VASP-GPU 6.4.3 では以下です。

```bash
module load nvidia
module load nvompi
module load vasp-gpu
```

`VASP_CMD` には、読み込んだmoduleが提供する実行コマンドを設定します。たとえば
CPU実行では `mpirun -np 16 vasp_std` のように設定します。環境によって実行
ファイル名が異なる場合は、`vasp_std` の部分を置き換えてください。

## 完了・収束判定

`scripts/check_vasp_done.sh` は、プロセスの終了コードだけではなく `OUTCAR` の
内容を見て判定します。VASPはイオン緩和が未収束でもexit code 0で終了する場合が
あるため、このパイプラインでは安全側の文字列判定を使います。

全モード共通の完了条件:

- `OUTCAR` が存在し、空でない
- `OUTCAR` に `General timing and accounting informations for this job` がある
- `OUTCAR` に `Elapsed time` がある

構造緩和モードで追加される条件:

- `OUTCAR` に `reached required accuracy` がある
- `CONTCAR` が存在し、空でない

終了コード:

| Code | 意味 | パイプラインの動作 |
|---|---|---|
| 0 | 完了。relaxでは収束も確認済み | 次へ進む |
| 1 | 未完了。タイミングフッタがない | 停止 |
| 2 | 終了したが未収束。例: `NSW`を使い切った | 停止 |
| 3 | 必要ファイルの欠損や空ファイル | 停止 |

VASPプロセス自体が非ゼロで終了した場合も、その時点で停止します。

## CONTCARからPOSCARへの引き継ぎ

`scripts/promote_contcar.sh` は、段階間の構造引き継ぎルールを強制します。

- コピー元の `CONTCAR` が存在し、空でなく、8行以上あることを確認する
- コピー元 `CONTCAR` を次段階の `POSCAR` にコピーする
- `POSCAR.provenance.txt` にコピー元、時刻、SHA-256チェックサムを記録する
- 次段階の `POSCAR` は必ず前段階の `CONTCAR` から作る

手動で引き継ぎ後の `POSCAR` を差し替えると、このワークフローの再現性の前提が
崩れます。

## DOS段階でのWAVECAR再利用ルール

`REUSE_WAVECAR_FOR_DOS="auto"` の場合:

1. HSE06緩和段階とDOS段階の `KPOINTS` を比較する。1行目のコメントは無視し、
   空白は正規化する
2. 完全一致し、かつ `02_hse_relax/WAVECAR` が空でなければ、
   `03_hse_dos/WAVECAR` にリンクし、DOS段階の `INCAR` を
   `ISTART = 1`、`ICHARG = 0` にする
3. それ以外では `WAVECAR` を使わず、`ISTART = 0`、`ICHARG = 2` で開始する

互換性のない `WAVECAR` を再利用すると計算結果を壊す可能性があるため、判断に
迷う場合は再利用しない側に倒します。完全に再利用を無効化したい場合は
`REUSE_WAVECAR_FOR_DOS="never"` を設定します。

## 途中再開の動作

- 既存ステージの `OUTCAR` が判定を通過する場合、そのステージは `SKIPPED` として
  スキップされる
- 既存ステージの `OUTCAR` が判定に失敗する場合、その場で停止する
- 失敗した計算は自動リトライしない。原因を確認し、失敗ステージのディレクトリを
  削除してから再実行する

この設計により、物理的・数値的な失敗を自動処理で隠さず、人間が確認できる形に
しています。

## 状態ログ

`pipeline_status.tsv` は追記型TSVです。

```text
timestamp / stage / state / detail
```

状態は `PREPARED`、`RUNNING`、`DONE`、`FAILED`、`SKIPPED` です。上書きしないため、
計算履歴がそのまま残ります。

## トラブルシューティング

| 症状 | よくある原因 | 対処 |
|---|---|---|
| `rc=2` で停止 | 構造緩和が未収束、`NSW`不足、初期構造が悪い、`EDIFFG`が厳しい | `OSZICAR`を確認し、入力を調整し、失敗ステージを削除して再実行 |
| `rc=1` で停止 | ジョブ中断、時間切れ、ノード障害 | `vasp.err` やスケジューラログを確認 |
| VASPが非ゼロ終了 | MPI、メモリ、ライブラリ、`POTCAR`、`POSCAR` の問題 | `vasp.err` を確認し、`preflight_check.sh` を再実行 |
| preflightで元素順不一致 | `POTCAR` の連結順が間違っている | `POTCAR.spec` に従って `POTCAR` を作り直す |
| HSE06が非常に遅い | hybrid functional計算は重い | 検証済みの軽いk-meshや `KPAR` / `NCORE` を検討 |

## ジョブスケジューラ環境

このパイプラインは、ワークステーション上でVASPを同期実行する設計です。SLURMや
PBSなどのクラスタで使う場合は、必要な資源を確保した1つのジョブの中で
パイプライン全体を実行するのが最も単純です。

```bash
# SLURMジョブスクリプト内の例:
module load intel
module load impi
module load vasp
VASP_CMD="srun vasp_std" bash scripts/run_pbe_hse_dos_pipeline.sh my_case
```

各ステージを別々のスケジューラジョブとして非同期投入する運用は、この
リポジトリの範囲外です。
