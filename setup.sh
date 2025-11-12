function setup_cluster() {
    echo "Setting up local Kubernetes cluster with Helm charts..."
    kind create cluster --config kind-config.yaml
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

    kubectl create secret generic tacokumo-admin-db-credentials \
        --from-literal=password="${ADMIN_DB_PASSWORD}" \
        --namespace=tacokumo-admin

    echo "Admin database secret 'tacokumo-admin-db-credentials' created successfully"
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

    kubectl create secret generic tacokumo-admin-auth0-credentials \
        --from-literal=domain="${AUTH0_DOMAIN}" \
        --from-literal=clientId="${AUTH0_CLIENT_ID}" \
        --from-literal=clientSecret="${AUTH0_CLIENT_SECRET}" \
        --namespace=tacokumo-admin

    echo "Auth0 secret 'tacokumo-admin-auth0-credentials' created successfully"
}

function setup_admin_db() {
    kubectl create ns tacokumo-admin
    kustomize build manifests/ | kubectl apply -f -
    create_admindb_secret
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
create_auth0_secret
apply_helmfile
