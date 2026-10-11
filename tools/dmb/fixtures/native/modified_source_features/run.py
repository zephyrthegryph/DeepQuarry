import importlib.util
from pathlib import Path
HERE = Path(__file__).resolve().parent
CASES = ('modified_cpu', 'modified_graphics', 'modified_skipped_cpu', 'parameter_cpu')
def main():
    path = HERE.parent / 'loop_local_diagnostics' / 'run.py'
    spec = importlib.util.spec_from_file_location('modified_feature_probe', path)
    driver = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(driver)
    driver.HERE = HERE
    driver.CASES = driver.ORIGINAL_CASES = CASES
    driver.SCOPE = 'compile-only modified/default nameof source-feature observations; no runtime'
    return driver.main()
if __name__ == '__main__':
    raise SystemExit(main())
