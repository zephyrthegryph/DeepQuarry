# Local declaration group observations

Five compile-only cases compare comma initialized/uninitialized/typed-list locals
with separate declarations and an indented var block. The typed lowerer currently
consumes one `StatementKind::Var` name/value per statement; this corpus determines
whether comma declarations require a parser-issued expansion. BYOND acceptance
and diagnostics are observed, never assumed. No production changes or runs yet.

`run.py` uses the SAME `loop_local_diagnostics` bounded launcher. Supply explicit
native/template/DM paths and SHA256 flags, `--backend both`, and a fresh
`--output-root E:/dq-cache/dmb-local-declaration-group-diagnostics`.
BYOND-only observation is available with `--backend byond-only`. Serial children
have 30-second watchdogs and the shared overall deadline/4GiB owned Job. No DD.
Exact diagnostic arrays, acceptance and source-rejection class remain separate;
Unsupported/internal rejection is not source-error parity. This compiler corpus
alone cannot prove execution value/evaluation order.
