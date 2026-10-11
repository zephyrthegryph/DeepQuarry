use super::*;
use dm_ir::SymbolId;

fn identity(name: &str) -> ProcedureIdentity {
    ProcedureIdentity {
        owner: SymbolId::of("/"),
        name: SymbolId::of(name),
        verb: false,
        occurrence: 0,
    }
}
fn layout(id: ProcedureIdentity) -> Arc<StaticLayout> {
    Arc::new(StaticLayout::capture(id, Arc::from([])).unwrap())
}
#[test]
fn exact_distinct_empty_layouts_share_inventory_but_roster_changes_decline() {
    let a = identity("a");
    let b = identity("b");
    let plans = [
        dm_tree::procedure_statics::capture_declarations(a, &[]).unwrap(),
        dm_tree::procedure_statics::capture_declarations(b, &[]).unwrap(),
    ];
    let plans = [&plans[0], &plans[1]];
    let receipt = InventoryReceipt::capture(vec![(a, layout(a)), (b, layout(b))], &plans).unwrap();
    assert!(Arc::ptr_eq(
        &receipt.inventory,
        &receipt.admit(&[(a, layout(a)), (b, layout(b))]).unwrap()
    ));
    assert!(receipt.admit(&[(b, layout(b)), (a, layout(a))]).is_none());
    assert!(receipt.admit(&[(a, layout(a))]).is_none());
    assert!(InventoryReceipt::capture(vec![(a, layout(a)), (a, layout(a))], &plans).is_none());
}

#[test]
fn changed_static_default_declines_without_reusing_current_origins() {
    let id = identity("defaults");
    let old_syntax = dm_syntax::parse("var/static/cache = 3\n");
    let new_syntax = dm_syntax::parse("var/static/cache = 4\n");
    let old = dm_tree::procedure_statics::capture_declarations(id, &old_syntax.items).unwrap();
    let new = dm_tree::procedure_statics::capture_declarations(id, &new_syntax.items).unwrap();
    assert_eq!(old.declarations.len(), 1);
    let issue = |plan: &StaticPlan| {
        Arc::new(
            StaticLayout::capture(
                id,
                plan.declarations
                    .iter()
                    .cloned()
                    .map(Arc::new)
                    .collect::<Vec<_>>()
                    .into(),
            )
            .unwrap(),
        )
    };
    let receipt = InventoryReceipt::capture(vec![(id, issue(&old))], &[&old]).unwrap();
    assert!(receipt.admit(&[(id, issue(&old))]).is_some());
    assert!(receipt.admit(&[(id, issue(&new))]).is_none());
}
