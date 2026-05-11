"""XCCDF results parser for the image-builder-pipeline.

Consumed by playbooks/generate_policy_data.yml as the `xccdf_parse` filter.
Returns a dict with rule counts, severity breakdown, hardening score, and
exempt-control candidates derived from low-severity XCCDF failures.
"""

from collections import Counter
from xml.etree import ElementTree as ET


def _local(tag):
    return tag.split("}", 1)[-1] if "}" in tag else tag


def xccdf_parse(xml_text):
    root = ET.fromstring(xml_text)

    rule_results = [e for e in root.iter() if _local(e.tag) == "rule-result"]

    by_result = Counter()
    by_severity_fail = Counter()
    failing_rules = []
    exempt_candidates = []

    for rr in rule_results:
        idref = rr.get("idref", "")
        severity = (rr.get("severity") or "unknown").lower()

        result_text = None
        for child in rr:
            if _local(child.tag) == "result":
                result_text = (child.text or "").strip().lower()
                break
        if not result_text:
            continue

        by_result[result_text] += 1

        if result_text == "fail":
            by_severity_fail[severity] += 1
            failing_rules.append({"control_id": idref, "severity_xccdf": severity})
            if severity == "low":
                exempt_candidates.append(
                    {
                        "control_id": idref,
                        "severity": "P3",
                        "reason": "AWS-specific exception (review-required)",
                        "applies_to": ["aws_ami"],
                    }
                )

    pass_count = by_result.get("pass", 0)
    fail_count = by_result.get("fail", 0)
    denominator = pass_count + fail_count
    score = round((pass_count / denominator) * 100, 2) if denominator else 0.0

    return {
        "total_rules": sum(by_result.values()),
        "passing": pass_count,
        "failing": fail_count,
        "notapplicable": by_result.get("notapplicable", 0),
        "notchecked": by_result.get("notchecked", 0),
        "error": by_result.get("error", 0),
        "unknown": by_result.get("unknown", 0),
        "informational": by_result.get("informational", 0),
        "notselected": by_result.get("notselected", 0),
        "fixed": by_result.get("fixed", 0),
        "failures_by_severity": dict(by_severity_fail),
        "hardening_score": score,
        "failing_rules": failing_rules,
        "exempt_candidates": exempt_candidates,
    }


class FilterModule:
    def filters(self):
        return {"xccdf_parse": xccdf_parse}
