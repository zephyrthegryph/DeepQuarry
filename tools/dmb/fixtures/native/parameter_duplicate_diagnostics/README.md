# Parameter diagnostic controls

Compiler-only paired probes: duplicate formal parameters, a local declaration
sharing a parameter name, and valid distinct parameters. No runtime is started.
The first two cases intentionally have no assumed acceptance/diagnostic contract:
the pinned BYOND capture establishes it before production changes are proposed.

Run `run.py` with explicit `--native`, `--template`, `--dm` absolute paths and each
matching `--*-sha256`. DreamMaker is restricted to the authenticated 516.1687 SHA.
Use `--output-root E:/dq-cache/dmb-parameter-diagnostics` (the default).

Every compiler child runs sequentially under the same kill-on-close 4GiB Windows
Job. Each child has at most 30 seconds and the entire six-child probe at most 90
seconds. Private fixture copies, outputs, stores, and receipts are on E: only.
The receipt records executable/template/source pins, exit results, source diagnostic
fields, acceptance disagreement, watchdog evidence, and owned-job cleanup. No
native/reference diagnostic is normalized into an expected answer.
