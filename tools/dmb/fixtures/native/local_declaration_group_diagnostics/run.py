"""Local declaration group observations through the existing compiler-only launcher."""
import importlib.util
from pathlib import Path
HERE = Path(__file__).resolve().parent
CASES = ('comma_initialized', 'comma_uninitialized', 'comma_typed_list', 'separate_control', 'group_block_control')


def driver():
    spec = importlib.util.spec_from_file_location(
        "local_group_compile", HERE.parent / "loop_local_diagnostics" / "run.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.HERE = HERE
    module.CASES = CASES
    module.ORIGINAL_CASES = CASES
    return module


if __name__ == "__main__":
    raise SystemExit(driver().main())
