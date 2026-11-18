# Native utility parity

The native Analyze and Checker routes use the retained native compiler frontend.
Parity is an explicit comparison utility, not a production parser fallback.
It requires `--legacy-oracle ABSOLUTE_EXE` and
`--legacy-oracle-sha256 LOWERCASE_SHA256`; it never builds a reference or
selects one from a default location. Missing historical Python lint scripts
are not reported as a passing comparison.

The reference image must be an independent frozen legacy Analyze executable.
Its open-file identity, exact bytes/version, legacy marker and absence of the
native client marker are checked before and after each bounded subprocess.
The ordinary native request still uses the existing compiler daemon and query
graph; no reference parser is linked into the production frontend.

With the qualified production cutover enabled, `analyze parity NAME...` compares default and raw reports and exit statuses,
fixture raw findings and normalized expected bytes, baseline update and seed
bytes, and the real registered selftest callbacks. `--fixtures-only` selects
only fixture cases. Fixture-directory presence and absence are recorded inputs,
so adding a previously absent fixture invalidates the completed inventory.

The two fixture configuration rules remain distinct. `sem fixture NAME` always
uses the repository configuration. Parity uses a fixture's own configuration
when present, otherwise the repository configuration. Both choices and the
presence observation are part of the actual native input closure. The frozen
reference runs on an owned exact-byte copy with the selected effective config
mapped into its repository-config position; it never rewrites real sources.

Native fixture raw and normalized outputs come from the same retained selected
producer. Equality is checked before any `--bless` write. A difference retains
its real producer proof, reports failure, and leaves the authored expected file
untouched. A successful write uses the existing fixed-target writer and actual
post-write preparation, not a hand-written file replacement.

Baseline comparisons preview the ordinary native planner's exact bytes,
including legitimate no-op targets. The reference update/seed runs only in an
owned cache sandbox whose fixed outputs come from the real planner's target
proofs. Every oracle attempt enrolls its actual outputs before identity-checked
cleanup. The project is never temporarily rewritten and blindly restored.

The utility request and terminal require schema `native-codemod-fixture-v2`, with no compatibility default. Missing/V1 request versions reject before any writer. The explicit client identifies itself as `native-analyze-client-v2`; default wrappers reject stale cached or no-build V1 images before invoking an operation. Terminal V2 keeps the existing 1024-byte
header cap. It carries a canonical streamed fingerprint of the held request,
rather than repeating long paths or selector vectors. Parity case observations
are counts plus seals over canonical actual-case frames. These are transport
DATA, not source authority: the producer retains and checks every actual input
ledger and the original binding through publication. Clients recompute the
request fingerprint and reject mismatched roots, flags, reference versions or
schemas. No truncation, implicit fallback or larger protocol budget is used.

Before the production default is enabled, the explicit utility is available as
`analyze-native parity NAME... --native-dmbc ABSOLUTE_COMPILER` with the same
required reference flags. Source implementation, syntax parsing and a completed
comparison suboperation do not establish whole-project or production-default
qualification. That qualification must use the actual combined executable.

Reference process metadata uses named per-field standard allocator frontiers
under the same source work, retained through cleanup. Hash scan buffers, reader
stacks, and argv encoding/quoting frontiers are accounted separately. Opaque
standard-library/OS process internals remain under the existing owned Job,
process-count, deadline and bounded-output contracts; they are not represented
as an exact source-heap census or a new independent process budget.
