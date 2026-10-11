"""Compile-only dot-formal global fallback controls; no runtime claims."""
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
CASES = ("global_only", "missing", "owner_shadow")

def main():
    spec = importlib.util.spec_from_file_location(
        "nameof_relative_global_driver", HERE.parent / "loop_local_diagnostics" / "run.py")
    driver = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(driver)
    driver.HERE = HERE
    driver.CASES = driver.ORIGINAL_CASES = CASES
    driver.SCOPE = "compile-only relative nameof global fallback; no runtime or shadow identity proof"
    return driver.main()

if __name__ == "__main__":
    raise SystemExit(main())
