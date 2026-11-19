#!/usr/bin/env bash

# NOTES:
# kube = apply manifests, inspect resources for kubernetes
# a remote for the CP of the kubernetes cluster
# kind = creates the kind clusters, loads imgs, exports kubeconfig
# creates containerized servers/nodes for kubernetes to run on

set -euo pipefail # exit on command errors or unset variables, for failures in pipeline
cd "$(dirname "$0")" # standardize root

# check required cli tools
for required in git podman podman.exe podman-compose helm kind.exe kubectl.exe; do
    if ! command -v "$required" >/dev/null 2>&1; then
        printf 'Missing required command: %s\n' "$required" >&2
        exit 1
    fi
done

# get all podman instances by name
mapfile -t machines < <(
  podman.exe machine list --format '{{.Name}}' | tr -d '\r'
)

# make select option
PS3="Choose a Podman machine: "
select machine in "${machines[@]}" "Create new"; do
  [[ -n "$machine" ]] || { echo "Invalid choice"; continue; }
  break
done

# collect data for new podman instance
if [[ "$machine" == "Create new" ]]; then
    read -r -p "Machine name: " new_machine
    
    read -r -p "CPUs [4]: " cpus
    cpus=${cpus:-4}
    if [[ ! "$cpus" =~ ^[1-9][0-9]*$ ]]; then
        echo "CPUs must be a positive whole number" >&2
        exit 1
    fi

    read -r -p "Memory in MiB [6144]: " memory_mib
    memory_mib=${memory_mib:-6144}
    if [[ ! "$memory_mib" =~ ^[1-9][0-9]*$ ]]; then
        echo "Memory space must be a positive whole number" >&2
        exit 1
    fi

    read -r -p "Disk in GiB [50]: " disk_gib
    disk_gib=${disk_gib:-50}
    if [[ ! "$disk_gib" =~ ^[1-9][0-9]*$ ]]; then
        echo "Disk space must be a positive whole number" >&2
        exit 1
    fi
    
    [[ -n "$new_machine" ]] || { echo "Machine name is required" >&2; exit 1; }
    podman.exe machine init --provider wsl --rootful --cpus "$cpus" --memory "$memory_mib" --disk-size "$disk_gib" --now "$new_machine"
    
    machine=$new_machine
else
    # else, check if running
    state=$(podman.exe machine inspect --format '{{.State}}' "$machine" | tr -d '\r')
    if [[ "$state" != "running" ]]; then
        podman.exe machine start "$machine"
    fi
fi

rootful=$(podman.exe machine inspect --format '{{.Rootful}}' "$machine" | tr -d '\r')
# env files for podman wsl
if [[ "$rootful" != true ]]; then
    echo "This Kubernetes setup requires a rootful Podman machine." >&2
    exit 1
fi

# check which machine and socket name its in
socket_name=podman-root.sock
socket=""
for candidate in \
    "/mnt/wsl/podman-sockets/$machine/$socket_name" \
    "/mnt/wsl/podman-sockets/podman-$machine/$socket_name"; do
    if [[ -S "$candidate" ]]; then
        socket=$candidate
        break
    fi
done

# error check for no socket found
[[ -n "$socket" ]] || { echo "Socket not found for $machine" >&2; exit 1; }

export CONTAINER_HOST="unix://$socket"
export PODMAN_COMPOSE_PROVIDER=/usr/bin/podman-compose

podman compose build # create/update, don't start

# connect cluster to machine
cluster_name=observability-lab
connection="${machine}-root"

# WSLENV = carries settings across the WSL to Windows boundary, needed for WSL inits
# $@ passes function args into kind
# vital so it has same reference point, wrapper for kind.exe
kind_cmd() {
    KIND_EXPERIMENTAL_PROVIDER=podman \
    CONTAINER_CONNECTION="$connection" \
    WSLENV="${WSLENV:+$WSLENV:}KIND_EXPERIMENTAL_PROVIDER/w:CONTAINER_CONNECTION/w" \
        kind.exe "$@"
}

# if cluster alraedy exists
existing_clusters=$(kind_cmd get clusters | tr -d '\r')

if printf '%s\n' "$existing_clusters" | grep -Fxq "$cluster_name"; then
    echo "Using existing cluster: $cluster_name"

    podman.exe --connection "$connection" \
        start "${cluster_name}-control-plane"
else
    kind_cmd create cluster \
        --name "$cluster_name" \
        --config "$(wslpath -w "$PWD/kind-config.yaml")" \
        --wait 120s
fi

# make own .kube directory for configs
mkdir -p "$HOME/.kube"
export KUBECONFIG="$HOME/.kube/${cluster_name}.yaml"

# save connection details for this kind cluster into the config file
kind_cmd export kubeconfig \
    --name "$cluster_name" \
    --kubeconfig "$(wslpath -w "$KUBECONFIG")" # convert to window filepath

# make it so that only the owner can read write
chmod 600 "$KUBECONFIG" 

# shortcut for kubectl for chosen cluster
# makes Windows kubectl use this scripts cluster connection file
kube_cmd() {
    kubectl.exe \
        --kubeconfig "$(wslpath -w "$KUBECONFIG")" \
        --context "kind-$cluster_name" \
        "$@"
}

# check if its rdy to go
kube_cmd wait --for=condition=Ready nodes --all --timeout=120s

# push all images to the cluster
for image in \
    localhost/java-app-lab:1 \
    localhost/grafana-setup-lab:1 \
    localhost/otel-collector-setup-lab:1 \
    localhost/prometheus-setup-lab:1 \
    localhost/jaeger-setup-lab:1
do
    kind_cmd load docker-image "$image" --name "$cluster_name"
done

# INGRESS STUFF
# add contour stuff to cluster
helm repo add contour https://projectcontour.github.io/helm-charts/ \
    --force-update

helm repo update contour

# install/upgrade contour using our values to override chart defaults
helm upgrade --install contour contour/contour \
    --version 0.9.0 \
    --values contour-values.yaml \
    --namespace projectcontour \
    --create-namespace \
    --kube-context "kind-$cluster_name" \
    --wait \
    --timeout 5m

# ARGOCD STUFF
# add argocd namespace if none
kube_cmd create namespace argocd --dry-run=client -o yaml |
    kube_cmd apply -f -

# install argocd version
argocd_version=v3.6.2
kube_cmd apply --server-side \
    --namespace argocd \
    --filename "https://raw.githubusercontent.com/argoproj/argo-cd/${argocd_version}/manifests/install.yaml"

# wait for the init
kube_cmd --namespace argocd wait \
    --for=condition=Available deployment --all --timeout=300s
kube_cmd --namespace argocd rollout status \
    statefulset/argocd-application-controller --timeout=300s

# auto fill argocd application
kube_cmd apply \
    --filename "$(wslpath -w "$PWD/argocd/observability-lab.yaml")"
