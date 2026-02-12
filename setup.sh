set -eux

kind create cluster
kubectl cluster-info --context kind-kind
kubectl create ns sample-project
helmfile sync -f helmfile.yaml
