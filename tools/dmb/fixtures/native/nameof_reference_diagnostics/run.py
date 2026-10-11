import importlib.util
from pathlib import Path
HERE = Path(__file__).resolve().parent
CASES = ('absent_type', 'absent_proc', 'absent_identifier', 'present_local')
def main():
    path = HERE.parent / 'loop_local_diagnostics' / 'run.py'
    spec = importlib.util.spec_from_file_location('nameof_reference_probe', path)
    driver = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(driver)
    driver.HERE = HERE
    driver.CASES = driver.ORIGINAL_CASES = CASES
    driver.SCOPE = 'compile-only nameof reference legality observations; no runtime'
    return driver.main()
if __name__ == '__main__':
    raise SystemExit(main())
