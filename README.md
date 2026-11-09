# grafana-sub-blueprint
A substitute for observability instead of AWS grafana, cost mitigation

# Required Installs - step by step process
1. Download Podman Desktop for ease of use.
2. Download WSL 2 or a Linux Environment since that is the basis for all of the commands to follow.
3. Download Grafana library.
4. Download Prometheus library.
5. TBF. So far have only configured this far.

# ALREADY DONE
- Configured Podman to work and can pull images for the specific Podman Machine.
- Created both Grafana and Prometheus containers from their respective images, together with their host ports at 3000 and 9090 respectively.
- Configured a Podman network to make Prometheus and Grafana containers communicate.
