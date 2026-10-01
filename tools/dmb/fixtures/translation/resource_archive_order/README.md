# Native resource registration order fixtures

Thirty native compile-only projects cover root-global promotion, reopened groups, explicit and implicit parents, sibling subtrees, native-root boundaries, deferred custom roots, switch/pick AST containers, map resources, and DMS/DMF imports. Assets A/B/C/D deliberately share bytes and a CRC, making alias ordering observable in native resource lookup.

The `.native.bin` and `.native.rsc.bin` snapshots were compiled with BYOND 516.1687 into clean output locations. No world was launched. Existing incremental RSC files must not be reused when regenerating these snapshots: prior entries can survive and newly imported names append to them.

`tests/resource_archive_order.rs` compares complete ordered resource signatures (kind, CRC, filename, declared length, payload), for every project in ordinary and debug translations. The JSONs are actual patched OpenDream exports, including `NativeResourceArchiveOrder`; they are not manually annotated.

The earlier apparent late DMS phase was an incremental archive artifact. Fresh native compilation imports included DMS files before the interface and code; interface-imported skin images precede the interface entry.

The `reparent_next_pass`, `explicit_lexical_parent`, and `reparent_parent_late` cases distinguish explicit actual-parent dependencies from normal lexical hierarchy grouping. Their native archives were compiled fresh; the first case requires C,A,D,B and rejects immediate child unblocking.

`first_resource_body` proves that a parent declared earlier with only nonresource fields does not register its later resource before an intervening child resource. Native order is B,A.

`procedure_group_first` and `field_group_first` distinguish the first procedure-group creation from the first resource-bearing field declaration. An earlier resource-free procedure seeds the procedure group, producing B,A; otherwise field A followed by procedure B produces A,B.

`reparented_procedure_group` requires C,A,B: the explicitly reparented owner’s procedure resources also wait for its actual parent in the next pass.

`reparented_descendants` requires C,A,B: lexical descendants share an explicitly reparented ancestor’s unresolved actual-parent dependency.

`client_procedure_namespaces` requires B,A,C: an earlier explicit `/proc` namespace groups later ordinary procedures ahead of an intervening bare `New` body and a later `/verb` namespace. `bare_method_empty_phase` requires A,B and rejects treating an earlier empty bare method as creation of the explicit `/proc` namespace.

`field_override_sequence` requires A,B,C: repeated field overrides remain distinct phases around an intervening procedure. `empty_variable_namespace` requires A,B: an earlier resource-free `/var` declaration creates the namespace for later declarations, even when an explicit procedure occurs between them.

`relative_variable_phase` and `relative_typed_variable_phase` prove that nested relative var declarations do not seed the shared absolute `/var` namespace. Both native archives order B before A; `empty_variable_namespace` preserves the absolute A-before-B control.
