#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

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
if [[ "$rootful" == true ]]; then
    socket_name=podman-root.sock
else
    socket_name=podman-user.sock
fi

# check which machine and socket name its in
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

podman compose up --build -d
podman compose ps
