"""Compile-only member registration observation through the bounded reference core."""
import importlib.util
import sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("member_order_core", HERE.parent / "initializer_dependent_order/run.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
runner.HERE = HERE
if __name__ == "__main__":
    arguments = sys.argv[1:]
    if "--reference-only" in arguments:
        arguments.remove("--reference-only")
    raise SystemExit(runner.reference_only(arguments))
