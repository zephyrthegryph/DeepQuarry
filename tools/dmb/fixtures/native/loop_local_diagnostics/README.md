# Loop local declaration diagnostics

Compile-only observation corpus; never runs DreamDaemon. No BYOND outcomes are
assumed before pinned capture. Includes enclosing each/pair/range declarations,
sibling loop scopes, and assignments to existing bindings without `var`.
Pair key/value declaration behavior is independently observed.

Uses the existing native-iteration owned-child launcher and Job cleanup. Each
compiler has a 30-second deadline, total corpus 300 seconds, logs capped at
1 MiB. Supply explicit native/template/DreamMaker paths and SHA256 pins:

```text
python tools/dmb/fixtures/native/loop_local_diagnostics/run.py --native NATIVE --native-sha256 SHA --template TEMPLATE --template-sha256 SHA --dm DREAMMAKER --dm-sha256 SHA --output-root E:/dq-cache/dmb-loop-local-diagnostics
```

Receipts retain both compiler diagnostics, source hashes, acceptance and source
error classification comparisons. Differing diagnostics are evidence, not
normalized away. A paired run exits successfully only when acceptance, source
error classification and exact diagnostics all agree. A complete receipt can
therefore accompany a nonzero exit when a diagnostic gap remains. No runtime
or full source-closure claim is made.

Additional bodyless-loop controls are opt-in through `--cases`. Pinned BYOND
516.1687 observations distinguish an explicit `{}` or `;` (accepted), a following
statement (accepted), and exhaustion or a following procedure declaration
(`: invalid expression`). An included file ending does not alone establish a
missing body: the parent can provide the next statement. The error location is
the current lexer cursor, including the parent manifest after an include returns.
These captures establish compile diagnostics only; they do not establish which
body an accepted following statement executes in.

`--backend byond-only` exits successfully when capture completes. It does not
certify native parity. The original default roster remains separate from these
additional controls so existing captures remain reproducible.
