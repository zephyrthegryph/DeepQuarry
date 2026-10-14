"""Compiler-only modified initializer recovery observations; no invented golden."""
import importlib.util
from pathlib import Path
HERE=Path(__file__).resolve().parent
CASES=('missing_one','missing_empty','missing_two','missing_known_proc','known_missing_field','missing_one_used','missing_known_proc_used','missing_one_used_lf','missing_known_proc_used_lf','missing_one_lf','undefined_modified_initializer_type')
def driver():
    spec=importlib.util.spec_from_file_location("modified_recovery_driver",HERE.parent/"loop_local_diagnostics"/"run.py")
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.HERE=HERE;module.CASES=CASES;module.ORIGINAL_CASES=CASES
    module.SCOPE="compiler-only modified initializer recovery observation; no assumed legality or golden"
    module.DEFAULT_OUTPUT_ROOT=Path("E:/dq-cache/dmb-modified-initializer-recovery-diagnostics")
    return module
if __name__=="__main__":raise SystemExit(driver().main())
