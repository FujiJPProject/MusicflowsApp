# MusicflowsApp

React / Spring Boot / PostgreSQL / Floci を用いた音楽制作アプリの開発リポジトリです。

## 開発環境

標準環境は Terraform 管理の `docker-compose.yml` です。Issue #35〜#37 の独立検証環境の Project 名・Volume・State・公開ポートを保持します。旧 Shell 環境のデータは自動移行しません。

- [環境構築手順書](doc/開発環境/環境構築手順書.md)
- [動作確認手順書](doc/開発環境/動作確認手順書.md)
- [トラブルシューティング](doc/開発環境/トラブルシューティング.md)
- [削除保留一覧](doc/開発環境/削除保留一覧.md)
- [Issue #39 回帰確認・検証記録](doc/開発環境/Issue39回帰確認.md)
- [コンテナ構成](doc/コンテナ構成/Readme.md)

## クイックスタート

Docker Engine / Compose v2、Bash、Git、curl、flock が必要です。WSL/Linux のリポジトリルートで実行してください。Java、Node.js、Terraform、AWS CLI、Python はコンテナ内で利用します。

初回の空環境だけ:

```bash
bash scripts/local/setup.sh
```

既存 Terraform 環境を引き継ぐ場合は、環境構築手順書の「既存環境の引継ぎ」を先に実施してください。既存 DB のパスワードを変更しないでください。

日常開発:

```bash
bash scripts/local/start.sh all
bash scripts/local/check.sh
bash scripts/local/stop.sh
```

Frontend: http://localhost:5174/  
Backend: http://localhost:8081/api/health  
Floci: http://localhost:4567/  

診断画面: /dev/db-test、/auth-test、/jobtest（有効時のみ）。CloudFront URL は check.sh で表示されます。

## 注意事項

- `docker compose down -v`、`terraform destroy`、Volume prune、State の削除を通常の復旧手順にしない。
- Lambda と Local Worker は同時に稼働させない。切替は worker-mode.sh を使う。
- Terraform Apply は Plan を確認してから実行する。
- AWS 実機での Terraform 管理は MusicflowInfra 側。ローカルの State や資格情報を共有しない。
- [旧 Shell 環境の記録（移行前）](https://github.com/FujiJPProject/MusicflowsApp/tree/5d8ea29e00804fb6523a89aba5cbf57fd933ea25)
