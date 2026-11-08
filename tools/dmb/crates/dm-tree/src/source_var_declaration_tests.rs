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
    assert_eq!(data.declared_type(), Some(SymbolId::of("/datum/item")));
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

#[test]fn admitted_native_structural_answers_match_actual_resolver_and_keep_serializer_io_failures(){
 struct Work{fail:bool,bytes:usize}impl dm_ir::CanonicalWork for Work{fn poll(&mut self)->std::io::Result<()>{Ok(())}fn reserve(&mut self,bytes:usize)->std::io::Result<()>{if self.fail{return Err(std::io::Error::from_raw_os_error(1450))}self.bytes+=bytes;Ok(())}}
 let front=crate::frontend::build(Path::new("source-var.dme"),&Source("/datum/holder\n    var/field = 1\n    proc/probe(value=2)\n        return value\n/datum/holder/child\n    probe(value=3)\n        return value\n"),&Default::default(),1).unwrap();let tree=front.snapshot.tree.as_ref();
 let queries=[Q::SourceVarDeclaration{owner:SymbolId::of("/datum/holder/child"),name:SymbolId::of("field")},Q::SourceDeclarationChain{owner:SymbolId::of("/datum/holder/child"),name:SymbolId::of("probe"),verb:false},Q::Ancestry(SymbolId::of("/datum/holder/child")),Q::Type(SymbolId::of("/datum/missing"))];
 for query in queries{let mut work=Work{fail:false,bytes:0};let actual=tree.resolve_with_canonical_work(query,&mut work).unwrap();assert_eq!(actual,Resolver::resolve(tree,query));let bytes=actual.canonical_bytes_using(&mut work).unwrap();assert_eq!(bytes,actual.canonical_bytes());}
 let query=queries[0];let actual=tree.resolve_with_canonical_work(query,&mut Work{fail:true,bytes:0}).unwrap_err();assert_eq!(actual.raw_os_error(),Some(1450));assert!(matches!(tree.resolve_with_canonical_work(query,&mut Work{fail:false,bytes:0}).unwrap(),M::Member{..}));
 let outside=Q::Var{owner:SymbolId::of("/datum/holder"),name:SymbolId::of("field")};assert_eq!(tree.resolve_with_canonical_work(outside,&mut Work{fail:false,bytes:0}).unwrap_err().kind(),std::io::ErrorKind::Unsupported,"unissued admission coverage is not an unfunded native fallback");assert!(matches!(Resolver::resolve(tree,outside),M::Member{..}),"ordinary native resolver acceptance is untouched");
}
