"""Pinned compile-only Input forms; operands require subsequent decoding."""
from pathlib import Path
import capture_initializer_receivers as capture

capture.SCHEMA = "dm-input-shapes-v1"
capture.CASES = ("input_shapes",)
capture.FIXTURES = Path(__file__).resolve().parent.parent / "fixtures/translation/input_remaining_shapes"

if __name__ == "__main__":
    raise SystemExit(capture.main())
