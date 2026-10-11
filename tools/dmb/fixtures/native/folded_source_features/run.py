import importlib.util
from pathlib import Path
HERE = Path(__file__).resolve().parent
CASES = ('global_cpu', 'global_graphics', 'constant_cpu', 'constant_graphics', 'skipped_cpu', 'skipped_graphics')
def main():
    path = HERE.parent / 'loop_local_diagnostics' / 'run.py'
    spec = importlib.util.spec_from_file_location('folded_feature_probe', path)
    driver = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(driver)
    driver.HERE = HERE
    driver.CASES = driver.ORIGINAL_CASES = CASES
    driver.SCOPE = 'compile-only folded nameof source-feature observations; no runtime'
    return driver.main()
if __name__ == '__main__':
    raise SystemExit(main())
