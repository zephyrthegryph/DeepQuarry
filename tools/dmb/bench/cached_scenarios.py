"""Exact disk-cache transition protocol over immutable captured snapshots."""
from pathlib import Path

SEQUENCE = ("cached-population", "parent-unchanged", "edited-cached", "cold-after-edit")
PARENT = frozenset(SEQUENCE[:2])
EDITED = frozenset(SEQUENCE[2:])


def validate(scenarios, parent_journal, workers):
    """Pure admission checks; never populate caches or mutate either snapshot."""
    if not any(scenario["name"] in SEQUENCE for scenario in scenarios):
        return False
    if tuple(scenario["name"] for scenario in scenarios) != SEQUENCE:
        raise ValueError("cached cohort must be exactly " + " -> ".join(SEQUENCE))
    if workers != [8]:
        raise ValueError("cached minimal-edit cohort requires exactly eight workers")
    if not parent_journal:
        raise ValueError("cached cohort requires immutable parent --input-journal")
    parent = Path(parent_journal).resolve()
    edited = None
    configuration = scenarios[0]["_semantic_configuration"]
    project = scenarios[0]["project"]
    for scenario in scenarios:
        if scenario.get("edits"):
            raise ValueError("cached cohort never edits live source")
        if scenario["project"] != project or scenario["_semantic_configuration"] != configuration:
            raise ValueError("cache transitions require one project and semantic configuration")
        no_cache = scenario.get("no_cache", False)
        if type(no_cache) is not bool or no_cache != (scenario["name"] == "cold-after-edit"):
            raise ValueError("only cold-after-edit must explicitly set no_cache=true")
        journal = Path(scenario.get("input_journal", parent)).resolve()
        if scenario["name"] in PARENT:
            if journal != parent:
                raise ValueError("parent cache phases must use the exact parent journal")
        else:
            authenticated = scenario.get("_edited_snapshot")
            if not authenticated or journal != authenticated["journal"] or journal == parent:
                raise ValueError("edited cache phases require authenticated derivative BYOND pins")
            identity = (journal, authenticated["snapshot_id"],
                        authenticated["provenance"]["variant_receipt_sha256"])
            if edited is not None and edited != identity:
                raise ValueError("edited cached and cold phases must use the same derivative")
            edited = identity
        scenario["_cache_protocol"] = {
            "phase": scenario["name"],
            "cache_state": "empty" if scenario["name"] == "cached-population" else
                "parent_populated" if scenario["name"] in ("parent-unchanged", "edited-cached") else "disabled",
            "process_state": "fresh_cli_each_phase_not_resident_daemon",
            "oracle": "fresh_no_cache_exact_pair_and_diagnostics",
            "mutation": "private_captured_derivative_only",
        }
    return True
