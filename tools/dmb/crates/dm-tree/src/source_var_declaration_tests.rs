use super::*;
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, Resolver};
use std::path::Path;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
#[test]
fn source_formal_metadata_ignores_child_default_overrides() {
    let front=crate::frontend::build(Path::new("source-var.dme"),&Source("/datum/item\n/datum/holder\n    var/datum/item/current\n/datum/holder/child\n    current = null\n"),&Default::default(),1).unwrap();
    let tree = front.snapshot.tree.as_ref();
    let query = Q::SourceVarDeclaration {
        owner: SymbolId::of("/datum/holder/child"),
        name: SymbolId::of("current"),
    };
    let M::Member { owner, data, .. } = Resolver::resolve(tree, query) else {
        panic!("formal source declaration unavailable");
    };
    assert_eq!(owner, SymbolId::of("/datum/holder"));
    assert_eq!(data.declared_type, Some(SymbolId::of("/datum/item")));
    // Effective defaults still keep their ordinary runtime lookup behavior.
    assert!(
        matches!(Resolver::resolve(tree,Q::Var{owner:SymbolId::of("/datum/holder/child"),name:SymbolId::of("current")}),M::Member{owner,..} if owner==SymbolId::of("/datum/holder/child"))
    );
}
#[test]
fn source_missing_is_not_an_intrinsic_absence_claim() {
    let front = crate::frontend::build(
        Path::new("source-var.dme"),
        &Source("/datum/holder\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let tree = front.snapshot.tree.as_ref();
    assert!(!tree.intrinsic_inventory_complete());
    let missing = Q::SourceVarDeclaration {
        owner: SymbolId::of("/datum/holder"),
        name: SymbolId::of("engine_or_source_name"),
    };
    assert_eq!(Resolver::resolve(tree, missing), M::Missing);
    let unknown = Q::SourceVarDeclaration {
        owner: SymbolId::of("/not_captured"),
        name: SymbolId::of("name"),
    };
    assert_eq!(Resolver::resolve(tree, unknown), M::Unsupported(unknown));
}
