"""Use the existing single-daemon retained/fresh/BYOND contract."""
import importlib.util
from pathlib import Path
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("lifetime_retained_core", HERE.parent / "incremental_runtime_contract/run.py")
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)
LABELS = ('static_count', 'static_first', 'static_second', 'static_after_write', 'instance_count', 'instance_first', 'instance_second')
if __name__ == "__main__":
    raise SystemExit(contract.main(fixture_directory=HERE, labels=LABELS, prefix="DQ_LIFETIME",
        scope="static/instance lifetime across unchanged, body and declaration retained revisions"))
