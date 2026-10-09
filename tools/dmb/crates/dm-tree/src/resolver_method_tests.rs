use crate::frontend;
use dm_ir::{
    ProcedureIdentity, ResolveQuery as Q, ResolvedMeaning as M, Resolver, SemanticValue, SymbolId,
};
use std::{collections::BTreeMap, path::Path};

struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(concat!(
            "/datum/base/callback()\n    return 0\n",
            "/datum/base/proc/callback()\n    return 1\n",
            "/datum/base/callback()\n    return 2\n",
            "/datum/base/verb/action()\n    return 3\n",
            "/datum/child\n    parent_type = /datum/base\n",
            "/datum/child/callback()\n    return 4\n",
            "/datum/child/action()\n    return 5\n",
            "/datum/grandchild\n    parent_type = /datum/child\n",
        )
        .into())
    }
}

#[test]
fn methods_anchor_to_certified_inherited_formals_while_literals_stay_strict() {
    let frontend = frontend::build(Path::new("project.dme"), &Source, &BTreeMap::new(), 1).unwrap();
    let tree = frontend.snapshot.tree.as_ref();
    for receiver in ["/datum/child", "/datum/grandchild"] {
        for (name, verb) in [("callback", false), ("action", true)] {
            let owner = SymbolId::of(receiver);
            let name = SymbolId::of(name);
            let method = Q::MethodProcedureValue { owner, name, verb };
            assert_eq!(
                Resolver::resolve(tree, method),
                M::Value(SemanticValue::Procedure(ProcedureIdentity {
                    owner: SymbolId::of("/datum/base"),
                    name,
                    verb,
                    // Source certification normalizes the formal to the base of
                    // its owner-local chain, even when an implicit body came first.
                    occurrence: 0,
                }))
            );
            let literal = Q::ProcedureValue {
                owner,
                name,
                verb,
                formal: true,
            };
            assert!(!matches!(Resolver::resolve(tree, literal), M::Value(_)));
            assert_ne!(
                serde_json::to_vec(&method).unwrap(),
                serde_json::to_vec(&literal).unwrap()
            );
        }
    }
}

#[test]
fn missing_method_does_not_fabricate_a_source_identity() {
    let frontend = frontend::build(Path::new("project.dme"), &Source, &BTreeMap::new(), 1).unwrap();
    let query = Q::MethodProcedureValue {
        owner: SymbolId::of("/datum/child"),
        name: SymbolId::of("absent"),
        verb: false,
    };
    assert!(!matches!(
        Resolver::resolve(frontend.snapshot.tree.as_ref(), query),
        M::Value(_)
    ));
    assert_eq!(query.domain(), dm_ir::ReadDomain::Tree);
}
