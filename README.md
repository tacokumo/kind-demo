# Kind Demo with Envoy Gateway

このプロジェクトは、KindクラスタでEnvoy Gateway v1.7.0とGateway APIを使用してアプリケーションにドメイン名でアクセスできるデモ環境を提供します。

## 構成

- **tacokumo-portal**: ポート1323のAPI（sample-projectネームスペース）
- **nginx-app**: nginxアプリケーション（tacokumoのApplicationカスタムリソース）
- **portal-controller-kubernetes**: カスタムコントローラ（portal-controller-systemネームスペース）
- **Envoy Gateway v1.7.0**: Gateway APIの実装（envoy-gateway-systemネームスペース）

## 前提条件

- Docker
- kubectl
- kind
- helmfile

## セットアップ

1. クラスタの作成と環境のセットアップ：

```bash
./setup.sh
```

このスクリプトは以下を実行します：
- ポートフォワーディング設定付きのkindクラスタを作成
- 必要なネームスペースを作成
- Helmfileを使用してすべてのアプリケーションとEnvoy Gatewayをデプロイ
- Gateway APIリソースを適用

## アクセス方法

セットアップ完了後、以下の方法でアプリケーションにアクセスできます：

### cURLでのアクセス

```bash
# Portal API のヘルスチェック
curl -H "Host: portal.localhost" http://localhost:30080/health/readiness

# Nginx アプリケーション
curl -H "Host: nginx.localhost" http://localhost:30080/
```

### ブラウザでのアクセス

ブラウザから以下のURLにアクセスする場合は、事前に`/etc/hosts`に以下を追加してください：

```
127.0.0.1 portal.localhost
127.0.0.1 nginx.localhost
```

その後、以下のURLにアクセスできます：
- Portal API: http://portal.localhost:30080
- Nginx App: http://nginx.localhost:30080

## アーキテクチャ

```
[Browser/curl]
    ↓ (Host: *.localhost)
[localhost:30080]
    ↓ (Kind cluster port mapping)
[Envoy Gateway Service:80]
    ↓ (Gateway API routing)
[Application Services]
    ├─ tacokumo-portal:1323 (portal.localhost)
    └─ nginx-app:80 (nginx.localhost)
```

## ファイル構成

- `kind-config.yaml`: Kindクラスタの設定（ポートマッピング含む）
- `helmfile.yaml`: HelmリリースとリポジトリのDSL
- `values/`: 各Helmチャートの設定ファイル
  - `tacokumo-portal.yaml`: Portal APIの設定
  - `portal-controller-kubernetes.yaml`: コントローラの設定
  - `envoy-gateway.yaml`: Envoy Gateway v1.7.0の設定
- `gateway/gateway.yaml`: Gateway APIリソースの定義
- `nginx-app/appconfig.yaml`: Nginx アプリケーションの設定

## トラブルシューティング

### Envoy Gatewayの状態確認

```bash
kubectl get pods -n envoy-gateway-system
kubectl get gateway -n envoy-gateway-system
kubectl get gatewayclass
```

### Gateway APIリソースの状態確認

```bash
kubectl describe gateway kind-gateway -n envoy-gateway-system
kubectl get httproute -A
```

### アプリケーションの状態確認

```bash
# Portal
kubectl get pods -n sample-project
kubectl get svc -n sample-project

# Nginx app
kubectl get application -A
```

## クリーンアップ

```bash
kind delete cluster
```

