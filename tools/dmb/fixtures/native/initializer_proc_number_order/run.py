"""Unused early literal control; reuse exact observable-order paired core."""
import importlib.util
from pathlib import Path
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('observable_order_core',HERE.parent/'initializer_observable_order/run.py')
runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)
runner.core.HERE=HERE
if __name__=='__main__':raise SystemExit(runner.core.main())
