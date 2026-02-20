#!/bin/bash

# =============================================================================
# Kubernetes Kind Cluster Setup Script with Safety Checks
# =============================================================================

# 色付き出力用の関数
print_info() { echo -e "\033[0;36m[INFO]\033[0m $1"; }
print_warn() { echo -e "\033[0;33m[WARN]\033[0m $1"; }
print_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }
print_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }

# エラー発生時の処理
handle_error() {
    print_error "スクリプトの実行中にエラーが発生しました（行: $1）"
    exit 1
}

# エラートラップを設定
trap 'handle_error $LINENO' ERR

# =============================================================================
# 安全性チェック
# =============================================================================

print_info "=== setup.sh 安全性チェック開始 ==="

# kubectl コマンドの可用性確認
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl コマンドが見つかりません"
    print_error "kubectlをインストールしてから再実行してください"
    exit 1
fi

# kind コマンドの可用性確認
if ! command -v kind &> /dev/null; then
    print_error "kind コマンドが見つかりません"
    print_error "kindをインストールしてから再実行してください"
    exit 1
fi

# helmfile コマンドの可用性確認
if ! command -v helmfile &> /dev/null; then
    print_error "helmfile コマンドが見つかりません"
    print_error "helmfileをインストールしてから再実行してください"
    exit 1
fi

# 現在のkubectlコンテキスト確認
current_context=$(kubectl config current-context 2>/dev/null || echo "none")

# kindクラスタが存在するかチェック
kind_exists=false
if kind get clusters 2>/dev/null | grep -q "^kind$"; then
    kind_exists=true
fi

# コンテキストがkind-kindでない場合の処理
if [ "$current_context" != "kind-kind" ]; then
    if [ "$kind_exists" = true ]; then
        print_warn "現在のコンテキストがkindクラスタではありません"
        print_warn "現在のコンテキスト: $current_context"
        print_warn "期待されるコンテキスト: kind-kind"
        print_info "kubectl config use-context kind-kind を実行してコンテキストを切り替えます"
        kubectl config use-context kind-kind
        current_context="kind-kind"
    else
        print_info "kindクラスタが存在しないため、新しく作成します"
    fi
fi

print_success "安全性チェック完了"

# =============================================================================
# 実行前確認プロンプト
# =============================================================================

echo ""
print_info "=== setup.sh実行確認 ==="
echo "現在のkubernetesコンテキスト: $current_context"
echo ""
echo "以下の操作を実行します："
echo "  - Kindクラスタの作成/確認"
echo "  - 名前空間の作成 (sample-project, envoy-gateway-system, portal-proxy)"
echo "  - Helmfileによるアプリケーションのデプロイ"
echo "  - Gateway APIリソースの適用"
echo "  - /etc/hostsの設定確認"
echo ""
echo "⚠️  この操作は現在のkubernetes環境に変更を加えます"
echo ""

while true; do
    read -p "続行しますか？ (y/N): " -n 1 -r
    echo
    case $REPLY in
        [Yy]* )
            print_info "セットアップを開始します..."
            break
            ;;
        [Nn]* | "" )
            print_info "セットアップをキャンセルしました"
            exit 0
            ;;
        * )
            print_warn "y (はい) または n (いいえ) で回答してください"
            ;;
    esac
done

# =============================================================================
# セットアップ処理開始
# =============================================================================

print_info "=== Kindクラスタのセットアップ開始 ==="

# kindクラスタが既に存在するかチェック
if kind get clusters 2>/dev/null | grep -q "^kind$"; then
    print_info "Kind cluster 'kind' は既に存在します。作成をスキップします。"
else
    print_info "Kindクラスタを作成しています..."
    if ! kind create cluster --config kind-config.yaml; then
        print_error "Kindクラスタの作成に失敗しました"
        exit 1
    fi
    print_success "Kindクラスタが作成されました"
fi

print_info "クラスタ接続を確認しています..."
if ! kubectl cluster-info --context kind-kind; then
    print_error "Kindクラスタへの接続に失敗しました"
    exit 1
fi
print_success "クラスタ接続を確認しました"

print_info "=== 名前空間の作成 ==="
# 名前空間を作成（既存の場合はスキップ）
print_info "sample-project名前空間を作成しています..."
kubectl create ns sample-project --dry-run=client -o yaml | kubectl apply -f -

print_info "envoy-gateway-system名前空間を作成しています..."
kubectl create ns envoy-gateway-system --dry-run=client -o yaml | kubectl apply -f -

print_info "portal-proxy名前空間を作成しています..."
kubectl create ns portal-proxy --dry-run=client -o yaml | kubectl apply -f -

print_success "名前空間の作成が完了しました"

print_info "=== Helmfileによるアプリケーションのデプロイ ==="
if ! helmfile sync -f helmfile.yaml; then
    print_error "Helmfileのデプロイに失敗しました"
    exit 1
fi
print_success "Helmfileのデプロイが完了しました"

print_info "=== Envoy Gatewayの起動待機 ==="
print_info "Envoy Gatewayが起動するまで待機しています（最大5分）..."
if ! kubectl wait --for=condition=available --timeout=300s deployment/envoy-gateway -n envoy-gateway-system; then
    print_error "Envoy Gatewayの起動がタイムアウトしました"
    print_error "kubectl get pods -n envoy-gateway-system で状態を確認してください"
    exit 1
fi
print_success "Envoy Gatewayが起動しました"

print_info "=== Gateway APIリソースの適用 ==="
if [ ! -f "gateway/gateway.yaml" ]; then
    print_error "gateway/gateway.yaml ファイルが見つかりません"
    exit 1
fi

if ! kubectl apply -f gateway/gateway.yaml; then
    print_error "Gateway APIリソースの適用に失敗しました"
    exit 1
fi
print_success "Gateway APIリソースが適用されました"

print_info "=== portal-proxyの起動待機 ==="
print_info "portal-proxyが起動するまで待機しています（最大5分）..."
if ! kubectl wait --for=condition=available --timeout=300s deployment/portal-proxy -n portal-proxy; then
    print_error "portal-proxyの起動がタイムアウトしました"
    print_error "kubectl get pods -n portal-proxy で状態を確認してください"
    exit 1
fi
print_success "portal-proxyが起動しました"

print_info "=== /etc/hosts設定確認 ==="
print_info "/etc/hostsの設定を確認しています..."

missing_hosts=()
required_hosts=("proxy.localhost" "portal.localhost" "nginx.localhost")

for host in "${required_hosts[@]}"; do
    if ! grep -q "$host" /etc/hosts 2>/dev/null; then
        missing_hosts+=("$host")
    fi
done

if [ ${#missing_hosts[@]} -gt 0 ]; then
    print_warn "以下のホスト名が /etc/hosts に見つかりません:"
    for host in "${missing_hosts[@]}"; do
        echo "  - $host"
    done
    echo ""
    print_warn "/etc/hostsに以下の行を追加してください（sudoが必要）:"
    for host in "${missing_hosts[@]}"; do
        echo "127.0.0.1 $host"
    done
    echo ""
    print_info "実行コマンド例:"
    for host in "${missing_hosts[@]}"; do
        echo "sudo sh -c 'echo \"127.0.0.1 $host\" >> /etc/hosts'"
    done
else
    print_success "必要なホスト名が /etc/hosts に設定されています"
fi

# =============================================================================
# セットアップ完了
# =============================================================================

echo ""
print_success "=== セットアップが完了しました！ ==="
echo ""
print_info "以下のコマンドでアプリケーションにアクセスできます:"
echo ""
echo "  Portal (ヘルスチェック):"
echo "    curl -H \"Host: portal.localhost\" http://localhost:30080/health/readiness"
echo ""
echo "  Nginx アプリケーション:"
echo "    curl -H \"Host: nginx.localhost\" http://localhost:30080/"
echo ""
echo "  Proxy サービス:"
echo "    curl -H \"Host: proxy.localhost\" http://localhost:30080/"
echo ""

if [ ${#missing_hosts[@]} -gt 0 ]; then
    print_warn "注意: /etc/hostsの設定が完了していないため、ブラウザでのアクセスは"
    print_warn "      ホスト名設定完了後に可能になります"
fi

print_success "setup.sh の実行が正常に完了しました"
