"""Paired list-index observations; no predefined fractional/error semantics."""
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "list_index_launcher", HERE.parent / "power_retirement_runtime" / "run.py")
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)

if __name__ == "__main__":
    raise SystemExit(launcher.main(
        fixture_directory=HERE,
        scope="numeric/associative/nested list-index observations and uncaught errors; "
              "same pinned fixture inputs, not full-program source closure or parity"))
