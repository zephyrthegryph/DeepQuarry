"""Conservative endpoint-union adoption; scalar/process/pipeline metrics unchanged."""
import math

METHOD = "exact-domain-endpoint-union-v1"
COMPLETE = "complete_temporally_disjoint_all_thread_union"

def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value >= 0

def equal(a, b):
    return (a is None and b is None) or (number(a) and number(b) and math.isclose(a, b, rel_tol=1e-9, abs_tol=1e-12))

def evaluate(row, stage_map, selected_stages):
    """Return independent per-domain costs, proof notes and malformed-claim errors."""
    stages = selected_stages(row)
    bounded = row.get("cpu_bounds_method") == "paired_thread_cpu_quantization"
    evidence = row.get("domain_cpu_bounds")
    selectors = row.get("domain_cpu_selectors")
    available = bool(evidence) or bool(selectors)
    errors = []
    if available and (not isinstance(evidence, dict) or not isinstance(selectors, dict)
                      or selectors != stage_map or set(evidence) != set(stage_map)):
        errors.append("domain endpoint proof selectors differ from authenticated stage map")
        available = False
    costs, notes = {}, {}
    for domain, names in stage_map.items():
        originals, points = [], []
        for scalar, bounds in (("max_thread_cpu_s", "max_thread_cpu_bounds_s"),
                               ("cpu_s", "cpu_bounds_s")):
            values, point_values = [], []
            for name in names:
                stage = stages.get(name, {})
                point_values.append(stage.get(scalar))
                bound = stage.get(bounds)
                values.append(bound.get("upper") if bounded and isinstance(bound, dict)
                              else stage.get(scalar))
            originals.append(sum(values) if all(number(v) for v in values) else None)
            points.append(sum(point_values) if all(number(v) for v in point_values) else None)
        chosen = list(originals)
        note = {"original_critical_upper_s": originals[0], "original_total_upper_s": originals[1],
                "reason": "historical_or_missing_proof", "critical_proof": None, "total_proof": None}
        if available and bounded:
            proof = evidence[domain]
            if not isinstance(proof, dict):
                errors.append("invalid domain endpoint proof: " + domain)
            elif "original_total_upper_s" not in proof:
                if any(key in proof for key in ("total_point_s", "total_union_upper_s", "total_upper_s",
                                               "total_proof", "selected_threads", "selected_intervals")):
                    errors.append("partial domain endpoint proof schema: " + domain)
                note["reason"] = "historical_proof_schema"
            else:
                note["reason"] = "conservative_proof_fallback"
                coverage = all(isinstance(proof.get(k), int) and not isinstance(proof[k], bool)
                               and proof[k] > 0 for k in ("selected_threads", "selected_intervals"))
                coverage = coverage and proof["selected_intervals"] >= proof["selected_threads"]
                for index, fields in enumerate((
                    ("critical_point_s", "original_upper_s", "all_thread_union_upper_s", "upper_s", "proof"),
                    ("total_point_s", "original_total_upper_s", "total_union_upper_s", "total_upper_s", "total_proof"))):
                    point, original, cap, upper, status = (proof.get(k) for k in fields)
                    label = "critical" if index == 0 else "total"
                    note[label + "_proof"] = status
                    if not equal(point, points[index]) or not equal(original, originals[index]):
                        errors.append("domain proof original differs from independent sum: " + domain + "/" + label)
                        continue
                    if status == COMPLETE:
                        if (not coverage or not number(original) or not number(point) or not number(cap) or not number(upper) or upper > original
                                or not equal(upper, min(original, cap))):
                            errors.append("invalid complete domain endpoint cap: " + domain + "/" + label)
                            continue
                        chosen[index] = upper
                        note["reason"] = "complete_endpoint_proof"
                    elif cap is not None or not equal(upper, original):
                        errors.append("unproved domain bound must preserve original: " + domain + "/" + label)
                note["selected_threads"] = proof.get("selected_threads")
                note["selected_intervals"] = proof.get("selected_intervals")
        costs[domain] = tuple(chosen)
        note.update(adopted_critical_upper_s=chosen[0], adopted_total_upper_s=chosen[1])
        notes[domain] = note
    return costs, notes, errors
