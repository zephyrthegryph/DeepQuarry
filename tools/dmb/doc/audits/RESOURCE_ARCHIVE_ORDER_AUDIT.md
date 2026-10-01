# Native resource archive order

Named RSC entries retain wire order. Equal content IDs are separate native resource-manager nodes; insertion order and tree rotations can affect the filename returned for a resource. Content-ID and payload equality alone therefore do not establish resource-name parity.

The optional `NativeResourceArchiveOrder` exporter array contains native archive names, including interface and client-script phase tokens. It is present even when empty. Legacy input without the array retains materialization order. The emitter expands an interface token into its imported skin icons followed by the interface, orders named records by the annotation, and derives resource kinds from the first ordered record for each content ID. Resource IDs are not reordered.

## Registration phases established by fresh native probes

Root-global initializer resources are promoted before owner groups. Source-created lexical type subtrees remain grouped across reopens. Known native roots precede deferred custom top-level roots. Within an owner, explicit `/var`, `/proc`, and `/verb` namespaces form separate groups anchored by their first declaration, including resource-free absolute declarations. Relative var declarations nested inside an owner block remain individual declaration phases; they do not anchor the later absolute `/var` namespace. Bare method overrides form individual name groups. Field override statements remain separate phases rather than being pooled with all of the owner's fields.

These distinctions are observable in the portable cases:

- Earlier empty explicit proc, field A, later explicit proc B: B,A.
- Earlier empty bare New, field A, explicit proc B: A,B.
- Explicit proc group B, intervening bare New A, later verb C: B,A,C.
- Earlier empty var declaration, explicit proc group, later declared resource A and proc resource B: A,B.
- Relative nested var without a resource, proc B, later relative resource var A: B,A (plain and typed-list declarations).
- Field override A, proc B, later field override C: A,B,C.
- Child B, unrelated C, parent declaration A, later child D: B,A,D,C.
- Earlier empty parent variable, child resource B, later parent override A: B,A.

Resource tokens in overwritten declarations and dead expressions are retained. Map resources follow code. Included client scripts precede interfaces and code, and skin imports precede the interface itself.

An earlier incremental-archive experiment appeared to place DMS files after resource-only declarations. Recompiling each project without an existing RSC disproved that interpretation: the old archive retained prior entries and appended the added scripts. The exporter contains no conditional DMS phase heuristic. Native snapshots used by the portable tests are regenerated from clean outputs.

## Explicit parent dependencies

An owner whose actual `parent_type` differs from its lexical parent waits until that actual parent has been visited. Deferred owners run in the next traversal pass, not immediately when the parent appears: child B, unrelated C, parent A, unrelated D produces C,A,D,B. An explicit clause equal to the lexical parent retains ordinary hierarchy order.

The dependency also applies to lexical descendants and each namespace/method phase. Child(parent left), grandchild resource B, unrelated C, left resource A yields C,A,B. This prevents descendant resources bypassing a late actual parent such as `/turf/open`.

## Verification scope

Portable probes live in `fixtures/translation/resource_archive_order` and `resource_cross_kind_order`. Their native archives and DMBs were produced by BYOND 516.1687 without running the world. The archive-order test covers 30 manifests in both debug modes (60 complete ordered archive comparisons). The fresh diagnostic matrix contains 132 legal cases; additional legal parent/root boundary probes cover dependency scheduling.

Full-game exact archive order remains a separate integration gate. These finite probes do not establish every possible future language construct, and the full-game result must not be inferred from their success.
