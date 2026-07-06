# VASPFlowForge

<p align="center">
  <img src="assets/vaspflowforge-thumbnail.png" alt="PBE 構造緩和、HSE06 構造緩和、HSE06 DOS の流れを示す VASPFlowForge サムネイル">
</p>

<p align="right">
  <a href="README.md">English</a> |
  <strong>日本語</strong>
</p>

**一括実行パイプライン: PBE 構造緩和 -> HSE06 構造緩和 -> HSE06 DOS。**


VASPFlowForge には `POTCAR` を含めません。ユーザーは各自のVASPライセンス環境で
擬ポテンシャルを用意してください。

## 目的

VASP の以下の3段チェーンを、1回のスクリプト実行で自動的に流すための
公開用プログラムセットです。研究グループ内で運用実績のある
`PBE relax -> HSE06 relax -> HSE06 DOS` 自動化ワークフローの考え方
を、特定の計算機環境に依存しない形に一般化しています。

1. PBEで構造緩和する
2. `01_pbe_relax/CONTCAR` を `02_hse_relax/POSCAR` にコピーする
3. HSE06で構造緩和する
4. `02_hse_relax/CONTCAR` を `03_hse_dos/POSCAR` にコピーする
5. HSE06で静的DOS計算を行う
6. `OUTCAR` の完了・収束判定に失敗したら安全側に停止する

```text
00_input/           ユーザーが用意する入力一式(POSCAR / POTCAR / INCAR.* / KPOINTS.*)
   |
   v
01_pbe_relax        PBE 構造緩和
   |  OUTCAR 判定: 正常終了 + reached required accuracy + CONTCAR 非空
   |  CONTCAR を次段の POSCAR にコピー
   v
02_hse_relax        HSE06 構造緩和
   |  OUTCAR 判定: 同上
   |  CONTCAR を次段の POSCAR にコピー
   v
03_hse_dos          HSE06 DOS 静的計算
      OUTCAR 判定: タイミングフッタ + Elapsed time
```

判定に失敗した段階でパイプラインは停止し、後段には触れません。再実行すると、
判定を通過済みの段階は自動スキップされ、途中から再開できます。

## 既存ツールとの違いと公開意義

VASPの自動化や後処理には、すでに優れた公開ツールがあります。たとえば
`atomate2`、`custodian`、`AiiDA-VASP`、`ASE`、`pyiron` などは、材料計算の
ワークフロー化、エラー処理、HPC運用、データ管理を強力に支援します。また
`sumo`、`PyProcar`、`VASPKIT` などは、電子状態解析やDOS・バンド構造の
後処理で広く使われています。

このリポジトリは、それらの大型フレームワークや解析ツールを置き換えるものでは
ありません。公開意義は、もっと小さく、実務に近いところにあります。

| 観点 | 既存の大型ツールで強い部分 | このリポジトリの狙い |
|---|---|---|
| 導入の重さ | Python環境、データベース、ワークフローエンジン、HPC連携まで含めて本格的に扱える | bash中心で、Linuxワークステーション上ですぐ読めて動かせる |
| 対象範囲 | 多種類の物性計算、大量材料、高スループット、複雑な再実行制御 | `PBE relax -> HSE06 relax -> HSE06 DOS` の1本道に絞る |
| 透明性 | 抽象化により強力だが、初心者には内部の段階遷移が見えにくい場合がある | 各段階のディレクトリ、`OUTCAR` 判定、`CONTCAR -> POSCAR` を明示する |
| 失敗時の扱い | 自動補正・自動再投入まで含められる | 失敗した段階で止め、人間が原因を確認してから再開する |
| 公開テンプレート性 | 研究室や計算基盤に合わせて設計することが多い | `POTCAR` を含めない、安全にGitHub公開できる最小構成を示す |

つまり、このツールのオリジナリティは「新しいVASP理論や巨大なワークフロー基盤」
ではなく、実際の研究現場でよく行うHSE06計算手順を、**1本の読めるbash
パイプラインとして、公開可能な形に整理したこと**にあります。

特に、次のような人にとって価値があります。

- 初めてHSE06 DOS計算までの段階実行を自動化したい人
- PBE緩和後の構造をHSE06緩和へ、さらにDOSへ安全に引き継ぎたい人
- 大型ワークフロー基盤を導入する前に、計算の流れを手元で理解したい人
- `POTCAR` を公開しない形で、VASP入力・実行補助スクリプトだけをGitHubに
  置きたい人
- 研究室内の手作業手順を、再利用可能なテンプレートとして整理したい人

このリポジトリは、最終的な大規模運用では `atomate2`、`custodian`、
`AiiDA-VASP`、`ASE`、`pyiron` などへ発展していく前段階の、軽量な
スターターキットとして位置づけています。

## 必要環境

- Linuxワークステーション(bash + coreutils)
- HSE06が使えるライセンス済みVASP。基準とするmodule環境は以下です。
  - CPU版: VASP 6.4.3。`module load intel; module load impi; module load vasp`
  - GPU版: VASP-GPU 6.4.3。`module load nvidia; module load nvompi; module load vasp-gpu`
- 各自のVASPライセンスに付属するPAW擬ポテンシャルライブラリ

VASP本体と `POTCAR` はこのリポジトリに含まれません。方針は
[docs/potcar_policy_ja.md](docs/potcar_policy_ja.md) にまとめています。

## リポジトリ構成

```text
scripts/
  run_pbe_hse_dos_pipeline.sh   3段パイプラインのメインスクリプト
  preflight_check.sh            実行前の入力検証
  check_vasp_done.sh            OUTCAR 完了・収束判定
  promote_contcar.sh            CONTCAR から POSCAR への引き継ぎ
templates/
  INCAR.01_pbe_relax / INCAR.02_hse_relax / INCAR.03_hse_dos
  KPOINTS.01_pbe_relax / KPOINTS.02_hse_relax / KPOINTS.03_hse_dos
  pipeline.conf.example
examples/STO/                   SrTiO3 サンプルケース(POTCARなし)
docs/                           ワークフロー、POTCAR方針、公開前チェック
tests/                          VASP不要のテスト
```

## 使い方

1. サンプルケースをコピーします。

   ```bash
   cp -r examples/STO my_case
   cd my_case
   ```
2. `00_input/` に入力を用意します。


   | ファイル                    | 内容                                              |
   | --------------------------- | ------------------------------------------------- |
   | `POSCAR`                    | 初期構造                                          |
   | `POTCAR`                    | 各自のライセンス済みPAWライブラリから連結したもの |
   | `POTCAR.spec`               | POTCAR連結順の公開可能な仕様                      |
   | `INCAR.01_pbe_relax` など   | 各段階のINCAR                                     |
   | `KPOINTS.01_pbe_relax` など | 各段階のKPOINTS                                   |
3. `pipeline.conf` にVASPのmodule環境と起動コマンドを設定します。

   CPU版の例:

   ```bash
   module load intel
   module load impi
   module load vasp
   VASP_CMD="mpirun -np 16 vasp_std"
   ```

   GPU版の例:

   ```bash
   module load nvidia
   module load nvompi
   module load vasp-gpu
   VASP_CMD="mpirun -np 4 vasp_std"
   ```

   moduleが公開する実行ファイル名が異なる場合は、`vasp_std` の部分を置き換えて
   ください。
4. dry-runで確認してから実行します。

   ```bash
   bash ../scripts/run_pbe_hse_dos_pipeline.sh --dry-run .
   bash ../scripts/run_pbe_hse_dos_pipeline.sh .
   ```

長時間計算では `tmux`、`screen`、または `nohup ... &` の利用を推奨します。

## 実際のVASP計算を流す手順

テストはVASP本体を動かしません。実計算を流す場合は、実際のVASP入力と、
ローカルで作成した `POTCAR` を含むケースディレクトリから始めます。

リポジトリルートで以下を実行します。

```bash
cp -r examples/STO my_case
cd my_case
```

各自のライセンス済みPAWライブラリから `00_input/POTCAR` を作成します。
STOサンプルでは、`00_input/POTCAR.spec` に従い `Sr_sv`、`Ti`、`O` の順で
連結します。

```bash
VASP_PP=/path/to/your/potpaw_PBE.54
cat "$VASP_PP/Sr_sv/POTCAR" "$VASP_PP/Ti/POTCAR" "$VASP_PP/O/POTCAR" > 00_input/POTCAR
```

`pipeline.conf` でCPU版またはGPU版のmodule環境を選び、`VASP_CMD` を設定します。

CPU版の例:

```bash
module load intel
module load impi
module load vasp
VASP_CMD="mpirun -np 16 vasp_std"
```

GPU版の例:

```bash
module load nvidia
module load nvompi
module load vasp-gpu
VASP_CMD="mpirun -np 4 vasp_std"
```

まずdry-runを実行します。入力を検証し、ステージディレクトリを作らずに
3段階の実行計画を表示します。

```bash
bash ../scripts/run_pbe_hse_dos_pipeline.sh --dry-run .
```

問題がなければ、本実行します。

```bash
bash ../scripts/run_pbe_hse_dos_pipeline.sh .
```

成功すると以下が作られます。

```text
01_pbe_relax/
02_hse_relax/
03_hse_dos/
pipeline_status.tsv
```

パイプラインは、現在のステージが判定を通過した場合だけ次へ進みます。停止した場合は、
停止したステージを確認し、入力や実行環境の問題を直したうえで、その失敗ステージの
ディレクトリを削除して同じコマンドを再実行します。

## STOサンプル

同梱している `examples/STO/` は、立方晶SrTiO3の5原子セル
(`a = 3.899 Angstrom`)で、PBE構造緩和 -> HSE06構造緩和 -> HSE06 DOSを
一括実行するサンプルです。

準備は上の実計算手順と同じです。

1. `00_input/POTCAR.spec` に従って `00_input/POTCAR` を自作する
2. CPU版またはGPU版のVASP 6.4.3 moduleを読み込み、`pipeline.conf` の
   `VASP_CMD` を設定する
3. dry-run後に本実行する

リポジトリルートから、`POTCAR` と `VASP_CMD` を用意したあと、以下で実行できます。

```bash
cd examples/STO
bash ../../scripts/run_pbe_hse_dos_pipeline.sh --dry-run .
bash ../../scripts/run_pbe_hse_dos_pipeline.sh .
```

初期設定のk点メッシュと `ENCUT = 520` はスターター設定です。本番利用に対して
収束済みであることは保証していません。実計算前に、入力ファイル内の
`CONVERGENCE_REQUIRED` と `USER_CHECK_REQUIRED` を確認してください。

このサンプルでは、ステージ02と03の `KPOINTS` が異なるため、DOS段階では
`WAVECAR` を再利用しません。安全側として `ISTART = 0`、`ICHARG = 2` で
最初から計算します。5原子セルでもHSE06は時間がかかるため、まず小さな計算資源で
PBE段階が通ることを確認するのがおすすめです。

## 失敗時の確認

パイプラインが停止したら、停止した段階のディレクトリで以下を確認します。


| ファイル              | 確認内容                                       |
| --------------------- | ---------------------------------------------- |
| `vasp.err`            | MPI、メモリ、ライブラリ、実行時エラー          |
| `vasp.out`            | VASP標準出力、警告、対称性エラーなど           |
| `OSZICAR`             | 電子・イオン反復の進み方                       |
| `OUTCAR`              | `reached required accuracy` とタイミングフッタ |
| `pipeline_status.tsv` | どの段階が失敗したか                           |

原因を直したら、失敗した段階のディレクトリを削除して再実行します。

```bash
rm -rf 02_hse_relax
bash ../scripts/run_pbe_hse_dos_pipeline.sh .
```

## テスト

VASPなしでテストできます。

```bash
bash tests/run_tests.sh
```

fake `OUTCAR`、fake `CONTCAR`、fake VASP実行体を使って、完了判定、
`CONTCAR` 引き継ぎ、失敗時停止、途中再開、DOS段階の `WAVECAR` 再利用切替を
検証します。

## ライセンス

MIT License。詳細は [LICENSE](LICENSE) を参照してください。
