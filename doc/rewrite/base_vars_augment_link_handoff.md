# Item-to-organ return relation proposal

One base-var row retires into a real sparse borrowed relation. Source-only draft, no generation/lint/build/tests. Wire dq_base_vars_augment_link_tests.dm and run its root and borrowed_replacement leaves plus existing dq_inventory_multiple_augment_setup.

The old undeclared rel_set is learned as implicit RELS_PLAIN with CLEAR policy by own_entry_of_kind (engine/refs/table.dm). It never owns the organ or item. New sparse pair keeps default CLEAR on both endpoint deletions, default REPLACE, one organ per item and many items per organ. There are no hooks, contributions or ownership transfer. Real integrated tool ownership remains on the existing integrated_tools/integrated_object declarations.

The organ endpoint deliberately permits /obj/item/organ, matching equip_augment_item's existing cling_to_organ parameter and item_my_augment's return contract; it does not introduce a narrower runtime admission guard just because the old field had an augment type hint. Actual production callers pass augments. All writes use existing link_set_one (not an invented link_set API); existing global view isolates reads and now uses link_get. No base field or shadow state remains.

New tests construct actual rotary implants and tools, deploy through the real human equip_augment_item transaction, drop through real inventory removal, and verify exact return, ownership, replacement and reciprocal endpoint cleanup. Independent external tool lifetime is checked with the tool physically outside the deleted organ so ordinary contents teardown cannot obscure borrowed-link semantics.
