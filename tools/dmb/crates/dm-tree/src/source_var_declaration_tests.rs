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

#[test]
fn admitted_parent_query_keeps_certification_scalar_storage_and_first_poll_error() {
    use std::io;
    struct Work { polls: usize, fail_at: Option<usize>, reserves: usize, allow_storage: bool, deny_storage: bool }
    impl dm_ir::CanonicalWork for Work {
        fn poll(&mut self) -> io::Result<()> {
            self.polls += 1;
            if self.fail_at == Some(self.polls) { return Err(io::Error::from_raw_os_error(1450)); }
            Ok(())
        }
        fn reserve(&mut self, _: usize) -> io::Result<()> {
            assert!(self.allow_storage, "the scalar Parent query must not allocate canonical metadata");
            self.reserves += 1;
            if self.deny_storage { return Err(io::ErrorKind::OutOfMemory.into()); }
            Ok(())
        }
    }
    let work = || Work { polls: 0, fail_at: None, reserves: 0, allow_storage: false, deny_storage: false };
    let ast = dm_syntax::parse("/datum/holder\n/datum/holder/child\n");
    let source = crate::from_ast(&ast, SymbolTable::default(), dm_ir::FileId(0), 0, 0).unwrap();
    let base = crate::build(source.symbols, &source.skeletons).unwrap();
    let hierarchy = EngineHierarchy {
        schema: 73,
        parents: base.types().iter().map(|node| (node.path, node.parent.map(|id| base.types()[id.index()].path))).collect(),
    };
    let certified = base.clone().with_engine_intrinsics(hierarchy, vec![]).unwrap();
    assert!(certified.intrinsic_hierarchy_certified());
    assert!(!certified.intrinsic_inventory_complete());
    let child = Q::Parent(SymbolId::of("/datum/holder/child"));
    let root = Q::Parent(SymbolId::of("/"));
    let unknown = Q::Parent(SymbolId::of("/not_captured"));
    assert_eq!(Resolver::resolve(&certified, child), M::Symbol(SymbolId::of("/datum/holder")));
    assert_eq!(Resolver::resolve(&certified, root), M::Missing);
    assert_eq!(Resolver::resolve(&certified, unknown), M::Unsupported(unknown));
    assert_eq!(Resolver::resolve(&base, child), M::Unsupported(child));
    for (tree, query) in [(&certified, child), (&certified, root), (&certified, unknown), (&base, child)] {
        let mut w = work();
        let actual = tree.resolve_with_canonical_work(query, &mut w).unwrap();
        assert_eq!(actual, Resolver::resolve(tree, query));
        assert_eq!(w.polls, 1);
        assert_eq!(w.reserves, 0);
        w.allow_storage = true;
        assert_eq!(actual.canonical_bytes_using(&mut w).unwrap(), actual.canonical_bytes());
        assert!(w.reserves > 0, "canonical output bytes still use the ordinary admitted serializer");
    }
    let mut failed = work(); failed.fail_at = Some(1);
    assert_eq!(certified.resolve_with_canonical_work(child, &mut failed).unwrap_err().raw_os_error(), Some(1450));
    assert_eq!(failed.polls, 1); assert_eq!(failed.reserves, 0);
    let answer = certified.resolve_with_canonical_work(child, &mut work()).unwrap();
    let mut denied = work(); denied.allow_storage = true; denied.deny_storage = true;
    assert_eq!(answer.canonical_bytes_using(&mut denied).unwrap_err().kind(), io::ErrorKind::OutOfMemory);
    let outside = Q::Var { owner: SymbolId::of("/datum/holder"), name: SymbolId::of("field") };
    assert_eq!(certified.resolve_with_canonical_work(outside, &mut work()).unwrap_err().kind(), io::ErrorKind::Unsupported, "other unissued structural queries remain fail closed");
}
