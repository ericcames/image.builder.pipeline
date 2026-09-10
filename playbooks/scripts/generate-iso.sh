#!/usr/bin/env bash
set -euo pipefail

# Defaults are named once and read by both usage() and the parser, so the help
# text cannot drift from the code again (#109). They match
# playbooks/vars/sno_defaults.yml.
DEFAULT_CLUSTER_NAME="edge"
DEFAULT_BASE_DOMAIN="internal.ames.net"

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
  --cluster-name NAME   Cluster name (default: ${DEFAULT_CLUSTER_NAME})
  --base-domain DOMAIN  Base domain (default: ${DEFAULT_BASE_DOMAIN})
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
KIT_DIR="${SCRIPT_DIR}/../.."

CLUSTER_NAME="$DEFAULT_CLUSTER_NAME"
BASE_DOMAIN="$DEFAULT_BASE_DOMAIN"
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

# Created and resolved to an absolute path here, before the playbook runs, so
# the playbook receives a path that does not depend on its working directory,
# and a bad --output-dir fails now rather than after the ISO is built (#103).
mkdir -p "$OUTPUT_DIR" || { echo "Error: cannot create output directory: $OUTPUT_DIR" >&2; exit 1; }
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

if [[ -z "${MACHINE_NETWORK:-}" ]]; then
  MACHINE_NETWORK="$(python3 -c "import ipaddress,sys; n=ipaddress.ip_interface(sys.argv[1]).network; print(n)" "$NODE_IP")"
fi

SSH_KEY_CONTENT="$(cat "$SSH_KEY")"

VARS_FILE="$(mktemp /tmp/sno-vars-XXXXXX.json)"
trap 'rm -f "$VARS_FILE"' EXIT

python3 -c "
import json, sys
ps = open(sys.argv[1]).read().strip()
print(json.dumps({
    'sno_cluster_name': sys.argv[2],
    'sno_base_domain': sys.argv[3],
    'sno_hostname': sys.argv[4],
    'sno_node_ip': sys.argv[5],
    'sno_interface': sys.argv[6],
    'sno_disk_device': sys.argv[7],
    'sno_mac_address': sys.argv[8],
    'sno_use_dhcp': sys.argv[9] == 'true',
    'sno_pull_secret': ps,
    'sno_ssh_key': sys.argv[10],
}))
" "$PULL_SECRET" "$CLUSTER_NAME" "$BASE_DOMAIN" "$HOSTNAME_VAL" \
  "$NODE_IP" "$INTERFACE" "$DISK" "$MAC" "$USE_DHCP" \
  "$SSH_KEY_CONTENT" > "$VARS_FILE"
chmod 600 "$VARS_FILE"

EXTRA_VARS=(-e "@${VARS_FILE}" -e "sno_output_dir=${OUTPUT_DIR}")

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
echo "  Output:    ${OUTPUT_DIR}/agent.x86_64.iso"
echo "  Network:   $(if [[ "$USE_DHCP" == "true" ]]; then echo DHCP; else echo "Static (gw=${GATEWAY}, dns=${DNS})"; fi)"
echo

ansible-playbook "${KIT_DIR}/playbooks/build_sno_installer.yml" \
  "${EXTRA_VARS[@]}" \
  "$@"
