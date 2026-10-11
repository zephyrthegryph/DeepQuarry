"""Nested map execution on the same retained/fresh/BYOND core."""
import importlib.util
from pathlib import Path
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("nested_map_retained_core", HERE.parent / "incremental_runtime_contract/run.py")
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)
LABELS = ("parent_present", "child_type", "nested_amount", "leaf_scalar", "body_marker")
if __name__ == "__main__":
    raise SystemExit(contract.main(fixture_directory=HERE, labels=LABELS, prefix="DQ_NESTED",
        asset_files=("contract-resource.txt", "probe.dmm"),
        scope="nested map modifier across retained initial/unchanged/body/structural revisions"))
