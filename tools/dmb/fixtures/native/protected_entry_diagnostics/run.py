"""Protected entry observations through the existing compiler-only launcher."""
import importlib.util
from pathlib import Path
HERE = Path(__file__).resolve().parent
CASES = ("goto_into_try", "goto_into_iterator", "goto_within_try",
         "goto_out_of_iterator", "nested_catch_return")


def driver():
    spec = importlib.util.spec_from_file_location(
        "protected_entry_compile", HERE.parent / "loop_local_diagnostics" / "run.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.HERE = HERE
    module.CASES = CASES
    module.ORIGINAL_CASES = CASES
    return module


if __name__ == "__main__":
    raise SystemExit(driver().main())
