#!/usr/bin/env python3
# ===========================================================================
# verify_cis_disk.py -- read the CIS hardening OFF the exported Windows disk,
# before the publish applies a label claiming it is there.
#
# WHY THIS EXISTS. `com.redhat.cis.level=L1` was an INPUT to the publish, not
# an observation of the disk: publish_windows_containerdisk.yml defaults to
# cis_level=L1 and the win2k22-cis-l1-golden repository, so the label recorded
# the operator's intent and nothing read the media back.
#
# That shipped. #91: `win2k22-cis-l1-golden:20260907-0516` carries a disk built
# and sysprepped on 2026-09-05 with no hardening on it at all -- byte-identical
# to the deliberately unhardened `win2k22-golden:20260905-2217`, 9307619328
# bytes, because the publish repackaged a qcow2 a previous run had left in the
# output directory. Every task reported success and the consumer demo scored 9
# of 27 CIS controls in front of the talk track that invites customers to read
# the report (sales.demos#358).
#
# THE FRESHNESS BUG IS FIXED SEPARATELY, in the playbook. This is the half that
# does not care how a wrong disk arrived. Whatever is about to be packaged gets
# read, and a label that the media does not support is refused.
#
# NO ROOT, NO LIBGUESTFS, NO CLUSTER. qemu-img + ntfsprogs (already required by
# this repo's Windows path) + regipy from pip. Deliberate: a check that needs
# sudo is a check that gets skipped, and one that needs the cluster cannot run
# at publish time on a laptop.
#
# Ported from sales.demos utilities/inspect-golden-image.py, which is the
# CONSUMER-side reader that found #91 -- same controls, same method. The
# producer half needs no registry pull: the disk is already here.
#
# Usage:
#   pip install regipy
#   playbooks/scripts/verify_cis_disk.py --disk output/.../disk.raw \
#       --workdir output/.../cis-verify --json output/.../cis_verify.json
#
# Exit codes: 0 the disk carries the hardening, 1 it does not, 2 the run could
# not reach a verdict (missing tool, unreadable hive). 2 is NOT a pass -- the
# playbook treats it as fatal, because "could not check" is exactly the state
# that let #91 through.
# ===========================================================================
"""Verify an exported Windows disk really carries the CIS hardening."""

import argparse
import json
import os
import subprocess
import sys

# The controls read back out of the hives. A deliberately SMALL subset of
# roles/windows_compliance/defaults/main.yml -- the ones whose presence is
# IMPOSSIBLE on a clean install, so a pass cannot be a Windows default in
# disguise. That is the whole trick: #358's original evidence was ambiguous
# precisely because nine "compliant" controls were stock values, and two days
# went into chasing a hypothesis those readings could not distinguish.
#
# hive, key path, value name, expected
CONTROLS = [
    ("SOFTWARE", r"\Policies\Microsoft\WindowsFirewall\DomainProfile", "EnableFirewall", 1),
    ("SOFTWARE", r"\Policies\Microsoft\WindowsFirewall\PrivateProfile", "EnableFirewall", 1),
    ("SOFTWARE", r"\Policies\Microsoft\WindowsFirewall\PublicProfile", "EnableFirewall", 1),
    ("SOFTWARE", r"\Policies\Microsoft\WindowsFirewall\PublicProfile", "DefaultInboundAction", 1),
    ("SOFTWARE", r"\Microsoft\Windows\CurrentVersion\Policies\System", "DontDisplayLastUserName", 1),
    ("SOFTWARE", r"\Policies\Microsoft\Windows", "DisableWebPnPDownload", 1),
    ("SYSTEM", r"\Control\Lsa", "SCENoApplyLegacyAuditPolicy", 1),
    ("SYSTEM", r"\Services\LanmanWorkstation\Parameters", "RequireSecuritySignature", 1),
    ("SYSTEM", r"\Services\LanmanServer\Parameters", "RequireSecuritySignature", 1),
    ("SYSTEM", r"\Services\LanmanServer\Parameters", "SMB1", 0),
]

HIVES = ("SOFTWARE", "SYSTEM")


class Indeterminate(Exception):
    """Raised when the disk cannot be read at all -- exit 2, never a pass."""


def run(*argv):
    r = subprocess.run(argv, capture_output=True, text=True)
    if r.returncode:
        raise Indeterminate(f"{' '.join(argv[:3])} failed:\n{r.stderr[-2000:]}")
    return r.stdout


def as_raw(disk, workdir):
    """Accept either a raw image or a qcow2; carving needs raw."""
    fmt = ""
    try:
        fmt = json.loads(run("qemu-img", "info", "--output=json", disk)).get("format", "")
    except Indeterminate:
        raise
    if fmt == "raw":
        return disk
    raw = os.path.join(workdir, "verify.raw")
    if not os.path.exists(raw):
        print(f"==> converting {fmt} to raw for inspection")
        run("qemu-img", "convert", "-O", "raw", disk, raw)
    return raw


def carve_volume(raw, workdir):
    """The Windows NTFS volume as its own file, so ntfscat can address it."""
    vol = os.path.join(workdir, "win.ntfs")
    if os.path.exists(vol):
        return vol
    table = json.loads(run("sfdisk", "-J", raw)).get("partitiontable", {})
    parts = table.get("partitions") or []
    if not parts:
        raise Indeterminate(f"no partition table on {raw}; is this a Windows disk?")
    sector = table.get("sectorsize", 512)
    # The Windows volume is the biggest partition; the others are the ESP and
    # the ~128 MiB Microsoft Reserved partition.
    big = max(parts, key=lambda p: p["size"])
    print(f"==> carving the Windows volume ({big['size'] * sector // (1 << 30)} GiB)")
    run("dd", f"if={raw}", f"of={vol}", "bs=1M",
        f"skip={big['start'] * sector // (1 << 20)}",
        f"count={big['size'] * sector // (1 << 20) + 1}",
        "conv=sparse", "status=none")
    return vol


def read_file(vol, path):
    r = subprocess.run(["ntfscat", "-f", vol, path], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def extract_hives(vol, workdir):
    for hive in HIVES:
        dest = os.path.join(workdir, hive)
        if os.path.exists(dest):
            continue
        data = read_file(vol, f"/Windows/System32/config/{hive}")
        if data is None:
            raise Indeterminate(f"could not read the {hive} hive out of the volume")
        with open(dest, "wb") as fh:
            fh.write(data)


def provenance(vol):
    """Date the disk from its own sysprep log.

    Provenance, not compliance -- reported either way, never fatal on its own.
    It is how #91 was caught: a disk whose only sysprep run predated its tag by
    two days. A publish that packages the right disk records one recent run.
    """
    log = read_file(vol, "/Windows/System32/Sysprep/Panther/setupact.log")
    if not log:
        return {"sysprep_runs": None}
    text = log.decode("utf-16" if log[:2] in (b"\xff\xfe", b"\xfe\xff") else "utf-8",
                      errors="replace")
    lines = text.splitlines()
    runs = [ln for ln in lines if "Beginning of a new sysprep run" in ln]
    stamps = [ln.split(",")[0] for ln in lines if "The time is now" in ln]
    info = {
        "sysprep_runs": len(runs),
        "sysprep_first": stamps[0] if stamps else None,
        "sysprep_last": stamps[-1] if stamps else None,
    }
    print(f"\n==> provenance: {len(runs)} sysprep run(s) recorded on this disk")
    if stamps:
        print(f"    first: {stamps[0]}")
        print(f"    last:  {stamps[-1]}")
    return info


def check(workdir):
    try:
        from regipy.registry import RegistryHive
    except ImportError:
        raise Indeterminate(
            "regipy is not installed. `pip install regipy` -- this check is not "
            "optional, because an unverified disk is how #91 shipped."
        )
    hives = {n: RegistryHive(os.path.join(workdir, n)) for n in HIVES}
    # An offline SYSTEM hive has no CurrentControlSet; \Select\Current names it.
    try:
        sel = {v.name: v.value for v in hives["SYSTEM"].get_key(r"\Select").get_values()}
        cs = f"\\ControlSet{sel.get('Current', 1):03d}"
    except Exception:
        cs = r"\ControlSet001"

    print(f"\n{'state':<15}{'found':<10}{'want':<8}key")
    results, good = [], 0
    for hive_name, path, value, want in CONTROLS:
        full = (cs + path) if hive_name == "SYSTEM" else path
        found, state = None, "KEY ABSENT"
        try:
            key = hives[hive_name].get_key(full)
        except Exception:
            key = None
        if key is not None:
            found = next((v.value for v in key.get_values()
                          if v.name and v.name.lower() == value.lower()), None)
            if found is None:
                state = "VALUE ABSENT"
            elif found == want:
                state, good = "OK", good + 1
            else:
                state = "WRONG"
        print(f"{state:<15}{str(found):<10}{str(want):<8}{hive_name}:{full}\\{value}")
        results.append({"hive": hive_name, "key": full, "value": value,
                        "want": want, "found": found, "state": state})
    return good, results


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--disk", required=True, help="raw or qcow2 disk to inspect")
    ap.add_argument("--workdir", required=True, help="scratch dir for hives and the volume")
    ap.add_argument("--json", help="write a machine-readable verdict here")
    args = ap.parse_args()

    os.makedirs(args.workdir, exist_ok=True)
    verdict = {"disk": args.disk, "controls_total": len(CONTROLS)}
    try:
        raw = as_raw(args.disk, args.workdir)
        vol = carve_volume(raw, args.workdir)
        extract_hives(vol, args.workdir)
        verdict.update(provenance(vol))
        good, results = check(args.workdir)
        verdict.update({"controls_present": good, "controls": results,
                        "hardened": good == len(CONTROLS)})
        rc = 0 if good == len(CONTROLS) else 1
    except Indeterminate as exc:
        print(f"\nINDETERMINATE: {exc}", file=sys.stderr)
        verdict.update({"hardened": None, "error": str(exc)})
        rc = 2

    if args.json:
        with open(args.json, "w") as fh:
            json.dump(verdict, fh, indent=2, default=str)

    if rc == 0:
        print(f"\n{verdict['controls_present']} of {len(CONTROLS)} non-default CIS "
              f"controls present")
        print("VERDICT: the disk carries the hardening. Safe to label L1.")
    elif rc == 1:
        print(f"\n{verdict['controls_present']} of {len(CONTROLS)} non-default CIS "
              f"controls present")
        print("VERDICT: THE DISK DOES NOT CARRY CIS HARDENING.")
        print("  Every control above is one that CANNOT be set on a clean install,")
        print("  so absence is not a Windows default -- it is a missing hardening")
        print("  pass. Do not label this L1. See #91.")
    else:
        print("VERDICT: could not read the disk. This is NOT a pass -- see #91.")
    return rc


if __name__ == "__main__":
    sys.exit(main())
