function setup_cluster() {
    echo "Setting up local Kubernetes cluster with Helm charts..."
    kind create cluster --config kind-config.yaml
    kubectl cluster-info --context kind-kind
}

function add_hosts_entries() {
    echo "Adding entries to /etc/hosts..."
    cat hosts-addition.txt | sudo tee -a /etc/hosts
}

function apply_helmfile() {
    echo "Applying Helm charts using Helmfile..."
    helmfile sync -f helmfile.yaml.gotmpl \
        --state-values-set tacokuAdminAPIAuth0Domain="${TACOKUMO_ADMIN_API_AUTH0_DOMAIN}" \
        --state-values-set tacokuAdminAPIAuth0Audience="${TACOKUMO_ADMIN_API_AUTH0_AUDIENCE}"
}

# setup_cluster
# add_hosts_entries
apply_helmfile