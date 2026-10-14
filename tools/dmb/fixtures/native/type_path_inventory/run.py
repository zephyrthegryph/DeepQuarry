"""Type-path inventory semantics on the existing retained/fresh/BYOND core."""
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "inventory_runtime_core", HERE.parent / "incremental_runtime_contract/run.py")
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)

if __name__ == "__main__":
    raise SystemExit(contract.main(
        fixture_directory=HERE,
        labels=("typed_count", "untyped_count", "excluded_count"),
        prefix="DQ_INVENTORY",
        scope="typed datum iteration versus type-path inventory and initial tier lookup"))
