#!/usr/bin/env bash
# ===========================================================================
# fetch_iso.sh — download the Windows installation ISO onto the build
# cluster's scratch volume and verify it. Runs as the first initContainer of
# the re-master pod. See image.builder.pipeline#46.
#
# WHY THIS IS A SEPARATE STAGE FROM THE PATCH. The patch needs guestfish, which
# lives in tekton-tasks-disk-virt, and **that image ships no CA bundle** —
# neither /etc/ssl/certs/ca-certificates.crt nor /etc/pki/tls/certs/ca-bundle.crt
# exists, so every HTTPS fetch from it fails with curl error 77. The tekton-tasks
# image fetches this URL from Microsoft happily. So each image does only what it
# is demonstrably able to do, and the container that touches the network is not
# the one that needs a device plugin.
#
# WHY NOT curl -k. windows_iso_sha256 is pinned and checked below, so TLS is
# belt-and-braces here — but turning verification off to work around a missing
# trust store is the wrong habit to write into a factory.
#
# Inputs:
#   ISO_URL      required — where to fetch the stock ISO
#   ISO_SHA256   optional — checksum, verified before anything else uses it
#   SCRATCH      optional — working directory, default /scratch
# ===========================================================================
set -euo pipefail

: "${ISO_URL:?ISO_URL must be set}"
SCRATCH="${SCRATCH:-/scratch}"
WORK="${SCRATCH}/work"
SERVE="${SCRATCH}/serve"
SRC="${WORK}/source.iso"

# Both directories are made here, by the stage that runs first, so the patch
# stage can assume them.
rm -rf "${WORK}" "${SERVE}"
mkdir -p "${WORK}" "${SERVE}"

echo "==> fetching ${ISO_URL}"
curl -fL --retry 3 --retry-delay 5 -o "${SRC}" "${ISO_URL}"
echo "==> fetched $(stat -c %s "${SRC}") bytes"

if [ -n "${ISO_SHA256:-}" ]; then
    echo "==> verifying sha256"
    echo "${ISO_SHA256}  ${SRC}" | sha256sum -c -
else
    echo "==> no ISO_SHA256 given, skipping the checksum"
fi
