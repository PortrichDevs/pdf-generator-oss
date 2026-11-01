# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

HTML を受け取り、headless Chromium (Selenium + CDP `Page.printToPDF`) で PDF に変換する小さな API。同じ変換ロジックを 2 つの実行形態で提供する。

- **ローカル / コンテナ**: Flask (`app.py`) — `Dockerfile`
- **本番**: AWS Lambda コンテナイメージ (`lambda_function.py`) — `Dockerfile-lambda`、API Gateway HTTP API 経由

## コマンド

```sh
# 依存導入 (Python 3.12 / Lambda イメージ・CI と同じ)
pip install -r requirements.txt -c constraints-lambda.txt

# テスト (unittest。pytest は使っていない)
python -m unittest
python -m unittest tests.LambdaHandlerTest                 # クラス単位
python -m unittest tests.AppHandlerTest.test_validation    # メソッド単位

# Flask 版をコンテナで起動
docker build -t pdf-generator .
docker run --rm -p 8000:5000 pdf-generator
curl -d '{"source":"<b>Hello World</b>"}' -H 'Content-Type: application/json' localhost:8000 > output.pdf

# Lambda 版イメージのビルド
docker build -f Dockerfile-lambda -t pdf-generator-lambda .

# インフラ (terraform/ 配下)。apply は人間の明示許可がある場合のみ
cd terraform && terraform plan -out=../var/plan/plan-$(date +%s).tfplan
```

Lint / フォーマッタの設定はリポジトリに存在しない。

## アーキテクチャ

- `core.py` が唯一のビジネスロジック。HTML を `/tmp` の一時ファイルに書き、リクエストごとに Chrome ドライバを起動 → `file://` で開く → `Page.printToPDF` → `quit()`。戻り値は **base64 文字列**。
  - `build_print_options()` はデフォルト (A4 相当の `paperWidth`/`paperHeight`、`displayHeaderFooter: False`) にクライアント指定の `print_options` を浅くマージする。キーは CDP `Page.printToPDF` のパラメータ名そのまま。
  - Chrome 起動フラグ (`--single-process`, `--no-sandbox`, `--disable-dev-shm-usage` 等) は Lambda 環境で動かすための前提。安易に外さないこと。
- `app.py` と `lambda_function.py` は入力検証 (`source` 必須、なければ 400) と `print_options` の扱いが**重複実装**されている。片方を変えたらもう片方も揃える。
  - Flask 版は base64 をデコードして生の PDF バイトを返す (201)。
  - Lambda 版は base64 のまま `isBase64Encoded: True` で返し、API Gateway がバイナリに戻す (201, `application/pdf`)。
  - README の「Response is Base64-encoded」はクライアントから見た挙動とは異なるので注意。
- `tests.py` は `core.webdriver` / 各ハンドラの `generate_pdf` を `unittest.mock.patch` で差し替えており、Chrome なしで実行できる。
- `Dockerfile-lambda` は、本番稼働イメージ (commit `c4fcc6f`、Amazon Linux 2 + Chromium 117 + IPA フォント) の**描画結果を Amazon Linux 2023 で再現する**ことを目的にしている (#9)。
  - ベースイメージ (digest)、Chrome for Testing のバージョンと checksum、Python パッケージ (`constraints-lambda.txt`) をすべて固定している。
  - フォントは本番と同じ IPA 4 種 + DejaVu Sans だけを使う。依存で入る他のフォント (Noto Sans など) は `docker/fonts-local.conf` で無効にしている。他のフォントが入ると `sans-serif` などの総称フォントの解決先が変わり、PDF の見た目が変わる。
  - `docker/verify-lambda-image.sh` がビルド時に、ブラウザのバージョン・共有ライブラリ・フォント構成・総称フォントの解決先を検証し、本番と違えばビルドを失敗させる。パッケージやフォントを変更するときは、このスクリプトの期待値も見直すこと。
  - selenium 4.4.3 はブラウザを自動で探すので、Chrome for Testing を `/usr/bin/chromium-browser` に symlink している (`core.py` は本番と同一に保つ)。
- Flask 版の `Dockerfile` には日本語フォントが入っておらず、Lambda 版とは構成が異なる (#8)。

## デプロイ / インフラ

- `.github/workflows/test.yml`: 全 push で `python -m unittest` と、Lambda イメージのビルド (push はしない。ビルド時の検証もここで走る)。
- `.github/workflows/ecr-lambda.yml`: `main` への push で `Dockerfile-lambda` をビルドし ECR (`ap-northeast-1`, リポジトリ `pdf-generator`) に `latest` と commit SHA タグで push する。
- `terraform/`: ECR / Lambda (timeout 60s, memory 1536MB) / API Gateway HTTP API (stage `v1`, `$default` ルート) をモジュール分割で管理。Terraform state はローカル (backend 設定なし)。
  - Lambda の `image_uri` は `lifecycle.ignore_changes` で Terraform 管理外とし、CI 側で更新する方針。ただし現状の `ecr-lambda.yml` はイメージ push までで、Lambda 関数の更新ステップはまだ無い。

## ADR を提案する基準

このリポジトリは issue を起点に改善を回す。issue や PR の作業中に、次のどれかに当てはまる判断が出てきたら、実装を進める前に ADR を書くようユーザーに提案する。ADR を勝手に作成はしない。

- **取り消すのに手間がかかる**: データの形、外部への約束 (API のリクエスト/レスポンス形式など)、ライブラリの選択など。
- **その機能の外にも影響する**: 他の機能や他のチームの作業を縛る。
- **本気で比べて、捨てた案がある**: 捨てた理由は、後から一番知りたくなる情報なので必ず残す。
- **知らない人が「なぜこうなっている？」と言って戻しかねない**: 一見不要・不自然に見える設定など。

このリポジトリで当てはまりそうな例:
- レスポンス形式 (Flask はバイナリ、Lambda は base64 + `isBase64Encoded`) → 外部への約束
- Selenium + Chromium の採用、Chrome 起動フラグ (`--single-process` など) → ライブラリ選択 / 戻されかねない設定
- Lambda の `image_uri` を Terraform ではなく CI で更新する方針 (`ignore_changes`) → 責務の分担、戻されかねない設定

ADR は `docs/adr/NNNN-<kebab-case-title>.md` (4 桁の連番) に置き、`docs/adr/template.md` の書式 (Nygard 形式 + 却下した案) で書く。決定を覆すときは、元の ADR を書き換えずに新しい ADR を作る。元の ADR のステータスは `Superseded by NNNN` にする。

## リポジトリ構成 (fork)

このリポジトリ `PortrichDevs/pdf-generator` は `d-mato/pdf-generator` の fork。**PR は必ず fork 側に出す**。`gh` は fork だと親リポジトリを PR 先に選ぶことがあるため、`--repo` を明示する。

```sh
gh pr create --repo PortrichDevs/pdf-generator --base main ...
```

## エージェント運用ルール (`.github/copilot-instructions.md` より抜粋)

- ユーザーとの会話・説明・コメントは**日本語**。
- 対話型コマンド・ページャは使わない (`git --no-pager ...`、REPL 禁止)。
- Terraform は既定で `plan` のみ。`apply` / 削除など本番影響のある操作は「計画 → ユーザー承認 → 実行」の順で行う。
- 長い出力はファイル保存し、画面には要点のみ。ログは `./var/log/agent/`、パッチ等は `./var/artifacts/`、plan ファイルは `./var/plan/`。
- コミットメッセージは `feat:` / `fix:` / `docs:` / `refactor:` / `test:` / `chore:` (スコープ任意、例 `fix(docker): ...`)。
- `.env` は生成・編集しない。
