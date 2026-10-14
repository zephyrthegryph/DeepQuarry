"""Compiler error contract through the existing serial paired compiler driver."""
import importlib.util
from pathlib import Path
HERE = Path(__file__).resolve().parent
CASES = ('undefined_initializer_proc', 'undefined_initializer_multiline', 'undefined_body_proc', 'undefined_body_var', 'undefined_body_type', 'malformed_signature', 'malformed_default', 'undefined_default_proc', 'duplicate_named_args', 'duplicate_local_static', 'duplicate_type_static', 'inherited_variable_redeclaration', 'inherited_static_redeclaration', 'valid_control')
CASES += ('undefined_modified_initializer_type', 'undefined_implied_initializer_type',
          'valid_modified_initializer_type', 'valid_implied_initializer_type')


def driver():
    spec = importlib.util.spec_from_file_location(
        "compile_error_contract_driver", HERE.parent / "loop_local_diagnostics" / "run.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.HERE = HERE
    module.CASES = CASES
    module.ORIGINAL_CASES = CASES
    module.SCOPE = "compiler-only error contract; legality/class/locations/wording observed independently"
    module.DEFAULT_OUTPUT_ROOT = Path("E:/dq-cache/dmb-compile-error-contract")
    return module


if __name__ == "__main__":
    raise SystemExit(driver().main())
