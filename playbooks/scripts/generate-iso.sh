#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $(basename "$0") [OPTIONS]

Generate an Agent-Based Installer ISO for Single Node OpenShift with
AAP 2.7, OpenShift Virtualization, and CIS L1 hardening.

Required:
  --pull-secret PATH    Path to pull-secret.json from console.redhat.com
  --ssh-key PATH        Path to SSH public key (e.g. ~/.ssh/id_ed25519.pub)
  --hostname NAME       Node hostname (e.g. nuc01)
  --ip CIDR             Node IP with prefix (e.g. 192.168.1.100/24)
  --gateway IP          Default gateway
  --dns IP              DNS server
  --interface NAME      Network interface (e.g. eno1)
  --disk DEVICE         Root disk device (e.g. /dev/sda)
  --mac ADDRESS         MAC address of the network interface

Optional:
  --cluster-name NAME   Cluster name (default: demo)
  --base-domain DOMAIN  Base domain (default: example.com)
  --machine-network CIDR  Machine network CIDR (default: derived from --ip)
  --ocp-version VER     OCP version (default: latest from configured channel)
  --dhcp                Use DHCP instead of static IP (--gateway and --dns not required)
  --output-dir DIR      Output directory (default: current directory)
  -h, --help            Show this help

Example:
  $(basename "$0") \\
    --pull-secret ~/pull-secret.json \\
    --ssh-key ~/.ssh/id_ed25519.pub \\
    --hostname nuc01 \\
    --ip 192.168.1.100/24 --gateway 192.168.1.1 --dns 192.168.1.1 \\
    --interface eno1 --disk /dev/sda --mac aa:bb:cc:dd:ee:ff \\
    --cluster-name demo --base-domain example.com

Then write to USB:
  sudo dd if=agent.x86_64.iso of=/dev/sdX bs=4M status=progress
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT_DIR="${SCRIPT_DIR}/.."

CLUSTER_NAME="edge"
BASE_DOMAIN="internal.ames.net"
USE_DHCP=false
OUTPUT_DIR="."
OCP_VERSION=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --pull-secret)  PULL_SECRET="$2"; shift 2 ;;
    --ssh-key)      SSH_KEY="$2"; shift 2 ;;
    --hostname)     HOSTNAME_VAL="$2"; shift 2 ;;
    --ip)           NODE_IP="$2"; shift 2 ;;
    --gateway)      GATEWAY="$2"; shift 2 ;;
    --dns)          DNS="$2"; shift 2 ;;
    --interface)    INTERFACE="$2"; shift 2 ;;
    --disk)         DISK="$2"; shift 2 ;;
    --mac)          MAC="$2"; shift 2 ;;
    --cluster-name) CLUSTER_NAME="$2"; shift 2 ;;
    --base-domain)  BASE_DOMAIN="$2"; shift 2 ;;
    --machine-network) MACHINE_NETWORK="$2"; shift 2 ;;
    --ocp-version)  OCP_VERSION="$2"; shift 2 ;;
    --dhcp)         USE_DHCP=true; shift ;;
    --output-dir)   OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

missing=()
[[ -z "${PULL_SECRET:-}" ]] && missing+=(--pull-secret)
[[ -z "${SSH_KEY:-}" ]] && missing+=(--ssh-key)
[[ -z "${HOSTNAME_VAL:-}" ]] && missing+=(--hostname)
[[ -z "${NODE_IP:-}" ]] && missing+=(--ip)
[[ -z "${INTERFACE:-}" ]] && missing+=(--interface)
[[ -z "${DISK:-}" ]] && missing+=(--disk)
[[ -z "${MAC:-}" ]] && missing+=(--mac)

if [[ "$USE_DHCP" == "false" ]]; then
  [[ -z "${GATEWAY:-}" ]] && missing+=(--gateway)
  [[ -z "${DNS:-}" ]] && missing+=(--dns)
fi

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Error: missing required options: ${missing[*]}" >&2
  echo >&2
  usage >&2
  exit 1
fi

[[ -f "$PULL_SECRET" ]] || { echo "Error: pull secret not found: $PULL_SECRET" >&2; exit 1; }
[[ -f "$SSH_KEY" ]] || { echo "Error: SSH key not found: $SSH_KEY" >&2; exit 1; }

if ! command -v ansible-playbook &>/dev/null; then
  echo "Error: ansible-playbook not found. Install ansible-core." >&2
  exit 1
fi

PULL_SECRET_CONTENT="$(cat "$PULL_SECRET")"
SSH_KEY_CONTENT="$(cat "$SSH_KEY")"

EXTRA_VARS=(
  -e "sno_cluster_name=${CLUSTER_NAME}"
  -e "sno_base_domain=${BASE_DOMAIN}"
  -e "sno_hostname=${HOSTNAME_VAL}"
  -e "sno_node_ip=${NODE_IP}"
  -e "sno_interface=${INTERFACE}"
  -e "sno_disk_device=${DISK}"
  -e "sno_mac_address=${MAC}"
  -e "sno_use_dhcp=${USE_DHCP}"
  -e "sno_pull_secret=${PULL_SECRET_CONTENT}"
  -e "sno_ssh_key=${SSH_KEY_CONTENT}"
)

if [[ -n "${GATEWAY:-}" ]]; then
  EXTRA_VARS+=(-e "sno_gateway=${GATEWAY}")
fi
if [[ -n "${DNS:-}" ]]; then
  EXTRA_VARS+=(-e "sno_dns=${DNS}")
fi
if [[ -n "${MACHINE_NETWORK:-}" ]]; then
  EXTRA_VARS+=(-e "sno_machine_network=${MACHINE_NETWORK}")
fi
if [[ -n "${OCP_VERSION}" ]]; then
  EXTRA_VARS+=(-e "sno_ocp_version=${OCP_VERSION}")
fi

echo "Generating SNO installer ISO..."
echo "  Cluster:   ${CLUSTER_NAME}.${BASE_DOMAIN}"
echo "  Hostname:  ${HOSTNAME_VAL}"
echo "  IP:        ${NODE_IP}"
echo "  Interface: ${INTERFACE}"
echo "  Disk:      ${DISK}"
echo "  Network:   $(if [[ "$USE_DHCP" == "true" ]]; then echo DHCP; else echo "Static (gw=${GATEWAY}, dns=${DNS})"; fi)"
echo

ansible-playbook "${KIT_DIR}/playbooks/build_sno_installer.yml" \
  "${EXTRA_VARS[@]}" \
  "$@"
