#!/usr/bin/env bash
# ===========================================================================
# remaster_iso.sh — make a Windows installation ISO boot without a keypress,
# then serve it to CDI over HTTP. Runs in a pod on the build cluster; never on
# a laptop. See image.builder.pipeline#40.
#
# WHY A POD AND NOT THIS MACHINE. Measured (#36): the cluster pulls this ISO at
# ~246 MiB/s and a laptop pushes at ~1 MiB/s. Re-mastering locally would mean a
# 4.7 GB upload — about 75 minutes — and would undo the whole reason
# windows_iso_source defaults to 'url'.
#
# WHY RENAME RATHER THAN RE-POINT EL TORITO. Red Hat's own
# kubevirt-tekton-tasks 'modify-windows-iso-file' deletes efisys.bin and
# cdboot.efi and renames the _noprompt twins over them, then rebuilds. Both
# files matter: efisys.bin IS the El Torito boot image, and cdboot.efi is what
# lives inside it. The xorriso invocation below is that task's, verbatim —
# deviating from a shipped, working recipe here buys nothing and risks media
# that boots on one firmware and not another.
#
# Inputs, all from the environment so this file needs no templating:
#   ISO_URL      required — where to fetch the stock ISO
#   ISO_SHA256   optional — checksum of the stock ISO, verified before use
#   OUT_NAME     required — filename to serve the re-mastered ISO as
#   PORT         optional — HTTP port, default 8080
#   SCRATCH      optional — working directory, default /scratch
# ===========================================================================
set -euo pipefail

: "${ISO_URL:?ISO_URL must be set}"
: "${OUT_NAME:?OUT_NAME must be set}"
PORT="${PORT:-8080}"
SCRATCH="${SCRATCH:-/scratch}"

WORK="${SCRATCH}/work"
SERVE="${SCRATCH}/serve"
SRC="${WORK}/source.iso"
TREE="${WORK}/tree"
EFI="${TREE}/efi/microsoft/boot"

# The image runs as an arbitrary UID under OpenShift's restricted SCC, so $HOME
# from the image is not writable. Nothing here needs a home, but xorriso and
# curl both write dot-files if they can find one.
export HOME="${SCRATCH}"

rm -rf "${WORK}" "${SERVE}"
mkdir -p "${WORK}" "${TREE}" "${SERVE}"

# Start serving an EMPTY directory first. The readiness probe reads /ready and
# nothing else, and /ready is written last — so a probe that passes means the
# ISO is complete, and CDI can never be pointed at a half-written file.
python3 -m http.server "${PORT}" --directory "${SERVE}" &
HTTP_PID=$!

echo "==> fetching ${ISO_URL}"
curl -fL --retry 3 --retry-delay 5 -o "${SRC}" "${ISO_URL}"
SRC_BYTES=$(stat -c %s "${SRC}")
echo "==> fetched ${SRC_BYTES} bytes"

if [ -n "${ISO_SHA256:-}" ]; then
    echo "==> verifying sha256"
    echo "${ISO_SHA256}  ${SRC}" | sha256sum -c -
fi

echo "==> extracting"
# xorriso reads Joliet when Rock Ridge is absent, which is the case on Windows
# media — so long, mixed-case names such as sources/install.wim and
# cdboot_noprompt.efi survive. Verified on a synthetic Joliet-only ISO before
# this was written. guestfish would also work and is what Red Hat's task uses,
# but it wants devices.kubevirt.io/kvm; xorriso keeps this pod unprivileged.
xorriso -osirrox on -indev "${SRC}" -extract / "${TREE}"

# A SILENTLY PARTIAL EXTRACTION would survive every other check here: the ISO
# would rebuild, boot, and then stop somewhere in Setup with nothing on screen
# to say why. That is the shape of defect after defect on #24, so it is checked
# rather than assumed.
if [ ! -f "${TREE}/sources/install.wim" ]; then
    echo "FATAL: sources/install.wim is not in the extracted tree." >&2
    echo "The ISO did not extract as a Windows installation medium." >&2
    exit 1
fi
TREE_BYTES=$(du -sb "${TREE}" | cut -f1)
echo "==> extracted ${TREE_BYTES} bytes, install.wim $(stat -c %s "${TREE}/sources/install.wim") bytes"
if [ "$((TREE_BYTES * 100 / SRC_BYTES))" -lt 95 ]; then
    echo "FATAL: extracted ${TREE_BYTES} bytes from a ${SRC_BYTES} byte ISO." >&2
    echo "That is under 95% and means the read lost files. Refusing to build" >&2
    echo "installation media out of a partial tree." >&2
    exit 1
fi

if [ ! -f "${EFI}/efisys_noprompt.bin" ] || [ ! -f "${EFI}/cdboot_noprompt.efi" ]; then
    echo "FATAL: ${EFI}/efisys_noprompt.bin or cdboot_noprompt.efi is missing." >&2
    echo "This ISO does not ship the no-prompt bootloader, so the build would" >&2
    echo "still stop at 'Press any key to boot from CD or DVD' with nothing on" >&2
    echo "the console to explain it. Refusing to produce media that looks" >&2
    echo "re-mastered and is not." >&2
    exit 1
fi

echo "==> swapping in the no-prompt bootloader"
# xorriso restores the ISO's read-only permissions onto the extracted tree.
chmod -R u+w "${TREE}"
rm -f "${EFI}/efisys.bin" "${EFI}/cdboot.efi"
mv "${EFI}/efisys_noprompt.bin" "${EFI}/efisys.bin"
mv "${EFI}/cdboot_noprompt.efi" "${EFI}/cdboot.efi"

# The source is 4.7 GB and is not needed again. Dropping it now keeps peak
# scratch use to tree + output rather than all three at once.
rm -f "${SRC}"

echo "==> rebuilding"
xorriso -as mkisofs -no-emul-boot \
    -e "efi/microsoft/boot/efisys.bin" \
    -boot-load-size 1 \
    -iso-level 4 \
    -J -l -D -N \
    -joliet-long \
    -relaxed-filenames \
    -V "WINDOWS" \
    -o "${WORK}/${OUT_NAME}" "${TREE}"
rm -rf "${TREE}"

# Printed, not parsed: this is what a human reads to confirm the UEFI entry
# points at efi/microsoft/boot/efisys.bin on the ISO that actually shipped.
xorriso -indev "${WORK}/${OUT_NAME}" -report_el_torito plain

mv "${WORK}/${OUT_NAME}" "${SERVE}/${OUT_NAME}"
echo "==> $(stat -c %s "${SERVE}/${OUT_NAME}") bytes  $(sha256sum "${SERVE}/${OUT_NAME}" | cut -d' ' -f1)"

echo ok > "${SERVE}/ready"
echo "==> serving ${OUT_NAME} on :${PORT}"

# Exits non-zero if the server dies, which fails the pod rather than leaving a
# Running pod that answers nothing.
wait "${HTTP_PID}"
