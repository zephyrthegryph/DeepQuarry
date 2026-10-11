"""Callable scenarios through the existing retained/fresh/BYOND runtime contract."""
import importlib.util
from pathlib import Path
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("callable_incremental_contract", HERE.parent / "incremental_runtime_contract/run.py")
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)
LABELS = ("copy_length", "copy_value", "original_value", "safe_known", "safe_null", "colon_verb", "typed_verb", "self_verb", "catch_number", "catch_exception", "explicit_array_methods", "implicit_array_methods")
if __name__ == "__main__":
    raise SystemExit(contract.main(fixture_directory=HERE, labels=LABELS, prefix="DQ_CALL", scope="callable execution across unchanged, body and structural retained/fresh revisions"))
