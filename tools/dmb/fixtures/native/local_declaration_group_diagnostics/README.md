# Local declaration group observations

Nine compile-only cases compare comma initialized/uninitialized/typed-list locals
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

Additional unobserved controls cover var/list prefix inheritance, nested list groups with comma leaves and typed Copy receivers, dependent initializers using a side-effecting counter, and repeated local names within one grouped comma leaf. Compiler acceptance alone does not authenticate execution order; the side-effect case is ready for a separate runtime capture after compiler results. No acceptance/value/error golden is assumed.
