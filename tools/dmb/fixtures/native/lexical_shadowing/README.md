# Lexical shadowing candidates

These three compile-only cases distinguish an inner declaration that shadows an
outer local, reuse in independent sibling blocks, and assignment to the outer
local. Their legality and native diagnostic parity are not asserted until the
pinned paired capture is run. No DreamDaemon or runtime result is issued.

Run `tools/dmb/phase0/capture_lexical_shadowing.py` with explicit `--byond`,
`--compiler`, `--compiler-sha256`, `--engine-template`,
`--engine-template-sha256`, and a fresh `--output` beneath `E:/dq-cache`.
The native executable SHA comes from its actual frozen build receipt; the
template SHA must match its actual bytes. The BYOND executable is independently
pinned to 516.1687 and its SHA/version are checked before and after capture.

Each compiler receives separately owned copies with identical source and manifest
bytes. Native invokes compile directly with `--no-daemon --no-cache --workers 1`,
the explicit template and bootstrap catalog; no wrapper can fall back to BYOND.
The Windows owned Job contains each suspended child before it is resumed, enforces
a 30-second child deadline, and is closed/reaped on every outcome. The capture
deadline is 210 seconds; logs and receipts are retained on failure.
