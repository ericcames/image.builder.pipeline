#!/usr/bin/env bash
# ===========================================================================
# remaster_iso.sh — make a Windows installation ISO boot without a keypress.
# Runs on the build cluster; never on a laptop. Takes the ISO that fetch_iso.sh
# has already downloaded and verified, and leaves the finished medium in
# $SCRATCH/serve for a sibling container to serve over HTTP.
# See image.builder.pipeline#40, #44 and #46.
#
# WHY A POD AND NOT THIS MACHINE. Measured (#36): the cluster pulls this ISO at
# ~246 MiB/s and a laptop pushes at ~1 MiB/s. Re-mastering locally would mean a
# 4.7 GB upload — about 75 minutes — and would undo the whole reason
# windows_iso_source defaults to 'url'.
#
# WHY IT DOES NOT FETCH (#46). This image ships no CA bundle, so any HTTPS
# download from it fails with curl error 77. Downloading is fetch_iso.sh's job,
# on an image that can do it.
#
# WHY guestfish AND NOT xorriso (#44). The real Windows Server 2022 medium is
# **UDF**, not ISO 9660 — `guestfish ... list-filesystems` says `/dev/sda: udf`,
# and its ISO 9660 tree is a stub holding one 135-byte file. It has to be UDF:
# `sources/install.wim` is 4,340,202,461 bytes, past the 4 GiB ISO 9660
# single-extent limit. libisofs, which xorriso reads with, has no UDF support,
# so `xorriso -osirrox -extract` returns one node. That is why Red Hat's
# modify-windows-iso-file extracts with guestfish and asks for
# devices.kubevirt.io/kvm: **the device is what buys UDF support**, because
# libguestfs boots a kernel that has a UDF driver.
#
# WHY A PATCH AND NOT A REBUILD. On this medium efisys.bin and
# efisys_noprompt.bin are the same size (1,474,560), and the hidden El Torito
# boot image is a byte-identical copy of the first. So the entire job is a
# same-length overwrite at one LBA: no 4.7 GB extraction, no re-authoring, and
# the original UDF filesystem is left exactly as Microsoft shipped it. Red Hat
# rebuilds because their pipeline has already extracted to a PVC; we have no
# such reason.
#
# THE IDENTITY ASSERTION IS LOAD-BEARING. Nothing is written until the bytes at
# the computed LBA are proved byte-identical to the prompting boot image, so a
# mis-parsed catalogue cannot corrupt the medium — it fails instead.
#
# Inputs, all from the environment so this file needs no templating:
#   OUT_NAME     required — filename to leave the re-mastered ISO under
#   SCRATCH      optional — working directory, default /scratch
# ===========================================================================
set -euo pipefail

: "${OUT_NAME:?OUT_NAME must be set}"
SCRATCH="${SCRATCH:-/scratch}"

WORK="${SCRATCH}/work"
SERVE="${SCRATCH}/serve"
SRC="${WORK}/source.iso"
BOOT_DIR="/efi/microsoft/boot"

# The image runs as an arbitrary UID under OpenShift's restricted SCC, so the
# image's own $HOME is not writable and guestfish wants somewhere to put
# .guestfish.
export HOME="${WORK}"

fatal() { echo "FATAL: $*" >&2; exit 1; }

[ -s "${SRC}" ] || fatal "${SRC} is missing. fetch_iso.sh runs before this and
should have left it there."
SRC_BYTES=$(stat -c %s "${SRC}")
echo "==> working on ${SRC}, ${SRC_BYTES} bytes"

echo "==> reading the boot images out of the medium"
guestfish --ro -a "${SRC}" -m /dev/sda <<EOF || fatal "could not mount the ISO. Expected a Windows installation medium readable as UDF or ISO 9660."
download ${BOOT_DIR}/efisys.bin ${WORK}/efisys.bin
download ${BOOT_DIR}/efisys_noprompt.bin ${WORK}/efisys_noprompt.bin
EOF

[ -s "${WORK}/efisys.bin" ] || fatal "${BOOT_DIR}/efisys.bin is not on this medium."
[ -s "${WORK}/efisys_noprompt.bin" ] || fatal \
    "${BOOT_DIR}/efisys_noprompt.bin is not on this medium. Without the
no-prompt bootloader the build would still stop at 'Press any key to boot from
CD or DVD' with nothing on the console to explain it. Refusing to produce media
that looks re-mastered and is not."

PROMPT_BYTES=$(stat -c %s "${WORK}/efisys.bin")
NOPROMPT_BYTES=$(stat -c %s "${WORK}/efisys_noprompt.bin")
echo "==> efisys.bin ${PROMPT_BYTES} bytes, efisys_noprompt.bin ${NOPROMPT_BYTES} bytes"

# THE WHOLE APPROACH RESTS ON THESE TWO BEING EQUAL. A shorter replacement would
# leave a tail of the old image behind and a longer one would run into whatever
# follows it. Both are silent corruptions, so this is checked rather than
# assumed — and if a future medium breaks it, the rebuild path in Red Hat's
# modify-windows-iso-file is the fallback to write.
[ "${PROMPT_BYTES}" = "${NOPROMPT_BYTES}" ] || fatal \
    "efisys.bin and efisys_noprompt.bin differ in size (${PROMPT_BYTES} vs
${NOPROMPT_BYTES}). An in-place patch needs them equal."
[ $((PROMPT_BYTES % 2048)) -eq 0 ] || fatal \
    "the boot image is not a whole number of 2048-byte sectors (${PROMPT_BYTES})."

# --- Find the EFI El Torito boot image --------------------------------------
# El Torito, as the spec lays it out: a Boot Record Volume Descriptor at LBA 17
# whose bytes 71..74 point at the boot catalogue, then 32-byte catalogue
# records — a validation entry, a default entry, then section headers (0x90 or
# 0x91) each followed by their section entries. The EFI one carries platform id
# 0xEF, and its section entry's bytes 8..11 are the load RBA.
le32() { od -An -tu4 -j "$1" -N4 "${SRC}" | tr -d ' \n'; }
u8() { od -An -tu1 -j "$1" -N1 "${SRC}" | tr -d ' \n'; }

[ "$(dd if="${SRC}" bs=1 skip=$((17 * 2048 + 1)) count=5 status=none)" = "CD001" ] ||
    fatal "no Boot Record Volume Descriptor at LBA 17 — this is not a bootable ISO."

CATALOG_LBA=$(le32 $((17 * 2048 + 71)))
echo "==> El Torito catalogue at LBA ${CATALOG_LBA}"

EFI_LBA=""
CATALOG_OFF=$((CATALOG_LBA * 2048))
for i in $(seq 0 63); do
    rec=$((CATALOG_OFF + i * 32))
    id=$(u8 "${rec}")
    platform=$(u8 $((rec + 1)))
    # 0x90 header, 0x91 final header; 0xEF is the EFI platform id.
    if { [ "${id}" = "144" ] || [ "${id}" = "145" ]; } && [ "${platform}" = "239" ]; then
        EFI_LBA=$(le32 $((rec + 32 + 8)))
        break
    fi
done
[ -n "${EFI_LBA}" ] || fatal \
    "no EFI section entry in the El Torito catalogue. This medium does not boot
via UEFI, so re-mastering it would change nothing."
echo "==> EFI boot image at LBA ${EFI_LBA}"

SECTORS=$((PROMPT_BYTES / 2048))
extent_sha() { dd if="${SRC}" bs=2048 skip="${EFI_LBA}" count="${SECTORS}" status=none | sha256sum | cut -d' ' -f1; }
sha_of() { sha256sum "$1" | cut -d' ' -f1; }

# NOTHING IS WRITTEN UNTIL THIS PASSES.
[ "$(extent_sha)" = "$(sha_of "${WORK}/efisys.bin")" ] || fatal \
    "the bytes at LBA ${EFI_LBA} are not ${BOOT_DIR}/efisys.bin. Either the
catalogue was read wrongly or this medium is laid out differently. Refusing to
write."
echo "==> confirmed: the boot image on the medium is the prompting one"

echo "==> patching ${SECTORS} sectors at LBA ${EFI_LBA}"
dd if="${WORK}/efisys_noprompt.bin" of="${SRC}" bs=2048 seek="${EFI_LBA}" \
    conv=notrunc status=none

[ "$(extent_sha)" = "$(sha_of "${WORK}/efisys_noprompt.bin")" ] ||
    fatal "the patch did not take."
[ "$(stat -c %s "${SRC}")" = "${SRC_BYTES}" ] ||
    fatal "the ISO changed length; it must not."
echo "==> patched, length unchanged at ${SRC_BYTES} bytes"

# The medium still has to READ. A patch that lands in the right place but
# breaks the filesystem would otherwise surface as a Windows Setup failure
# twenty minutes later.
echo "==> re-reading the medium"
guestfish --ro -a "${SRC}" -m /dev/sda ll /sources/install.wim ||
    fatal "the medium no longer mounts after patching."

mv "${SRC}" "${SERVE}/${OUT_NAME}"
echo "==> $(stat -c %s "${SERVE}/${OUT_NAME}") bytes  $(sha_of "${SERVE}/${OUT_NAME}")"

# Written last. The readiness probe reads /ready and nothing else, so a passing
# probe means the medium is complete and correct, not merely that a process is
# alive.
echo ok > "${SERVE}/ready"
echo "==> done"
