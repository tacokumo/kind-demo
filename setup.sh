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

function create_auth0_secret() {
    echo "Creating Auth0 credentials secret..."

    # Check if required Auth0 environment variables are set
    if [[ -z "${AUTH0_DOMAIN}" || -z "${AUTH0_CLIENT_ID}" || -z "${AUTH0_CLIENT_SECRET}" ]]; then
        echo "Error: AUTH0_DOMAIN, AUTH0_CLIENT_ID, and AUTH0_CLIENT_SECRET environment variables must be set"
        echo "Please set these variables before running the script:"
        echo "  export AUTH0_DOMAIN=your-domain.auth0.com"
        echo "  export AUTH0_CLIENT_ID=your-client-id"
        echo "  export AUTH0_CLIENT_SECRET=your-client-secret"
        exit 1
    fi

    # Check if secret already exists
    if kubectl get secret tacokumo-admin-auth0-credentials -n tacokumo-admin >/dev/null 2>&1; then
        echo "Auth0 secret 'tacokumo-admin-auth0-credentials' already exists, skipping creation..."
    else
        kubectl create secret generic tacokumo-admin-auth0-credentials \
            --from-literal=domain="${AUTH0_DOMAIN}" \
            --from-literal=clientId="${AUTH0_CLIENT_ID}" \
            --from-literal=clientSecret="${AUTH0_CLIENT_SECRET}" \
            --namespace=tacokumo-admin
        echo "Auth0 secret 'tacokumo-admin-auth0-credentials' created successfully"
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
}

function clone_admin_api() {
    echo "Cloning admin-api repository..."

    # Create tmp directory if it doesn't exist
    mkdir -p tmp

    # Remove existing admin-api directory if it exists
    if [ -d "tmp/admin-api" ]; then
        echo "Removing existing admin-api directory..."
        rm -rf tmp/admin-api
    fi

    # Clone the repository
    git clone https://github.com/tacokumo/admin-api tmp/admin-api

    echo "Admin API repository cloned successfully to tmp/admin-api"
}

function migrate_admin_db() {
    echo "Running database migration for admin API..."

    # Check if tmp/admin-api directory exists
    if [ ! -d "tmp/admin-api" ]; then
        echo "Error: tmp/admin-api directory not found. Please run clone_admin_api first."
        exit 1
    fi

    # Start port-forward in background
    echo "Setting up port-forward to PostgreSQL service..."
    kubectl port-forward -n tacokumo-admin service/postgresql 5432:5432 &
    PORT_FORWARD_PID=$!

    # Wait for port-forward to establish and database to be ready
    echo "Waiting for port-forward to establish and database to be ready..."
    sleep 10

    # Additional check: wait for port to be available
    for i in {1..30}; do
        # Try multiple methods to check if port is available
        if nc -z localhost 5432 2>/dev/null || \
           timeout 2 bash -c "</dev/tcp/localhost/5432" 2>/dev/null || \
           lsof -i :5432 >/dev/null 2>&1; then
            echo "Port-forward established successfully"
            break
        fi
        echo "Waiting for port-forward... ($i/30)"
        sleep 2
    done

    # Final check: ensure PostgreSQL pod is ready
    echo "Ensuring PostgreSQL pod is ready..."
    kubectl wait --for=condition=ready pod -l app=postgresql -n tacokumo-admin --timeout=300s

    # Run migration
    echo "Running database migration..."
    cd tmp/admin-api

    # Check if running on macOS and adjust host accordingly
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - use host.docker.internal for Docker to access host
        docker run --rm \
            -v "$(pwd)/sql/schema.sql:/schema.sql" \
            arigaio/atlas:latest schema apply \
            --url "postgres://admin_api:password@host.docker.internal:5432/tacokumo_admin_db?sslmode=disable" \
            --dev-url "postgres://postgres:password@host.docker.internal:5432/postgres?sslmode=disable" \
            --to "file:///schema.sql" --auto-approve
    else
        # Linux - use --network host
        make migrate IS_DOCKER=false HOST=localhost PORT=5432 USER=admin_api PASSWORD=password DB=tacokumo_admin_db DEV_USER=postgres DEV_PASSWORD=password DEV_DB=postgres
    fi
    MIGRATION_EXIT_CODE=$?
    cd ../..

    # Kill port-forward process
    echo "Cleaning up port-forward..."
    kill $PORT_FORWARD_PID 2>/dev/null || true

    if [ $MIGRATION_EXIT_CODE -eq 0 ]; then
        echo "Database migration completed successfully"
    else
        echo "Database migration failed with exit code $MIGRATION_EXIT_CODE"
        exit $MIGRATION_EXIT_CODE
    fi
}

function apply_helmfile() {
    echo "Applying Helm charts using Helmfile..."
    helmfile sync -f helmfile.yaml.gotmpl \
        --state-values-set tacokuAdminAPIAuth0Domain="${TACOKUMO_ADMIN_API_AUTH0_DOMAIN}" \
        --state-values-set tacokuAdminAPIAuth0Audience="${TACOKUMO_ADMIN_API_AUTH0_AUDIENCE}"
}

setup_cluster
# add_hosts_entries
setup_admin_db
clone_admin_api
migrate_admin_db
create_auth0_secret
apply_helmfile
