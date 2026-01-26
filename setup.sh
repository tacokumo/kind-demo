function setup_cluster() {
    echo "Setting up local Kubernetes cluster with Helm charts..."

    # Check if cluster already exists
    if kind get clusters | grep -q "^kind$"; then
        echo "Kind cluster 'kind' already exists, skipping creation..."
    else
        kind create cluster --config kind-config.yaml
    fi

    kubectl cluster-info --context kind-kind
}

function add_hosts_entries() {
    echo "Adding entries to /etc/hosts..."
    cat hosts-addition.txt | sudo tee -a /etc/hosts
}

function create_admindb_secret() {
    echo "Creating admin database credentials secret..."
    # Set default password if not provided via environment variable
    ADMIN_DB_PASSWORD=${ADMIN_DB_PASSWORD:-"password"}

    # Check if secret already exists
    if kubectl get secret tacokumo-admin-db-credentials -n tacokumo-admin >/dev/null 2>&1; then
        echo "Admin database secret 'tacokumo-admin-db-credentials' already exists, skipping creation..."
    else
        kubectl create secret generic tacokumo-admin-db-credentials \
            --from-literal=password="${ADMIN_DB_PASSWORD}" \
            --namespace=tacokumo-admin
        echo "Admin database secret 'tacokumo-admin-db-credentials' created successfully"
    fi
}

function create_valkey_secret() {
    echo "Creating Valkey credentials secret..."

    # Check if secret already exists
    if kubectl get secret tacokumo-admin-valkey-credentials -n tacokumo-admin >/dev/null 2>&1; then
        echo "Valkey credentials secret 'tacokumo-admin-valkey-credentials' already exists, skipping creation..."
    else
        kubectl create secret generic tacokumo-admin-valkey-credentials \
            --from-literal=password="" \
            --namespace=tacokumo-admin
        echo "Valkey credentials secret 'tacokumo-admin-valkey-credentials' created successfully"
    fi
}

function create_github_oauth_secret() {
    echo "Creating GitHub OAuth credentials secret..."

    # Check if required GitHub OAuth environment variables are set
    if [[ -z "${GITHUB_CLIENT_ID}" || -z "${GITHUB_CLIENT_SECRET}" ]]; then
        echo "Error: GITHUB_CLIENT_ID and GITHUB_CLIENT_SECRET environment variables must be set"
        echo "Please set these variables before running the script:"
        echo "  export GITHUB_CLIENT_ID=your-client-id"
        echo "  export GITHUB_CLIENT_SECRET=your-client-secret"
        exit 1
    fi

    # Check if secret already exists
    if kubectl get secret tacokumo-admin-github-oauth -n tacokumo-admin >/dev/null 2>&1; then
        echo "GitHub OAuth secret 'tacokumo-admin-github-oauth' already exists, skipping creation..."
    else
        kubectl create secret generic tacokumo-admin-github-oauth \
            --from-literal=clientId="${GITHUB_CLIENT_ID}" \
            --from-literal=clientSecret="${GITHUB_CLIENT_SECRET}" \
            --namespace=tacokumo-admin
        echo "GitHub OAuth secret 'tacokumo-admin-github-oauth' created successfully"
    fi
}

function setup_admin_db() {
    # Check if namespace already exists
    if kubectl get ns tacokumo-admin >/dev/null 2>&1; then
        echo "Namespace 'tacokumo-admin' already exists, skipping creation..."
    else
        kubectl create ns tacokumo-admin
    fi

    kustomize build manifests/ | kubectl apply -f -
    create_admindb_secret
    create_valkey_secret
}

function clone_admin() {
    echo "Cloning admin repository..."

    # Create tmp directory if it doesn't exist
    mkdir -p tmp

    # Remove existing admin directory if it exists
    if [ -d "tmp/admin" ]; then
        echo "Removing existing admindirectory..."
        rm -rf tmp/admin
    fi

    # Clone the repository
    git clone https://github.com/tacokumo/admin tmp/admin

    echo "Admin repository cloned successfully to tmp/admin"
}

function migrate_admin_db() {
    echo "Running database migration for admin using Kubernetes Job..."

    # Check if tmp/admini directory exists
    if [ ! -d "tmp/admin" ]; then
        echo "Error: tmp/admin directory not found. Please run clone_admin first."
        exit 1
    fi

    # Check if schema file exists
    if [ ! -f "tmp/admin/sql/schema.sql" ]; then
        echo "Error: Schema file not found at tmp/admin/sql/schema.sql"
        exit 1
    fi

    # Wait for PostgreSQL pod to be ready
    echo "Waiting for PostgreSQL pod to be ready..."
    kubectl wait --for=condition=ready pod -l app=postgresql -n tacokumo-admin --timeout=300s

    # Create ConfigMap from schema file
    echo "Creating ConfigMap with database schema..."
    kubectl create configmap admin-db-schema \
        --from-file=schema.sql=tmp/admin/sql/schema.sql \
        -n tacokumo-admin \
        --dry-run=client -o yaml | kubectl apply -f -

    # Clean up any existing migration job
    echo "Cleaning up any existing migration job..."
    kubectl delete job admin-db-migration -n tacokumo-admin --ignore-not-found=true

    # Wait for job deletion to complete
    kubectl wait --for=delete job/admin-db-migration -n tacokumo-admin --timeout=30s 2>/dev/null || true

    # Apply the migration job
    echo "Starting database migration job..."
    kubectl apply -f manifests/migration-job.yaml

    # Wait for job to complete
    echo "Waiting for migration job to complete..."
    if kubectl wait --for=condition=complete job/admin-db-migration -n tacokumo-admin --timeout=600s; then
        echo "Database migration completed successfully!"

        # Show job logs for confirmation
        echo "Migration job logs:"
        kubectl logs -l job-name=admin-db-migration -n tacokumo-admin --tail=20

        # Clean up resources
        echo "Cleaning up migration resources..."
        kubectl delete configmap admin-db-schema -n tacokumo-admin --ignore-not-found=true

        return 0
    else
        echo "Migration job failed or timed out!"

        # Show job status and logs for debugging
        echo "Job status:"
        kubectl get job admin-db-migration -n tacokumo-admin -o wide

        echo "Job pods:"
        kubectl get pods -l job-name=admin-db-migration -n tacokumo-admin

        echo "Migration job logs (last 50 lines):"
        kubectl logs -l job-name=admin-db-migration -n tacokumo-admin --tail=50

        # Don't clean up on failure for debugging
        echo "Leaving job and ConfigMap for debugging. Clean up manually with:"
        echo "kubectl delete job admin-db-migration -n tacokumo-admin"
        echo "kubectl delete configmap admin-db-schema -n tacokumo-admin"

        exit 1
    fi
}

function apply_helmfile() {
    echo "Applying Helm charts using Helmfile..."

    # Set defaults for optional environment variables
    GITHUB_OAUTH_CALLBACK_URL=${GITHUB_OAUTH_CALLBACK_URL:-"http://localhost:8080/v1alpha1/auth/callback"}
    GITHUB_OAUTH_ALLOWED_ORGS=${GITHUB_OAUTH_ALLOWED_ORGS:-""}

    helmfile sync -f helmfile.yaml.gotmpl \
        --state-values-set githubOAuthCallbackUrl="${GITHUB_OAUTH_CALLBACK_URL}" \
        --state-values-set githubOAuthAllowedOrgs="${GITHUB_OAUTH_ALLOWED_ORGS}"
}

setup_cluster
# add_hosts_entries
setup_admin_db
clone_admin
migrate_admin_db
create_github_oauth_secret
apply_helmfile
