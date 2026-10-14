# Parameter diagnostic controls

Seven compiler-only paired controls cover duplicate formal parameters, ordinary,
nested and for-loop locals sharing a parameter name, valid distinct parameters,
and typed duplicate formals in both orders. The authenticated BYOND capture
establishes the rules; no runtime is started.

Run `run.py` with explicit `--native`, `--template`, `--dm` absolute paths and each
matching `--*-sha256`. DreamMaker is restricted to the authenticated 516.1687 SHA.
Use `--output-root E:/dq-cache/dmb-parameter-diagnostics` (the default).

Every compiler child runs sequentially under the same kill-on-close 4GiB Windows
Job. Each child has at most 30 seconds and the entire fourteen-child probe at most 90
seconds. Private fixture copies, outputs, stores, and receipts are on E: only.
The receipt records executable/template/source pins, exit results, source diagnostic
fields, acceptance disagreement, watchdog evidence, and owned-job cleanup. No
native/reference diagnostic is normalized into an expected answer.

## Pinned receiver namespace authority

`native_receiver_namespace.json` is extracted from the local reference shipped with
pinned DreamMaker 516.1687. Both reference files and compiler are SHA256 pinned.
`phase0/extract_native_receiver_namespace.py` reproduces this read-only extraction.
The documented /datum procedure namespace contains New, Del, Topic, Read and Write;
all five exactly match the conservative native-bootstrap catalog receiver roster.
This reviewed namespace closes arbitrary absent method names on /datum and purely
source-defined descendants whose current inheritance stays within this closure.
Source method/verb positives take precedence. Other native namespaces, global calls,
unknown current owners, cyclic ancestry and known native names lacking ABI/code
proof remain unsupported. The JSON records documentation/catalog differences for
other native types; these differences do not grant closed coverage.

The seven-case paired compiler capture remains independent evidence for parameter
rules. Its formerly_missing spelling does not appear in the namespace authority.
