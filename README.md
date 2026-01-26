# KIND demo

TACOKUMOクラスタをKinD上で動作させるデモ用リポジトリ。

## 前提条件

- Docker
- kind
- kubectl
- helmfile
- kustomize

## セットアップ

```bash
# GitHub OAuth の設定（必須）
export GITHUB_CLIENT_ID="your-client-id"
export GITHUB_CLIENT_SECRET="your-client-secret"

# オプション
export GITHUB_OAUTH_CALLBACK_URL="http://admin.tacokumo.local/v1alpha1/auth/callback"
export GITHUB_OAUTH_ALLOWED_ORGS="your-org"

# 実行
./setup.sh
```

## 動作確認

```bash
# Pod 確認
kubectl get pods -n tacokumo-admin

# API ヘルスチェック
kubectl port-forward svc/tacokumo-admin-api 8080:8080 -n tacokumo-admin &
curl http://localhost:8080/v1alpha1/health/readiness

# UI アクセス
kubectl port-forward svc/tacokumo-admin-ui 3000:3000 -n tacokumo-admin &
open http://localhost:3000
```

## クリーンアップ

```bash
kind delete cluster
```
