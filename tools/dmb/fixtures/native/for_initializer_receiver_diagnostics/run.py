"""For initializer receiver observations through the existing compiler-only launcher."""
import importlib.util
from pathlib import Path
HERE = Path(__file__).resolve().parent
CASES = ('for_typed_list_copy', 'for_typed_list_add', 'for_typed_source', 'for_untyped_dot', 'ordinary_typed_control', 'for_receiver_after_loop', 'for_outer_typed_shadow', 'for_nested_outer_receiver', 'for_typed_source_explicit_new')


def driver():
    spec = importlib.util.spec_from_file_location(
        "for_initializer_compile", HERE.parent / "loop_local_diagnostics" / "run.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.HERE = HERE
    module.CASES = CASES
    module.ORIGINAL_CASES = CASES
    return module


if __name__ == "__main__":
    raise SystemExit(driver().main())
