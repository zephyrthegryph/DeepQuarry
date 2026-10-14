"""Finite compile-only name observations; never an exhaustive namespace certificate."""
import importlib.util
from pathlib import Path
HERE = Path(__file__).resolve().parent
CASES = ("context_world", "context_usr", "context_src", "context_args", "catalog_direction", "catalog_boolean", "unknown_global", "authored_shadow")
ORIGINAL_CASES = CASES
CASES += ('context_callee', 'context_caller', 'context_type', 'context_implied_type', 'context_proc', 'context_global')

def main():
    source = HERE.parent / "loop_local_diagnostics" / "run.py"
    spec = importlib.util.spec_from_file_location("name_compile_observations", source)
    driver = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(driver)
    driver.HERE = HERE
    driver.CASES = CASES
    # All observed entry-path regressions are mandatory in the default corpus.
    driver.ORIGINAL_CASES = CASES
    return driver.main()

if __name__ == "__main__":
    raise SystemExit(main())
