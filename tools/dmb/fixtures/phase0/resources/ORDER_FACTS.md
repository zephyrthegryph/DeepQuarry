# Resource import phase facts needed by the cold frontend

The native import-order collector must consume grammar facts recorded **before**
`normalize::declarations_in_scope` flattens declaration groups. It cannot recover
namespace creation from the resolved final member table: empty namespaces,
resource-free declarations, reopened groups and overwritten declarations matter.

## Minimum reusable source ledger

Record ordered events beside occurrence provenance, independent of arena IDs:

- `EnterType/LeaveType`: authored path, resolved lexical owner, whether the path
  is absolute, lexical ancestor chain and encounter ordinal.
- `CreateNamespace`: exact owner and `var/proc/verb`, absolute versus relative
  declaration form, even if empty or all children have no resources.
- `FieldOccurrence`: exact declared/assigned member occurrence, namespace-event
  identity if present, ordered authored initializer token occurrence ranges.
  Repeated overrides remain events even when superseded.
- `ProcedureOccurrence`: explicit proc/verb namespace event versus bare method
  declaration, exact occurrence ID and lazily captured body source range.
- `ParentAssignment`: authored target and exact resolved actual-parent fact;
  deferred traversal depends on both actual and lexical parent dependencies.
- `NonTextImport`: manifest DMS/DMF/maps occurrence and ordered captured asset
  references. Skin icon references precede the DMF archive record.

These are generic grammar/declaration facts usable by analysis and documentation.
They must retain exact source provenance but must not encode BYOND resource IDs,
archive payloads, or a second mutable copy of the semantic tree.

Resource-reference traversal is a separate captured input per field/body/map:
lexical string interpolation traversal is already shared by
`dm_resources::capture::discover_literals`; switch/pick containers and procedure
body grammar traversal need verification against the native fixture corpus.
Body discovery must remain lazy and bounded rather than re-retaining full ASTs.

## Target collector

A pure BYOND import-phase collector consumes that ledger, the immutable resolved
parent hierarchy, per-occurrence ordered resource references and nontext imports.
It returns a complete alias permutation, validated by
`assets::project_resources`. It must replay passes and namespace/procedure groups
from the corpus rather than treating source encounter order as native order.

Required distinguishing controls are already in
`fixtures/translation/resource_archive_order`: `reparent_next_pass`,
`reparented_descendants`, `first_resource_body`, `procedure_group_first`,
`field_group_first`, `client_procedure_namespaces`, `bare_method_empty_phase`,
`field_override_sequence`, `empty_variable_namespace`, `relative_variable_phase`
and `relative_typed_variable_phase`. The README states the proven ordering for
those cases. Import-phase implementation is incomplete until all controls agree.

For now automatic archive projection is admitted only when runtime content IDs
are unique across aliases. Exact caller-certified permutations support the
ambiguous cases; dictionary sorting and guessed phase grouping are rejected.
This is a temporary admission boundary, not completion of the phase collector.
