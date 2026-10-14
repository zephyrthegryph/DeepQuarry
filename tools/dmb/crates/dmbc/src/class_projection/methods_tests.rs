use super::*;
use std::path::Path;
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(include_str!(
            "../../../../fixtures/native_compiler/procedure_membership_interleaved/probe.dm"
        )
        .to_string())
    }
}
struct NoFields;
impl CapturedFieldEvaluator for NoFields {
    fn evaluate(&self, _: SymbolId, _: &SymbolicExpression) -> Result<SemanticValue, String> {
        Err("fixture has no field initializers".into())
    }
}
fn projected() -> (ClassProjection, dm_ir::SymbolTable) {
    let frontend =
        dm_tree::frontend::build(Path::new("fixture.dme"), &Source, &BTreeMap::new(), 1).unwrap();
    let projection = project(&frontend.snapshot, &frontend.emission_order, &NoFields).unwrap();
    (projection, frontend.snapshot.tree.symbols().clone())
}
fn tables(
    projection: &ClassProjection,
    symbols: &dm_ir::SymbolTable,
    ids: [u32; 5],
) -> dm_link::LinkTables {
    let owner = SymbolId::of("/datum/probe");
    let mut inventory = dm_link::LinkInventory::default();
    let mut spellings = HashSet::new();
    for (key, index) in projection.procedure_membership.iter().rev().zip(ids) {
        let Key::Proc { name, .. } = *key else {
            panic!("procedure fixture")
        };
        for symbol in [owner, name] {
            if spellings.insert(symbol) {
                inventory
                    .spellings
                    .push((symbol, Arc::from(symbols.text(symbol).unwrap().as_bytes())));
            }
        }
        inventory.entries.push(dm_link::Entry {
            key: *key,
            content: Vec::<u8>::new().into(),
        });
        inventory.fixed.push((*key, index));
    }
    dm_link::LinkTables::build(inventory).unwrap()
}
#[test]
fn interleaved_membership_matches_authenticated_byond_roster_without_grouping_chains() {
    let (projection, symbols) = projected();
    let tables = tables(&projection, &symbols, [0, 1, 2, 3, 4]);
    let lists = procedure_membership(&projection, &tables).unwrap();
    let owner = SymbolId::of("/datum/probe");
    let expected = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/native_compiler/procedure_membership_interleaved/probe.native.bin"
    ))
    .unwrap();
    let class = expected
        .classes
        .iter()
        .find(|class| expected.string(class.path_string_id()) == Some(b"/datum/probe"))
        .unwrap();
    assert_eq!(
        lists[&(owner, false)],
        expected.lists[class.lists_and_procs[1] as usize]
    );
    assert_eq!(lists[&(owner, false)], [4, 3, 2, 1, 0]);
    let names: Vec<_> = projection
        .procedure_membership
        .iter()
        .map(|key| match key {
            Key::Proc { name, .. } => symbols.text(*name).unwrap(),
            _ => panic!(),
        })
        .collect();
    assert_eq!(names, ["beta", "alpha", "gamma", "beta", "alpha"]);
    let alpha = projection
        .chains
        .iter()
        .find(|chain| chain.name == SymbolId::of("alpha"))
        .unwrap();
    assert_eq!(alpha.entries.len(), 2);
    assert!(!projection.procedure_declarations[&alpha.entries[0]]);
    assert!(projection.procedure_declarations[&alpha.entries[1]]);
}
#[test]
fn issued_membership_is_independent_of_nonencounter_linker_indexes() {
    let (projection, symbols) = projected();
    let tables = tables(&projection, &symbols, [40, 7, 33, 11, 3]);
    assert_eq!(
        procedure_membership(&projection, &tables).unwrap()[&(SymbolId::of("/datum/probe"), false)],
        [3, 11, 33, 7, 40]
    );
}
